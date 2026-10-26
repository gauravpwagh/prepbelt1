import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

const ist = Duration(hours: 5, minutes: 30);

/// Europe/London offsets for 2026 (BST 29 Mar 01:00 UTC → 25 Oct 01:00 UTC).
Duration london(DateTime utc) {
  final start = DateTime.utc(2026, 3, 29, 1);
  final end = DateTime.utc(2026, 10, 25, 1);
  return (!utc.isBefore(start) && utc.isBefore(end))
      ? const Duration(hours: 1)
      : Duration.zero;
}

void main() {
  group('IST with 4 AM day start', () {
    LocalDayClock clockAt(DateTime utc) =>
        LocalDayClock(FixedClock(utc), (_) => ist, dayStartHour: 4);

    test('03:59 local still belongs to the previous day', () {
      // 2026-11-03 03:59 IST = 2026-11-02 22:29 UTC
      expect(clockAt(DateTime.utc(2026, 11, 2, 22, 29)).today(),
          LocalDate(2026, 11, 2));
    });

    test('04:00 local starts the new day', () {
      // 2026-11-03 04:00 IST = 2026-11-02 22:30 UTC
      expect(clockAt(DateTime.utc(2026, 11, 2, 22, 30)).today(),
          LocalDate(2026, 11, 3));
    });

    test('00:30 local is still yesterday', () {
      // 2026-11-03 00:30 IST = 2026-11-02 19:00 UTC
      expect(clockAt(DateTime.utc(2026, 11, 2, 19)).today(), LocalDate(2026, 11, 2));
    });
  });

  test('day start 0 uses the plain local date', () {
    final c = LocalDayClock(FixedClock(DateTime.utc(2026, 11, 2, 19)), (_) => ist,
        dayStartHour: 0);
    expect(c.today(), LocalDate(2026, 11, 3));
  });

  test('offset change between calls (user travels)', () {
    var offset = ist;
    final fixed = FixedClock(DateTime.utc(2026, 11, 2, 20));
    final c = LocalDayClock(fixed, (_) => offset, dayStartHour: 4);
    expect(c.today(), LocalDate(2026, 11, 2)); // 01:30 IST → previous day
    offset = const Duration(hours: -5); // New York-ish: 15:00 local
    expect(c.today(), LocalDate(2026, 11, 2));
    fixed.advance(const Duration(hours: 13)); // 04:00 local next day
    expect(c.today(), LocalDate(2026, 11, 3));
  });

  group('Europe/London across DST', () {
    LocalDayClock clockAt(DateTime utc) =>
        LocalDayClock(FixedClock(utc), london, dayStartHour: 4);

    test('summer time: 03:30 UTC is 04:30 BST → same day', () {
      expect(clockAt(DateTime.utc(2026, 6, 10, 3, 30)).today(), LocalDate(2026, 6, 10));
    });
    test('winter time: 03:30 UTC is 03:30 GMT → previous day', () {
      expect(clockAt(DateTime.utc(2026, 12, 10, 3, 30)).today(), LocalDate(2026, 12, 9));
    });
    test('the spring-forward night', () {
      // 29 Mar 2026 02:59 UTC = 03:59 BST → still 28 Mar
      expect(clockAt(DateTime.utc(2026, 3, 29, 2, 59)).today(), LocalDate(2026, 3, 28));
      // 03:00 UTC = 04:00 BST → 29 Mar
      expect(clockAt(DateTime.utc(2026, 3, 29, 3)).today(), LocalDate(2026, 3, 29));
    });
    test('the fall-back night', () {
      // 25 Oct 2026 03:59 UTC = 03:59 GMT → still 24 Oct
      expect(clockAt(DateTime.utc(2026, 10, 25, 3, 59)).today(), LocalDate(2026, 10, 24));
      expect(clockAt(DateTime.utc(2026, 10, 25, 4)).today(), LocalDate(2026, 10, 25));
    });
  });

  test('FixedClock advance and set', () {
    final c = FixedClock(DateTime.utc(2026, 1, 1));
    c.advance(const Duration(days: 2));
    expect(c.nowUtc(), DateTime.utc(2026, 1, 3));
    c.set(DateTime.utc(2027, 1, 1));
    expect(c.nowUtc(), DateTime.utc(2027, 1, 1));
  });
}
