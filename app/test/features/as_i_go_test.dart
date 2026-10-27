// Splitting a task as you go (design D17, §10b; CUJ 15).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/application/add_item.dart';
import 'package:prepbelt/application/mark_studied.dart';
import 'package:prepbelt/core/providers.dart';

import '../application/app_helpers.dart';

void main() {
  late Fixture f;
  late ProviderContainer c;

  setUp(() async {
    f = Fixture();
    c = containerFor(f);
    await f.subject('sub1', name: 'History', order: 1);
  });

  Future<String> addAsIGo() => c.read(addItemProvider)(
      const AddItemRequest(title: 'Spectrum', subjectId: 'sub1', baseMinutes: 30, asIGo: true));

  Future<Set<String>> planned() async =>
      {for (final n in (await f.db.nodesDao.planning()).nodes) n.id};

  group('use case', () {
    tearDown(() async {
      c.dispose();
      await f.close();
    });

    test('a part becomes a studied subtask; the plan row moves to it', () async {
      final task = await addAsIGo();
      expect((await f.db.nodesDao.byId(task))!.splitAsIGo, SplitAsIGo.open);
      final plan = await c.read(buildTodayPlanProvider).refresh();
      expect(plan.rows.single.nodeId, task);
      expect(await c.read(markStudiedProvider).nextPart(task), 'Part 1');

      final e = await c.read(markStudiedProvider)(task, 35, part: const StudiedPart('Ch 1–2'));
      final part = (await f.db.nodesDao.byId(e.nodeId))!;
      expect((part.kind, part.parentId, part.title, part.baseMinutes),
          (NodeKind.subtask, task, 'Ch 1–2', 35));
      expect((await f.db.itemStateDao.stateOf(part.id)).belt, Belt.red);
      expect(await f.db.eventsDao.countFor(task), 0);

      final rows = (await f.db.plansDao.planFor(f.dayClock.today()))!.rows;
      expect(rows.single.nodeId, part.id);
      expect(rows.single.doneAtUtc, isNotNull);

      // Still open: planned as its next part, with the next title.
      expect(await planned(), contains(task));
      expect(await c.read(markStudiedProvider).nextPart(task), 'Ch 3–4');
    });

    test('a part outside the plan gets a done row; the last part ends it', () async {
      final task = await addAsIGo();
      await f.planWith(f.dayClock.today(), const []);
      final e = await c.read(markStudiedProvider)(task, 5,
          part: const StudiedPart('Ch 1', last: true));
      expect((await f.db.nodesDao.byId(e.nodeId))!.baseMinutes, 10); // clamped
      final rows = (await f.db.plansDao.planFor(f.dayClock.today()))!.rows;
      expect((rows.single.nodeId, rows.single.rowType), (e.nodeId, RowType.firstRead));
      expect((await f.db.nodesDao.byId(task))!.splitAsIGo, SplitAsIGo.done);
      expect(await planned(), isNot(contains(task)));
      expect(await c.read(markStudiedProvider).nextPart(task), isNull);
    });

    test('the task itself never gets events while open', () async {
      final task = await addAsIGo();
      expect(() => f.writer.writeFirstStudy(task, 30), throwsStateError);
      expect(() => c.read(markStudiedProvider)(task, 30), throwsArgumentError);
      await c.read(markStudiedProvider).finish(task);
      // Finished with no parts: an ordinary unread task.
      expect(await planned(), contains(task));
      await c.read(markStudiedProvider)(task, 30);
      expect(await f.db.eventsDao.countFor(task), 1);
    });

    test('only tasks can be split as you go', () async {
      expect(
          () => c.read(addItemProvider)(const AddItemRequest(
              title: 'Modern', kind: NodeKind.topic, subjectId: 'sub1', asIGo: true)),
          throwsArgumentError);
    });
  });

  group('widgets', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PrepBeltApp()));
      await tester.pumpAndSettle();
    }

    Future<void> tearDownApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await f.close();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('Add: "Split as I go" saves an open task', (tester) async {
      await f.db.settingsDao.setLastUsedSubjectId('sub1'); // not the Inbox
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-title')), 'Spectrum');
      await tester.ensureVisible(find.text('Split into parts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split into parts'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('add-as-i-go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-as-i-go')));
      await tester.pumpAndSettle();
      expect(find.text('Chapters'), findsNothing); // the one-shot split is hidden
      await tester.ensureVisible(find.byKey(const Key('add-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-save')));
      await tester.pumpAndSettle();

      final node = (await f.db.nodesDao.allLive()).singleWhere((n) => n.title == 'Spectrum');
      expect(node.splitAsIGo, SplitAsIGo.open);
      expect(find.text('Spectrum · next part'), findsOneWidget); // on Today
      await tearDownApp(tester);
    });

    testWidgets('Start and Finish ask for the part (CUJ 15)', (tester) async {
      final task = await addAsIGo();
      await pumpApp(tester);
      await tester.tap(find.byKey(Key('start-$task')));
      await tester.pumpAndSettle();
      f.clock.advance(const Duration(minutes: 35));
      await tester.tap(find.byKey(Key('finish-$task')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('part-title'))).controller!.text,
          'Part 1');
      await tester.enterText(find.byKey(const Key('part-title')), 'Ch 1–2');
      await tester.tap(find.byKey(const Key('finish-confirm')));
      await tester.pumpAndSettle();

      final part = (await f.db.nodesDao.children(task)).single;
      expect((part.title, part.baseMinutes), ('Ch 1–2', 35));
      final e = (await f.db.eventsDao.eventsFor(part.id)).single as FirstStudy;
      expect(e.sessionId, isNotNull);
      expect(find.textContaining('Red · next review'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Mark part studied names the part, pre-filled', (tester) async {
      final task = await addAsIGo();
      await c.read(markStudiedProvider)(task, 30, part: const StudiedPart('Ch 1'));
      await pumpApp(tester);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Split as I go'), findsOneWidget);
      await tester.tap(find.byKey(Key('node-$task')));
      await tester.pumpAndSettle();
      expect(find.text('1 part so far'), findsOneWidget);

      await tester.tap(find.byKey(const Key('item-record')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const Key('part-title')));
      expect(field.controller!.text, 'Ch 2');
      await tester.tap(find.byKey(const Key('part-last')));
      await tester.tap(find.byKey(const Key('studied-save')));
      await tester.pumpAndSettle();

      final parts = await f.db.nodesDao.children(task);
      expect([for (final p in parts) p.title], ['Ch 1', 'Ch 2']);
      expect((await f.db.nodesDao.byId(task))!.splitAsIGo, SplitAsIGo.done);
      await tearDownApp(tester);
    });
  });
}
