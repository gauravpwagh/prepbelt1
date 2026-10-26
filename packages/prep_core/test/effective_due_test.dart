import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Design §12: last review on T, ladder due T+7.
  final s = stateAt(Belt.yellow, last: 0, due: 7);

  final cases = <(String, Deadline?, LocalDate)>[
    ('no deadline', null, day(7)),
    ('exam in 40 days', examIn(40), day(7)),
    ('exam in 3 days', examIn(3), day(2)),
    ('exam in 2 days', examIn(2), day(1)),
    ('exam tomorrow → no cap', examIn(1), day(7)),
  ];
  for (final (name, d, expected) in cases) {
    test(name, () => expect(effectiveDue(s, d), expected));
  }

  test('exam today is ignored by the resolver', () {
    final d = resolveDeadline([ExamRef(id: 'a', name: 'A', date: day(0))], day(0));
    expect(d, isNull);
    expect(effectiveDue(s, d), day(7));
  });

  test('ladder date already before the cap is unchanged', () {
    expect(effectiveDue(stateAt(Belt.red, last: 0, due: 1), examIn(10)), day(1));
  });

  test('unread items have no due date', () {
    expect(effectiveDue(ItemState.unread, examIn(10)), isNull);
  });

  test('capSuffix only when the cap moved the date', () {
    expect(capSuffix(s, examIn(3)), ' Capped by MPSC Prelims on ${shortDate(day(3))}.');
    expect(capSuffix(s, examIn(40)), isNull);
    expect(capSuffix(s, null), isNull);
    expect(capSuffix(s, examIn(1)), isNull);
    expect(capSuffix(s, examIn(3), (d) => d.toIso()),
        ' Capped by MPSC Prelims on ${day(3).toIso()}.');
  });
}
