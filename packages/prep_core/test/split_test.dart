import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

void main() {
  test('chapters', () {
    final parts = split(const Chapters(1, 12));
    expect(parts.length, 12);
    expect(parts.first, const SplitPart('Ch 1', 'Ch 1'));
    expect(parts.last, const SplitPart('Ch 12', 'Ch 12'));
    expect(split(const Chapters(4, 4)), [const SplitPart('Ch 4', 'Ch 4')]);
  });

  test('page chunks, last chunk shorter', () {
    expect(split(const PageChunks(1, 45, 20)), const [
      SplitPart('pp. 1–20', 'pp. 1–20'),
      SplitPart('pp. 21–40', 'pp. 21–40'),
      SplitPart('pp. 41–45', 'pp. 41–45'),
    ]);
    expect(split(const PageChunks(41, 41, 20)), const [SplitPart('p. 41', 'p. 41')]);
  });

  test('custom titles drop blanks', () {
    expect(split(const Custom(['Preamble', ' ', 'Fundamental Rights '])), const [
      SplitPart('Preamble', null),
      SplitPart('Fundamental Rights', null),
    ]);
  });

  test('invalid ranges throw', () {
    expect(() => split(const Chapters(5, 4)), throwsArgumentError);
    expect(() => split(const Chapters(0, 4)), throwsArgumentError);
    expect(() => split(const PageChunks(1, 10, 0)), throwsArgumentError);
    expect(() => split(const Custom([''])), throwsArgumentError);
  });
}
