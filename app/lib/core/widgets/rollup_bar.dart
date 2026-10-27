import 'package:flutter/material.dart';
import 'package:prep_core/prep_core.dart';

import '../theme/belt_colors.dart';

/// A stacked bar of leaf belts, weakest on the left.
class RollupBar extends StatelessWidget {
  const RollupBar(this.rollup, {super.key, this.height = 6});

  final Rollup rollup;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (rollup.total == 0) return SizedBox(height: height);
    final order = [Belt.unread, Belt.red, Belt.orange, Belt.yellow, Belt.lightGreen, Belt.green];
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final b in order)
            if ((rollup.counts[b] ?? 0) > 0)
              Expanded(flex: rollup.counts[b]!, child: ColoredBox(color: beltColor(b))),
        ]),
      ),
    );
  }
}
