import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'diagnostics_providers.dart';

/// Diagnostics (design §10): notification permission, battery status with a
/// settings button, last reminder scheduled, test notification, integrity
/// result, Share logs.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final integrity = ref.watch(integrityProvider);
    final checks = ref.watch(deviceChecksProvider).value;
    final offset = ref.read(offsetFnProvider);
    String time(DateTime utc) {
      final l = utc.add(offset(utc));
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(integrityProvider);
          ref.invalidate(deviceChecksProvider);
        },
        child: ListView(children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(checks == null
                ? 'Checking…'
                : checks.notificationsAllowed
                    ? 'Allowed'
                    : 'Not allowed'),
            trailing: checks != null && !checks.notificationsAllowed
                ? TextButton(
                    onPressed: () async {
                      await ref.read(notificationPortProvider).requestPermission();
                      ref.invalidate(deviceChecksProvider);
                    },
                    child: const Text('Allow'),
                  )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Battery optimisation'),
            subtitle: Text(switch (checks?.batteryIgnored) {
              true => 'Off for PrepBelt — reminders run on time',
              false => 'On — reminders may be delayed',
              null => 'Unknown',
            }),
            trailing: TextButton(
              onPressed: () => ref.read(deviceStatusProvider).openBatterySettings(),
              child: const Text('Settings'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Daily reminder'),
            subtitle: Text([
              if (checks?.lastReminderScheduled != null)
                'Last scheduled at ${time(checks!.lastReminderScheduled!)}',
              if (checks != null) '${checks.pending.length} pending',
            ].join(' · ')),
          ),
          ListTile(
            key: const Key('diag-test'),
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Send test notification'),
            onTap: () => ref.read(notificationPortProvider).showTest(),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Database integrity'),
            subtitle: Text(switch (integrity) {
              AsyncData(:final value) => '$value',
              AsyncError(:final error) => 'Check failed: $error',
              _ => 'Checking…',
            }),
            trailing: IconButton(
              tooltip: 'Check again',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(integrityProvider),
            ),
          ),
          ListTile(
            key: const Key('diag-share-logs'),
            leading: const Icon(Icons.ios_share),
            title: const Text('Share logs'),
            subtitle: const Text('Logs and device facts only — never your data'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(shareLogsProvider)();
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Could not share logs: $e')));
              }
            },
          ),
        ]),
      ),
    );
  }
}
