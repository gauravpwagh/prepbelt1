import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../layout.dart';
import '../slots.dart';

/// A list with the selected item beside it (design D14, plan item 108).
///
/// Expanded windows show [list] on the left and the item selected in [pane]
/// on the right. Other windows show only [list], and opening an item pushes
/// the Item screen. When an expanded window shrinks with an item selected,
/// that item is pushed so it stays open.
class TwoPane extends ConsumerWidget {
  const TwoPane({super.key, required this.pane, required this.list, required this.placeholder});

  final String pane;
  final Widget list;

  /// Shown on the right when nothing is selected.
  final String placeholder;

  static const listWidth = 400.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedItemProvider(pane));
    final detail = ref.watch(itemDetailProvider);
    final expanded = windowClassOf(context) == WindowClass.expanded;

    if (!expanded || detail == null) {
      if (selected != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref.read(selectedItemProvider(pane).notifier).select(null);
          context.push('/item/$selected');
        });
      }
      return ItemPane(pane: pane, child: list);
    }

    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      SizedBox(width: listWidth, child: ItemPane(pane: pane, child: list)),
      const VerticalDivider(width: 1),
      Expanded(
        child: selected == null
            ? ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Center(
                  key: Key('$pane-placeholder'),
                  child: Text(placeholder,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              )
            : ItemPane(
                pane: pane,
                embedded: true,
                child: KeyedSubtree(key: Key('$pane-detail-$selected'), child: detail(selected)),
              ),
      ),
    ]);
  }
}
