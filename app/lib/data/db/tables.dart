// The tables from design §2 (plan item 54). Column names, CHECKs and indexes
// follow the design exactly; change them only through a new schema version.
import 'package:drift/drift.dart';

import 'converters.dart';

@DataClassName('ExamRow')
class Exams extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get examDate => text().map(const LocalDateConverter())();
  IntColumn get archivedAt =>
      integer().nullable().map(const UtcMillisConverter())();
  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SubjectRow')
@TableIndex.sql(
    'CREATE UNIQUE INDEX subjects_one_inbox ON subjects (is_inbox) WHERE is_inbox = 1')
class Subjects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExamSubjectRow')
class ExamSubjects extends Table {
  TextColumn get examId => text().references(Exams, #id)();
  TextColumn get subjectId => text().references(Subjects, #id)();

  @override
  Set<Column> get primaryKey => {examId, subjectId};
}

@DataClassName('NodeRow')
@TableIndex(name: 'study_nodes_parent_id', columns: {#parentId})
@TableIndex(name: 'study_nodes_subject_id', columns: {#subjectId})
class StudyNodes extends Table {
  TextColumn get id => text()();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get parentId => text().nullable().references(StudyNodes, #id)();
  TextColumn get kind => text().map(const NodeKindConverter())();
  TextColumn get taskKind =>
      text().nullable().map(const TaskKindConverter())();
  TextColumn get title => text()();
  TextColumn get positionText => text().nullable()();
  IntColumn get baseMinutes => integer().nullable()();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer().map(const UtcMillisConverter())();
  IntColumn get deletedAt =>
      integer().nullable().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (kind IN ('topic', 'task', 'subtask'))",
        "CHECK (task_kind IS NULL OR task_kind IN ('reading', 'pyq', 'other'))",
        // Topics carry no task kind or base time; tasks and subtasks carry both.
        "CHECK ((kind = 'topic' AND task_kind IS NULL AND base_minutes IS NULL)"
            " OR (kind <> 'topic' AND task_kind IS NOT NULL"
            " AND base_minutes BETWEEN 10 AND 50))",
      ];
}

@DataClassName('FolderRow')
class SourceFolders extends Table {
  TextColumn get id => text()();

  /// Null means "pick again" (after a restore).
  TextColumn get treeUri => text().nullable()();
  TextColumn get displayName => text()();
  TextColumn get purpose => text().map(const FolderPurposeConverter())();
  IntColumn get grantedAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints =>
      ["CHECK (purpose IN ('sources', 'backup'))"];
}

@DataClassName('SourceRow')
class NodeSources extends Table {
  TextColumn get nodeId => text().references(StudyNodes, #id)();
  TextColumn get sourceType => text().map(const SourceTypeConverter())();
  TextColumn get url => text().nullable()();
  TextColumn get folderId =>
      text().nullable().references(SourceFolders, #id)();
  TextColumn get relativePath => text().nullable()();
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get locationNote => text().nullable()();
  TextColumn get excerpt => text().nullable()();
  TextColumn get linkStatus => text().map(const LinkStatusConverter())();

  @override
  Set<Column> get primaryKey => {nodeId};

  @override
  List<String> get customConstraints => [
        "CHECK (source_type IN ('pdf', 'book', 'web', 'ai_chat', 'video',"
            " 'notes', 'lecture', 'app', 'other_device'))",
        "CHECK (link_status IN ('ok', 'needs_relink', 'not_linked'))",
        'CHECK (excerpt IS NULL OR length(excerpt) <= 20000)',
      ];
}

// At most one open session. Every open row indexes the same value (1), so a
// second one violates uniqueness; closed rows are outside the partial index.
@DataClassName('SessionRow')
@TableIndex.sql('CREATE UNIQUE INDEX study_sessions_one_open'
    ' ON study_sessions ((ended_at_utc IS NULL)) WHERE ended_at_utc IS NULL')
class StudySessions extends Table {
  TextColumn get id => text()();
  TextColumn get nodeId => text().references(StudyNodes, #id)();
  IntColumn get startedAtUtc => integer().map(const UtcMillisConverter())();
  IntColumn get endedAtUtc =>
      integer().nullable().map(const UtcMillisConverter())();
  IntColumn get confirmedMinutes => integer().nullable()();
  BoolColumn get edited => boolean().withDefault(const Constant(false))();
  BoolColumn get discarded => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The append-only event log. No code updates rows; the only delete is
/// "Archive and remove" (design §8a), through `StudyWriter`.
@DataClassName('EventRow')
@TableIndex(name: 'review_events_node_at', columns: {#nodeId, #atUtc})
class ReviewEvents extends Table {
  TextColumn get id => text()();
  TextColumn get nodeId => text().references(StudyNodes, #id)();
  TextColumn get eventType => text()();
  IntColumn get atUtc => integer().map(const UtcMillisConverter())();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tzId => text()();
  TextColumn get grade => text().nullable().map(const GradeConverter())();
  IntColumn get minutes => integer().nullable()();
  TextColumn get sessionId =>
      text().nullable().references(StudySessions, #id)();
  TextColumn get beltBefore => text().nullable().map(const BeltConverter())();
  TextColumn get beltAfter => text().nullable().map(const BeltConverter())();
  IntColumn get intervalDays => integer().nullable()();
  TextColumn get ladderDueAfter =>
      text().nullable().map(const LocalDateConverter())();
  TextColumn get explanation => text().nullable()();
  TextColumn get undoesEventId =>
      text().nullable().references(ReviewEvents, #id)();
  TextColumn get batchId => text().nullable()();
  TextColumn get scheduler => text().withDefault(const Constant('ladder'))();
  IntColumn get schedulerVersion =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  // The per-event_type column table in design §2.
  @override
  List<String> get customConstraints => [
        "CHECK (scheduler = 'ladder' AND scheduler_version = 1)",
        'CHECK (interval_days IS NULL OR interval_days >= 1)',
        'CHECK (minutes IS NULL OR minutes >= 0)',
        "CHECK (grade IS NULL OR grade IN ('forgot', 'shaky', 'solid'))",
        "CHECK (belt_before IS NULL OR belt_before IN"
            " ('unread', 'red', 'orange', 'yellow', 'light_green', 'green'))",
        "CHECK (belt_after IS NULL OR belt_after IN"
            " ('unread', 'red', 'orange', 'yellow', 'light_green', 'green'))",
        "CHECK ("
            "(event_type = 'first_study' AND grade IS NULL"
            " AND minutes IS NOT NULL"
            " AND belt_before = 'unread' AND belt_after = 'red'"
            " AND interval_days = 1 AND ladder_due_after IS NOT NULL"
            " AND undoes_event_id IS NULL AND batch_id IS NULL)"
            " OR (event_type = 'review' AND grade IS NOT NULL"
            " AND minutes IS NOT NULL"
            " AND belt_before IS NOT NULL AND belt_before <> 'unread'"
            " AND belt_after IS NOT NULL AND belt_after <> 'unread'"
            " AND interval_days IS NOT NULL AND ladder_due_after IS NOT NULL"
            " AND undoes_event_id IS NULL AND batch_id IS NULL)"
            " OR (event_type = 'reschedule' AND grade IS NULL"
            " AND minutes IS NULL AND session_id IS NULL"
            " AND belt_before IS NOT NULL AND belt_after = belt_before"
            " AND interval_days IS NULL AND ladder_due_after IS NOT NULL"
            " AND undoes_event_id IS NULL AND batch_id IS NOT NULL)"
            " OR (event_type = 'undo' AND grade IS NULL"
            " AND minutes IS NULL AND session_id IS NULL"
            " AND belt_before IS NULL AND belt_after IS NULL"
            " AND interval_days IS NULL AND ladder_due_after IS NULL"
            " AND undoes_event_id IS NOT NULL AND batch_id IS NULL)"
            ")",
      ];
}

@DataClassName('ItemStateRow')
@TableIndex(name: 'item_state_ladder_due', columns: {#ladderDue})
@TableIndex(name: 'item_state_belt', columns: {#belt})
class ItemStates extends Table {
  @override
  String get tableName => 'item_state';

  TextColumn get nodeId => text().references(StudyNodes, #id)();
  TextColumn get belt => text().map(const BeltConverter())();
  TextColumn get ladderDue =>
      text().nullable().map(const LocalDateConverter())();
  TextColumn get lastReviewDate =>
      text().nullable().map(const LocalDateConverter())();
  IntColumn get reviewCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {nodeId};

  @override
  List<String> get customConstraints => [
        "CHECK (belt IN"
            " ('unread', 'red', 'orange', 'yellow', 'light_green', 'green'))",
      ];
}

@DataClassName('DayPlanHeaderRow')
class DayPlans extends Table {
  TextColumn get localDate => text().map(const LocalDateConverter())();
  IntColumn get budgetMinutes => integer()();
  IntColumn get reviewMinutes => integer()();
  IntColumn get firstReadMinutes => integer()();
  IntColumn get waitingCount => integer()();
  IntColumn get waitingMinutes => integer()();
  TextColumn get catchUpState => text()
      .map(const CatchUpStateConverter())
      .withDefault(const Constant('none'))();
  TextColumn get catchUpBatchId => text().nullable()();
  IntColumn get builtAtUtc => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {localDate};

  @override
  List<String> get customConstraints => [
        "CHECK (catch_up_state IN ('none', 'offered', 'accepted', 'declined'))",
      ];
}

@DataClassName('DayPlanEntryRow')
class DayPlanRows extends Table {
  TextColumn get localDate => text()
      .map(const LocalDateConverter())
      .references(DayPlans, #localDate, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get nodeId => text().references(StudyNodes, #id)();
  TextColumn get rowType => text().map(const RowTypeConverter())();
  IntColumn get estimatedMinutes => integer()();
  TextColumn get reason => text().map(const ReasonConverter())();
  IntColumn get doneAtUtc =>
      integer().nullable().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {localDate, position};

  @override
  List<String> get customConstraints => [
        "CHECK (row_type IN ('review', 'first_read'))",
        "CHECK (reason IN"
            " ('due', 'overdue', 'deadline_risk', 'catch_up', 'first_read'))",
      ];
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// One row, carried into every backup (design §8).
@DataClassName('BackupMetaRow')
class BackupMeta extends Table {
  @override
  String get tableName => 'backup_meta';

  IntColumn get formatVersion => integer()();
  IntColumn get schemaVersion => integer()();
  TextColumn get appVersion => text()();
  IntColumn get createdAtUtc => integer().map(const UtcMillisConverter())();
}
