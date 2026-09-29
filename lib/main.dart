import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deadline_reminders.dart';
import 'group_hub.dart';

const Color kMilk = Color(0xFFF7F4ED);
const Color kCard = Color(0xFFFFFDF8);
const Color kBlue = Color(0xFF3478F6);
const Color kText = Color(0xFF1F2430);
const Color kMuted = Color(0xFF7E8798);

const List<String> kDays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<Color> kSubjectColors = <Color>[
  Color(0xFFFFB45A),
  Color(0xFF6EA8FE),
  Color(0xFF8BD3A8),
  Color(0xFFD99AF7),
  Color(0xFFFF8E8E),
  Color(0xFF6FD0D8),
  Color(0xFFF0D264),
  Color(0xFF9DA7FF),
];

const List<IconData> kSubjectIcons = <IconData>[
  Icons.calculate_rounded,
  Icons.menu_book_rounded,
  Icons.computer_rounded,
  Icons.code_rounded,
  Icons.science_rounded,
  Icons.language_rounded,
  Icons.psychology_rounded,
  Icons.sports_basketball_rounded,
  Icons.business_center_rounded,
  Icons.design_services_rounded,
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaskHubApp());
}

class TaskHubApp extends StatefulWidget {
  const TaskHubApp({super.key});

  @override
  State<TaskHubApp> createState() => _TaskHubAppState();
}

class _TaskHubAppState extends State<TaskHubApp> {
  int _tab = 0;
  bool _loading = true;
  List<Lesson> _lessons = <Lesson>[];
  List<DeadlineItem> _deadlines = <DeadlineItem>[];
  List<DeadlineItem> _groupDeadlines = <DeadlineItem>[];

  Future<void> _syncReminders() async {
    try {
      await DeadlineReminders.sync(<DeadlineItem>[..._deadlines, ..._groupDeadlines]);
    } catch (error) {
      debugPrint('Could not schedule deadline reminders: $error');
    }
  }

