import 'package:drift/drift.dart';

import '../data/db/app_database.dart';

/// Re-runs [load] whenever any of [tables] changes, starting immediately.
/// Screens use this to watch derived views built from several tables.
Stream<T> watchTables<T>(AppDatabase db, Set<ResultSetImplementation<dynamic, dynamic>> tables,
    Future<T> Function() load) async* {
  yield await load();
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables(tables))) {
    yield await load();
  }
}
