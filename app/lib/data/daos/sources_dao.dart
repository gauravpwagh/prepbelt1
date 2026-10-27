import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import '../db/tables.dart';

part 'sources_dao.g.dart';

@DriftAccessor(tables: [NodeSources, SourceFolders])
class SourcesDao extends DatabaseAccessor<AppDatabase> with _$SourcesDaoMixin {
  SourcesDao(super.db);

  /// Inserts or replaces the source of a task.
  Future<void> upsertSource(NodeSourcesCompanion source) =>
      into(nodeSources).insertOnConflictUpdate(source);

  Future<SourceRow?> sourceFor(String nodeId) =>
      (select(nodeSources)..where((s) => s.nodeId.equals(nodeId)))
          .getSingleOrNull();

  Future<void> setLinkStatus(String nodeId, LinkStatus status) =>
      (update(nodeSources)..where((s) => s.nodeId.equals(nodeId)))
          .write(NodeSourcesCompanion(linkStatus: Value(status)));

  Future<void> deleteSource(String nodeId) =>
      (delete(nodeSources)..where((s) => s.nodeId.equals(nodeId))).go();

  /// Sources "Re-link by folder" tries to match (design §7): every
  /// `needs_relink` source, plus `not_linked` PDFs that have a file name.
  Future<List<SourceRow>> relinkCandidates() => (select(nodeSources)
        ..where((s) =>
            s.linkStatus.equalsValue(LinkStatus.needsRelink) |
            (s.linkStatus.equalsValue(LinkStatus.notLinked) &
                s.sourceType.equalsValue(SourceType.pdf) &
                s.fileName.isNotNull())))
      .get();

  // ---- folders ----

  Future<void> insertFolder(SourceFoldersCompanion folder) =>
      into(sourceFolders).insert(folder);

  Future<FolderRow?> folderById(String id) =>
      (select(sourceFolders)..where((f) => f.id.equals(id))).getSingleOrNull();

  /// Folders for [purpose], oldest grant first (the order shared PDFs are
  /// matched in).
  Future<List<FolderRow>> folders(FolderPurpose purpose) =>
      (select(sourceFolders)
            ..where((f) => f.purpose.equalsValue(purpose))
            ..orderBy([(f) => OrderingTerm.asc(f.grantedAt)]))
          .get();

  /// Records a fresh grant; null marks the folder "pick again".
  Future<void> setTreeUri(String id, String? treeUri, {DateTime? grantedAt}) =>
      (update(sourceFolders)..where((f) => f.id.equals(id))).write(
          SourceFoldersCompanion(
              treeUri: Value(treeUri),
              grantedAt:
                  grantedAt == null ? const Value.absent() : Value(grantedAt)));

  /// Fails on a foreign key while sources still point at the folder.
  Future<void> deleteFolder(String id) =>
      (delete(sourceFolders)..where((f) => f.id.equals(id))).go();
}
