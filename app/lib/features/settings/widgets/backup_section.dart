import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db_watch.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/restore_flow.dart';
import '../../../platform/folder_access.dart';

final _backupInfoProvider = StreamProvider.autoDispose<(String?, DateTime?)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(db, {db.settings, db.sourceFolders}, () async {
    final id = await db.settingsDao.backupFolderId();
    final folder = id == null ? null : await db.sourcesDao.folderById(id);
    return (
      folder == null ? null : (folder.treeUri == null ? '${folder.displayName} (pick again)' : folder.displayName),
      await db.settingsDao.lastBackupAtUtc(),
    );
  });
});

/// Backup folder, Back up now, Restore (design §10 Settings).
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  Future<void> _run(BuildContext context, Future<String?> Function() f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final m = await f();
      if (m != null) messenger.showSnackBar(SnackBar(content: Text(m)));
    } on FolderException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (folder, last) = ref.watch(_backupInfoProvider).value ?? (null, null);
    final backup = ref.read(runBackupProvider);
    final offset = ref.read(offsetFnProvider);
    String when(DateTime utc) {
      final l = utc.add(offset(utc));
      return '${formatShortDate(ref.read(localDayClockProvider).dayOf(utc))} '
          '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Backups')),
      ListTile(
        key: const Key('settings-backup-folder'),
        leading: const Icon(Icons.folder_special_outlined),
        title: const Text('Backup folder'),
        subtitle: Text(folder ?? 'Not chosen — backups stay on this phone'),
        onTap: () => _run(context, () async =>
            await backup.chooseFolder() ? 'Backup folder set' : null),
      ),
      ListTile(
        key: const Key('settings-backup-now'),
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Back up now'),
        subtitle: Text(last == null ? 'No backup yet' : 'Last backup ${when(last)}'),
        onTap: () => _run(context, () async => 'Saved ${(await backup.now()).name}'),
      ),
      ListTile(
        key: const Key('settings-restore'),
        leading: const Icon(Icons.restore),
        title: const Text('Restore from backup'),
        onTap: () => runRestoreFlow(context),
      ),
    ]);
  }
}
