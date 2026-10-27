import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import 'delete_item.dart';

/// Where an item can go: the top of a subject, or under a topic or task.
class MoveTarget {
  const MoveTarget({required this.subjectId, this.parentId});
  final String subjectId;
  final String? parentId;
}

/// Moves an item, with everything under it, to another subject, topic or
/// task (design §10a). History and belts stay; only the exam cap, read from
/// the new subject's exams, can change.
///
/// * A topic goes to the top of a subject.
/// * A task goes to the top of a subject or under a topic.
/// * A subtask goes under another task that has no review history, or to the
///   top of a subject or under a topic, where it becomes a task with a copy
///   of its old task's source.
class MoveItem {
  MoveItem(this._db);
  final AppDatabase _db;

  Future<void> call(String nodeId, MoveTarget to) => _db.transaction(() async {
        final node = await _db.nodesDao.byId(nodeId);
        if (node == null || node.deletedAt != null) {
          throw StateError('The item no longer exists');
        }
        if (await _db.subjectsDao.byId(to.subjectId) == null) {
          throw StateError('The subject no longer exists');
        }
        NodeRow? parent;
        if (to.parentId != null) {
          parent = await _db.nodesDao.byId(to.parentId!);
          if (parent == null || parent.deletedAt != null || parent.subjectId != to.subjectId) {
            throw StateError('The new place no longer exists');
          }
        }
        final kind = switch (node.kind) {
          NodeKind.subtask when parent?.kind != NodeKind.task => NodeKind.task,
          final k => k,
        };
        if (!canAttach(kind, parent?.kind)) {
          throw StateError(parent == null
              ? 'A ${kind.key} needs a parent'
              : 'A ${node.kind.key} cannot go under a ${parent.kind.key}');
        }
        if (parent != null && parent.id == node.parentId) return; // already there
        if (parent == null && node.parentId == null && node.subjectId == to.subjectId) return;
        if (kind == NodeKind.subtask &&
            !canAddChild(parent!.kind, await _db.eventsDao.countFor(parent.id))) {
          throw StateError('That task has review history, so it cannot gain subtasks.');
        }

        // A subtask that becomes a task keeps the source it used to inherit.
        final oldTask = node.kind == NodeKind.subtask && kind == NodeKind.task
            ? await _db.nodesDao.byId(node.parentId!)
            : null;
        await refile(_db, node, subjectId: to.subjectId, parentId: parent?.id, kind: kind);
        if (oldTask != null && await _db.sourcesDao.sourceFor(node.id) == null) {
          final source = await _db.sourcesDao.sourceFor(oldTask.id);
          if (source != null) {
            await _db.sourcesDao.upsertSource(source.copyWith(nodeId: node.id).toCompanion(true));
          }
        }
      });
}
