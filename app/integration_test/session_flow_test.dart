// Plan item 103: run with `flutter test integration_test` on API 26 and 36
// emulators. Storage is in-memory and the folder picker is faked; the
// notification plugin is real.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/platform/notification_port.dart';

import '../test/application/app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Start → come back → Finish → Red, with a real notification', (tester) async {
    final f = Fixture();
    await f.seedTree();
    final c = containerFor(f, notifications: LocalNotificationPort(f.clock));
    await c.read(notificationPortProvider).init((_) {});
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PrepBeltApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-st1')));
    await tester.pumpAndSettle();
    f.clock.advance(const Duration(minutes: 38));
    await tester.tap(find.byKey(const Key('finish-st1')));
    await tester.pumpAndSettle();
    expect(find.text('Studied 38 min'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-confirm')));
    await tester.pumpAndSettle();
    expect((await f.db.itemStateDao.stateOf('st1')).belt, Belt.red);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await f.close();
  });
}
