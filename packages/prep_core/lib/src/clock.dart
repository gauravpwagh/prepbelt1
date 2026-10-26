import 'local_date.dart';

/// The only source of "now" for rules code. The app supplies a system clock;
/// tests supply [FixedClock].
abstract interface class Clock {
  DateTime nowUtc();
}

/// Returns the UTC offset in force at [utc] for the user's time zone.
/// The app builds this from the `timezone` package, so DST is handled there.
typedef OffsetFn = Duration Function(DateTime utc);

/// Decides what "today" is. The study day starts at [dayStartHour] local time,
/// so 00:30 still belongs to the previous day when the hour is 4 (design §5).
class LocalDayClock {
  LocalDayClock(this.clock, this.offset, {this.dayStartHour = 4})
      : assert(dayStartHour >= 0 && dayStartHour < 24);

  final Clock clock;
  final OffsetFn offset;
  final int dayStartHour;

  LocalDate today() => dayOf(clock.nowUtc());

  /// The study day an instant belongs to.
  LocalDate dayOf(DateTime utc) {
    final u = utc.toUtc();
    final local = u.add(offset(u)).subtract(Duration(hours: dayStartHour));
    return LocalDate(local.year, local.month, local.day);
  }
}

/// A clock for tests that only moves when told to.
class FixedClock implements Clock {
  FixedClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime utc) => _now = utc.toUtc();
}
