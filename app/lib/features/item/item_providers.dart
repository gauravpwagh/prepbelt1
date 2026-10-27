import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/explain_due.dart';
import '../../core/db_watch.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';

class ItemView {
  const ItemView({
    required this.node,
    required this.subject,
    required this.parent,
    required this.children,
    required this.source,
    required this.sourceOwner,
    required this.eventCount,
    required this.explanation,
  });

  final NodeRow node;
  final SubjectRow subject;
  final NodeRow? parent;
  final List<NodeRow> children;

  /// The node's own source, or its task's for a subtask.
  final SourceRow? source;

  /// The task that owns [source].
  final NodeRow? sourceOwner;
  final int eventCount;
  final DueExplanation explanation;

  bool get reviewable => isReviewable(node.kind, children.length);

  /// An open task split as you go (design §10b): studied part by part.
  bool get asIGo => node.splitAsIGo == SplitAsIGo.open;
  bool get canSplit_ => node.kind == NodeKind.task && canSplit(eventCount);
  bool get canAddChild_ => canAddChild(node.kind, eventCount);
  ItemState get state => explanation.state;
}

/// Null when the node no longer exists or was deleted.
final itemViewProvider = StreamProvider.autoDispose.family<ItemView?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  final explain = ref.watch(explainDueProvider);
  return watchTables(
    db,
    {
      db.studyNodes,
      db.reviewEvents,
      db.itemStates,
      db.nodeSources,
      db.subjects,
      db.exams,
      db.examSubjects,
    },
    () async {
      final node = await db.nodesDao.byId(id);
      if (node == null || node.deletedAt != null) return null;
      final parent = node.parentId == null ? null : await db.nodesDao.byId(node.parentId!);
      final owner = node.kind == NodeKind.subtask ? parent : node;
      return ItemView(
        node: node,
        subject: (await db.subjectsDao.byId(node.subjectId))!,
        parent: parent,
        children: await db.nodesDao.children(id),
        source: owner == null ? null : await db.sourcesDao.sourceFor(owner.id),
        sourceOwner: owner,
        eventCount: await db.eventsDao.countFor(id),
        explanation: await explain(id),
      );
    },
  );
});
