# CLAUDE.md — PrepBelt

Context for Claude Code working in this repository. Read this first.

## What this is

PrepBelt is an offline Android app, built in Flutter, for competitive-exam preparation. iOS (iPhone and iPad) and tablet layouts are in scope as milestones M8 and M9 (design D13, D14, §13); the design's open questions for them need the author's answers before M9. It does four things:

*   tracks study items under exams and subjects;
*   schedules reviews on a fixed belt ladder, capped by exam dates;
*   plans each day in minutes;
*   shows progress as belts, from Red to Green.

## Source of truth

1.  **[docs/designs/prepbelt.md](docs/designs/prepbelt.md)** is the approved design. Decisions D1–D12, the CUJs, the rules in §3–§8a, and the Risks section all live there. Do not change behaviour without updating it.
2.  **[docs/plans/prepbelt_implementation.md](docs/plans/prepbelt_implementation.md)** is the file-by-file plan, with item numbers, conventions and the verification plan. Build against it.
3.  If the code and the docs disagree, stop and ask the author. Don't guess.

The design came out of the Elephant-Goldfish Model (EGM) process: a brainstorm, a draft, and a consolidated review with fixes. To review a changed design, use `/egm:egm-review docs/designs/prepbelt.md` once the EGM plugin is installed.

## Status

Milestones M1–M8 are implemented; M9 (iOS) is planned. Local checks: `flutter analyze` clean, 145 `prep_core` tests and 88 app tests pass, the coverage gate passes (application 89.8%), `check_imports` passes. CI on `main` is green.

| Milestone | State |
| --- | --- |
| M1 `prep_core` | Done. CI pins `flutter-version` 3.47.8. |
| M2 data layer | Done: schema v1, DAOs, `StudyWriter`, integrity check, `drift_schema_v1.json`. |
| M3 core screens | Done: Today, Library, Item, Add/Split, Grade, Exams, onboarding. |
| M4 timer and notifications | Done: Start/Finish, ongoing and "Still reading?" notifications, reconcile, battery explainer. |
| M5 sources and sharing | Done: SAF folders, PDF browser, Open/Re-link, Share to app. |
| M6 backups and catch-up | Done: routine/safety/pre-migration backups, restore, catch-up card. |
| M6b exam files | Done: export, import with clash choices, copy as new attempt, archive and remove. |
| M7 diagnostics | Done: rotating logs, crash.log, Share logs, Diagnostics, 5k-item seed. |
| M8 adaptive layouts | Done: window classes, navigation rail, two panes for Today and Library, reading width (plan items 106–111). |
| M9 iOS | Planned (plan items 112–119); waits for the Android internal test and Open Questions 1–4. |

## Releasing

See [docs/release/RELEASE.md](docs/release/RELEASE.md): the upload key (`app/android/key.properties`, never committed), building the app bundle, Play Console answers, store text and the tester checklist. Release builds without `key.properties` are debug-signed and cannot be uploaded.

## Not yet verified (needs a device)

*   **Integration tests** (`app/integration_test/`): all three pass on the local Pixel 9 API 35 emulator (`flutter test integration_test -d emulator-5554`). The plan also asks for API 26 and API 36 runs; no such emulators exist here yet.
*   **Performance** (design NFR) must be measured in a profile build on a 4 GB phone with `test/perf/seed_5k.dart`. On the development PC (debug, in-memory) the plan input and build takes about 90 ms and the Library queries about 55 ms.
*   **Manual release checks** in the implementation plan's Verification Plan (Xiaomi/Oppo/Vivo, kill during a session, restore on a second device, sharing from real apps).
*   Local APK builds need the Android SDK licenses accepted (`flutter doctor --android-licenses`); CI builds the release APK and checks there is no INTERNET permission.

## Conventions added during implementation

*   Features never import each other. Sheets or widgets that one feature shows inside another go through `core/sheets.dart` (`AppSheets`) and `core/slots.dart`, which `app.dart` fills. Shared flows that only need providers live in `core/widgets/` (folder chooser, restore flow).
*   Only `platform/clock.dart` reads the system time; the log sink and the notification port take a clock.
*   `appDatabaseProvider` owns the database (closed on dispose). Restore closes it, swaps the file and invalidates the provider; `restoreBackupFor(container)` builds the restore use case from the root container for that reason.
*   `app/android/build.gradle.kts` carries a shim for `receive_sharing_intent` 1.9.0, which is written for AGP 9 (built-in Kotlin, compileSdk 37): it applies the Kotlin plugin and compiles it against SDK 36. Local Flutter 3.41.6 needs it; it is a no-op on CI's newer tooling.
*   Time zones load from `timezone/data/latest_all.dart` (`platform/time_zone.dart`): Android reports legacy names such as "Asia/Calcutta" that the default data set lacks.
*   Local Flutter is 3.41.6 while CI uses 3.47.8. On 3.41.6 the newest compatible Drift is 2.34.0, so `drift` and `drift_dev` are pinned exactly.

## Rules that must not be broken

*   `prep_core` imports no Flutter, Drift, platform code or `dart:io`. IDs and time-zone offsets are passed in.
*   Feature folders under `app/lib/features/` never import each other. `tool/check_imports.dart` enforces this.
*   In `app/lib`, only `data/` and `platform/` import `dart:io`; the layers above pass file paths and use `LocalFiles` (`platform/local_files.dart`). `tool/check_imports.dart` enforces this too.
*   **Single owners:**
    *   Only `SystemClock` reads the system time.
    *   Only `StudyWriter` writes events.
    *   `review_events` is append-only. The one exception is "Archive and remove", described in §8a.
*   The exam cap is applied when a date is read (`effectiveDue`) and is never stored.
*   Belts and grades are stored by their string keys, never by position.
*   **Release builds:**
    *   No `INTERNET` permission.
    *   No exact-alarm permissions.
    *   No `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
    *   `allowBackup="false"`.
*   **Native code:** the only hand-written Kotlin is the two-method `prepbelt/device` channel in `MainActivity` (plan item 41).

## Commands

```sh
flutter pub get
dart run tool/check_imports.dart
(cd packages/prep_core && dart analyze --fatal-infos && dart test)
python3 tool/sim/planner_check.py        # Goal 5 cross-check; must exit 0
```

## Author

vijwagh31@gmail.com. Ask before changing scope, the belt rules, or anything in the Decisions section.
