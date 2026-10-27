import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/integrity.dart';

import 'helpers.dart';

void main() {
  late Fixture f;
  late AppDatabase db;

  setUp(() async {
    f = Fixture();
    db = f.db;
    await f.seedTree();
  });
  tearDown(() => f.close());

  Future<ItemState> state(String id) => db.itemStateDao.stateOf(id);
  Future<bool> done(String id) async {
    final rows = (await db.plansDao.planFor(day0))!.rows;
    return rows.firstWhere((r) => r.nodeId == id).doneAtUtc != null;
  }

  group('first study and review', () {
    test('first study: Unread → Red, due tomorrow, plan row done', () async {
      await f.planWith(day0, ['st1']);
      final e = await f.writer.writeFirstStudy('st1', 25, sessionId: null);
      expect(e.localDate, day0);
      expect(e.tzId, 'Asia/Kolkata');
      expect(await state('st1'),
          ItemState(belt: Belt.red, ladderDue: day0.plusDays(1), lastReviewDate: day0));
      expect(await done('st1'), isTrue);
      expect((await db.eventsDao.eventsFor('st1')).single, isA<FirstStudy>());
    });

    test('reviews follow the ladder and count', () async {
      await f.writer.writeFirstStudy('st1', 30);
      f.clock.advance(const Duration(days: 1));
      final solid = await f.writer.writeReview('st1', Grade.solid, 8);
      expect(solid.outcome.beltAfter, Belt.orange);
      f.clock.advance(const Duration(days: 3));
      await f.writer.writeReview('st1', Grade.forgot, 8);
      final s = await state('st1');
      expect(s.belt, Belt.red);
      expect(s.reviewCount, 2);
      expect(s.ladderDue, day0.plusDays(5));
      expect(s.lastReviewDate, day0.plusDays(4));
    });

    test('the study day starts at 04:00 local', () async {
      // 23:15 UTC on 1 Mar = 04:45 IST on 2 Mar; 22:00 UTC = 03:30 IST → still 1 Mar.
      f.clock.set(DateTime.utc(2026, 3, 1, 22));
      expect((await f.writer.writeFirstStudy('st1', 30)).localDate, day0);
      f.clock.set(DateTime.utc(2026, 3, 1, 23, 15));
      expect((await f.writer.writeFirstStudy('st2', 30)).localDate, day0.plusDays(1));
    });

    test('refuses what the rules forbid, writing nothing', () async {
      final w = f.writer;
      await expectLater(w.writeReview('st1', Grade.solid, 5), throwsStateError);
      await expectLater(w.writeFirstStudy('t1', 30), throwsStateError); // topic
      await expectLater(w.writeFirstStudy('k1', 30), throwsStateError); // has subtasks
      await expectLater(w.writeFirstStudy('nope', 30), throwsStateError);
      await w.writeFirstStudy('st1', 30);
      await expectLater(w.writeFirstStudy('st1', 30), throwsStateError);
      await db.nodesDao.softDelete('st2', t0);
      await expectLater(w.writeFirstStudy('st2', 30), throwsStateError);
      expect(await db.eventsDao.countFor('st1'), 1);
      expect(await db.eventsDao.countFor('st2'), 0);
    });
  });

  group('undo', () {
    test('steps back one event at a time and clears the plan row', () async {
      await f.planWith(day0, ['st1']);
      final w = f.writer;
      await w.writeFirstStudy('st1', 30);
      await w.writeReview('st1', Grade.solid, 8);
      expect(await done('st1'), isTrue);

      final u1 = await w.writeUndoLatest('st1');
      expect(u1!.targetId, isNot(u1.id));
      expect((await state('st1')).belt, Belt.red);
      expect(await done('st1'), isFalse);

      await w.writeUndoLatest('st1');
      expect(await state('st1'), ItemState.unread);
      expect(await w.writeUndoLatest('st1'), isNull);
      expect(await db.eventsDao.countFor('st1'), 4);

      final latest = await db.eventsDao.lastN('st1', 2);
      expect([for (final e in latest) e.typeKey], ['undo', 'undo']);
    });
  });

  group('catch-up batches', () {
    test('reschedule keeps belts; undoBatch skips nodes studied since', () async {
      final w = f.writer;
      await w.writeFirstStudy('st1', 30);
      await w.writeFirstStudy('st2', 30);
      final moved = await w.writeRescheduleBatch(
          {'st1': day0.plusDays(3), 'st2': day0.plusDays(4)}, 'b1');
      expect(moved, hasLength(2));
      expect(await state('st1'),
          ItemState(belt: Belt.red, ladderDue: day0.plusDays(3), lastReviewDate: day0));
      expect(await db.eventsDao.byBatch('b1'), hasLength(2));

      await w.writeReview('st2', Grade.solid, 8);
      expect(await w.undoBatch('b1'), 1);
      expect((await state('st1')).ladderDue, day0.plusDays(1));
      expect((await state('st2')).belt, Belt.orange);
      expect(await w.undoBatch('b1'), 0);
    });
  });

  group('deleteSubjectsHard', () {
    test('removes one subject completely and keeps the other', () async {
      final w = f.writer;
      await f.subject('sub2', name: 'History', order: 2);
      await f.node('h1', 'sub2', NodeKind.task);
      await db.examsDao.insertExam(ExamsCompanion.insert(
          id: 'x1', name: 'MPSC', examDate: day0.plusDays(60), createdAt: t0));
      await db.subjectsDao.link('x1', 'sub1');
      await db.subjectsDao.link('x1', 'sub2');

      await db.sessionsDao.start('s1', 'st1', t0);
      await db.sessionsDao.finish('s1', t0, 30, edited: false);
      await w.writeFirstStudy('st1', 30, sessionId: 's1');
      await w.writeFirstStudy('h1', 30);
      await f.planWith(day0, ['k2', 'h1']);
      await db.settingsDao.setLastUsedSubjectId('sub1');
      await db.settingsDao.setLastUsedTopicId('t1');

      await w.deleteSubjectsHard({'sub1'});

      Future<int> count(String table) async => (await db
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');
      expect(await db.subjectsDao.byId('sub1'), isNull);
      expect(await count('study_nodes'), 1);
      expect(await count('review_events'), 1);
      expect(await count('item_state'), 1);
      expect(await count('study_sessions'), 0);
      expect(await count('day_plan_rows'), 1);
      expect([for (final s in await db.subjectsDao.forExam('x1')) s.id], ['sub2']);
      expect(await db.settingsDao.lastUsedSubjectId(), isNull);
      expect(await db.settingsDao.lastUsedTopicId(), isNull);
      expect((await runIntegrityCheck(db)).ok, isTrue);

      await w.deleteSubjectsHard({}); // no-op
      expect(await count('subjects'), 1);
    });

    test('keeps last-used settings that point elsewhere', () async {
      await f.subject('sub2');
      await f.node('t2', 'sub2', NodeKind.topic);
      await db.settingsDao.setLastUsedSubjectId('sub2');
      await db.settingsDao.setLastUsedTopicId('t2');
      await f.writer.deleteSubjectsHard({'sub1'});
      expect(await db.settingsDao.lastUsedSubjectId(), 'sub2');
      expect(await db.settingsDao.lastUsedTopicId(), 't2');
    });
  });
}
