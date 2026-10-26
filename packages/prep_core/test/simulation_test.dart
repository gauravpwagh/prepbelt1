// Goal 5 simulation (design §12, decision D12). The same model is ported to
// Python in tool/sim/planner_check.py so the maths can be checked without Dart.
import 'dart:math';

import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _Sim {
  _Sim(this.id, this.base, this.subject, this.order);
  final String id;
  final int base;
  final int subject;
  final int order;
  ItemState state = ItemState.unread;
  bool resched = false;
  int? firstStudyDay;
  final reviewDays = <int>[];
}

class _Result {
  double worstOutsideExamWeek = 0;
  double worstExamWeek = 0;
  int missedBeforeExam = 0;
}

_Result _run(int seed, {int items = 300, int budget = 90, int days = 90, double miss = 0.15}) {
  final rnd = Random(seed);
  const bases = [20, 30, 30, 30, 40, 50];
  final sims = [for (var k = 0; k < items; k++) _Sim('n$k', bases[rnd.nextInt(6)], k % 6, k)];
  // Exam A on day 45 (subjects 0–2), exam B on day 80 (subjects 1, 3–5).
  final examA = ExamRef(id: 'A', name: 'Exam A', date: day(45));
  final examB = ExamRef(id: 'B', name: 'Exam B', date: day(80));
  List<ExamRef> examsFor(int subject) => [
        if (subject <= 2) examA,
        if (subject == 1 || subject >= 3) examB,
      ];
  final result = _Result();

  for (var t = 0; t < days; t++) {
    if (rnd.nextDouble() < miss) continue;
    final today = day(t);

    PlanInput input() => PlanInput(today: today, budget: budget, items: [
          for (final s in sims)
            PlanItem(
              nodeId: s.id,
              state: s.state,
              baseMinutes: s.base,
              deadline: resolveDeadline(examsFor(s.subject), today),
              sortKey: SortKey(subjectOrder: 0, taskOrder: s.order, createdAtUtcMs: 0, id: s.id),
              newestIsReschedule: s.resched,
            ),
        ]);

    var plan = buildPlan(input());
    if (shouldOffer(plan)) {
      final proposal = propose(input(), plan);
      final byId = {for (final s in sims) s.id: s};
      for (final a in proposal.assignments) {
        final s = byId[a.nodeId]!;
        final o = reschedule(s.state, a.date);
        s.state = ItemState(
          belt: o.beltAfter,
          ladderDue: o.ladderDue,
          lastReviewDate: s.state.lastReviewDate,
          reviewCount: s.state.reviewCount,
        );
        s.resched = true;
      }
      plan = buildPlan(input());
    }

    if (plan.reviewShare > 0) {
      final ratio = plan.waitingMinutes / plan.reviewShare;
      final examWeek = [examA, examB].any((e) {
        final d = today.daysUntil(e.date);
        return d > 0 && d <= Defaults.deadlineRiskDays;
      });
      if (examWeek) {
        result.worstExamWeek = max(result.worstExamWeek, ratio);
      } else {
        result.worstOutsideExamWeek = max(result.worstOutsideExamWeek, ratio);
      }
    }

    final byId = {for (final s in sims) s.id: s};
    for (final row in plan.rows) {
      final s = byId[row.nodeId]!;
      if (row.type == RowType.review) {
        final r = rnd.nextDouble();
        final g = r < 0.6 ? Grade.solid : (r < 0.9 ? Grade.shaky : Grade.forgot);
        final o = review(s.state, g, today);
        s.state = ItemState(
          belt: o.beltAfter,
          ladderDue: o.ladderDue,
          lastReviewDate: today,
          reviewCount: s.state.reviewCount + 1,
        );
        s.resched = false;
        s.reviewDays.add(t);
      } else {
        final o = firstStudy(today);
        s.state = ItemState(belt: o.beltAfter, ladderDue: o.ladderDue, lastReviewDate: today);
        s.firstStudyDay = t;
      }
    }
  }

  for (final s in sims) {
    final first = s.firstStudyDay;
    if (first == null) continue;
    for (final e in examsFor(s.subject)) {
      final examDay = t0.daysUntil(e.date);
      if (examDay > days || examDay - first < 3) continue;
      if (!s.reviewDays.any((r) => r > first && r < examDay)) result.missedBeforeExam++;
    }
  }
  return result;
}

void main() {
  test('Goal 5 across 20 seeds', () {
    for (var seed = 1; seed <= 20; seed++) {
      final r = _run(seed);
      expect(r.worstOutsideExamWeek, lessThanOrEqualTo(3.0),
          reason: 'seed $seed: waiting minutes outside exam week');
      expect(r.missedBeforeExam, 0, reason: 'seed $seed: items without a pre-exam review');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
