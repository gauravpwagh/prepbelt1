import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const node = 'ch1';

  test('no events → unread', () {
    expect(deriveState(const []), ItemState.unread);
    expect(undoableEvent(const []), isNull);
  });

  test('first study → Red, due tomorrow', () {
    final fs = firstStudyEvent(node, 0);
    final s = deriveState([fs]);
    expect(s.belt, Belt.red);
    expect(s.ladderDue, day(1));
    expect(s.lastReviewDate, day(0));
    expect(s.reviewCount, 0);
    expect(undoableEvent([fs]), fs);
  });

  test('review chain and undo of the latest review', () {
    final fs = firstStudyEvent(node, 0);
    final s1 = deriveState([fs]);
    final r1 = reviewEvent(node, s1, Grade.solid, 1);
    final s2 = deriveState([fs, r1]);
    expect(s2.belt, Belt.orange);
    expect(s2.ladderDue, day(4));
    expect(s2.reviewCount, 1);

    final u = undoEvent(node, r1.id, 1);
    expect(deriveState([fs, r1, u]), s1);
    expect(undoableEvent([fs, r1, u]), fs);
  });

  test('two undos in a row step back twice; undoing first study → unread', () {
    final fs = firstStudyEvent(node, 0);
    final r1 = reviewEvent(node, deriveState([fs]), Grade.solid, 1);
    final u1 = undoEvent(node, r1.id, 1, hour: 7);
    final u2 = undoEvent(node, fs.id, 1, hour: 8);
    expect(deriveState([fs, r1, u1, u2]), ItemState.unread);
    expect(undoableEvent([fs, r1, u1, u2]), isNull);
  });

  test('undo events are never undoable', () {
    final fs = firstStudyEvent(node, 0);
    final r1 = reviewEvent(node, deriveState([fs]), Grade.forgot, 1);
    final u1 = undoEvent(node, r1.id, 1);
    expect(undoableEvent([fs, r1, u1]), isNot(isA<Undo>()));
  });

  test('input order does not matter; ties keep list order', () {
    final fs = firstStudyEvent(node, 0);
    final r1 = reviewEvent(node, deriveState([fs]), Grade.solid, 1);
    expect(deriveState([r1, fs]), deriveState([fs, r1]));
  });

  test('reschedule keeps lastReviewDate and reviewCount', () {
    final fs = firstStudyEvent(node, 0);
    final r1 = reviewEvent(node, deriveState([fs]), Grade.solid, 1);
    final s = deriveState([fs, r1]);
    final rs = Reschedule(
      id: nextId(),
      nodeId: node,
      atUtc: at(6),
      localDate: day(6),
      tzId: 'Asia/Kolkata',
      batchId: 'b1',
      outcome: reschedule(s, day(8)),
    );
    final after = deriveState([fs, r1, rs]);
    expect(after.belt, Belt.orange);
    expect(after.ladderDue, day(8));
    expect(after.lastReviewDate, day(1));
    expect(after.reviewCount, 1);
  });
}
