import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db_watch.dart';
import '../../../core/providers.dart';
import '../../../platform/folder_access.dart';

final _needsFolderProvider = StreamProvider.autoDispose<bool>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final backups = ref.watch(backupServiceProvider);
  return watchTables(db, {db.settings, db.sourceFolders}, () async => await backups.backupTree() == null);
});

/// Shown until a backup folder is chosen (design §8).
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(_needsFolderProvider).value ?? false)) return const SizedBox.shrink();
    return Card(
      key: const Key('backup-banner'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Choose a backup folder'),
        subtitle: const Text('Backups stay on this phone until you do.'),
        trailing: TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              if (await ref.read(runBackupProvider).chooseFolder()) {
                messenger.showSnackBar(const SnackBar(content: Text('Backed up')));
              }
            } on FolderException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message)));
            }
          },
          child: const Text('Choose'),
        ),
      ),
    );
  }
}
