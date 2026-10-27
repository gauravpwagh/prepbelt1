import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';
import 'exams_providers.dart';

/// Create or edit an exam: name, date, and linked subjects.
Future<void> showExamForm(BuildContext context, {ExamEntry? entry}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExamForm(entry: entry),
    );

class ExamForm extends ConsumerStatefulWidget {
  const ExamForm({super.key, this.entry});
  final ExamEntry? entry;

  @override
  ConsumerState<ExamForm> createState() => _ExamFormState();
}

class _ExamFormState extends ConsumerState<ExamForm> {
  late final _name = TextEditingController(text: widget.entry?.exam.name ?? '');
  final _newSubject = TextEditingController();
  late LocalDate? _date = widget.entry?.exam.examDate;
  late final Set<String> _subjects = {
    for (final s in widget.entry?.subjects ?? const <SubjectRow>[]) s.id,
  };

  @override
  void dispose() {
    _name.dispose();
    _newSubject.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final initial = _date ?? today.plusDays(90);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  Future<void> _addSubject() async {
    final name = _newSubject.text.trim();
    if (name.isEmpty) return;
    final id = await ref.read(saveExamProvider).createSubject(name);
    setState(() {
      _subjects.add(id);
      _newSubject.clear();
    });
  }

  Future<void> _save() async {
    final date = _date;
    if (_name.text.trim().isEmpty || date == null) return;
    final save = ref.read(saveExamProvider);
    final navigator = Navigator.of(context);
    final e = widget.entry;
    if (e == null) {
      await save.create(_name.text, date, _subjects);
    } else {
      await save.update(e.exam.id, _name.text, date, _subjects);
    }
    await ref.read(buildTodayPlanProvider).refresh();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(examsViewProvider).value?.allSubjects ?? const [];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.entry == null ? 'New exam' : 'Edit exam',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                key: const Key('exam-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Exam name'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('exam-date'),
                icon: const Icon(Icons.event),
                label: Text(_date == null
                    ? 'Pick the exam date'
                    : '${formatShortDate(_date!)} ${_date!.year}'),
                onPressed: _pickDate,
              ),
              const SizedBox(height: 12),
              const Text('Subjects'),
              Wrap(spacing: 8, children: [
                for (final s in subjects)
                  FilterChip(
                    label: Text(s.name),
                    selected: _subjects.contains(s.id),
                    onSelected: (on) =>
                        setState(() => on ? _subjects.add(s.id) : _subjects.remove(s.id)),
                  ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newSubject,
                    decoration: const InputDecoration(labelText: 'New subject'),
                    onSubmitted: (_) => _addSubject(),
                  ),
                ),
                IconButton(onPressed: _addSubject, icon: const Icon(Icons.add)),
              ]),
              const SizedBox(height: 16),
              FilledButton(key: const Key('exam-save'), onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
