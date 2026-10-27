import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables.dart';

part 'sessions_dao.g.dart';

@DriftAccessor(tables: [StudySessions])
class SessionsDao extends DatabaseAccessor<AppDatabase>
    with _$SessionsDaoMixin {
  SessionsDao(super.db);

  SimpleSelectStatement<$StudySessionsTable, SessionRow> get _openQuery =>
      select(studySessions)..where((s) => s.endedAtUtc.isNull());

  /// The open session, if any. A unique index allows at most one.
  Future<SessionRow?> open() => _openQuery.getSingleOrNull();

  Stream<SessionRow?> watchOpen() => _openQuery.watchSingleOrNull();

  /// Starts a session; throws if one is already open.
  Future<void> start(String id, String nodeId, DateTime at) =>
      into(studySessions).insert(
          StudySessionsCompanion.insert(id: id, nodeId: nodeId, startedAtUtc: at));

  Future<void> finish(String id, DateTime endedAt, int minutes,
          {required bool edited}) =>
      (update(studySessions)..where((s) => s.id.equals(id))).write(
          StudySessionsCompanion(
              endedAtUtc: Value(endedAt),
              confirmedMinutes: Value(minutes),
              edited: Value(edited)));

  Future<void> discard(String id, DateTime endedAt) =>
      (update(studySessions)..where((s) => s.id.equals(id))).write(
          StudySessionsCompanion(
              endedAtUtc: Value(endedAt), discarded: const Value(true)));
}
