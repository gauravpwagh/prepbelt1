import 'package:prepbelt/data/db/app_database.dart';
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
