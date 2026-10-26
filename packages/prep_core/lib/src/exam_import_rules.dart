// Validation, privacy and ID rules for exam files (design §8a).
import 'package:meta/meta.dart';

import 'belt.dart';
import 'defaults.dart';
import 'exam_package.dart';
import 'hierarchy.dart';

// ------------------------------------------------------------- validate --

/// Returns human-readable problems; empty means the file can be imported.
List<String> validate(ExamPackage p) {
  final errors = <String>[];
  if (p.formatVersion > examFormatVersion) {
    return ['Update the app to import this file (format ${p.formatVersion}).'];
  }
  if (p.formatVersion < 1) errors.add('Unknown format version ${p.formatVersion}.');

  // Unique IDs across the whole file.
  final seen = <String>{};
  for (final id in [
    p.exam.id,
    ...p.subjects.map((s) => s.id),
    ...p.nodes.map((n) => n.id),
    ...p.events.map((e) => e.id),
  ]) {
    if (!seen.add(id)) errors.add('ID "$id" appears more than once.');
  }

  final subjectIds = {for (final s in p.subjects) s.id};
  final nodes = {for (final n in p.nodes) n.id: n};
  final childCount = <String, int>{};
  for (final n in p.nodes) {
    if (n.parentId != null) childCount[n.parentId!] = (childCount[n.parentId!] ?? 0) + 1;
  }

  for (final n in p.nodes) {
    if (!subjectIds.contains(n.subjectId)) {
      errors.add('Item "${n.title}" points to a missing subject.');
    }
    final parent = n.parentId == null ? null : nodes[n.parentId];
    if (n.parentId != null && parent == null) {
      errors.add('Item "${n.title}" points to a missing parent.');
    }
    if (parent != null && parent.subjectId != n.subjectId) {
      errors.add('Item "${n.title}" is in a different subject from its parent.');
    }
    if (!canAttach(n.kind, parent?.kind)) {
      errors.add('Item "${n.title}" breaks the topic → task → subtask rule.');
    }
    if (n.kind == NodeKind.topic) {
      if (n.baseMinutes != null || n.taskKind != null) {
        errors.add('Topic "${n.title}" must not have a base time or task kind.');
      }
    } else {
      final b = n.baseMinutes;
      if (b == null || b < Defaults.baseMin || b > Defaults.baseMax) {
        errors.add('Item "${n.title}" has a base time outside 10–50 minutes.');
      }
      if (n.taskKind == null) errors.add('Item "${n.title}" has no task kind.');
    }
  }

  for (final s in p.sources) {
    if (!nodes.containsKey(s.nodeId)) errors.add('A source points to a missing item.');
    if ((s.excerpt?.length ?? 0) > Defaults.excerptMaxChars) {
      errors.add('An excerpt is longer than 20,000 characters.');
    }
  }

  // Events.
  final eventsById = {for (final e in p.events) e.id: e};
  final nodesWithEvents = <String>{};
  for (final e in p.events) {
    final n = nodes[e.nodeId];
    if (n == null) {
      errors.add('An event points to a missing item.');
      continue;
    }
    nodesWithEvents.add(n.id);
    if (!isReviewable(n.kind, childCount[n.id] ?? 0)) {
      errors.add('Item "${n.title}" has events but cannot be reviewed.');
    }
    if (e.schedulerVersion != 1) errors.add('Unknown scheduler version ${e.schedulerVersion}.');
    errors.addAll(_eventColumnErrors(e));
    if (e.eventType == 'undo') {
      final target = e.undoesEventId == null ? null : eventsById[e.undoesEventId];
      if (target == null) {
        errors.add('An undo points to a missing event.');
      } else if (target.nodeId != e.nodeId ||
          target.eventType == 'undo' ||
          target.atUtcMs > e.atUtcMs) {
        errors.add('An undo must point to an earlier event on the same item.');
      }
    }
  }
  for (final id in nodesWithEvents) {
    if (nodes[id]!.kind == NodeKind.task && (childCount[id] ?? 0) > 0) {
      errors.add('Task "${nodes[id]!.title}" has both subtasks and events.');
    }
  }
  if (p.mode == PackageMode.structure && p.events.isNotEmpty) {
    errors.add('A structure file must not contain events.');
  }
  return errors;
}

List<String> _eventColumnErrors(PkgEvent e) {
  bool belts() => e.beltBefore != null && e.beltAfter != null;
  final ok = switch (e.eventType) {
    'first_study' => e.grade == null &&
        e.minutes != null &&
        e.beltBefore == Belt.unread &&
        e.beltAfter == Belt.red &&
        e.intervalDays == 1 &&
        e.ladderDueAfter != null &&
        e.undoesEventId == null,
    'review' => e.grade != null &&
        e.minutes != null &&
        belts() &&
        e.beltAfter != Belt.unread &&
        (e.intervalDays ?? 0) >= 1 &&
        e.ladderDueAfter != null &&
        e.undoesEventId == null,
    'reschedule' => e.grade == null &&
        belts() &&
        e.beltBefore == e.beltAfter &&
        e.intervalDays == null &&
        e.ladderDueAfter != null &&
        e.batchId != null,
    'undo' => e.grade == null &&
        e.beltBefore == null &&
        e.beltAfter == null &&
        e.ladderDueAfter == null &&
        e.undoesEventId != null,
    _ => false,
  };
  return ok ? const [] : ['Event ${e.id} (${e.eventType}) has invalid columns.'];
}

