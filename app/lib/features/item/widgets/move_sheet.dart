import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../../application/move_item.dart';
import '../../../core/providers.dart';
import '../../../data/db/app_database.dart';

/// One place in the Move picker.
class MoveChoice {
  const MoveChoice(this.target, this.label, this.kind, this.depth,
      {this.current = false, this.note});
  final MoveTarget target;
  final String label;

  /// Null for a subject.
  final NodeKind? kind;

  final int depth;

  /// Where the item already is.
  final bool current;

  /// Why a choice can't be picked (a task with review history).
  final String? note;

  bool get enabled => !current && note == null;
}

/// Every place [node] can move to (design §10a): subjects (Inbox last), their
/// topics for tasks and subtasks, and their tasks for subtasks.
final moveChoicesProvider =
    FutureProvider.autoDispose.family<List<MoveChoice>, String>((ref, nodeId) async {
  final db = ref.watch(appDatabaseProvider);
  final node = (await db.nodesDao.byId(nodeId))!;
  final subjects = await db.subjectsDao.all();
  subjects.sort((a, b) => (a.isInbox ? 1 : 0).compareTo(b.isInbox ? 1 : 0));
  final choices = <MoveChoice>[];

  Future<void> addTasks(String subjectId, List<NodeRow> tasks, int depth) async {
    for (final t in tasks) {
      if (t.kind != NodeKind.task) continue;
      final events = await db.eventsDao.countFor(t.id);
      choices.add(MoveChoice(MoveTarget(subjectId: subjectId, parentId: t.id), t.title, NodeKind.task, depth,
          current: t.id == node.parentId,
          note: canAddChild(NodeKind.task, events) ? null : 'has review history'));
    }
  }

  for (final s in subjects) {
    choices.add(MoveChoice(MoveTarget(subjectId: s.id), s.name, null, 0,
        current: node.parentId == null && node.subjectId == s.id));
    if (node.kind == NodeKind.topic) continue;
    final roots = await db.nodesDao.roots(s.id);
    for (final r in roots) {
      if (r.kind == NodeKind.topic) {
        choices.add(MoveChoice(MoveTarget(subjectId: s.id, parentId: r.id), r.title, NodeKind.topic, 1,
            current: r.id == node.parentId));
        if (node.kind == NodeKind.subtask) await addTasks(s.id, await db.nodesDao.children(r.id), 2);
      }
    }
    if (node.kind == NodeKind.subtask) await addTasks(s.id, roots, 1);
  }
  return choices;
});

/// Shows the picker and returns the chosen place, or null.
Future<MoveTarget?> showMoveSheet(BuildContext context, NodeRow node) =>
    showModalBottomSheet<MoveTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MoveSheet(node),
    );

class _MoveSheet extends ConsumerWidget {
  const _MoveSheet(this.node);
  final NodeRow node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choices = ref.watch(moveChoicesProvider(node.id));
    final text = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => switch (choices) {
        AsyncData(:final value) => ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Move "${node.title}"', style: text.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  node.kind == NodeKind.subtask
                      ? 'Pick a task, or a subject or topic to make it a task of its own.'
                      : 'Everything under it moves too. Belts and history stay.',
                  style: text.bodySmall,
                ),
              ),
              for (final c in value)
                ListTile(
                  key: Key('move-${c.target.parentId ?? c.target.subjectId}'),
                  enabled: c.enabled,
                  contentPadding: EdgeInsets.only(left: 16 + 24.0 * c.depth, right: 16),
                  leading: Icon(switch (c.kind) {
                    null => Icons.menu_book_outlined,
                    NodeKind.topic => Icons.folder_outlined,
                    _ => Icons.description_outlined,
                  }),
                  title: Text(c.label),
                  subtitle: c.current
                      ? const Text('Here now')
                      : c.note == null
                          ? null
                          : Text(c.note!),
                  onTap: () => Navigator.pop(context, c.target),
                ),
            ],
          ),
        AsyncError(:final error) => Center(child: Text('Could not load: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
