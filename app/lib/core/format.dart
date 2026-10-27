import 'package:intl/intl.dart';
import 'package:prep_core/prep_core.dart';

final _short = DateFormat('d MMM');
final _weekday = DateFormat('EEE d');

/// UI dates: "14 Mar".
String formatShortDate(LocalDate d) =>
    _short.format(DateTime(d.year, d.month, d.day));

/// "1 h 20 min", "45 min".
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "Today", "Tomorrow", "Yesterday" or "14 Mar", relative to [today].
String formatRelativeDay(LocalDate d, LocalDate today) =>
    switch (today.daysUntil(d)) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => formatShortDate(d),
    };

/// Coming up's day labels (design D16): "Tomorrow", then "Thu 29".
String formatWeekdayDay(LocalDate d, LocalDate today) => today.daysUntil(d) == 1
    ? 'Tomorrow'
    : _weekday.format(DateTime(d.year, d.month, d.day));
