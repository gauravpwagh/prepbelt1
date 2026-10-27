import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:prep_core/prep_core.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets/folder_chooser.dart';
import '../../data/exchange/exam_importer.dart';
import '../../platform/folder_access.dart';
import '../../platform/local_files.dart';

final _previewProvider = FutureProvider.autoDispose
    .family<ImportPreview, String>((ref, path) => ref.watch(importExamProvider).preview(path));

/// Exams → Import: picks a `.prepbelt.json` from a granted folder and opens
/// the Import screen.
Future<void> importFromFolder(BuildContext context, WidgetRef ref) async {
  final folderId = await chooseSourceFolder(context, ref, title: 'Import from');
  if (folderId == null || !context.mounted) return;
  final db = ref.read(appDatabaseProvider);
  final folder = (await db.sourcesDao.folderById(folderId))!;
  final files = [
    await for (final e in ref.read(folderAccessProvider).walk(folder.treeUri!))
      if (e.name.endsWith('.prepbelt.json')) e,
  ];
  if (!context.mounted) return;
  if (files.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('No .prepbelt.json files in ${folder.displayName}')));
    return;
  }
  final pick = await showDialog<FolderEntry>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Choose an exam file'),
      children: [
        for (final f in files)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, f), child: Text(f.relativePath)),
      ],
    ),
  );
  if (pick == null || !context.mounted) return;
  final local = p.join(await ref.read(cacheDirProvider)(), 'import-${pick.name}');
  await ref.read(folderAccessProvider).copyToLocal(pick.uri, local);
  if (context.mounted) await context.push('/exams/import', extra: local);
}

/// The Import screen (design §10): file summary, editable name and date, ID
/// notices, one clash choice per clashing subject, Import. The file is a
/// cache copy and is deleted when the screen closes.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.path});

  /// The local cache copy of the exam file.
  final String path;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  TextEditingController? _name;
  LocalDate? _date;
  final _choices = <String, ClashChoice>{};
  var _busy = false;

  /// Read once: `ref` is unusable in [dispose].
  late final LocalFiles _files = ref.read(localFilesProvider);

  @override
  void initState() {
    super.initState();
    _files;
  }

  @override
  void dispose() {
    _name?.dispose();
    _files.deleteIfExists(widget.path).ignore();
    super.dispose();
  }

  Future<void> _import(ImportPreview p) async {
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(importExamProvider)(p,
          examName: _name!.text.trim().isEmpty ? p.package.exam.name : _name!.text,
          examDate: _date ?? p.package.exam.examDate,
          choices: _choices);
      router.go('/library');
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${p.itemCount} items'),
        action: p.hasPdfSources
            ? SnackBarAction(label: 'Re-link PDFs', onPressed: () => router.go('/settings'))
            : null,
      ));
    } on ImportRejected catch (e) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_previewProvider(widget.path));
    return Scaffold(
      appBar: AppBar(title: const Text('Import exam')),
      body: switch (preview) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error is ImportRejected
                ? 'This file can\'t be imported:\n\n$error'
                : 'Could not read the file: $error'),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, ImportPreview p) {
    final pkg = p.package;
    _name ??= TextEditingController(text: pkg.exam.name);
    final date = _date ?? pkg.exam.examDate;
    final text = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
        '${pkg.subjects.length} subjects · ${p.itemCount} items · '
        '${pkg.mode == PackageMode.progress ? 'with progress' : 'structure only'}',
        style: text.titleMedium,
      ),
      if (pkg.mode == PackageMode.structure)
        const Text('Every item starts Unread.'),
      const SizedBox(height: 12),
      TextField(
        key: const Key('import-name'),
        controller: _name,
        decoration: const InputDecoration(labelText: 'Exam name'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('${formatShortDate(date)} ${date.year}'),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime(date.year, date.month, date.day),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
        },
      ),
      const SizedBox(height: 16),
      for (final s in p.subjects) _subjectTile(s),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('import-go'),
        onPressed: _busy ? null : () => _import(p),
        child: const Text('Import'),
      ),
    ]);
  }

  Widget _subjectTile(SubjectPreview s) {
    final name = s.subject.name;
    final notice = switch (s.action) {
      SubjectAction.linkExisting => 'Already on this phone — linked, items not duplicated',
      SubjectAction.keepIds => '${s.itemCount} items',
      SubjectAction.copy => '${s.itemCount} items (copied with new IDs)',
    };
    final clash = s.clash;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          Text(notice),
          if (clash != null) ...[
            const SizedBox(height: 8),
            RadioGroup<ClashChoice>(
              groupValue: _choices[s.subject.id] ?? ClashChoice.keepSeparate,
              onChanged: (v) => setState(() => _choices[s.subject.id] = v!),
              child: Column(children: [
                RadioListTile<ClashChoice>(
                  key: Key('clash-add-${s.subject.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: ClashChoice.addToExisting,
                  title: Text('Add these items to your existing ${clash.name}'),
                  subtitle: s.clashUsedBy.isEmpty
                      ? null
                      : Text('Used by ${s.clashUsedBy.join(', ')}'),
                ),
                RadioListTile<ClashChoice>(
                  contentPadding: EdgeInsets.zero,
                  value: ClashChoice.keepSeparate,
                  title: Text('Keep a separate copy ($name 2)'),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
