import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/application/capture_shared.dart';
import 'package:prepbelt/application/sort_share.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';
import 'package:prepbelt/platform/local_files.dart';
import 'package:prepbelt/platform/share_receiver.dart';

import 'app_helpers.dart';

const _files = IoLocalFiles();

void main() {
  late Fixture f;
  late AppDatabase db;
  late ProviderContainer c;
  late FakeFolderAccess folders;
  late Directory tmp;

  setUp(() async {
    f = Fixture();
    db = f.db;
    folders = FakeFolderAccess();
    c = containerFor(f, folders: folders);
    tmp = await Directory.systemTemp.createTemp('prepbelt_test');
  });
  tearDown(() async {
    c.dispose();
    await f.close();
    await tmp.delete(recursive: true);
  });

  Future<SharedCopy> copy(String name, {int bytes = 100, String? content}) async {
    final file = File('${tmp.path}/$name');
    await file.writeAsString(content ?? '%PDF-${'x' * (bytes - 5)}');
    return SharedCopy(file.path, name, await file.length());
  }

  Future<String> grant(String name, Map<String, int> files, {int minutesAgo = 0}) async {
    folders.addTree(name, files);
    final id = 'f-$name';
    await db.sourcesDao.insertFolder(SourceFoldersCompanion.insert(
        id: id,
        treeUri: Value('tree:$name'),
        displayName: name,
        purpose: FolderPurpose.sources,
        grantedAt: t0.subtract(Duration(minutes: minutesAgo))));
    return id;
  }

  group('capture_shared', () {
    test('CUJ 2b: an AI chat link becomes an Inbox task with the excerpt', () async {
      const text = 'About the Preamble https://claude.ai/share/abc and more';
      final share = IncomingShare(text: text, subject: 'Preamble chat');
      final capture = c.read(captureSharedProvider);
      final drafts = capture.drafts(share);
      expect(drafts.single.title, 'Preamble chat');
      final id = (await capture.save(share, drafts)).single;

      final node = (await db.nodesDao.byId(id))!;
      expect(node.title, 'Preamble chat');
      expect((await db.subjectsDao.byId(node.subjectId))!.isInbox, isTrue);
      final s = (await db.sourcesDao.sourceFor(id))!;
      expect([s.sourceType, s.url, s.excerpt, s.linkStatus],
          [SourceType.aiChat, 'https://claude.ai/share/abc', text, LinkStatus.ok]);
    });

    test('CUJ 2c: a PDF in a granted folder is linked; the copy is deleted', () async {
      final pdf = await copy('Polity_notes.pdf', bytes: 1234);
      await grant('Older', {'misc/other.pdf': 5}, minutesAgo: 10);
      await grant('UPSC', {'b/Polity_notes.pdf': 1234, 'a/Polity_notes.pdf': 1234});
      final share = IncomingShare(files: [pdf]);
      final capture = c.read(captureSharedProvider);
      final id = (await capture.save(share, capture.drafts(share))).single;

      final s = (await db.sourcesDao.sourceFor(id))!;
      expect([s.folderId, s.relativePath, s.linkStatus],
          ['f-UPSC', 'a/Polity_notes.pdf', LinkStatus.ok]);
      expect((await db.nodesDao.byId(id))!.title, 'Polity_notes');
      expect(File(pdf.cachePath).existsSync(), isFalse);
    });

    test('an unmatched PDF is saved not_linked with a note', () async {
      final pdf = await copy('Elsewhere.pdf');
      await grant('UPSC', {'Elsewhere.pdf': 1});
      final share = IncomingShare(files: [pdf]);
      final capture = c.read(captureSharedProvider);
      final drafts = capture.drafts(share)..single.title = 'Renamed';
      final id = (await capture.save(share, drafts, subjectId: null)).single;
      final s = (await db.sourcesDao.sourceFor(id))!;
      expect([s.linkStatus, s.locationNote, s.fileName],
          [LinkStatus.notLinked, unmatchedShareNote, 'Elsewhere.pdf']);
      expect((await db.nodesDao.byId(id))!.title, 'Renamed');
      expect(File(pdf.cachePath).existsSync(), isFalse);
    });
  });

  group('sort_share', () {
    test('exam files, PDFs, text and anything else', () async {
      final exam = await copy('MPSC.prepbelt.json',
          content: jsonEncode({'format': 'prepbelt-exam', 'format_version': 1}));
      expect(await sortShare(IncomingShare(files: [exam]), _files), isA<ExamFileShare>());
      final other = await copy('notes.json', content: '{"format":"x"}');
      expect(await sortShare(IncomingShare(files: [other]), _files), isA<UnsupportedShare>());
      final pdf = await copy('a.pdf');
      expect(await sortShare(IncomingShare(files: [pdf]), _files), isA<CaptureShare>());
      final unnamed = await copy('FILE_123.bin');
      expect(
          await sortShare(IncomingShare(files: [SharedCopy(unnamed.cachePath, null, 1)]), _files),
          isA<CaptureShare>()); // the %PDF- header decides
      final png = await copy('photo.png', content: 'PNG');
      expect(await sortShare(IncomingShare(files: [png]), _files), isA<UnsupportedShare>());
      expect(await sortShare(const IncomingShare(text: 'hello'), _files), isA<CaptureShare>());
      expect(await isExamFile('${tmp.path}/missing.json', _files), isFalse);
    });
  });

  group('relink and folders', () {
    test('matches by name and size and lists the rest (CUJ 7)', () async {
      await f.subject('s');
      for (final id in ['a', 'b', 'c', 'd']) {
        await f.node(id, 's', NodeKind.task);
      }
      Future<void> pdf(String node, String file, int? size, LinkStatus st) =>
          db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
              nodeId: node,
              sourceType: SourceType.pdf,
              linkStatus: st,
              fileName: Value(file),
              fileSize: Value(size)));
      await pdf('a', 'Laxmikant.pdf', 500, LinkStatus.needsRelink);
      await pdf('b', 'Spectrum.pdf', 300, LinkStatus.notLinked);
      await pdf('c', 'Missing.pdf', 10, LinkStatus.notLinked);
      await pdf('d', 'Typed.pdf', null, LinkStatus.notLinked);
      final folder = await grant('New', {
        'books/Laxmikant.pdf': 500,
        'Spectrum.pdf': 300,
        'x/Typed.pdf': 77,
      });

      final r = await c.read(relinkSourcesProvider)(folder);
      expect(r.matched, 3);
      expect(r.unmatched, ['Missing.pdf']);
      final a = (await db.sourcesDao.sourceFor('a'))!;
      expect([a.folderId, a.relativePath, a.linkStatus],
          [folder, 'books/Laxmikant.pdf', LinkStatus.ok]);
      expect((await db.sourcesDao.sourceFor('d'))!.fileSize, 77);
    });

    test('add dedupes a folder; forget marks its PDFs needs_relink', () async {
      final manage = c.read(sourceFoldersProvider);
      folders.nextPick = 'UPSC';
      final id = await manage.add(FolderPurpose.sources);
      expect(await manage.add(FolderPurpose.sources), id);
      folders.nextPick = null;
      expect(await manage.add(FolderPurpose.sources), isNull);

      await f.subject('s');
      await f.node('a', 's', NodeKind.task);
      await db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
          nodeId: 'a',
          sourceType: SourceType.pdf,
          linkStatus: LinkStatus.ok,
          folderId: Value(id),
          relativePath: const Value('a.pdf'),
          fileName: const Value('a.pdf')));
      await db.sourcesDao.setTreeUri(id!, null);
      folders.nextPick = 'UPSC';
      expect(await manage.regrant(id), isTrue);
      expect((await db.sourcesDao.folderById(id))!.treeUri, 'tree:UPSC');

      await manage.forget(id);
      final s = (await db.sourcesDao.sourceFor('a'))!;
      expect([s.folderId, s.linkStatus], [null, LinkStatus.needsRelink]);
      expect(await db.sourcesDao.folderById(id), isNull);
    });
  });
}
