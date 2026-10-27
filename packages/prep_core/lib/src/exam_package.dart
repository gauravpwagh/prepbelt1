// The exam file format and its pure rules (design §8a). The app layer reads
// the database into an [ExamPackage], and writes one back on import.
import 'dart:convert';

import 'package:meta/meta.dart';

import 'as_i_go.dart';
import 'belt.dart';
import 'events.dart';
import 'grade.dart';
import 'hierarchy.dart';
import 'local_date.dart';
import 'share_classifier.dart';

const examFormatId = 'prepbelt-exam';
const examFormatVersion = 1;

/// Files larger than this are not parsed.
const examFileMaxBytes = 20 * 1024 * 1024;

enum PackageMode {
  structure('structure'),
  progress('progress');

  const PackageMode(this.key);
  final String key;
}

@immutable
final class PkgExam {
  const PkgExam({required this.id, required this.name, required this.examDate});
  final String id;
  final String name;
  final LocalDate examDate;

  PkgExam copyWith({String? id, String? name, LocalDate? examDate}) => PkgExam(
      id: id ?? this.id, name: name ?? this.name, examDate: examDate ?? this.examDate);
}

@immutable
final class PkgSubject {
  const PkgSubject({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.alsoUsedBy = const [],
  });
  final String id;
  final String name;
  final int sortOrder;
  final List<String> alsoUsedBy;

  PkgSubject copyWith({String? id, String? name, int? sortOrder, List<String>? alsoUsedBy}) =>
      PkgSubject(
        id: id ?? this.id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        alsoUsedBy: alsoUsedBy ?? this.alsoUsedBy,
      );
}

@immutable
final class PkgNode {
  const PkgNode({
    required this.id,
    required this.subjectId,
    this.parentId,
    required this.kind,
    this.taskKind,
    required this.title,
    this.positionText,
    this.baseMinutes,
    required this.sortOrder,
    required this.createdAtUtcMs,
    this.splitAsIGo,
  });
  final String id;
  final String subjectId;
  final String? parentId;
  final NodeKind kind;
  final TaskKind? taskKind;
  final String title;
  final String? positionText;
  final int? baseMinutes;
  final int sortOrder;
  final int createdAtUtcMs;

  /// Optional (design §10b): older files and older apps leave it out.
  final SplitAsIGo? splitAsIGo;

  PkgNode copyWith({String? id, String? subjectId, String? parentId, int? sortOrder}) => PkgNode(
        id: id ?? this.id,
        subjectId: subjectId ?? this.subjectId,
        parentId: parentId ?? this.parentId,
        kind: kind,
        taskKind: taskKind,
        title: title,
        positionText: positionText,
        baseMinutes: baseMinutes,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAtUtcMs: createdAtUtcMs,
        splitAsIGo: splitAsIGo,
      );
}

@immutable
final class PkgSource {
  const PkgSource({
    required this.nodeId,
    required this.sourceType,
    this.url,
    this.fileName,
    this.fileSize,
    this.locationNote,
    this.excerpt,
  });
  final String nodeId;
  final SourceType sourceType;
  final String? url;
  final String? fileName;
  final int? fileSize;
  final String? locationNote;
  final String? excerpt;

  PkgSource copyWith({String? nodeId}) => PkgSource(
        nodeId: nodeId ?? this.nodeId,
        sourceType: sourceType,
        url: url,
        fileName: fileName,
        fileSize: fileSize,
        locationNote: locationNote,
        excerpt: excerpt,
      );

  PkgSource stripped() => PkgSource(
        nodeId: nodeId,
        sourceType: sourceType,
        url: sourceType == SourceType.aiChat ? null : url,
        fileName: fileName,
        fileSize: fileSize,
      );
}

/// One `review_events` row without `session_id`.
@immutable
final class PkgEvent {
  const PkgEvent({
    required this.id,
    required this.nodeId,
    required this.eventType,
    required this.atUtcMs,
    required this.localDate,
    required this.tzId,
    this.grade,
    this.minutes,
    this.beltBefore,
    this.beltAfter,
    this.intervalDays,
    this.ladderDueAfter,
    this.explanation,
    this.undoesEventId,
    this.batchId,
    this.schedulerVersion = 1,
  });

