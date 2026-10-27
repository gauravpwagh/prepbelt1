import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import '../db/tables.dart';

part 'plans_dao.g.dart';

/// A frozen day plan as stored: its header and its rows in position order.
typedef StoredPlan = ({DayPlanHeaderRow header, List<DayPlanEntryRow> rows});

@DriftAccessor(tables: [DayPlans, DayPlanRows])
class PlansDao extends DatabaseAccessor<AppDatabase> with _$PlansDaoMixin {
  PlansDao(super.db);

  SimpleSelectStatement<$DayPlanRowsTable, DayPlanEntryRow> _rowsOf(
          LocalDate date) =>
      select(dayPlanRows)
        ..where((r) => r.localDate.equalsValue(date))
        ..orderBy([(r) => OrderingTerm.asc(r.position)]);

  Future<StoredPlan?> planFor(LocalDate date) async {
    final header = await (select(dayPlans)
          ..where((p) => p.localDate.equalsValue(date)))
        .getSingleOrNull();
    if (header == null) return null;
    return (header: header, rows: await _rowsOf(date).get());
  }

  Stream<List<DayPlanEntryRow>> watchRows(LocalDate date) =>
      _rowsOf(date).watch();

  /// Saves [plan] as the frozen plan for [date]. Done rows already stored for
  /// that day are kept where they are (Refresh, design §4); the new rows,
  /// which `buildPlan` never repeats for done items, follow them. The
  /// catch-up state of an existing header is kept.
  Future<void> savePlan(LocalDate date, DayPlan plan,
          {required int budget, required DateTime builtAt}) =>
      transaction(() async {
        await into(dayPlans).insert(
          DayPlansCompanion.insert(
            localDate: date,
            budgetMinutes: budget,
            reviewMinutes: plan.reviewMinutes,
            firstReadMinutes: plan.firstReadMinutes,
            waitingCount: plan.waitingCount,
            waitingMinutes: plan.waitingMinutes,
            builtAtUtc: builtAt,
          ),
          onConflict: DoUpdate((_) => DayPlansCompanion(
                budgetMinutes: Value(budget),
                reviewMinutes: Value(plan.reviewMinutes),
                firstReadMinutes: Value(plan.firstReadMinutes),
                waitingCount: Value(plan.waitingCount),
                waitingMinutes: Value(plan.waitingMinutes),
                builtAtUtc: Value(builtAt),
              )),
        );
        await (delete(dayPlanRows)
              ..where((r) => r.localDate.equalsValue(date) & r.doneAtUtc.isNull()))
            .go();
        var position = await _nextPosition(date);
        await batch((b) => b.insertAll(dayPlanRows, [
              for (final row in plan.rows)
                DayPlanRowsCompanion.insert(
                  localDate: date,
                  position: position++,
                  nodeId: row.nodeId,
                  rowType: row.type,
                  estimatedMinutes: row.minutes,
                  reason: row.reason,
                ),
            ]));
      });

  Future<int> _nextPosition(LocalDate date) async {
    final max = dayPlanRows.position.max();
    final row = await (selectOnly(dayPlanRows)
          ..addColumns([max])
          ..where(dayPlanRows.localDate.equalsValue(date)))
        .getSingle();
    final m = row.read(max);
    return m == null ? 0 : m + 1;
  }

  /// Marks [nodeId]'s open row on [date] done. Returns false when the node has
  /// no open row that day.
  Future<bool> markDone(LocalDate date, String nodeId, DateTime at) async {
    final n = await (update(dayPlanRows)
          ..where((r) =>
              r.localDate.equalsValue(date) &
              r.nodeId.equals(nodeId) &
              r.doneAtUtc.isNull()))
        .write(DayPlanRowsCompanion(doneAtUtc: Value(at)));
    return n > 0;
  }

  /// Clears `done_at_utc` on [nodeId]'s row on [date] (Undo, design §3).
  Future<void> clearDone(LocalDate date, String nodeId) => (update(dayPlanRows)
        ..where((r) => r.localDate.equalsValue(date) & r.nodeId.equals(nodeId)))
      .write(const DayPlanRowsCompanion(doneAtUtc: Value(null)));

  /// Appends a row that is already done, for an item studied outside the
  /// plan. The day's header must exist.
  Future<void> addDoneRow(LocalDate date, String nodeId, RowType type,
      int minutes, Reason reason, DateTime at) async {
    await into(dayPlanRows).insert(DayPlanRowsCompanion.insert(
      localDate: date,
      position: await _nextPosition(date),
      nodeId: nodeId,
      rowType: type,
      estimatedMinutes: minutes,
      reason: reason,
      doneAtUtc: Value(at),
    ));
  }

  /// Done rows of [date], as `PlanInput.done` for a refresh.
  Future<List<DoneRow>> doneRows(LocalDate date) async => [
        for (final r in await (_rowsOf(date)..where((r) => r.doneAtUtc.isNotNull()))
            .get())
          DoneRow(r.nodeId, r.rowType, r.estimatedMinutes),
      ];

  Future<void> setCatchUp(LocalDate date, CatchUpState state,
          {String? batchId}) =>
      (update(dayPlans)..where((p) => p.localDate.equalsValue(date))).write(
          DayPlansCompanion(
              catchUpState: Value(state), catchUpBatchId: Value(batchId)));
}
