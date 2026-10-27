import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import 'build_today_plan.dart';

/// "Why is this due?" (CUJ 6): the rule, the cap, and the last 5 events.
class DueExplanation {
  const DueExplanation({
    required this.state,
    required this.deadline,
    required this.effectiveDue,
    required this.text,
    required this.recent,
  });

  final ItemState state;
  final Deadline? deadline;
  final LocalDate? effectiveDue;

  /// The newest event's explanation plus the cap suffix; "Not studied yet."
  /// for an Unread item.
  final String text;

  /// Newest first.
  final List<StudyEvent> recent;
}

class ExplainDue {
  ExplainDue(this._db, this._dayClock);

  final AppDatabase _db;
  final LocalDayClock _dayClock;

  Future<DueExplanation> call(String nodeId) async {
    final node = (await _db.nodesDao.byId(nodeId))!;
    final events = await _db.eventsDao.eventsFor(nodeId);
    final state = deriveState(events);
    final deadline =
        await deadlineForSubject(_db, node.subjectId, _dayClock.today());
    final newest = undoableEvent(events);
    final base = newest?.outcome?.explanation ?? 'Not studied yet.';
    return DueExplanation(
      state: state,
      deadline: deadline,
      effectiveDue: effectiveDue(state, deadline),
      text: '$base${capSuffix(state, deadline) ?? ''}',
      recent: await _db.eventsDao.lastN(nodeId, 5),
    );
  }
}
