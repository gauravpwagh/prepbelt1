import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';

/// Splits a task into subtasks (plan item 79, CUJ 2). Each subtask inherits
/// the task's kind and source, holds its own position and gets the default
/// base time.
class SplitItem {
  SplitItem(this._db, {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Whether [taskId] may be split: a live task with no review history.
  Future<bool> allowed(String taskId) async {
    final task = await _db.nodesDao.byId(taskId);
    return task != null &&
        task.deletedAt == null &&
        task.kind == NodeKind.task &&
        canSplit(await _db.eventsDao.countFor(taskId));
  }

  Future<List<String>> call(String taskId, SplitSpec spec) =>
      _db.transaction(() async {
        if (!await allowed(taskId)) {
          throw StateError('Only a task with no review history can be split. '
              'Create a new task with chapters instead.');
        }
        final task = (await _db.nodesDao.byId(taskId))!;
        final parts = split(spec);
        final kind = task.taskKind ?? TaskKind.reading;
        var order = await _db.nodesDao.nextSortOrder(task.subjectId, task.id);
        final now = _now();
        final ids = <String>[];
        for (final p in parts) {
          final id = _newId();
          await _db.nodesDao.insertNode(StudyNodesCompanion.insert(
            id: id,
            subjectId: task.subjectId,
            parentId: Value(task.id),
            kind: NodeKind.subtask,
            taskKind: Value(kind),
            title: p.title,
            positionText: Value(p.positionText),
            baseMinutes: Value(kind.defaultBaseMinutes),
            sortOrder: order++,
            createdAt: now,
          ));
          ids.add(id);
        }
        return ids;
      });
}
