import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/catch_up.dart';
import '../../../core/db_watch.dart';
import '../../../core/providers.dart';
import '../../../data/db/converters.dart';

final _offerProvider = StreamProvider.autoDispose<CatchUpOffer?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final catchUp = ref.watch(catchUpProvider);
  ref.watch(todayProvider);
  return watchTables(db, {db.dayPlans}, catchUp.offer);
});

final _acceptedProvider = StreamProvider.autoDispose<bool>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = ref.watch(todayProvider);
  return watchTables(db, {db.dayPlans}, () async =>
      (await db.plansDao.planFor(today))?.header.catchUpState == CatchUpState.accepted);
});

/// CUJ 5: "Spread 18 overdue reviews over the next 6 days?", or "Undo
/// catch-up" on the day it was accepted.
class CatchUpCard extends ConsumerWidget {
  const CatchUpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catchUp = ref.read(catchUpProvider);
    if (ref.watch(_acceptedProvider).value ?? false) {
      return Card(
        key: const Key('catch-up-undo'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.event_repeat),
          title: const Text('Catch-up applied'),
          trailing: TextButton(onPressed: catchUp.undo, child: const Text('Undo catch-up')),
        ),
      );
    }
    final offer = ref.watch(_offerProvider).value;
    if (offer == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Card(
      key: const Key('catch-up-offer'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            offer.count == 0
                ? 'Some reviews can\'t fit before your exam'
                : 'Spread ${offer.count} overdue ${offer.count == 1 ? 'review' : 'reviews'} '
                    'over the next ${offer.proposal.days} days?',
            style: text.titleMedium,
          ),
          for (final line in offer.wontFitLines)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(line, style: text.bodySmall)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: catchUp.decline, child: const Text('Not today')),
            if (offer.count > 0)
              FilledButton(
                key: const Key('catch-up-accept'),
                onPressed: () => catchUp.accept(offer),
                child: const Text('Spread them'),
              ),
          ]),
        ]),
      ),
    );
  }
}
