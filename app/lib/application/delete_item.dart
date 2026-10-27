import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';

/// What a delete changed, so that it can be undone (design §10a).
class DeleteReceipt {
  const DeleteReceipt._(this.nodeId, this.before, this.copiedSources, this.movedToInbox);

  final String nodeId;

  /// How many children moved to the Inbox.
  final int movedToInbox;

  /// Every node the delete changed, as it was before.
  final List<NodeRow> before;

  /// Nodes that were given a copy of their old task's source.
  final List<String> copiedSources;
}

/// Soft-deletes an item. History stays (design §10a).
///
/// With [keepChildren] false the item and everything under it are deleted.
/// With [keepChildren] true only the item goes, and its live children move to
/// the Inbox: a topic's tasks keep their subtasks, and a task's subtasks
/// become tasks that carry a copy of the task's source.
class DeleteItem {
  DeleteItem(this._db, {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<DeleteReceipt> call(String nodeId, {bool keepChildren = false}) =>
      _db.transaction(() async {
        final node = await _db.nodesDao.byId(nodeId);
        if (node == null || node.deletedAt != null) {
          throw StateError('The item no longer exists');
        }
        final before = <NodeRow>[];
        final copied = <String>[];
        var moved = 0;
        if (keepChildren) {
          final inbox = await _db.subjectsDao.ensureInbox(newId: _newId, now: _now());
          final source = node.kind == NodeKind.task ? await _db.sourcesDao.sourceFor(node.id) : null;
          for (final child in await _db.nodesDao.children(node.id)) {
            final asTask = child.kind == NodeKind.subtask;
            moved++;
            before.addAll(await refile(_db, child,
                subjectId: inbox.id, parentId: null, kind: NodeKind.task));
            if (asTask && source != null && await _db.sourcesDao.sourceFor(child.id) == null) {
              await _db.sourcesDao.upsertSource(source.copyWith(nodeId: child.id).toCompanion(true));
              copied.add(child.id);
            }
          }
          before.add(node);
          await _db.nodesDao.updateNode(node.id, StudyNodesCompanion(deletedAt: Value(_now())));
        } else {
          before.addAll(await _db.nodesDao.liveSubtree(node.id));
          await _db.nodesDao.softDelete(node.id, _now());
        }
        return DeleteReceipt._(node.id, before, copied, moved);
      });

  /// Puts every node back as it was and drops the copied sources.
  Future<void> undo(DeleteReceipt r) => _db.transaction(() async {
        for (final id in r.copiedSources) {
          await _db.sourcesDao.deleteSource(id);
        }
        for (final n in r.before) {
          await _db.nodesDao.replaceNode(n);
        }
      });
}

/// Moves [node] to [subjectId] under [parentId] as [kind], at the end of its
/// new siblings, and moves its whole subtree (live or not) to [subjectId].
/// Returns the rows as they were before.
Future<List<NodeRow>> refile(
  AppDatabase db,
  NodeRow node, {
  required String subjectId,
  required String? parentId,
  required NodeKind kind,
}) async {
  final subtree = await db.nodesDao.subtree(node.id);
  final order = await db.nodesDao.nextSortOrder(subjectId, parentId);
  await db.nodesDao.updateNode(
      node.id,
      StudyNodesCompanion(
        subjectId: Value(subjectId),
        parentId: Value(parentId),
        kind: Value(kind),
        sortOrder: Value(order),
      ));
  for (final d in subtree) {
    if (d.id != node.id && d.subjectId != subjectId) {
      await db.nodesDao.updateNode(d.id, StudyNodesCompanion(subjectId: Value(subjectId)));
    }
  }
  return subtree;
}
