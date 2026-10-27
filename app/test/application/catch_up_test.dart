import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';

import 'app_helpers.dart';

void main() {
  late Fixture f;
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    f = Fixture();
    db = f.db;
    c = containerFor(f);
    await f.subject('s', name: 'Polity');
    // Eight items studied on day 0, then the user misses five days.
    for (var i = 0; i < 8; i++) {
      await f.node('n$i', 's', NodeKind.task, order: i, base: 50);
      await f.writer.writeFirstStudy('n$i', 50);
    }
    await db.settingsDao.setDailyMinutes(30);
    f.clock.advance(const Duration(days: 6));
    c.invalidate(todayProvider);
  });
  tearDown(() async {
    c.dispose();
    await f.close();
  });

  test('CUJ 5: offer, accept with belts unchanged, then undo', () async {
    final plan = await c.read(buildTodayPlanProvider).get();
    expect(plan.header.waitingCount, greaterThan(0));

    final catchUp = c.read(catchUpProvider);
    final offer = (await catchUp.offer())!;
    expect(offer.count, plan.header.waitingCount);
    expect(offer.proposal.days, greaterThan(1));
    final today = c.read(todayProvider);
    expect((await db.plansDao.planFor(today))!.header.catchUpState, CatchUpState.offered);

    final batch = await catchUp.accept(offer);
    final header = (await db.plansDao.planFor(today))!.header;
    expect([header.catchUpState, header.catchUpBatchId], [CatchUpState.accepted, batch]);
    expect(header.waitingCount, 0);
    final moved = await db.eventsDao.byBatch(batch);
    expect(moved, hasLength(offer.count));
    for (final e in moved) {
      expect(e.outcome!.beltAfter, Belt.red);
      expect(e.outcome!.ladderDue! > today, isTrue);
    }
    expect(await catchUp.offer(), isNull);

    expect(await catchUp.undo(), offer.count);
    expect((await db.plansDao.planFor(today))!.header.waitingCount, offer.count);
    expect((await db.itemStateDao.stateOf(moved.first.nodeId)).ladderDue, day0.plusDays(1));
    expect(await catchUp.undo(), 0);
  });

  test('decline hides the offer for the day', () async {
    final catchUp = c.read(catchUpProvider);
    expect(await catchUp.offer(), isNotNull);
    await catchUp.decline();
    expect(await catchUp.offer(), isNull);
  });

  test('an exam too soon is reported as not fitting', () async {
    await c.read(saveExamProvider).create('MPSC Prelims', c.read(todayProvider).plusDays(1), {'s'});
    final offer = (await c.read(catchUpProvider).offer())!;
    expect(offer.wontFitLines.single, startsWith('${offer.proposal.wontFit.values.single} can\'t fit'
        ' before MPSC Prelims at 30 min/day'));
  });
}
