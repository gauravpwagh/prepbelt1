import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/study_writer.dart';
import 'build_today_plan.dart';

/// The part a session covered, for a task split as you go (design §10b).
class StudiedPart {
  const StudiedPart(this.title, {this.last = false});
  final String title;

  /// "That was the last part": the task is finished.
  final bool last;
}

/// First reading of an item (plan item 75), or of the next part of a task
/// split as you go (design §10b).
class MarkStudied {
  MarkStudied(this._db, this._writer, this._plans, this._dayClock,
      {required String Function() newId})
      : _newId = newId;

  final AppDatabase _db;
  final StudyWriter _writer;
  final BuildTodayPlan _plans;
  final LocalDayClock _dayClock;
  final String Function() _newId;

  /// The pre-filled minutes without a timer: the item's base time.
  Future<int> defaultMinutes(String nodeId) async =>
      (await _db.nodesDao.byId(nodeId))?.baseMinutes ?? 0;

  /// The pre-filled title of the next part, or null when [nodeId] is not an
  /// open task split as you go.
  Future<String?> nextPart(String nodeId) async {
    final node = await _db.nodesDao.byId(nodeId);
    if (node?.splitAsIGo != SplitAsIGo.open) return null;
    return nextPartTitle([for (final c in await _db.nodesDao.children(nodeId)) c.title]);
  }

  /// Writes `first_study`. An item that is not in today's plan gets a done
  /// `first_read` row, so the day's minutes count it. For an open task
  /// split as you go, [part] names the part: it is added as a subtask and
  /// studied instead, and the task's plan row moves to it.
  Future<FirstStudy> call(String nodeId, int minutes,
          {String? sessionId, StudiedPart? part}) =>
      _db.transaction(() async {
        final plan = await _plans.get();
        final today = _dayClock.today();
        final node = (await _db.nodesDao.byId(nodeId))!;
        var studied = nodeId;
        var inPlan = plan.rows.any((r) => r.nodeId == nodeId);
        if (node.splitAsIGo == SplitAsIGo.open) {
          final title = part?.title.trim() ?? '';
          if (title.isEmpty) throw ArgumentError('Name the part you covered');
          studied = _newId();
          await _db.nodesDao.insertNode(StudyNodesCompanion.insert(
            id: studied,
            subjectId: node.subjectId,
            parentId: Value(node.id),
            kind: NodeKind.subtask,
            taskKind: Value(node.taskKind),
            title: title,
            baseMinutes: Value(partBaseMinutes(minutes)),
            sortOrder: await _db.nodesDao.nextSortOrder(node.subjectId, node.id),
            createdAt: _dayClock.clock.nowUtc(),
          ));
          inPlan = await _db.plansDao.moveOpenRow(today, nodeId, studied);
          if (part!.last) await finish(nodeId);
        }
        final e = await _writer.writeFirstStudy(studied, minutes, sessionId: sessionId);
        if (!inPlan && e.localDate == today) {
          await _db.plansDao.addDoneRow(e.localDate, studied, RowType.firstRead,
              minutes, Reason.firstRead, e.atUtc);
        }
        return e;
      });

  /// Ends a task split as you go ("Mark finished", design §10b).
  Future<void> finish(String taskId) => _db.nodesDao.updateNode(
      taskId, const StudyNodesCompanion(splitAsIGo: Value(SplitAsIGo.done)));
}
