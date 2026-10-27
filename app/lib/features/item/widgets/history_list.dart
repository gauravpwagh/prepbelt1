import 'package:flutter/material.dart';
import 'package:prep_core/prep_core.dart';

import '../../../core/format.dart';

/// The last events, newest first: date, grade, belt change, minutes.
class HistoryList extends StatelessWidget {
  const HistoryList(this.events, {super.key});
  final List<StudyEvent> events;

  @override
  Widget build(BuildContext context) {
    final undone = {for (final e in events) if (e is Undo) e.targetId};
    return Column(children: [
      for (final e in events)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(formatShortDate(e.localDate)),
          title: Text(
            _describe(e),
            style: undone.contains(e.id)
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
        ),
    ]);
  }
}

String _describe(StudyEvent e) {
  String belts(Outcome o) => o.beltBefore == o.beltAfter
      ? o.beltAfter.label
      : '${o.beltBefore.label} → ${o.beltAfter.label}';
  return switch (e) {
    FirstStudy(:final outcome, :final minutes) =>
      'First reading · ${belts(outcome)} · ${formatMinutes(minutes)}',
    Review(:final grade, :final outcome, :final minutes) =>
      '${grade.label} · ${belts(outcome)} · ${formatMinutes(minutes)}',
    Reschedule(:final outcome) =>
      'Catch-up · moved to ${formatShortDate(outcome.ladderDue!)}',
    Undo() => 'Undo',
  };
}
