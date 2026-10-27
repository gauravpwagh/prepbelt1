import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/slots.dart';
import 'settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editMinutes(BuildContext context, WidgetRef ref, int current) async {
    final c = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily study minutes'),
        content: TextField(
          key: const Key('daily-minutes'),
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              helperText: '${Defaults.dailyMinutesMin}–${Defaults.dailyMinutesMax} minutes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(c.text.trim());
              if (v != null && v >= Defaults.dailyMinutesMin && v <= Defaults.dailyMinutesMax) {
                Navigator.pop(ctx, v);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (value != null) await ref.read(settingsActionsProvider).setDailyMinutes(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(settingsViewProvider);
    final extra = ref.watch(settingsSectionsProvider);
    final actions = ref.read(settingsActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: switch (view) {
        AsyncData(:final value) => ListView(children: [
            ListTile(
              key: const Key('settings-minutes'),
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Daily study time'),
              subtitle: Text('${value.dailyMinutes} min'),
              onTap: () => _editMinutes(context, ref, value.dailyMinutes),
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: const Text('New study day starts at'),
              subtitle: const Text('Work after midnight counts for the day before'),
              trailing: DropdownButton<int>(
                value: value.dayStartHour,
                items: [
                  for (var h = 0; h <= 6; h++)
                    DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
                ],
                onChanged: (h) => h == null ? null : actions.setDayStartHour(h),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Daily reminder'),
              subtitle: Text(TimeOfDay(hour: value.reminder.hour, minute: value.reminder.minute)
                  .format(context)),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: value.reminder.hour, minute: value.reminder.minute),
                );
                if (t != null) await actions.setReminderTime(t.hour, t.minute);
              },
            ),
            ...extra,
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('Diagnostics'),
              onTap: () => context.push('/diagnostics'),
            ),
          ]),
        AsyncError(:final error) => Center(child: Text('Could not load: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
