import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/add_item.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';
import '../../core/slots.dart';
import '../../data/db/app_database.dart';
import 'capture_providers.dart';
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
      body: switch (data) {
        AsyncData(:final value) => _AddForm(
            data: value,
            subjectId: subjectId,
            kind: kind,
            startWithSplit: split,
          ),
        AsyncError(:final error) => Center(child: Text('Could not load: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

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
    final d = widget.data;
    final topics = d.topicsBySubject[_subjectId] ?? const [];
    final pdfPicker = ref.watch(pdfPickerProvider);
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
          DropdownButtonFormField<String>(
            key: const Key('add-subject'),
            initialValue: _subjectId,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [
              for (final s in d.subjects) DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() {
              _subjectId = v!;
              _topicId = null;
            }),
          ),
          if (!isTopic && topics.isNotEmpty) ...[
            gap,
            DropdownButtonFormField<String?>(
              initialValue: _topicId,
              decoration: const InputDecoration(labelText: 'Topic (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No topic')),
                for (final t in topics) DropdownMenuItem(value: t.id, child: Text(t.title)),
              ],
              onChanged: (v) => setState(() => _topicId = v),
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
            if (pdfPicker != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(_pickedPdf?.fileName ?? 'Pick from a folder'),
                onPressed: () async {
                  final picked = await pdfPicker(context);
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
