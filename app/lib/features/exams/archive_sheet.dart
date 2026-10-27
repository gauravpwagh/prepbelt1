import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/archive_and_remove.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import 'exams_providers.dart';

/// Archive (keep in app), or Export and remove (CUJ 12).
Future<void> showArchiveSheet(BuildContext context, ExamEntry entry) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archive (keep in app)'),
            subtitle: const Text('Stops planning and capping; history stays'),
            onTap: () async {
              Navigator.pop(c);
              final container = ProviderScope.containerOf(context, listen: false);
              await container.read(saveExamProvider).setArchived(entry.exam.id, archived: true);
              await container.read(buildTodayPlanProvider).refresh();
            },
          ),
          ListTile(
            key: const Key('archive-remove'),
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Export and remove'),
            subtitle: const Text('Saves a file with progress to the backup folder, then deletes'),
            onTap: () {
              Navigator.pop(c);
              _exportAndRemove(context, entry);
            },
          ),
        ]),
      ),
    );

Future<void> _exportAndRemove(BuildContext context, ExamEntry entry) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final archive = container.read(archiveAndRemoveProvider);
  final messenger = ScaffoldMessenger.of(context);
  final ArchivePlan plan;
  try {
    plan = await archive.prepare(entry.exam.id);
  } on ArchiveBlocked catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  final typed = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Remove this exam?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saved ${plan.fileName} in ${plan.folderName}.'),
          if (plan.keptSubjects.isNotEmpty)
            Text('Kept (used by another exam): ${plan.keptSubjects.join(', ')}.'),
          const SizedBox(height: 8),
          Text('Type "${plan.examName}" to delete it with its items, history and sessions.'),
          TextField(
            key: const Key('archive-typed'),
            controller: typed,
            onChanged: (_) => setState(() {}),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('archive-confirm'),
            onPressed: typed.text.trim() == plan.examName.trim() ? () => Navigator.pop(c, true) : null,
            child: const Text('Remove'),
          ),
        ],
      ),
    ),
  );
  final name = typed.text;
  typed.dispose();
  if (ok != true) return;
  await archive.remove(plan, typedName: name);
  messenger.showSnackBar(SnackBar(content: Text('Removed ${plan.examName}')));
}

/// Copy as new attempt (CUJ 10): asks for the new name and date.
Future<void> showCopyAttemptDialog(BuildContext context, ExamEntry entry) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final name = TextEditingController(text: '${entry.exam.name} (next attempt)');
  var date = entry.exam.examDate.plusDays(365);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Copy as new attempt'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('copy-name'), controller: name,
              decoration: const InputDecoration(labelText: 'Exam name')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('${formatShortDate(date)} ${date.year}'),
            onPressed: () async {
              final picked = await showDatePicker(
                  context: c,
                  initialDate: DateTime(date.year, date.month, date.day),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100));
              if (picked != null) setState(() => date = LocalDate.fromDateTime(picked));
            },
          ),
          const SizedBox(height: 8),
          const Text('Subjects are copied separately; every item starts Unread.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              key: const Key('copy-go'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Copy')),
        ],
      ),
    ),
  );
  final n = name.text;
  name.dispose();
  if (ok != true) return;
  await container.read(copyAsNewAttemptProvider)(entry.exam.id, name: n, date: date);
}
