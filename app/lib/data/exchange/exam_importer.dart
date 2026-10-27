// Exam import (design §8a "Import rules", plan item 63). Adds rows only; never
// changes or merges existing rows.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import '../study_writer.dart';

/// The file was rejected; nothing was written.
class ImportRejected implements Exception {
  const ImportRejected(this.messages);
  final List<String> messages;

  @override
  String toString() => messages.join('\n');
}

enum ClashChoice { addToExisting, keepSeparate }

class SubjectPreview {
  const SubjectPreview({
    required this.subject,
    required this.action,
    required this.clash,
    required this.clashUsedBy,
    required this.itemCount,
  });

  final PkgSubject subject;
  final SubjectAction action;

  /// An existing subject with the same name, for a subject that will be
  /// inserted. Never the Inbox.
  final SubjectRow? clash;

  /// Other exams that use [clash].
  final List<String> clashUsedBy;
  final int itemCount;
}

class ImportPreview {
  const ImportPreview({
    required this.package,
    required this.ids,
    required this.subjects,
  });

  final ExamPackage package;
  final ImportIdPlan ids;
  final List<SubjectPreview> subjects;

  int get itemCount => package.nodes.length;
  bool get hasPdfSources => package.sources.any((s) => s.sourceType == SourceType.pdf);
}

class ExamImporter {
  ExamImporter(this._db, this._writer,
      {required String Function() newId, required DateTime Function() now})
      : _newId = newId,
        _now = now;

  final AppDatabase _db;
  final StudyWriter _writer;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<ImportPreview> previewFile(String path) async {
    final file = File(path);
    if (await file.length() > examFileMaxBytes) {
      throw const ImportRejected(['The file is larger than 20 MB']);
    }
    final ExamPackage pkg;
    try {
      pkg = ExamPackage.decode(await file.readAsString());
    } on FormatException catch (e) {
      throw ImportRejected([e.message]);
    }
    return preview(pkg);
  }

  Future<ImportPreview> preview(ExamPackage pkg) async {
    final errors = validate(pkg);
    if (errors.isNotEmpty) throw ImportRejected(errors);
    final ids = planIds(pkg, await _existingIds());
    final subjects = <SubjectPreview>[];
    for (final s in pkg.subjects) {
      final action = ids.subjects[s.id]!;
      SubjectRow? clash;
      var usedBy = const <String>[];
      if (action != SubjectAction.linkExisting && !_isInboxName(s.name)) {
        final same = [
          for (final x in await _db.subjectsDao.findByName(s.name))
            if (!x.isInbox) x,
        ];
        if (same.isNotEmpty) {
          clash = same.first;
          usedBy = [for (final e in await _db.examsDao.examsForSubject(clash.id)) e.name];
        }
      }
      subjects.add(SubjectPreview(
        subject: s,
        action: action,
        clash: clash,
        clashUsedBy: usedBy,
        itemCount: pkg.nodes.where((n) => n.subjectId == s.id).length,
      ));
    }
    return ImportPreview(package: pkg, ids: ids, subjects: subjects);
  }

