import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sheets that more than one feature opens. Features never import each
/// other, so `app.dart` provides the implementation.
abstract interface class AppSheets {
  /// The grade sheet for a review. Returns true when a grade was saved.
  Future<bool> grade(BuildContext context, String nodeId,
      {int? minutes, String? sessionId});

  /// Confirms minutes for a first reading. Returns true when saved.
  Future<bool> studied(BuildContext context, String nodeId,
      {int? minutes, String? sessionId});
}

final appSheetsProvider = Provider<AppSheets>(
    (ref) => throw UnimplementedError('appSheetsProvider is set in app.dart'));
