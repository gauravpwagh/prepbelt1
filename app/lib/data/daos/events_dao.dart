import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'events_dao.g.dart';

/// Read-only access to the event log. Only `StudyWriter` writes events.
@DriftAccessor(tables: [ReviewEvents])
class EventsDao extends DatabaseAccessor<AppDatabase> with _$EventsDaoMixin {
  EventsDao(super.db);

  // Ties on `at_utc` fall back to insertion order, as `deriveState` expects.
  static const _rowid = CustomExpression<int>('rowid');

  /// Every event of [nodeId], oldest first.
  Future<List<StudyEvent>> eventsFor(String nodeId) async => [
        for (final r in await (select(reviewEvents)
              ..where((e) => e.nodeId.equals(nodeId))
              ..orderBy([
                (e) => OrderingTerm.asc(e.atUtc),
                (_) => OrderingTerm.asc(_rowid),
              ]))
            .get())
          toStudyEvent(r),
      ];

  /// The newest [n] events of [nodeId], newest first.
  Future<List<StudyEvent>> lastN(String nodeId, int n) async => [
        for (final r in await (select(reviewEvents)
              ..where((e) => e.nodeId.equals(nodeId))
              ..orderBy([
                (e) => OrderingTerm.desc(e.atUtc),
                (_) => OrderingTerm.desc(_rowid),
              ])
              ..limit(n))
            .get())
          toStudyEvent(r),
      ];

  /// The `reschedule` events of one catch-up batch.
  Future<List<StudyEvent>> byBatch(String batchId) async => [
        for (final r in await (select(reviewEvents)
              ..where((e) => e.batchId.equals(batchId))
              ..orderBy([(_) => OrderingTerm.asc(_rowid)]))
            .get())
          toStudyEvent(r),
      ];

  /// All events of [nodeId], undos included (`canAddChild`, `canSplit`).
  Future<int> countFor(String nodeId) async {
    final count = reviewEvents.id.count();
    final row = await (selectOnly(reviewEvents)
          ..addColumns([count])
          ..where(reviewEvents.nodeId.equals(nodeId)))
        .getSingle();
    return row.read(count)!;
  }
}

/// Maps a stored row to its `prep_core` event.
StudyEvent toStudyEvent(EventRow r) {
  Outcome outcome() => Outcome(
        beltBefore: r.beltBefore!,
        beltAfter: r.beltAfter!,
        intervalDays: r.intervalDays,
        ladderDue: r.ladderDueAfter,
        explanation: r.explanation ?? '',
      );
  return switch (r.eventType) {
    'first_study' => FirstStudy(
        id: r.id,
        nodeId: r.nodeId,
        atUtc: r.atUtc,
        localDate: r.localDate,
        tzId: r.tzId,
        minutes: r.minutes!,
        sessionId: r.sessionId,
        outcome: outcome()),
    'review' => Review(
        id: r.id,
        nodeId: r.nodeId,
        atUtc: r.atUtc,
        localDate: r.localDate,
        tzId: r.tzId,
        grade: r.grade!,
        minutes: r.minutes!,
        sessionId: r.sessionId,
        outcome: outcome()),
    'reschedule' => Reschedule(
        id: r.id,
        nodeId: r.nodeId,
        atUtc: r.atUtc,
        localDate: r.localDate,
        tzId: r.tzId,
        batchId: r.batchId!,
        outcome: outcome()),
    'undo' => Undo(
        id: r.id,
        nodeId: r.nodeId,
        atUtc: r.atUtc,
        localDate: r.localDate,
        tzId: r.tzId,
        targetId: r.undoesEventId!),
    _ => throw StateError('Unknown event type ${r.eventType}'),
  };
}

/// Maps a `prep_core` event to an insertable row.
ReviewEventsCompanion toEventRow(StudyEvent e) {
  final o = e.outcome;
  final (minutes, sessionId) = switch (e) {
    FirstStudy(:final minutes, :final sessionId) => (minutes, sessionId),
    Review(:final minutes, :final sessionId) => (minutes, sessionId),
    _ => (null, null),
  };
  return ReviewEventsCompanion.insert(
    id: e.id,
    nodeId: e.nodeId,
    eventType: e.typeKey,
    atUtc: e.atUtc,
    localDate: e.localDate,
    tzId: e.tzId,
    grade: Value(e is Review ? e.grade : null),
    minutes: Value(minutes),
    sessionId: Value(sessionId),
    beltBefore: Value(o?.beltBefore),
    beltAfter: Value(o?.beltAfter),
    intervalDays: Value(o?.intervalDays),
    ladderDueAfter: Value(o?.ladderDue),
    explanation: Value(o?.explanation),
    undoesEventId: Value(e is Undo ? e.targetId : null),
    batchId: Value(e is Reschedule ? e.batchId : null),
    schedulerVersion: const Value(schedulerVersion),
  );
}
