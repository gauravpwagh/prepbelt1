import 'package:meta/meta.dart';

import 'belt.dart';
import 'deadline.dart';
import 'defaults.dart';
import 'effective_due.dart';
import 'hierarchy.dart';
import 'item_state.dart';
import 'local_date.dart';

enum RowType {
  review('review'),
  firstRead('first_read');

  const RowType(this.key);
  final String key;
}

enum Reason {
  due('due'),
  overdue('overdue'),
  deadlineRisk('deadline_risk'),
  catchUp('catch_up'),
  firstRead('first_read');

  const Reason(this.key);
  final String key;
}

@immutable
final class PlanItem {
  const PlanItem({
    required this.nodeId,
    required this.state,
    required this.baseMinutes,
    required this.sortKey,
    this.deadline,
    this.newestIsReschedule = false,
  });

  final String nodeId;
  final ItemState state;
  final int baseMinutes;
  final Deadline? deadline;
  final SortKey sortKey;
  final bool newestIsReschedule;

  bool get isUnread => state.belt == Belt.unread;
}

@immutable
final class DoneRow {
  const DoneRow(this.nodeId, this.type, this.minutes);
  final String nodeId;
  final RowType type;
  final int minutes;
}

@immutable
final class PlanInput {
  const PlanInput({
    required this.today,
    required this.budget,
    required this.items,
    this.done = const [],
  });

  final LocalDate today;
  final int budget;

  /// Reviewable items outside the Inbox.
  final List<PlanItem> items;

  /// Rows already finished today (they count against the budget first).
  final List<DoneRow> done;
}

@immutable
final class PlanRow {
  const PlanRow(this.nodeId, this.type, this.minutes, this.reason);
  final String nodeId;
  final RowType type;
  final int minutes;
  final Reason reason;

  @override
  String toString() => 'PlanRow($nodeId, ${type.key}, $minutes, ${reason.key})';
}

@immutable
final class DayPlan {
  const DayPlan({
    required this.rows,
    required this.reviewMinutes,
    required this.firstReadMinutes,
    required this.waitingNodeIds,
    required this.waitingMinutes,
    required this.reviewShare,
    required this.reserve,
    required this.splitSuggested,
    required this.summary,
  });

  /// Planned rows not yet done: reviews (priority order) then first readings.
  final List<PlanRow> rows;
  final int reviewMinutes;
  final int firstReadMinutes;

  /// Due reviews that did not fit, in priority order.
  final List<String> waitingNodeIds;
  final int waitingMinutes;
  final int reviewShare;
  final int reserve;
  final List<String> splitSuggested;
  final String summary;

  int get waitingCount => waitingNodeIds.length;
}

/// Minutes one review of an item takes: max(3, ceil(base × 0.25)).
int reviewCost(int baseMinutes) {
  final c = (baseMinutes * Defaults.reviewFraction).ceil();
  return c < Defaults.minReviewMinutes ? Defaults.minReviewMinutes : c;
}

/// Minutes kept for first readings while unread items exist (design §4 step 1).
int reserveFor(int budget, Iterable<PlanItem> unreadInSortOrder) {
  if (unreadInSortOrder.isEmpty) return 0;
  final share = (budget * Defaults.reserveFraction).ceil();
  final first = unreadInSortOrder.first.baseMinutes;
  final want = share > first ? share : first;
  return want < budget ? want : budget;
}

/// Priority order for due reviews (design §4 step 2).
int compareDue(PlanItem a, PlanItem b, LocalDate today) {
  int toDeadline(PlanItem i) =>
      i.deadline == null ? 1 << 30 : today.daysUntil(i.deadline!.date);
  int overdue(PlanItem i) =>
      effectiveDue(i.state, i.deadline)!.daysUntil(today);

  var c = toDeadline(a).compareTo(toDeadline(b));
  if (c != 0) return c;
  c = overdue(b).compareTo(overdue(a)); // more overdue first
  if (c != 0) return c;
  c = a.state.belt.step.compareTo(b.state.belt.step);
  if (c != 0) return c;
  return a.sortKey.compareTo(b.sortKey);
}

