import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/mark_studied.dart';
import '../providers.dart';

/// The pre-filled next part, or null when the item is not an open task
/// split as you go (design §10b).
final nextPartProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, nodeId) => ref.watch(markStudiedProvider).nextPart(nodeId));

/// "What did you cover?" and "That was the last part", shown by the Finish
/// and Mark studied sheets for a task split as you go. Renders nothing for
/// any other item. Reports the part, or null, through [onChanged].
class PartFields extends ConsumerStatefulWidget {
  const PartFields({super.key, required this.nodeId, required this.onChanged});
  final String nodeId;
  final ValueChanged<StudiedPart?> onChanged;

  @override
  ConsumerState<PartFields> createState() => _PartFieldsState();
}

class _PartFieldsState extends ConsumerState<PartFields> {
  TextEditingController? _title;
  var _last = false;

  @override
  void dispose() {
    _title?.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(StudiedPart(_title!.text, last: _last));

  @override
  Widget build(BuildContext context) {
    final next = ref.watch(nextPartProvider(widget.nodeId)).value;
    if (next == null) return const SizedBox.shrink();
    if (_title == null) {
      _title = TextEditingController(text: next);
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          key: const Key('part-title'),
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What did you cover?',
            helperText: 'Saved as a part of this task, at Red',
          ),
          onChanged: (_) => _emit(),
        ),
        CheckboxListTile(
          key: const Key('part-last'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _last,
          title: const Text('That was the last part'),
          onChanged: (v) {
            setState(() => _last = v ?? false);
            _emit();
          },
        ),
      ],
    );
  }
}
