import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/layout.dart';
import '../../core/providers.dart';
import 'archive_sheet.dart';
import 'exam_form.dart';
import 'export_sheet.dart';
import 'import_screen.dart';
import 'exams_providers.dart';

class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(examsViewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Exams'), actions: [
        IconButton(
          key: const Key('exam-import'),
          tooltip: 'Import',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: () => importFromFolder(context, ref),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-exams',
        key: const Key('exam-add'),
        icon: const Icon(Icons.add),
        label: const Text('Exam'),
        onPressed: () => showExamForm(context),
      ),
      body: ReadingWidth(child: switch (view) {
        AsyncData(:final value) => value.exams.isEmpty
            ? const Center(child: Text('No exams yet'))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [for (final e in value.exams) _ExamTile(e)],
              ),
        AsyncError(:final error) => Center(child: Text('Could not load: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      }),
    );
  }
}

class _ExamTile extends ConsumerWidget {
  const _ExamTile(this.entry);
  final ExamEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry.exam;
    final today = ref.watch(todayProvider);
    final archived = e.archivedAt != null;
    final passed = e.examDate <= today;
    final days = today.daysUntil(e.examDate);
    return ListTile(
      key: Key('exam-${e.id}'),
      title: Text(e.name),
      subtitle: Text([
        '${formatShortDate(e.examDate)} ${e.examDate.year}',
        if (archived) 'archived' else if (passed) 'passed' else 'in $days days',
        if (entry.subjects.isNotEmpty) entry.subjects.map((s) => s.name).join(', '),
      ].join(' · ')),
      leading: Icon(archived ? Icons.archive_outlined : Icons.event_note),
      onTap: () => showExamForm(context, entry: entry),
      trailing: PopupMenuButton<String>(
        onSelected: (a) async {
          final save = ref.read(saveExamProvider);
          final plans = ref.read(buildTodayPlanProvider);
          switch (a) {
            case 'unarchive':
              await save.setArchived(e.id, archived: false);
              await plans.refresh();
            case 'archive':
              await showArchiveSheet(context, entry);
            case 'export':
              await showExportSheet(context, entry);
            case 'copy':
              await showCopyAttemptDialog(context, entry);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'export', child: Text('Export')),
          const PopupMenuItem(value: 'copy', child: Text('Copy as new attempt')),
          PopupMenuItem(
            value: archived ? 'unarchive' : 'archive',
            child: Text(archived ? 'Unarchive' : 'Archive…'),
          ),
        ],
      ),
    );
  }
}