  final String id;
  final String nodeId;

  /// `first_study` | `review` | `reschedule` | `undo`
  final String eventType;
  final int atUtcMs;
  final LocalDate localDate;
  final String tzId;
  final Grade? grade;
  final int? minutes;
  final Belt? beltBefore;
  final Belt? beltAfter;
  final int? intervalDays;
  final LocalDate? ladderDueAfter;
  final String? explanation;
  final String? undoesEventId;
  final String? batchId;
  final int schedulerVersion;

  PkgEvent copyWith({String? id, String? nodeId, String? undoesEventId, String? batchId}) =>
      PkgEvent(
        id: id ?? this.id,
        nodeId: nodeId ?? this.nodeId,
        eventType: eventType,
        atUtcMs: atUtcMs,
        localDate: localDate,
        tzId: tzId,
        grade: grade,
        minutes: minutes,
        beltBefore: beltBefore,
        beltAfter: beltAfter,
        intervalDays: intervalDays,
        ladderDueAfter: ladderDueAfter,
        explanation: explanation,
        undoesEventId: undoesEventId ?? this.undoesEventId,
        batchId: batchId ?? this.batchId,
        schedulerVersion: schedulerVersion,
      );

  /// Converts to the domain event, for `deriveState` after import.
  StudyEvent toStudyEvent() {
    final at = DateTime.fromMillisecondsSinceEpoch(atUtcMs, isUtc: true);
    Outcome outcome() => Outcome(
          beltBefore: beltBefore!,
          beltAfter: beltAfter!,
          intervalDays: intervalDays,
          ladderDue: ladderDueAfter,
          explanation: explanation ?? '',
        );
    return switch (eventType) {
      'first_study' => FirstStudy(
          id: id, nodeId: nodeId, atUtc: at, localDate: localDate, tzId: tzId,
          minutes: minutes ?? 0, outcome: outcome()),
      'review' => Review(
          id: id, nodeId: nodeId, atUtc: at, localDate: localDate, tzId: tzId,
          grade: grade!, minutes: minutes ?? 0, outcome: outcome()),
      'reschedule' => Reschedule(
          id: id, nodeId: nodeId, atUtc: at, localDate: localDate, tzId: tzId,
          batchId: batchId ?? '', outcome: outcome()),
      'undo' => Undo(
          id: id, nodeId: nodeId, atUtc: at, localDate: localDate, tzId: tzId,
          targetId: undoesEventId!),
      _ => throw FormatException('Unknown event type', eventType),
    };
  }
}

@immutable
final class ExamPackage {
  const ExamPackage({
    this.formatVersion = examFormatVersion,
    this.appVersion = '',
    this.exportedAtUtcMs = 0,
    required this.mode,
    required this.exam,
    required this.subjects,
    required this.nodes,
    required this.sources,
    this.events = const [],
  });

  final int formatVersion;
  final String appVersion;
  final int exportedAtUtcMs;
  final PackageMode mode;
  final PkgExam exam;
  final List<PkgSubject> subjects;
  final List<PkgNode> nodes;
  final List<PkgSource> sources;
  final List<PkgEvent> events;

  ExamPackage copyWith({
    PkgExam? exam,
    List<PkgSubject>? subjects,
    List<PkgNode>? nodes,
    List<PkgSource>? sources,
    List<PkgEvent>? events,
  }) =>
      ExamPackage(
        formatVersion: formatVersion,
        appVersion: appVersion,
        exportedAtUtcMs: exportedAtUtcMs,
        mode: mode,
        exam: exam ?? this.exam,
        subjects: subjects ?? this.subjects,
        nodes: nodes ?? this.nodes,
        sources: sources ?? this.sources,
        events: events ?? this.events,
      );

