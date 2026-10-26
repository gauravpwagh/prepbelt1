import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

PkgEvent _ev(String id, String node, String type, int dayOffset,
    {Outcome? o, Grade? grade, String? undoes, String? batch, int hour = 6}) {
  return PkgEvent(
    id: id,
    nodeId: node,
    eventType: type,
    atUtcMs: at(dayOffset, hour).millisecondsSinceEpoch,
    localDate: day(dayOffset),
    tzId: 'Asia/Kolkata',
    grade: grade,
    minutes: type == 'first_study' || type == 'review' ? 10 : null,
    beltBefore: o?.beltBefore,
    beltAfter: o?.beltAfter,
    intervalDays: o?.intervalDays,
    ladderDueAfter: o?.ladderDue,
    explanation: o?.explanation,
    undoesEventId: undoes,
    batchId: batch,
  );
}

/// Polity (topic → task → 2 subtasks) and History (one task), with history on
/// subtask st1: first study, Solid, then an undone Forgot; a reschedule on k2.
ExamPackage sample({PackageMode mode = PackageMode.progress}) {
  final fs = firstStudy(day(0));
  final s1 = ItemState(belt: fs.beltAfter, ladderDue: fs.ladderDue, lastReviewDate: day(0));
  final solid = review(s1, Grade.solid, day(1));
  final s2 = ItemState(belt: solid.beltAfter, ladderDue: solid.ladderDue, lastReviewDate: day(1));
  final forgot = review(s2, Grade.forgot, day(4));
  final fsK2 = firstStudy(day(0));
  final k2State = ItemState(belt: Belt.red, ladderDue: day(1), lastReviewDate: day(0));
  return ExamPackage(
    mode: mode,
    exam: PkgExam(id: 'exam1', name: 'MPSC Prelims', examDate: day(130)),
    subjects: const [
      PkgSubject(id: 'sub1', name: 'Polity', sortOrder: 0, alsoUsedBy: ['UPSC Prelims']),
      PkgSubject(id: 'sub2', name: 'History', sortOrder: 1),
    ],
    nodes: const [
      PkgNode(id: 't1', subjectId: 'sub1', kind: NodeKind.topic, title: 'Constitution',
          sortOrder: 0, createdAtUtcMs: 1),
      PkgNode(id: 'k1', subjectId: 'sub1', parentId: 't1', kind: NodeKind.task,
          taskKind: TaskKind.reading, title: 'Laxmikant', baseMinutes: 30, sortOrder: 0,
          createdAtUtcMs: 2),
      PkgNode(id: 'st1', subjectId: 'sub1', parentId: 'k1', kind: NodeKind.subtask,
          taskKind: TaskKind.reading, title: 'Ch 1', positionText: 'Ch 1', baseMinutes: 30,
          sortOrder: 0, createdAtUtcMs: 3),
      PkgNode(id: 'st2', subjectId: 'sub1', parentId: 'k1', kind: NodeKind.subtask,
          taskKind: TaskKind.reading, title: 'Ch 2', positionText: 'Ch 2', baseMinutes: 30,
          sortOrder: 1, createdAtUtcMs: 4),
      PkgNode(id: 'k2', subjectId: 'sub2', kind: NodeKind.task, taskKind: TaskKind.pyq,
          title: 'Modern PYQ', baseMinutes: 40, sortOrder: 0, createdAtUtcMs: 5),
    ],
    sources: const [
      PkgSource(nodeId: 'k1', sourceType: SourceType.pdf, fileName: 'Laxmikant.pdf',
          fileSize: 1234, locationNote: 'Downloads', excerpt: 'my notes'),
      PkgSource(nodeId: 'k2', sourceType: SourceType.aiChat,
          url: 'https://claude.ai/share/abc', excerpt: 'chat text'),
    ],
    events: mode == PackageMode.structure
        ? const []
        : [
            _ev('e1', 'st1', 'first_study', 0, o: fs),
            _ev('e2', 'st1', 'review', 1, o: solid, grade: Grade.solid),
            _ev('e3', 'st1', 'review', 4, o: forgot, grade: Grade.forgot),
            _ev('e4', 'st1', 'undo', 4, undoes: 'e3', hour: 7),
            _ev('e5', 'k2', 'first_study', 0, o: fsK2),
            _ev('e6', 'k2', 'reschedule', 2, o: reschedule(k2State, day(5)), batch: 'b1'),
          ],
  );
}

ExamPackage _withNodes(ExamPackage p, List<PkgNode> extra) =>
    p.copyWith(nodes: [...p.nodes, ...extra]);

