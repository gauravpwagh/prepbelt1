import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/application/archive_and_remove.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';
import 'package:prepbelt/data/exchange/exam_exporter.dart';
import 'package:prepbelt/data/exchange/exam_importer.dart';

import '../application/app_helpers.dart';

/// Phone A: MPSC (Polity, History) and UPSC (Polity), with history.
Future<void> seedPhoneA(Fixture f, ProviderContainer c) async {
  await f.seedTree(); // sub1 "Polity": t1 → k1 → st1, st2; k2
  await f.subject('sub2', name: 'History', order: 2);
  await f.node('h1', 'sub2', NodeKind.task);
  final db = f.db;
  await db.examsDao.insertExam(ExamsCompanion.insert(
      id: 'mpsc', name: 'MPSC Prelims', examDate: day0.plusDays(100), createdAt: t0));
  await db.examsDao.insertExam(ExamsCompanion.insert(
      id: 'upsc', name: 'UPSC Prelims', examDate: day0.plusDays(150), createdAt: t0));
  await db.subjectsDao.link('mpsc', 'sub1');
  await db.subjectsDao.link('mpsc', 'sub2');
  await db.subjectsDao.link('upsc', 'sub1');
  await db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
      nodeId: 'k1',
      sourceType: SourceType.pdf,
      linkStatus: LinkStatus.ok,
      fileName: const Value('Laxmikant.pdf'),
      fileSize: const Value(1234),
      locationNote: const Value('Downloads')));
  await db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
      nodeId: 'k2',
      sourceType: SourceType.aiChat,
      linkStatus: LinkStatus.ok,
      url: const Value('https://claude.ai/share/x'),
      excerpt: const Value('chat')));
  await f.writer.writeFirstStudy('st1', 30);
  await f.writer.writeReview('st1', Grade.solid, 8);
  await f.writer.writeReview('st1', Grade.forgot, 8);
  await f.writer.writeUndoLatest('st1');
  await f.writer.writeFirstStudy('h1', 30);
}

