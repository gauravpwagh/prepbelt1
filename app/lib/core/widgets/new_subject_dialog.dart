import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../providers.dart';

final _openExamsProvider = FutureProvider.autoDispose<List<ExamRow>>((ref) async => [
      for (final e in await ref.watch(appDatabaseProvider).examsDao.all())
        if (e.archivedAt == null) e,
    ]);

/// Creates a subject where one is being picked (design §10a): a name and
/// optional exams to link it to. Returns the new subject, or null when
/// cancelled.
Future<SubjectRow?> showNewSubjectDialog(BuildContext context) => showDialog<SubjectRow>(
      context: context,
      builder: (_) => const _NewSubjectDialog(),
    );

class _NewSubjectDialog extends ConsumerStatefulWidget {
  const _NewSubjectDialog();

  @override
  ConsumerState<_NewSubjectDialog> createState() => _NewSubjectDialogState();
}

class _NewSubjectDialogState extends ConsumerState<_NewSubjectDialog> {
  final _name = TextEditingController();
  final _exams = <String>{};
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final db = ref.read(appDatabaseProvider);
    final id = await ref.read(saveExamProvider).createSubject(_name.text, examIds: _exams);
    navigator.pop(await db.subjectsDao.byId(id));
  }

  @override
  Widget build(BuildContext context) {
    final exams = ref.watch(_openExamsProvider).value ?? const [];
    return AlertDialog(
      title: const Text('New subject'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('new-subject-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Subject name'),
              onSubmitted: (_) => _create(),
            ),
            if (exams.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('For exams (optional)', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 8, children: [
                for (final e in exams)
                  FilterChip(
                    label: Text(e.name),
                    selected: _exams.contains(e.id),
                    onSelected: (on) =>
                        setState(() => on ? _exams.add(e.id) : _exams.remove(e.id)),
                  ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('new-subject-create'),
          onPressed: _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Asks for a single name (rename a subject, new topic). Returns the trimmed
/// name, or null when cancelled or empty.
Future<String?> showNameDialog(BuildContext context,
    {required String title, required String label, String initial = '', String action = 'Save'}) async {
  final c = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('name-dialog-field'),
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
          key: const Key('name-dialog-ok'),
          onPressed: () => Navigator.pop(d, c.text),
          child: Text(action),
        ),
      ],
    ),
  );
  // The controller is left to the garbage collector: the dialog may still be
  // animating out.
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}
