// App-private files (plan item 105). Above platform/ and data/, local files are
// named by path and every file operation goes through this port, so use cases,
// screens and wiring never import dart:io and another platform only swaps the
// implementations here and in data/.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A local file could not be read or written.
class LocalFileException implements Exception {
  const LocalFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class LocalFiles {
  Future<int> length(String path);

  Future<String> readString(String path);

  Future<void> writeString(String path, String contents);

  /// Up to [count] bytes from the start of [path].
  Future<List<int>> readHead(String path, int count);

  Future<void> deleteIfExists(String path);
}

class IoLocalFiles implements LocalFiles {
  const IoLocalFiles();

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FileSystemException catch (e) {
      throw LocalFileException(e.message);
    }
  }

  @override
  Future<int> length(String path) => _guard(() => File(path).length());

  @override
  Future<String> readString(String path) => _guard(() => File(path).readAsString());

  @override
  Future<void> writeString(String path, String contents) =>
      _guard(() => File(path).writeAsString(contents));

  @override
  Future<List<int>> readHead(String path, int count) => _guard(() async {
        final f = await File(path).open();
        try {
          return await f.read(count);
        } finally {
          await f.close();
        }
      });

  @override
  Future<void> deleteIfExists(String path) => _guard(() async {
        final f = File(path);
        if (await f.exists()) await f.delete();
      });
}

/// The cache directory: scratch copies that are deleted after use.
Future<String> appCacheDir() async => (await getTemporaryDirectory()).path;

/// The app-private directory: logs and the private `backups` folder.
Future<String> appPrivateDir() async => (await getApplicationSupportDirectory()).path;