  // ---------------------------------------------------------------- JSON --

  Map<String, Object?> toJson() => {
        'format': examFormatId,
        'format_version': formatVersion,
        'app_version': appVersion,
        'exported_at_utc': exportedAtUtcMs,
        'mode': mode.key,
        'exam': {'id': exam.id, 'name': exam.name, 'exam_date': exam.examDate.toIso()},
        'subjects': [
          for (final s in subjects)
            {
              'id': s.id,
              'name': s.name,
              'sort_order': s.sortOrder,
              if (s.alsoUsedBy.isNotEmpty) 'also_used_by': s.alsoUsedBy,
            }
        ],
        'nodes': [
          for (final n in nodes)
            {
              'id': n.id,
              'subject_id': n.subjectId,
              'parent_id': n.parentId,
              'kind': n.kind.key,
              'task_kind': n.taskKind?.key,
              'title': n.title,
              'position_text': n.positionText,
              'base_minutes': n.baseMinutes,
              'sort_order': n.sortOrder,
              'created_at_utc': n.createdAtUtcMs,
              if (n.splitAsIGo != null) 'split_as_i_go': n.splitAsIGo!.key,
            }
        ],
        'sources': [
          for (final s in sources)
            {
              'node_id': s.nodeId,
              'source_type': s.sourceType.key,
              if (s.url != null) 'url': s.url,
              'file_name': s.fileName,
              'file_size': s.fileSize,
              if (s.locationNote != null) 'location_note': s.locationNote,
              if (s.excerpt != null) 'excerpt': s.excerpt,
            }
        ],
        if (mode == PackageMode.progress)
          'events': [
            for (final e in events)
              {
                'id': e.id,
                'node_id': e.nodeId,
                'event_type': e.eventType,
                'at_utc': e.atUtcMs,
                'local_date': e.localDate.toIso(),
                'tz_id': e.tzId,
                'grade': e.grade?.key,
                'minutes': e.minutes,
                'belt_before': e.beltBefore?.key,
                'belt_after': e.beltAfter?.key,
                'interval_days': e.intervalDays,
                'ladder_due_after': e.ladderDueAfter?.toIso(),
                'explanation': e.explanation,
                'undoes_event_id': e.undoesEventId,
                'batch_id': e.batchId,
                'scheduler': 'ladder',
                'scheduler_version': e.schedulerVersion,
              }
          ],
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parses a file. Throws [FormatException] for anything that is not a
  /// readable exam file; use [validate] afterwards for the content rules.
  factory ExamPackage.decode(String source) {
    if (source.length > examFileMaxBytes) {
      throw const FormatException('File too large');
    }
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Not a PrepBelt exam file');
    }
    if (raw is! Map<String, Object?> || raw['format'] != examFormatId) {
      throw const FormatException('Not a PrepBelt exam file');
    }
    return ExamPackage.fromJson(raw);
  }

