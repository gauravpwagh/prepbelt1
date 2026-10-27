import 'package:logging/logging.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../platform/notification_port.dart';
import 'session_title.dart';

final _log = Logger('session');

/// The open session as the Finish sheet shows it.
class OpenSession {
  const OpenSession({
    required this.session,
    required this.title,
    required this.elapsedMinutes,
    required this.stale,
    required this.prefill,
    required this.unread,
  });

  final SessionRow session;
  final String title;

  /// now − started_at, in whole minutes; a negative value counts as 0.
  final int elapsedMinutes;

  /// Older than max(4 h, 3 × base): the sheet asks "Did you finish?".
  final bool stale;

  /// Elapsed minutes, or the base time when stale.
  final int prefill;

  /// Unread items get a first study; others go to the grade sheet.
  final bool unread;
}

sealed class FinishOutcome {
  const FinishOutcome(this.nodeId, this.minutes, this.sessionId);
  final String nodeId;
  final int minutes;
  final String sessionId;
}

final class NeedsFirstStudy extends FinishOutcome {
  const NeedsFirstStudy(super.nodeId, super.minutes, super.sessionId);
}

final class NeedsGrade extends FinishOutcome {
  const NeedsGrade(super.nodeId, super.minutes, super.sessionId);
}

/// Finish (design §6, plan item 73).
class FinishSession {
  FinishSession(this._db, this._notifications, {required DateTime Function() now})
      : _now = now;

  final AppDatabase _db;
  final NotificationPort _notifications;
  final DateTime Function() _now;

  Future<OpenSession?> pending() async {
    final s = await _db.sessionsDao.open();
    if (s == null) return null;
    final node = await _db.nodesDao.byId(s.nodeId);
    final base = node?.baseMinutes ?? Defaults.baseMin;
    var elapsed = _now().difference(s.startedAtUtc).inMinutes;
    if (elapsed < 0) elapsed = 0;
    final stale = elapsed > Defaults.staleSession(base);
    return OpenSession(
      session: s,
      title: node == null ? 'Deleted item' : await sessionTitle(_db, s.nodeId),
      elapsedMinutes: elapsed,
      stale: stale,
      prefill: stale ? base : elapsed,
      unread: (await _db.itemStateDao.stateOf(s.nodeId)).belt == Belt.unread,
    );
  }

  /// Ends the session with the confirmed minutes. The caller then writes the
  /// first study, or shows the grade sheet, with this session's ID.
  Future<FinishOutcome> confirm(OpenSession open, int minutes) async {
    final s = open.session;
    await _db.sessionsDao.finish(s.id, _now(), minutes, edited: minutes != open.prefill);
    await _cancelNotifications();
    _log.info('Session ${s.id} finished: $minutes min');
    return open.unread
        ? NeedsFirstStudy(s.nodeId, minutes, s.id)
        : NeedsGrade(s.nodeId, minutes, s.id);
  }

  Future<void> _cancelNotifications() async {
    try {
      await _notifications.cancelSession();
    } catch (e, st) {
      _log.warning('Cancelling session notifications failed', e, st);
    }
  }
}
