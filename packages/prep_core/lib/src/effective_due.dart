import 'deadline.dart';
import 'item_state.dart';
import 'local_date.dart';

/// The due date the user sees (design §3). The cap is never stored.
///
///   no ladder date                         → null (item is unread)
///   no deadline, or deadline − 1 ≤ last    → ladderDue
///   otherwise                              → min(ladderDue, deadline − 1)
LocalDate? effectiveDue(ItemState state, Deadline? deadline) {
  final due = state.ladderDue;
  if (due == null) return null;
  if (deadline == null) return due;
  final cap = deadline.date.plusDays(-1);
  final last = state.lastReviewDate;
  if (last != null && cap <= last) return due;
  return LocalDate.min(due, cap);
}

/// " Capped by {exam} on {date}." when the cap moved the date, else null.
String? capSuffix(
  ItemState state,
  Deadline? deadline, [
  String Function(LocalDate) format = shortDate,
]) {
  final eff = effectiveDue(state, deadline);
  if (eff == null || deadline == null || eff == state.ladderDue) return null;
  return ' Capped by ${deadline.examName} on ${format(deadline.date)}.';
}
