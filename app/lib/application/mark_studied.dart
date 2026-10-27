import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/study_writer.dart';
import 'build_today_plan.dart';

/// First reading of an item (plan item 75).
class MarkStudied {
  MarkStudied(this._db, this._writer, this._plans, this._dayClock);

  final AppDatabase _db;
  final StudyWriter _writer;
  final BuildTodayPlan _plans;
  final LocalDayClock _dayClock;

  /// The pre-filled minutes without a timer: the item's base time.
  Future<int> defaultMinutes(String nodeId) async =>
      (await _db.nodesDao.byId(nodeId))?.baseMinutes ?? 0;

  /// Writes `first_study`. An item that is not in today's plan gets a done
  /// `first_read` row, so the day's minutes count it.
  Future<FirstStudy> call(String nodeId, int minutes, {String? sessionId}) =>
      _db.transaction(() async {
        final plan = await _plans.get();
        final inPlan = plan.rows.any((r) => r.nodeId == nodeId);
        final e =
            await _writer.writeFirstStudy(nodeId, minutes, sessionId: sessionId);
        if (!inPlan && e.localDate == _dayClock.today()) {
          await _db.plansDao.addDoneRow(e.localDate, nodeId, RowType.firstRead,
              minutes, Reason.firstRead, e.atUtc);
        }
        return e;
      });
}
