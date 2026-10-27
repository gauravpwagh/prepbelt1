import 'package:logging/logging.dart';
import 'package:prep_core/prep_core.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../platform/folder_access.dart';
import '../platform/share_receiver.dart';
import 'add_item.dart';

final _log = Logger('capture');

const unmatchedShareNote = 'Shared from another app — locate later';

/// A draft as the capture sheet edits it.
class CaptureDraft {
  CaptureDraft(this.draft, this.copy) : title = draft.title;
  final ShareDraft draft;

  /// The cache copy behind a shared file, if any.
  final SharedCopy? copy;
  String title;
}

/// Turns a share into Planned tasks (design §7, plan item 83).
class CaptureShared {
  CaptureShared(this._db, this._folders, this._addItem);

  final AppDatabase _db;
  final FolderAccess _folders;
  final AddItem _addItem;

  List<CaptureDraft> drafts(IncomingShare share) {
    final drafts = classifyShare(
      text: share.text,
      subject: share.subject,
      files: [for (final f in share.files) SharedFile(name: f.name, size: f.size)],
    );
    // classifyShare emits file drafts in file order, then any text draft.
    var i = 0;
    return [
      for (final d in drafts)
        CaptureDraft(d, d.file != null && i < share.files.length ? share.files[i++] : null),
    ];
  }

  /// Saves every draft into [subjectId] (null = Inbox), then deletes the
  /// share's cache copies. Returns the new task IDs.
  Future<List<String>> save(IncomingShare share, List<CaptureDraft> drafts,
      {String? subjectId}) async {
    try {
      final ids = <String>[];
      for (final c in drafts) {
        ids.add(await _addItem(AddItemRequest(
          title: c.title.trim().isEmpty ? c.draft.title : c.title,
          subjectId: subjectId,
          source: await _sourceFor(c.draft),
        )));
      }
      return ids;
    } finally {
      await share.discardFiles();
    }
  }

  Future<NewSource> _sourceFor(ShareDraft d) async {
    final f = d.file;
    if (f == null) {
      return NewSource(type: d.type, url: d.url, excerpt: d.excerpt);
    }
    final match = f.name != null && f.size != null ? await _findFile(f.name!, f.size!) : null;
    if (match != null) {
      return NewSource(
        type: SourceType.pdf,
        folderId: match.$1,
        relativePath: match.$2,
        fileName: f.name,
        fileSize: f.size,
        linkStatus: LinkStatus.ok,
      );
    }
    return NewSource(
      type: SourceType.pdf,
      fileName: f.name,
      fileSize: f.size,
      locationNote: unmatchedShareNote,
      linkStatus: LinkStatus.notLinked,
    );
  }

  /// The first file named [name] with [size] across the granted source
  /// folders, by `granted_at` and then relative path.
  Future<(String folderId, String relativePath)?> _findFile(String name, int size) async {
    for (final folder in await _db.sourcesDao.folders(FolderPurpose.sources)) {
      if (folder.treeUri == null) continue;
      final hits = <String>[];
      try {
        await for (final e in _folders.walk(folder.treeUri!)) {
          if (e.name == name && e.size == size) hits.add(e.relativePath);
        }
      } on FolderException catch (e) {
        _log.warning('Could not walk ${folder.displayName}: $e');
        continue;
      }
      if (hits.isNotEmpty) {
        hits.sort();
        return (folder.id, hits.first);
      }
    }
    return null;
  }
}
