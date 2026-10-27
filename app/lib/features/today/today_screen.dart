import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/format.dart';
import '../../core/layout.dart';
import '../../core/providers.dart';
import '../../core/sheets.dart';
import '../../core/slots.dart';
import '../../core/widgets/belt_chip.dart';
import '../../core/widgets/minutes_text.dart';
import '../../core/widgets/two_pane.dart';
import 'today_providers.dart';
import 'widgets/backup_banner.dart';
import 'widgets/catch_up_card.dart';

/// Rows an open section shows before "Show all" (design D16).
const _shown = 5;

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(todayViewProvider);
    return TwoPane(
      pane: 'today',
      placeholder: 'Choose a row to see the item here',
      list: Scaffold(
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
          heroTag: 'fab-today',
          tooltip: 'Add',
          onPressed: () => context.push('/add'),
          child: const Icon(Icons.add),
        ),
        body: switch (view) {
          AsyncData(:final value) => _TodayBody(value),
          AsyncError(:final error) => Center(child: Text('Could not build the plan: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

class _TodayBody extends ConsumerWidget {
  const _TodayBody(this.view);
  final TodayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final banners = ref.watch(todayBannersProvider);
    final saved = ref.watch(todayOpenSectionsProvider).value;
    final open = saved ??
        {view.dueNow.isNotEmpty ? 'due' : (view.upNext.isNotEmpty ? 'next' : 'coming')};

    void toggle(String id) {
      final next = {...open};
      if (!next.remove(id)) next.add(id);
      ref.read(appDatabaseProvider).settingsDao.setTodayOpenSections(view.date, next);
    }

    String fitNote(List<TodayEntry> rows) {
      final fits = rows.where((r) => r.fits).length;
      return fits == rows.length ? '' : ' · $fits ${fits == 1 ? 'fits' : 'fit'} today';
    }

    int minutes(List<TodayEntry> rows) => rows.fold(0, (s, r) => s + r.minutes);
    final weekCount = view.comingUp
        .where((g) => g.bucket == UpcomingBucket.day)
        .fold(0, (s, g) => s + g.entries.length);
    final comingCount = view.comingUp.fold(0, (s, g) => s + g.entries.length);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(view.summary, key: const Key('today-summary'), style: text.titleMedium),
        ),
        ...banners,
        const CatchUpCard(),
        const BackupBanner(),
        if (!view.hasItems)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text('Nothing planned yet', style: text.titleMedium),
              const SizedBox(height: 8),
              FilledButton.tonal(
                  onPressed: () => context.push('/add'), child: const Text('Add more items')),
            ]),
          )
        else if (view.dueNow.isEmpty && view.upNext.isEmpty)
          Padding(
            key: const Key('today-all-done'),
            padding: const EdgeInsets.all(16),
            child: Text(
              view.comingUp.isEmpty
                  ? 'All done for today'
                  : 'All done for today · next review '
                      '${view.comingUp.first.label == 'Tomorrow' ? 'tomorrow' : view.comingUp.first.label}'
                      ' (${view.comingUp.first.entries.length})',
              style: text.bodyLarge,
            ),
          ),
        if (view.dueNow.isNotEmpty)
          _Section(
            id: 'due',
            title: 'Due now',
            detail: '${view.dueNow.length} · ${formatMinutes(minutes(view.dueNow))}'
                '${fitNote(view.dueNow)}',
            open: open.contains('due'),
            onToggle: toggle,
            child: _Rows(view.dueNow, budget: view.budget),
          ),
        if (view.upNext.isNotEmpty)
          _Section(
            id: 'next',
            title: 'Up next',
            detail: '${view.upNext.length} new · ${formatMinutes(minutes(view.upNext))}'
                '${fitNote(view.upNext)}',
            open: open.contains('next'),
            onToggle: toggle,
            child: _Rows(view.upNext, budget: view.budget),
          ),
        if (view.comingUp.isNotEmpty)
          _Section(
            id: 'coming',
            title: 'Coming up',
            detail: weekCount > 0
                ? '${_count(weekCount, 'review', 'reviews')} this week'
                : _count(comingCount, 'review', 'reviews'),
            open: open.contains('coming'),
            onToggle: toggle,
            child: Column(children: [
              for (final (i, g) in view.comingUp.indexed)
                _ComingGroup(g, today: view.date, initiallyOpen: i == 0),
            ]),
          ),
      ],
    );
  }
}

