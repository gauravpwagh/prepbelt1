// Plan item 104: seeds 5,000 items with history for profiling. The design's
// performance targets (NFR) are measured in profile mode on a 4 GB phone; the
// test below records the same operations on the host as a regression guard.
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/data/daos/events_dao.dart';
import 'package:prepbelt/data/db/app_database.dart';

/// 10 subjects × 5 topics × 20 tasks × 5 subtasks = 5,000 reviewable
/// subtasks. About 60% have history from the last 60 days.
Future<void> seed5k(AppDatabase db, {required DateTime now, int seed = 1}) async {
  final rnd = Random(seed);
  final today = LocalDate.fromDateTime(now);
  await db.batch((b) {
    b.insert(db.exams,
        ExamsCompanion.insert(id: 'exam-a', name: 'MPSC Prelims', examDate: today.plusDays(45), createdAt: now));
    b.insert(db.exams,
        ExamsCompanion.insert(id: 'exam-b', name: 'UPSC Prelims', examDate: today.plusDays(80), createdAt: now));
    for (var s = 0; s < 10; s++) {
      b.insert(db.subjects,
          SubjectsCompanion.insert(id: 's$s', name: 'Subject $s', sortOrder: s, createdAt: now));
      b.insert(db.examSubjects, ExamSubjectsCompanion.insert(examId: s < 6 ? 'exam-a' : 'exam-b', subjectId: 's$s'));
      if (s == 5) b.insert(db.examSubjects, ExamSubjectsCompanion.insert(examId: 'exam-b', subjectId: 's5'));
      for (var t = 0; t < 5; t++) {
        final topic = 's$s-t$t';
        b.insert(db.studyNodes, StudyNodesCompanion.insert(
            id: topic, subjectId: 's$s', kind: NodeKind.topic, title: 'Topic $t', sortOrder: t, createdAt: now));
        for (var k = 0; k < 20; k++) {
          final task = '$topic-k$k';
          b.insert(db.studyNodes, StudyNodesCompanion.insert(
              id: task, subjectId: 's$s', parentId: Value(topic), kind: NodeKind.task,
              taskKind: const Value(TaskKind.reading), baseMinutes: const Value(30),
              title: 'Book $k', sortOrder: k, createdAt: now));
          for (var c = 0; c < 5; c++) {
            b.insert(db.studyNodes, StudyNodesCompanion.insert(
                id: '$task-c$c', subjectId: 's$s', parentId: Value(task), kind: NodeKind.subtask,
                taskKind: const Value(TaskKind.reading), baseMinutes: Value(10 + rnd.nextInt(5) * 10),
                title: 'Ch ${c + 1}', positionText: Value('Ch ${c + 1}'), sortOrder: c, createdAt: now));
          }
        }
      }
    }
  });

  // History: a first study and a few graded reviews, replayed through the
  // belt policy so the rows are exactly what StudyWriter would write.
  var n = 0;
  await db.batch((b) {
    for (var s = 0; s < 10; s++) {
      for (var t = 0; t < 5; t++) {
        for (var k = 0; k < 20; k++) {
          for (var c = 0; c < 5; c++) {
            if (rnd.nextDouble() > 0.6) continue;
            final node = 's$s-t$t-k$k-c$c';
            var day = today.plusDays(-60 + rnd.nextInt(30));
            final events = <StudyEvent>[];
            var state = ItemState.unread;
            StudyEvent add(StudyEvent e) {
              events.add(e);
              state = deriveState(events);
              b.insert(db.reviewEvents, toEventRow(e));
              return e;
            }

            add(FirstStudy(
                id: 'e${n++}', nodeId: node, atUtc: now, localDate: day, tzId: 'Asia/Kolkata',
                minutes: 30, outcome: firstStudy(day)));
            for (var r = rnd.nextInt(5); r > 0; r--) {
              day = state.ladderDue!;
              if (day > today) break;
              final g = Grade.values[rnd.nextInt(10) < 6 ? 2 : (rnd.nextBool() ? 1 : 0)];
              add(Review(
                  id: 'e${n++}', nodeId: node, atUtc: now, localDate: day, tzId: 'Asia/Kolkata',
                  grade: g, minutes: 8, outcome: review(state, g, day)));
            }
            b.insert(db.itemStates, ItemStatesCompanion.insert(
              nodeId: node,
              belt: state.belt,
              ladderDue: Value(state.ladderDue),
              lastReviewDate: Value(state.lastReviewDate),
              reviewCount: Value(state.reviewCount),
            ));
          }
        }
      }
    }
  });
}
