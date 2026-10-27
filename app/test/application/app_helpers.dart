import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/providers.dart';

import '../data/helpers.dart';

export '../data/helpers.dart';

/// A [ProviderContainer] wired to [f]'s database, clock and IDs.
ProviderContainer containerFor(Fixture f, {List<dynamic> extra = const []}) {
  final c = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(f.db),
    clockProvider.overrideWithValue(f.clock),
    offsetFnProvider.overrideWithValue((_) => ist),
    tzIdProvider.overrideWithValue('Asia/Kolkata'),
    idGeneratorProvider.overrideWithValue(f.newId),
    ...appOverrides,
    ...extra.cast(),
  ]);
  c.read(onboardingDoneProvider.notifier).set(true);
  return c;
}
