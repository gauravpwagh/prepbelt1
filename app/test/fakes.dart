import 'dart:async';
import 'dart:io';

import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/platform/folder_access.dart';
import 'package:prepbelt/platform/share_receiver.dart';
import 'package:prepbelt/platform/device_status.dart';
import 'package:prepbelt/platform/notification_port.dart';
import 'package:prepbelt/platform/source_opener.dart';

/// Records what the app asked the notification system to do.
class FakeNotifications implements NotificationPort {
  final log = <String>[];
  bool granted = true;
  String? launch;

  @override
  Future<void> init(void Function(String route) onTap) async => log.add('init');
  @override
  Future<String?> launchRoute() async => launch;
  @override
  Future<void> showOngoingSession(String title, DateTime startedAtUtc) async =>
      log.add('ongoing:$title');
  @override
  Future<void> scheduleStillReading(DateTime atUtc, String title) async =>
      log.add('still:${atUtc.toIso8601String()}');
  @override
  Future<void> scheduleDailyReminder(int hour, int minute) async =>
      log.add('reminder:$hour:$minute');
  @override
  Future<void> cancelSession() async => log.add('cancel');
  @override
  Future<bool> requestPermission() async {
    log.add('request');
    return granted;
  }

  @override
  Future<bool> permissionGranted() async => granted;
  @override
  Future<List<String>> pending() async => const ['#1 Your study plan is ready'];
  @override
  Future<void> showTest() async => log.add('test');
}

class FakeDeviceStatus implements DeviceStatus {
  bool? ignored = false;
  var opened = 0;
  @override
  Future<bool?> batteryOptimizationIgnored() async => ignored;
  @override
  Future<void> openBatterySettings() async => opened++;
}

class FakeOpener implements SourceOpener {
  OpenResult result = OpenResult.ok;
  final opened = <String>[];
  @override
  Future<OpenResult> open(SourceRow source) async {
    opened.add(source.nodeId);
    return result;
  }
}

/// Folders as maps of relative path → size. URIs are `tree:<name>` and
/// `doc:<name>/<path>`.
class FakeFolderAccess implements FolderAccess {
  final trees = <String, Map<String, int>>{};
  final written = <String, List<String>>{};
  String? nextPick;

  void addTree(String name, Map<String, int> files) => trees['tree:$name'] = files;

  @override
  Future<FolderGrant?> pickFolder() async {
    final n = nextPick;
    if (n == null) return null;
    trees.putIfAbsent('tree:$n', () => {});
    return FolderGrant('tree:$n', n);
  }

  @override
  Future<List<String>> persisted() async => trees.keys.toList();

  @override
  Stream<FolderEntry> walk(String treeUri) async* {
    final t = trees[treeUri];
    if (t == null) throw const FolderException(FolderError.noPermission, 'No access');
    for (final MapEntry(key: path, value: size) in t.entries) {
      yield FolderEntry(
          relativePath: path,
          name: path.split('/').last,
          size: size,
          uri: 'doc:${treeUri.substring(5)}/$path',
          isDir: false);
    }
  }

  @override
  Future<String?> resolve(String treeUri, String relativePath) async =>
      trees[treeUri]?.containsKey(relativePath) == true
          ? 'doc:${treeUri.substring(5)}/$relativePath'
          : null;

  @override
  Future<void> writeFile(String treeUri, String name, File file, {String mime = ''}) async {
    final t = trees[treeUri];
    if (t == null) throw const FolderException(FolderError.noPermission, 'No access');
    t[name] = await file.length();
    (written[treeUri] ??= []).add(name);
  }

  @override
  Future<List<FolderEntry>> list(String treeUri) async => [
        for (final MapEntry(key: path, value: size) in (trees[treeUri] ?? const {}).entries)
          if (!path.contains('/'))
            FolderEntry(
                relativePath: path,
                name: path,
                size: size,
                uri: 'doc:${treeUri.substring(5)}/$path',
                isDir: false),
      ];

  @override
  Future<void> delete(String uri) async {
    final rest = uri.substring(4);
    final slash = rest.indexOf('/');
    trees['tree:${rest.substring(0, slash)}']?.remove(rest.substring(slash + 1));
  }

  /// Local files that "live" in a folder, for copyToLocal.
  final contents = <String, File>{};

  @override
  Future<File> copyToLocal(String uri, File dest) async {
    final src = contents[uri];
    if (src == null) throw const FolderException(FolderError.notFound, 'Missing');
    await dest.parent.create(recursive: true);
    return src.copy(dest.path);
  }
}

class FakeShareReceiver implements ShareReceiver {
  final _c = StreamController<IncomingShare>.broadcast();
  void send(IncomingShare s) => _c.add(s);

  @override
  Stream<IncomingShare> get shares => _c.stream;
}
