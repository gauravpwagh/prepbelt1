// Today in three sections: Due now, Up next, Coming up (design D16; CUJ 14).
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
    await f.seedTree(); // unread k2, st1, st2 in sort order, 30 min each
    await f.db.settingsDao.setDailyMinutes(45);
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

  Finder row(String id) => find.byKey(Key('plan-row-$id'));

  testWidgets('Up next lists every unread item with the line after what fits', (tester) async {
    await pumpApp(tester);
    expect(find.text('0 done · 30 of 45 min'), findsOneWidget);
    expect(find.byKey(const Key('section-due')), findsNothing); // nothing due
    expect(find.text('3 new · 1 h 30 min · 1 fits today'), findsOneWidget);

    // Open by default: k2 above the line, st1 and st2 below, all startable.
    final line = tester.getTopLeft(find.byKey(const Key('today-line'))).dy;
    expect(tester.getTopLeft(row('k2')).dy, lessThan(line));
    expect(tester.getTopLeft(row('st1')).dy, greaterThan(line));
    expect(row('st2'), findsOneWidget);
    expect(find.byKey(const Key('start-st2')), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('a finished item moves to Coming up with a ✓', (tester) async {
    await pumpApp(tester);
    await c.read(markStudiedProvider).call('k2', 30);
    await tester.pumpAndSettle();

    expect(row('k2'), findsNothing);
    expect(find.text('1 done · 30 of 45 min'), findsOneWidget);
    await tester.tap(find.byKey(const Key('section-coming')));
    await tester.pumpAndSettle();
    expect(find.text('1 review · 8 min (1 done today)'), findsOneWidget);
    expect(find.byKey(const Key('coming-row-k2')), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('Due now shows overdue days and is open by default', (tester) async {
    await f.writer.writeFirstStudy('k2', 30); // Red, due tomorrow
    f.clock.advance(const Duration(days: 3));
    c.invalidate(todayProvider);
    await pumpApp(tester);

    expect(find.byKey(const Key('section-due')), findsOneWidget);
    expect(row('k2'), findsOneWidget);
    expect(find.text('2 days overdue'), findsOneWidget);
    expect(row('st1'), findsNothing); // Up next is closed
    await tearDownApp(tester);
  });

  test('grading an item that is not in the plan adds a done review row', () async {
    await f.writer.writeFirstStudy('k2', 30);
    f.clock.advance(const Duration(days: 1));
    c.invalidate(todayProvider);
    final today = f.dayClock.today();
    await f.planWith(today, const []); // a plan without k2
    await c.read(gradeReviewProvider).call('k2', Grade.solid, 8);
    final rows = (await f.db.plansDao.planFor(today))!.rows;
    expect(rows.single.nodeId, 'k2');
    expect(rows.single.rowType, RowType.review);
    expect(rows.single.estimatedMinutes, 8);
    expect(rows.single.doneAtUtc, isNotNull);
    c.dispose();
    await f.close();
  });

  testWidgets('open sections are kept for the day, then reset', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('today-line')), findsOneWidget); // Up next open
    await tester.tap(find.byKey(const Key('section-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-line')), findsNothing);
    expect(await f.db.settingsDao.todayOpenSections(f.dayClock.today()), <String>{});

    f.clock.advance(const Duration(days: 1));
    c.invalidate(todayProvider);
    await tester.pumpAndSettle();
    expect(await f.db.settingsDao.todayOpenSections(f.dayClock.today()), isNull);
    expect(find.byKey(const Key('today-line')), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('an open section shows 5 rows, then "Show all"', (tester) async {
    for (var i = 0; i < 4; i++) {
      await f.node('x$i', 'sub1', NodeKind.task, order: 10 + i);
    }
    await pumpApp(tester);
    await tester.scrollUntilVisible(find.text('Show all 7'), 100);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all 7'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(row('x3'), 100);
    expect(row('x3'), findsOneWidget);
    expect(find.text('Show all 7'), findsNothing);
    await tearDownApp(tester);
  });
}
