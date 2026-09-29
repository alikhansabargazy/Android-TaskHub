# TaskHub API

A dependency-free Python 3.10+ HTTP API for separate TaskHub accounts. It stores
users, hashed passwords, hashed bearer tokens and each user's planner in SQLite.

## Start locally

From the repository root:

```bash
TASKHUB_DB=./data/taskhub.sqlite3 python3 -m backend.app
```

The API listens on `127.0.0.1:8000` by default. Set `TASKHUB_HOST` and
`TASKHUB_PORT` to change that. `GET /health` returns `{"status":"ok"}`.
Run tests with `python3 -m unittest discover -s backend/tests -v`.

For a phone on your LAN, bind to `0.0.0.0` and point the phone at the machine's
LAN address; the Android emulator reaches the host at `10.0.2.2:8000`. A real
public deployment **must** use HTTPS at a reverse proxy. Back up the SQLite
file together with its `-wal` and `-shm` files or use SQLite's backup API.
Set `TASKHUB_CORS_ORIGIN` to the exact origin of a web frontend if needed.

## API

All request bodies use `Content-Type: application/json`; responses are JSON.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Health check |
| POST | `/api/v1/auth/register` | Create account; `email`, `password` (12–1024 characters) |
| POST | `/api/v1/auth/login` | Log in with the same fields |
| GET | `/api/v1/auth/me` | Current account |
| POST | `/api/v1/auth/logout` | Revoke the current token |
| GET | `/api/v1/state` | Get planner and its `revision` |
| PUT | `/api/v1/state` | Replace planner, with the revision from the last GET |

Register/login return `token`, `expiresIn` (seconds), and `user`. Other private
requests require `Authorization: Bearer <token>`. A token expires after 30 days.
Keep it in device secure storage; don't put it in the source code or a URL.

A state GET returns `{"revision":0,"lessons":[],"deadlines":[]}` for a new
account. PUT the same shape with the user's lesson and deadline JSON arrays.
The server validates required fields and limits each array to 1000 objects and
the full request to 512 KiB. A successful PUT returns the incremented revision.
If another device already wrote a new revision, PUT returns HTTP 409
`revision_conflict`; GET the new state and ask the user how to reconcile it.
A 401 means the token is absent, invalid or expired.

The Flutter app currently keeps data in SharedPreferences; it has **not yet
been wired to this API**. Installing and starting the server alone will not
sync data from the app. This API is the backend contract for that client work.
