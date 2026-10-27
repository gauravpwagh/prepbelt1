import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/add_item.dart';

/// Extension points that `app.dart` fills with widgets from other features,
/// so that features never import each other.

/// The trailing action of a Today plan row for [nodeId].
typedef RowActionBuilder = Widget Function(BuildContext context, String nodeId,
    {required bool unread});

final planRowActionProvider =
    Provider<RowActionBuilder?>((ref) => null);

/// Cards shown on Today above the plan list (catch-up, backup banner).
final todayBannersProvider = Provider<List<Widget>>((ref) => const []);

/// Open / Re-link buttons on an item's source card, for the task [taskId].
typedef SourceActionsBuilder = Widget Function(BuildContext context, String taskId);

final sourceActionsProvider = Provider<SourceActionsBuilder?>((ref) => null);

/// Picks a PDF from a granted folder for a new source (the in-app folder
/// browser). Null until folder access exists, or when the user cancels.
typedef PdfPicker = Future<NewSource?> Function(BuildContext context);

final pdfPickerProvider = Provider<PdfPicker?>((ref) => null);

/// Extra Settings rows from other features.
final settingsSectionsProvider = Provider<List<Widget>>((ref) => const []);

/// Onboarding steps after the first item (permissions, battery, backup
/// folder). Each builds a page and calls `next` when the user moves on.
typedef OnboardingStep = Widget Function(BuildContext context, VoidCallback next);

final onboardingStepsProvider = Provider<List<OnboardingStep>>((ref) => const []);

/// "Restore from backup" on the first onboarding page; null hides it.
final restoreLauncherProvider =
    Provider<Future<bool> Function(BuildContext context)?>((ref) => null);
