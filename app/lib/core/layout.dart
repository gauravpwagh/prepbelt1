// Adaptive layouts (design D14, §13; plan item 106). The only place that knows
// the breakpoints.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum WindowClass { compact, medium, expanded }

/// Compact below 600 logical pixels, expanded from 840.
WindowClass windowClassOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return WindowClass.compact;
  if (w < 840) return WindowClass.medium;
  return WindowClass.expanded;
}

/// The widest that forms, settings and sheets grow.
const readingWidth = 640.0;

/// Centres [child] at [readingWidth] at most.
class ReadingWidth extends StatelessWidget {
  const ReadingWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: readingWidth),
          child: child,
        ),
      );
}

/// The item shown in the right pane of a two-pane screen, by pane name
/// (`library`, `today`). Null shows the placeholder.
final selectedItemProvider =
    NotifierProvider.family<SelectedItem, String?, String>(SelectedItem.new);

class SelectedItem extends Notifier<String?> {
  SelectedItem(this.pane);
  final String pane;

  @override
  String? build() => null;

  void select(String? nodeId) => state = nodeId;
}

/// Marks the subtree of a two-pane screen: [pane] names its selection, and
/// [embedded] is true inside the right pane.
class ItemPane extends InheritedWidget {
  const ItemPane({super.key, required this.pane, this.embedded = false, required super.child});

  final String pane;
  final bool embedded;

  static ItemPane? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ItemPane>();

  @override
  bool updateShouldNotify(ItemPane old) => pane != old.pane || embedded != old.embedded;
}

/// Opens an item: in the right pane when the screen shows two panes,
/// otherwise as the pushed Item screen.
void openItem(BuildContext context, WidgetRef ref, String nodeId) {
  final pane = ItemPane.of(context);
  if (pane != null && windowClassOf(context) == WindowClass.expanded) {
    ref.read(selectedItemProvider(pane.pane).notifier).select(nodeId);
  } else {
    context.push('/item/$nodeId');
  }
}

/// Whether [nodeId] is the item open in the right pane, for highlighting its
/// row in the list.
bool isOpenInPane(BuildContext context, WidgetRef ref, String nodeId) {
  final pane = ItemPane.of(context);
  if (pane == null || pane.embedded || windowClassOf(context) != WindowClass.expanded) {
    return false;
  }
  return ref.watch(selectedItemProvider(pane.pane)) == nodeId;
}

/// Leaves an item that was deleted: clears the pane or pops the screen.
void closeItem(BuildContext context, WidgetRef ref) {
  final pane = ItemPane.of(context);
  if (pane != null && pane.embedded) {
    ref.read(selectedItemProvider(pane.pane).notifier).select(null);
  } else {
    context.pop();
  }
}
