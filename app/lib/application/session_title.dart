import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';

/// The task that owns [node]'s source: the node itself, or a subtask's task.
Future<NodeRow?> sourceOwnerOf(AppDatabase db, NodeRow node) async =>
    node.kind == NodeKind.subtask && node.parentId != null
        ? db.nodesDao.byId(node.parentId!)
        : node;

/// "{task} · {position}" for notifications (design §6, CUJ 3c):
/// "Spectrum Modern History (printed) · Ch 9 · pp. 210–236".
Future<String> sessionTitle(AppDatabase db, String nodeId) async {
  final node = (await db.nodesDao.byId(nodeId))!;
  final task = await sourceOwnerOf(db, node) ?? node;
  final source = await db.sourcesDao.sourceFor(task.id);
  final parts = <String>[
    source?.sourceType == SourceType.book ? '${task.title} (printed)' : task.title,
    if (node.id != task.id) node.title,
    if (node.positionText != null && node.positionText != node.title) node.positionText!,
  ];
  return parts.join(' · ');
}
