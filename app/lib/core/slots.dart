import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extension points that `app.dart` fills with widgets from other features,
/// so that features never import each other.

/// The trailing action of a Today plan row for [nodeId].
typedef RowActionBuilder = Widget Function(BuildContext context, String nodeId,
    {required bool unread});

final planRowActionProvider =
    Provider<RowActionBuilder?>((ref) => null);

/// The Item screen for [nodeId], shown in the right pane of Library and Today
/// on expanded windows (design D14).
typedef ItemDetailBuilder = Widget Function(String nodeId);

final itemDetailProvider = Provider<ItemDetailBuilder?>((ref) => null);

/// Cards shown on Today above the plan list (catch-up, backup banner).
final todayBannersProvider = Provider<List<Widget>>((ref) => const []);

/// Onboarding steps after the first item (permissions, battery, backup
/// folder). Each builds a page and calls `next` when the user moves on.
typedef OnboardingStep = Widget Function(BuildContext context, VoidCallback next);

final onboardingStepsProvider = Provider<List<OnboardingStep>>((ref) => const []);
