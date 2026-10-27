import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../core/widgets/rollup_bar.dart';
import 'library_providers.dart';
import 'widgets/node_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(libraryViewProvider);
    return Scaffold(
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
        if (inbox != null && inbox.roots.isNotEmpty) SubjectSection(inbox, initiallyExpanded: true),
      ],
    );
  }
}

class SubjectSection extends StatelessWidget {
  const SubjectSection(this.subject, {super.key, this.initiallyExpanded = false});

  final LibrarySubject subject;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final r = subject.rollup;
    return ExpansionTile(
      key: PageStorageKey('subject-${subject.subject.id}'),
      initiallyExpanded: initiallyExpanded,
      leading: subject.subject.isInbox ? const Icon(Icons.inbox) : null,
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
