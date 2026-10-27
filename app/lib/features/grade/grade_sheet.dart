import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/grade_review.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/belt_colors.dart';
import '../../core/widgets/belt_chip.dart';

final _previewProvider = FutureProvider.autoDispose
    .family<GradePreview, String>((ref, nodeId) => ref.watch(gradeReviewProvider).preview(nodeId));

/// Forgot / Shaky / Solid, each with its definition and next date (design
/// §10). Returns true when a grade was saved.
Future<bool> showGradeSheet(BuildContext context, String nodeId,
    {int? minutes, String? sessionId}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GradeSheet(nodeId: nodeId, minutes: minutes, sessionId: sessionId),
  );
  return saved ?? false;
}

class GradeSheet extends ConsumerStatefulWidget {
  const GradeSheet({super.key, required this.nodeId, this.minutes, this.sessionId});

  final String nodeId;
  final int? minutes;
  final String? sessionId;

  @override
  ConsumerState<GradeSheet> createState() => _GradeSheetState();
}

class _GradeSheetState extends ConsumerState<GradeSheet> {
  TextEditingController? _minutes;
  var _saving = false;

  @override
  void dispose() {
    _minutes?.dispose();
    super.dispose();
  }

  Future<void> _grade(GradeOption o) async {
    final minutes = int.tryParse(_minutes!.text.trim());
    if (minutes == null || minutes < 0) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final undo = ref.read(undoLatestProvider);
    try {
      await ref.read(gradeReviewProvider)(widget.nodeId, o.grade, minutes,
          sessionId: widget.sessionId);
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
      return;
    }
    navigator.pop(true);
    messenger.showSnackBar(SnackBar(
      content: Text(o.dropNote ?? o.outcome.explanation),
      action: SnackBarAction(
          label: 'Undo', onPressed: () => undo(widget.nodeId)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_previewProvider(widget.nodeId));
    final today = ref.watch(todayProvider);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: switch (preview) {
          AsyncData(:final value) => () {
              _minutes ??= TextEditingController(
                  text: '${widget.minutes ?? value.defaultMinutes}');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text(value.title, style: text.titleLarge)),
                    BeltChip(value.belt),
                  ]),
                  const SizedBox(height: 8),
                  if (value.isPyq)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(pyqGuidance, style: text.bodyMedium),
                    ),
                  TextField(
                    key: const Key('grade-minutes'),
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes', suffixText: 'min'),
                  ),
                  const SizedBox(height: 12),
                  for (final o in value.options.reversed)
                    _GradeButton(
                      option: o,
                      today: today,
                      enabled: !_saving,
                      onTap: () => _grade(o),
                    ),
                ],
              );
            }(),
          AsyncError(:final error) => Text('Could not load: $error'),
          _ => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.option,
    required this.today,
    required this.enabled,
    required this.onTap,
  });

  final GradeOption option;
  final LocalDate today;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final days = today.daysUntil(o.nextDue);
    final text = Theme.of(context).textTheme;
    return Card(
      key: Key('grade-${o.grade.key}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
                width: 6,
                height: 48,
                decoration: BoxDecoration(
                    color: beltColor(o.outcome.beltAfter),
                    borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.grade.label, style: text.titleMedium),
                Text(o.grade.definition, style: text.bodySmall),
                Text(
                  'Next: ${formatShortDate(o.nextDue)} '
                  '(${days == 1 ? 'tomorrow' : 'in $days days'})'
                  '${o.capNote ?? ''}',
                  style: text.bodySmall,
                ),
              ]),
            ),
            BeltChip(o.outcome.beltAfter, dense: true),
          ]),
        ),
      ),
    );
  }
}
