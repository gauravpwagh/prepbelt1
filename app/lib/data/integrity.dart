// The integrity check (design §8, plan item 64). It only reports; nothing is
// changed automatically.
import 'db/app_database.dart';

class IntegrityReport {
  const IntegrityReport({
    required this.integrity,
    required this.foreignKeyViolations,
    required this.openSessions,
  });

  /// `PRAGMA integrity_check` lines; `['ok']` when healthy.
  final List<String> integrity;

  /// One line per `PRAGMA foreign_key_check` row.
  final List<String> foreignKeyViolations;

  final int openSessions;

  bool get ok =>
      integrity.length == 1 &&
      integrity.single == 'ok' &&
      foreignKeyViolations.isEmpty &&
      openSessions <= 1;

  @override
  String toString() => ok
      ? 'Integrity OK'
      : 'Integrity problems: ${[
          if (!(integrity.length == 1 && integrity.single == 'ok')) ...integrity,
          ...foreignKeyViolations,
          if (openSessions > 1) '$openSessions open sessions',
        ].join('; ')}';
}

Future<IntegrityReport> runIntegrityCheck(AppDatabase db) async {
  final integrity = [
    for (final r in await db.customSelect('PRAGMA integrity_check').get())
      r.data.values.first.toString(),
  ];
  final fk = [
    for (final r in await db.customSelect('PRAGMA foreign_key_check').get())
      '${r.data['table']} row ${r.data['rowid']} → ${r.data['parent']}',
  ];
  final open = await db
      .customSelect(
          'SELECT COUNT(*) AS n FROM study_sessions WHERE ended_at_utc IS NULL')
      .getSingle();
  return IntegrityReport(
    integrity: integrity,
    foreignKeyViolations: fk,
    openSessions: open.read<int>('n'),
  );
}
