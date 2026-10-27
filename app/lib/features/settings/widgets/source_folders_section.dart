import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db_watch.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/folder_chooser.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/converters.dart';
import '../../../platform/folder_access.dart';

final _foldersProvider = StreamProvider.autoDispose<List<FolderRow>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return watchTables(db, {db.sourceFolders}, () => db.sourcesDao.folders(FolderPurpose.sources));
});

/// Source folders: grant, pick again (after a restore), forget, re-link.
class SourceFoldersSection extends ConsumerWidget {
  const SourceFoldersSection({super.key});

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } on FolderException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(_foldersProvider).value ?? const [];
    final manage = ref.read(sourceFoldersProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Source folders'),
      ),
      for (final f in folders)
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(f.displayName),
          subtitle: f.treeUri == null ? const Text('Pick again to restore access') : null,
          trailing: PopupMenuButton<String>(
            onSelected: (a) => _guard(context, () async {
              if (a == 'regrant') await manage.regrant(f.id);
              if (a == 'forget') await manage.forget(f.id);
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'regrant', child: Text('Pick again')),
              PopupMenuItem(value: 'forget', child: Text('Forget folder')),
            ],
          ),
        ),
      ListTile(
        key: const Key('settings-add-folder'),
        leading: const Icon(Icons.create_new_folder_outlined),
        title: const Text('Grant access to a folder'),
        onTap: () => _guard(context, () => manage.add(FolderPurpose.sources)),
      ),
      ListTile(
        leading: const Icon(Icons.link),
        title: const Text('Re-link by folder'),
        subtitle: const Text('Match PDFs by file name and size'),
        onTap: () => relinkByFolder(context, ref),
      ),
    ]);
  }
}
