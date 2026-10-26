import 'package:prep_core/prep_core.dart';

/// Base date for tests: 2026-11-02 (a Monday).
final t0 = LocalDate(2026, 11, 2);

LocalDate day(int offset) => t0.plusDays(offset);

DateTime at(int offsetDays, [int hourUtc = 6]) =>
    DateTime.utc(2026, 11, 2, hourUtc).add(Duration(days: offsetDays));

int _seq = 0;
String nextId() => 'e${(_seq++).toString().padLeft(5, '0')}';

FirstStudy firstStudyEvent(String nodeId, int dayOffset, {int minutes = 30}) =>
    FirstStudy(
      id: nextId(),
      nodeId: nodeId,
      atUtc: at(dayOffset),
      localDate: day(dayOffset),
      tzId: 'Asia/Kolkata',
      minutes: minutes,
      outcome: firstStudy(day(dayOffset)),
    );

Review reviewEvent(String nodeId, ItemState before, Grade g, int dayOffset,
        {int minutes = 8, int hour = 6}) =>
    Review(
      id: nextId(),
      nodeId: nodeId,
      atUtc: at(dayOffset, hour),
      localDate: day(dayOffset),
      tzId: 'Asia/Kolkata',
      grade: g,
      minutes: minutes,
      outcome: review(before, g, day(dayOffset)),
    );

Undo undoEvent(String nodeId, String targetId, int dayOffset, {int hour = 7}) =>
    Undo(
      id: nextId(),
      nodeId: nodeId,
      atUtc: at(dayOffset, hour),
      localDate: day(dayOffset),
      tzId: 'Asia/Kolkata',
      targetId: targetId,
    );

ItemState stateAt(Belt belt, {required int last, required int due}) =>
    ItemState(belt: belt, ladderDue: day(due), lastReviewDate: day(last), reviewCount: 1);

SortKey key(int order) =>
    SortKey(subjectOrder: 0, taskOrder: order, createdAtUtcMs: 0, id: 'n$order');

PlanItem unreadItem(String id, int order, {int base = 30, Deadline? deadline}) =>
    PlanItem(
      nodeId: id,
      state: ItemState.unread,
      baseMinutes: base,
      sortKey: key(order),
      deadline: deadline,
    );

PlanItem dueItem(String id, int order,
        {Belt belt = Belt.orange,
        int last = -3,
        int due = 0,
        int base = 30,
        Deadline? deadline,
        bool resched = false}) =>
    PlanItem(
      nodeId: id,
      state: stateAt(belt, last: last, due: due),
      baseMinutes: base,
      sortKey: key(order),
      deadline: deadline,
      newestIsReschedule: resched,
    );

Deadline examIn(int days, {String id = 'x1', String name = 'MPSC Prelims'}) =>
    Deadline(examId: id, examName: name, date: day(days));