Reason reasonFor(PlanItem item, LocalDate today) {
  if (item.newestIsReschedule) return Reason.catchUp;
  final d = item.deadline;
  if (d != null && today.daysUntil(d.date) <= Defaults.deadlineRiskDays) {
    return Reason.deadlineRisk;
  }
  final eff = effectiveDue(item.state, item.deadline)!;
  return eff < today ? Reason.overdue : Reason.due;
}

/// Builds today's plan (design §4). Pure: same input, same output.
DayPlan buildPlan(PlanInput input) {
  final today = input.today;
  final doneIds = {for (final d in input.done) d.nodeId};
  final candidates = [
    for (final i in input.items)
      if (!doneIds.contains(i.nodeId)) i,
  ];

  final unread = [
    for (final i in candidates)
      if (i.isUnread) i,
  ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  final due = [
    for (final i in candidates)
      if (!i.isUnread && effectiveDue(i.state, i.deadline)! <= today) i,
  ]..sort((a, b) => compareDue(a, b, today));

  final reserve = reserveFor(input.budget, unread);
  final reviewShare = input.budget - reserve;

  var doneReview = 0;
  var doneFirst = 0;
  for (final d in input.done) {
    if (d.type == RowType.review) {
      doneReview += d.minutes;
    } else {
      doneFirst += d.minutes;
    }
  }
  var reviewLeft = reviewShare - doneReview;
  if (reviewLeft < 0) reviewLeft = 0;
  var reserveLeft = reserve - doneFirst;
  if (reserveLeft < 0) reserveLeft = 0;

  // Step 2: reviews into the review share.
  final placed = <String>{};
  for (final i in due) {
    final cost = reviewCost(i.baseMinutes);
    if (cost <= reviewLeft) {
      placed.add(i.nodeId);
      reviewLeft -= cost;
    }
  }

  // Step 3: first readings into the reserve plus unused review share.
  var firstLeft = reserveLeft + reviewLeft;
  final firstRows = <PlanRow>[];
  for (final u in unread) {
    if (u.baseMinutes <= firstLeft) {
      firstRows.add(PlanRow(u.nodeId, RowType.firstRead, u.baseMinutes, Reason.firstRead));
      firstLeft -= u.baseMinutes;
    }
  }

  // Step 4: second pass — leftover minutes to unplaced due reviews.
  for (final i in due) {
    if (placed.contains(i.nodeId)) continue;
    final cost = reviewCost(i.baseMinutes);
    if (cost <= firstLeft) {
      placed.add(i.nodeId);
      firstLeft -= cost;
    }
  }

  final reviewRows = <PlanRow>[];
  final waiting = <String>[];
  var waitingMinutes = 0;
  for (final i in due) {
    final cost = reviewCost(i.baseMinutes);
    if (placed.contains(i.nodeId)) {
      reviewRows.add(PlanRow(i.nodeId, RowType.review, cost, reasonFor(i, today)));
    } else {
      waiting.add(i.nodeId);
      waitingMinutes += cost;
    }
  }

  final reviewMinutes = reviewRows.fold(0, (s, r) => s + r.minutes);
  final firstReadMinutes = firstRows.fold(0, (s, r) => s + r.minutes);
  final splitSuggested = [
    for (final u in unread)
      if (u.baseMinutes > input.budget) u.nodeId,
  ];

  return DayPlan(
    rows: [...reviewRows, ...firstRows],
    reviewMinutes: reviewMinutes,
    firstReadMinutes: firstReadMinutes,
    waitingNodeIds: waiting,
    waitingMinutes: waitingMinutes,
    reviewShare: reviewShare,
    reserve: reserve,
    splitSuggested: splitSuggested,
    summary: planSummary(reviewMinutes, firstReadMinutes, waiting.length),
  );
}

/// "40 min reviews · 20 min new reading · 4 waiting" or "Nothing due today".
String planSummary(int reviewMinutes, int firstReadMinutes, int waiting) {
  if (reviewMinutes == 0 && firstReadMinutes == 0) {
    return waiting > 0 ? 'Nothing fits today · $waiting waiting' : 'Nothing due today';
  }
  final base = '$reviewMinutes min reviews · $firstReadMinutes min new reading';
  return waiting > 0 ? '$base · $waiting waiting' : base;
}
