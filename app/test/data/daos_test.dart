import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';
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

  ReviewEventsCompanion event(String id, String type,
          {Grade? grade,
          int? minutes,
          Belt? before,
          Belt? after,
          int? interval,
          LocalDate? due,
          String? undoes,
          String? batch,
          String node = 'st1'}) =>
      ReviewEventsCompanion.insert(
        id: id,
        nodeId: node,
        eventType: type,
        atUtc: t0,
        localDate: day0,
        tzId: 'Asia/Kolkata',
        grade: Value(grade),
        minutes: Value(minutes),
        beltBefore: Value(before),
        beltAfter: Value(after),
        intervalDays: Value(interval),
        ladderDueAfter: Value(due),
        undoesEventId: Value(undoes),
        batchId: Value(batch),
      );
  Future<void> insert(ReviewEventsCompanion e) =>
      db.into(db.reviewEvents).insert(e);
  final tomorrow = day0.plusDays(1);

  group('event CHECKs', () {
    test('first_study without a session is valid', () async {
      await insert(event('e1', 'first_study',
          minutes: 30, before: Belt.unread, after: Belt.red, interval: 1, due: tomorrow));
      expect(await db.eventsDao.countFor('st1'), 1);
    });

    test('each event type rejects the wrong columns', () async {
      final bad = [
        // first_study needs minutes and Unread → Red with interval 1.
        event('b1', 'first_study',
            before: Belt.unread, after: Belt.red, interval: 1, due: tomorrow),
        event('b2', 'first_study',
            minutes: 30, before: Belt.red, after: Belt.red, interval: 1, due: tomorrow),
        // review needs a grade.
        event('b3', 'review',
            minutes: 5, before: Belt.red, after: Belt.orange, interval: 3, due: tomorrow),
        // reschedule needs a batch and keeps the belt.
        event('b4', 'reschedule', before: Belt.red, after: Belt.red, due: tomorrow),
        event('b5', 'reschedule',
            before: Belt.red, after: Belt.orange, due: tomorrow, batch: 'x'),
        // undo carries only its target.
        event('b6', 'undo', undoes: null),
        event('b7', 'undo', before: Belt.red, after: Belt.red),
        // unknown type; interval below 1.
        event('b8', 'bogus'),
        event('b9', 'review',
            grade: Grade.solid, minutes: 5, before: Belt.red, after: Belt.orange,
            interval: 0, due: tomorrow),
      ];
      for (final e in bad) {
        await expectLater(insert(e), throwsA(isA<SqliteException>()),
            reason: e.id.value);
      }
    });

    test('foreign keys are enforced', () async {
      await expectLater(
          insert(event('e1', 'first_study',
              node: 'nope', minutes: 30, before: Belt.unread, after: Belt.red,
              interval: 1, due: tomorrow)),
          throwsA(isA<SqliteException>()));
    });
  });

  group('sessions', () {
    test('at most one open session', () async {
      final s = db.sessionsDao;
      await s.start('s1', 'st1', t0);
      await expectLater(s.start('s2', 'st2', t0), throwsA(isA<SqliteException>()));
      expect((await s.open())!.id, 's1');

      await s.finish('s1', t0.add(const Duration(minutes: 25)), 25, edited: true);
      expect(await s.open(), isNull);
      await s.start('s3', 'st2', t0);
      await s.discard('s3', t0);
      final rows = await db.select(db.studySessions).get();
      expect({for (final r in rows) r.id: (r.confirmedMinutes, r.edited, r.discarded)}, {
        's1': (25, true, false),
        's3': (null, false, true),
      });
    });
  });

  group('nodes', () {
    test('rollup CTE returns reviewable leaf belts', () async {
      await f.writer.writeFirstStudy('st1', 30);
      final n = db.nodesDao;
      expect(await n.leafBelts('k1'), unorderedEquals([Belt.red, Belt.unread]));
      expect(await n.leafBelts('t1'), unorderedEquals([Belt.red, Belt.unread]));
      expect(await n.subjectLeafBelts('sub1'),
          unorderedEquals([Belt.red, Belt.unread, Belt.unread]));
      expect(rollup(await n.leafBelts('t1')).weakestStarted, Belt.red);

      await n.softDelete('st2', t0);
      expect(await n.leafBelts('k1'), [Belt.red]);

      // A task whose subtasks are all deleted becomes a leaf itself.
      await n.softDelete('st1', t0);
      expect(await n.leafBelts('k1'), [Belt.unread]);
    });

    test('soft delete covers descendants and hides them', () async {
      final n = db.nodesDao;
      await n.softDelete('t1', t0);
      for (final id in ['t1', 'k1', 'st1', 'st2']) {
        expect((await n.byId(id))!.deletedAt, t0, reason: id);
      }
      expect([for (final r in await n.roots('sub1')) r.id], ['k2']);
      expect(await n.watchTree('sub1').first, hasLength(1));
      expect(await n.leafBelts('t1'), isEmpty);
    });

    test('children, counts and sort keys', () async {
      final n = db.nodesDao;
      expect([for (final c in await n.children('k1')) c.id], ['st1', 'st2']);
      expect(await n.liveChildCount('k1'), 2);
      expect([for (final r in await n.roots('sub1')) r.id], ['t1', 'k2']);

      final keys = await n.sortKeys();
      expect(keys.keys, unorderedEquals(['st1', 'st2', 'k2']));
      final st2 = keys['st2']!;
      expect([st2.subjectOrder, st2.topicOrder, st2.taskOrder, st2.subtaskOrder],
          [1, 2, 3, 1]);
      final k2 = keys['k2']!;
      expect([k2.topicOrder, k2.taskOrder, k2.subtaskOrder], [0, 4, 0]);
      expect(keys['st1']!.compareTo(st2), lessThan(0));
    });

    test('base_minutes and topic columns are checked', () async {
      await expectLater(f.node('x', 'sub1', NodeKind.task, base: 60),
          throwsA(isA<SqliteException>()));
      await expectLater(
          db.into(db.studyNodes).insert(StudyNodesCompanion.insert(
              id: 'y', subjectId: 'sub1', kind: NodeKind.topic,
              baseMinutes: const Value(30), title: 'y', sortOrder: 0, createdAt: t0)),
          throwsA(isA<SqliteException>()));
    });
  });

  group('item state', () {
    test('missing rows read as Unread; allReviewable lists only leaves', () async {
      expect(await db.itemStateDao.stateOf('st1'), ItemState.unread);
      await f.writer.writeFirstStudy('st1', 30);
      final all = await db.itemStateDao.allReviewable();
      expect(all.keys, unorderedEquals(['st1', 'st2', 'k2']));
      expect(all['st1'],
          ItemState(belt: Belt.red, ladderDue: tomorrow, lastReviewDate: day0));
      expect(all['k2'], ItemState.unread);
      expect((await db.itemStateDao.watch('st1').first).belt, Belt.red);
    });
  });

  group('subjects and exams', () {
    test('Inbox is created once and only once', () async {
      final s = db.subjectsDao;
      final a = await s.ensureInbox(newId: f.newId, now: t0);
      final b = await s.ensureInbox(newId: f.newId, now: t0);
      expect(b.id, a.id);
      expect(a.isInbox, isTrue);
      await expectLater(
          s.insertSubject(SubjectsCompanion.insert(
              id: 'i2', name: 'Inbox', sortOrder: 9, isInbox: const Value(true),
              createdAt: t0)),
          throwsA(isA<SqliteException>()));
      expect(await s.nextSortOrder(), 2);
      expect([for (final r in await s.findByName('Polity')) r.id], ['sub1']);
    });

    test('links, active exams and exams for a subject', () async {
      final e = db.examsDao;
      await e.insertExam(ExamsCompanion.insert(
          id: 'x2', name: 'UPSC', examDate: const LocalDate(2026, 6, 1), createdAt: t0));
      await e.insertExam(ExamsCompanion.insert(
          id: 'x1', name: 'MPSC', examDate: const LocalDate(2026, 5, 1), createdAt: t0));
      await db.subjectsDao.link('x1', 'sub1');
      await db.subjectsDao.link('x1', 'sub1'); // no-op
      await db.subjectsDao.link('x2', 'sub1');
      expect([for (final x in await e.examsForSubject('sub1')) x.id], ['x1', 'x2']);
      expect([for (final s in await db.subjectsDao.forExam('x1')) s.id], ['sub1']);

      await e.updateExam('x2', ExamsCompanion(archivedAt: Value(t0)));
      expect([for (final x in await e.watchActive().first) x.id], ['x1']);

      await db.subjectsDao.unlink('x1', 'sub1');
      await e.deleteExam('x2');
      expect(await e.examsForSubject('sub1'), isEmpty);
      expect(await e.byId('x2'), isNull);
    });
  });

  group('sources', () {
    test('relink candidates and folder reset', () async {
      final s = db.sourcesDao;
      await s.insertFolder(SourceFoldersCompanion.insert(
          id: 'f1', treeUri: const Value('content://tree/1'), displayName: 'Books',
          purpose: FolderPurpose.sources, grantedAt: t0));
      NodeSourcesCompanion add(String node, SourceType type, LinkStatus status,
              {String? file}) =>
          NodeSourcesCompanion.insert(
              nodeId: node, sourceType: type, linkStatus: status,
              fileName: Value(file), folderId: Value(file == null ? null : 'f1'));
      await s.upsertSource(add('st1', SourceType.pdf, LinkStatus.needsRelink, file: 'a.pdf'));
      await s.upsertSource(add('st2', SourceType.pdf, LinkStatus.notLinked, file: 'b.pdf'));
      await s.upsertSource(add('k2', SourceType.book, LinkStatus.notLinked));
      expect([for (final c in await s.relinkCandidates()) c.nodeId],
          unorderedEquals(['st1', 'st2']));

      await s.setLinkStatus('st1', LinkStatus.ok);
      expect((await s.sourceFor('st1'))!.linkStatus, LinkStatus.ok);
      await s.setTreeUri('f1', null);
      expect((await s.folders(FolderPurpose.sources)).single.treeUri, isNull);
      await expectLater(s.deleteFolder('f1'), throwsA(isA<SqliteException>()));
      await s.deleteSource('st1');
      expect(await s.sourceFor('st1'), isNull);
    });
  });

  group('plans', () {
    test('refresh keeps done rows and the catch-up state', () async {
      final p = db.plansDao;
      await f.planWith(day0, ['st1', 'st2']);
      expect(await p.markDone(day0, 'st1', t0), isTrue);
      expect(await p.markDone(day0, 'k2', t0), isFalse);
      await p.setCatchUp(day0, CatchUpState.accepted, batchId: 'b1');

      await f.planWith(day0, ['k2']);
      final plan = (await p.planFor(day0))!;
      expect([for (final r in plan.rows) (r.position, r.nodeId, r.doneAtUtc != null)],
          [(0, 'st1', true), (1, 'k2', false)]);
      expect(plan.header.catchUpState, CatchUpState.accepted);
      expect(plan.header.catchUpBatchId, 'b1');
      expect([for (final d in await p.doneRows(day0)) d.nodeId], ['st1']);

      await p.addDoneRow(day0, 'st2', RowType.firstRead, 30, Reason.firstRead, t0);
      await p.clearDone(day0, 'st1');
      expect([for (final d in await p.doneRows(day0)) d.nodeId], ['st2']);
      expect(await p.planFor(day0.plusDays(1)), isNull);
    });
  });

  group('settings', () {
    test('defaults, round trips and ranges', () async {
      final s = db.settingsDao;
      expect(await s.dailyMinutes(), 90);
      expect(await s.dayStartHour(), 4);
      expect(await s.reminderTime(), (hour: 7, minute: 0));
      expect(await s.onboardingDone(), isFalse);
      expect(await s.lastBackupAtUtc(), isNull);

      await s.setDailyMinutes(120);
      await s.setDayStartHour(3);
      await s.setReminderTime(6, 5);
      await s.setOnboardingDone(true);
      await s.setLastBackupAtUtc(t0);
      await s.setBackupFolderId('f1');
      await s.setLastUsedSubjectId('sub1');
      await s.setLastUsedTopicId('t1');
      expect(await s.dailyMinutes(), 120);
      expect(await s.dayStartHour(), 3);
      expect(await s.reminderTime(), (hour: 6, minute: 5));
      expect(await s.onboardingDone(), isTrue);
      expect(await s.lastBackupAtUtc(), t0);
      expect(await s.backupFolderId(), 'f1');
      expect(await s.lastUsedSubjectId(), 'sub1');
      expect(await s.lastUsedTopicId(), 't1');

      expect(() => s.setDailyMinutes(10), throwsRangeError);
      expect(() => s.setDailyMinutes(601), throwsRangeError);
      expect(() => s.setDayStartHour(24), throwsRangeError);
      expect(() => s.setReminderTime(7, 60), throwsRangeError);
    });
  });

  group('integrity', () {
    test('a healthy database passes', () async {
      await db.sessionsDao.start('s1', 'st1', t0);
      final r = await runIntegrityCheck(db);
      expect(r.ok, isTrue, reason: '$r');
      expect(r.openSessions, 1);
      expect('$r', 'Integrity OK');
    });

    test('reports foreign key violations', () async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
          "INSERT INTO item_state (node_id, belt, review_count) VALUES ('ghost', 'red', 0)");
      await db.customStatement('PRAGMA foreign_keys = ON');
      final r = await runIntegrityCheck(db);
      expect(r.ok, isFalse);
      expect(r.foreignKeyViolations.single, contains('item_state'));
      expect('$r', startsWith('Integrity problems'));
    });
  });
}
