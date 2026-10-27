import 'package:drift/drift.dart';
import 'package:prep_core/prep_core.dart';

import '../db/app_database.dart';
import '../db/tables.dart';
import 'nodes_dao.dart' show reviewableSql;

part 'item_state_dao.g.dart';

@DriftAccessor(tables: [ItemStates, StudyNodes])
class ItemStateDao extends DatabaseAccessor<AppDatabase>
    with _$ItemStateDaoMixin {
  ItemStateDao(super.db);

  /// Written by `StudyWriter` in the same transaction as each event.
  Future<void> upsert(String nodeId, ItemState state) =>
      into(itemStates).insertOnConflictUpdate(ItemStatesCompanion.insert(
        nodeId: nodeId,
        belt: state.belt,
        ladderDue: Value(state.ladderDue),
        lastReviewDate: Value(state.lastReviewDate),
        reviewCount: Value(state.reviewCount),
      ));

  SimpleSelectStatement<$ItemStatesTable, ItemStateRow> _of(String nodeId) =>
      select(itemStates)..where((s) => s.nodeId.equals(nodeId));

  /// The node's state; Unread when it has none.
  Future<ItemState> stateOf(String nodeId) async =>
      _toState(await _of(nodeId).getSingleOrNull());

  Stream<ItemState> watch(String nodeId) =>
      _of(nodeId).watchSingleOrNull().map(_toState);

  /// Every stored state, keyed by node ID (nodes without a row are Unread).
  Future<Map<String, ItemState>> all() async =>
      {for (final r in await select(itemStates).get()) r.nodeId: _toState(r)};

  /// The state of every live reviewable node, keyed by node ID.
  Future<Map<String, ItemState>> allReviewable() async {
    final rows = await customSelect(
      'SELECT n.id AS node_id, s.belt, s.ladder_due, s.last_review_date,'
      ' s.review_count'
      ' FROM study_nodes n LEFT JOIN item_state s ON s.node_id = n.id'
      ' WHERE $reviewableSql',
      readsFrom: {studyNodes, itemStates},
    ).get();
    LocalDate? date(String? iso) => iso == null ? null : LocalDate.parse(iso);
    return {
      for (final r in rows)
        r.read<String>('node_id'): switch (r.readNullable<String>('belt')) {
          null => ItemState.unread,
          final belt => ItemState(
              belt: Belt.fromKey(belt),
              ladderDue: date(r.readNullable<String>('ladder_due')),
              lastReviewDate:
                  date(r.readNullable<String>('last_review_date')),
              reviewCount: r.read<int>('review_count'),
            ),
        },
    };
  }
}

ItemState _toState(ItemStateRow? r) => r == null
    ? ItemState.unread
    : ItemState(
        belt: r.belt,
        ladderDue: r.ladderDue,
        lastReviewDate: r.lastReviewDate,
        reviewCount: r.reviewCount,
      );
