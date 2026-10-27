// Battery optimisation status and device facts (plan item 69).
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

abstract interface class DeviceStatus {
  /// Null when it cannot be read (for example, not on Android).
  Future<bool?> batteryOptimizationIgnored();

  /// Opens `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, where the
  /// user finds PrepBelt themselves.
  Future<void> openBatterySettings();

  /// "Xiaomi Redmi Note 12 · Android 14 (API 34)".
  Future<String> deviceSummary();
}

/// `prepbelt/device`, the app's one native channel (MainActivity.kt).
const deviceChannel = MethodChannel('prepbelt/device');

class AndroidDeviceStatus implements DeviceStatus {
  const AndroidDeviceStatus();

  @override
  Future<bool?> batteryOptimizationIgnored() async {
    try {
      return await deviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String> deviceSummary() async {
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      return '${a.manufacturer} ${a.model} · Android ${a.version.release} (API ${a.version.sdkInt})';
    } catch (_) {
      return 'Unknown device';
    }
  }

  @override
  Future<void> openBatterySettings() => const AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      ).launch();
}
