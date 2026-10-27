import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/integrity.dart';

final integrityProvider = FutureProvider.autoDispose<IntegrityReport>(
    (ref) => runIntegrityCheck(ref.watch(appDatabaseProvider)));
