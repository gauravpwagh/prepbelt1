import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:prepbelt/application/share_logs.dart';
import 'package:prepbelt/platform/logging.dart';

import 'app_helpers.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('prepbelt_log_test'));
  tearDown(() => dir.delete(recursive: true));

  test('the log rotates at the size limit and keeps two files', () {
    final sink = FileLogSink(dir, now: () => t0, maxBytes: 100);
    for (var i = 0; i < 30; i++) {
      sink.write('line $i ${'x' * 20}');
    }
    expect(sink.current.existsSync(), isTrue);
    expect(sink.previous.existsSync(), isTrue);
    expect(dir.listSync().length, 2);
    expect(sink.current.readAsStringSync(), contains('line 29'));
    expect(sink.previous.readAsStringSync(), isNot(contains('line 0 ')));
  });

  test('records are formatted with level, logger and error', () {
    final r = LogRecord(Level.WARNING, 'Backup failed', 'backup', StateError('disk'));
    expect(formatRecord(r), contains('WARNING backup: Backup failed | Bad state: disk'));
  });

  test('Share logs zips logs, crash.log and meta.txt — never the database', () async {
    final sink = FileLogSink(dir, now: () => t0)
      ..write('hello')
      ..writeCrash(StateError('boom'), StackTrace.empty);
    expect(sink.crash.readAsStringSync(), startsWith('${t0.toIso8601String()} Bad state: boom'));
    final notes = FakeNotifications()..granted = false;
    final sharer = FakeSharer();
    final share = ShareLogs(sink, FakeDeviceStatus()..ignored = true, notes, sharer,
        appVersion: '0.1.0', tzId: 'Asia/Kolkata', cacheDir: () async => dir, now: () => t0);

    final meta = await share.meta();
    expect(meta, contains('PrepBelt 0.1.0 (schema 1)'));
    expect(meta, contains('Notifications allowed: false'));
    expect(meta, contains('Battery optimisation ignored: true'));
    expect(meta, contains('Time zone: Asia/Kolkata'));

    await share();
    final zip = ZipDecoder().decodeBytes(File(sharer.shared.single).readAsBytesSync());
    expect(zip.files.map((f) => f.name), unorderedEquals(['log.txt', 'crash.log', 'meta.txt']));
  });
}
