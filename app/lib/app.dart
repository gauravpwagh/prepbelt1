import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';

import 'core/providers.dart';
import 'core/sheets.dart';
import 'core/theme/app_theme.dart';
import 'data/integrity.dart';
import 'features/grade/grade_sheet.dart';
import 'features/grade/studied_sheet.dart';
import 'router.dart';

final _log = Logger('app');

/// Wiring that only the app root may do: it imports every feature and fills
/// the extension points in `core/sheets.dart` and `core/slots.dart`.
final List<Override> appOverrides = [
  appSheetsProvider.overrideWithValue(const _Sheets()),
];

class _Sheets implements AppSheets {
  const _Sheets();

  @override
  Future<bool> grade(BuildContext context, String nodeId, {int? minutes, String? sessionId}) =>
      showGradeSheet(context, nodeId, minutes: minutes, sessionId: sessionId);

  @override
  Future<bool> studied(BuildContext context, String nodeId,
          {int? minutes, String? sessionId}) =>
      showStudiedSheet(context, nodeId, minutes: minutes, sessionId: sessionId);
}

/// Work that runs after the first frame (design §8 startup order).
final afterFirstFrameProvider = Provider<List<Future<void> Function()>>((ref) => [
      () async {
        final r = await runIntegrityCheck(ref.read(appDatabaseProvider));
        if (!r.ok) _log.severe('$r');
      },
    ]);

class PrepBeltApp extends ConsumerStatefulWidget {
  const PrepBeltApp({super.key});

  @override
  ConsumerState<PrepBeltApp> createState() => _PrepBeltAppState();
}

class _PrepBeltAppState extends ConsumerState<PrepBeltApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final task in ref.read(afterFirstFrameProvider)) {
        try {
          await task();
        } catch (e, st) {
          _log.severe('After-first-frame task failed', e, st);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new study day may have started while the app was in the background.
    if (state == AppLifecycleState.resumed) ref.invalidate(todayProvider);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'PrepBelt',
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        routerConfig: ref.watch(routerProvider),
      );
}