  void _setGroupDeadlines(List<DeadlineItem> items) {
    _groupDeadlines = items;
    _syncReminders();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<dynamic> lessonJson =
        jsonDecode(prefs.getString('taskhub_lessons') ?? '[]') as List<dynamic>;
    final List<dynamic> deadlineJson =
        jsonDecode(prefs.getString('taskhub_deadlines') ?? '[]') as List<dynamic>;

    if (!mounted) return;
    setState(() {
      _lessons = lessonJson
          .map((dynamic e) => Lesson.fromJson(e as Map<String, dynamic>))
          .toList();
      _deadlines = deadlineJson
          .map((dynamic e) => DeadlineItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
    await _syncReminders();
  }

  Future<void> _saveLessons() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'taskhub_lessons',
      jsonEncode(_lessons.map((Lesson e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveDeadlines() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'taskhub_deadlines',
      jsonEncode(_deadlines.map((DeadlineItem e) => e.toJson()).toList()),
    );
    await _syncReminders();
  }

  Future<void> _addLesson(Lesson lesson) async {
    setState(() => _lessons = <Lesson>[..._lessons, lesson]);
    await _saveLessons();
  }

  Future<void> _deleteLesson(String id) async {
    setState(() => _lessons = _lessons.where((Lesson e) => e.id != id).toList());
    await _saveLessons();
  }

  Future<void> _clearSchedule() async {
    setState(() => _lessons = <Lesson>[]);
    await _saveLessons();
  }

  Future<void> _addDeadline(DeadlineItem item) async {
    setState(() => _deadlines = <DeadlineItem>[..._deadlines, item]);
    try {
      await DeadlineReminders.requestPermission();
    } catch (error) {
      debugPrint('Could not request notification permission: $error');
    }
    await _saveDeadlines();
  }

  Future<void> _toggleDeadline(String id) async {
    setState(() {
      _deadlines = _deadlines.map((DeadlineItem e) {
        if (e.id != id) return e;
        return e.copyWith(completed: !e.completed);
      }).toList();
    });
    await _saveDeadlines();
  }

  Future<void> _deleteDeadline(String id) async {
    setState(() {
      _deadlines =
          _deadlines.where((DeadlineItem e) => e.id != id).toList();
    });
    await _saveDeadlines();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TaskHub',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kMilk,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBlue,
          brightness: Brightness.light,
          surface: kCard,
        ),
        fontFamily: 'SF Pro Display',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: kText,
            fontWeight: FontWeight.w800,
          ),
          titleLarge: TextStyle(
            color: kText,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: kText),
          bodyMedium: TextStyle(color: kMuted),
        ),
      ),
      home: _loading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : Scaffold(
              body: SafeArea(
                child: IndexedStack(
                  index: _tab,
                  children: <Widget>[
                    SchedulePage(
                      lessons: _lessons,
                      onAddLesson: _addLesson,
                      onDeleteLesson: _deleteLesson,
                      onClearSchedule: _clearSchedule,
                    ),
                    DeadlinesPage(
                      deadlines: _deadlines,
                      lessons: _lessons,
                      onAdd: _addDeadline,
                      onToggle: _toggleDeadline,
                      onDelete: _deleteDeadline,
                    ),
                    const MapPage(),
                    GroupHubPage(onDeadlinesChanged: _setGroupDeadlines),
                  ],
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (int index) {
                  setState(() => _tab = index);
                },
                indicatorColor: const Color(0xFFDCE9FF),
                backgroundColor: kCard,
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: 'Schedule',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.flag_outlined),
                    selectedIcon: Icon(Icons.flag_rounded),
                    label: 'Deadlines',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map_rounded),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.groups_outlined),
                    selectedIcon: Icon(Icons.groups_rounded),
                    label: 'Groups',
                  ),
                ],
              ),
            ),
    );
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    required this.lessons,
    required this.onAddLesson,
    required this.onDeleteLesson,
    required this.onClearSchedule,
    super.key,
  });

  final List<Lesson> lessons;
  final Future<void> Function(Lesson lesson) onAddLesson;
  final Future<void> Function(String id) onDeleteLesson;
  final Future<void> Function() onClearSchedule;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int _selectedDay = DateTime.now().weekday - 1;

  Future<void> _openLessonEditor() async {
    final Lesson? lesson = await showModalBottomSheet<Lesson>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      builder: (BuildContext context) {
        return LessonEditor(
          initialDay: kDays[_selectedDay],
        );
      },
    );

    if (lesson != null) {
      await widget.onAddLesson(lesson);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String day = kDays[_selectedDay];
    final List<Lesson> lessons = widget.lessons
        .where((Lesson e) => e.day == day)
        .toList()
      ..sort((Lesson a, Lesson b) => a.start.compareTo(b.start));

    return Column(
      children: <Widget>[
        const TaskHubHeader(subtitle: 'Your week, your way'),
        SizedBox(
          height: 56,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: kDays.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final bool selected = index == _selectedDay;
              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                label: Text(shortDay(kDays[index])),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : kText,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: kBlue,
                backgroundColor: kCard,
                side: BorderSide(
                  color: selected
                      ? kBlue
                      : const Color(0xFFE7E2D9),
                ),
                onSelected: (_) {
                  setState(() => _selectedDay = index);
                },
              );
            },
          ),
        ),
        Expanded(
          child: lessons.isEmpty
              ? EmptySchedule(
                  day: day,
                  onAdd: _openLessonEditor,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            day,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: 28),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _openLessonEditor,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add class'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...lessons.map(
                      (Lesson lesson) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LessonCard(
                          lesson: lesson,
                          onDelete: () => widget.onDeleteLesson(lesson.id),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _openLessonEditor,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Import / add another class'),
                    ),
                    if (widget.lessons.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () async {
                          final bool? yes = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Clear schedule?'),
                                content: const Text(
                                  'This will remove all classes from TaskHub.',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (yes == true) {
                            await widget.onClearSchedule();
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear schedule'),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class EmptySchedule extends StatelessWidget {
  const EmptySchedule({
    required this.day,
    required this.onAdd,
    super.key,
  });

  final String day;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE8E3DA)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.calendar_view_week_rounded,
                  size: 34,
                  color: kBlue,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No classes on $day',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Build your own schedule and choose a color and icon for every subject.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Import / create schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LessonCard extends StatelessWidget {
  const LessonCard({
    required this.lesson,
    required this.onDelete,
    super.key,
  });

  final Lesson lesson;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(lesson.colorValue);
    final IconData icon = IconData(
      lesson.iconCodePoint,
      fontFamily: 'MaterialIcons',
    );

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAE5DC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x0D000000),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Container(
              width: 7,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(22),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 17, 8, 17),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            lesson.subject,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kText,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: <Widget>[
                              MetaText(
                                icon: Icons.schedule_rounded,
                                text: '${lesson.start} – ${lesson.end}',
                              ),
                              MetaText(
                                icon: Icons.location_on_outlined,
                                text: lesson.room.isEmpty
                                    ? 'No room'
                                    : lesson.room,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: onDelete,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LessonEditor extends StatefulWidget {
  const LessonEditor({
    required this.initialDay,
    super.key,
  });

  final String initialDay;

  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _room = TextEditingController();

  late String _day;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  Color _color = kSubjectColors.first;
  IconData _icon = kSubjectIcons.first;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
  }

  @override
  void dispose() {
    _subject.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  void _save() {
    final String subject = _subject.text.trim();
    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the subject name')),
      );
      return;
    }

    Navigator.pop(
      context,
      Lesson(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        day: _day,
        subject: subject,
        room: _room.text.trim(),
        start: formatTime(_start),
        end: formatTime(_end),
        colorValue: _color.toARGB32(),
        iconCodePoint: _icon.codePoint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + keyboard),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7D2C9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Import / create a class',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kText,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _day,
              decoration: const InputDecoration(
                labelText: 'Day',
                border: OutlineInputBorder(),
              ),
              items: kDays
                  .map(
                    (String day) => DropdownMenuItem<String>(
                      value: day,
                      child: Text(day),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value != null) setState(() => _day = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(
                labelText: 'Subject',
                hintText: 'e.g. Discrete Mathematics',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Room',
                hintText: 'e.g. C1.2.345',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('Start ${formatTime(_start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('End ${formatTime(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Subject color',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kSubjectColors.map((Color color) {
                final bool selected = color.toARGB32() == _color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? kText : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: Colors.white,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Subject icon',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kSubjectIcons.map((IconData icon) {
                final bool selected = icon.codePoint == _icon.codePoint;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _icon = icon),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? _color.withValues(alpha: 0.2)
                          : const Color(0xFFF0EDE6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? _color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: selected ? _color : kMuted,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Save class'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeadlinesPage extends StatelessWidget {
  const DeadlinesPage({
    required this.deadlines,
    required this.lessons,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final List<DeadlineItem> deadlines;
  final List<Lesson> lessons;
  final Future<void> Function(DeadlineItem item) onAdd;
  final Future<void> Function(String id) onToggle;
  final Future<void> Function(String id) onDelete;

  Future<void> _openAdd(BuildContext context) async {
    final DeadlineItem? item = await showModalBottomSheet<DeadlineItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCard,
      builder: (_) => DeadlineEditor(lessons: lessons),
    );

    if (item != null) {
      await onAdd(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DeadlineItem> sorted = <DeadlineItem>[...deadlines]
      ..sort((DeadlineItem a, DeadlineItem b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return a.due.compareTo(b.due);
      });

    return Column(
      children: <Widget>[
        const TaskHubHeader(subtitle: 'Keep deadlines under control'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Deadlines',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 28),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openAdd(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Container(
                      width: 520,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFE8E3DA),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.flag_rounded,
                            size: 52,
                            color: kBlue,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No deadlines yet',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add tasks manually and TaskHub will keep them sorted by date.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => _openAdd(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add deadline'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final DeadlineItem item = sorted[index];
                    return DeadlineCard(
                      item: item,
                      onToggle: () => onToggle(item.id),
                      onDelete: () => onDelete(item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class DeadlineCard extends StatelessWidget {
  const DeadlineCard({
    required this.item,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final DeadlineItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(item.colorValue);

    return AnimatedOpacity(
      opacity: item.completed ? 0.55 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEAE5DC)),
        ),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: item.completed,
              onChanged: (_) => onToggle(),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.17),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                IconData(
                  item.iconCodePoint,
                  fontFamily: 'MaterialIcons',
                ),
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kText,
                      decoration:
                          item.completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(item.subject),
                  const SizedBox(height: 4),
                  Text(
                    formatDeadline(item.due),
                    style: TextStyle(
                      color: item.due.isBefore(DateTime.now()) &&
                              !item.completed
                          ? const Color(0xFFD65050)
                          : kBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class DeadlineEditor extends StatefulWidget {
  const DeadlineEditor({
    required this.lessons,
    super.key,
  });

  final List<Lesson> lessons;

  @override
  State<DeadlineEditor> createState() => _DeadlineEditorState();
}

class _DeadlineEditorState extends State<DeadlineEditor> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _subject = TextEditingController();

  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 23, minute: 59);

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (time != null) setState(() => _time = time);
  }

  void _save() {
    if (_title.text.trim().isEmpty || _subject.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter title and subject')),
      );
      return;
    }

    final String subject = _subject.text.trim();
    Lesson? matching;
    for (final Lesson lesson in widget.lessons) {
      if (lesson.subject.toLowerCase() == subject.toLowerCase()) {
        matching = lesson;
        break;
      }
    }

    final DateTime due = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    Navigator.pop(
      context,
      DeadlineItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: _title.text.trim(),
        subject: subject,
        due: due,
        completed: false,
        colorValue:
            matching?.colorValue ?? kSubjectColors.first.toARGB32(),
        iconCodePoint:
            matching?.iconCodePoint ?? Icons.flag_rounded.codePoint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> subjects = widget.lessons
        .map((Lesson e) => e.subject)
        .toSet()
        .toList()
      ..sort();

    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + keyboard),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7D2C9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Add deadline',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kText,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Task',
                hintText: 'e.g. Homework 3',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue value) {
                if (value.text.isEmpty) return subjects;
                return subjects.where(
                  (String s) => s
                      .toLowerCase()
                      .contains(value.text.toLowerCase()),
                );
              },
              onSelected: (String value) => _subject.text = value,
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController controller,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                controller.addListener(() {
                  _subject.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded),
                    label: Text(
                      '${_date.day.toString().padLeft(2, '0')}.'
                      '${_date.month.toString().padLeft(2, '0')}.'
                      '${_date.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(formatTime(_time)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Save deadline'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static final Uri _mapUrl = Uri.parse('https://yuujiso.github.io/aitumap');
  WebViewController? _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();

    // webview_flutter supports Android/iOS/macOS. Open the desktop map in a
    // browser on Linux and Windows, where no WebView implementation is bundled.
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) return;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kMilk)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) setState(() => _progress = progress);
          },
        ),
      )
      ..loadRequest(_mapUrl);
  }

  Future<void> _openMap() async {
    if (!await launchUrl(_mapUrl, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the map in a browser')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const TaskHubHeader(subtitle: 'AITU campus map'),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'University Map',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 28),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Reload',
                onPressed: _controller?.reload ?? _openMap,
                icon: Icon(_controller == null
                    ? Icons.open_in_browser_rounded : Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (_controller != null && _progress < 100)
          LinearProgressIndicator(
            value: _progress == 0 ? null : _progress / 100,
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5E0D6)),
            ),
            child: _controller == null
                ? Center(child: FilledButton.icon(
                    onPressed: _openMap,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('Open AITU map in browser'),
                  ))
                : WebViewWidget(controller: _controller!),
          ),
        ),
      ],
    );
  }
}

class TaskHubHeader extends StatelessWidget {
  const TaskHubHeader({
    required this.subtitle,
    super.key,
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                    ),
                    children: <InlineSpan>[
                      TextSpan(
                        text: 'Task',
                        style: TextStyle(color: kText),
                      ),
                      TextSpan(
                        text: 'Hub',
                        style: TextStyle(color: kBlue),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: kMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: kBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class MetaText extends StatelessWidget {
  const MetaText({
    required this.icon,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: kMuted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: kMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class Lesson {
  const Lesson({
    required this.id,
    required this.day,
    required this.subject,
    required this.room,
    required this.start,
    required this.end,
    required this.colorValue,
    required this.iconCodePoint,
  });

  final String id;
  final String day;
  final String subject;
  final String room;
  final String start;
  final String end;
  final int colorValue;
  final int iconCodePoint;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'day': day,
        'subject': subject,
        'room': room,
        'start': start,
        'end': end,
        'colorValue': colorValue,
        'iconCodePoint': iconCodePoint,
      };

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      day: json['day'] as String,
      subject: json['subject'] as String,
      room: (json['room'] ?? '') as String,
      start: json['start'] as String,
      end: json['end'] as String,
      colorValue: json['colorValue'] as int,
      iconCodePoint: json['iconCodePoint'] as int,
    );
  }
}

class DeadlineItem {
  const DeadlineItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.due,
    required this.completed,
    required this.colorValue,
    required this.iconCodePoint,
  });

  final String id;
  final String title;
  final String subject;
  final DateTime due;
  final bool completed;
  final int colorValue;
  final int iconCodePoint;

  DeadlineItem copyWith({
    bool? completed,
  }) {
    return DeadlineItem(
      id: id,
      title: title,
      subject: subject,
      due: due,
      completed: completed ?? this.completed,
      colorValue: colorValue,
      iconCodePoint: iconCodePoint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'subject': subject,
        'due': due.toIso8601String(),
        'completed': completed,
        'colorValue': colorValue,
        'iconCodePoint': iconCodePoint,
      };

  factory DeadlineItem.fromJson(Map<String, dynamic> json) {
    return DeadlineItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String,
      due: DateTime.parse(json['due'] as String),
      completed: json['completed'] as bool,
      colorValue: json['colorValue'] as int,
      iconCodePoint: json['iconCodePoint'] as int,
    );
  }
}

String shortDay(String day) {
  switch (day) {
    case 'Monday':
      return 'Mon';
    case 'Tuesday':
      return 'Tue';
    case 'Wednesday':
      return 'Wed';
    case 'Thursday':
      return 'Thu';
    case 'Friday':
      return 'Fri';
    case 'Saturday':
      return 'Sat';
    case 'Sunday':
      return 'Sun';
    default:
      return day;
  }
}

String formatTime(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

String formatDeadline(DateTime due) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime date = DateTime(due.year, due.month, due.day);
  final int days = date.difference(today).inDays;
  final String time =
      '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';

  if (days == 0) return 'Today • $time';
  if (days == 1) return 'Tomorrow • $time';
  if (days == -1) return 'Yesterday • $time';

  return '${due.day.toString().padLeft(2, '0')}.'
      '${due.month.toString().padLeft(2, '0')}.${due.year} • $time';
}
