import '../data/db/app_database.dart';

/// Soft-deletes an item and everything under it. History stays.
class DeleteItem {
  DeleteItem(this._db, {required DateTime Function() now}) : _now = now;
  final AppDatabase _db;
  final DateTime Function() _now;

  Future<void> call(String nodeId) => _db.nodesDao.softDelete(nodeId, _now());
}
