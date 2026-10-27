import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/sheets.dart';
import '../../core/slots.dart';
import '../../core/widgets/belt_chip.dart';
import '../../core/widgets/minutes_text.dart';
import 'today_providers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(todayViewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Refresh plan',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(buildTodayPlanProvider).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add',
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
      body: switch (view) {
        AsyncData(:final value) => _TodayBody(value),
        AsyncError(:final error) => Center(child: Text('Could not build the plan: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody(this.view);
  final TodayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final banners = ref.watch(todayBannersProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(view.summary, key: const Key('today-summary'), style: text.titleMedium),
        ),
        if (view.doneMinutes > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${formatMinutes(view.doneMinutes)} done', style: text.bodySmall),
          ),
        ...banners,
        if (view.waitingCount > 0)
          ListTile(
            key: const Key('today-waiting'),
            leading: const Icon(Icons.schedule),
            title: Text(
                '${view.waitingCount} ${view.waitingCount == 1 ? 'review' : 'reviews'} waiting'),
          ),
        if (view.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text('Nothing planned yet', style: text.titleMedium),
              const SizedBox(height: 8),
              FilledButton.tonal(
                  onPressed: () => context.push('/add'), child: const Text('Add more items')),
            ]),
          ),
        for (final r in view.rows) PlanRowTile(r),
        if (view.rows.isNotEmpty && view.rows.every((r) => r.done))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                  onPressed: () => context.push('/add'), child: const Text('Add more items')),
            ),
          ),
      ],
    );
  }
}

/// Without a timer: "Studied" for a first reading, "Review" otherwise.
Widget _defaultAction(BuildContext context, WidgetRef ref, TodayRow r) {
  final sheets = ref.read(appSheetsProvider);
  final unread = r.state.belt == Belt.unread;
  return FilledButton.tonal(
    key: Key('row-action-${r.node.id}'),
    onPressed: () => unread
        ? sheets.studied(context, r.node.id)
        : sheets.grade(context, r.node.id),
    child: Text(unread ? 'Studied' : 'Review'),
  );
}

class PlanRowTile extends ConsumerWidget {
  const PlanRowTile(this.row, {super.key});
  final TodayRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final action = ref.watch(planRowActionProvider);
    final unread = r.state.belt == Belt.unread;
    final reason = switch (r.entry.reason) {
      Reason.firstRead => 'First reading',
      Reason.due => 'Due',
      Reason.overdue => 'Overdue',
      Reason.deadlineRisk => 'Exam soon',
      Reason.catchUp => 'Catch-up',
    };
    return ListTile(
      key: Key('plan-row-${r.node.id}'),
      onTap: () => context.push('/item/${r.node.id}'),
      leading: r.done
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.radio_button_unchecked),
      title: Text(r.title,
          style: r.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
      subtitle: Row(children: [
        BeltChip(r.state.belt, dense: true),
        const SizedBox(width: 8),
        MinutesText(r.entry.estimatedMinutes),
        const SizedBox(width: 8),
        Flexible(child: Text(reason, overflow: TextOverflow.ellipsis)),
        if (r.node.positionText != null && r.node.positionText != r.node.title) ...[
          const SizedBox(width: 8),
          Flexible(child: Text(r.node.positionText!, overflow: TextOverflow.ellipsis)),
        ],
      ]),
      trailing: r.done
          ? null
          : action?.call(context, r.node.id, unread: unread) ??
              _defaultAction(context, ref, r),
    );
  }
}
