import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'nodes_dao.g.dart';

/// SQL for "node `n` is reviewable" (`isReviewable` in `prep_core`): live, not
/// a topic, and without live children.
const reviewableSql = "n.deleted_at IS NULL AND n.kind <> 'topic'"
    ' AND NOT EXISTS (SELECT 1 FROM study_nodes c'
    ' WHERE c.parent_id = n.id AND c.deleted_at IS NULL)';

@DriftAccessor(tables: [StudyNodes, Subjects, ItemStates])
class NodesDao extends DatabaseAccessor<AppDatabase> with _$NodesDaoMixin {
  NodesDao(super.db);

  Future<void> insertNode(StudyNodesCompanion node) =>
      into(studyNodes).insert(node);

  /// The node, including a soft-deleted one.
  Future<NodeRow?> byId(String id) =>
      (select(studyNodes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<void> updateNode(String id, StudyNodesCompanion changes) =>
      (update(studyNodes)..where((n) => n.id.equals(id))).write(changes);

  /// Soft-deletes [id] and every live descendant.
  Future<void> softDelete(String id, DateTime at) => customUpdate(
        'WITH RECURSIVE sub(id) AS ('
        ' SELECT ?1'
        ' UNION ALL SELECT n.id FROM study_nodes n JOIN sub ON n.parent_id = sub.id'
        ') UPDATE study_nodes SET deleted_at = ?2'
        ' WHERE id IN (SELECT id FROM sub) AND deleted_at IS NULL',
        variables: [
          Variable.withString(id),
          Variable.withInt(at.toUtc().millisecondsSinceEpoch),
        ],
        updates: {studyNodes},
        updateKind: UpdateKind.update,
      );

  SimpleSelectStatement<$StudyNodesTable, NodeRow> _ordered(
          Expression<bool> Function($StudyNodesTable n) where) =>
      select(studyNodes)
        ..where((n) => where(n) & n.deletedAt.isNull())
        ..orderBy([
          (n) => OrderingTerm.asc(n.sortOrder),
          (n) => OrderingTerm.asc(n.createdAt),
          (n) => OrderingTerm.asc(n.id),
        ]);

  /// Live children of [parentId], in sort order.
  Future<List<NodeRow>> children(String parentId) =>
      _ordered((n) => n.parentId.equals(parentId)).get();

  /// Live top-level nodes of [subjectId], in sort order.
  Future<List<NodeRow>> roots(String subjectId) =>
      _ordered((n) => n.subjectId.equals(subjectId) & n.parentId.isNull())
          .get();

  Future<int> liveChildCount(String parentId) async {
    final count = studyNodes.id.count();
    final row = await (selectOnly(studyNodes)
          ..addColumns([count])
          ..where(studyNodes.parentId.equals(parentId) &
              studyNodes.deletedAt.isNull()))
        .getSingle();
    return row.read(count)!;
  }

  /// Every live node of [subjectId], in sort order within each parent. The
  /// caller builds the tree from `parentId`.
  Stream<List<NodeRow>> watchTree(String subjectId) =>
      _ordered((n) => n.subjectId.equals(subjectId)).watch();

  /// Belts of the reviewable leaves at or below [nodeId] (design §3 rollup).
  /// Leaves with no `item_state` row are Unread.
  Future<List<Belt>> leafBelts(String nodeId) => _leafBelts(
        'SELECT ?1 AS id'
        ' UNION ALL SELECT n.id FROM study_nodes n JOIN sub ON n.parent_id = sub.id'
        ' WHERE n.deleted_at IS NULL',
        nodeId,
      );

  /// Belts of every reviewable leaf of [subjectId].
  Future<List<Belt>> subjectLeafBelts(String subjectId) => _leafBelts(
        'SELECT id FROM study_nodes WHERE subject_id = ?1',
        subjectId,
      );

  Future<List<Belt>> _leafBelts(String subSql, String arg) async {
    final rows = await customSelect(
      'WITH RECURSIVE sub(id) AS ($subSql)'
      " SELECT COALESCE(s.belt, 'unread') AS belt"
      ' FROM sub JOIN study_nodes n ON n.id = sub.id'
      ' LEFT JOIN item_state s ON s.node_id = n.id'
      ' WHERE $reviewableSql',
      variables: [Variable.withString(arg)],
      readsFrom: {studyNodes, itemStates},
    ).get();
    return [for (final r in rows) Belt.fromKey(r.read<String>('belt'))];
  }

  /// [SortKey]s for every live reviewable node, keyed by node ID.
  Future<Map<String, SortKey>> sortKeys() async {
    final subjectOrder = {
      for (final s in await select(subjects).get()) s.id: s.sortOrder,
    };
    final live = {
      for (final n in await (select(studyNodes)
            ..where((n) => n.deletedAt.isNull()))
          .get())
        n.id: n,
    };
    final hasChildren = {
      for (final n in live.values)
        if (n.parentId != null) n.parentId!,
    };
    final keys = <String, SortKey>{};
    for (final n in live.values) {
      if (n.kind == NodeKind.topic || hasChildren.contains(n.id)) continue;
      final task = n.kind == NodeKind.subtask ? live[n.parentId] : n;
      if (task == null) continue; // A subtask whose task is deleted.
      final topic = task.parentId == null ? null : live[task.parentId];
      keys[n.id] = SortKey(
        subjectOrder: subjectOrder[n.subjectId] ?? 0,
        topicOrder: topic?.sortOrder ?? 0,
        taskOrder: task.sortOrder,
        subtaskOrder: n.kind == NodeKind.subtask ? n.sortOrder : 0,
        createdAtUtcMs: n.createdAt.millisecondsSinceEpoch,
        id: n.id,
      );
    }
    return keys;
  }
}
