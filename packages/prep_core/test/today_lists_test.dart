import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('rows below the line: due in planner order, unread in sort order', () {
    final input = PlanInput(today: day(0), budget: 45, items: [
      dueItem('late', 3, due: -2),
      dueItem('now', 1),
      dueItem('planned', 0),
      unreadItem('u2', 12),
      unreadItem('u1', 11),
      unreadItem('uPlanned', 10),
    ]);
    final l = todayLists(input, {'planned', 'uPlanned'});
    expect([for (final i in l.dueBeyond) i.nodeId], ['late', 'now']);
    expect([for (final i in l.unreadBeyond) i.nodeId], ['u1', 'u2']);
    expect(l.upcoming, isEmpty);
  });

  test('Coming up: by date, exam cap applied, done items move here', () {
    final input = PlanInput(today: day(0), budget: 45, items: [
      dueItem('d3', 0, last: 0, due: 3),
      dueItem('d1b', 2, last: 0, due: 1),
      dueItem('d1a', 1, last: 0, due: 1),
      dueItem('capped', 3, last: -1, due: 20, deadline: examIn(6)),
    ]);
    // 'd1a' was done today: it is in the plan, but no longer due.
    final l = todayLists(input, {'d1a'});
    expect([for (final u in l.upcoming) u.item.nodeId], ['d1a', 'd1b', 'd3', 'capped']);
    expect(l.upcoming.last.due, day(5));
    expect(l.dueBeyond, isEmpty);
  });

  test('upcomingBucket boundaries', () {
    UpcomingBucket b(int d) => upcomingBucket(day(d), day(0));
    expect([b(1), b(7), b(8), b(14), b(15)], [
      UpcomingBucket.day,
      UpcomingBucket.day,
      UpcomingBucket.nextWeek,
      UpcomingBucket.nextWeek,
      UpcomingBucket.later,
    ]);
  });
}
