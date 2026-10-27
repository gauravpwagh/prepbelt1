// Battery optimisation status and device facts (plan item 69).
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

abstract interface class DeviceStatus {
  /// Null when it cannot be read (for example, not on Android).
  Future<bool?> batteryOptimizationIgnored();

  /// Opens `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, where the
  /// user finds PrepBelt themselves.
  Future<void> openBatterySettings();
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
  Future<void> openBatterySettings() => const AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      ).launch();
}
