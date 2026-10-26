import 'package:meta/meta.dart';

import 'belt.dart';
import 'events.dart';
import 'local_date.dart';

/// Current state of one reviewable item (the `item_state` row).
@immutable
final class ItemState {
  const ItemState({
    required this.belt,
    this.ladderDue,
    this.lastReviewDate,
    this.reviewCount = 0,
  });

  static const unread = ItemState(belt: Belt.unread);

  final Belt belt;
  final LocalDate? ladderDue;
  final LocalDate? lastReviewDate;
  final int reviewCount;

  @override
  bool operator ==(Object o) =>
      o is ItemState &&
      o.belt == belt &&
      o.ladderDue == ladderDue &&
      o.lastReviewDate == lastReviewDate &&
      o.reviewCount == reviewCount;

  @override
  int get hashCode => Object.hash(belt, ladderDue, lastReviewDate, reviewCount);

  @override
  String toString() =>
      'ItemState(${belt.key}, due $ladderDue, last $lastReviewDate, n=$reviewCount)';
}

/// Events of one node in the order they happened. Ties on [StudyEvent.atUtc]
/// keep their original list order.
List<StudyEvent> _ordered(List<StudyEvent> events) {
  final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])];
  indexed.sort((a, b) {
    final c = a.$2.atUtc.compareTo(b.$2.atUtc);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

Set<String> _undoneIds(Iterable<StudyEvent> events) =>
    {for (final e in events) if (e is Undo) e.targetId};

/// The newest event that is not an [Undo] and has not been undone. This is the
/// event whose outputs define the state, and the one "Undo" would reverse.
StudyEvent? undoableEvent(List<StudyEvent> events) {
  final ordered = _ordered(events);
  final undone = _undoneIds(ordered);
  for (final e in ordered.reversed) {
    if (e is! Undo && !undone.contains(e.id)) return e;
  }
  return null;
}

/// Derives `item_state` from one node's events (design §2).
ItemState deriveState(List<StudyEvent> events) {
  final ordered = _ordered(events);
  final undone = _undoneIds(ordered);
  final valid = [
    for (final e in ordered)
      if (e is! Undo && !undone.contains(e.id)) e,
  ];
  if (valid.isEmpty) return ItemState.unread;

  final newest = valid.last;
  final out = newest.outcome!;
  LocalDate? lastReview;
  for (final e in valid.reversed) {
    if (e is FirstStudy || e is Review) {
      lastReview = e.localDate;
      break;
    }
  }
  return ItemState(
    belt: out.beltAfter,
    ladderDue: out.ladderDue,
    lastReviewDate: lastReview,
    reviewCount: valid.whereType<Review>().length,
  );
}
