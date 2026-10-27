import 'package:logging/logging.dart';

import '../data/db/app_database.dart';
import '../platform/notification_port.dart';

final _log = Logger('session');

/// Discard (plan item 74): ends the open session and writes nothing else.
class DiscardSession {
  DiscardSession(this._db, this._notifications, {required DateTime Function() now})
      : _now = now;

  final AppDatabase _db;
  final NotificationPort _notifications;
  final DateTime Function() _now;

  Future<void> call(String sessionId) async {
    await _db.sessionsDao.discard(sessionId, _now());
    try {
      await _notifications.cancelSession();
    } catch (e, st) {
      _log.warning('Cancelling session notifications failed', e, st);
    }
    _log.info('Session $sessionId discarded');
  }
}
