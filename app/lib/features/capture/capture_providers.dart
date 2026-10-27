import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/providers.dart';
import '../../data/db/app_database.dart';

class AddFormData {
  const AddFormData({
    required this.subjects,
    required this.topicsBySubject,
    required this.parent,
    required this.lastSubjectId,
    required this.lastTopicId,
  });

  /// Inbox first, then the others in sort order.
  final List<SubjectRow> subjects;
  final Map<String, List<NodeRow>> topicsBySubject;
  final NodeRow? parent;
  final String? lastSubjectId;
  final String? lastTopicId;
}

final addFormDataProvider =
    FutureProvider.autoDispose.family<AddFormData, String?>((ref, parentId) async {
  final db = ref.watch(appDatabaseProvider);
  await db.subjectsDao.ensureInbox(
      newId: ref.read(idGeneratorProvider), now: ref.read(clockProvider).nowUtc());
  final subjects = await db.subjectsDao.all();
  subjects.sort((a, b) => (a.isInbox ? 0 : 1).compareTo(b.isInbox ? 0 : 1));
  final topics = <String, List<NodeRow>>{};
  for (final s in subjects) {
    topics[s.id] = [
      for (final n in await db.nodesDao.roots(s.id))
        if (n.kind == NodeKind.topic) n,
    ];
  }
  return AddFormData(
    subjects: subjects,
    topicsBySubject: topics,
    parent: parentId == null ? null : await db.nodesDao.byId(parentId),
    lastSubjectId: await db.settingsDao.lastUsedSubjectId(),
    lastTopicId: await db.settingsDao.lastUsedTopicId(),
  );
});
