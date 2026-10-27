import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../../core/labels.dart';
import '../../../core/slots.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/converters.dart';

/// The item's source: type, link or file, location note and status. Open
/// and Re-link come from [sourceActionsProvider] once folder access exists.
class SourceCard extends ConsumerWidget {
  const SourceCard({super.key, required this.source, required this.owner});

  final SourceRow source;
  final NodeRow owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = source;
    final text = Theme.of(context).textTheme;
    final actions = ref.watch(sourceActionsProvider);
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
          if (actions != null) actions(context, owner.id),
        ]),
      ),
    );
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
