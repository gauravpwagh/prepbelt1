import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/db_watch.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';

/// One node in the Library tree. Leaves carry their belt; parents carry the
/// rollup of the reviewable leaves below them (design §3, never stored).
class LibraryNode {
  LibraryNode(this.node, this.children, this.state);

  final NodeRow node;
  final List<LibraryNode> children;

  /// Only for reviewable leaves.
  final ItemState? state;

  bool get isLeaf => state != null;

  late final List<Belt> leafBelts = isLeaf
      ? [state!.belt]
      : [for (final c in children) ...c.leafBelts];

  late final Rollup rollup = _rollupOf(leafBelts);
}

// The field name `rollup` hides prep_core's function inside these classes.
Rollup _rollupOf(List<Belt> belts) => rollup(belts);

class LibrarySubject {
  LibrarySubject(this.subject, this.roots);
  final SubjectRow subject;
  final List<LibraryNode> roots;

  late final Rollup rollup = _rollupOf([for (final r in roots) ...r.leafBelts]);
}

class LibraryView {
  const LibraryView({
    required this.exams,
    required this.examFilter,
    required this.subjects,
    required this.inbox,
  });

  final List<ExamRow> exams;
  final String? examFilter;
  final List<LibrarySubject> subjects;
  final LibrarySubject? inbox;
}

/// The exam the Library is filtered to; null shows every subject.
final libraryExamFilterProvider =
    NotifierProvider<LibraryExamFilter, String?>(LibraryExamFilter.new);

class LibraryExamFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? examId) => state = examId;
}

final libraryViewProvider = StreamProvider.autoDispose<LibraryView>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final filter = ref.watch(libraryExamFilterProvider);
  return watchTables(
    db,
    {db.studyNodes, db.itemStates, db.subjects, db.examSubjects, db.exams},
    () async {
      final exams = await db.examsDao.all();
      final subjects = filter == null
          ? await db.subjectsDao.all()
          : await db.subjectsDao.forExam(filter);
      final inbox = await db.subjectsDao.inbox();
      final nodes = await db.nodesDao.allLive();
      final states = await db.itemStateDao.allReviewable();

      final byParent = <String?, List<NodeRow>>{};
      for (final n in nodes) {
        (byParent[n.parentId ?? 'root:${n.subjectId}'] ??= []).add(n);
      }
      LibraryNode build(NodeRow n) {
        final kids = [for (final c in byParent[n.id] ?? const <NodeRow>[]) build(c)];
        final reviewable = isReviewable(n.kind, kids.length);
        return LibraryNode(n, kids, reviewable ? (states[n.id] ?? ItemState.unread) : null);
      }

      LibrarySubject subjectView(SubjectRow s) => LibrarySubject(
          s, [for (final n in byParent['root:${s.id}'] ?? const <NodeRow>[]) build(n)]);

      return LibraryView(
        exams: exams,
        examFilter: filter,
        subjects: [
          for (final s in subjects)
            if (!s.isInbox) subjectView(s),
        ],
        inbox: inbox == null ? null : subjectView(inbox),
      );
    },
  );
});
