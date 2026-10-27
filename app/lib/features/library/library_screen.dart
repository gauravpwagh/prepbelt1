import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/providers.dart';
import '../../core/widgets/new_subject_dialog.dart';
import '../../core/widgets/rollup_bar.dart';
import '../../core/widgets/two_pane.dart';
import 'library_providers.dart';
import 'widgets/node_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(libraryViewProvider);
    return TwoPane(
      pane: 'library',
      placeholder: 'Choose an item to see it here',
      list: Scaffold(
        appBar: AppBar(title: const Text('Library')),
        floatingActionButton: FloatingActionButton(
          heroTag: 'fab-library',
          tooltip: 'Add',
          onPressed: () => context.push('/add'),
          child: const Icon(Icons.add),
        ),
        body: switch (view) {
          AsyncData(:final value) => _LibraryBody(value),
          AsyncError(:final error) => Center(child: Text('Could not load: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody(this.view);
  final LibraryView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.read(libraryExamFilterProvider.notifier);
    final inbox = view.inbox;
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (view.exams.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: view.examFilter == null,
                  onSelected: (_) => filter.set(null),
                ),
              ),
              for (final e in view.exams)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.archivedAt == null ? e.name : '${e.name} (archived)'),
                    selected: view.examFilter == e.id,
                    onSelected: (_) => filter.set(e.id),
                  ),
                ),
            ]),
          ),
        if (view.subjects.isEmpty && (inbox == null || inbox.roots.isEmpty))
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No items yet. Tap + to add one.')),
          ),
        for (final s in view.subjects) SubjectSection(s),
        ListTile(
          key: const Key('library-new-subject'),
          leading: const Icon(Icons.add),
          title: const Text('New subject'),
          onTap: () => showNewSubjectDialog(context),
        ),
        if (inbox != null && inbox.roots.isNotEmpty) SubjectSection(inbox, initiallyExpanded: true),
      ],
    );
  }
}

class SubjectSection extends ConsumerWidget {
  const SubjectSection(this.subject, {super.key, this.initiallyExpanded = false});

  final LibrarySubject subject;
  final bool initiallyExpanded;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showNameDialog(context,
        title: 'Rename subject', label: 'Subject name', initial: subject.subject.name);
    if (name == null) return;
    await ref.read(saveExamProvider).renameSubject(subject.subject.id, name);
  }

  /// Asks what happens to the items (design §10a), with no default.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final s = subject.subject;
    final empty = subject.roots.isEmpty;
    final keep = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${s.name}"?'),
        content: Text(empty
            ? 'The subject has no items. Its exam links are removed.'
            : 'Move its items to the Inbox, or delete them too? Exam links are removed '
                'either way.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          if (!empty)
            TextButton(
              key: const Key('subject-delete-items'),
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Delete items too'),
            ),
          FilledButton(
            key: const Key('subject-delete-keep'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(empty ? 'Delete' : 'Move items to Inbox'),
          ),
        ],
      ),
    );
    if (keep == null) return;
    final plan = ref.read(buildTodayPlanProvider);
    await ref.read(saveExamProvider).deleteSubject(s.id, keepItems: keep);
    await plan.refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = subject.rollup;
    final inbox = subject.subject.isInbox;
    return ExpansionTile(
      key: PageStorageKey('subject-${subject.subject.id}'),
      initiallyExpanded: initiallyExpanded,
      leading: inbox ? const Icon(Icons.inbox) : null,
      controlAffinity: inbox ? null : ListTileControlAffinity.leading,
      trailing: inbox
          ? null
          : PopupMenuButton<String>(
              key: Key('subject-menu-${subject.subject.id}'),
              onSelected: (a) => switch (a) {
                'rename' => _rename(context, ref),
                'delete' => _delete(context, ref),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete subject')),
              ],
            ),
      title: Text(subject.subject.name),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.total == 0 ? 'No items' : rollupLabel(r)),
        const SizedBox(height: 4),
        RollupBar(r),
      ]),
      children: [
        for (final n in subject.roots) NodeTile(n, depth: 0),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: const Text('Add here'),
          onTap: () => context.push('/add?subject=${subject.subject.id}'),
        ),
      ],
    );
  }
}
