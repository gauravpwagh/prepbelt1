import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../../core/layout.dart';
import '../../../core/widgets/belt_chip.dart';
import '../../../core/widgets/rollup_bar.dart';
import '../library_providers.dart';

/// A topic, task or subtask, with its belt (leaf) or rollup (parent).
class NodeTile extends ConsumerWidget {
  const NodeTile(this.item, {super.key, required this.depth});

  final LibraryNode item;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = item.node;
    final indent = 16.0 + 20.0 * depth;
    final asIGo = n.splitAsIGo == SplitAsIGo.open;
    final tile = ListTile(
      key: Key('node-${n.id}'),
      selected: isOpenInPane(context, ref, n.id),
      contentPadding: EdgeInsets.only(left: indent, right: 16),
      leading: Icon(switch (n.kind) {
        NodeKind.topic => Icons.folder_outlined,
        NodeKind.task => item.isLeaf ? Icons.description_outlined : Icons.library_books_outlined,
        NodeKind.subtask => Icons.subdirectory_arrow_right,
      }),
      title: Text(n.title),
      subtitle: item.isLeaf
          ? (asIGo ? const Text('Split as I go · no parts yet') : null)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([
                if (asIGo) 'Split as I go',
                item.rollup.total == 0 ? 'Empty' : rollupLabel(item.rollup),
              ].join(' · ')),
              const SizedBox(height: 4),
              RollupBar(item.rollup, height: 4),
            ]),
      trailing: item.isLeaf ? BeltChip(item.state!.belt, dense: true) : null,
      onTap: () => openItem(context, ref, n.id),
    );
    if (item.children.isEmpty) return tile;
    return Column(children: [
      tile,
      for (final c in item.children) NodeTile(c, depth: depth + 1),
    ]);
  }
}
