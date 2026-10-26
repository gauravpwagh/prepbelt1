import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

void main() {
  test('canAttach depth rule', () {
    expect(canAttach(NodeKind.topic, null), isTrue);
    expect(canAttach(NodeKind.topic, NodeKind.topic), isFalse);
    expect(canAttach(NodeKind.task, null), isTrue);
    expect(canAttach(NodeKind.task, NodeKind.topic), isTrue);
    expect(canAttach(NodeKind.task, NodeKind.task), isFalse);
    expect(canAttach(NodeKind.subtask, NodeKind.task), isTrue);
    expect(canAttach(NodeKind.subtask, null), isFalse);
    expect(canAttach(NodeKind.subtask, NodeKind.subtask), isFalse);
  });

  test('a task with history cannot gain children or be split', () {
    expect(canAddChild(NodeKind.task, 0), isTrue);
    expect(canAddChild(NodeKind.task, 3), isFalse);
    expect(canAddChild(NodeKind.topic, 5), isTrue);
    expect(canAddChild(NodeKind.subtask, 0), isFalse);
    expect(canSplit(0), isTrue);
    expect(canSplit(1), isFalse);
  });

  test('reviewability', () {
    expect(isReviewable(NodeKind.topic, 0), isFalse);
    expect(isReviewable(NodeKind.task, 0), isTrue);
    expect(isReviewable(NodeKind.task, 2), isFalse);
    expect(isReviewable(NodeKind.subtask, 0), isTrue);
  });

  test('task kinds carry default base times (D3)', () {
    expect(TaskKind.reading.defaultBaseMinutes, 30);
    expect(TaskKind.pyq.defaultBaseMinutes, 40);
    expect(TaskKind.other.defaultBaseMinutes, 20);
    expect(TaskKind.fromKey('pyq'), TaskKind.pyq);
    expect(NodeKind.fromKey('subtask'), NodeKind.subtask);
  });

  test('SortKey compares field by field', () {
    SortKey k(int s, int tp, int t, int st, int c, String id) => SortKey(
        subjectOrder: s, topicOrder: tp, taskOrder: t, subtaskOrder: st,
        createdAtUtcMs: c, id: id);
    final keys = [
      k(1, 0, 0, 0, 0, 'a'),
      k(0, 2, 0, 0, 0, 'a'),
      k(0, 1, 5, 0, 0, 'a'),
      k(0, 1, 4, 2, 0, 'a'),
      k(0, 1, 4, 1, 9, 'a'),
      k(0, 1, 4, 1, 3, 'b'),
      k(0, 1, 4, 1, 3, 'a'),
    ]..sort();
    expect([for (final x in keys) '${x.subjectOrder}${x.topicOrder}${x.taskOrder}'
        '${x.subtaskOrder}${x.createdAtUtcMs}${x.id}'],
        ['01413a', '01413b', '01419a', '01420a', '01500a', '02000a', '10000a']);
  });

  group('rollup label (D6)', () {
    test('nothing started', () {
      expect(rollupLabel(rollup(List.filled(12, Belt.unread))), '0/12 started');
    });
    test('mixed; unread is not the weakest', () {
      final r = rollup([Belt.unread, Belt.orange, Belt.green, Belt.red, Belt.green]);
      expect(r.weakestStarted, Belt.red);
      expect(r.counts[Belt.unread], 1);
      expect(rollupLabel(r), 'Weakest: Red · 2/5 Green');
    });
    test('all green', () {
      expect(rollupLabel(rollup(List.filled(3, Belt.green))), 'Weakest: Green · 3/3 Green');
    });
  });
}
