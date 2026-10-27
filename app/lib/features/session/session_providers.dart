import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/finish_session.dart';
import '../../core/db_watch.dart';
import '../../core/providers.dart';

/// The open session as the Finish sheet would show it, or null.
final openSessionProvider = StreamProvider.autoDispose<OpenSession?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final finish = ref.watch(finishSessionProvider);
  return watchTables(db, {db.studySessions}, finish.pending);
});
