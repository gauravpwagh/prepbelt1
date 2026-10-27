import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/layout.dart';
import '../../core/providers.dart';
import 'split_fields.dart';

final _asIGoAllowedProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, id) => ref.watch(splitItemProvider).asIGoAllowed(id));

/// Splits an existing task with no review history (CUJ 2), or turns it into
/// one split as you go (design §10b).
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  SplitSpec? _spec;
  var _asIGo = false;
  var _saving = false;

  Future<void> _save() async {
    final spec = _spec;
    if (spec == null && !_asIGo) return;
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final split = ref.read(splitItemProvider);
      final String done;
      if (_asIGo) {
        await split.asIGo(widget.taskId);
        done = 'Split as I go: name each part as you study it';
      } else {
        done = 'Created ${(await split(widget.taskId, spec!)).length} subtasks';
      }
      await ref.read(buildTodayPlanProvider).refresh();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      router.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asIGoAllowed = ref.watch(_asIGoAllowedProvider(widget.taskId)).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Split into parts')),
      body: ReadingWidth(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Each part becomes an Unread subtask with its own position and '
            'the default base time. Subtasks share the task\'s source.'),
        const SizedBox(height: 16),
        SplitFields(
          key: ValueKey(asIGoAllowed),
          allowNone: false,
          onChanged: (s) => setState(() => _spec = s),
          onAsIGo: asIGoAllowed ? (v) => setState(() => _asIGo = v) : null,
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('split-save'),
          onPressed: _saving || (_spec == null && !_asIGo) ? null : _save,
          child: const Text('Split'),
        ),
      ])),
    );
  }
}
