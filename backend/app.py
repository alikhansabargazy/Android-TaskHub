"""TaskHub API. Run with: python -m backend.app"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

DB_PATH = Path(os.environ.get("TASKHUB_DB", "taskhub.sqlite3"))
SESSION_LIFETIME = 30 * 24 * 3600
MAX_BODY = 512 * 1024
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def valid_items(items, kind):
    if not isinstance(items, list) or len(items) > 1000:
        return False
    common = ("id", "subject", "colorValue", "iconCodePoint")
    specific = ("day", "room", "start", "end") if kind == "lessons" else ("title", "due", "completed")
    ids = set()
    for item in items:
        if not isinstance(item, dict) or not all(key in item for key in common + specific):
            return False
        if any(not isinstance(item[key], str) or len(item[key]) > 256 for key in common[:2]):
            return False
        if not item["id"] or item["id"] in ids or not item["subject"]:
            return False
        ids.add(item["id"])
        if any(type(item[key]) is not int for key in ("colorValue", "iconCodePoint")):
            return False
        if any(not isinstance(item[key], str) or len(item[key]) > 256 for key in specific if key != "completed"):
            return False
        if kind == "deadlines" and type(item["completed"]) is not bool:
            return False
    return True


@contextmanager
def database(path: Path = DB_PATH):
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    connection.execute("PRAGMA busy_timeout=10000")
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def initialize(path: Path = DB_PATH):
    with database(path) as db:
        db.execute("PRAGMA journal_mode=WAL")
        db.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                password_hash BLOB NOT NULL,
                salt BLOB NOT NULL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash BLOB PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                expires_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS planner (
                user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                revision INTEGER NOT NULL DEFAULT 0,
                lessons TEXT NOT NULL DEFAULT '[]',
                deadlines TEXT NOT NULL DEFAULT '[]'
            );
        """)


