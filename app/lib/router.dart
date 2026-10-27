import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prep_core/prep_core.dart';

import 'core/providers.dart';
import 'features/capture/add_item_screen.dart';
import 'features/capture/split_sheet.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'features/exams/exams_screen.dart';
import 'features/exams/import_screen.dart';
import 'features/item/item_screen.dart';
import 'features/library/library_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/today/today_screen.dart';

/// The root navigator, for sheets shown from outside the widget tree
/// (the Finish sheet on launch and resume).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Routes from design §10. While onboarding is not done every location
/// redirects to `/onboarding` (plan item 49).
final routerProvider = Provider<GoRouter>((ref) {
  final done = ValueNotifier(ref.read(onboardingDoneProvider));
  ref.listen(onboardingDoneProvider, (_, v) => done.value = v);
  ref.onDispose(done.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/today',
    refreshListenable: done,
    redirect: (context, state) {
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!done.value) return atOnboarding ? null : '/onboarding';
      return atOnboarding ? '/today' : null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/today', builder: (context, state) => const TodayScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/library', builder: (context, state) => const LibraryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/exams', builder: (context, state) => const ExamsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, s) => ItemScreen(nodeId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/add',
        builder: (context, s) {
          final q = s.uri.queryParameters;
          return AddItemScreen(
            subjectId: q['subject'],
            parentId: q['parent'],
            kind: q['kind'] == null ? null : NodeKind.fromKey(q['kind']!),
            split: q['split'] == '1',
          );
        },
      ),
      GoRoute(
        path: '/add/split/:id',
        builder: (context, s) => SplitScreen(taskId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/diagnostics', builder: (context, state) => const DiagnosticsScreen()),
      GoRoute(
        path: '/exams/import',
        builder: (context, s) => ImportScreen(file: s.extra! as File),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class HomeShell extends StatelessWidget {
  const HomeShell(this.shell, {super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Exams'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      );
}
