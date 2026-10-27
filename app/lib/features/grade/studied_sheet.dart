import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../application/mark_studied.dart';
import '../../core/providers.dart';
import '../../core/widgets/part_fields.dart';

final _defaultMinutesProvider = FutureProvider.autoDispose
    .family<int, String>((ref, nodeId) => ref.watch(markStudiedProvider).defaultMinutes(nodeId));

/// Confirms the minutes of a first reading, then writes it. Returns true
/// when saved.
Future<bool> showStudiedSheet(BuildContext context, String nodeId,
    {int? minutes, String? sessionId}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => StudiedSheet(nodeId: nodeId, minutes: minutes, sessionId: sessionId),
  );
  return saved ?? false;
}

class StudiedSheet extends ConsumerStatefulWidget {
  const StudiedSheet({super.key, required this.nodeId, this.minutes, this.sessionId});

  final String nodeId;
  final int? minutes;
  final String? sessionId;

  @override
  ConsumerState<StudiedSheet> createState() => _StudiedSheetState();
}

class _StudiedSheetState extends ConsumerState<StudiedSheet> {
  TextEditingController? _minutes;
  StudiedPart? _part;
  var _saving = false;

  @override
  void dispose() {
    _minutes?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes!.text.trim());
    if (minutes == null || minutes < 0) return;
    if (_part != null && _part!.title.trim().isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final undo = ref.read(undoLatestProvider);
    try {
      final e = await ref.read(markStudiedProvider)(widget.nodeId, minutes,
          sessionId: widget.sessionId, part: _part);
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text('Red · next review ${formatShortDate(e.outcome.ladderDue!)}'),
        action: SnackBarAction(
            label: 'Undo', onPressed: () => undo(e.nodeId)),
      ));
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaults = ref.watch(_defaultMinutesProvider(widget.nodeId));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: switch (defaults) {
          AsyncData(:final value) => () {
              _minutes ??= TextEditingController(text: '${widget.minutes ?? value}');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Mark as studied', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('First reading → Red. Next review tomorrow.'),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('studied-minutes'),
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes', suffixText: 'min'),
                  ),
                  PartFields(nodeId: widget.nodeId, onChanged: (p) => _part = p),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('studied-save'),
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              );
            }(),
          AsyncError(:final error) => Text('Could not load: $error'),
          _ => const Padding(
              padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}
