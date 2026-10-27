// Catch-up (design §4, CUJ 5, plan items 81–82).
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../data/study_writer.dart';
import 'build_today_plan.dart';

/// What the catch-up card offers today.
class CatchUpOffer {
  const CatchUpOffer({
    required this.proposal,
    required this.budget,
    required this.examNames,
  });

  final Proposal proposal;
  final int budget;
  final Map<String, String> examNames;

  int get count => proposal.assignments.length;

  /// "3 can't fit before MPSC Prelims at 90 min/day — about 15 more min/day
  /// would fit them." (D12), one per exam.
  List<String> get wontFitLines => [
        for (final MapEntry(key: exam, value: n) in proposal.wontFit.entries)
          '$n can\'t fit before ${examNames[exam] ?? 'the exam'} at $budget min/day'
              '${proposal.extraMinutesPerDay(exam) > 0 ? ' — about ${proposal.extraMinutesPerDay(exam)} more min/day would fit them' : ''}.',
      ];
}

class CatchUp {
  CatchUp(this._db, this._writer, this._plans, this._dayClock,
      {required String Function() newId})
      : _newId = newId;

  final AppDatabase _db;
  final StudyWriter _writer;
  final BuildTodayPlan _plans;
  final LocalDayClock _dayClock;
  final String Function() _newId;

  /// The offer, shown once per study day while reviews are waiting.
  Future<CatchUpOffer?> offer() async {
    final today = _dayClock.today();
    final header = (await _plans.get()).header;
    if (header.waitingCount == 0) return null;
    if (header.catchUpState != CatchUpState.none &&
        header.catchUpState != CatchUpState.offered) {
      return null;
    }
    final (input, plan) = await _plans.compute();
    if (!shouldOffer(plan)) return null;
    final proposal = propose(input, plan);
    if (proposal.isEmpty) return null;
    if (header.catchUpState == CatchUpState.none) {
      await _db.plansDao.setCatchUp(today, CatchUpState.offered);
    }
    return CatchUpOffer(
      proposal: proposal,
      budget: input.budget,
      examNames: {for (final e in await _db.examsDao.all()) e.id: e.name},
    );
  }

  /// Accept: one `reschedule` per assigned item, sharing a batch ID; belts
  /// unchanged; today's plan refreshed with done rows kept.
  Future<String> accept(CatchUpOffer offer) async {
    final today = _dayClock.today();
    final batch = _newId();
    await _writer.writeRescheduleBatch(
        {for (final a in offer.proposal.assignments) a.nodeId: a.date}, batch);
    await _db.plansDao.setCatchUp(today, CatchUpState.accepted, batchId: batch);
    await _plans.refresh();
    return batch;
  }

  /// Hides the offer until the next study day.
  Future<void> decline() =>
      _db.plansDao.setCatchUp(_dayClock.today(), CatchUpState.declined);

  /// "Undo catch-up", available on the study day it was accepted. Returns
  /// how many reschedules were undone.
  Future<int> undo() async {
    final today = _dayClock.today();
    final header = (await _db.plansDao.planFor(today))?.header;
    final batch = header?.catchUpBatchId;
    if (header?.catchUpState != CatchUpState.accepted || batch == null) return 0;
    final n = await _writer.undoBatch(batch);
    await _db.plansDao.setCatchUp(today, CatchUpState.offered);
    await _plans.refresh();
    return n;
  }
}
