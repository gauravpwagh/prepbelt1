import 'package:logging/logging.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../platform/notification_port.dart';
import '../platform/source_opener.dart';
import 'session_title.dart';

final _log = Logger('session');

sealed class StartResult {
  const StartResult();
}

final class Started extends StartResult {
  const Started(this.sessionId, this.open);
  final String sessionId;

  /// How opening the source went; `notFound` has already marked the source
  /// `needs_relink`. Null when the item has no source.
  final OpenResult? open;
}

/// Another session is open: finish or discard it first.
final class AlreadyOpen extends StartResult {
  const AlreadyOpen(this.session);
  final SessionRow session;
}

/// Start (design §6, plan item 72).
class StartSession {
  StartSession(
    this._db,
    this._notifications,
    this._opener, {
    required String Function() newId,
    required DateTime Function() now,
  })  : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final NotificationPort _notifications;
  final SourceOpener _opener;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<StartResult> call(String nodeId) async {
    final open = await _db.sessionsDao.open();
    if (open != null) return AlreadyOpen(open);

    final node = (await _db.nodesDao.byId(nodeId))!;
    final id = _newId();
    final now = _now();
    await _db.sessionsDao.start(id, nodeId, now);
    _log.info('Session $id started on $nodeId');

    final title = await sessionTitle(_db, nodeId);
    final base = node.baseMinutes ?? Defaults.baseMin;
    try {
      await _notifications.showOngoingSession(title, now);
      await _notifications.scheduleStillReading(
          now.add(Duration(minutes: Defaults.stillReadingAfter(base))), title);
    } catch (e, st) {
      // The notification is a convenience; reopening the app always finds
      // the session (CUJ 3a).
      _log.warning('Session notification failed', e, st);
    }

    final owner = await sourceOwnerOf(_db, node);
    final source = owner == null ? null : await _db.sourcesDao.sourceFor(owner.id);
    OpenResult? result;
    if (source != null) {
      result = await _opener.open(source);
      if (result == OpenResult.notFound) {
        await _db.sourcesDao.setLinkStatus(source.nodeId, LinkStatus.needsRelink);
      }
    }
    return Started(id, result);
  }
}
