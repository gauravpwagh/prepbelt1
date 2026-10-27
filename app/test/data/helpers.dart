import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/study_writer.dart';

/// A fresh in-memory database with the full schema and PRAGMAs applied.
AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// 06:00 UTC = 11:30 in Asia/Kolkata, on study day 2026-03-01.
final t0 = DateTime.utc(2026, 3, 1, 6);
const day0 = LocalDate(2026, 3, 1);
const ist = Duration(hours: 5, minutes: 30);

/// A database, a fixed clock at [t0], and a [StudyWriter] with sequential IDs.
class Fixture {
  Fixture() : db = memoryDb(), clock = FixedClock(t0) {
    dayClock = LocalDayClock(clock, (_) => ist);
    writer = StudyWriter(db,
        dayClock: dayClock, newId: newId, tzId: () => 'Asia/Kolkata');
  }

  final AppDatabase db;
  final FixedClock clock;
  late final LocalDayClock dayClock;
  late final StudyWriter writer;

  var _next = 0;
  String newId() => 'g${(_next++).toString().padLeft(4, '0')}';

  Future<void> close() => db.close();

  Future<void> subject(String id, {String? name, int order = 0}) =>
      db.subjectsDao.insertSubject(SubjectsCompanion.insert(
          id: id, name: name ?? id, sortOrder: order, createdAt: t0));

  Future<void> node(String id, String subjectId, NodeKind kind,
      {String? parent, int order = 0, int base = 30, int created = 0}) {
    final topic = kind == NodeKind.topic;
    return db.nodesDao.insertNode(StudyNodesCompanion.insert(
      id: id,
      subjectId: subjectId,
      parentId: Value(parent),
      kind: kind,
      taskKind: Value(topic ? null : TaskKind.reading),
      title: id,
      baseMinutes: Value(topic ? null : base),
      sortOrder: order,
      createdAt: t0.add(Duration(milliseconds: created)),
    ));
  }

  /// Subject `sub1` (order 1): topic `t1` → task `k1` → subtasks `st1`, `st2`;
  /// plus top-level task `k2`.
  Future<void> seedTree() async {
    await subject('sub1', name: 'Polity', order: 1);
    await node('t1', 'sub1', NodeKind.topic, order: 2);
    await node('k1', 'sub1', NodeKind.task, parent: 't1', order: 3);
    await node('st1', 'sub1', NodeKind.subtask, parent: 'k1', order: 0);
    await node('st2', 'sub1', NodeKind.subtask, parent: 'k1', order: 1);
    await node('k2', 'sub1', NodeKind.task, order: 4);
  }

  /// An empty frozen plan for [date] with one open row per node.
  Future<void> planWith(LocalDate date, List<String> nodeIds) =>
      db.plansDao.savePlan(
        date,
        DayPlan(
          rows: [
            for (final id in nodeIds)
              PlanRow(id, RowType.review, 10, Reason.due),
          ],
          reviewMinutes: 10 * nodeIds.length,
          firstReadMinutes: 0,
          waitingNodeIds: const [],
          waitingMinutes: 0,
          reviewShare: 60,
          reserve: 30,
          splitSuggested: const [],
          summary: '',
        ),
        budget: 90,
        builtAt: t0,
      );
}