  /// Writes everything in one transaction and returns the new exam's ID.
  /// [forceSeparate] (Copy as new attempt) never adds to existing subjects.
  Future<String> import(
    ImportPreview preview, {
    required String examName,
    required LocalDate examDate,
    Map<String, ClashChoice> choices = const {},
    bool forceSeparate = false,
  }) =>
      _db.transaction(() async {
        // Re-check against the database as it is now.
        final fresh = await this.preview(preview.package);
        final actions = fresh.ids.subjects;
        final copied = {
          for (final MapEntry(:key, :value) in actions.entries)
            if (value == SubjectAction.copy) key,
        };
        // Old subject ID → new, for subjects that were remapped.
        final remapped = remapSubjects(preview.package, copied, _newId);
        final byOldIndex = {
          for (final (i, s) in preview.package.subjects.indexed) s.id: remapped.subjects[i].id,
        };

        final now = _now();
        final examId = fresh.ids.newExamId ? _newId() : remapped.exam.id;
        await _db.examsDao.insertExam(ExamsCompanion.insert(
            id: examId, name: examName.trim(), examDate: examDate, createdAt: now));

        final skipSubjects = <String>{};
        final subjectTarget = <String, String>{}; // file (remapped) ID → database ID
        final shiftFor = <String, int>{};
        var order = await _db.subjectsDao.nextSortOrder();
        final takenNames = [for (final s in await _db.subjectsDao.all()) s.name];

        for (final sp in fresh.subjects) {
          final fileId = byOldIndex[sp.subject.id]!;
          if (sp.action == SubjectAction.linkExisting) {
            await _db.subjectsDao.link(examId, sp.subject.id);
            skipSubjects.add(fileId);
            continue;
          }
          final clash = sp.clash;
          final choice = forceSeparate ? ClashChoice.keepSeparate : choices[sp.subject.id];
          if (clash != null && choice == ClashChoice.addToExisting) {
            subjectTarget[fileId] = clash.id;
            shiftFor[clash.id] = await _maxTopLevelOrder(clash.id);
            await _db.subjectsDao.link(examId, clash.id);
            continue;
          }
          final name = (clash != null || _isInboxName(sp.subject.name))
              ? firstFreeName(sp.subject.name, takenNames)
              : sp.subject.name;
          takenNames.add(name);
          await _db.subjectsDao.insertSubject(SubjectsCompanion.insert(
            id: fileId,
            name: name,
            sortOrder: order++,
            isInbox: const Value(false),
            createdAt: now,
          ));
          subjectTarget[fileId] = fileId;
          await _db.subjectsDao.link(examId, fileId);
        }

        // Nodes: parents before children (topic, then task, then subtask).
        final nodes = [
          for (final n in remapped.nodes)
            if (!skipSubjects.contains(n.subjectId)) n,
        ];
        final placed = <PkgNode>[];
        for (final MapEntry(key: fileSubject, value: dbSubject) in subjectTarget.entries) {
          final mine = [for (final n in nodes) if (n.subjectId == fileSubject) n];
          final shifted = shiftFor.containsKey(dbSubject) ? shiftTopLevel(mine, shiftFor[dbSubject]!) : mine;
          placed.addAll([for (final n in shifted) n.copyWith(subjectId: dbSubject)]);
        }
        placed.sort((a, b) => a.kind.index.compareTo(b.kind.index));
        for (final n in placed) {
          await _db.nodesDao.insertNode(StudyNodesCompanion.insert(
            id: n.id,
            subjectId: n.subjectId,
            parentId: Value(n.parentId),
            kind: n.kind,
            taskKind: Value(n.taskKind),
            title: n.title,
            positionText: Value(n.positionText),
            baseMinutes: Value(n.baseMinutes),
            sortOrder: n.sortOrder,
            createdAt: DateTime.fromMillisecondsSinceEpoch(n.createdAtUtcMs, isUtc: true),
          ));
        }

        final placedIds = {for (final n in placed) n.id};
        for (final s in remapped.sources) {
          if (!placedIds.contains(s.nodeId)) continue;
          await _db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
            nodeId: s.nodeId,
            sourceType: s.sourceType,
            url: Value(s.url),
            fileName: Value(s.fileName),
            fileSize: Value(s.fileSize),
            locationNote: Value(s.locationNote),
            excerpt: Value(s.excerpt),
            // PDF sources arrive not_linked; URL sources ok.
            linkStatus: s.url != null && s.sourceType != SourceType.pdf
                ? LinkStatus.ok
                : LinkStatus.notLinked,
          ));
        }

        if (remapped.mode == PackageMode.progress) {
          await _writer.writeImported([
            for (final e in remapped.events)
              if (placedIds.contains(e.nodeId)) e.toStudyEvent(),
          ]);
        }
        return examId;
      });

  Future<int> _maxTopLevelOrder(String subjectId) async =>
      await _db.nodesDao.nextSortOrder(subjectId, null) - 1;

  /// IDs present here, including soft-deleted rows.
  Future<ExistingIds> _existingIds() async {
    Future<Set<String>> ids(String table) async => {
          for (final r in await _db.customSelect('SELECT id FROM $table').get())
            r.read<String>('id'),
        };
    return ExistingIds(
      exams: await ids('exams'),
      subjects: await ids('subjects'),
      nodes: await ids('study_nodes'),
      events: await ids('review_events'),
    );
  }
}

bool _isInboxName(String name) => name.trim().toLowerCase() == 'inbox';
