// Column converters (plan item 53). Enums are stored by their string keys,
// never by position, so reordering an enum can never change stored data.
import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

/// Instants as UTC milliseconds in an INTEGER column.
class UtcMillisConverter extends TypeConverter<DateTime, int> {
  const UtcMillisConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// Study days as `YYYY-MM-DD` text.
class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parse(fromDb);

  @override
  String toSql(LocalDate value) => value.toIso();
}

/// Base for enums that carry a stable `key`.
abstract class _KeyConverter<T extends Object> extends TypeConverter<T, String> {
  const _KeyConverter();

  List<T> get values;
  String keyOf(T value);

  @override
  T fromSql(String fromDb) => values.firstWhere((v) => keyOf(v) == fromDb,
      orElse: () => throw ArgumentError.value(fromDb, 'key', 'Unknown $T'));

  @override
  String toSql(T value) => keyOf(value);
}

class BeltConverter extends _KeyConverter<Belt> {
  const BeltConverter();
  @override
  List<Belt> get values => Belt.values;
  @override
  String keyOf(Belt value) => value.key;
}

class GradeConverter extends _KeyConverter<Grade> {
  const GradeConverter();
  @override
  List<Grade> get values => Grade.values;
  @override
  String keyOf(Grade value) => value.key;
}

class NodeKindConverter extends _KeyConverter<NodeKind> {
  const NodeKindConverter();
  @override
  List<NodeKind> get values => NodeKind.values;
  @override
  String keyOf(NodeKind value) => value.key;
}

class SplitAsIGoConverter extends _KeyConverter<SplitAsIGo> {
  const SplitAsIGoConverter();
  @override
  List<SplitAsIGo> get values => SplitAsIGo.values;
  @override
  String keyOf(SplitAsIGo value) => value.key;
}

class TaskKindConverter extends _KeyConverter<TaskKind> {
  const TaskKindConverter();
  @override
  List<TaskKind> get values => TaskKind.values;
  @override
  String keyOf(TaskKind value) => value.key;
}

class SourceTypeConverter extends _KeyConverter<SourceType> {
  const SourceTypeConverter();
  @override
  List<SourceType> get values => SourceType.values;
  @override
  String keyOf(SourceType value) => value.key;
}

class RowTypeConverter extends _KeyConverter<RowType> {
  const RowTypeConverter();
  @override
  List<RowType> get values => RowType.values;
  @override
  String keyOf(RowType value) => value.key;
}

class ReasonConverter extends _KeyConverter<Reason> {
  const ReasonConverter();
  @override
  List<Reason> get values => Reason.values;
  @override
  String keyOf(Reason value) => value.key;
}

/// `node_sources.link_status` (design §7).
enum LinkStatus {
  ok('ok'),
  needsRelink('needs_relink'),
  notLinked('not_linked');

  const LinkStatus(this.key);
  final String key;
}

class LinkStatusConverter extends _KeyConverter<LinkStatus> {
  const LinkStatusConverter();
  @override
  List<LinkStatus> get values => LinkStatus.values;
  @override
  String keyOf(LinkStatus value) => value.key;
}

/// `source_folders.purpose`.
enum FolderPurpose {
  sources('sources'),
  backup('backup');

  const FolderPurpose(this.key);
  final String key;
}

class FolderPurposeConverter extends _KeyConverter<FolderPurpose> {
  const FolderPurposeConverter();
  @override
  List<FolderPurpose> get values => FolderPurpose.values;
  @override
  String keyOf(FolderPurpose value) => value.key;
}

/// `day_plans.catch_up_state` (design §4).
enum CatchUpState {
  none('none'),
  offered('offered'),
  accepted('accepted'),
  declined('declined');

  const CatchUpState(this.key);
  final String key;
}

class CatchUpStateConverter extends _KeyConverter<CatchUpState> {
  const CatchUpStateConverter();
  @override
  List<CatchUpState> get values => CatchUpState.values;
  @override
  String keyOf(CatchUpState value) => value.key;
}