  factory ExamPackage.fromJson(Map<String, Object?> j) {
    T req<T>(Map<String, Object?> m, String k) {
      final v = m[k];
      if (v is! T) throw FormatException('Missing or wrong "$k"');
      return v;
    }

    T? opt<T>(Map<String, Object?> m, String k) {
      final v = m[k];
      if (v == null) return null;
      if (v is T) return v as T;
      throw FormatException('Wrong type for "$k"');
    }

    List<Map<String, Object?>> list(String k) => [
          for (final e in (j[k] as List<Object?>? ?? const []))
            if (e is Map<String, Object?>) e else throw FormatException('Bad entry in "$k"'),
        ];

    E key<E>(List<E> values, String Function(E) keyOf, String k) =>
        values.firstWhere((v) => keyOf(v) == k,
            orElse: () => throw FormatException('Unknown value "$k"'));

    final version = req<int>(j, 'format_version');
    final modeKey = req<String>(j, 'mode');
    final exam = req<Map<String, Object?>>(j, 'exam');

    return ExamPackage(
      formatVersion: version,
      appVersion: opt<String>(j, 'app_version') ?? '',
      exportedAtUtcMs: opt<int>(j, 'exported_at_utc') ?? 0,
      mode: key(PackageMode.values, (m) => m.key, modeKey),
      exam: PkgExam(
        id: req<String>(exam, 'id'),
        name: req<String>(exam, 'name'),
        examDate: LocalDate.parse(req<String>(exam, 'exam_date')),
      ),
      subjects: [
        for (final s in list('subjects'))
          PkgSubject(
            id: req<String>(s, 'id'),
            name: req<String>(s, 'name'),
            sortOrder: req<int>(s, 'sort_order'),
            alsoUsedBy: [for (final x in opt<List<Object?>>(s, 'also_used_by') ?? const []) '$x'],
          ),
      ],
      nodes: [
        for (final n in list('nodes'))
          PkgNode(
            id: req<String>(n, 'id'),
            subjectId: req<String>(n, 'subject_id'),
            parentId: opt<String>(n, 'parent_id'),
            kind: _parseKey(NodeKind.fromKey, req<String>(n, 'kind')),
            taskKind: opt<String>(n, 'task_kind') == null
                ? null
                : _parseKey(TaskKind.fromKey, req<String>(n, 'task_kind')),
            title: req<String>(n, 'title'),
            positionText: opt<String>(n, 'position_text'),
            baseMinutes: opt<int>(n, 'base_minutes'),
            sortOrder: req<int>(n, 'sort_order'),
            createdAtUtcMs: req<int>(n, 'created_at_utc'),
            splitAsIGo: opt<String>(n, 'split_as_i_go') == null
                ? null
                : _parseKey(SplitAsIGo.fromKey, req<String>(n, 'split_as_i_go')),
          ),
      ],
      sources: [
        for (final s in list('sources'))
          PkgSource(
            nodeId: req<String>(s, 'node_id'),
            sourceType: key(SourceType.values, (t) => t.key, req<String>(s, 'source_type')),
            url: opt<String>(s, 'url'),
            fileName: opt<String>(s, 'file_name'),
            fileSize: opt<int>(s, 'file_size'),
            locationNote: opt<String>(s, 'location_note'),
            excerpt: opt<String>(s, 'excerpt'),
          ),
      ],
      events: [
        for (final e in list('events'))
          PkgEvent(
            id: req<String>(e, 'id'),
            nodeId: req<String>(e, 'node_id'),
            eventType: req<String>(e, 'event_type'),
            atUtcMs: req<int>(e, 'at_utc'),
            localDate: LocalDate.parse(req<String>(e, 'local_date')),
            tzId: req<String>(e, 'tz_id'),
            grade: opt<String>(e, 'grade') == null
                ? null
                : key<Grade>(Grade.values, (g) => g.key, req<String>(e, 'grade')),
            minutes: opt<int>(e, 'minutes'),
            beltBefore: opt<String>(e, 'belt_before') == null
                ? null
                : key<Belt>(Belt.values, (b) => b.key, req<String>(e, 'belt_before')),
            beltAfter: opt<String>(e, 'belt_after') == null
                ? null
                : key<Belt>(Belt.values, (b) => b.key, req<String>(e, 'belt_after')),
            intervalDays: opt<int>(e, 'interval_days'),
            ladderDueAfter: opt<String>(e, 'ladder_due_after') == null
                ? null
                : LocalDate.parse(req<String>(e, 'ladder_due_after')),
            explanation: opt<String>(e, 'explanation'),
            undoesEventId: opt<String>(e, 'undoes_event_id'),
            batchId: opt<String>(e, 'batch_id'),
            schedulerVersion: opt<int>(e, 'scheduler_version') ?? 1,
          ),
      ],
    );
  }
}

/// Parses an enum key, turning an unknown value into a [FormatException].
E _parseKey<E>(E Function(String) fromKey, String k) {
  try {
    return fromKey(k);
  } on ArgumentError {
    throw FormatException('Unknown value "$k"');
  }
}
