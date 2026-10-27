import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/exam_exchange.dart';
import '../../core/providers.dart';
import '../../platform/folder_access.dart';
import 'exams_providers.dart';

/// Export (CUJ 9, 11): Structure only / With progress, "Include notes and
/// excerpts" (off for structure, on for progress), the also-used-by notice,
/// and Share or Save to folder.
Future<void> showExportSheet(BuildContext context, ExamEntry entry) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExportSheet(entry: entry),
    );

final _noticesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, id) => ref.watch(exportExamProvider).alsoUsedNotices(id));

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, required this.entry});
  final ExamEntry entry;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  var _mode = PackageMode.structure;
  var _notes = false;
  var _busy = false;

  Future<void> _run(Future<String?> Function(ExportExam e) f) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final m = await f(ref.read(exportExamProvider));
      navigator.pop();
      if (m != null) messenger.showSnackBar(SnackBar(content: Text(m)));
    } on FolderException catch (e) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _share() async {
    if (_mode == PackageMode.progress) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: const Text(historyWarning),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Share')),
          ],
        ),
      );
      if (go != true) return;
    }
    await _run((e) async {
      await e.share(widget.entry.exam.id, _mode, includeNotes: _notes);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(_noticesProvider(widget.entry.exam.id)).value ?? const [];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export ${widget.entry.exam.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<PackageMode>(
              segments: const [
                ButtonSegment(value: PackageMode.structure, label: Text('Structure only')),
                ButtonSegment(value: PackageMode.progress, label: Text('With progress')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.single;
                _notes = _mode == PackageMode.progress;
              }),
            ),
            SwitchListTile(
              key: const Key('export-notes'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Include notes and excerpts'),
              subtitle: const Text('Excerpts, location notes, AI-chat links and your other exam names'),
              value: _notes,
              onChanged: (v) => setState(() => _notes = v),
            ),
            for (final n in notices)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(n)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save to folder'),
                  onPressed: _busy
                      ? null
                      : () => _run((e) async =>
                          'Saved ${await e.saveToFolder(widget.entry.exam.id, _mode, includeNotes: _notes)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('export-share'),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: _busy ? null : _share,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
