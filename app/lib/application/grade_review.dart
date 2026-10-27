import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/study_writer.dart';
import 'build_today_plan.dart';

/// One choice on the grade sheet: the outcome and the date it leads to.
class GradeOption {
  const GradeOption(this.grade, this.outcome, this.nextDue, this.capNote);
  final Grade grade;
  final Outcome outcome;

  /// The effective (exam-capped) next date.
  final LocalDate nextDue;

  /// " Capped by … on …." when the cap moved the date.
  final String? capNote;

  /// "Back to Orange — quick look tomorrow." when Forgot drops the belt.
  String? get dropNote => outcome.beltAfter.step < outcome.beltBefore.step
      ? dropMessage(outcome.beltAfter)
      : null;
}

class GradePreview {
  const GradePreview({
    required this.title,
    required this.belt,
    required this.isPyq,
    required this.defaultMinutes,
    required this.options,
  });
  final String title;
  final Belt belt;
  final bool isPyq;

  /// The review cost, pre-filled when there was no timer.
  final int defaultMinutes;
  final List<GradeOption> options;
}

/// A graded review (plan item 76).
class GradeReview {
  GradeReview(this._db, this._writer, this._plans, this._dayClock);

  final AppDatabase _db;
  final StudyWriter _writer;
  final BuildTodayPlan _plans;
  final LocalDayClock _dayClock;

  Future<GradePreview> preview(String nodeId) async {
    final node = (await _db.nodesDao.byId(nodeId))!;
    final state = await _db.itemStateDao.stateOf(nodeId);
    final today = _dayClock.today();
    final deadline = await deadlineForSubject(_db, node.subjectId, today);
    return GradePreview(
      title: node.title,
      belt: state.belt,
      isPyq: node.taskKind == TaskKind.pyq,
      defaultMinutes: reviewCost(node.baseMinutes ?? Defaults.baseMin),
      options: [
        for (final g in Grade.values)
          () {
            final o = review(state, g, today);
            final after = ItemState(
                belt: o.beltAfter,
                ladderDue: o.ladderDue,
                lastReviewDate: today,
                reviewCount: state.reviewCount + 1);
            return GradeOption(g, o, effectiveDue(after, deadline)!,
                capSuffix(after, deadline));
          }(),
      ],
    );
  }

  /// Writes the review. An item that is not in today's plan (a row below the
  /// line, design D16) gets a done `review` row, so the day's minutes count
  /// it.
  Future<Review> call(String nodeId, Grade grade, int minutes,
          {String? sessionId}) =>
      _db.transaction(() async {
        final plan = await _plans.get();
        final inPlan = plan.rows.any((r) => r.nodeId == nodeId);
        final node = (await _db.nodesDao.byId(nodeId))!;
        final state = await _db.itemStateDao.stateOf(nodeId);
        final today = _dayClock.today();
        final due = effectiveDue(state, await deadlineForSubject(_db, node.subjectId, today));
        final e = await _writer.writeReview(nodeId, grade, minutes, sessionId: sessionId);
        if (!inPlan && e.localDate == today) {
          await _db.plansDao.addDoneRow(e.localDate, nodeId, RowType.review, minutes,
              due != null && due < today ? Reason.overdue : Reason.due, e.atUtc);
        }
        return e;
      });
}
