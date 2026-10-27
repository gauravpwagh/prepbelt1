import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/add_item.dart';
import '../../core/labels.dart';
import '../../core/layout.dart';
import '../../core/providers.dart';
import '../../core/widgets/new_subject_dialog.dart';
import '../../data/db/app_database.dart';
import 'capture_providers.dart';
import 'source_picker_sheet.dart';
import 'split_fields.dart';

/// The full Add form (design §10): title, subject and topic (last used
/// preselected), kind, base time, optional source, and the split tool.
class AddItemScreen extends ConsumerWidget {
  const AddItemScreen({
    super.key,
    this.subjectId,
    this.parentId,
    this.kind,
    this.split = false,
  });

  final String? subjectId;
  final String? parentId;
  final NodeKind? kind;
  final bool split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(addFormDataProvider(parentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Add')),
      body: ReadingWidth(child: switch (data) {
        AsyncData(:final value) => _AddForm(
            data: value,
            subjectId: subjectId,
            kind: kind,
            startWithSplit: split,
          ),
        AsyncError(:final error) => Center(child: Text('Could not load: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      }),
    );
  }
}

/// The menu value of "+ New subject…" and "+ New topic…".
const _newValue = '__new__';

const _urlTypes = {SourceType.web, SourceType.aiChat, SourceType.video, SourceType.app};

class _AddForm extends ConsumerStatefulWidget {
  const _AddForm({required this.data, this.subjectId, this.kind, this.startWithSplit = false});

  final AddFormData data;
  final String? subjectId;
  final NodeKind? kind;
  final bool startWithSplit;

  @override
  ConsumerState<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends ConsumerState<_AddForm> {
  final _title = TextEditingController();
  final _position = TextEditingController();
  final _url = TextEditingController();
  final _note = TextEditingController();
  final _excerpt = TextEditingController();

  late String _subjectId;
  String? _topicId;
  late NodeKind _kind;
  var _taskKind = TaskKind.reading;
  int? _base;
  SourceType? _sourceType;
  NewSource? _pickedPdf;
  SplitSpec? _split;
  var _saving = false;

  // Subjects and topics created from this form (design §10a).
  final _newSubjects = <SubjectRow>[];
  final _newTopics = <String, List<NodeRow>>{};

  List<SubjectRow> get _subjects => [...widget.data.subjects, ..._newSubjects];
  List<NodeRow> _topicsOf(String subjectId) => [
        ...widget.data.topicsBySubject[subjectId] ?? const <NodeRow>[],
        ..._newTopics[subjectId] ?? const <NodeRow>[],
      ];

  // Bumped after the "+ New" dialogs so the menus rebuild, showing the real
  // selection rather than "+ New…" when the dialog is cancelled.
  var _menus = 0;

  Future<void> _newSubject() async {
    final s = await showNewSubjectDialog(context);
    if (!mounted) return;
    setState(() => _menus++);
    if (s == null) return;
    setState(() {
      _newSubjects.add(s);
      _subjectId = s.id;
      _topicId = null;
    });
  }

  Future<void> _newTopic() async {
    final name = await showNameDialog(context,
        title: 'New topic', label: 'Topic name', action: 'Create');
    if (!mounted) return;
    setState(() => _menus++);
    if (name == null) return;
    final db = ref.read(appDatabaseProvider);
    final id = await ref
        .read(addItemProvider)(AddItemRequest(title: name, kind: NodeKind.topic, subjectId: _subjectId));
    final topic = await db.nodesDao.byId(id);
    if (topic == null || !mounted) return;
    setState(() {
      (_newTopics[_subjectId] ??= []).add(topic);
      _topicId = id;
    });
  }

  NodeRow? get _parent => widget.data.parent;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    final inbox = d.subjects.firstWhere((s) => s.isInbox);
    bool known(String? id) => id != null && d.subjects.any((s) => s.id == id);
    _subjectId = _parent?.subjectId ??
        (known(widget.subjectId)
            ? widget.subjectId!
            : known(d.lastSubjectId)
                ? d.lastSubjectId!
                : inbox.id);
    if (_parent == null &&
        (d.topicsBySubject[_subjectId] ?? const []).any((t) => t.id == d.lastTopicId)) {
      _topicId = d.lastTopicId;
    }
    _kind = widget.kind ??
        switch (_parent?.kind) {
          NodeKind.task => NodeKind.subtask,
          _ => NodeKind.task,
        };
    if (_parent?.taskKind != null) _taskKind = _parent!.taskKind!;
  }

  @override
  void dispose() {
    for (final c in [_title, _position, _url, _note, _excerpt]) {
      c.dispose();
    }
    super.dispose();
  }

  NewSource? get _source {
    final t = _sourceType;
    if (t == null || _kind != NodeKind.task) return null;
    if (t == SourceType.pdf && _pickedPdf != null) {
      return NewSource(
        type: t,
        folderId: _pickedPdf!.folderId,
        relativePath: _pickedPdf!.relativePath,
        fileName: _pickedPdf!.fileName,
        fileSize: _pickedPdf!.fileSize,
        locationNote: _note.text,
      );
    }
    return NewSource(
      type: t,
      url: _urlTypes.contains(t) ? _url.text : null,
      fileName: t == SourceType.pdf ? _url.text : null,
      locationNote: _note.text,
      excerpt: _excerpt.text,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a title')));
      return;
    }
    setState(() => _saving = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(addItemProvider)(AddItemRequest(
        title: _title.text,
        kind: _kind,
        subjectId: _subjectId,
        parentId: _parent?.id ?? (_kind == NodeKind.topic ? null : _topicId),
        taskKind: _taskKind,
        baseMinutes: _kind == NodeKind.topic ? null : _base,
        positionText: _position.text,
        source: _source,
      ));
      if (_split != null && _kind == NodeKind.task) {
        await ref.read(splitItemProvider)(id, _split!);
      }
      await ref.read(buildTodayPlanProvider).refresh();
      messenger.showSnackBar(SnackBar(content: Text('Added "${_title.text.trim()}"')));
      router.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _topicsOf(_subjectId);
    final isTopic = _kind == NodeKind.topic;
    final base = _base ?? _taskKind.defaultBaseMinutes;
    const gap = SizedBox(height: 12);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_parent != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Under "${_parent!.title}"',
                style: Theme.of(context).textTheme.titleSmall),
          ),
        if (_parent == null)
          SegmentedButton<NodeKind>(
            segments: const [
              ButtonSegment(value: NodeKind.task, label: Text('Task')),
              ButtonSegment(value: NodeKind.topic, label: Text('Topic')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.single),
          ),
        gap,
        TextField(
          key: const Key('add-title'),
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: isTopic ? 'Topic name' : 'Title (e.g. "Laxmikant Polity")'),
        ),
        if (_parent == null) ...[
          gap,
          // Keyed by the selection so that a subject or topic created from
          // the menu shows as selected.
          KeyedSubtree(
            key: ValueKey('subject-$_subjectId-$_menus'),
            child: DropdownButtonFormField<String>(
              key: const Key('add-subject'),
              initialValue: _subjectId,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in _subjects) DropdownMenuItem(value: s.id, child: Text(s.name)),
                const DropdownMenuItem(
                  key: Key('add-new-subject'),
                  value: _newValue,
                  child: Text('+ New subject…'),
                ),
              ],
              onChanged: (v) => v == _newValue
                  ? _newSubject()
                  : setState(() {
                      _subjectId = v!;
                      _topicId = null;
                    }),
            ),
          ),
          if (!isTopic) ...[
            gap,
            KeyedSubtree(
              key: ValueKey('topic-$_subjectId-$_topicId-$_menus'),
              child: DropdownButtonFormField<String?>(
                key: const Key('add-topic'),
                initialValue: _topicId,
                decoration: const InputDecoration(labelText: 'Topic (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No topic')),
                  for (final t in topics) DropdownMenuItem(value: t.id, child: Text(t.title)),
                  const DropdownMenuItem(
                    key: Key('add-new-topic'),
                    value: _newValue,
                    child: Text('+ New topic…'),
                  ),
                ],
                onChanged: (v) => v == _newValue ? _newTopic() : setState(() => _topicId = v),
              ),
            ),
          ],
        ],
        if (!isTopic) ...[
          gap,
          SegmentedButton<TaskKind>(
            segments: [
              for (final k in TaskKind.values)
                ButtonSegment(value: k, label: Text(taskKindLabel(k))),
            ],
            selected: {_taskKind},
            onSelectionChanged: (s) => setState(() => _taskKind = s.single),
          ),
          gap,
          Text('Base time: $base min'),
          Slider(
            value: base.toDouble(),
            min: Defaults.baseMin.toDouble(),
            max: Defaults.baseMax.toDouble(),
            divisions: (Defaults.baseMax - Defaults.baseMin) ~/ 5,
            label: '$base min',
            onChanged: (v) => setState(() => _base = v.round()),
          ),
          TextField(
            controller: _position,
            decoration: const InputDecoration(labelText: 'Position (e.g. "Ch 3 · pp. 40–62")'),
          ),
        ],
        if (_kind == NodeKind.task) ...[
          gap,
          DropdownButtonFormField<SourceType?>(
            key: const Key('add-source-type'),
            initialValue: _sourceType,
            decoration: const InputDecoration(labelText: 'Source (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final t in SourceType.values)
                DropdownMenuItem(value: t, child: Text(sourceTypeLabel(t))),
            ],
            onChanged: (v) => setState(() => _sourceType = v),
          ),
          if (_urlTypes.contains(_sourceType)) ...[
            gap,
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link'),
            ),
          ],
          if (_sourceType == SourceType.pdf) ...[
            gap,
            OutlinedButton.icon(
              key: const Key('add-pick-pdf'),
              icon: const Icon(Icons.folder_open),
              label: Text(_pickedPdf?.fileName ?? 'Pick from a folder'),
              onPressed: () async {
                final picked = await pickPdfSource(context, ref);
                if (picked != null) setState(() => _pickedPdf = picked);
              },
            ),
            if (_pickedPdf == null)
              TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'File name (link it later)'),
              ),
          ],
          if (_sourceType != null) ...[
            gap,
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: 'Where it is (optional, e.g. "Printed copy, shelf 2")'),
            ),
          ],
          if (_sourceType == SourceType.notes || _sourceType == SourceType.aiChat) ...[
            gap,
            TextField(
              controller: _excerpt,
              minLines: 2,
              maxLines: 6,
              maxLength: Defaults.excerptMaxChars,
              decoration: const InputDecoration(labelText: 'Excerpt (optional)'),
            ),
          ],
          gap,
          ExpansionTile(
            initiallyExpanded: widget.startWithSplit,
            tilePadding: EdgeInsets.zero,
            title: const Text('Split into chapters'),
            children: [SplitFields(onChanged: (s) => _split = s)],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('add-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save as Planned'),
        ),
      ],
    );
  }
}
