// Logging, crash capture and Share logs (design §11, plan item 71). Nothing is
// uploaded; logs leave the phone only through the share sheet.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// A rotating log: `log.txt` plus one older `log.1.txt`, about 1 MB each.
class FileLogSink {
  FileLogSink(this.dir, {required DateTime Function() now, this.maxBytes = 1024 * 1024})
      : _now = now;

  final Directory dir;
  final int maxBytes;
  final DateTime Function() _now;

  File get current => File(p.join(dir.path, 'log.txt'));
  File get previous => File(p.join(dir.path, 'log.1.txt'));
  File get crash => File(p.join(dir.path, 'crash.log'));

  void write(String line) {
    try {
      final f = current;
      if (f.existsSync() && f.lengthSync() > maxBytes) {
        if (previous.existsSync()) previous.deleteSync();
        f.renameSync(previous.path);
      }
      current.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } on FileSystemException {
      // Logging must never take the app down.
    }
  }

  void writeCrash(Object error, StackTrace? stack) {
    try {
      crash.writeAsStringSync(
          '${_now().toIso8601String()} $error\n${stack ?? ''}\n\n',
          mode: FileMode.append);
    } on FileSystemException {
      // Ignored for the same reason.
    }
  }

  List<File> get files => [previous, current, crash].where((f) => f.existsSync()).toList();
}

String formatRecord(LogRecord r) {
  final b = StringBuffer('${r.time.toUtc().toIso8601String()} ${r.level.name} ${r.loggerName}: ${r.message}');
  if (r.error != null) b.write(' | ${r.error}');
  if (r.stackTrace != null) b.write('\n${r.stackTrace}');
  return b.toString();
}

/// Sends every log record to [sink] (and to the console in debug builds).
void initLogging(FileLogSink sink) {
  sink.dir.createSync(recursive: true);
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    final line = formatRecord(r);
    sink.write(line);
    if (kDebugMode) debugPrint(line);
  });
}

/// `FlutterError.onError` and `PlatformDispatcher.instance.onError` write
/// to `crash.log`.
void installErrorHooks(FileLogSink sink) {
  final log = Logger('crash');
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    sink.writeCrash(details.exception, details.stack);
    log.severe('Flutter error', details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    sink.writeCrash(error, stack);
    log.severe('Uncaught error', error, stack);
    return true;
  };
}

/// Zips the logs, `crash.log` and [meta] (`meta.txt`) into [outDir].
File zipLogs(FileLogSink sink, String meta, Directory outDir) {
  final archive = Archive();
  for (final f in sink.files) {
    archive.add(ArchiveFile.bytes(p.basename(f.path), f.readAsBytesSync()));
  }
  archive.add(ArchiveFile.bytes('meta.txt', utf8.encode(meta)));
  final out = File(p.join(outDir.path, 'prepbelt-logs.zip'));
  out.writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return out;
}
