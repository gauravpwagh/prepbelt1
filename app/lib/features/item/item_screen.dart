import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';
import '../../core/sheets.dart';
import '../../core/slots.dart';
import '../../core/widgets/belt_chip.dart';
import '../../core/widgets/minutes_text.dart';
import 'item_providers.dart';
import 'widgets/history_list.dart';
import 'widgets/source_card.dart';
import 'widgets/why_due_panel.dart';

class ItemScreen extends ConsumerWidget {
  const ItemScreen({super.key, required this.nodeId});
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(itemViewProvider(nodeId));
    return switch (view) {
      AsyncData(value: final v?) => _ItemBody(v),
      AsyncData() => Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('This item no longer exists.'))),
      AsyncError(:final error) =>
        Scaffold(appBar: AppBar(), body: Center(child: Text('Could not load: $error'))),
      _ => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
    };
  }
}

class _ItemBody extends ConsumerWidget {
  const _ItemBody(this.v);
  final ItemView v;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text(v.children.isEmpty
            ? '"${v.node.title}" will be removed from your plan and Library.'
            : '"${v.node.title}" and everything under it will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(deleteItemProvider)(v.node.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = v.node;
    final text = Theme.of(context).textTheme;
    final today = ref.watch(todayProvider);
    final sheets = ref.read(appSheetsProvider);
    final rowAction = ref.watch(planRowActionProvider);
    final unread = v.state.belt == Belt.unread;
    final due = v.explanation.effectiveDue;
    return Scaffold(
      appBar: AppBar(
        title: Text(n.kind == NodeKind.subtask && v.parent != null
            ? '${v.parent!.title} · ${n.title}'
            : n.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (a) => switch (a) {
              'delete' => _delete(context, ref),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (v.reviewable) BeltChip(v.state.belt),
            Chip(label: Text(v.subject.name)),
            if (n.taskKind != null) Chip(label: Text(taskKindLabel(n.taskKind!))),
            if (n.baseMinutes != null) Chip(label: MinutesText(n.baseMinutes!)),
            if (n.positionText != null) Chip(label: Text(n.positionText!)),
          ]),
          const SizedBox(height: 12),
          if (v.reviewable) ...[
            Text(
              unread
                  ? 'Not studied yet'
                  : due == null
                      ? 'No review scheduled'
                      : 'Next review: ${formatRelativeDay(due, today)}'
                          '${due < today ? ' (overdue)' : ''}',
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (rowAction != null) rowAction(context, n.id, unread: unread),
              OutlinedButton(
                key: const Key('item-record'),
                onPressed: () =>
                    unread ? sheets.studied(context, n.id) : sheets.grade(context, n.id),
                child: Text(unread ? 'Mark studied' : 'Grade review'),
              ),
              if (v.eventCount > 0)
                TextButton.icon(
                  key: const Key('item-undo'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo latest'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final u = await ref.read(undoLatestProvider)(n.id);
                    messenger.showSnackBar(SnackBar(
                        content: Text(u == null ? 'Nothing to undo' : 'Undone')));
                  },
                ),
            ]),
            const SizedBox(height: 16),
            WhyDuePanel(v.explanation),
          ],
          if (v.source != null) ...[
            const SizedBox(height: 16),
            SourceCard(source: v.source!, owner: v.sourceOwner!),
          ],
          if (v.children.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(n.kind == NodeKind.topic ? 'Tasks' : 'Subtasks', style: text.titleSmall),
            for (final c in v.children)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.title),
                subtitle: c.positionText == null ? null : Text(c.positionText!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/item/${c.id}'),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (n.kind == NodeKind.topic)
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add task'),
                onPressed: () => context.push('/add?parent=${n.id}'),
              ),
            if (n.kind == NodeKind.task && v.canAddChild_)
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add subtask'),
                onPressed: () => context.push('/add?parent=${n.id}&kind=subtask'),
              ),
            if (v.canSplit_)
              OutlinedButton.icon(
                key: const Key('item-split'),
                icon: const Icon(Icons.call_split),
                label: const Text('Split into chapters'),
                onPressed: () => context.push('/add/split/${n.id}'),
              ),
            if (n.kind == NodeKind.task && !v.canSplit_)
              OutlinedButton.icon(
                icon: const Icon(Icons.library_add),
                label: const Text('Create a new task with chapters'),
                onPressed: () => context.push('/add?subject=${n.subjectId}&split=1'),
              ),
          ]),
          if (v.reviewable && v.explanation.recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('History', style: text.titleSmall),
            HistoryList(v.explanation.recent),
          ],
        ],
      ),
    );
  }
}
