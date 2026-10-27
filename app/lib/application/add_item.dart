import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';

/// A source attached to a new task. Subtasks inherit their task's source.
class NewSource {
  const NewSource({
    required this.type,
    this.url,
    this.folderId,
    this.relativePath,
    this.fileName,
    this.fileSize,
    this.locationNote,
    this.excerpt,
    this.linkStatus,
  });

  final SourceType type;
  final String? url;
  final String? folderId;
  final String? relativePath;
  final String? fileName;
  final int? fileSize;
  final String? locationNote;
  final String? excerpt;

  /// Defaults to `ok` for a URL or a linked file, otherwise `not_linked`.
  final LinkStatus? linkStatus;

  LinkStatus get status =>
      linkStatus ??
      (url != null || relativePath != null ? LinkStatus.ok : LinkStatus.notLinked);
}

class AddItemRequest {
  const AddItemRequest({
    required this.title,
    this.kind = NodeKind.task,
    this.subjectId,
    this.parentId,
    this.taskKind,
    this.baseMinutes,
    this.positionText,
    this.source,
    this.asIGo = false,
  });

  final String title;
  final NodeKind kind;

  /// Ignored when [parentId] is set (the parent's subject is used); null
  /// with no parent means the Inbox.
  final String? subjectId;
  final String? parentId;
  final TaskKind? taskKind;
  final int? baseMinutes;
  final String? positionText;
  final NewSource? source;

  /// Split as you go (design D17); tasks only.
  final bool asIGo;
}

/// Adds a topic, task or subtask (plan item 78).
class AddItem {
  AddItem(this._db, {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<String> call(AddItemRequest r) => _db.transaction(() async {
        final title = r.title.trim();
        if (title.isEmpty) throw ArgumentError('A title is needed');
        if (title.length > 200) throw ArgumentError('The title is too long');

        NodeRow? parent;
        if (r.parentId != null) {
          parent = await _db.nodesDao.byId(r.parentId!);
          if (parent == null || parent.deletedAt != null) {
            throw StateError('The parent item no longer exists');
          }
        }
        if (!canAttach(r.kind, parent?.kind)) {
          throw StateError(parent == null
              ? 'A ${r.kind.key} needs a parent'
              : 'A ${r.kind.key} cannot go under a ${parent.kind.key}');
        }
        if (r.kind == NodeKind.subtask &&
            !canAddChild(parent!.kind, await _db.eventsDao.countFor(parent.id))) {
          throw StateError('This task has review history, so it cannot gain '
              'subtasks. Create a new task with chapters instead.');
        }
        if (r.asIGo && r.kind != NodeKind.task) {
          throw ArgumentError('Only tasks can be split as you go');
        }
        if (r.source != null && r.kind != NodeKind.task) {
          throw ArgumentError('Only tasks carry a source');
        }

        final subjectId = parent?.subjectId ??
            r.subjectId ??
            (await _db.subjectsDao.ensureInbox(newId: _newId, now: _now())).id;

        final isTopic = r.kind == NodeKind.topic;
        final taskKind =
            isTopic ? null : (r.taskKind ?? parent?.taskKind ?? TaskKind.reading);
        final base = isTopic ? null : (r.baseMinutes ?? taskKind!.defaultBaseMinutes);
        if (base != null && (base < Defaults.baseMin || base > Defaults.baseMax)) {
          throw RangeError.range(base, Defaults.baseMin, Defaults.baseMax, 'baseMinutes');
        }

        final id = _newId();
        await _db.nodesDao.insertNode(StudyNodesCompanion.insert(
          id: id,
          subjectId: subjectId,
          parentId: Value(parent?.id),
          kind: r.kind,
          taskKind: Value(taskKind),
          title: title,
          positionText: Value(_blankToNull(r.positionText)),
          baseMinutes: Value(base),
          sortOrder: await _db.nodesDao.nextSortOrder(subjectId, parent?.id),
          createdAt: _now(),
          splitAsIGo: Value(r.asIGo ? SplitAsIGo.open : null),
        ));
        final s = r.source;
        if (s != null) {
          await _db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
            nodeId: id,
            sourceType: s.type,
            url: Value(_blankToNull(s.url)),
            folderId: Value(s.folderId),
            relativePath: Value(s.relativePath),
            fileName: Value(s.fileName),
            fileSize: Value(s.fileSize),
            locationNote: Value(_blankToNull(s.locationNote)),
            excerpt: Value(_blankToNull(s.excerpt)),
            linkStatus: s.status,
          ));
        }

        // Remember the subject and topic for the next quick add.
        await _db.settingsDao.setLastUsedSubjectId(subjectId);
        await _db.settingsDao.setLastUsedTopicId(switch (r.kind) {
          NodeKind.topic => id,
          _ when parent?.kind == NodeKind.topic => parent!.id,
          NodeKind.subtask => parent?.parentId,
          _ => null,
        });
        return id;
      });
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
