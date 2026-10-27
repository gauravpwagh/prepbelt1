import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/providers.dart';
import 'split_fields.dart';

/// Splits an existing task with no review history (CUJ 2).
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  SplitSpec? _spec;
  var _saving = false;

  Future<void> _save() async {
    final spec = _spec;
    if (spec == null) return;
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = await ref.read(splitItemProvider)(widget.taskId, spec);
      await ref.read(buildTodayPlanProvider).refresh();
      messenger.showSnackBar(SnackBar(content: Text('Created ${ids.length} subtasks')));
      router.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Split into chapters')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Each part becomes an Unread subtask with its own position and '
              'the default base time. Subtasks share the task\'s source.'),
          const SizedBox(height: 16),
          SplitFields(allowNone: false, onChanged: (s) => setState(() => _spec = s)),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('split-save'),
            onPressed: _saving || _spec == null ? null : _save,
            child: const Text('Split'),
          ),
        ]),
      );
}
