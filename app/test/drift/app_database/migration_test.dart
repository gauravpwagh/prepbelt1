// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('migration from v1 to v2 does not corrupt data', () async {
    final oldExamsData = <v1.ExamsData>[];
    final expectedNewExamsData = <v2.ExamsData>[];

    final oldSubjectsData = <v1.SubjectsData>[
      const v1.SubjectsData(id: 's1', name: 'Polity', sortOrder: 0, isInbox: 0, createdAt: 1),
    ];
    final expectedNewSubjectsData = <v2.SubjectsData>[
      const v2.SubjectsData(id: 's1', name: 'Polity', sortOrder: 0, isInbox: 0, createdAt: 1),
    ];

    final oldExamSubjectsData = <v1.ExamSubjectsData>[];
    final expectedNewExamSubjectsData = <v2.ExamSubjectsData>[];

    // Existing tasks are not split as you go (design D17).
    final oldStudyNodesData = <v1.StudyNodesData>[
      const v1.StudyNodesData(id: 'k1', subjectId: 's1', kind: 'task', taskKind: 'reading',
          title: 'Laxmikant', baseMinutes: 30, sortOrder: 0, createdAt: 2),
    ];
    final expectedNewStudyNodesData = <v2.StudyNodesData>[
      const v2.StudyNodesData(id: 'k1', subjectId: 's1', kind: 'task', taskKind: 'reading',
          title: 'Laxmikant', baseMinutes: 30, sortOrder: 0, createdAt: 2),
    ];

    final oldSourceFoldersData = <v1.SourceFoldersData>[];
    final expectedNewSourceFoldersData = <v2.SourceFoldersData>[];

    final oldNodeSourcesData = <v1.NodeSourcesData>[];
    final expectedNewNodeSourcesData = <v2.NodeSourcesData>[];

    final oldStudySessionsData = <v1.StudySessionsData>[];
    final expectedNewStudySessionsData = <v2.StudySessionsData>[];

    final oldReviewEventsData = <v1.ReviewEventsData>[];
    final expectedNewReviewEventsData = <v2.ReviewEventsData>[];

    final oldItemStateData = <v1.ItemStateData>[];
    final expectedNewItemStateData = <v2.ItemStateData>[];

    final oldDayPlansData = <v1.DayPlansData>[];
    final expectedNewDayPlansData = <v2.DayPlansData>[];

    final oldDayPlanRowsData = <v1.DayPlanRowsData>[];
    final expectedNewDayPlanRowsData = <v2.DayPlanRowsData>[];

    final oldSettingsData = <v1.SettingsData>[];
    final expectedNewSettingsData = <v2.SettingsData>[];

    final oldBackupMetaData = <v1.BackupMetaData>[];
    final expectedNewBackupMetaData = <v2.BackupMetaData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.exams, oldExamsData);
        batch.insertAll(oldDb.subjects, oldSubjectsData);
        batch.insertAll(oldDb.examSubjects, oldExamSubjectsData);
        batch.insertAll(oldDb.studyNodes, oldStudyNodesData);
        batch.insertAll(oldDb.sourceFolders, oldSourceFoldersData);
        batch.insertAll(oldDb.nodeSources, oldNodeSourcesData);
        batch.insertAll(oldDb.studySessions, oldStudySessionsData);
        batch.insertAll(oldDb.reviewEvents, oldReviewEventsData);
        batch.insertAll(oldDb.itemState, oldItemStateData);
        batch.insertAll(oldDb.dayPlans, oldDayPlansData);
        batch.insertAll(oldDb.dayPlanRows, oldDayPlanRowsData);
        batch.insertAll(oldDb.settings, oldSettingsData);
        batch.insertAll(oldDb.backupMeta, oldBackupMetaData);
      },
      validateItems: (newDb) async {
        expect(expectedNewExamsData, await newDb.select(newDb.exams).get());
        expect(
            expectedNewSubjectsData, await newDb.select(newDb.subjects).get());
        expect(expectedNewExamSubjectsData,
            await newDb.select(newDb.examSubjects).get());
        expect(expectedNewStudyNodesData,
            await newDb.select(newDb.studyNodes).get());
        expect(expectedNewSourceFoldersData,
            await newDb.select(newDb.sourceFolders).get());
        expect(expectedNewNodeSourcesData,
            await newDb.select(newDb.nodeSources).get());
        expect(expectedNewStudySessionsData,
            await newDb.select(newDb.studySessions).get());
        expect(expectedNewReviewEventsData,
            await newDb.select(newDb.reviewEvents).get());
        expect(expectedNewItemStateData,
            await newDb.select(newDb.itemState).get());
        expect(
            expectedNewDayPlansData, await newDb.select(newDb.dayPlans).get());
        expect(expectedNewDayPlanRowsData,
            await newDb.select(newDb.dayPlanRows).get());
        expect(
            expectedNewSettingsData, await newDb.select(newDb.settings).get());
        expect(expectedNewBackupMetaData,
            await newDb.select(newDb.backupMeta).get());
      },
    );
  });
}