/// A collapsible section: one header line, and its rows when open.
class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.title,
    required this.detail,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String id;
  final String title;
  final String detail;
  final bool open;
  final void Function(String id) onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        ListTile(
          key: Key('section-$id'),
          onTap: () => onToggle(id),
          leading: Icon(open ? Icons.expand_more : Icons.chevron_right),
          title: Text(title.toUpperCase(), style: text.labelLarge),
          subtitle: Text(detail),
        ),
        if (open) child,
      ],
    );
  }
}

/// Rows of Due now or Up next: the plan's rows, the line, then the rest.
class _Rows extends StatefulWidget {
  const _Rows(this.rows, {required this.budget});
  final List<TodayEntry> rows;
  final int budget;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final shown = _all ? rows : rows.take(_shown).toList();
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      if (!shown[i].fits && (i == 0 || shown[i - 1].fits)) {
        children.add(_Line(widget.budget));
      }
      children.add(PlanRowTile(shown[i]));
    }
    if (shown.length < rows.length) {
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text('Show all ${rows.length}'),
          ),
        ),
      ));
    }
    return Column(children: children);
  }
}

/// The dashed line: rows below it don't fit today's minutes (design D16).
class _Line extends StatelessWidget {
  const _Line(this.budget);
  final int budget;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    final dashes = Expanded(
      child: LayoutBuilder(
        builder: (context, c) => Row(children: [
          for (var i = 0; i < c.maxWidth ~/ 8; i++)
            Container(
                width: 4, height: 1, color: color, margin: const EdgeInsets.only(right: 4)),
        ]),
      ),
    );
    return Padding(
      key: const Key('today-line'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        dashes,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('beyond today\'s ${formatMinutes(budget)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ),
        dashes,
      ]),
    );
  }
}

class _ComingGroup extends StatelessWidget {
  const _ComingGroup(this.group, {required this.today, required this.initiallyOpen});
  final ComingUpGroup group;
  final LocalDate today;
  final bool initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final done = g.doneToday > 0 ? ' (${g.doneToday} done today)' : '';
    return ExpansionTile(
      key: Key('coming-${g.label}'),
      initiallyExpanded: initiallyOpen,
      tilePadding: const EdgeInsets.only(left: 32, right: 16),
      title: Text(g.label),
      subtitle: Text(
          '${_count(g.entries.length, 'review', 'reviews')} · ${formatMinutes(g.minutes)}$done'),
      children: [
        for (final e in g.entries)
          _ComingRow(e, showDate: g.bucket != UpcomingBucket.day, today: today),
      ],
    );
  }
}

/// A Coming up row: view-only, it opens the item.
class _ComingRow extends ConsumerWidget {
  const _ComingRow(this.entry, {required this.showDate, required this.today});
  final TodayEntry entry;
  final bool showDate;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    return ListTile(
      key: Key('coming-row-${e.node.id}'),
      contentPadding: const EdgeInsets.only(left: 48, right: 16),
      selected: isOpenInPane(context, ref, e.node.id),
      onTap: () => openItem(context, ref, e.node.id),
      leading: e.doneToday
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.event_outlined),
      title: Text(e.title),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          BeltChip(e.state.belt, dense: true),
          MinutesText(e.minutes),
          if (showDate && e.due != null) Text(formatRelativeDay(e.due!, today)),
          if (e.doneToday) const Text('Done today'),
        ],
      ),
    );
  }
}

/// Without a timer: "Studied" for a first reading, "Review" otherwise.
Widget _defaultAction(BuildContext context, WidgetRef ref, TodayEntry r) {
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
  final TodayEntry row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final action = ref.watch(planRowActionProvider);
    final unread = r.state.belt == Belt.unread;
    final reason = r.daysOverdue > 0
        ? '${_count(r.daysOverdue, 'day', 'days')} overdue'
        : switch (r.reason) {
            Reason.firstRead => 'First reading',
            Reason.due || Reason.overdue => 'Due today',
            Reason.deadlineRisk => 'Exam soon',
            Reason.catchUp => 'Catch-up',
          };
    return ListTile(
      key: Key('plan-row-${r.node.id}'),
      selected: isOpenInPane(context, ref, r.node.id),
      onTap: () => openItem(context, ref, r.node.id),
      leading: const Icon(Icons.radio_button_unchecked),
      title: Text(r.title),
      // Wraps instead of overflowing on narrow rows (small phones, the
      // two-pane list).
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          BeltChip(r.state.belt, dense: true),
          MinutesText(r.minutes),
          Text(reason),
          if (r.node.positionText != null && r.node.positionText != r.node.title)
            Text(r.node.positionText!, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: action?.call(context, r.node.id, unread: unread) ??
          _defaultAction(context, ref, r),
    );
  }
}
