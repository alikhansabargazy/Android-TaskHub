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


class GroupTest(unittest.TestCase):
    setUp = ApiTest.setUp
    tearDown = ApiTest.tearDown
    request = ApiTest.request

    def test_group_join_shared_schedule_personal_completion_and_access(self):
        owner = self.request('POST', '/api/v1/auth/register',
                             {'email': 'owner@example.com', 'password': 'owner password 123'})[1]['token']
        member = self.request('POST', '/api/v1/auth/register',
                              {'email': 'member@example.com', 'password': 'member password 123'})[1]['token']
        outsider = self.request('POST', '/api/v1/auth/register',
                                {'email': 'other@example.com', 'password': 'other password 123'})[1]['token']
        created = self.request('POST', '/api/v1/groups', {'name': 'CS-2401'}, owner)
        self.assertEqual(created[0], 201)
        group = created[1]
        route = '/api/v1/groups/' + str(group['id'])
        self.assertEqual(self.request('GET', route + '/state', token=outsider)[0], 404)
        self.assertEqual(self.request('POST', '/api/v1/groups/join',
                                     {'inviteCode': group['inviteCode']}, member)[0], 200)
        lesson = {'id': 'lesson-1', 'day': 'Monday', 'subject': 'Math', 'room': '201',
                  'start': '09:00', 'end': '10:00', 'colorValue': 123, 'iconCodePoint': 456}
        deadline = {'id': 'task-1', 'title': 'Quiz', 'subject': 'Math', 'due': '2026-10-01T12:00:00',
                    'completed': False, 'colorValue': 123, 'iconCodePoint': 456}
        state = {'revision': 0, 'lessons': [lesson], 'deadlines': [deadline]}
        self.assertEqual(self.request('PUT', route + '/state', state, member)[0], 403)
        self.assertEqual(self.request('PUT', route + '/deadlines/task-1/completion',
                                     {'completed': True}, outsider)[0], 404)
        self.assertEqual(self.request('PUT', route + '/state', state, owner)[1]['revision'], 1)
        self.assertEqual(self.request('PUT', route + '/state', state, owner)[0], 409)
        feed = self.request('GET', '/api/v1/feed', token=member)[1]
        self.assertEqual(feed['groups'][0]['lessons'], [lesson])
        self.assertFalse(feed['groups'][0]['deadlines'][0]['completed'])
        self.assertEqual(self.request('PUT', route + '/deadlines/task-1/completion',
                                     {'completed': True}, member)[0], 200)
        self.assertTrue(self.request('GET', '/api/v1/feed', token=member)[1]
                        ['groups'][0]['deadlines'][0]['completed'])
        self.assertFalse(self.request('GET', '/api/v1/feed', token=owner)[1]
                         ['groups'][0]['deadlines'][0]['completed'])
        self.assertEqual(self.request('POST', route + '/leave', token=owner)[0], 403)
        self.assertEqual(self.request('POST', route + '/leave', token=member)[0], 200)
        self.assertEqual(self.request('GET', '/api/v1/feed', token=member)[1]['groups'], [])

    def test_separate_group_timetables(self):
        owner = self.request('POST', '/api/v1/auth/register',
                             {'email': 'owner@example.com', 'password': 'owner password 123'})[1]['token']
        member = self.request('POST', '/api/v1/auth/register',
                              {'email': 'member@example.com', 'password': 'member password 123'})[1]['token']
        first = self.request('POST', '/api/v1/groups', {'name': 'Group A'}, owner)[1]
        second = self.request('POST', '/api/v1/groups', {'name': 'Group B'}, owner)[1]
        for group in (first, second):
            self.assertEqual(self.request('POST', '/api/v1/groups/join',
                                          {'inviteCode': group['inviteCode']}, member)[0], 200)
            lesson = {'id': str(group['id']), 'day': 'Monday', 'subject': group['name'],
                      'room': '1', 'start': '09:00', 'end': '10:00',
                      'colorValue': 123, 'iconCodePoint': 456}
            self.assertEqual(self.request('PUT',
                           f"/api/v1/groups/{group['id']}/state",
                           {'revision': 0, 'lessons': [lesson], 'deadlines': []}, owner)[0], 200)
        groups = self.request('GET', '/api/v1/feed', token=member)[1]['groups']
        self.assertEqual({g['name']: g['lessons'][0]['subject'] for g in groups},
                         {'Group A': 'Group A', 'Group B': 'Group B'})


class WebTest(unittest.TestCase):
    def test_serves_web_assets_and_rejects_missing_files(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / 'index.html').write_text('<!doctype html><title>TaskHub</title>')
            (root / 'main.dart.js').write_text('console.log("app")')
            path = root / 'db.sqlite3'
            initialize(path)
            server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(path, root))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                for route, status, marker in [('/', 200, b'TaskHub'),
                                               ('/main.dart.js', 200, b'console'),
                                               ('/groups/1', 200, b'TaskHub'),
                                               ('/missing.js', 404, b'not_found')]:
                    connection = HTTPConnection('127.0.0.1', server.server_port)
                    connection.request('GET', route)
                    response = connection.getresponse()
                    self.assertEqual(response.status, status)
                    self.assertIn(marker, response.read())
                    connection.close()
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
