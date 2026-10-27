import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/add_item.dart';
import '../../core/providers.dart';
import 'capture_providers.dart';

/// Quick add: a title and one tap (design §10). The last-used subject is
/// preselected; "More options" opens the full form.
Future<void> showQuickAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const QuickAddSheet(),
    );

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _title = TextEditingController();
  String? _subjectId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(addItemProvider)(AddItemRequest(title: _title.text, subjectId: _subjectId));
    await ref.read(buildTodayPlanProvider).refresh();
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Added "${_title.text.trim()}"')));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(addFormDataProvider(null));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: switch (data) {
          AsyncData(:final value) => () {
              final fallback = value.subjects.any((s) => s.id == value.lastSubjectId)
                  ? value.lastSubjectId!
                  : value.subjects.first.id;
              final selected = _subjectId ?? fallback;
              return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('quick-title'),
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final s in value.subjects)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: selected == s.id,
                      onSelected: (_) => setState(() => _subjectId = s.id),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/add');
                    },
                    child: const Text('More options'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _subjectId ??= fallback;
                      _save();
                    },
                    child: const Text('Save'),
                  ),
                ]),
              ],
            );
            }(),
          _ => const Padding(
              padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}
