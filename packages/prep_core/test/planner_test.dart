import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

int _total(DayPlan p) => p.reviewMinutes + p.firstReadMinutes;

void main() {
  test('reviewCost', () {
    expect(reviewCost(10), 3);
    expect(reviewCost(20), 5);
    expect(reviewCost(30), 8);
    expect(reviewCost(40), 10);
    expect(reviewCost(50), 13);
  });

  test('defaults: 90 min, one 30-min unread item → reserve 30', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [unreadItem('u1', 1)]));
    expect(p.reserve, 30);
    expect(p.reviewShare, 60);
    expect(p.rows.single.nodeId, 'u1');
    expect(p.summary, '0 min reviews · 30 min new reading');
  });

  test('reviews first, then first readings from reserve + unused share', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [
      for (var i = 0; i < 3; i++) dueItem('r$i', i),
      for (var i = 0; i < 3; i++) unreadItem('u$i', 10 + i),
    ]));
    expect([for (final r in p.rows) r.nodeId], ['r0', 'r1', 'r2', 'u0', 'u1']);
    expect(p.reviewMinutes, 24);
    expect(p.firstReadMinutes, 60);
    expect(p.summary, '24 min reviews · 60 min new reading');
    expect(_total(p), lessThanOrEqualTo(90));
  });

  test('waiting reviews when the share is full', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [
      for (var i = 0; i < 10; i++) dueItem('r$i', i, base: 40),
      unreadItem('u0', 20),
    ]));
    expect(p.reviewMinutes, 60);
    expect(p.firstReadMinutes, 30);
    expect(p.waitingCount, 4);
    expect(p.waitingMinutes, 40);
    expect(p.summary, '60 min reviews · 30 min new reading · 4 waiting');
  });

  test('second pass gives leftover reserve to waiting reviews', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [
      for (var i = 0; i < 10; i++) dueItem('r$i', i, base: 40),
      unreadItem('u0', 20, base: 20),
    ]));
    expect(p.reserve, 27);
    expect(p.reviewMinutes, 70);
    expect(p.firstReadMinutes, 20);
    expect(p.waitingCount, 3);
    expect(_total(p), 90);
  });

  test('no unread items → whole budget for reviews', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [
      for (var i = 0; i < 10; i++) dueItem('r$i', i, base: 40),
    ]));
    expect(p.reserve, 0);
    expect(p.reviewMinutes, 90);
    expect(p.waitingCount, 1);
  });

  test('small budget still fits the next first reading', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 30, items: [
      dueItem('r0', 0),
      unreadItem('u0', 1),
    ]));
    expect(p.reserve, 30);
    expect(p.firstReadMinutes, 30);
    expect(p.waitingCount, 1);
    expect(p.summary, '0 min reviews · 30 min new reading · 1 waiting');
  });

  test('item bigger than the whole budget → split suggested', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 30, items: [unreadItem('big', 0, base: 50)]));
    expect(p.rows, isEmpty);
    expect(p.splitSuggested, ['big']);
    expect(p.summary, 'Nothing due today');
  });

  test('nothing to do', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 90, items: [dueItem('later', 0, due: 5)]));
    expect(p.rows, isEmpty);
    expect(p.summary, 'Nothing due today');
  });

  test('priority: nearer exam, then more overdue, then lower belt, then sort key', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 300, items: [
      dueItem('plain', 0),
      dueItem('lowBelt', 1, belt: Belt.red, last: -1),
      dueItem('overdue', 2, due: -3, last: -6),
      dueItem('exam20', 3, deadline: examIn(20)),
      dueItem('exam5', 4, deadline: examIn(5, id: 'x2')),
    ]));
    expect([for (final r in p.rows) r.nodeId],
        ['exam5', 'exam20', 'overdue', 'lowBelt', 'plain']);
  });

  test('reasons', () {
    final p = buildPlan(PlanInput(today: day(0), budget: 300, items: [
      dueItem('due', 0),
      dueItem('over', 1, due: -2, last: -5),
      dueItem('risk', 2, deadline: examIn(7)),
      dueItem('moved', 3, resched: true, deadline: examIn(5)),
    ]));
    final reasons = {for (final r in p.rows) r.nodeId: r.reason};
    expect(reasons, {
      'due': Reason.due,
      'over': Reason.overdue,
      'risk': Reason.deadlineRisk,
      'moved': Reason.catchUp,
    });
  });

  test('exam cap makes an item due early', () {
    // Ladder due in 10 days, exam in 3 days → due day 2, not today.
    final notYet = dueItem('a', 0, due: 10, last: -2, deadline: examIn(3));
    expect(buildPlan(PlanInput(today: day(0), budget: 90, items: [notYet])).rows, isEmpty);
    expect(buildPlan(PlanInput(today: day(2), budget: 90, items: [notYet])).rows.single.nodeId, 'a');
  });

  test('done rows count against the budget and are not selected again', () {
    final p = buildPlan(PlanInput(
      today: day(0),
      budget: 90,
      items: [
        dueItem('r0', 0),
        dueItem('r1', 1),
        unreadItem('u0', 10),
        unreadItem('u1', 11),
        unreadItem('uDone', 9),
      ],
      done: const [
        DoneRow('r1', RowType.review, 8),
        DoneRow('uDone', RowType.firstRead, 30),
      ],
    ));
    expect([for (final r in p.rows) r.nodeId], ['r0', 'u0']);
    expect(_total(p) + 38, lessThanOrEqualTo(90));
  });

  test('deterministic', () {
    PlanInput input() => PlanInput(today: day(0), budget: 90, items: [
          for (var i = 0; i < 20; i++) dueItem('r$i', 20 - i, base: 20 + i),
          for (var i = 0; i < 5; i++) unreadItem('u$i', i),
        ]);
    expect(buildPlan(input()).rows.toString(), buildPlan(input()).rows.toString());
  });
}
