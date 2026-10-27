import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

void main() {
  test('nextPartTitle', () {
    expect(nextPartTitle([]), 'Part 1');
    expect(nextPartTitle(['Ch 3']), 'Ch 4');
    expect(nextPartTitle(['Ch 1–2']), 'Ch 3–4');
    expect(nextPartTitle(['pp. 21–40']), 'pp. 41–60');
    expect(nextPartTitle(['pp. 1-10 (intro)']), 'pp. 11-20 (intro)');
    expect(nextPartTitle(['Lecture 9 notes']), 'Lecture 10 notes');
    expect(nextPartTitle(['12']), '13');
    expect(nextPartTitle(['Intro', 'Preface']), 'Part 3');
    expect(nextPartTitle(['Ch 9–3']), 'Ch 9–4'); // not a range: last number
  });

  test('partBaseMinutes', () {
    expect([partBaseMinutes(4), partBaseMinutes(35), partBaseMinutes(90)], [10, 35, 50]);
  });

  test('SplitAsIGo keys', () {
    for (final v in SplitAsIGo.values) {
      expect(SplitAsIGo.fromKey(v.key), v);
    }
    expect(() => SplitAsIGo.fromKey('x'), throwsArgumentError);
  });
}
