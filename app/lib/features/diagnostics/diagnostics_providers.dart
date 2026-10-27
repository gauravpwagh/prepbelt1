import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/integrity.dart';

final integrityProvider = FutureProvider.autoDispose<IntegrityReport>(
    (ref) => runIntegrityCheck(ref.watch(appDatabaseProvider)));

class DeviceChecks {
  const DeviceChecks({
    required this.notificationsAllowed,
    required this.batteryIgnored,
    required this.pending,
    required this.lastReminderScheduled,
  });

  final bool notificationsAllowed;

  /// Null when it cannot be read.
  final bool? batteryIgnored;
  final List<String> pending;
  final DateTime? lastReminderScheduled;
}

final deviceChecksProvider = FutureProvider.autoDispose<DeviceChecks>((ref) async {
  final n = ref.watch(notificationPortProvider);
  return DeviceChecks(
    notificationsAllowed: await n.permissionGranted(),
    batteryIgnored: await ref.watch(deviceStatusProvider).batteryOptimizationIgnored(),
    pending: await n.pending(),
    lastReminderScheduled: ref.watch(reconcileNotificationsProvider).lastScheduled,
  );
});
