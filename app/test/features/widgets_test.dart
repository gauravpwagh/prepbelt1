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

  setUp(() {
    f = Fixture();
    c = containerFor(f);
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

  testWidgets('Today lists the plan and marks a first reading studied', (tester) async {
    await f.seedTree();
    await pumpApp(tester);

    expect(find.byKey(const Key('today-summary')), findsOneWidget);
    expect(find.text('k1 · st1'), findsOneWidget);
    expect(find.textContaining('min new reading'), findsOneWidget);

    await tester.tap(find.byKey(const Key('row-action-st1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studied-minutes')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('studied-minutes')), '25');
    await tester.tap(find.byKey(const Key('studied-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Red · next review'), findsOneWidget);
    expect((await f.db.itemStateDao.stateOf('st1')).belt, Belt.red);
    expect(find.byKey(const Key('row-action-st1')), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('Grade sheet shows definitions and next dates, and saves', (tester) async {
    await f.seedTree();
    await f.writer.writeFirstStudy('k2', 30);
    f.clock.advance(const Duration(days: 1));
    c.invalidate(todayProvider);
    await pumpApp(tester);

    expect(find.text('Review'), findsOneWidget);
    await tester.tap(find.byKey(const Key('row-action-k2')));
    await tester.pumpAndSettle();
    expect(find.text(Grade.solid.definition), findsOneWidget);
    expect(find.text(Grade.forgot.definition), findsOneWidget);
    expect(find.textContaining('Next: '), findsNWidgets(3));
    expect(find.textContaining('in 3 days'), findsOneWidget); // Solid at Red → Orange

    await tester.tap(find.byKey(const Key('grade-solid')));
    await tester.pumpAndSettle();
    expect((await f.db.itemStateDao.stateOf('k2')).belt, Belt.orange);
    expect(find.textContaining('Solid at Red → Orange'), findsOneWidget);
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

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Laxmikant Ch 1–5'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tearDownApp(tester);
  });
}
