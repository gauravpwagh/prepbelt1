import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';

import 'application/sort_share.dart';
import 'core/providers.dart';
import 'core/sheets.dart';
import 'core/slots.dart';
import 'core/theme/app_theme.dart';
import 'data/integrity.dart';
import 'features/capture/share_capture_sheet.dart';
import 'features/grade/grade_sheet.dart';
import 'features/grade/studied_sheet.dart';
import 'features/session/finish_sheet.dart';
import 'features/session/start_button.dart';
import 'features/settings/settings_providers.dart';
import 'platform/share_receiver.dart';
import 'router.dart';

final _log = Logger('app');

/// Wiring that only the app root may do: it imports every feature and fills
/// the extension points in `core/sheets.dart` and `core/slots.dart`.
final List<Override> appOverrides = [
  appSheetsProvider.overrideWithValue(const _Sheets()),
  planRowActionProvider.overrideWithValue(
      (context, nodeId, {required unread}) => StartButton(nodeId: nodeId)),
  todayBannersProvider.overrideWithValue(const [SessionBanner()]),
  reminderChangedProvider
      .overrideWith((ref) => ref.read(reconcileNotificationsProvider).call),
];

class _Sheets implements AppSheets {
  const _Sheets();

  @override
  Future<bool> grade(BuildContext context, String nodeId,
          {int? minutes, String? sessionId}) =>
      showGradeSheet(context, nodeId, minutes: minutes, sessionId: sessionId);

  @override
  Future<bool> studied(BuildContext context, String nodeId,
          {int? minutes, String? sessionId}) =>
      showStudiedSheet(context, nodeId, minutes: minutes, sessionId: sessionId);
}

/// Work that runs after the first frame (design §8 startup order).
final afterFirstFrameProvider =
    Provider<List<Future<void> Function()>>((ref) => [
          () async {
            final r = await runIntegrityCheck(ref.read(appDatabaseProvider));
            if (!r.ok) _log.severe('$r');
          },
          () => ref.read(reconcileNotificationsProvider)(),
      () async {
        if (ref.read(onboardingDoneProvider)) await ref.read(runBackupProvider).ifDue();
      },
          () async {
            final route =
                await ref.read(notificationPortProvider).launchRoute();
            if (route != null && ref.read(onboardingDoneProvider)) {
              ref.read(routerProvider).go(route);
            }
          },
        ]);

/// With an open session, launching or resuming the app brings back the
/// Finish sheet over Today (CUJ 3a).
Future<void> showFinishIfOpen(Ref ref) async {
  if (!ref.read(onboardingDoneProvider)) return;
  if (await ref.read(appDatabaseProvider).sessionsDao.open() == null) return;
  ref.read(routerProvider).go('/today');
  await Future<void>.delayed(Duration.zero);
  final context = rootNavigatorKey.currentContext;
  if (context != null && context.mounted) await showFinishSheet(context);
}

final showFinishIfOpenProvider =
    Provider<Future<void> Function()>((ref) => () => showFinishIfOpen(ref));

class PrepBeltApp extends ConsumerStatefulWidget {
  const PrepBeltApp({super.key});

  @override
  ConsumerState<PrepBeltApp> createState() => _PrepBeltAppState();
}

class _PrepBeltAppState extends ConsumerState<PrepBeltApp>
    with WidgetsBindingObserver {
  StreamSubscription<IncomingShare>? _shares;

  /// A share that arrived before onboarding finished (design §7).
  IncomingShare? _held;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shares = ref.read(shareReceiverProvider).shares.listen(_onShare);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final task in [
        ...ref.read(afterFirstFrameProvider),
        ref.read(showFinishIfOpenProvider),
      ]) {
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
    _shares?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onShare(IncomingShare share) async {
    if (!ref.read(onboardingDoneProvider)) {
      await _held?.discardFiles();
      _held = share;
      return;
    }
    await _route(share);
  }

  Future<void> _route(IncomingShare share) async {
    final kind = await sortShare(share, ref.read(localFilesProvider));
    final router = ref.read(routerProvider);
    switch (kind) {
      case ExamFileShare(:final copy):
        router.go('/exams');
        router.push('/exams/import', extra: copy.cachePath);
      case CaptureShare():
        router.go('/today');
        await Future<void>.delayed(Duration.zero);
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          await showShareCaptureSheet(context, share);
        }
      case UnsupportedShare():
        await share.discardFiles();
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Unsupported file')));
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new study day may have started while the app was in the background.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(todayProvider);
      ref.read(showFinishIfOpenProvider)();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onboardingDoneProvider, (_, done) {
      final held = _held;
      if (done && held != null) {
        _held = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _route(held));
      }
    });
    return MaterialApp.router(
      title: 'PrepBelt',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
