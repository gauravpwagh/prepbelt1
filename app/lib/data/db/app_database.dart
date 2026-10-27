// The Drift database (plan item 55). Schema changes only add, each with a
// committed `make-migrations` snapshot; release builds never drop the data.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:prep_core/prep_core.dart';

import '../daos/events_dao.dart';
import '../daos/exams_dao.dart';
import '../daos/item_state_dao.dart';
import '../daos/nodes_dao.dart';
import '../daos/plans_dao.dart';
import '../daos/sessions_dao.dart';
import '../daos/settings_dao.dart';
import '../daos/sources_dao.dart';
import '../daos/subjects_dao.dart';
import 'app_database.steps.dart';
import 'converters.dart';
import 'db_file.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Exams,
  Subjects,
  ExamSubjects,
  StudyNodes,
  SourceFolders,
  NodeSources,
  StudySessions,
  ReviewEvents,
  ItemStates,
  DayPlans,
  DayPlanRows,
  Settings,
  BackupMeta,
], daos: [
  ExamsDao,
  SubjectsDao,
  NodesDao,
  SourcesDao,
  EventsDao,
  ItemStateDao,
  SessionsDao,
  PlansDao,
  SettingsDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens `prepbelt.sqlite` in the app's files directory. Drift runs its
  /// queries in a background isolate.
  factory AppDatabase.open() => AppDatabase(driftDatabase(
        name: 'prepbelt',
        native: DriftNativeOptions(databasePath: () async => (await databaseFile()).path),
      ));

  var _closed = false;

  /// Safe to call more than once (restore closes the database before the
  /// provider that owns it is reset).
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await super.close();
  }

  static const currentSchema = 2;

  @override
  int get schemaVersion => currentSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // Each version adds a `stepByStep` step from
        // `app_database.steps.dart`; there is no destructive fallback.
        onUpgrade: stepByStep(
          // v2: tasks split as you go (design D17).
          from1To2: (m, schema) async {
            await m.addColumn(schema.studyNodes, schema.studyNodes.splitAsIGo);
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA busy_timeout = 5000');
        },
      );
}
