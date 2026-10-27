// Folder access through the Storage Access Framework (design §7, plan item
// 67). The user grants folders, never single files.
import 'dart:io';

import 'package:saf/saf.dart';

enum FolderError { noPermission, notFound, io }

class FolderException implements Exception {
  const FolderException(this.error, this.message);
  final FolderError error;
  final String message;

  @override
  String toString() => 'FolderException(${error.name}): $message';
}

class FolderGrant {
  const FolderGrant(this.treeUri, this.displayName);
  final String treeUri;
  final String displayName;
}

class FolderEntry {
  const FolderEntry({
    required this.relativePath,
    required this.name,
    required this.size,
    required this.uri,
    required this.isDir,
  });

  final String relativePath;
  final String name;
  final int size;
  final String uri;
  final bool isDir;
}

abstract interface class FolderAccess {
  /// The system folder picker; null when cancelled.
  Future<FolderGrant?> pickFolder();

  /// Tree URIs with a persisted grant.
  Future<List<String>> persisted();

  /// Every file below [treeUri] (directories are skipped).
  Stream<FolderEntry> walk(String treeUri);

  /// The document URI of [relativePath] in [treeUri], or null.
  Future<String?> resolve(String treeUri, String relativePath);

  /// Writes the local file at [path] into [treeUri] as [name].
  Future<void> writeFile(String treeUri, String name, String path, {String mime});

  /// Files directly in [treeUri] (for backup rotation and restore).
  Future<List<FolderEntry>> list(String treeUri);

  Future<void> delete(String uri);

  /// Copies [uri] to the local path [dest].
  Future<void> copyToLocal(String uri, String dest);
}

class SafFolderAccess implements FolderAccess {
  SafFolderAccess([Saf? saf]) : _saf = saf ?? Saf();

  final Saf _saf;
  final _resolved = <String, Map<String, String>>{};

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SafPermissionException catch (e) {
      throw FolderException(FolderError.noPermission, e.message);
    } on SafNotFoundException catch (e) {
      throw FolderException(FolderError.notFound, e.message);
    } on SafException catch (e) {
      throw FolderException(FolderError.io, e.message);
    }
  }

  @override
  Future<FolderGrant?> pickFolder() => _guard(() async {
        final d = await _saf.pickDirectory();
        return d == null ? null : FolderGrant(d.uri, d.name);
      });

  @override
  Future<List<String>> persisted() =>
      _guard(() async => [for (final p in await _saf.persistedPermissions()) p.uri]);

  @override
  Stream<FolderEntry> walk(String treeUri) async* {
    try {
      await for (final e in _saf.walk(treeUri)) {
        if (e.file.isDir) continue;
        yield FolderEntry(
          relativePath: e.relativePath,
          name: e.file.name,
          size: e.file.length,
          uri: e.file.uri,
          isDir: false,
        );
      }
    } on SafPermissionException catch (e) {
      throw FolderException(FolderError.noPermission, e.message);
    } on SafNotFoundException catch (e) {
      throw FolderException(FolderError.notFound, e.message);
    }
  }

  @override
  Future<String?> resolve(String treeUri, String relativePath) async {
    final cache = _resolved[treeUri] ??= {
      await for (final e in walk(treeUri)) e.relativePath: e.uri,
    };
    final hit = cache[relativePath];
    if (hit != null && await _saf.exists(hit)) return hit;
    // The folder changed since the cached walk; walk once more.
    _resolved.remove(treeUri);
    final fresh = _resolved[treeUri] = {
      await for (final e in walk(treeUri)) e.relativePath: e.uri,
    };
    return fresh[relativePath];
  }

  @override
  Future<void> writeFile(String treeUri, String name, String path,
          {String mime = 'application/octet-stream'}) =>
      _guard(() => _saf.writeFileStream(treeUri, name, mime, File(path).openRead(), overwrite: true));

  @override
  Future<List<FolderEntry>> list(String treeUri) => _guard(() async => [
        for (final f in await _saf.list(treeUri))
          FolderEntry(
              relativePath: f.name, name: f.name, size: f.length, uri: f.uri, isDir: f.isDir),
      ]);

  @override
  Future<void> delete(String uri) => _guard(() => _saf.delete(uri));

  @override
  Future<void> copyToLocal(String uri, String dest) => _guard(() async {
        await File(dest).parent.create(recursive: true);
        await _saf.copyToLocalFile(uri, dest);
      });
}