// -------------------------------------------------------------- privacy --

/// Applies the "Include notes and excerpts" switch: when off, drops excerpts,
/// location notes, AI-chat URLs and the names of other exams.
ExamPackage applyPrivacy(ExamPackage p, {required bool includeNotes}) {
  if (includeNotes) return p;
  return p.copyWith(
    subjects: [for (final s in p.subjects) s.copyWith(alsoUsedBy: const [])],
    sources: [for (final s in p.sources) s.stripped()],
  );
}

// ------------------------------------------------------------------ IDs --

/// IDs already present in the database, including soft-deleted rows.
@immutable
final class ExistingIds {
  const ExistingIds({
    this.exams = const {},
    this.subjects = const {},
    this.nodes = const {},
    this.events = const {},
  });
  final Set<String> exams;
  final Set<String> subjects;
  final Set<String> nodes;
  final Set<String> events;
}

enum SubjectAction {
  /// Same subject already on this phone: link the exam, skip its contents.
  linkExisting,

  /// Insert with the file's IDs.
  keepIds,

  /// Insert with new IDs.
  copy,
}

@immutable
final class ImportIdPlan {
  const ImportIdPlan({required this.subjects, required this.newExamId});
  final Map<String, SubjectAction> subjects;
  final bool newExamId;
}

/// Decides IDs per subject (§8a step 2). Structure files always copy.
ImportIdPlan planIds(ExamPackage p, ExistingIds existing) {
  final actions = <String, SubjectAction>{};
  for (final s in p.subjects) {
    if (p.mode == PackageMode.structure) {
      actions[s.id] = SubjectAction.copy;
      continue;
    }
    if (existing.subjects.contains(s.id)) {
      actions[s.id] = SubjectAction.linkExisting;
      continue;
    }
    final nodeIds = {for (final n in p.nodes) if (n.subjectId == s.id) n.id};
    final clash = nodeIds.any(existing.nodes.contains) ||
        p.events.any((e) => nodeIds.contains(e.nodeId) && existing.events.contains(e.id));
    actions[s.id] = clash ? SubjectAction.copy : SubjectAction.keepIds;
  }
  return ImportIdPlan(
    subjects: actions,
    newExamId: p.mode == PackageMode.structure || existing.exams.contains(p.exam.id),
  );
}

/// Gives new IDs to [subjectIds] and everything under them, rewriting all
/// references. Batch IDs on moved events get new IDs (same old ID → same new
/// ID); events of other subjects keep theirs. A batch only groups events for
/// "Undo catch-up" on the day it was made, so a split batch is harmless.
ExamPackage remapSubjects(ExamPackage p, Set<String> subjectIds, String Function() newId) {
  final map = <String, String>{};
  for (final id in subjectIds) {
    map[id] = newId();
  }
  final movedNodes = {for (final n in p.nodes) if (subjectIds.contains(n.subjectId)) n.id};
  for (final id in movedNodes) {
    map[id] = newId();
  }
  for (final e in p.events) {
    if (movedNodes.contains(e.nodeId)) map[e.id] = newId();
  }
  final batches = <String, String>{};
  String? batch(String? b) => b == null ? null : batches.putIfAbsent(b, newId);
  String r(String id) => map[id] ?? id;

  return p.copyWith(
    subjects: [for (final s in p.subjects) s.copyWith(id: r(s.id))],
    nodes: [
      for (final n in p.nodes)
        n.copyWith(
          id: r(n.id),
          subjectId: r(n.subjectId),
          parentId: n.parentId == null ? null : r(n.parentId!),
        ),
    ],
    sources: [for (final s in p.sources) s.copyWith(nodeId: r(s.nodeId))],
    events: [
      for (final e in p.events)
        movedNodes.contains(e.nodeId)
            ? e.copyWith(
                id: r(e.id),
                nodeId: r(e.nodeId),
                undoesEventId: e.undoesEventId == null ? null : r(e.undoesEventId!),
                batchId: batch(e.batchId),
              )
            : e,
    ],
  );
}

/// Every ID in the file (exam, subjects, nodes, events).
Set<String> allIds(ExamPackage p) => {
      p.exam.id,
      for (final s in p.subjects) s.id,
      for (final n in p.nodes) n.id,
      for (final e in p.events) e.id,
    };

/// "{name} 2", "{name} 3", … — the first name not in [taken] (case-insensitive).
String firstFreeName(String name, Iterable<String> taken) {
  final lower = {for (final t in taken) t.toLowerCase()};
  if (!lower.contains(name.toLowerCase())) return name;
  for (var n = 2;; n++) {
    final candidate = '$name $n';
    if (!lower.contains(candidate.toLowerCase())) return candidate;
  }
}

/// Shifts top-level sort orders of nodes moved into an existing subject so
/// they come after [existingMax] (§8a "Add to existing").
List<PkgNode> shiftTopLevel(List<PkgNode> nodes, int existingMax) {
  if (nodes.isEmpty) return nodes;
  final topMin = nodes
      .where((n) => n.parentId == null)
      .fold<int?>(null, (m, n) => m == null || n.sortOrder < m ? n.sortOrder : m);
  if (topMin == null) return nodes;
  final delta = existingMax + 1 - topMin;
  return [
    for (final n in nodes) n.parentId == null ? n.copyWith(sortOrder: n.sortOrder + delta) : n,
  ];
}
