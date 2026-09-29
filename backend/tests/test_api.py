import json
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path

from backend.app import initialize, make_handler


class ApiTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        path = Path(self.temp.name) / 'db.sqlite3'
        initialize(path)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(path))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, route, payload=None, token=None):
        connection = HTTPConnection('127.0.0.1', self.server.server_port)
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        connection.request(method, route,
                           body=json.dumps(payload).encode() if payload is not None else None,
                           headers=headers)
        response = connection.getresponse()
        result = response.status, json.loads(response.read())
        connection.close()
        return result

    def test_registration_sync_isolation_and_conflict(self):
        a = self.request('POST', '/api/v1/auth/register',
                         {'email': 'A@Example.com', 'password': 'a long password 123'})
        b = self.request('POST', '/api/v1/auth/register',
                         {'email': 'b@example.com', 'password': 'another long password'})
        self.assertEqual(a[0], 201)
        self.assertEqual(self.request('POST', '/api/v1/auth/register',
                                     {'email': 'a@example.com', 'password': 'another long password'})[0], 409)
        token = a[1]['token']
        self.assertEqual(self.request('GET', '/api/v1/state')[0], 401)
        state = {'revision': 0, 'lessons': [{'id': 'one', 'day': 'Monday', 'subject': 'Math', 'room': '201', 'start': '09:00', 'end': '10:00', 'colorValue': 123, 'iconCodePoint': 456}], 'deadlines': []}
        self.assertEqual(self.request('PUT', '/api/v1/state', state, token)[1]['revision'], 1)
        self.assertEqual(self.request('PUT', '/api/v1/state', state, token)[0], 409)
        self.assertEqual(self.request('GET', '/api/v1/state', token=b[1]['token'])[1]['lessons'], [])
        self.assertEqual(self.request('GET', '/api/v1/state', token=token)[1]['lessons'], state['lessons'])
        self.assertEqual(self.request('POST', '/api/v1/auth/logout', token=token)[0], 200)
        self.assertEqual(self.request('GET', '/api/v1/state', token=token)[0], 401)

    def test_validation_and_login(self):
        self.assertEqual(self.request('POST', '/api/v1/auth/register',
                                     {'email': 'invalid', 'password': '123'})[0], 400)
        a = self.request('POST', '/api/v1/auth/register',
                         {'email': 'a@example.com', 'password': 'a long password 123'})
        self.assertEqual(self.request('POST', '/api/v1/auth/login',
                                     {'email': 'a@example.com', 'password': 'wrong password 123'})[0], 401)
        self.assertEqual(self.request('POST', '/api/v1/auth/login',
                                     {'email': 'a@example.com', 'password': 'a long password 123'})[0], 200)
        self.assertEqual(self.request('PUT', '/api/v1/state',
                                     {'revision': True, 'lessons': [], 'deadlines': []}, a[1]['token'])[0], 400)


if __name__ == '__main__':
    unittest.main()
