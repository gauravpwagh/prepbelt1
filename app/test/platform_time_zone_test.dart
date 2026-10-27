import 'package:flutter_test/flutter_test.dart';
import 'package:prepbelt/platform/time_zone.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('legacy Android zone names resolve; unknown ones fall back to UTC', () {
    // Android 15 emulators report "Asia/Calcutta".
    expect(setLocalTimeZone('Asia/Calcutta'), 'Asia/Calcutta');
    final now = DateTime.utc(2026, 3, 1, 6).millisecondsSinceEpoch;
    expect(tz.local.timeZone(now).offset, const Duration(hours: 5, minutes: 30));
    expect(setLocalTimeZone('Mars/Olympus'), 'UTC');
    expect(setLocalTimeZone(null), 'UTC');
  });
}
