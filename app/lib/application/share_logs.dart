import 'dart:io';

import '../data/db/app_database.dart';
import '../platform/device_status.dart';
import '../platform/file_sharer.dart';
import '../platform/logging.dart';
import '../platform/notification_port.dart';

/// Share logs (design §11): logs, crash.log and meta.txt in one zip through
/// the share sheet. The database is never included.
class ShareLogs {
  ShareLogs(this._sink, this._device, this._notifications, this._sharer,
      {required this.appVersion,
      required this.tzId,
      required Future<Directory> Function() cacheDir,
      required DateTime Function() now})
      : _cacheDir = cacheDir,
        _now = now;

  final FileLogSink _sink;
  final DeviceStatus _device;
  final NotificationPort _notifications;
  final FileSharer _sharer;
  final String appVersion;
  final String tzId;
  final Future<Directory> Function() _cacheDir;
  final DateTime Function() _now;

  Future<String> meta() async {
    final battery = await _device.batteryOptimizationIgnored();
    return [
      'PrepBelt $appVersion (schema ${AppDatabase.currentSchema})',
      'Device: ${await _device.deviceSummary()}',
      'Time zone: $tzId',
      'Notifications allowed: ${await _notifications.permissionGranted()}',
      'Battery optimisation ignored: ${battery ?? 'unknown'}',
      'Created: ${_now().toIso8601String()}',
    ].join('\n');
  }

  Future<File> zip() async => zipLogs(_sink, await meta(), await _cacheDir());

  Future<void> call() async => _sharer.shareFile(await zip(), subject: 'PrepBelt logs');
}
