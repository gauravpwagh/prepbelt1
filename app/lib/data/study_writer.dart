// The only code that writes `review_events` (plan item 58). Each write runs in
// one transaction that appends the event, re-derives `item_state` with
// `deriveState`, and updates today's plan row.
import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import 'daos/events_dao.dart';
import 'db/app_database.dart';

class StudyWriter {
  StudyWriter(
    this._db, {
    required LocalDayClock dayClock,
    required String Function() newId,
    required String Function() tzId,
  })  : _dayClock = dayClock,
        _newId = newId,
        _tzId = tzId;

  final AppDatabase _db;
  final LocalDayClock _dayClock;
  final String Function() _newId;
  final String Function() _tzId;

  /// First reading of an Unread item: Unread → Red, due tomorrow.
  Future<FirstStudy> writeFirstStudy(String nodeId, int minutes,
          {String? sessionId}) =>
      _db.transaction(() async {
        await _requireReviewable(nodeId);
        final events = await _db.eventsDao.eventsFor(nodeId);
        if (deriveState(events).belt != Belt.unread) {
          throw StateError('Item $nodeId has already been studied.');
        }
        final (now, today) = _now();
        final e = FirstStudy(
          id: _newId(),
          nodeId: nodeId,
          atUtc: now,
          localDate: today,
          tzId: _tzId(),
          minutes: minutes,
          sessionId: sessionId,
          outcome: firstStudy(today),
        );
        await _append(e, events);
        await _db.plansDao.markDone(today, nodeId, now);
        return e;
      });

  /// A graded review; the belt moves by the rule in design §3.
  Future<Review> writeReview(String nodeId, Grade grade, int minutes,
          {String? sessionId}) =>
      _db.transaction(() async {
        await _requireReviewable(nodeId);
        final events = await _db.eventsDao.eventsFor(nodeId);
        final (now, today) = _now();
        final e = Review(
          id: _newId(),
          nodeId: nodeId,
          atUtc: now,
          localDate: today,
          tzId: _tzId(),
          grade: grade,
          minutes: minutes,
          sessionId: sessionId,
          outcome: review(deriveState(events), grade, today),
        );
        await _append(e, events);
        await _db.plansDao.markDone(today, nodeId, now);
        return e;
      });

  /// Undoes the node's newest event that is not an undo and not undone.
  /// Returns null, writing nothing, when there is none.
  Future<Undo?> writeUndoLatest(String nodeId) => _db.transaction(() async {
        final events = await _db.eventsDao.eventsFor(nodeId);
        final target = undoableEvent(events);
        if (target == null) return null;
        final (now, today) = _now();
        final e = await _undo(target, events, now, today);
        if (target is FirstStudy || target is Review) {
          await _db.plansDao.clearDone(today, nodeId);
        }
        return e;
      });

  /// Accepting catch-up: one `reschedule` per item, sharing [batchId]. Belts
  /// are unchanged.
  Future<List<Reschedule>> writeRescheduleBatch(
          Map<String, LocalDate> assignments, String batchId) =>
      _db.transaction(() async {
        final (now, today) = _now();
        final tz = _tzId();
        final written = <Reschedule>[];
        for (final MapEntry(key: nodeId, value: due) in assignments.entries) {
          final events = await _db.eventsDao.eventsFor(nodeId);
          final e = Reschedule(
            id: _newId(),
            nodeId: nodeId,
            atUtc: now,
            localDate: today,
            tzId: tz,
            batchId: batchId,
            outcome: reschedule(deriveState(events), due),
          );
          await _append(e, events);
          written.add(e);
        }
        return written;
      });

  /// Undo catch-up: undoes each event of the batch that is still its node's
  /// newest undoable event. Returns how many were undone.
  Future<int> undoBatch(String batchId) => _db.transaction(() async {
        final (now, today) = _now();
        var undone = 0;
        for (final b in await _db.eventsDao.byBatch(batchId)) {
          final events = await _db.eventsDao.eventsFor(b.nodeId);
          if (undoableEvent(events)?.id != b.id) continue;
          await _undo(b, events, now, today);
          undone++;
        }
        return undone;
      });

  /// "Archive and remove" (design §8a): the only hard delete in the app.
  /// Removes every row of [subjectIds] in the design's order and clears the
  /// last-used settings that point at removed rows.
  Future<void> deleteSubjectsHard(Set<String> subjectIds) async {
    if (subjectIds.isEmpty) return;
    final ids = subjectIds.toList();
    final marks = List.filled(ids.length, '?').join(', ');
    final args = [for (final id in ids) Variable.withString(id)];
    final nodesSql = 'SELECT id FROM study_nodes WHERE subject_id IN ($marks)';

    await _db.transaction(() async {
      final settings = _db.settingsDao;
      final topicId = await settings.lastUsedTopicId();
      if (topicId != null) {
        final topic = await _db.nodesDao.byId(topicId);
        if (topic != null && subjectIds.contains(topic.subjectId)) {
          await settings.setLastUsedTopicId(null);
        }
      }
      if (subjectIds.contains(await settings.lastUsedSubjectId())) {
        await settings.setLastUsedSubjectId(null);
      }

      Future<void> go(String sql, TableInfo<Table, Object?> table) => _db.customUpdate(sql,
          variables: args, updates: {table}, updateKind: UpdateKind.delete);
      await go('DELETE FROM day_plan_rows WHERE node_id IN ($nodesSql)',
          _db.dayPlanRows);
      await go('DELETE FROM review_events WHERE node_id IN ($nodesSql)',
          _db.reviewEvents);
      await go('DELETE FROM study_sessions WHERE node_id IN ($nodesSql)',
          _db.studySessions);
      await go('DELETE FROM item_state WHERE node_id IN ($nodesSql)',
          _db.itemStates);
      await go('DELETE FROM node_sources WHERE node_id IN ($nodesSql)',
          _db.nodeSources);
      await go('DELETE FROM study_nodes WHERE subject_id IN ($marks)',
          _db.studyNodes);
      await go('DELETE FROM exam_subjects WHERE subject_id IN ($marks)',
          _db.examSubjects);
      await go('DELETE FROM subjects WHERE id IN ($marks)', _db.subjects);
    });
  }

  (DateTime, LocalDate) _now() {
    final now = _dayClock.clock.nowUtc();
    return (now, _dayClock.dayOf(now));
  }

  Future<void> _requireReviewable(String nodeId) async {
    final node = await _db.nodesDao.byId(nodeId);
    if (node == null || node.deletedAt != null) {
      throw StateError('No live item $nodeId.');
    }
    final children = await _db.nodesDao.liveChildCount(nodeId);
    if (!isReviewable(node.kind, children)) {
      throw StateError('Item $nodeId is not reviewable.');
    }
  }

  Future<Undo> _undo(StudyEvent target, List<StudyEvent> events, DateTime now,
      LocalDate today) async {
    final e = Undo(
      id: _newId(),
      nodeId: target.nodeId,
      atUtc: now,
      localDate: today,
      tzId: _tzId(),
      targetId: target.id,
    );
    await _append(e, events);
    return e;
  }

  Future<void> _append(StudyEvent e, List<StudyEvent> before) async {
    await _db.into(_db.reviewEvents).insert(toEventRow(e));
    await _db.itemStateDao.upsert(e.nodeId, deriveState([...before, e]));
  }
}
