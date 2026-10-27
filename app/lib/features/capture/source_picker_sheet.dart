import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/add_item.dart';
import '../../core/providers.dart';
import '../../core/widgets/folder_chooser.dart';
import '../../data/db/converters.dart';
import '../../platform/folder_access.dart';

/// The in-app folder browser (design §7): every pick is inside a granted
/// folder, so the app never needs per-file permissions.
Future<NewSource?> pickPdfSource(BuildContext context, WidgetRef ref) async {
  final folderId = await chooseSourceFolder(context, ref, title: 'Pick a PDF from');
  if (folderId == null || !context.mounted) return null;
  final folder = (await ref.read(appDatabaseProvider).sourcesDao.folderById(folderId))!;
  if (!context.mounted) return null;
  final entry = await showModalBottomSheet<FolderEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PdfBrowser(treeUri: folder.treeUri!, folderName: folder.displayName),
  );
  if (entry == null) return null;
  return NewSource(
    type: SourceType.pdf,
    folderId: folderId,
    relativePath: entry.relativePath,
    fileName: entry.name,
    fileSize: entry.size,
    linkStatus: LinkStatus.ok,
  );
}

final _pdfsProvider =
    FutureProvider.autoDispose.family<List<FolderEntry>, String>((ref, treeUri) async {
  final all = await ref.watch(folderAccessProvider).walk(treeUri).toList();
  return [
    for (final e in all)
      if (e.name.toLowerCase().endsWith('.pdf')) e,
  ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
});

class _PdfBrowser extends ConsumerStatefulWidget {
  const _PdfBrowser({required this.treeUri, required this.folderName});
  final String treeUri;
  final String folderName;

  @override
  ConsumerState<_PdfBrowser> createState() => _PdfBrowserState();
}

class _PdfBrowserState extends ConsumerState<_PdfBrowser> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final pdfs = ref.watch(_pdfsProvider(widget.treeUri));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
                labelText: 'Search ${widget.folderName}', prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: switch (pdfs) {
            AsyncData(:final value) => () {
                final shown = [
                  for (final e in value)
                    if (_query.isEmpty || e.relativePath.toLowerCase().contains(_query)) e,
                ];
                if (shown.isEmpty) return const Center(child: Text('No PDFs here'));
                return ListView(children: [
                  for (final e in shown)
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(e.name),
                      subtitle: e.relativePath == e.name ? null : Text(e.relativePath),
                      onTap: () => Navigator.pop(context, e),
                    ),
                ]);
              }(),
            AsyncError(:final error) => Center(child: Text('Could not read the folder: $error')),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ]),
    );
  }
}
