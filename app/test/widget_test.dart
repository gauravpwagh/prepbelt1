import 'package:flutter_test/flutter_test.dart';
import 'package:prepbelt/main.dart';

void main() {
  testWidgets('placeholder shell shows the app name', (tester) async {
    await tester.pumpWidget(const PrepBeltApp());
    expect(find.text('PrepBelt'), findsOneWidget);
  });
}
