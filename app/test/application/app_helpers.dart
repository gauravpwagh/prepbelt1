import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prepbelt/app.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/platform/logging.dart';
import 'package:prepbelt/platform/notification_port.dart';

import '../data/helpers.dart';
import '../fakes.dart';

export '../data/helpers.dart';
export '../fakes.dart';

/// A [ProviderContainer] wired to [f]'s database, clock and IDs.
ProviderContainer containerFor(
  Fixture f, {
  List<dynamic> extra = const [],
  NotificationPort? notifications,
  FakeOpener? opener,
  FakeDeviceStatus? device,
  FakeFolderAccess? folders,
  FakeShareReceiver? shares,
  FakeSharer? sharer,
}) {
  final c = ProviderContainer(overrides: [
    logSinkProvider.overrideWithValue(
        FileLogSink(Directory.systemTemp.createTempSync('prepbelt_logs').path, now: f.clock.nowUtc)),
    fileSharerProvider.overrideWithValue(sharer ?? FakeSharer()),
    folderAccessProvider.overrideWithValue(folders ?? FakeFolderAccess()),
    shareReceiverProvider.overrideWithValue(shares ?? FakeShareReceiver()),
    notificationPortProvider.overrideWithValue(notifications ?? FakeNotifications()),
    sourceOpenerProvider.overrideWithValue(opener ?? FakeOpener()),
    deviceStatusProvider.overrideWithValue(device ?? FakeDeviceStatus()),
    appDatabaseProvider.overrideWithValue(f.db),
    clockProvider.overrideWithValue(f.clock),
    offsetFnProvider.overrideWithValue((_) => ist),
    tzIdProvider.overrideWithValue('Asia/Kolkata'),
    idGeneratorProvider.overrideWithValue(f.newId),
    ...appOverrides,
    ...extra.cast(),
  ]);
  c.read(onboardingDoneProvider.notifier).set(true);
  return c;
}
