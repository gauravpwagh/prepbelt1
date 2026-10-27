import 'package:flutter/material.dart';
import 'package:prep_core/prep_core.dart';

enum SplitMode { none, chapters, pages, custom, asIGo }

/// The split tool: chapters from–to, page chunks, or custom titles.
class SplitFields extends StatefulWidget {
  const SplitFields(
      {super.key, required this.onChanged, this.allowNone = true, this.onAsIGo});

  /// Called with the current spec, or null for "don't split" / invalid input.
  final ValueChanged<SplitSpec?> onChanged;
  final bool allowNone;

  /// When set, offers "As I go" (design §10b) and reports whether it is
  /// chosen; the spec is then null.
  final ValueChanged<bool>? onAsIGo;

  @override
  State<SplitFields> createState() => _SplitFieldsState();
}

class _SplitFieldsState extends State<SplitFields> {
  late SplitMode _mode = widget.allowNone ? SplitMode.none : SplitMode.chapters;
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '12');
  final _size = TextEditingController(text: '20');
  final _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _size, _custom]) {
      c.dispose();
    }
    super.dispose();
  }

  SplitSpec? get spec {
    int? n(TextEditingController c) => int.tryParse(c.text.trim());
    final from = n(_from), to = n(_to), size = n(_size);
    final spec = switch (_mode) {
      SplitMode.none || SplitMode.asIGo => null,
      SplitMode.chapters when from != null && to != null => Chapters(from, to),
      SplitMode.pages when from != null && to != null && size != null =>
        PageChunks(from, to, size),
      SplitMode.custom => Custom(_custom.text.split('\n')),
      _ => null,
    };
    if (spec == null) return null;
    try {
      split(spec);
      return spec;
    } on ArgumentError {
      return null;
    }
  }

  void _emit() {
    widget.onAsIGo?.call(_mode == SplitMode.asIGo);
    widget.onChanged(spec);
  }

  @override
  Widget build(BuildContext context) {
    final preview = spec == null ? null : split(spec!);
    Widget number(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
            onChanged: (_) => setState(_emit),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<SplitMode>(
        segments: [
          if (widget.allowNone) const ButtonSegment(value: SplitMode.none, label: Text('No split')),
          const ButtonSegment(value: SplitMode.chapters, label: Text('Chapters')),
          const ButtonSegment(value: SplitMode.pages, label: Text('Pages')),
          const ButtonSegment(value: SplitMode.custom, label: Text('Custom')),
          if (widget.onAsIGo != null)
            const ButtonSegment(
                value: SplitMode.asIGo, label: Text('As I go', key: Key('split-as-i-go'))),
        ],
        showSelectedIcon: widget.onAsIGo == null,
        selected: {_mode},
        onSelectionChanged: (s) => setState(() {
          _mode = s.single;
          _emit();
        }),
      ),
      const SizedBox(height: 8),
      if (_mode == SplitMode.chapters || _mode == SplitMode.pages)
        Row(children: [
          number(_from, _mode == SplitMode.chapters ? 'From chapter' : 'From page'),
          const SizedBox(width: 8),
          number(_to, _mode == SplitMode.chapters ? 'To chapter' : 'To page'),
          if (_mode == SplitMode.pages) ...[
            const SizedBox(width: 8),
            number(_size, 'Pages each'),
          ],
        ]),
      if (_mode == SplitMode.custom)
        TextField(
          controller: _custom,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'One title per line'),
          onChanged: (_) => setState(_emit),
        ),
      if (_mode == SplitMode.asIGo)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Name each part as you study it. The Finish and Mark studied '
              'sheets ask what you covered, and each part becomes a subtask at Red.'),
        ),
      if (_mode != SplitMode.none && _mode != SplitMode.asIGo)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            preview == null
                ? 'Check the numbers'
                : '${preview.length} subtasks: ${preview.take(4).map((p) => p.title).join(', ')}'
                    '${preview.length > 4 ? ' …' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ]);
  }
}
