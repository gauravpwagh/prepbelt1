// Property tests (design §12) using seeded random sequences, so every run
// checks the same cases.
import 'dart:math';

import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('random review sequences keep the ladder invariants', () {
    for (var seed = 1; seed <= 200; seed++) {
      final rnd = Random(seed);
      final node = 'n$seed';
      final events = <StudyEvent>[firstStudyEvent(node, 0)];
      var state = deriveState(events);
      var date = 0;

      for (var step = 0; step < 25; step++) {
        final before = state;
        date += 1 + rnd.nextInt(10);
        final g = Grade.values[rnd.nextInt(3)];
        final e = reviewEvent(node, state, g, date);
        final o = e.outcome;

        expect(o.intervalDays, greaterThanOrEqualTo(1));
        expect(o.ladderDue! > day(date), isTrue);
        expect(o.beltAfter.step, inInclusiveRange(1, Belt.topStep));
        expect((o.beltAfter.step - o.beltBefore.step).abs(), lessThanOrEqualTo(1));

        events.add(e);
        state = deriveState(events);
        expect(state.belt, o.beltAfter);
        expect(state.ladderDue, o.ladderDue);
        expect(state.lastReviewDate, day(date));

        // Undo restores the previous state exactly; drop it again afterwards.
        if (rnd.nextInt(5) == 0) {
          final u = undoEvent(node, e.id, date, hour: 23);
          expect(deriveState([...events, u]), before);
        }
      }
      expect(state.reviewCount, 25);
    }
  });

  test('exam cap: deadline ≥ last + 2 ⇒ effectiveDue ≤ deadline − 1', () {
    final rnd = Random(7);
    for (var i = 0; i < 2000; i++) {
      final last = rnd.nextInt(30);
      final due = last + 1 + rnd.nextInt(40);
      final s = stateAt(Belt.values[1 + rnd.nextInt(5)], last: last, due: due);
      final dl = last + 2 + rnd.nextInt(60);
      final eff = effectiveDue(s, examIn(dl))!;
      expect(eff <= day(dl - 1), isTrue, reason: 'last=$last due=$due exam=$dl');
      expect(eff > day(last), isTrue);
      expect(eff <= day(due), isTrue);
    }
  });

  test('planner never exceeds the budget', () {
    final rnd = Random(11);
    for (var run = 0; run < 300; run++) {
      final budget = 15 + rnd.nextInt(200);
      final count = rnd.nextInt(60);
      final items = <PlanItem>[
        for (var i = 0; i < count; i++)
          rnd.nextBool()
              ? unreadItem('u$i', i, base: 10 + rnd.nextInt(41))
              : dueItem('r$i', i,
                  base: 10 + rnd.nextInt(41),
                  belt: Belt.values[1 + rnd.nextInt(5)],
                  due: -rnd.nextInt(5),
                  last: -6),
      ];
      final p = buildPlan(PlanInput(today: day(0), budget: budget, items: items));
      expect(p.reviewMinutes + p.firstReadMinutes, lessThanOrEqualTo(budget));
      final firstUnread = items.where((i) => i.isUnread).toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
      if (firstUnread.isNotEmpty && firstUnread.first.baseMinutes <= budget) {
        expect(p.firstReadMinutes, greaterThan(0));
      }
    }
  });
}
