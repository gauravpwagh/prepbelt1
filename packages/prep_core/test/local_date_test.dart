import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

void main() {
  test('parse and format round trip', () {
    expect(LocalDate.parse('2027-03-14').toIso(), '2027-03-14');
    expect(LocalDate(2027, 3, 4).toIso(), '2027-03-04');
  });

  test('parse rejects bad input', () {
    expect(() => LocalDate.parse('2027-3-14'), throwsFormatException);
    expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
  });

  test('arithmetic crosses month and year ends', () {
    expect(LocalDate(2026, 12, 31).plusDays(1), LocalDate(2027, 1, 1));
    expect(LocalDate(2028, 2, 28).plusDays(1), LocalDate(2028, 2, 29));
    expect(LocalDate(2026, 3, 1).plusDays(-1), LocalDate(2026, 2, 28));
    expect(LocalDate(2026, 11, 2).daysUntil(LocalDate(2027, 3, 14)), 132);
    expect(LocalDate(2027, 3, 14).daysUntil(LocalDate(2026, 11, 2)), -132);
  });

  test('comparison and min/max', () {
    final a = LocalDate(2026, 11, 2), b = LocalDate(2026, 11, 3);
    expect(a < b, isTrue);
    expect(b <= b, isTrue);
    expect(LocalDate.min(a, b), a);
    expect(LocalDate.max(a, b), b);
  });

  test('shortDate', () {
    expect(shortDate(LocalDate(2027, 3, 14)), '14 Mar');
    expect(shortDate(LocalDate(2027, 12, 1)), '1 Dec');
  });
}
