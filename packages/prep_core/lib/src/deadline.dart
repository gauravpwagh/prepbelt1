import 'package:meta/meta.dart';

import 'local_date.dart';

@immutable
final class ExamRef {
  const ExamRef({
    required this.id,
    required this.name,
    required this.date,
    this.archived = false,
  });

  final String id;
  final String name;
  final LocalDate date;
  final bool archived;
}

@immutable
final class Deadline {
  const Deadline({
    required this.examId,
    required this.examName,
    required this.date,
  });

  final String examId;
  final String examName;
  final LocalDate date;

  @override
  bool operator ==(Object other) =>
      other is Deadline && other.examId == examId && other.date == date;

  @override
  int get hashCode => Object.hash(examId, date);
}

/// The earliest exam linked to the item's subject that is not archived and is
/// dated after [today]. An exam taking place today no longer caps anything.
Deadline? resolveDeadline(Iterable<ExamRef> exams, LocalDate today) {
  ExamRef? best;
  for (final e in exams) {
    if (e.archived || e.date <= today) continue;
    if (best == null ||
        e.date < best.date ||
        (e.date == best.date && e.id.compareTo(best.id) < 0)) {
      best = e;
    }
  }
  return best == null
      ? null
      : Deadline(examId: best.id, examName: best.name, date: best.date);
}
