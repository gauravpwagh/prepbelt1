import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/start_session.dart';
import '../../core/providers.dart';
import '../../platform/source_opener.dart';
import 'finish_sheet.dart';
import 'session_providers.dart';

/// Start on a plan row or item: runs the timer and opens the source.
class StartButton extends ConsumerWidget {
  const StartButton({super.key, required this.nodeId});
  final String nodeId;

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(startSessionProvider)(nodeId);
    switch (result) {
      case Started(:final open):
        final note = switch (open) {
          OpenResult.notFound => 'Source not found. Timer started; re-link it from the item.',
          OpenResult.noApp => 'No app can open this source. Timer started.',
          _ => null,
        };
        if (note != null) messenger.showSnackBar(SnackBar(content: Text(note)));
      case AlreadyOpen():
        if (!context.mounted) return;
        final finish = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('A session is running'),
            content: const Text('Finish or discard the running session first.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true), child: const Text('Finish it')),
            ],
          ),
        );
        if (finish == true && context.mounted) await showFinishSheet(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(openSessionProvider).value;
    if (running?.session.nodeId == nodeId) {
      return FilledButton(
        key: Key('finish-$nodeId'),
        onPressed: () => showFinishSheet(context),
        child: const Text('Finish'),
      );
    }
    return FilledButton.tonalIcon(
      key: Key('start-$nodeId'),
      icon: const Icon(Icons.play_arrow),
      label: const Text('Start'),
      onPressed: () => _start(context, ref),
    );
  }
}

/// A card on Today while a session is open.
class SessionBanner extends ConsumerWidget {
  const SessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openSessionProvider).value;
    if (open == null) return const SizedBox.shrink();
    return Card(
      key: const Key('session-banner'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.timer),
        title: Text(open.title),
        subtitle: const Text('Session running'),
        trailing: FilledButton(
          onPressed: () => showFinishSheet(context),
          child: const Text('Finish'),
        ),
      ),
    );
  }
}
