import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import '../platform/folder_access.dart';

final _log = Logger('relink');

class RelinkReport {
  const RelinkReport(this.matched, this.unmatched);
  final int matched;

  /// File names (or task titles) that could not be matched.
  final List<String> unmatched;
}

/// "Re-link by folder" (design §7, CUJ 7): matches `needs_relink` sources,
/// and `not_linked` PDFs with a file name, by file name and size.
class RelinkSources {
  RelinkSources(this._db, this._folders);

  final AppDatabase _db;
  final FolderAccess _folders;

  Future<RelinkReport> call(String folderId) async {
    final folder = await _db.sourcesDao.folderById(folderId);
    if (folder?.treeUri == null) {
      throw const FolderException(FolderError.noPermission, 'Pick the folder again first');
    }
    final byNameSize = <(String, int), String>{};
    final byName = <String, List<(String path, int size)>>{};
    await for (final e in _folders.walk(folder!.treeUri!)) {
      byNameSize.putIfAbsent((e.name, e.size), () => e.relativePath);
      (byName[e.name] ??= []).add((e.relativePath, e.size));
    }

    var matched = 0;
    final unmatched = <String>[];
    for (final s in await _db.sourcesDao.relinkCandidates()) {
      final name = s.fileName;
      if (name == null) {
        unmatched.add((await _db.nodesDao.byId(s.nodeId))?.title ?? s.nodeId);
        continue;
      }
      // Size is known for files that were linked before; a missing size
      // (typed-in file name) matches on name alone when it is unique.
      final path = s.fileSize != null
          ? byNameSize[(name, s.fileSize!)]
          : (byName[name]?.length == 1 ? byName[name]!.single.$1 : null);
      if (path == null) {
        unmatched.add(name);
        continue;
      }
      await (_db.update(_db.nodeSources)..where((t) => t.nodeId.equals(s.nodeId))).write(
        NodeSourcesCompanion(
          folderId: Value(folderId),
          relativePath: Value(path),
          fileSize: Value(s.fileSize ?? byName[name]!.single.$2),
          linkStatus: const Value(LinkStatus.ok),
        ),
      );
      matched++;
    }
    _log.info('Re-link in ${folder.displayName}: $matched matched, ${unmatched.length} not');
    return RelinkReport(matched, unmatched);
  }
}
