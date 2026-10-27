import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/db_watch.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';

class TodayRow {
  const TodayRow({
    required this.entry,
    required this.node,
    required this.parentTitle,
    required this.state,
  });

  final DayPlanEntryRow entry;
  final NodeRow node;
  final String? parentTitle;
  final ItemState state;

  bool get done => entry.doneAtUtc != null;

  /// "Laxmikant · Ch 3" for a subtask; the task title otherwise.
  String get title => parentTitle == null ? node.title : '$parentTitle · ${node.title}';
}

class TodayView {
  const TodayView({required this.date, required this.header, required this.rows});

  final LocalDate date;
  final DayPlanHeaderRow header;
  final List<TodayRow> rows;

  int get reviewMinutes => _minutes(RowType.review);
  int get firstReadMinutes => _minutes(RowType.firstRead);
  int get waitingCount => header.waitingCount;
  int get doneMinutes =>
      rows.where((r) => r.done).fold(0, (s, r) => s + r.entry.estimatedMinutes);

  int _minutes(RowType t) => rows
      .where((r) => r.entry.rowType == t)
      .fold(0, (s, r) => s + r.entry.estimatedMinutes);

  String get summary => planSummary(reviewMinutes, firstReadMinutes, waitingCount);
}

/// Today's frozen plan with its items (design §10: Today watches the frozen
/// plan rows). Building the plan the first time it is read is part of this.
final todayViewProvider = StreamProvider.autoDispose<TodayView>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final plans = ref.watch(buildTodayPlanProvider);
  final today = ref.watch(todayProvider);
  return watchTables(db, {db.dayPlans, db.dayPlanRows, db.itemStates, db.studyNodes},
      () async {
    final plan = await plans.get();
    final rows = <TodayRow>[];
    for (final e in plan.rows) {
      final node = await db.nodesDao.byId(e.nodeId);
      if (node == null) continue;
      final parent = node.parentId == null ? null : await db.nodesDao.byId(node.parentId!);
      rows.add(TodayRow(
        entry: e,
        node: node,
        parentTitle: node.kind == NodeKind.subtask ? parent?.title : null,
        state: await db.itemStateDao.stateOf(node.id),
      ));
    }
    return TodayView(date: today, header: plan.header, rows: rows);
  });
});
