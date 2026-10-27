import 'package:prep_core/prep_core.dart';

import '../data/study_writer.dart';

/// Undo the item's latest event (plan item 77).
class UndoLatest {
  UndoLatest(this._writer);
  final StudyWriter _writer;

  Future<Undo?> call(String nodeId) => _writer.writeUndoLatest(nodeId);
}
