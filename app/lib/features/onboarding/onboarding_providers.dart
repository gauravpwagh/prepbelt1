import 'package:prep_core/prep_core.dart';

/// The first error in the onboarding form, or null when it is complete.
String? validateOnboarding({
  required String exam,
  required LocalDate? date,
  required String subject,
  required int? minutes,
  required String item,
}) {
  if (exam.trim().isEmpty) return 'Enter the exam name';
  if (date == null) return 'Pick the exam date';
  if (subject.trim().isEmpty) return 'Enter a subject';
  if (minutes == null ||
      minutes < Defaults.dailyMinutesMin ||
      minutes > Defaults.dailyMinutesMax) {
    return 'Daily time must be ${Defaults.dailyMinutesMin}–${Defaults.dailyMinutesMax} minutes';
  }
  if (item.trim().isEmpty) return 'Enter your first item';
  return null;
}
