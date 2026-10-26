import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final mpsc = ExamRef(id: 'm', name: 'MPSC', date: day(30));
  final upsc = ExamRef(id: 'u', name: 'UPSC', date: day(90));

  test('earliest upcoming exam wins', () {
    expect(resolveDeadline([upsc, mpsc], day(0))!.examId, 'm');
  });

  test('after the first exam passes, the next one caps', () {
    expect(resolveDeadline([upsc, mpsc], day(30))!.examId, 'u');
    expect(resolveDeadline([upsc, mpsc], day(31))!.examId, 'u');
  });

  test('archived exams are ignored', () {
    final archived = ExamRef(id: 'm', name: 'MPSC', date: day(30), archived: true);
    expect(resolveDeadline([archived, upsc], day(0))!.examId, 'u');
  });

  test('past exams and no exams give no deadline', () {
    expect(resolveDeadline([mpsc], day(40)), isNull);
    expect(resolveDeadline(const [], day(0)), isNull);
  });

  test('ties on date break by id', () {
    final b = ExamRef(id: 'b', name: 'B', date: day(10));
    final a = ExamRef(id: 'a', name: 'A', date: day(10));
    expect(resolveDeadline([b, a], day(0))!.examId, 'a');
  });
}
