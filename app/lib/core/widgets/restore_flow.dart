import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup/restore_service.dart';
import '../../platform/folder_access.dart';
import '../providers.dart';

/// CUJ 7: pick the backup folder, pick a `prepbelt-*.db`, confirm, restore.
/// Returns true when the data was replaced.
Future<bool> runRestoreFlow(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final restore = restoreBackupFor(container);
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  final choice = await restore.pickFolder().catchError((Object e) {
    say('$e');
    return null;
  });
  if (choice == null || !context.mounted) return false;
  if (choice.files.isEmpty) {
    say('No PrepBelt backups in ${choice.grant.displayName}');
    return false;
  }
  final file = await showDialog<FolderEntry>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Choose a backup'),
      children: [
        for (final f in choice.files)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, f),
            child: Text(f.name),
          ),
      ],
    ),
  );
  if (file == null || !context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Replace all data?'),
      content: Text('Everything in PrepBelt will be replaced with ${file.name}. '
          'A safety backup of the current data is written first.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true) return false;

  final (result, integrity) = await restore.restore(choice, file);
  switch (result) {
    case RestoreOk():
      await afterRestore(container);
      say(integrity == null || integrity.ok
          ? 'Restored. Pick your PDF folders again in Settings, then Re-link by folder.'
          : 'Restored, but the integrity check reported problems (see Diagnostics).');
      return true;
    case RestoreNewerSchema():
      say('Update the app to restore this backup');
    case RestoreUnknownFormat():
      say('This file is not a PrepBelt backup');
    case RestoreCorrupt(:final detail):
      say('This backup is damaged: $detail');
    case RestoreIoError(:final detail):
      say('Could not restore: $detail');
  }
  return false;
}
