import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import 'add_item.dart';
import 'build_today_plan.dart';
import 'mark_studied.dart';
import 'save_exam.dart';

class OnboardingInput {
  const OnboardingInput({
    required this.examName,
    required this.examDate,
    required this.subjectName,
    required this.dailyMinutes,
    required this.itemTitle,
    this.taskKind = TaskKind.reading,
    this.studiedToday = false,
  });

  final String examName;
  final LocalDate examDate;
  final String subjectName;
  final int dailyMinutes;
  final String itemTitle;
  final TaskKind taskKind;
  final bool studiedToday;
}

/// The data part of onboarding (CUJ 1): exam, subject, daily minutes and the
/// first item. The plan is built before the item's first study is written,
/// so a "Studied today" item shows as a done first-reading row.
class CompleteOnboarding {
  CompleteOnboarding(this._db, this._exams, this._addItem, this._plans, this._markStudied);

  final AppDatabase _db;
  final SaveExam _exams;
  final AddItem _addItem;
  final BuildTodayPlan _plans;
  final MarkStudied _markStudied;

  /// Returns the first item's ID.
  Future<String> call(OnboardingInput i) async {
    final itemId = await _db.transaction(() async {
      await _db.settingsDao.setDailyMinutes(i.dailyMinutes);
      final existing = [
        for (final s in await _db.subjectsDao.findByName(i.subjectName))
          if (!s.isInbox) s,
      ];
      final subjectId = existing.isNotEmpty
          ? existing.first.id
          : await _exams.createSubject(i.subjectName);
      await _exams.create(i.examName, i.examDate, {subjectId});
      return _addItem(AddItemRequest(
          title: i.itemTitle, subjectId: subjectId, taskKind: i.taskKind));
    });
    await _plans.refresh();
    if (i.studiedToday) {
      await _markStudied(itemId, await _markStudied.defaultMinutes(itemId));
    }
    await _db.settingsDao.setOnboardingDone(true);
    return itemId;
  }
}
