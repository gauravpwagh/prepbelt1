// Notifications (design §9, plan item 66). Everything scheduled is inexact;
// the app never asks for exact alarms.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:timezone/timezone.dart' as tz;

final _log = Logger('notifications');

abstract interface class NotificationPort {
  /// [onTap] receives the route carried by a tapped notification.
  Future<void> init(void Function(String route) onTap);

  /// The route of the notification that launched the app, if any.
  Future<String?> launchRoute();

  /// "{task} · {position}" with a running clock and a Done action.
  Future<void> showOngoingSession(String title, DateTime startedAtUtc);

  /// "Still on {title}? Tap to finish." at [atUtc].
  Future<void> scheduleStillReading(DateTime atUtc, String title);

  /// "Your study plan is ready", daily at [hour]:[minute] local time.
  Future<void> scheduleDailyReminder(int hour, int minute);

  Future<void> cancelSession();
  Future<bool> requestPermission();
  Future<bool> permissionGranted();

  /// Descriptions of pending scheduled notifications (Diagnostics).
  Future<List<String>> pending();

  Future<void> showTest();
}

abstract final class NotificationIds {
  static const dailyReminder = 1;
  static const session = 2;
  static const stillReading = 3;
  static const test = 9;
}

class LocalNotificationPort implements NotificationPort {
  LocalNotificationPort([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _reminders = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Daily plan reminder and "Still reading?"',
    importance: Importance.defaultImportance,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init(void Function(String route) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload ?? '/today'),
    );
  }

  @override
  Future<String?> launchRoute() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload ?? '/today';
  }

  @override
  Future<void> showOngoingSession(String title, DateTime startedAtUtc) => _plugin.show(
        id: NotificationIds.session,
        title: title,
        body: 'Studying — tap Done when you finish',
        payload: '/today',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'session',
            'Study session',
            channelDescription: 'The running study timer',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            usesChronometer: true,
            when: startedAtUtc.millisecondsSinceEpoch,
            actions: const [
              AndroidNotificationAction('done', 'Done', showsUserInterface: true),
            ],
          ),
        ),
      );

  @override
  Future<void> scheduleStillReading(DateTime atUtc, String title) => _plugin.zonedSchedule(
        id: NotificationIds.stillReading,
        title: 'Still on $title?',
        body: 'Tap to finish.',
        payload: '/today',
        scheduledDate: tz.TZDateTime.from(atUtc, tz.local),
        notificationDetails: const NotificationDetails(android: _reminders),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

  @override
  Future<void> scheduleDailyReminder(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    _log.info('Daily reminder scheduled for $at');
    return _plugin.zonedSchedule(
      id: NotificationIds.dailyReminder,
      title: 'Your study plan is ready',
      payload: '/today',
      scheduledDate: at,
      notificationDetails: const NotificationDetails(android: _reminders),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancelSession() async {
    await _plugin.cancel(id: NotificationIds.session);
    await _plugin.cancel(id: NotificationIds.stillReading);
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> permissionGranted() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<List<String>> pending() async => [
        for (final p in await _plugin.pendingNotificationRequests())
          '#${p.id} ${p.title ?? ''}'.trim(),
      ];

  @override
  Future<void> showTest() => _plugin.show(
        id: NotificationIds.test,
        title: 'Test notification',
        body: 'Notifications are working.',
        payload: '/diagnostics',
        notificationDetails: const NotificationDetails(android: _reminders),
      );
}