void main() {
  late Fixture a;
  late ProviderContainer ca;
  late Fixture b;
  late ProviderContainer cb;
  late Directory tmp;

  setUp(() async {
    a = Fixture();
    ca = containerFor(a);
    b = Fixture();
    cb = containerFor(b);
    tmp = await Directory.systemTemp.createTemp('prepbelt_exchange');
    await seedPhoneA(a, ca);
  });
  tearDown(() async {
    ca.dispose();
    cb.dispose();
    await a.close();
    await b.close();
    await tmp.delete(recursive: true);
  });

  Future<ExamPackage> export(String exam, PackageMode mode, {bool notes = true}) =>
      ca.read(examExporterProvider).build(exam, mode, includeNotes: notes);

  Future<Map<String, ItemState>> states(AppDatabase db) => db.itemStateDao.allReviewable();

  group('export', () {
    test('structure: no events; privacy off drops notes; file name and also-used-by', () async {
      final pkg = await export('mpsc', PackageMode.structure, notes: false);
      expect(pkg.events, isEmpty);
      expect(pkg.nodes, hasLength(6));
      final k1 = pkg.sources.firstWhere((s) => s.nodeId == 'k1');
      expect([k1.fileName, k1.fileSize, k1.locationNote], ['Laxmikant.pdf', 1234, null]);
      expect(pkg.sources.firstWhere((s) => s.nodeId == 'k2').url, isNull);
      expect(pkg.subjects.every((s) => s.alsoUsedBy.isEmpty), isTrue);
      expect(jsonDecode(pkg.encode()), isNot(contains('events')));

      final full = await export('mpsc', PackageMode.progress);
      expect(full.subjects.firstWhere((s) => s.id == 'sub1').alsoUsedBy, ['UPSC Prelims']);
      expect(full.events, hasLength(5));
      expect(examFileName('MPSC: Prelims/2027'), 'MPSC_ Prelims_2027.prepbelt.json');
      final notices = await ca.read(exportExamProvider).alsoUsedNotices('mpsc');
      expect(notices, ['Polity is also used by UPSC Prelims.']);
    });
  });

  group('import', () {
    test('progress to a fresh phone keeps IDs and re-derives the same state (CUJ 11)', () async {
      final pkg = await export('mpsc', PackageMode.progress);
      final importer = cb.read(examImporterProvider);
      final preview = await importer.preview(pkg);
      expect(preview.subjects.map((s) => s.action), everyElement(SubjectAction.keepIds));
      expect(preview.hasPdfSources, isTrue);

      final id = await importer.import(preview, examName: 'MPSC Prelims', examDate: day0.plusDays(90));
      expect(id, 'mpsc');
      expect(await states(b.db), await states(a.db));
      final k1 = (await b.db.sourcesDao.sourceFor('k1'))!;
      expect(k1.linkStatus, LinkStatus.notLinked);
      expect((await b.db.sourcesDao.sourceFor('k2'))!.linkStatus, LinkStatus.ok);
      expect((await b.db.examsDao.byId('mpsc'))!.examDate, day0.plusDays(90));

      // The second exam shares Polity: it is linked, and Polity is not duplicated.
      final upsc = await export('upsc', PackageMode.progress);
      final p2 = await importer.preview(upsc);
      expect(p2.subjects.single.action, SubjectAction.linkExisting);
      await importer.import(p2, examName: 'UPSC Prelims', examDate: day0.plusDays(150));
      expect((await b.db.subjectsDao.findByName('Polity')), hasLength(1));
      expect([for (final s in await b.db.subjectsDao.forExam('upsc')) s.id], ['sub1']);
      expect(await b.db.eventsDao.countFor('st1'), 4);
    });

    test('structure mode: new IDs, everything Unread, both clash choices', () async {
      await b.subject('mine', name: 'polity'); // case-insensitive clash
      await b.node('existing', 'mine', NodeKind.task, order: 7);
      await b.db.subjectsDao.ensureInbox(newId: b.newId, now: t0);
      final pkg = await export('mpsc', PackageMode.structure);
      final importer = cb.read(examImporterProvider);
      final preview = await importer.preview(pkg);
      final polity = preview.subjects.firstWhere((s) => s.subject.name == 'Polity');
      expect(polity.action, SubjectAction.copy);
      expect(polity.clash!.id, 'mine');
      expect(preview.subjects.firstWhere((s) => s.subject.name == 'History').clash, isNull);

      final id = await importer.import(preview,
          examName: 'MPSC 2028',
          examDate: day0.plusDays(400),
          choices: {'sub1': ClashChoice.addToExisting});
      expect(id, isNot('mpsc'));
      final roots = await b.db.nodesDao.roots('mine');
      expect([for (final r in roots) r.sortOrder], [7, 8, 10]); // t1 2→8, k2 4→10
      expect(await b.db.nodesDao.byId('st1'), isNull); // new IDs
      expect((await states(b.db)).values.every((s) => s == ItemState.unread), isTrue);
      expect([for (final s in await b.db.subjectsDao.forExam(id)) s.name]..sort(), ['History', 'polity']);

      final again = await importer.preview(pkg);
      await importer.import(again,
          examName: 'MPSC 2029', examDate: day0.plusDays(500),
          choices: {'sub1': ClashChoice.keepSeparate});
      final names = [for (final s in await b.db.subjectsDao.all()) s.name];
      expect(names, containsAll(['Polity 2', 'History 2']));
    });

    test('the Inbox is never a clash target; an "Inbox" subject becomes "Inbox 2"', () async {
      await a.db.subjectsDao.updateSubject('sub2', const SubjectsCompanion(name: Value('Inbox')));
      await b.db.subjectsDao.ensureInbox(newId: b.newId, now: t0);
      final importer = cb.read(examImporterProvider);
      final preview = await importer.preview(await export('mpsc', PackageMode.structure));
      final inbox = preview.subjects.firstWhere((s) => s.subject.name == 'Inbox');
      expect(inbox.clash, isNull);
      final id = await importer.import(preview,
          examName: 'X', examDate: day0.plusDays(9), choices: {'sub2': ClashChoice.addToExisting});
      final linked = await b.db.subjectsDao.forExam(id);
      expect(linked.map((s) => s.name), contains('Inbox 2'));
      expect(linked.any((s) => s.isInbox), isFalse);
    });

    test('Copy as new attempt never merges and keeps the old attempt intact', () async {
      final id = await ca.read(copyAsNewAttemptProvider)('mpsc', name: 'MPSC 2028', date: day0.plusDays(400));
      final subjects = await a.db.subjectsDao.forExam(id);
      expect(subjects.map((s) => s.name), unorderedEquals(['Polity 2', 'History 2']));
      expect((await a.db.itemStateDao.stateOf('st1')).belt, Belt.orange);
      final copied = await a.db.nodesDao.roots(subjects.firstWhere((s) => s.name == 'Polity 2').id);
      expect(copied, hasLength(2));
    });

    test('an invalid file writes nothing', () async {
      final bad = File('${tmp.path}/bad.prepbelt.json')
        ..writeAsStringSync(jsonEncode({
          'format': 'prepbelt-exam',
          'format_version': 1,
          'mode': 'structure',
          'exam': {'id': 'e', 'name': 'E', 'exam_date': '2027-01-01'},
          'subjects': [],
          'nodes': [
            {'id': 'n', 'subject_id': 'missing', 'kind': 'task', 'task_kind': 'reading',
             'title': 'T', 'base_minutes': 30, 'sort_order': 0, 'created_at_utc': 0},
          ],
          'sources': [],
        }));
      await expectLater(cb.read(examImporterProvider).previewFile(bad.path), throwsA(isA<ImportRejected>()));
      final newer = File('${tmp.path}/newer.json')
        ..writeAsStringSync(jsonEncode({
          ...jsonDecode((await export('mpsc', PackageMode.structure)).encode()) as Map<String, Object?>,
          'format_version': 9,
        }));
      await expectLater(cb.read(examImporterProvider).previewFile(newer.path), throwsA(isA<ImportRejected>()));
      expect(await b.db.examsDao.all(), isEmpty);
    });
  });

  group('archive and remove (CUJ 12)', () {
    late FakeFolderAccess folders;
    late ProviderContainer c;

    setUp(() async {
      folders = FakeFolderAccess()..addTree('Drive', {});
      c = containerFor(a, folders: folders, extra: [
        cacheDirProvider.overrideWithValue(() async => tmp.path),
      ]);
    });
    tearDown(() => c.dispose());

    Future<void> chooseBackupFolder() async {
      await a.db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
          id: 'b', treeUri: const Value('tree:Drive'), displayName: 'Drive',
          purpose: FolderPurpose.backup, grantedAt: t0));
      await a.db.settingsDao.setBackupFolderId('b');
      // copyToLocal reads back what writeFile stored: keep the bytes.
      folders.writeHook = (name, file) async {
        final keep = File('${tmp.path}/kept-$name');
        await file.copy(keep.path);
        folders.contents['doc:Drive/$name'] = keep;
      };
    }

    test('blocked without a backup folder or with a running session', () async {
      final archive = c.read(archiveAndRemoveProvider);
      await expectLater(archive.prepare('mpsc'), throwsA(isA<ArchiveBlocked>()));
      await chooseBackupFolder();
      await a.db.sessionsDao.start('s1', 'h1', t0);
      await expectLater(archive.prepare('mpsc'),
          throwsA(predicate((e) => '$e'.contains('Finish or discard'))));
    });

    test('exports, verifies, then removes only the unshared subject', () async {
      await chooseBackupFolder();
      await a.db.sessionsDao.start('s1', 'h1', t0);
      await a.db.sessionsDao.finish('s1', t0, 30, edited: false);
      await a.db.settingsDao.setLastUsedSubjectId('sub2');
      final archive = c.read(archiveAndRemoveProvider);
      final plan = await archive.prepare('mpsc');
      expect(plan.removeSubjects, {'sub2'});
      expect(plan.keptSubjects, ['Polity']);
      expect(folders.trees['tree:Drive']!.keys, ['MPSC Prelims.prepbelt.json']);

      await expectLater(archive.remove(plan, typedName: 'mpsc'), throwsA(isA<ArchiveBlocked>()));
      await archive.remove(plan, typedName: 'MPSC Prelims');
      expect(await a.db.examsDao.byId('mpsc'), isNull);
      expect(await a.db.subjectsDao.byId('sub2'), isNull);
      expect(await a.db.nodesDao.byId('h1'), isNull);
      expect(await a.db.select(a.db.studySessions).get(), isEmpty);
      expect(await a.db.subjectsDao.byId('sub1'), isNotNull);
      expect(await a.db.settingsDao.lastUsedSubjectId(), isNull);

      // Re-importing the archive links back to the kept Polity.
      final file = folders.contents['doc:Drive/MPSC Prelims.prepbelt.json']!;
      final importer = c.read(examImporterProvider);
      final preview = await importer.previewFile(file.path);
      expect(preview.subjects.firstWhere((s) => s.subject.id == 'sub1').action,
          SubjectAction.linkExisting);
      await importer.import(preview, examName: 'MPSC Prelims', examDate: day0.plusDays(100));
      expect(await a.db.eventsDao.countFor('h1'), 1);
      expect(await a.db.subjectsDao.findByName('Polity'), hasLength(1));
    });

    test('a failed read-back deletes nothing', () async {
      await chooseBackupFolder();
      folders.writeHook = (name, file) async {}; // nothing to read back
      await expectLater(c.read(archiveAndRemoveProvider).prepare('mpsc'), throwsA(anything));
      expect(await a.db.examsDao.byId('mpsc'), isNotNull);
      expect(await a.db.subjectsDao.byId('sub2'), isNotNull);
    });
  });
}
