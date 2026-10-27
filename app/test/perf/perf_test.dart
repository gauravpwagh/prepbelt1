import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/integrity.dart';

import '../application/app_helpers.dart';
import 'seed_5k.dart';

/// Host-side timings on the 5,000-item seed. The NFR targets (Library ≤ 100
/// ms, plan build ≤ 50 ms) are for a profile build on a 4 GB phone; here the
/// bounds are loose and only catch a query that has gone badly wrong.
void main() {
  test('5,000 items: plan build and Library load stay fast', () async {
    final f = Fixture();
    final ProviderContainer c = containerFor(f);
    await seed5k(f.db, now: t0);
    expect(await f.db.nodesDao.plannable(), hasLength(5000));
    expect((await runIntegrityCheck(f.db)).ok, isTrue);

    final plans = c.read(buildTodayPlanProvider);
    await plans.compute(); // warm-up
    final sw = Stopwatch()..start();
    final (input, plan) = await plans.compute();
    final planMs = sw.elapsedMilliseconds;
    sw
      ..reset()
      ..start();
    final nodes = await f.db.nodesDao.allLive();
    final states = await f.db.itemStateDao.allReviewable();
    final libraryMs = sw.elapsedMilliseconds;

    // ignore: avoid_print
    print('seed_5k: plan input+build ${planMs}ms, Library queries ${libraryMs}ms, '
        '${plan.rows.length} rows, ${plan.waitingCount} waiting');
    expect(input.items, hasLength(5000));
    expect(nodes.length, 6050);
    expect(states, hasLength(5000));
    expect(planMs, lessThan(5000));
    expect(libraryMs, lessThan(3000));
    c.dispose();
    await f.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
