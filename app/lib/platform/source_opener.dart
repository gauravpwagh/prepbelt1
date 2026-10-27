// Opening a task's source in another app (design §7, plan item 68).
import '../data/db/app_database.dart';

enum OpenResult { ok, notFound, noApp }

abstract interface class SourceOpener {
  /// `not_linked` sources (printed books, other devices) open nothing and
  /// return [OpenResult.ok].
  Future<OpenResult> open(SourceRow source);
}

/// Used until folder access and intents are wired (and in tests).
class NoopSourceOpener implements SourceOpener {
  const NoopSourceOpener();

  @override
  Future<OpenResult> open(SourceRow source) async => OpenResult.ok;
}
