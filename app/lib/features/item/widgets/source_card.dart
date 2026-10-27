import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../../core/labels.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/folder_chooser.dart';
import '../../../platform/source_opener.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/converters.dart';

/// The item's source: type, link or file, location note and status, with
/// Open and Re-link (design §10).
class SourceCard extends ConsumerWidget {
  const SourceCard({super.key, required this.source, required this.owner});

  final SourceRow source;
  final NodeRow owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = source;
    final text = Theme.of(context).textTheme;
    final detail = s.url ?? s.fileName ?? s.locationNote;
    return Card(
      key: const Key('source-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_icon(s.sourceType)),
            const SizedBox(width: 8),
            Expanded(child: Text(sourceTypeLabel(s.sourceType), style: text.titleSmall)),
            if (s.linkStatus == LinkStatus.needsRelink)
              const Chip(label: Text('Needs re-link'))
            else if (s.linkStatus == LinkStatus.notLinked && s.sourceType == SourceType.pdf)
              const Chip(label: Text('Not linked')),
          ]),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (s.locationNote != null && detail != s.locationNote) ...[
            const SizedBox(height: 4),
            Text(s.locationNote!, style: text.bodySmall),
          ],
          if (s.excerpt != null) ...[
            const SizedBox(height: 4),
            Text(s.excerpt!, maxLines: 4, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (s.url != null || s.relativePath != null)
              FilledButton.tonalIcon(
                key: const Key('source-open'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
                onPressed: () => _open(context, ref),
              ),
            if (s.sourceType == SourceType.pdf)
              OutlinedButton.icon(
                key: const Key('source-relink'),
                icon: const Icon(Icons.link),
                label: const Text('Re-link'),
                onPressed: () => relinkByFolder(context, ref),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await ref.read(sourceOpenerProvider).open(source);
    switch (r) {
      case OpenResult.ok:
        break;
      case OpenResult.notFound:
        await ref
            .read(appDatabaseProvider)
            .sourcesDao
            .setLinkStatus(source.nodeId, LinkStatus.needsRelink);
        messenger.showSnackBar(const SnackBar(content: Text('File not found. Re-link it.')));
      case OpenResult.noApp:
        messenger.showSnackBar(const SnackBar(content: Text('No app can open this source.')));
    }
  }
}

IconData _icon(SourceType t) => switch (t) {
      SourceType.pdf => Icons.picture_as_pdf_outlined,
      SourceType.book => Icons.menu_book_outlined,
      SourceType.web => Icons.public,
      SourceType.aiChat => Icons.chat_outlined,
      SourceType.video => Icons.ondemand_video,
      SourceType.notes => Icons.sticky_note_2_outlined,
      SourceType.lecture => Icons.school_outlined,
      SourceType.app => Icons.apps,
      SourceType.otherDevice => Icons.devices_other,
    };
