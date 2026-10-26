import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

(PlanInput, DayPlan) _plan(List<PlanItem> items, {int budget = 90}) {
  final input = PlanInput(today: day(0), budget: budget, items: items);
  return (input, buildPlan(input));
}

void main() {
  test('no waiting → no offer, empty proposal', () {
    final (input, plan) = _plan([dueItem('a', 0)]);
    expect(shouldOffer(plan), isFalse);
    expect(propose(input, plan).isEmpty, isTrue);
  });

  test('waiting reviews move to tomorrow when it has room', () {
    // No unread → share 90; 15 reviews × 10 min → 9 placed, 6 waiting.
    final (input, plan) = _plan([for (var i = 0; i < 15; i++) dueItem('r$i', i, base: 40)]);
    expect(shouldOffer(plan), isTrue);
    expect(plan.waitingCount, 6);
    final p = propose(input, plan);
    expect(p.assignments.length, 6);
    expect(p.assignments.every((a) => a.date == day(1)), isTrue);
    expect(p.days, 2);
    expect(p.wontFit, isEmpty);
    // Today's placed rows are never moved.
    final moved = {for (final a in p.assignments) a.nodeId};
    expect(moved.intersection({for (final r in plan.rows) r.nodeId}), isEmpty);
  });

  test('capacity counts reviews already due on later days', () {
    final (input, plan) = _plan([
      for (var i = 0; i < 15; i++) dueItem('r$i', i, base: 40),
      for (var i = 0; i < 9; i++) dueItem('t$i', 100 + i, base: 40, due: 1, last: -2),
    ]);
    final p = propose(input, plan);
    expect(p.assignments.every((a) => a.date == day(2)), isTrue);
    expect(p.days, 3);
  });

  test('exam in 2 days with a full tomorrow → placed anyway, counted in wontFit', () {
    final exam = examIn(2);
    final (input, plan) = _plan([
      for (var i = 0; i < 12; i++) dueItem('r$i', i, base: 40, deadline: exam),
      for (var i = 0; i < 9; i++) dueItem('t$i', 100 + i, base: 40, due: 1, last: -2),
    ]);
    expect(plan.waitingCount, 3);
    final p = propose(input, plan);
    expect(p.assignments.length, 3);
    expect(p.assignments.every((a) => a.date == day(1)), isTrue);
    expect(p.wontFit, {'x1': 3});
    expect(p.wontFitMinutes, {'x1': 30});
    expect(p.daysUntilExam, {'x1': 2});
    expect(p.extraMinutesPerDay('x1'), 15);
  });

  test('exam tomorrow → stays waiting, counted in wontFit', () {
    final exam = examIn(1);
    final (input, plan) = _plan([
      for (var i = 0; i < 12; i++) dueItem('r$i', i, base: 40, deadline: exam),
    ]);
    expect(plan.waitingCount, 3);
    final p = propose(input, plan);
    expect(p.assignments, isEmpty);
    expect(p.days, 0);
    expect(p.wontFit, {'x1': 3});
    expect(p.extraMinutesPerDay('x1'), 30);
  });

  for (final (label, deadline) in [('far deadline', examIn(60, id: 'far')), ('no deadline', null)]) {
    test('no room in the horizon, $label → stays waiting', () {
      final (input, plan) = _plan([
        for (var i = 0; i < 12; i++) dueItem('r$i', i, base: 40, deadline: deadline),
        // Fill days 1 and 2 completely.
        for (var d = 1; d <= 2; d++)
          for (var i = 0; i < 9; i++)
            dueItem('f$d$i', 100 + d * 10 + i, base: 40, due: d, last: -2),
      ]);
      expect(plan.waitingCount, 3);
      final p = propose(input, plan, horizon: 3);
      expect(p.assignments, isEmpty);
      expect(p.wontFit, isEmpty);
    });
  }

  test('assignments never land after deadline − 1', () {
    final exam = examIn(4);
    final (input, plan) = _plan([
      for (var i = 0; i < 40; i++) dueItem('r$i', i, base: 40, deadline: exam),
    ]);
    final p = propose(input, plan);
    expect(p.assignments.every((a) => a.date <= day(3)), isTrue);
    expect(p.wontFit['x1'], greaterThan(0));
  });
}
