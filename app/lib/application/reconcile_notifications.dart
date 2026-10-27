import 'package:logging/logging.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../platform/notification_port.dart';
import 'session_title.dart';

final _log = Logger('notifications');

/// Re-creates every notification from the database (design §9): the daily
/// reminder, and the session notifications while a session is open. Runs on
/// app open, after session writes and after a reminder change; the plugin's
/// receivers handle reboots and updates.
class ReconcileNotifications {
  ReconcileNotifications(this._db, this._port, {required DateTime Function() now})
      : _now = now;

  final AppDatabase _db;
  final NotificationPort _port;
  final DateTime Function() _now;

  /// When the daily reminder was last scheduled (Diagnostics).
  DateTime? lastScheduled;

  Future<void> call() async {
    try {
      final t = await _db.settingsDao.reminderTime();
      await _port.scheduleDailyReminder(t.hour, t.minute);
      lastScheduled = _now();

      final s = await _db.sessionsDao.open();
      if (s == null) {
        await _port.cancelSession();
        return;
      }
      final node = await _db.nodesDao.byId(s.nodeId);
      final title = await sessionTitle(_db, s.nodeId);
      await _port.showOngoingSession(title, s.startedAtUtc);
      final still = s.startedAtUtc
          .add(Duration(minutes: Defaults.stillReadingAfter(node?.baseMinutes ?? Defaults.baseMin)));
      if (still.isAfter(_now())) await _port.scheduleStillReading(still, title);
    } catch (e, st) {
      _log.warning('Reconcile failed', e, st);
    }
  }
}
