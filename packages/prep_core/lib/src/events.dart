import 'package:meta/meta.dart';

import 'belt.dart';
import 'grade.dart';
import 'local_date.dart';

/// What an event did to an item. Stored with the event so state never has to
/// be recomputed from the whole history (design §2).
@immutable
final class Outcome {
  const Outcome({
    required this.beltBefore,
    required this.beltAfter,
    required this.intervalDays,
    required this.ladderDue,
    required this.explanation,
  });

  final Belt beltBefore;
  final Belt beltAfter;

  /// Null for reschedules.
  final int? intervalDays;
  final LocalDate? ladderDue;
  final String explanation;

  @override
  bool operator ==(Object o) =>
      o is Outcome &&
      o.beltBefore == beltBefore &&
      o.beltAfter == beltAfter &&
      o.intervalDays == intervalDays &&
      o.ladderDue == ladderDue &&
      o.explanation == explanation;

  @override
  int get hashCode =>
      Object.hash(beltBefore, beltAfter, intervalDays, ladderDue, explanation);

  @override
  String toString() =>
      'Outcome(${beltBefore.key}→${beltAfter.key}, +$intervalDays, $ladderDue)';
}

/// One row of the append-only `review_events` log.
@immutable
sealed class StudyEvent {
  const StudyEvent({
    required this.id,
    required this.nodeId,
    required this.atUtc,
    required this.localDate,
    required this.tzId,
  });

  final String id;
  final String nodeId;
  final DateTime atUtc;
  final LocalDate localDate;
  final String tzId;

  /// Null only for [Undo].
  Outcome? get outcome;

  String get typeKey;
}

final class FirstStudy extends StudyEvent {
  const FirstStudy({
    required super.id,
    required super.nodeId,
    required super.atUtc,
    required super.localDate,
    required super.tzId,
    required this.minutes,
    this.sessionId,
    required this.outcome,
  });

  final int minutes;
  final String? sessionId;
  @override
  final Outcome outcome;
  @override
  String get typeKey => 'first_study';
}

final class Review extends StudyEvent {
  const Review({
    required super.id,
    required super.nodeId,
    required super.atUtc,
    required super.localDate,
    required super.tzId,
    required this.grade,
    required this.minutes,
    this.sessionId,
    required this.outcome,
  });

  final Grade grade;
  final int minutes;
  final String? sessionId;
  @override
  final Outcome outcome;
  @override
  String get typeKey => 'review';
}

final class Reschedule extends StudyEvent {
  const Reschedule({
    required super.id,
    required super.nodeId,
    required super.atUtc,
    required super.localDate,
    required super.tzId,
    required this.batchId,
    required this.outcome,
  });

  final String batchId;
  @override
  final Outcome outcome;
  @override
  String get typeKey => 'reschedule';
}

final class Undo extends StudyEvent {
  const Undo({
    required super.id,
    required super.nodeId,
    required super.atUtc,
    required super.localDate,
    required super.tzId,
    required this.targetId,
  });

  final String targetId;
  @override
  Outcome? get outcome => null;
  @override
  String get typeKey => 'undo';
}
