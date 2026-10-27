// Adaptive layouts (design D14, §13; plan item 111).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/layout.dart';
import 'package:prepbelt/features/item/item_screen.dart';

import '../application/app_helpers.dart';

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tabletLandscape = Size(1280, 800);

void main() {
  late Fixture f;
  late ProviderContainer c;

  setUp(() async {
    f = Fixture();
    c = containerFor(f);
    await f.seedTree();
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PrepBeltApp()));
    await tester.pumpAndSettle();
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await f.close();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('window classes follow the width', (tester) async {
    final seen = <WindowClass>[];
    for (final w in const <double>[390, 599, 600, 839, 840]) {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(w, 800)),
        child: Builder(builder: (context) {
          seen.add(windowClassOf(context));
          return const SizedBox();
        }),
      ));
    }
    c.dispose();
    await f.close();
    expect(seen, [
      WindowClass.compact,
      WindowClass.compact,
      WindowClass.medium,
      WindowClass.medium,
      WindowClass.expanded,
    ]);
  });

  testWidgets('phone: bottom bar, and a plan row pushes the Item screen', (tester) async {
    await pumpAt(tester, phone);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const Key('today-placeholder')), findsNothing);

    await tester.tap(find.byKey(const Key('plan-row-st1')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('tablet portrait: rail, one pane, centred forms', (tester) async {
    await pumpAt(tester, tabletPortrait);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('today-placeholder')), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final box = tester.getSize(find.descendant(
        of: find.byType(ReadingWidth), matching: find.byType(ConstrainedBox)).first);
    expect(box.width, lessThanOrEqualTo(readingWidth));

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-row-st1')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemScreen), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('tablet landscape: two panes on Today and Library', (tester) async {
    await pumpAt(tester, tabletLandscape);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('today-placeholder')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-row-st1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-detail-st1')), findsOneWidget);
    expect(find.byKey(const Key('plan-row-st1')), findsOneWidget); // the list stays
    expect(tester.widget<ListTile>(find.byKey(const Key('plan-row-st1'))).selected, isTrue);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-placeholder')), findsOneWidget);
    await tester.tap(find.text('Polity'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-k2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-detail-k2')), findsOneWidget);

    // Each tab keeps its own selection.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-detail-st1')), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('shrinking with an item open pushes it', (tester) async {
    await pumpAt(tester, tabletLandscape);
    await tester.tap(find.byKey(const Key('plan-row-k2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-detail-k2')), findsOneWidget);

    await resize(tester, phone);
    expect(find.byType(ItemScreen), findsOneWidget);
    expect(find.byKey(const Key('today-detail-k2')), findsNothing);

    // Back returns to the phone list, with the selection cleared.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ItemScreen), findsNothing);
    expect(find.byKey(const Key('plan-row-k2')), findsOneWidget);
    await tearDownApp(tester);
  });
}
