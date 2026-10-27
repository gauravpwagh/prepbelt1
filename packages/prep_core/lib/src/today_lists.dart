import 'package:meta/meta.dart';

import 'effective_due.dart';
import 'local_date.dart';
import 'planner.dart';

/// A studied item due after today.
@immutable
final class UpcomingItem {
  const UpcomingItem(this.item, this.due);
  final PlanItem item;

  /// The effective (exam-capped) due date.
  final LocalDate due;
}

/// What Today lists beyond the frozen plan (design D16, §4).
@immutable
final class TodayLists {
  const TodayLists({
    required this.dueBeyond,
    required this.unreadBeyond,
    required this.upcoming,
  });

  /// Due reviews not in today's plan, in planner order (below the line).
  final List<PlanItem> dueBeyond;

  /// Unread items not in today's plan, in sort order (below the line).
  final List<PlanItem> unreadBeyond;

  /// Studied items due after today, by date, then in planner order.
  final List<UpcomingItem> upcoming;
}

/// Splits [input]'s items into the rows below the line and Coming up.
/// [plannedIds] are the nodes with a row in today's plan, done or not.
/// Pure: same input, same output.
TodayLists todayLists(PlanInput input, Set<String> plannedIds) {
  final today = input.today;
  final dueBeyond = <PlanItem>[];
  final unreadBeyond = <PlanItem>[];
  final upcoming = <UpcomingItem>[];
  for (final i in input.items) {
    if (i.isUnread) {
      if (!plannedIds.contains(i.nodeId)) unreadBeyond.add(i);
      continue;
    }
    final due = effectiveDue(i.state, i.deadline)!;
    if (due > today) {
      upcoming.add(UpcomingItem(i, due));
    } else if (!plannedIds.contains(i.nodeId)) {
      dueBeyond.add(i);
    }
  }
  dueBeyond.sort((a, b) => compareDue(a, b, today));
  unreadBeyond.sort((a, b) => a.sortKey.compareTo(b.sortKey));
  upcoming.sort((a, b) {
    final c = a.due.compareTo(b.due);
    return c != 0 ? c : compareDue(a.item, b.item, a.due);
  });
  return TodayLists(dueBeyond: dueBeyond, unreadBeyond: unreadBeyond, upcoming: upcoming);
}

/// Coming up's groups: one per day for days 1–7, then next week, then later.
enum UpcomingBucket { day, nextWeek, later }

UpcomingBucket upcomingBucket(LocalDate due, LocalDate today) {
  final d = today.daysUntil(due);
  if (d <= 7) return UpcomingBucket.day;
  if (d <= 14) return UpcomingBucket.nextWeek;
  return UpcomingBucket.later;
}
