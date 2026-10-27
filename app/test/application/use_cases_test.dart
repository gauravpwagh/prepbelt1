import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/application/add_item.dart';
import 'package:prepbelt/application/complete_onboarding.dart';
import 'package:prepbelt/application/move_item.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';

import 'app_helpers.dart';

void main() {
  late Fixture f;
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    f = Fixture();
    db = f.db;
    c = containerFor(f);
  });
  tearDown(() async {
    c.dispose();
    await f.close();
  });

  Future<String> exam(String name, int inDays, Set<String> subjects) =>
      c.read(saveExamProvider).create(name, day0.plusDays(inDays), subjects);

  group('build_today_plan', () {
    test('plans first readings, skips the Inbox and freezes the plan', () async {
      await f.seedTree();
      await exam('MPSC', 60, {'sub1'});
      final inbox = await db.subjectsDao.ensureInbox(newId: f.newId, now: t0);
      await f.node('inboxed', inbox.id, NodeKind.task);

      final plan = await c.read(buildTodayPlanProvider).get();
      final ids = [for (final r in plan.rows) r.nodeId];
      expect(ids, isNot(contains('inboxed')));
      expect(ids, containsAllInOrder(['st1', 'st2']));
      expect(plan.rows.every((r) => r.rowType == RowType.firstRead), isTrue);
      expect(plan.header.budgetMinutes, 90);

      // Frozen: a new item does not appear until Refresh.
      await f.node('k3', 'sub1', NodeKind.task, order: 9);
      expect((await c.read(buildTodayPlanProvider).get()).rows.length, plan.rows.length);
    });

    test('refresh keeps done rows; due reviews come first, with reasons', () async {
      await f.seedTree();
      await exam('MPSC', 5, {'sub1'});
      await c.read(buildTodayPlanProvider).get();
      await c.read(markStudiedProvider)('st1', 30);
      f.clock.advance(const Duration(days: 1));
      c.invalidate(todayProvider);

      final plans = c.read(buildTodayPlanProvider);
      final day1 = await plans.get();
      expect(day1.rows.first.nodeId, 'st1');
      expect(day1.rows.first.rowType, RowType.review);
      expect(day1.rows.first.reason, Reason.deadlineRisk);

      await c.read(gradeReviewProvider)('st1', Grade.solid, 5);
      final refreshed = await plans.refresh();
      final st1 = refreshed.rows.where((r) => r.nodeId == 'st1').toList();
      expect(st1, hasLength(1));
      expect(st1.single.doneAtUtc, isNotNull);
    });

    test('a reschedule as the newest event gives the catch_up reason', () async {
      await f.seedTree();
      await c.read(markStudiedProvider)('st1', 30);
      await f.writer.writeRescheduleBatch({'st1': day0.plusDays(2)}, 'b1');
      f.clock.advance(const Duration(days: 2));
      c.invalidate(todayProvider);
      final (input, plan) = await c.read(buildTodayPlanProvider).compute();
      expect(input.items.firstWhere((i) => i.nodeId == 'st1').newestIsReschedule, isTrue);
      expect(plan.rows.firstWhere((r) => r.nodeId == 'st1').reason, Reason.catchUp);
    });
  });

  group('mark_studied', () {
    test('an item outside the plan gets a done first_read row', () async {
      await f.seedTree();
      await f.planWith(day0, const []);
      await c.read(markStudiedProvider)('k2', 25);
      final rows = (await db.plansDao.planFor(day0))!.rows;
      expect(rows.single.nodeId, 'k2');
      expect(rows.single.rowType, RowType.firstRead);
      expect(rows.single.estimatedMinutes, 25);
      expect(rows.single.doneAtUtc, isNotNull);
      expect(await c.read(markStudiedProvider).defaultMinutes('k2'), 30);
    });

    test('an item in the plan has its row marked done', () async {
      await f.seedTree();
      await c.read(buildTodayPlanProvider).get();
      await c.read(markStudiedProvider)('st1', 30);
      final rows = (await db.plansDao.planFor(day0))!.rows;
      expect(rows.where((r) => r.nodeId == 'st1').single.doneAtUtc, isNotNull);
    });
  });

  group('grade_review', () {
    test('preview shows each grade with its capped next date', () async {
      await f.seedTree();
      await exam('MPSC', 4, {'sub1'});
      await c.read(markStudiedProvider)('k2', 30);
      f.clock.advance(const Duration(days: 1));
      c.invalidate(todayProvider);

      final p = await c.read(gradeReviewProvider).preview('k2');
      expect(p.belt, Belt.red);
      expect(p.defaultMinutes, reviewCost(30));
      final byGrade = {for (final o in p.options) o.grade: o};
      // Solid at Red → Orange, ladder +3 = day 4, but the exam on day 4 caps it to day 3.
      expect(byGrade[Grade.solid]!.outcome.beltAfter, Belt.orange);
      expect(byGrade[Grade.solid]!.nextDue, day0.plusDays(3));
      expect(byGrade[Grade.solid]!.capNote, contains('Capped by MPSC'));
      expect(byGrade[Grade.forgot]!.nextDue, day0.plusDays(2));
      expect(byGrade[Grade.forgot]!.dropNote, isNull); // Red stays Red

      await c.read(gradeReviewProvider)('k2', Grade.solid, 8);
      await f.writer.writeReview('k2', Grade.forgot, 3);
      final undoDrop = (await c.read(gradeReviewProvider).preview('k2'))
          .options
          .firstWhere((o) => o.grade == Grade.forgot);
      expect(undoDrop.dropNote, isNull);
    });

    test('Forgot below Orange has a drop message; PYQ is flagged', () async {
      await f.subject('s');
      await f.node('p', 's', NodeKind.task);
      await db.nodesDao.updateNode(
          'p', const StudyNodesCompanion(taskKind: Value(TaskKind.pyq)));
      await f.writer.writeFirstStudy('p', 30);
      await f.writer.writeReview('p', Grade.solid, 5);
      final p = await c.read(gradeReviewProvider).preview('p');
      expect(p.isPyq, isTrue);
      expect(p.options.firstWhere((o) => o.grade == Grade.forgot).dropNote,
          'Back to Red — quick look tomorrow.');
    });
  });

  group('add_item and split_item', () {
    test('defaults to the Inbox and remembers subject and topic', () async {
      final add = c.read(addItemProvider);
      final id = await add(const AddItemRequest(title: '  Quick note  '));
      final node = (await db.nodesDao.byId(id))!;
      final inbox = (await db.subjectsDao.inbox())!;
      expect(node.subjectId, inbox.id);
      expect(node.title, 'Quick note');
      expect(node.baseMinutes, 30);
      expect(await db.settingsDao.lastUsedSubjectId(), inbox.id);

      await f.seedTree();
      final under = await add(const AddItemRequest(
          title: 'Fundamental Rights', parentId: 't1', taskKind: TaskKind.pyq));
      expect((await db.nodesDao.byId(under))!.baseMinutes, 40);
      expect((await db.nodesDao.byId(under))!.sortOrder, 4);
      expect(await db.settingsDao.lastUsedTopicId(), 't1');

      final sub = await add(const AddItemRequest(
          title: 'Ch 3', kind: NodeKind.subtask, parentId: 'k1'));
      expect((await db.nodesDao.byId(sub))!.subjectId, 'sub1');
      expect(await db.settingsDao.lastUsedTopicId(), 't1');
    });

    test('enforces the depth rule, history rule and base range', () async {
      await f.seedTree();
      final add = c.read(addItemProvider);
      expect(() => add(const AddItemRequest(title: 'x', kind: NodeKind.subtask)),
          throwsStateError);
      expect(() => add(const AddItemRequest(title: 'x', kind: NodeKind.topic, parentId: 't1')),
          throwsStateError);
      expect(() => add(const AddItemRequest(title: '')), throwsArgumentError);
      expect(() => add(const AddItemRequest(title: 'x', baseMinutes: 5)), throwsRangeError);
      expect(
          () => add(const AddItemRequest(
              title: 'x', kind: NodeKind.topic, source: NewSource(type: SourceType.web))),
          throwsArgumentError);

      await f.writer.writeFirstStudy('k2', 30);
      expect(
          () => add(const AddItemRequest(title: 'x', kind: NodeKind.subtask, parentId: 'k2')),
          throwsStateError);
    });

    test('a task source is stored with its link status', () async {
      final id = await c.read(addItemProvider)(const AddItemRequest(
        title: 'Spectrum',
        source: NewSource(type: SourceType.book, locationNote: 'Printed copy, shelf 2'),
      ));
      final s = (await db.sourcesDao.sourceFor(id))!;
      expect(s.linkStatus, LinkStatus.notLinked);
      expect(s.locationNote, 'Printed copy, shelf 2');
      final web = await c.read(addItemProvider)(const AddItemRequest(
          title: 'Web', source: NewSource(type: SourceType.web, url: 'https://x.org')));
      expect((await db.sourcesDao.sourceFor(web))!.linkStatus, LinkStatus.ok);
    });

    test('split creates Unread subtasks with positions (CUJ 2)', () async {
      await f.subject('s');
      await f.node('laxmikant', 's', NodeKind.task);
      final split = c.read(splitItemProvider);
      expect(await split.allowed('laxmikant'), isTrue);
      final ids = await split('laxmikant', const Chapters(1, 12));
      expect(ids, hasLength(12));
      final kids = await db.nodesDao.children('laxmikant');
      expect([for (final k in kids.take(2)) (k.title, k.positionText, k.baseMinutes)],
          [('Ch 1', 'Ch 1', 30), ('Ch 2', 'Ch 2', 30)]);
      expect(rollupLabel(rollup(await db.nodesDao.leafBelts('laxmikant'))), '0/12 started');

      await f.node('done', 's', NodeKind.task);
      await f.writer.writeFirstStudy('done', 30);
      expect(await split.allowed('done'), isFalse);
      expect(() => split('done', const Chapters(1, 2)), throwsStateError);
    });
  });

  group('exams, explain and delete', () {
    test('save_exam links, re-links, archives and never links the Inbox', () async {
      final save = c.read(saveExamProvider);
      final polity = await save.createSubject('Polity');
      final history = await save.createSubject('History');
      final inbox = await db.subjectsDao.ensureInbox(newId: f.newId, now: t0);
      final id = await save.create('MPSC', day0.plusDays(30), {polity, inbox.id});
      expect([for (final s in await db.subjectsDao.forExam(id)) s.id], [polity]);
      await save.update(id, 'MPSC 2027', day0.plusDays(40), {history});
      expect([for (final s in await db.subjectsDao.forExam(id)) s.id], [history]);
      expect((await db.examsDao.byId(id))!.name, 'MPSC 2027');
      await save.setArchived(id, archived: true);
      expect((await db.examsDao.byId(id))!.archivedAt, isNotNull);
      expect(() => save.createSubject(' '), throwsArgumentError);
    });

    test('explain_due adds the cap suffix; delete hides the subtree', () async {
      await f.seedTree();
      await exam('MPSC', 30, {'sub1'});
      expect((await c.read(explainDueProvider)('st1')).text, 'Not studied yet.');
      await f.writer.writeFirstStudy('st1', 30);
      for (var i = 0; i < 4; i++) {
        await f.writer.writeReview('st1', Grade.solid, 5);
      }
      final e = await c.read(explainDueProvider)('st1');
      expect(e.state.belt, Belt.green);
      expect(e.text, contains('Capped by MPSC'));
      expect(e.effectiveDue, day0.plusDays(29));
      expect(e.recent, hasLength(5));

      await c.read(deleteItemProvider)('k1');
      expect((await db.nodesDao.byId('st1'))!.deletedAt, isNotNull);
    });
  });

  group('move, delete with orphans, subjects (design §10a)', () {
    // seedTree: sub1 { t1 (topic) { k1 (task) { st1, st2 } }, k2 (task) }
    Future<NodeRow> node(String id) async => (await db.nodesDao.byId(id))!;
    Future<String> inboxId() async =>
        (await db.subjectsDao.ensureInbox(newId: f.newId, now: t0)).id;
    Future<void> pdfOn(String id) => db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
        nodeId: id, sourceType: SourceType.pdf, fileName: const Value('p.pdf'),
        linkStatus: LinkStatus.notLinked));

    test('delete only this: subtasks become Inbox tasks with the source; undo puts back',
        () async {
      await f.seedTree();
      await pdfOn('k1');
      await f.writer.writeFirstStudy('st1', 30);
      final inbox = await inboxId();
      final r = await c.read(deleteItemProvider)('k1', keepChildren: true);
      expect(r.movedToInbox, 2);
      for (final id in ['st1', 'st2']) {
        final n = await node(id);
        expect((n.kind, n.subjectId, n.parentId, n.deletedAt), (NodeKind.task, inbox, null, null));
        expect((await db.sourcesDao.sourceFor(id))!.fileName, 'p.pdf');
      }
      expect((await node('k1')).deletedAt, isNotNull);
      expect((await db.itemStateDao.stateOf('st1')).belt, Belt.red); // history stays

      await c.read(deleteItemProvider).undo(r);
      expect((await node('k1')).deletedAt, isNull);
      final st1 = await node('st1');
      expect((st1.kind, st1.subjectId, st1.parentId), (NodeKind.subtask, 'sub1', 'k1'));
      expect(await db.sourcesDao.sourceFor('st1'), isNull);
    });

    test('deleting a topic keeps its tasks whole; delete everything cascades', () async {
      await f.seedTree();
      final inbox = await inboxId();
      final r = await c.read(deleteItemProvider)('t1', keepChildren: true);
      expect(r.movedToInbox, 1);
      final k1 = await node('k1');
      expect((k1.subjectId, k1.parentId), (inbox, null));
      expect(((await node('st1')).subjectId, (await node('st1')).parentId), (inbox, 'k1'));

      final all = await c.read(deleteItemProvider)('k1');
      expect(all.movedToInbox, 0);
      expect((await node('st2')).deletedAt, isNotNull);
      await c.read(deleteItemProvider).undo(all);
      expect((await node('st2')).deletedAt, isNull);
    });

    test('move: a task with its subtasks, a subtask to a task or out on its own', () async {
      await f.seedTree();
      await f.subject('sub2', name: 'History', order: 2);
      await f.node('t2', 'sub2', NodeKind.topic);
      await pdfOn('k1');
      final move = c.read(moveItemProvider);

      await move('k1', const MoveTarget(subjectId: 'sub2', parentId: 't2'));
      expect(((await node('k1')).subjectId, (await node('k1')).parentId), ('sub2', 't2'));
      expect((await node('st1')).subjectId, 'sub2');

      await move('st2', const MoveTarget(subjectId: 'sub1', parentId: 'k2'));
      final st2 = await node('st2');
      expect((st2.kind, st2.parentId, st2.subjectId), (NodeKind.subtask, 'k2', 'sub1'));

      await move('st1', const MoveTarget(subjectId: 'sub1'));
      final st1 = await node('st1');
      expect((st1.kind, st1.parentId), (NodeKind.task, null));
      expect((await db.sourcesDao.sourceFor('st1'))!.fileName, 'p.pdf');

      // A task with history can't gain subtasks; a topic can't go under a topic.
      await f.writer.writeFirstStudy('st1', 30);
      await f.node('st3', 'sub1', NodeKind.subtask, parent: 'k2');
      expect(() => move('st3', const MoveTarget(subjectId: 'sub1', parentId: 'st1')),
          throwsStateError);
      expect(() => move('t2', const MoveTarget(subjectId: 'sub1', parentId: 't1')),
          throwsStateError);
    });

    test('moving out of the Inbox puts an item into the plan', () async {
      final add = c.read(addItemProvider);
      final id = await add(const AddItemRequest(title: 'Shared note'));
      expect([for (final n in await db.nodesDao.plannable()) n.id], isNot(contains(id)));
      final polity = await c.read(saveExamProvider).createSubject('Polity');
      await c.read(moveItemProvider)(id, MoveTarget(subjectId: polity));
      expect([for (final n in await db.nodesDao.plannable()) n.id], contains(id));
    });

    test('subjects: create with exams, rename, delete keeping or dropping items', () async {
      final save = c.read(saveExamProvider);
      final e = await exam('MPSC', 30, {});
      final s = await save.createSubject('Labour', examIds: {e});
      expect([for (final x in await db.subjectsDao.forExam(e)) x.id], [s]);
      await save.renameSubject(s, 'Labour codes');
      expect((await db.subjectsDao.byId(s))!.name, 'Labour codes');
      final inbox = await inboxId();
      expect(() => save.renameSubject(inbox, 'X'), throwsStateError);
      expect(() => save.deleteSubject(inbox, keepItems: true), throwsStateError);

      await f.seedTree();
      await f.node('gone', 'sub1', NodeKind.task);
      await db.nodesDao.softDelete('gone', t0);
      await save.deleteSubject('sub1', keepItems: true);
      expect(await db.subjectsDao.byId('sub1'), isNull);
      final t1 = await node('t1');
      expect((t1.subjectId, t1.kind, t1.deletedAt), (inbox, NodeKind.topic, null));
      expect(((await node('st1')).subjectId, (await node('st1')).parentId), (inbox, 'k1'));
      expect((await node('gone')).subjectId, inbox);

      await f.subject('sub3');
      await f.node('k9', 'sub3', NodeKind.task);
      await db.settingsDao.setLastUsedSubjectId('sub3');
      await save.deleteSubject('sub3', keepItems: false);
      final k9 = await node('k9');
      expect((k9.subjectId, k9.deletedAt != null), (inbox, true));
      expect(await db.settingsDao.lastUsedSubjectId(), isNull);
    });
  });

  test('complete_onboarding: CUJ 1 leaves a done first-reading row at Red', () async {
    final id = await c.read(completeOnboardingProvider)(OnboardingInput(
      examName: 'MPSC Prelims',
      examDate: day0.plusDays(200),
      subjectName: 'Polity',
      dailyMinutes: 90,
      itemTitle: 'Laxmikant Ch 1–5',
      studiedToday: true,
    ));
    final plan = (await db.plansDao.planFor(day0))!;
    final row = plan.rows.singleWhere((r) => r.nodeId == id);
    expect(row.rowType, RowType.firstRead);
    expect(row.doneAtUtc, isNotNull);
    expect((await db.itemStateDao.stateOf(id)).belt, Belt.red);
    expect(await db.settingsDao.onboardingDone(), isTrue);
    expect(await db.settingsDao.dailyMinutes(), 90);
    final subjects = await db.subjectsDao.findByName('polity');
    expect(subjects, hasLength(1));
  });
}
