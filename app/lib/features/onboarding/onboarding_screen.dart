import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prep_core/prep_core.dart';

import '../../application/complete_onboarding.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';
import '../../core/slots.dart';
import '../../core/widgets/restore_flow.dart';
import '../../platform/folder_access.dart';
import 'onboarding_providers.dart';

/// CUJ 1: Start fresh (or Restore) → exam, subject, minutes, first item →
/// plan → permissions, battery, backup folder (later milestones add those
/// pages through [onboardingStepsProvider]).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _page = 0;

  void _next() => setState(() => _page++);

  void _finish() => ref.read(onboardingDoneProvider.notifier).set(true);

  @override
  Widget build(BuildContext context) {
    final steps = <OnboardingStep>[
      (context, next) => _PermissionStep(next: next),
      (context, next) => _BatteryStep(next: next),
      (context, next) => _BackupStep(next: next),
      ...ref.watch(onboardingStepsProvider),
    ];
    final Widget body;
    if (_page == 0) {
      body = _Welcome(
        onFresh: _next,
        onRestore: () async {
          if (await runRestoreFlow(context)) _finish();
        },
      );
    } else if (_page == 1) {
      body = _FirstExamForm(onDone: steps.isEmpty ? _finish : _next);
    } else if (_page - 2 < steps.length) {
      final last = _page - 2 == steps.length - 1;
      body = steps[_page - 2](context, last ? _finish : _next);
    } else {
      body = const SizedBox.shrink();
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
    return Scaffold(body: SafeArea(child: body));
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onFresh, this.onRestore});
  final VoidCallback onFresh;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        Text('PrepBelt', style: text.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Plan each day in minutes. Review on a belt ladder from Red to Green, '
            'always before your exam.', style: text.bodyLarge, textAlign: TextAlign.center),
        const Spacer(),
        FilledButton(
            key: const Key('onboarding-fresh'), onPressed: onFresh, child: const Text('Start fresh')),
        if (onRestore != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
              key: const Key('onboarding-restore'),
              onPressed: onRestore,
              child: const Text('Restore from backup')),
        ],
      ]),
    );
  }
}

class _FirstExamForm extends ConsumerStatefulWidget {
  const _FirstExamForm({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_FirstExamForm> createState() => _FirstExamFormState();
}

class _FirstExamFormState extends ConsumerState<_FirstExamForm> {
  final _exam = TextEditingController();
  final _subject = TextEditingController();
  final _minutes = TextEditingController(text: '${Defaults.dailyMinutes}');
  final _item = TextEditingController();
  LocalDate? _date;
  var _kind = TaskKind.reading;
  var _studied = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_exam, _subject, _minutes, _item]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final initial = _date ?? today.plusDays(120);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year, today.month, today.day).add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  Future<void> _submit() async {
    final minutes = int.tryParse(_minutes.text.trim());
    final error = validateOnboarding(
      exam: _exam.text,
      date: _date,
      subject: _subject.text,
      minutes: minutes,
      item: _item.text,
    );
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      await ref.read(completeOnboardingProvider)(OnboardingInput(
        examName: _exam.text,
        examDate: _date!,
        subjectName: _subject.text,
        dailyMinutes: minutes!,
        itemTitle: _item.text,
        taskKind: _kind,
        studiedToday: _studied,
      ));
      widget.onDone();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Your exam', style: Theme.of(context).textTheme.headlineSmall),
      gap,
      TextField(
        key: const Key('ob-exam'),
        controller: _exam,
        decoration: const InputDecoration(labelText: 'Exam (e.g. MPSC Prelims)'),
      ),
      gap,
      OutlinedButton.icon(
        key: const Key('ob-date'),
        icon: const Icon(Icons.event),
        label: Text(_date == null
            ? 'Exam date'
            : '${formatShortDate(_date!)} ${_date!.year}'),
        onPressed: _pickDate,
      ),
      gap,
      TextField(
        key: const Key('ob-subject'),
        controller: _subject,
        decoration: const InputDecoration(labelText: 'First subject (e.g. Polity)'),
      ),
      gap,
      TextField(
        key: const Key('ob-minutes'),
        controller: _minutes,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Study time per day', suffixText: 'min'),
      ),
      gap,
      TextField(
        key: const Key('ob-item'),
        controller: _item,
        decoration: const InputDecoration(labelText: 'First item (e.g. Laxmikant Ch 1–5)'),
      ),
      gap,
      SegmentedButton<TaskKind>(
        segments: [
          for (final k in TaskKind.values) ButtonSegment(value: k, label: Text(taskKindLabel(k))),
        ],
        selected: {_kind},
        onSelectionChanged: (s) => setState(() => _kind = s.single),
      ),
      CheckboxListTile(
        key: const Key('ob-studied'),
        contentPadding: EdgeInsets.zero,
        value: _studied,
        onChanged: (v) => setState(() => _studied = v ?? false),
        title: const Text('Studied today'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      FilledButton(
        key: const Key('ob-continue'),
        onPressed: _saving ? null : _submit,
        child: const Text('Continue'),
      ),
    ]);
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.primary,
    required this.onPrimary,
    required this.onSkip,
  });

  final IconData icon;
  final String title;
  final String body;
  final String primary;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        Icon(icon, size: 56),
        const SizedBox(height: 16),
        Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(body, style: text.bodyLarge, textAlign: TextAlign.center),
        const Spacer(),
        FilledButton(key: Key('step-$primary'), onPressed: onPrimary, child: Text(primary)),
        TextButton(key: const Key('step-skip'), onPressed: onSkip, child: const Text('Not now')),
      ]),
    );
  }
}

/// Asks once for the notification permission (Android 13+).
class _PermissionStep extends ConsumerWidget {
  const _PermissionStep({required this.next});
  final VoidCallback next;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StepPage(
        icon: Icons.notifications_active_outlined,
        title: 'Reminders and the study timer',
        body: 'PrepBelt reminds you when your plan is ready and shows a running clock '
            'while you study in another app.',
        primary: 'Allow notifications',
        onPrimary: () async {
          try {
            await ref.read(notificationPortProvider).requestPermission();
            await ref.read(reconcileNotificationsProvider)();
          } finally {
            next();
          }
        },
        onSkip: next,
      );
}

/// Explains battery optimisation and opens the system screen (design §9).
class _BatteryStep extends ConsumerWidget {
  const _BatteryStep({required this.next});
  final VoidCallback next;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StepPage(
        icon: Icons.battery_saver_outlined,
        title: 'Keep reminders on time',
        body: 'Some phones stop apps in the background, which can delay reminders. '
            "On the next screen, find PrepBelt and choose 'Don't optimise' "
            '(or "Unrestricted").',
        primary: 'Open battery settings',
        onPrimary: () async {
          try {
            await ref.read(deviceStatusProvider).openBatterySettings();
          } catch (_) {
            // Not every phone has this screen; the explainer is enough.
          } finally {
            next();
          }
        },
        onSkip: next,
      );
}

/// After the first item is saved, asks for a backup folder (CUJ 1). Skipping
/// leaves the Today banner as a reminder.
class _BackupStep extends ConsumerWidget {
  const _BackupStep({required this.next});
  final VoidCallback next;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _StepPage(
        icon: Icons.backup_outlined,
        title: 'Choose a backup folder',
        body: 'PrepBelt backs up every day. Pick a folder your cloud-drive app syncs, '
            'so a new phone can restore everything.',
        primary: 'Choose folder',
        onPrimary: () async {
          try {
            await ref.read(runBackupProvider).chooseFolder();
          } on FolderException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            }
          } finally {
            next();
          }
        },
        onSkip: next,
      );
}