def make_handler(path: Path = DB_PATH):
    allowed_origin = os.environ.get("TASKHUB_CORS_ORIGIN", "")

    class Handler(BaseHTTPRequestHandler):
        server_version = "TaskHubAPI/1"

        def _send(self, status: int, data: dict):
            body = json.dumps(data, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            if allowed_origin and self.headers.get("Origin") == allowed_origin:
                self.send_header("Access-Control-Allow-Origin", allowed_origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
                self.send_header("Access-Control-Allow-Methods", "GET, PUT, POST, OPTIONS")
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            if allowed_origin and self.headers.get("Origin") == allowed_origin:
                self._send(HTTPStatus.NO_CONTENT, {})
            else:
                self._send(HTTPStatus.FORBIDDEN, {"error": "origin_not_allowed"})

        def _body(self):
            if self.headers.get("Content-Type", "").split(";", 1)[0].strip() != "application/json":
                raise ValueError("Content-Type must be application/json")
            try:
                length = int(self.headers.get("Content-Length", "-1"))
            except ValueError as exc:
                raise ValueError("invalid Content-Length") from exc
            if not 0 <= length <= MAX_BODY:
                raise ValueError("body must be at most 512 KiB")
            try:
                result = json.loads(self.rfile.read(length))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError("invalid JSON") from exc
            if not isinstance(result, dict):
                raise ValueError("expected a JSON object")
            return result

        def _user(self, db):
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Bearer "):
                return None
            token = auth[7:]
            if len(token) != 64 or not re.fullmatch(r"[0-9a-f]{64}", token):
                return None
            row = db.execute(
                "SELECT users.id, users.email FROM sessions JOIN users ON users.id=sessions.user_id "
                "WHERE sessions.token_hash=? AND sessions.expires_at>?",
                (hashlib.sha256(token.encode()).digest(), int(time.time())),
            ).fetchone()
            return row

        def _route(self):
            route = urlsplit(self.path).path
            method = self.command
            if (method, route) == ("GET", "/health"):
                return self._send(200, {"status": "ok"})
            if route in ("/api/v1/auth/register", "/api/v1/auth/login") and method == "POST":
                data = self._body()
                email = data.get("email", "")
                password = data.get("password", "")
                if not isinstance(email, str) or not EMAIL_RE.fullmatch(email) or len(email) > 254:
                    return self._send(400, {"error": "invalid_email"})
                if not isinstance(password, str) or not 12 <= len(password) <= 1024:
                    return self._send(400, {"error": "password_length_must_be_12_to_1024"})
                email = email.casefold()
                with database(path) as db:
                    if route.endswith("register"):
                        salt = secrets.token_bytes(16)
                        password_hash = hashlib.scrypt(password.encode(), salt=salt,
                                                       n=2**14, r=8, p=1, dklen=32)
                        try:
                            cursor = db.execute("INSERT INTO users(email,password_hash,salt,created_at) VALUES(?,?,?,?)",
                                                (email, password_hash, salt, int(time.time())))
                        except sqlite3.IntegrityError:
                            return self._send(409, {"error": "email_taken"})
                        user_id = cursor.lastrowid
                        db.execute("INSERT INTO planner(user_id) VALUES(?)", (user_id,))
                    else:
                        row = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
                        # Do the same work for unknown accounts to reduce account probing.
                        salt = row["salt"] if row else bytes(16)
                        candidate = hashlib.scrypt(password.encode(), salt=salt,
                                                   n=2**14, r=8, p=1, dklen=32)
                        if not row or not hmac.compare_digest(candidate, row["password_hash"]):
                            return self._send(401, {"error": "invalid_credentials"})
                        user_id = row["id"]
                    token = secrets.token_hex(32)
                    db.execute("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)",
                               (hashlib.sha256(token.encode()).digest(), user_id,
                                int(time.time()) + SESSION_LIFETIME))
                    return self._send(201 if route.endswith("register") else 200,
                                      {"token": token, "expiresIn": SESSION_LIFETIME,
                                       "user": {"id": user_id, "email": email}})
            if route in ("/api/v1/auth/me", "/api/v1/auth/logout", "/api/v1/state"):
                with database(path) as db:
                    user = self._user(db)
                    if user is None:
                        return self._send(401, {"error": "unauthorized"})
                    if (method, route) == ("GET", "/api/v1/auth/me"):
                        return self._send(200, {"id": user["id"], "email": user["email"]})
                    if (method, route) == ("POST", "/api/v1/auth/logout"):
                        token = self.headers["Authorization"][7:]
                        db.execute("DELETE FROM sessions WHERE token_hash=?",
                                   (hashlib.sha256(token.encode()).digest(),))
                        return self._send(200, {"ok": True})
                    if route == "/api/v1/state" and method == "GET":
                        row = db.execute("SELECT * FROM planner WHERE user_id=?", (user["id"],)).fetchone()
                        return self._send(200, {"revision": row["revision"],
                                                "lessons": json.loads(row["lessons"]),
                                                "deadlines": json.loads(row["deadlines"])})
                    if route == "/api/v1/state" and method == "PUT":
                        data = self._body()
                        if type(data.get("revision")) is not int or data["revision"] < 0:
                            return self._send(400, {"error": "invalid_revision"})
                        for key in ("lessons", "deadlines"):
                            value = data.get(key)
                            if not valid_items(value, key):
                                return self._send(400, {"error": "invalid_" + key})
                        cursor = db.execute(
                            "UPDATE planner SET revision=revision+1, lessons=?, deadlines=? "
                            "WHERE user_id=? AND revision=?",
                            (json.dumps(data["lessons"]), json.dumps(data["deadlines"]),
                             user["id"], data["revision"]),
                        )
                        if cursor.rowcount == 0:
                            return self._send(409, {"error": "revision_conflict"})
                        return self._send(200, {"revision": data["revision"] + 1})
            return self._send(404, {"error": "not_found"})

        def do_GET(self):
            self._handle()

        def do_POST(self):
            self._handle()

        def do_PUT(self):
            self._handle()

        def _handle(self):
            try:
                self._route()
            except ValueError as exc:
                self._send(400, {"error": "bad_request", "message": str(exc)})
            except sqlite3.Error:
                self._send(500, {"error": "database_error"})

    return Handler


def main():
    host = os.environ.get("TASKHUB_HOST", "127.0.0.1")
    port = int(os.environ.get("TASKHUB_PORT", "8000"))
    initialize(DB_PATH)
    server = ThreadingHTTPServer((host, port), make_handler(DB_PATH))
    print(f"TaskHub API listening on http://{host}:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
