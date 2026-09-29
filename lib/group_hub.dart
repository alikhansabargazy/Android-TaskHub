import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

const String taskHubApiUrl = String.fromEnvironment(
  'TASKHUB_API_URL', defaultValue: 'http://10.0.2.2:8000',
);

class _ApiError implements Exception {
  const _ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _GroupApi {
  static const _storage = FlutterSecureStorage();
  String? token;

  Future<void> restore() async {
    token = await _storage.read(key: 'taskhub_token');
  }

  Future<Map<String, dynamic>> call(String method, String path, [Map<String, dynamic>? data]) async {
    final request = http.Request(method, Uri.parse('$taskHubApiUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (data != null) request.body = jsonEncode(data);
    final streamed = await request.send().timeout(const Duration(seconds: 12));
    final body = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(body.body) as Map<String, dynamic>;
    if (body.statusCode >= 400) {
      if (body.statusCode == 401) {
        token = null;
        await _storage.delete(key: 'taskhub_token');
      }
      throw _ApiError('${decoded['error'] ?? 'Request failed'} (${body.statusCode})');
    }
    return decoded;
  }

  Future<void> authenticate(String email, String password, bool register) async {
    final result = await call('POST', '/api/v1/auth/${register ? 'register' : 'login'}',
        {'email': email, 'password': password});
    token = result['token'] as String;
    await _storage.write(key: 'taskhub_token', value: token);
  }

  Future<void> logout() async {
    try {
      await call('POST', '/api/v1/auth/logout');
    } finally {
      token = null;
      await _storage.delete(key: 'taskhub_token');
    }
  }
}

class GroupHubPage extends StatefulWidget {
  const GroupHubPage({required this.onDeadlinesChanged, super.key});
  final ValueChanged<List<DeadlineItem>> onDeadlinesChanged;

  @override
  State<GroupHubPage> createState() => _GroupHubPageState();
}

class _GroupHubPageState extends State<GroupHubPage> {
  final _api = _GroupApi();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _register = false;
  String? _error;
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _state;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    await _perform(() async {
      await _api.restore();
      if (_api.token != null) await _load();
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (error) {
      if (_api.token == null) widget.onDeadlinesChanged([]);
      if (mounted) setState(() {
        _error = error.toString();
        if (_api.token == null) {
          _groups = [];
          _selected = null;
          _state = null;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final result = await _api.call('GET', '/api/v1/groups');
    final groups = (result['groups'] as List).cast<Map<String, dynamic>>();
    final selectedId = _selected?['id'];
    final selected = groups.where((g) => g['id'] == selectedId).firstOrNull;
    final feed = await _api.call('GET', '/api/v1/feed');
    final deadlines = <DeadlineItem>[];
    final completions = <String, bool>{};
    for (final group in (feed['groups'] as List).cast<Map<String, dynamic>>()) {
      for (final raw in (group['deadlines'] as List).cast<Map<String, dynamic>>()) {
        final item = DeadlineItem.fromJson(raw);
        if (group['id'] == selected?['id']) {
          completions[item.id] = item.completed;
        }
        deadlines.add(DeadlineItem(
          id: 'group:${group['id']}:${item.id}', title: item.title,
          subject: item.subject, due: item.due, completed: item.completed,
          colorValue: item.colorValue, iconCodePoint: item.iconCodePoint,
        ));
      }
    }
    widget.onDeadlinesChanged(deadlines);
    if (mounted) setState(() {
      _groups = groups;
      _selected = selected;
      _completion..clear()..addAll(completions);
    });
    if (selected != null) await _loadSelected();
  }

  Future<void> _loadSelected() async {
    final id = _selected?['id'];
    if (id == null) return;
    final state = await _api.call('GET', '/api/v1/groups/$id/state');
    if (mounted && _selected?['id'] == id) setState(() => _state = state);
  }

  Future<void> _editGroup({Lesson? lesson, DeadlineItem? deadline}) async {
    final id = _selected?['id'];
    if (id == null || _state == null) return;
    final lessons = (List<dynamic>.from(_state!['lessons'] as List));
    final deadlines = (List<dynamic>.from(_state!['deadlines'] as List));
    if (lesson != null) lessons.add(lesson.toJson());
    if (deadline != null) deadlines.add(deadline.toJson());
    await _api.call('PUT', '/api/v1/groups/$id/state', {
      'revision': _state!['revision'], 'lessons': lessons, 'deadlines': deadlines,
    });
    await _loadSelected();
    await _load();
  }

  Future<void> _addLesson() async {
    final lesson = await showModalBottomSheet<Lesson>(
      context: context, isScrollControlled: true,
      builder: (_) => const LessonEditor(initialDay: 'Monday'),
    );
    if (lesson != null) await _perform(() => _editGroup(lesson: lesson));
  }

  Future<void> _addDeadline() async {
    final lessons = (_state?['lessons'] as List? ?? [])
        .map((e) => Lesson.fromJson(e as Map<String, dynamic>)).toList();
    final item = await showModalBottomSheet<DeadlineItem>(
      context: context, isScrollControlled: true,
      builder: (_) => DeadlineEditor(lessons: lessons),
    );
    if (item != null) await _perform(() => _editGroup(deadline: item));
  }

  Future<void> _removeItem(String key, String itemId) async {
    final state = _state!;
    final lessons = List<dynamic>.from(state['lessons'] as List);
    final deadlines = List<dynamic>.from(state['deadlines'] as List);
    (key == 'lessons' ? lessons : deadlines)
        .removeWhere((item) => item['id'] == itemId);
    await _api.call('PUT', '/api/v1/groups/${_selected!['id']}/state', {
      'revision': state['revision'], 'lessons': lessons, 'deadlines': deadlines,
    });
    await _loadSelected();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final owner = _selected?['role'] == 'owner';
    final lessons = (_state?['lessons'] as List? ?? [])
        .map((e) => Lesson.fromJson(e as Map<String, dynamic>)).toList();
    final deadlines = (_state?['deadlines'] as List? ?? [])
        .map((e) => DeadlineItem.fromJson(e as Map<String, dynamic>)).toList();
    return Column(children: [
      const TaskHubHeader(subtitle: 'Shared class groups'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 40), children: [
        if (_api.token == null) ...[
          const Text('Sign in to share your group schedule'),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _password, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (12+ characters)')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : () => _perform(() async {
            await _api.authenticate(_email.text.trim(), _password.text, _register);
            _password.clear();
            await _load();
          }), child: Text(_register ? 'Create account' : 'Sign in')),
          TextButton(onPressed: () => setState(() => _register = !_register),
              child: Text(_register ? 'Already have an account?' : 'Create an account')),
        ] else ...[
          Row(children: [
            const Expanded(child: Text('Your groups', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            IconButton(onPressed: _busy ? null : () => _perform(_load), icon: const Icon(Icons.refresh)),
            TextButton(onPressed: _busy ? null : () => _perform(() async {
              await _api.logout();
              widget.onDeadlinesChanged([]);
              setState(() { _groups = []; _selected = null; _state = null; });
            }), child: const Text('Log out')),
          ]),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'New group name')),
          FilledButton.tonal(onPressed: _busy ? null : () => _perform(() async {
            final group = await _api.call('POST', '/api/v1/groups', {'name': _name.text.trim()});
            _name.clear();
            setState(() => _selected = group);
            await _load();
          }), child: const Text('Create group')),
          TextField(controller: _code, decoration: const InputDecoration(labelText: 'Invitation code')),
          OutlinedButton(onPressed: _busy ? null : () => _perform(() async {
            final group = await _api.call('POST', '/api/v1/groups/join',
                {'inviteCode': _code.text.trim()});
            _code.clear();
            setState(() => _selected = group);
            await _load();
          }), child: const Text('Join group')),
          const SizedBox(height: 12),
          ..._groups.map((group) => ListTile(
            selected: group['id'] == _selected?['id'],
            title: Text(group['name'] as String),
            subtitle: Text(group['role'] as String),
            onTap: () => _perform(() async {
              setState(() { _selected = group; _state = null; });
              await _load();
            }),
          )),
          if (_selected != null) ...[
            const Divider(),
            Text(_selected!['name'] as String,
                style: Theme.of(context).textTheme.headlineMedium),
            if (owner) SelectableText('Invite code: ${_selected!['inviteCode']}'),
            if (!owner) TextButton(onPressed: _busy ? null : () => _perform(() async {
              await _api.call('POST', '/api/v1/groups/${_selected!['id']}/leave');
              setState(() { _selected = null; _state = null; });
              await _load();
            }), child: const Text('Leave group')),
            if (owner) Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _busy ? null : _addLesson,
                  icon: const Icon(Icons.add), label: const Text('Add class')),
              FilledButton.icon(onPressed: _busy ? null : _addDeadline,
                  icon: const Icon(Icons.flag), label: const Text('Add deadline')),
            ]),
            const SizedBox(height: 16),
            const Text('Schedule', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            if (lessons.isEmpty) const Text('No classes yet'),
            ...lessons.map((item) => ListTile(
              title: Text('${item.day} · ${item.subject}'),
              subtitle: Text('${item.start}–${item.end} · ${item.room}'),
              trailing: owner ? IconButton(icon: const Icon(Icons.delete_outline),
                onPressed: () => _perform(() => _removeItem('lessons', item.id))) : null,
            )),
            const Text('Deadlines', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            if (deadlines.isEmpty) const Text('No deadlines yet'),
            ...deadlines.map((item) => ListTile(
              title: Text(item.title),
              subtitle: Text('${item.subject} · ${formatDeadline(item.due)}'),
              leading: Checkbox(value: (_completion[item.id] ?? false), onChanged: (value) =>
                  _perform(() async {
                    await _api.call('PUT', '/api/v1/groups/${_selected!['id']}/deadlines/${Uri.encodeComponent(item.id)}/completion',
                        {'completed': value ?? false});
                    await _load();
                  })),
              trailing: owner ? IconButton(icon: const Icon(Icons.delete_outline),
                onPressed: () => _perform(() => _removeItem('deadlines', item.id))) : null,
            )),
          ],
        ],
      ])),
    ]);
  }

  final Map<String, bool> _completion = {};
}
