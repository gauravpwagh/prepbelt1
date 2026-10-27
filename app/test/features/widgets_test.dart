import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/router.dart';
import 'package:prepbelt/platform/share_receiver.dart';

import '../application/app_helpers.dart';

void main() {
  late Fixture f;
  late ProviderContainer c;
  late FakeShareReceiver shares;

  setUp(() {
    f = Fixture();
    shares = FakeShareReceiver();
    c = containerFor(f, shares: shares);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PrepBeltApp()));
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await f.close();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('CUJ 3a: Start, come back 38 minutes later, Finish → Red', (tester) async {
    await f.seedTree();
    await pumpApp(tester);

    expect(find.byKey(const Key('today-summary')), findsOneWidget);
    expect(find.text('k1 · st1'), findsOneWidget);
    expect(find.textContaining('min new reading'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-st1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-banner')), findsOneWidget);

    f.clock.advance(const Duration(minutes: 38));
    await tester.tap(find.byKey(const Key('finish-st1')));
    await tester.pumpAndSettle();
    expect(find.text('Studied 38 min'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Red · next review'), findsOneWidget);
    expect((await f.db.itemStateDao.stateOf('st1')).belt, Belt.red);
    expect(find.byKey(const Key('session-banner')), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('Finish on a review opens the grade sheet with the minutes', (tester) async {
    await f.seedTree();
    await f.writer.writeFirstStudy('k2', 30);
    f.clock.advance(const Duration(days: 1));
    c.invalidate(todayProvider);
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('start-k2')));
    await tester.pumpAndSettle();
    f.clock.advance(const Duration(minutes: 9));
    await tester.tap(find.byKey(const Key('finish-k2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(Grade.solid.definition), findsOneWidget);
    expect(find.text(Grade.forgot.definition), findsOneWidget);
    expect(find.textContaining('Next: '), findsNWidgets(3));
    expect(find.textContaining('in 3 days'), findsOneWidget); // Solid at Red → Orange
    expect(tester.widget<TextField>(find.byKey(const Key('grade-minutes'))).controller!.text, '9');

    await tester.tap(find.byKey(const Key('grade-solid')));
    await tester.pumpAndSettle();
    expect((await f.db.itemStateDao.stateOf('k2')).belt, Belt.orange);
    expect(find.textContaining('Solid at Red → Orange'), findsOneWidget);
    final e = (await f.db.eventsDao.eventsFor('k2')).last as Review;
    expect(e.sessionId, isNotNull);
    expect(e.minutes, 9);
    await tearDownApp(tester);
  });

  testWidgets('Item screen: mark studied without a timer, then undo', (tester) async {
    await f.seedTree();
    await pumpApp(tester);
    await tester.tap(find.text('k2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('studied-save')));
    await tester.pumpAndSettle();
    expect((await f.db.itemStateDao.stateOf('k2')).belt, Belt.red);

    await tester.tap(find.byKey(const Key('why-due')));
    await tester.pumpAndSettle();
    expect(find.text('First read → Red. Next review in 1 day.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-undo')));
    await tester.pumpAndSettle();
    expect((await f.db.itemStateDao.stateOf('k2')).belt, Belt.unread);
    await tearDownApp(tester);
  });

  testWidgets('Library shows the rollup label and leaf belts', (tester) async {
    await f.seedTree();
    await f.writer.writeFirstStudy('st1', 30);
    await pumpApp(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Polity'), findsOneWidget);
    expect(find.text('Weakest: Red · 0/3 Green'), findsOneWidget);
    await tester.tap(find.text('Polity'));
    await tester.pumpAndSettle();
    expect(find.text('Weakest: Red · 0/2 Green'), findsWidgets); // t1 and k1
    expect(find.text('Red · 1/5'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('Onboarding (CUJ 1) ends on Today with a done row', (tester) async {
    c.read(onboardingDoneProvider.notifier).set(false);
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('onboarding-fresh')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ob-exam')), 'MPSC Prelims');
    await tester.enterText(find.byKey(const Key('ob-subject')), 'Polity');
    await tester.enterText(find.byKey(const Key('ob-item')), 'Laxmikant Ch 1–5');
    await tester.tap(find.byKey(const Key('ob-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Pick the exam date'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ob-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ob-studied')));
    await tester.ensureVisible(find.byKey(const Key('ob-continue')));
    await tester.tap(find.byKey(const Key('ob-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-Allow notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a backup folder'), findsOneWidget);
    await tester.tap(find.byKey(const Key('step-skip')));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.byKey(const Key('backup-banner')), findsOneWidget);
    expect(find.text('Laxmikant Ch 1–5'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('Share capture sheet saves a shared link to the Inbox (CUJ 2b)', (tester) async {
    await f.seedTree();
    await pumpApp(tester);
    shares.send(const IncomingShare(text: 'https://chatgpt.com/share/xyz', subject: 'Federalism'));
    await tester.pumpAndSettle();

    expect(find.text('Add to PrepBelt'), findsOneWidget);
    expect(find.text('AI chat'), findsOneWidget);
    expect(find.text('Federalism'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-save')));
    await tester.pumpAndSettle();

    final inbox = (await f.db.subjectsDao.inbox())!;
    final roots = await f.db.nodesDao.roots(inbox.id);
    expect(roots.single.title, 'Federalism');
    expect(find.text('Saved as Planned'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('A share before onboarding waits until onboarding is done', (tester) async {
    c.read(onboardingDoneProvider.notifier).set(false);
    await pumpApp(tester);
    shares.send(const IncomingShare(text: 'Read Article 21 notes'));
    await tester.pumpAndSettle();
    expect(find.text('Add to PrepBelt'), findsNothing);

    c.read(onboardingDoneProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(find.text('Add to PrepBelt'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('Import screen offers one clash choice and imports (CUJ 10)', (tester) async {
    await f.seedTree();
    await f.db.examsDao.insertExam(ExamsCompanion.insert(
        id: 'x', name: 'MPSC', examDate: day0.plusDays(60), createdAt: t0));
    await f.db.subjectsDao.link('x', 'sub1');
    final pkg = await c.read(examExporterProvider).build('x', PackageMode.structure, includeNotes: true);
    late File file;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('prepbelt_import');
      file = File('${dir.path}/MPSC.prepbelt.json');
      await file.writeAsString(pkg.encode());
    });
    await pumpApp(tester);
    c.read(routerProvider).push('/exams/import', extra: file.path);
    // The preview reads the file with real IO: let it run between pumps.
    for (var i = 0; i < 20 && find.byKey(const Key('import-go')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('1 subjects · 5 items · structure only'), findsOneWidget);
    expect(find.text('Add these items to your existing Polity'), findsOneWidget);
    expect(find.text('Used by MPSC'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clash-add-sub1')));
    await tester.enterText(find.byKey(const Key('import-name')), 'MPSC 2028');
    await tester.tap(find.byKey(const Key('import-go')));
    await tester.pumpAndSettle();

    expect(find.text('Imported 5 items'), findsOneWidget);
    expect((await f.db.examsDao.all()).map((e) => e.name), containsAll(['MPSC', 'MPSC 2028']));
    expect(await f.db.nodesDao.roots('sub1'), hasLength(4));
    await tearDownApp(tester);
  });

  testWidgets('Diagnostics shows permission, battery, integrity and shares logs', (tester) async {
    await pumpApp(tester);
    c.read(routerProvider).push('/diagnostics');
    await tester.pumpAndSettle();
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('On — reminders may be delayed'), findsOneWidget);
    expect(find.text('Integrity OK'), findsOneWidget);
    await tester.tap(find.byKey(const Key('diag-test')));
    await tester.pumpAndSettle();
    await tearDownApp(tester);
  });
}
