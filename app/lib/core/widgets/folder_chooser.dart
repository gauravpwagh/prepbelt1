import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/converters.dart';
import '../../platform/folder_access.dart';
import '../providers.dart';

/// Lets the user choose one of the granted source folders, or grant a new
/// one. Returns the folder ID, or null when cancelled.
Future<String?> chooseSourceFolder(BuildContext context, WidgetRef ref,
    {String title = 'Choose a folder'}) async {
  final db = ref.read(appDatabaseProvider);
  final folders = await db.sourcesDao.folders(FolderPurpose.sources);
  if (!context.mounted) return null;
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (final f in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, f.id),
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.displayName),
              subtitle: f.treeUri == null ? const Text('Pick again') : null,
            ),
          ),
        SimpleDialogOption(
          key: const Key('folder-grant-new'),
          onPressed: () => Navigator.pop(c, ''),
          child: const ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('Grant access to a folder'),
          ),
        ),
      ],
    ),
  );
  if (choice == null) return null;
  final sources = ref.read(sourceFoldersProvider);
  try {
    if (choice.isEmpty) return await sources.add(FolderPurpose.sources);
    final f = folders.firstWhere((f) => f.id == choice);
    if (f.treeUri == null && !await sources.regrant(f.id)) return null;
    return choice;
  } on FolderException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return null;
  }
}

/// Runs "Re-link by folder" and reports what matched.
Future<void> relinkByFolder(BuildContext context, WidgetRef ref) async {
  final folderId = await chooseSourceFolder(context, ref, title: 'Re-link by folder');
  if (folderId == null || !context.mounted) return;
  try {
    final r = await ref.read(relinkSourcesProvider)(folderId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Re-linked ${r.matched}'),
        content: r.unmatched.isEmpty
            ? const Text('Every source was matched.')
            : Text('Not found in this folder:\n${r.unmatched.take(20).join('\n')}'
                '${r.unmatched.length > 20 ? '\n…' : ''}'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  } on FolderException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
