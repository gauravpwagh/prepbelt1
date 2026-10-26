import 'package:meta/meta.dart';

import 'defaults.dart';
import 'effective_due.dart';
import 'local_date.dart';
import 'planner.dart';

@immutable
final class Assignment {
  const Assignment(this.nodeId, this.date);
  final String nodeId;
  final LocalDate date;

  @override
  String toString() => 'Assignment($nodeId → $date)';
}

@immutable
final class Proposal {
  const Proposal({
    required this.assignments,
    required this.days,
    required this.wontFit,
    this.wontFitMinutes = const {},
    this.daysUntilExam = const {},
  });

  /// Waiting items moved to a later day (each becomes a `reschedule` event).
  final List<Assignment> assignments;

  /// Days the spread covers, today counted as day 1. 0 if nothing moves.
  final int days;

  /// examId → number of waiting reviews that can't fit before that exam.
  final Map<String, int> wontFit;

  /// examId → review minutes of the items counted in [wontFit].
  final Map<String, int> wontFitMinutes;

  /// examId → days from today to the exam (for the shortfall message).
  final Map<String, int> daysUntilExam;

  bool get isEmpty => assignments.isEmpty && wontFit.isEmpty;

  /// Extra daily minutes that would fit the shortfall before [examId]
  /// (decision D12): ceil(minutes that don't fit / days left before the exam).
  int extraMinutesPerDay(String examId) {
    final minutes = wontFitMinutes[examId] ?? 0;
    if (minutes == 0) return 0;
    final days = daysUntilExam[examId] ?? 1;
    return (minutes / (days < 1 ? 1 : days)).ceil();
  }
}

/// Offer catch-up whenever today's plan has waiting reviews.
bool shouldOffer(DayPlan today) => today.waitingCount > 0;

/// Spreads today's waiting reviews over the next days (design §4).
///
/// Today's placed rows stay where they are. Each waiting item goes to the
/// earliest day d ∈ 1…horizon−1 that still has review capacity and is no later
/// than `latest` (deadline − 1, or the horizon end with no deadline).
///
/// When no day has room:
///  * deadline within the horizon → placed on `latest` anyway (over capacity)
///    and counted in [Proposal.wontFit];
///  * exam tomorrow (latest ≤ today) → stays waiting, counted in wontFit;
///  * deadline beyond the horizon, or no deadline → stays waiting.
Proposal propose(
  PlanInput input,
  DayPlan today, {
  int horizon = Defaults.catchUpHorizon,
}) {
  final t = input.today;
  final byId = {for (final i in input.items) i.nodeId: i};
  final waitingSet = today.waitingNodeIds.toSet();

  // Projected review load on future days from items already due then.
  final capacity = List<int>.filled(horizon, today.reviewShare);
  capacity[0] = 0; // today is fixed
  for (final i in input.items) {
    if (i.isUnread || waitingSet.contains(i.nodeId)) continue;
    final eff = effectiveDue(i.state, i.deadline);
    if (eff == null) continue;
    final d = t.daysUntil(eff);
    if (d >= 1 && d < horizon) capacity[d] -= reviewCost(i.baseMinutes);
  }

  final assignments = <Assignment>[];
  final wontFit = <String, int>{};
  final wontFitMinutes = <String, int>{};
  final daysUntilExam = <String, int>{};
  void countWontFit(String examId, int cost, int daysToExam) {
    wontFit[examId] = (wontFit[examId] ?? 0) + 1;
    wontFitMinutes[examId] = (wontFitMinutes[examId] ?? 0) + cost;
    daysUntilExam[examId] = daysToExam;
  }

  var maxDay = 0;

  for (final id in today.waitingNodeIds) {
    final item = byId[id];
    if (item == null) continue;
    final cost = reviewCost(item.baseMinutes);
    final deadline = item.deadline;
    final latestOffset =
        deadline == null ? horizon - 1 : t.daysUntil(deadline.date) - 1;

    if (deadline != null && latestOffset <= 0) {
      countWontFit(deadline.examId, cost, latestOffset + 1);
      continue;
    }

    final lastDay = latestOffset < horizon - 1 ? latestOffset : horizon - 1;
    int? chosen;
    for (var d = 1; d <= lastDay; d++) {
      if (capacity[d] >= cost) {
        chosen = d;
        break;
      }
    }

    if (chosen == null) {
      if (deadline != null && latestOffset <= horizon - 1) {
        chosen = latestOffset;
        countWontFit(deadline.examId, cost, latestOffset + 1);
      } else {
        continue; // stays waiting
      }
    }

    capacity[chosen] -= cost;
    assignments.add(Assignment(id, t.plusDays(chosen)));
    if (chosen > maxDay) maxDay = chosen;
  }

  return Proposal(
    assignments: assignments,
    days: assignments.isEmpty ? 0 : maxDay + 1,
    wontFit: wontFit,
    wontFitMinutes: wontFitMinutes,
    daysUntilExam: daysUntilExam,
  );
}
