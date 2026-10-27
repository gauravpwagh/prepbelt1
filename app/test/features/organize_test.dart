// Organising items: move, delete with orphans, subjects where they are
// picked (design §10a; plan items 120–126).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/providers.dart';

import '../application/app_helpers.dart';

void main() {
  late Fixture f;
  late ProviderContainer c;

  setUp(() async {
    f = Fixture();
    c = containerFor(f);
    await f.seedTree();
  });

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

  Future<void> openInLibrary(WidgetTester tester, String nodeId) async {
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polity'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('node-$nodeId')));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('Add: "+ New subject…" creates, links and selects a subject', (tester) async {
    final examId = await c.read(saveExamProvider).create('MPSC', day0.plusDays(60), {'sub1'});
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-title')), 'Code on Wages');

    await tester.tap(find.byKey(const Key('add-subject')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New subject…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-subject-name')), 'Labour codes');
    await tester.tap(find.widgetWithText(FilterChip, 'MPSC'));
    await tester.tap(find.byKey(const Key('new-subject-create')));
    await tester.pumpAndSettle();
    expect(find.text('Labour codes'), findsOneWidget); // selected in the menu

    await tester.tap(find.byKey(const Key('add-save')));
    await tester.pumpAndSettle();
    final subject = (await f.db.subjectsDao.findByName('Labour codes')).single;
    expect([for (final s in await f.db.subjectsDao.forExam(examId)) s.name],
        containsAll(['Polity', 'Labour codes']));
    final roots = await f.db.nodesDao.roots(subject.id);
    expect(roots.single.title, 'Code on Wages');
    await tearDownApp(tester);
  });

  testWidgets('Delete asks; "Delete only this" moves subtasks to the Inbox; Undo', (tester) async {
    await pumpApp(tester);
    await openInLibrary(tester, 'k1');
    await menu(tester, 'Delete');
    expect(find.textContaining('has 2 subtasks'), findsOneWidget);
    expect(find.byKey(const Key('delete-everything')), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-only-this')));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 moved to the Inbox'), findsOneWidget);
    final st1 = (await f.db.nodesDao.byId('st1'))!;
    expect((st1.kind, st1.parentId), (NodeKind.task, null));
    expect((await f.db.subjectsDao.byId(st1.subjectId))!.isInbox, isTrue);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await f.db.nodesDao.byId('k1'))!.deletedAt, isNull);
    expect((await f.db.nodesDao.byId('st1'))!.parentId, 'k1');
    await tearDownApp(tester);
  });

  testWidgets('Move… files a task under another subject', (tester) async {
    await f.subject('sub2', name: 'History', order: 2);
    await pumpApp(tester);
    await openInLibrary(tester, 'k2');
    await menu(tester, 'Move…');
    expect(find.text('Here now'), findsOneWidget);
    await tester.tap(find.byKey(const Key('move-sub2')));
    await tester.pumpAndSettle();
    expect(find.text('Moved "k2"'), findsOneWidget);
    expect((await f.db.nodesDao.byId('k2'))!.subjectId, 'sub2');
    await tearDownApp(tester);
  });

  testWidgets('Library: rename a subject, then delete it keeping its items', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('subject-menu-sub1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-dialog-field')), 'Indian Polity');
    await tester.tap(find.byKey(const Key('name-dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Indian Polity'), findsOneWidget);

    await tester.tap(find.byKey(const Key('subject-menu-sub1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete subject'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('subject-delete-items')), findsOneWidget);
    await tester.tap(find.byKey(const Key('subject-delete-keep')));
    await tester.pumpAndSettle();

    expect(find.text('Indian Polity'), findsNothing);
    expect(await f.db.subjectsDao.byId('sub1'), isNull);
    expect(find.text('t1'), findsOneWidget); // the topic, now in the open Inbox
    await tearDownApp(tester);
  });
}
