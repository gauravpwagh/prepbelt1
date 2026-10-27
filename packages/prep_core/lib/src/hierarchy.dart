import 'package:meta/meta.dart';

import 'belt.dart';

enum NodeKind {
  topic('topic'),
  task('task'),
  subtask('subtask');

  const NodeKind(this.key);
  final String key;

  static NodeKind fromKey(String key) => values.firstWhere((k) => k.key == key,
      orElse: () => throw ArgumentError.value(key, 'key', 'Unknown node kind'));
}

enum TaskKind {
  reading('reading', 30),
  pyq('pyq', 40),
  other('other', 20);

  const TaskKind(this.key, this.defaultBaseMinutes);
  final String key;

  /// Decision D3.
  final int defaultBaseMinutes;

  static TaskKind fromKey(String key) => values.firstWhere((k) => k.key == key,
      orElse: () => throw ArgumentError.value(key, 'key', 'Unknown task kind'));
}

/// Depth rule (design §2): topic → task → subtask, topic optional.
/// [parent] is null when the node sits directly under a subject.
bool canAttach(NodeKind child, NodeKind? parent) => switch (child) {
      NodeKind.topic => parent == null,
      NodeKind.task => parent == null || parent == NodeKind.topic,
      NodeKind.subtask => parent == NodeKind.task,
    };

/// Whether a child may be added under [parent]. A task that already has
/// review events can't gain subtasks (its history would be orphaned).
bool canAddChild(NodeKind parent, int parentEventCount) => switch (parent) {
      NodeKind.topic => true,
      NodeKind.task => parentEventCount == 0,
      NodeKind.subtask => false,
    };

/// Split is allowed only for a task with no review history.
bool canSplit(int eventCount) => eventCount == 0;

/// Only leaves get belts: a task with no live subtasks, or a subtask.
bool isReviewable(NodeKind kind, int liveChildCount) => switch (kind) {
      NodeKind.topic => false,
      NodeKind.task => liveChildCount == 0,
      NodeKind.subtask => true,
    };

/// Order of items across the whole tree (design §4).
@immutable
final class SortKey implements Comparable<SortKey> {
  const SortKey({
    required this.subjectOrder,
    this.topicOrder = 0,
    required this.taskOrder,
    this.subtaskOrder = 0,
    required this.createdAtUtcMs,
    required this.id,
  });

  final int subjectOrder;
  final int topicOrder;
  final int taskOrder;
  final int subtaskOrder;
  final int createdAtUtcMs;
  final String id;

  @override
  int compareTo(SortKey o) {
    for (final c in [
      subjectOrder.compareTo(o.subjectOrder),
      topicOrder.compareTo(o.topicOrder),
      taskOrder.compareTo(o.taskOrder),
      subtaskOrder.compareTo(o.subtaskOrder),
      createdAtUtcMs.compareTo(o.createdAtUtcMs),
      id.compareTo(o.id),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) => other is SortKey && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(
      subjectOrder, topicOrder, taskOrder, subtaskOrder, createdAtUtcMs, id);
}

/// Belt summary of a parent's reviewable descendants (decision D6).
@immutable
final class Rollup {
  const Rollup({
    required this.weakestStarted,
    required this.counts,
    required this.total,
  });

  /// Lowest belt among started items; null when nothing has started.
  final Belt? weakestStarted;
  final Map<Belt, int> counts;
  final int total;

  int get greens => counts[Belt.green] ?? 0;
}

Rollup rollup(Iterable<Belt> leafBelts) {
  final counts = {for (final b in Belt.values) b: 0};
  Belt? weakest;
  var total = 0;
  for (final b in leafBelts) {
    counts[b] = counts[b]! + 1;
    total++;
    if (b != Belt.unread && (weakest == null || b.step < weakest.step)) {
      weakest = b;
    }
  }
  return Rollup(weakestStarted: weakest, counts: counts, total: total);
}

/// "0/12 started" or "Weakest: Orange · 8/10 Green".
String rollupLabel(Rollup r) => r.weakestStarted == null
    ? '0/${r.total} started'
    : 'Weakest: ${r.weakestStarted!.label} · ${r.greens}/${r.total} Green';
