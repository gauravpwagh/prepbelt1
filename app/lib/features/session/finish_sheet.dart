import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/finish_session.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/sheets.dart';

var _showing = false;

/// The Finish sheet over Today (design §6): editable minutes, "Did you
/// finish?" when stale, and Discard. After Confirm, an Unread item gets its
/// first study and any other item opens the grade sheet.
Future<void> showFinishSheet(BuildContext context) async {
  if (_showing) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final open = await container.read(finishSessionProvider).pending();
  if (open == null || !context.mounted) return;

  _showing = true;
  final FinishOutcome? outcome;
  try {
    outcome = await showModalBottomSheet<FinishOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FinishSheet(open: open),
    );
  } finally {
    _showing = false;
  }
  await container.read(reconcileNotificationsProvider)();
  if (outcome == null || !context.mounted) return;

  switch (outcome) {
    case NeedsFirstStudy(:final nodeId, :final minutes, :final sessionId):
      final e = await container.read(markStudiedProvider)(nodeId, minutes, sessionId: sessionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Red · next review ${formatShortDate(e.outcome.ladderDue!)}'),
        ));
      }
    case NeedsGrade(:final nodeId, :final minutes, :final sessionId):
      await container
          .read(appSheetsProvider)
          .grade(context, nodeId, minutes: minutes, sessionId: sessionId);
  }
}

class FinishSheet extends ConsumerStatefulWidget {
  const FinishSheet({super.key, required this.open});
  final OpenSession open;

  @override
  ConsumerState<FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends ConsumerState<FinishSheet> {
  late final _minutes = TextEditingController(text: '${widget.open.prefill}');
  var _busy = false;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final m = int.tryParse(_minutes.text.trim());
    if (m == null || m < 0) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final outcome = await ref.read(finishSessionProvider).confirm(widget.open, m);
    navigator.pop(outcome);
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await ref.read(discardSessionProvider)(widget.open.session.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.open;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(o.title, style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              o.stale
                  ? 'Did you finish? This session started ${formatMinutes(o.elapsedMinutes)} ago.'
                  : 'Studied ${formatMinutes(o.elapsedMinutes)}',
              key: const Key('finish-elapsed'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('finish-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes studied', suffixText: 'min'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('finish-confirm'),
              onPressed: _busy ? null : _confirm,
              child: Text(o.unread ? 'Save first reading' : 'Next: grade it'),
            ),
            TextButton(
              key: const Key('finish-discard'),
              onPressed: _busy ? null : _discard,
              child: const Text('Discard session'),
            ),
          ],
        ),
      ),
    );
  }
}
