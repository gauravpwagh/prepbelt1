import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/application/finish_session.dart';
import 'package:prepbelt/application/start_session.dart';
import 'package:prepbelt/core/providers.dart';
import 'package:prepbelt/data/db/app_database.dart';
import 'package:prepbelt/data/db/converters.dart';
import 'package:prepbelt/platform/source_opener.dart';

import 'app_helpers.dart';

void main() {
  late Fixture f;
  late AppDatabase db;
  late ProviderContainer c;
  late FakeNotifications notes;
  late FakeOpener opener;

  setUp(() async {
    f = Fixture();
    db = f.db;
    notes = FakeNotifications();
    opener = FakeOpener();
    c = containerFor(f, notifications: notes, opener: opener);
    await f.seedTree();
  });
  tearDown(() async {
    c.dispose();
    await f.close();
  });

  Future<void> bookSource(String task, {String note = 'Printed copy, shelf 2'}) =>
      db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
          nodeId: task,
          sourceType: SourceType.book,
          linkStatus: LinkStatus.notLinked,
          locationNote: Value(note)));

  group('start_session', () {
    test('starts once, shows the clock and schedules "Still reading?"', () async {
      await bookSource('k1');
      await db.nodesDao
          .updateNode('st1', const StudyNodesCompanion(positionText: Value('pp. 1–20')));
      final r = await c.read(startSessionProvider)('st1');
      expect(r, isA<Started>());
      expect(notes.log, [
        'ongoing:k1 (printed) · st1 · pp. 1–20',
        'still:${t0.add(const Duration(minutes: 60)).toIso8601String()}',
      ]);
      expect(opener.opened, ['k1']); // the subtask inherits the task's source

      final again = await c.read(startSessionProvider)('st2');
      expect(again, isA<AlreadyOpen>());
      expect((again as AlreadyOpen).session.nodeId, 'st1');
    });

    test('a missing file marks the source needs_relink', () async {
      await db.sourcesDao.upsertSource(NodeSourcesCompanion.insert(
          nodeId: 'k2',
          sourceType: SourceType.pdf,
          linkStatus: LinkStatus.ok,
          fileName: const Value('a.pdf')));
      opener.result = OpenResult.notFound;
      final r = await c.read(startSessionProvider)('k2') as Started;
      expect(r.open, OpenResult.notFound);
      expect((await db.sourcesDao.sourceFor('k2'))!.linkStatus, LinkStatus.needsRelink);
    });

    test('no source opens nothing', () async {
      final r = await c.read(startSessionProvider)('k2') as Started;
      expect(r.open, isNull);
      expect(opener.opened, isEmpty);
    });
  });

  group('finish_session', () {
    test('CUJ 3a: 38 minutes later, confirm writes a first study with the session', () async {
      await c.read(startSessionProvider)('st1');
      f.clock.advance(const Duration(minutes: 38));
      final finish = c.read(finishSessionProvider);
      final open = (await finish.pending())!;
      expect([open.elapsedMinutes, open.prefill, open.stale, open.unread], [38, 38, false, true]);

      final out = await finish.confirm(open, 38);
      expect(out, isA<NeedsFirstStudy>());
      await c.read(markStudiedProvider)(out.nodeId, out.minutes, sessionId: out.sessionId);
      final s = (await db.select(db.studySessions).get()).single;
      expect([s.confirmedMinutes, s.edited, s.endedAtUtc], [38, false, t0.add(const Duration(minutes: 38))]);
      final e = (await db.eventsDao.eventsFor('st1')).single as FirstStudy;
      expect(e.sessionId, s.id);
      expect(notes.log.last, 'cancel');
      expect(await finish.pending(), isNull);
    });

    test('stale sessions pre-fill the base time; reviews need a grade', () async {
      await f.writer.writeFirstStudy('k2', 30);
      await c.read(startSessionProvider)('k2');
      f.clock.advance(const Duration(hours: 5));
      final finish = c.read(finishSessionProvider);
      final open = (await finish.pending())!;
      expect([open.stale, open.prefill, open.unread], [true, 30, false]);
      final out = await finish.confirm(open, 45);
      expect(out, isA<NeedsGrade>());
      expect((await db.select(db.studySessions).get()).single.edited, isTrue);
    });

    test('a clock that went backwards counts as 0 minutes', () async {
      await c.read(startSessionProvider)('st1');
      f.clock.advance(const Duration(minutes: -10));
      expect((await c.read(finishSessionProvider).pending())!.elapsedMinutes, 0);
    });

    test('discard ends the session and writes nothing else', () async {
      await c.read(startSessionProvider)('st1');
      final open = (await c.read(finishSessionProvider).pending())!;
      await c.read(discardSessionProvider)(open.session.id);
      final s = (await db.select(db.studySessions).get()).single;
      expect(s.discarded, isTrue);
      expect(await db.eventsDao.countFor('st1'), 0);
      expect(await db.sessionsDao.open(), isNull);
    });
  });

  group('reconcile_notifications', () {
    test('schedules the reminder and restores an open session', () async {
      await db.settingsDao.setReminderTime(6, 30);
      final reconcile = c.read(reconcileNotificationsProvider);
      await reconcile();
      expect(notes.log, ['reminder:6:30', 'cancel']);
      expect(reconcile.lastScheduled, t0);

      await c.read(startSessionProvider)('st1');
      notes.log.clear();
      f.clock.advance(const Duration(minutes: 10));
      await reconcile();
      expect(notes.log.first, 'reminder:6:30');
      expect(notes.log[1], startsWith('ongoing:k1 · st1'));
      expect(notes.log[2], startsWith('still:'));

      notes.log.clear();
      f.clock.advance(const Duration(hours: 2));
      await reconcile();
      expect(notes.log.where((l) => l.startsWith('still:')), isEmpty);
    });
  });
}
