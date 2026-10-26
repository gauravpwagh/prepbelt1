import 'belt.dart';
import 'events.dart';
import 'grade.dart';
import 'item_state.dart';
import 'local_date.dart';

/// Bumped whenever the ladder or the rules change; stored on every event.
const schedulerVersion = 1;

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// First study: Unread → Red, next review tomorrow.
Outcome firstStudy(LocalDate date) => Outcome(
      beltBefore: Belt.unread,
      beltAfter: Belt.red,
      intervalDays: 1,
      ladderDue: date.plusDays(1),
      explanation: 'First read → Red. Next review in 1 day.',
    );

/// A graded review (design §3). [state] must not be Unread.
Outcome review(ItemState state, Grade grade, LocalDate date) {
  final from = state.belt;
  if (from == Belt.unread) {
    throw StateError('An unread item must be first-studied before review.');
  }
  late final Belt to;
  late final int n;
  late final String text;
  switch (grade) {
    case Grade.solid:
      to = from.up();
      n = to.interval!;
      text = from == Belt.green
          ? 'Solid at Green → stays Green. Next review in ${_days(n)}.'
          : 'Solid at ${from.label} → ${to.label}. Next review in ${_days(n)}.';
    case Grade.shaky:
      to = from;
      n = from.shakyInterval!;
      text = from == Belt.red
          ? 'Shaky at Red: next review in 1 day.'
          : 'Shaky at ${from.label}: ${_days(from.interval!)} halved → ${_days(n)}.';
    case Grade.forgot:
      to = from.down();
      n = 1;
      text = from == Belt.red
          ? 'Forgot at Red → stays Red. Quick look tomorrow.'
          : 'Forgot at ${from.label} → ${to.label}. Quick look tomorrow.';
  }
  return Outcome(
    beltBefore: from,
    beltAfter: to,
    intervalDays: n,
    ladderDue: date.plusDays(n),
    explanation: text,
  );
}

/// Catch-up move: the belt stays, only the ladder due date changes.
Outcome reschedule(ItemState state, LocalDate newDue) {
  if (state.belt == Belt.unread) {
    throw StateError('Only studied items can be rescheduled.');
  }
  return Outcome(
    beltBefore: state.belt,
    beltAfter: state.belt,
    intervalDays: null,
    ladderDue: newDue,
    explanation: 'Moved by catch-up to ${shortDate(newDue)}.',
  );
}

/// Message on the grade sheet after a drop, e.g. "Back to Orange — quick look tomorrow."
String dropMessage(Belt belt) => 'Back to ${belt.label} — quick look tomorrow.';
