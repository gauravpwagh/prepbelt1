import 'package:flutter/material.dart';
import 'package:prep_core/prep_core.dart';

import '../theme/belt_colors.dart';

/// "{label} · {step}/5", or just "Unread".
class BeltChip extends StatelessWidget {
  const BeltChip(this.belt, {super.key, this.dense = false});

  final Belt belt;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bg = beltColor(belt);
    final text = belt == Belt.unread
        ? belt.label
        : '${belt.label} · ${belt.step}/${Belt.topStep}';
    return Semantics(
      label: 'Belt $text',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor(bg))),
      ),
    );
  }
}
