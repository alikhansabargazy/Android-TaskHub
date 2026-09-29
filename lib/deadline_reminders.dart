import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'main.dart';

/// Device-local deadline alerts. Remote push requires an account and push server.
class DeadlineReminders {
  DeadlineReminders._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> initialize() async {
    if (!supported || _ready) return;
    tz.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    ));
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  static int _id(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> sync(List<DeadlineItem> deadlines) async {
    if (!supported) return;
    await initialize();
    // Only cancel notifications owned by TaskHub; leave other app schedules alone.
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith('taskhub:') ?? false) {
        await _plugin.cancel(notification.id);
      }
    }
    final now = DateTime.now();
    for (final item in deadlines.where((item) =>
        !item.completed && item.due.isAfter(now))) {
      await _plugin.zonedSchedule(
        _id(item.id),
        'Deadline: ${item.title}',
        '${item.subject} • deadline reached',
        tz.TZDateTime.from(item.due, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'taskhub_deadlines', 'TaskHub deadlines',
            channelDescription: 'Reminders at the due time of a task',
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        payload: 'taskhub:${item.id}',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
