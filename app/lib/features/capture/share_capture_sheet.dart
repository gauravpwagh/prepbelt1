import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/capture_shared.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';
import '../../core/widgets/new_subject_dialog.dart';
import '../../data/db/app_database.dart';
import '../../platform/share_receiver.dart';

/// The Share capture sheet (design §7, CUJ 2b/2c): one card per draft with
/// an editable title and source preview, subject chips (Inbox first, then
/// the last-used subject and the rest), and one-tap Save.
Future<void> showShareCaptureSheet(BuildContext context, IncomingShare share) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShareCaptureSheet(share: share),
  );
  // Dismissed without saving: the cache copies still go.
  if (saved != true) await share.discardFiles();
  await container.read(buildTodayPlanProvider).refresh();
}

final _subjectsProvider = FutureProvider.autoDispose<(List<SubjectRow>, String?)>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final inbox = await db.subjectsDao.ensureInbox(
      newId: ref.read(idGeneratorProvider), now: ref.read(clockProvider).nowUtc());
  final last = await db.subjectsDao.byId(await db.settingsDao.lastUsedSubjectId() ?? '');
  final rest = [
    for (final s in await db.subjectsDao.all())
      if (!s.isInbox && s.id != last?.id) s,
  ];
  return ([inbox, if (last != null && !last.isInbox) last, ...rest], inbox.id);
});

class ShareCaptureSheet extends ConsumerStatefulWidget {
  const ShareCaptureSheet({super.key, required this.share});
  final IncomingShare share;

  @override
  ConsumerState<ShareCaptureSheet> createState() => _ShareCaptureSheetState();
}

class _ShareCaptureSheetState extends ConsumerState<ShareCaptureSheet> {
  late final List<CaptureDraft> _drafts = ref.read(captureSharedProvider).drafts(widget.share);
  String? _subjectId;
  var _saving = false;

  /// Subjects created from this sheet.
  final _newSubjects = <SubjectRow>[];

  Future<void> _newSubject() async {
    final s = await showNewSubjectDialog(context);
    if (s == null || !mounted) return;
    setState(() {
      _newSubjects.add(s);
      _subjectId = s.id;
    });
  }

  Future<void> _save(String inboxId) async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = await ref
          .read(captureSharedProvider)
          .save(widget.share, _drafts, subjectId: _subjectId ?? inboxId);
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
          content: Text(ids.length == 1 ? 'Saved as Planned' : 'Saved ${ids.length} items')));
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(_subjectsProvider);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: switch (subjects) {
          AsyncData(value: (final list, final inboxId)) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add to PrepBelt', style: text.titleLarge),
                  const SizedBox(height: 8),
                  for (final (i, d) in _drafts.indexed)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          TextFormField(
                            key: Key('share-title-$i'),
                            initialValue: d.title,
                            decoration: const InputDecoration(labelText: 'Title'),
                            onChanged: (v) => d.title = v,
                          ),
                          const SizedBox(height: 8),
                          Text(sourceTypeLabel(d.draft.type), style: text.labelLarge),
                          if (d.draft.url != null)
                            Text(d.draft.url!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (d.draft.file != null)
                            Text(d.draft.file!.name ?? 'Unnamed PDF', style: text.bodySmall),
                          if (d.draft.excerpt != null && d.draft.url == null)
                            Text(d.draft.excerpt!, maxLines: 3, overflow: TextOverflow.ellipsis,
                                style: text.bodySmall),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final s in [...list, ..._newSubjects])
                      ChoiceChip(
                        key: Key('share-subject-${s.id}'),
                        label: Text(s.name),
                        selected: (_subjectId ?? inboxId) == s.id,
                        onSelected: (_) => setState(() => _subjectId = s.id),
                      ),
                    ActionChip(
                      key: const Key('share-new-subject'),
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                      onPressed: _newSubject,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('share-save'),
                    onPressed: _saving || _drafts.isEmpty ? null : () => _save(inboxId!),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          AsyncError(:final error) => Text('Could not load: $error'),
          _ => const Padding(
              padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}