void main() {
  group('JSON', () {
    test('round trip keeps everything', () {
      final p = sample();
      final again = ExamPackage.decode(p.encode());
      expect(again.encode(), p.encode());
      expect(again.events.length, 6);
    });

    test('structure files carry no events key', () {
      final json = sample(mode: PackageMode.structure).toJson();
      expect(json.containsKey('events'), isFalse);
      expect(json['format'], examFormatId);
    });

    test('decode rejects non-exam files', () {
      expect(() => ExamPackage.decode('not json'), throwsFormatException);
      expect(() => ExamPackage.decode('{"format":"other"}'), throwsFormatException);
      final bad = sample().encode().replaceFirst('"kind": "topic"', '"kind": "chapter"');
      expect(() => ExamPackage.decode(bad), throwsFormatException);
    });
  });

  group('validate', () {
    test('the sample is valid', () => expect(validate(sample()), isEmpty));

    test('newer format version asks for an update', () {
      final p = ExamPackage.fromJson({...sample().toJson(), 'format_version': 2});
      expect(validate(p).single, contains('Update the app'));
    });

    test('duplicate IDs', () {
      final p = _withNodes(sample(), const [
        PkgNode(id: 'st1', subjectId: 'sub1', parentId: 'k1', kind: NodeKind.subtask,
            taskKind: TaskKind.reading, title: 'dup', baseMinutes: 30, sortOrder: 9,
            createdAtUtcMs: 9),
      ]);
      expect(validate(p).join(), contains('more than once'));
    });

    final broken = <String, List<PkgNode>>{
      'missing subject': const [
        PkgNode(id: 'x', subjectId: 'nope', kind: NodeKind.task, taskKind: TaskKind.other,
            title: 'x', baseMinutes: 20, sortOrder: 0, createdAtUtcMs: 0),
      ],
      'missing parent': const [
        PkgNode(id: 'x', subjectId: 'sub1', parentId: 'ghost', kind: NodeKind.subtask,
            taskKind: TaskKind.other, title: 'x', baseMinutes: 20, sortOrder: 0, createdAtUtcMs: 0),
      ],
      'parent in another subject': const [
        PkgNode(id: 'x', subjectId: 'sub2', parentId: 'k1', kind: NodeKind.subtask,
            taskKind: TaskKind.other, title: 'x', baseMinutes: 20, sortOrder: 0, createdAtUtcMs: 0),
      ],
      'depth rule': const [
        PkgNode(id: 'x', subjectId: 'sub1', parentId: 't1', kind: NodeKind.subtask,
            taskKind: TaskKind.other, title: 'x', baseMinutes: 20, sortOrder: 0, createdAtUtcMs: 0),
      ],
      'base time out of range': const [
        PkgNode(id: 'x', subjectId: 'sub2', kind: NodeKind.task, taskKind: TaskKind.other,
            title: 'x', baseMinutes: 90, sortOrder: 0, createdAtUtcMs: 0),
      ],
      'topic with base time': const [
        PkgNode(id: 'x', subjectId: 'sub2', kind: NodeKind.topic, title: 'x', baseMinutes: 20,
            sortOrder: 0, createdAtUtcMs: 0),
      ],
      'task with events gains a subtask': const [
        PkgNode(id: 'x', subjectId: 'sub2', parentId: 'k2', kind: NodeKind.subtask,
            taskKind: TaskKind.other, title: 'x', baseMinutes: 20, sortOrder: 0, createdAtUtcMs: 0),
      ],
    };
    broken.forEach((name, nodes) {
      test(name, () => expect(validate(_withNodes(sample(), nodes)), isNotEmpty));
    });

    test('events on a task that has subtasks', () {
      final p = sample();
      final bad = p.copyWith(events: [...p.events, _ev('e9', 'k1', 'first_study', 0, o: firstStudy(day(0)))]);
      expect(validate(bad).join(), contains('cannot be reviewed'));
    });

    test('undo pointing at another item or at a later event', () {
      final p = sample();
      final otherNode = p.copyWith(events: [...p.events, _ev('e9', 'st1', 'undo', 5, undoes: 'e5')]);
      expect(validate(otherNode).join(), contains('earlier event on the same item'));
      final missing = p.copyWith(events: [...p.events, _ev('e9', 'st1', 'undo', 5, undoes: 'zz')]);
      expect(validate(missing).join(), contains('missing event'));
    });

    test('event with wrong columns', () {
      final p = sample();
      final bad = p.copyWith(events: [...p.events, _ev('e9', 'st2', 'review', 3, grade: Grade.solid)]);
      expect(validate(bad).join(), contains('invalid columns'));
    });

    test('structure file with events', () {
      final p = sample(mode: PackageMode.structure).copyWith(events: sample().events);
      expect(validate(p).join(), contains('must not contain events'));
    });

    test('over-long excerpt', () {
      final p = sample();
      final bad = p.copyWith(sources: [
        PkgSource(nodeId: 'st2', sourceType: SourceType.notes, excerpt: 'x' * 20001),
      ]);
      expect(validate(bad).join(), contains('20,000'));
    });
  });

  test('privacy switch drops excerpts, notes, AI-chat links and other exam names', () {
    final p = applyPrivacy(sample(), includeNotes: false);
    expect(p.subjects.first.alsoUsedBy, isEmpty);
    final k1 = p.sources.firstWhere((s) => s.nodeId == 'k1');
    expect(k1.excerpt, isNull);
    expect(k1.locationNote, isNull);
    expect(k1.fileName, 'Laxmikant.pdf');
    expect(p.sources.firstWhere((s) => s.nodeId == 'k2').url, isNull);
    expect(applyPrivacy(sample(), includeNotes: true).encode(), sample().encode());
  });

  group('planIds', () {
    test('structure mode always copies', () {
      final plan = planIds(sample(mode: PackageMode.structure), const ExistingIds());
      expect(plan.subjects.values.toSet(), {SubjectAction.copy});
      expect(plan.newExamId, isTrue);
    });

    test('fresh phone keeps IDs', () {
      final plan = planIds(sample(), const ExistingIds());
      expect(plan.subjects, {'sub1': SubjectAction.keepIds, 'sub2': SubjectAction.keepIds});
      expect(plan.newExamId, isFalse);
    });

    test('existing subject is linked; clashing node IDs force a copy', () {
      final plan = planIds(
          sample(), const ExistingIds(subjects: {'sub1'}, nodes: {'k2'}, exams: {'exam1'}));
      expect(plan.subjects, {'sub1': SubjectAction.linkExisting, 'sub2': SubjectAction.copy});
      expect(plan.newExamId, isTrue);
    });

    test('clashing event IDs also force a copy', () {
      final plan = planIds(sample(), const ExistingIds(events: {'e5'}));
      expect(plan.subjects['sub2'], SubjectAction.copy);
      expect(plan.subjects['sub1'], SubjectAction.keepIds);
    });
  });

  test('remapSubjects rewrites every reference of the moved subject only', () {
    var n = 0;
    final p = sample();
    final r = remapSubjects(p, {'sub1'}, () => 'new${n++}');
    final oldSub1 = {'sub1', 't1', 'k1', 'st1', 'st2', 'e1', 'e2', 'e3', 'e4'};
    expect(allIds(r).intersection(oldSub1), isEmpty);
    expect(validate(r), isEmpty);
    // History is untouched.
    expect(r.subjects[1].id, 'sub2');
    expect(r.events.where((e) => e.nodeId == 'k2').map((e) => e.id), ['e5', 'e6']);
    expect(r.events.firstWhere((e) => e.nodeId == 'k2' && e.eventType == 'reschedule').batchId, 'b1');
    // The undo still points at the (renamed) Forgot event on the same item.
    final undo = r.events.firstWhere((e) => e.eventType == 'undo');
    final target = r.events.firstWhere((e) => e.id == undo.undoesEventId);
    expect(target.grade, Grade.forgot);
    expect(target.nodeId, undo.nodeId);
    // State derived after import matches the original.
    List<StudyEvent> evs(ExamPackage x, String node) =>
        [for (final e in x.events) if (e.nodeId == node) e.toStudyEvent()];
    final st1New = r.nodes.firstWhere((x) => x.title == 'Ch 1').id;
    expect(deriveState(evs(r, st1New)), deriveState(evs(p, 'st1')));
  });

  test('remapping a subject with a batch gives one new batch ID', () {
    var n = 0;
    final r = remapSubjects(sample(), {'sub2'}, () => 'id${n++}');
    final batchIds = {for (final e in r.events) if (e.batchId != null) e.batchId};
    expect(batchIds.length, 1);
    expect(batchIds.single, isNot('b1'));
  });

  test('derived state after import (k2 was rescheduled)', () {
    final p = sample();
    final s = deriveState([for (final e in p.events) if (e.nodeId == 'k2') e.toStudyEvent()]);
    expect(s.belt, Belt.red);
    expect(s.ladderDue, day(5));
    final st1 = deriveState([for (final e in p.events) if (e.nodeId == 'st1') e.toStudyEvent()]);
    expect(st1.belt, Belt.orange);
    expect(st1.reviewCount, 1);
  });

  test('firstFreeName', () {
    expect(firstFreeName('Polity', ['History']), 'Polity');
    expect(firstFreeName('Polity', ['polity', 'Polity 2']), 'Polity 3');
    expect(firstFreeName('Inbox', ['Inbox']), 'Inbox 2');
  });

  test('shiftTopLevel moves only top-level nodes after the existing maximum', () {
    final nodes = sample().nodes.where((x) => x.subjectId == 'sub1').toList();
    final shifted = shiftTopLevel(nodes, 7);
    expect(shifted.firstWhere((x) => x.id == 't1').sortOrder, 8);
    expect(shifted.firstWhere((x) => x.id == 'k1').sortOrder, 0);
  });
}
