import 'package:meta/meta.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A calendar date with no time or time zone. Used for study days and due
/// dates so that instants and days can never be mixed up.
@immutable
final class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// Takes the year, month and day fields of [dt] as they are.
  factory LocalDate.fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  /// Parses `YYYY-MM-DD`. Throws [FormatException] on anything else,
  /// including impossible dates such as 2026-02-30.
  factory LocalDate.parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('Not a YYYY-MM-DD date', iso);
    final d = LocalDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    final check = d._utc;
    if (check.year != d.year || check.month != d.month || check.day != d.day) {
      throw FormatException('Impossible date', iso);
    }
    return d;
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  LocalDate plusDays(int days) =>
      LocalDate.fromDateTime(_utc.add(Duration(days: days)));

  /// Whole days from this date to [other] (negative if [other] is earlier).
  int daysUntil(LocalDate other) => other._utc.difference(_utc).inDays;

  bool operator <(LocalDate o) => compareTo(o) < 0;
  bool operator <=(LocalDate o) => compareTo(o) <= 0;
  bool operator >(LocalDate o) => compareTo(o) > 0;
  bool operator >=(LocalDate o) => compareTo(o) >= 0;

  static LocalDate min(LocalDate a, LocalDate b) => a <= b ? a : b;
  static LocalDate max(LocalDate a, LocalDate b) => a >= b ? a : b;

  @override
  int compareTo(LocalDate o) {
    if (year != o.year) return year.compareTo(o.year);
    if (month != o.month) return month.compareTo(o.month);
    return day.compareTo(o.day);
  }

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}'
      '-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// Formats a date the way the UI shows it, e.g. "14 Mar".
String shortDate(LocalDate d) => '${d.day} ${_months[d.month - 1]}';
