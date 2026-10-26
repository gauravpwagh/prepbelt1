import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('ladder table matches design §3', () {
    expect([for (final b in Belt.values) b.interval], [null, 1, 3, 7, 16, 35]);
    expect([for (final b in Belt.values) b.shakyInterval], [null, 1, 2, 4, 8, 18]);
    expect([for (final b in Belt.values) b.key],
        ['unread', 'red', 'orange', 'yellow', 'light_green', 'green']);
    expect(Belt.fromKey('light_green'), Belt.lightGreen);
    expect(() => Belt.fromKey('blue'), throwsArgumentError);
  });

  test('up and down stay inside the ladder', () {
    expect(Belt.green.up(), Belt.green);
    expect(Belt.red.down(), Belt.red);
    expect(Belt.unread.up(), Belt.red);
    expect(Belt.unread.down(), Belt.unread);
  });

  test('first study', () {
    final o = firstStudy(day(0));
    expect(o.beltBefore, Belt.unread);
    expect(o.beltAfter, Belt.red);
    expect(o.intervalDays, 1);
    expect(o.ladderDue, day(1));
    expect(o.explanation, 'First read → Red. Next review in 1 day.');
  });

  // (from, grade) → (to, interval, explanation)
  final cases = <(Belt, Grade, Belt, int, String)>[
    (Belt.red, Grade.solid, Belt.orange, 3, 'Solid at Red → Orange. Next review in 3 days.'),
    (Belt.orange, Grade.solid, Belt.yellow, 7, 'Solid at Orange → Yellow. Next review in 7 days.'),
    (Belt.yellow, Grade.solid, Belt.lightGreen, 16,
        'Solid at Yellow → Light green. Next review in 16 days.'),
    (Belt.lightGreen, Grade.solid, Belt.green, 35,
        'Solid at Light green → Green. Next review in 35 days.'),
    (Belt.green, Grade.solid, Belt.green, 35,
        'Solid at Green → stays Green. Next review in 35 days.'),
    (Belt.red, Grade.shaky, Belt.red, 1, 'Shaky at Red: next review in 1 day.'),
    (Belt.orange, Grade.shaky, Belt.orange, 2, 'Shaky at Orange: 3 days halved → 2 days.'),
    (Belt.yellow, Grade.shaky, Belt.yellow, 4, 'Shaky at Yellow: 7 days halved → 4 days.'),
    (Belt.lightGreen, Grade.shaky, Belt.lightGreen, 8,
        'Shaky at Light green: 16 days halved → 8 days.'),
    (Belt.green, Grade.shaky, Belt.green, 18, 'Shaky at Green: 35 days halved → 18 days.'),
    (Belt.red, Grade.forgot, Belt.red, 1, 'Forgot at Red → stays Red. Quick look tomorrow.'),
    (Belt.orange, Grade.forgot, Belt.red, 1, 'Forgot at Orange → Red. Quick look tomorrow.'),
    (Belt.yellow, Grade.forgot, Belt.orange, 1, 'Forgot at Yellow → Orange. Quick look tomorrow.'),
    (Belt.lightGreen, Grade.forgot, Belt.yellow, 1,
        'Forgot at Light green → Yellow. Quick look tomorrow.'),
    (Belt.green, Grade.forgot, Belt.lightGreen, 1,
        'Forgot at Green → Light green. Quick look tomorrow.'),
  ];

  for (final (from, g, to, n, text) in cases) {
    test('${from.key} + ${g.key}', () {
      final o = review(stateAt(from, last: -n, due: 0), g, day(10));
      expect(o.beltBefore, from);
      expect(o.beltAfter, to);
      expect(o.intervalDays, n);
      expect(o.ladderDue, day(10 + n));
      expect(o.explanation, text);
    });
  }

  test('repeated Shaky never shrinks the interval', () {
    var s = stateAt(Belt.yellow, last: 0, due: 7);
    for (var i = 0; i < 5; i++) {
      final o = review(s, Grade.shaky, day(10 + i * 4));
      expect(o.intervalDays, 4);
      s = ItemState(belt: o.beltAfter, ladderDue: o.ladderDue, lastReviewDate: day(10 + i * 4));
    }
  });

  test('reviewing an unread item is an error', () {
    expect(() => review(ItemState.unread, Grade.solid, day(0)), throwsStateError);
  });

  test('reschedule keeps the belt and moves the date', () {
    final o = reschedule(stateAt(Belt.yellow, last: -7, due: 0), day(3));
    expect(o.beltBefore, Belt.yellow);
    expect(o.beltAfter, Belt.yellow);
    expect(o.intervalDays, isNull);
    expect(o.ladderDue, day(3));
    expect(o.explanation, 'Moved by catch-up to ${shortDate(day(3))}.');
    expect(() => reschedule(ItemState.unread, day(3)), throwsStateError);
  });

  test('drop message', () {
    expect(dropMessage(Belt.orange), 'Back to Orange — quick look tomorrow.');
  });

  test('grade definitions', () {
    expect(Grade.solid.definition, 'Could explain it without looking.');
    expect(Grade.fromKey('shaky'), Grade.shaky);
    expect(schedulerVersion, 1);
  });
}
