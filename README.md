# PrepBelt

An offline Android app (Flutter) for competitive-exam preparation. It tracks study items, schedules reviews with spaced repetition capped by exam dates, plans each day in minutes, and shows progress as martial-arts belts from Red to Green.

*   Design: [docs/designs/prepbelt.md](docs/designs/prepbelt.md)
*   Implementation plan: [docs/plans/prepbelt_implementation.md](docs/plans/prepbelt_implementation.md)

## Status

| Milestone | What | State |
| --- | --- | --- |
| M1 | `packages/prep_core`: belts, exam cap, planner, catch-up, share classifier, exam file format, with tests | Done: analyzer clean, tests and coverage gate pass, CI green |
| M2 | Data layer (Drift): schema v1, DAOs, `StudyWriter`, integrity check | Done (pending CI) |
| M3 | Core screens | Not started |
| M4 | Timer and notifications | Not started |
| M5 | Folder access, sources, Share to app | Not started |
| M6 / M6b | Backups, restore, catch-up UI; exam export/import | Not started |
| M7 | Diagnostics, logging, performance | Not started |

Local development currently uses Flutter 3.41.6; CI pins 3.47.8. On 3.41.6 the newest compatible Drift is 2.34.0, so `drift` and `drift_dev` are pinned to it in `app/pubspec.yaml`.

## Layout

```text
packages/prep_core/   Pure Dart rules (no Flutter, Drift or dart:io)
  lib/src/            belt, belt_policy, effective_due, deadline, planner,
                      catch_up, hierarchy, split, share_classifier,
                      exam_package, exam_import_rules, clock, local_date
  test/               unit, property and 90-day simulation tests
app/                  Flutter app (Android); lib/data/ is the Drift data layer
tool/                 check_imports.dart, coverage_gate.dart, sim/planner_check.py
docs/                 design and implementation plan
```

## Commands

Run these from the repository root with Flutter (stable) installed:

```sh
flutter pub get                                   # resolves the pub workspace
dart run tool/check_imports.dart                  # layering rules
(cd packages/prep_core && dart analyze --fatal-infos)
(cd packages/prep_core && dart test)              # all prep_core tests
(cd packages/prep_core && dart pub global activate coverage && dart pub global run coverage:test_with_coverage)
dart run tool/coverage_gate.dart packages/prep_core/coverage/lcov.info
python3 tool/sim/planner_check.py                 # cross-check of the planner maths
```

## Rules for contributors

*   `prep_core` must not import Flutter, Drift, platform code or `dart:io`. IDs and time-zone offsets are passed in.
*   Feature folders under `app/lib/features/` never import each other.
*   Only `SystemClock` reads the system time. Only `StudyWriter` writes events. The exam cap is applied when a date is read, never stored.
*   Belts and grades are stored by their string keys (`light_green`, `solid`), never by position.
*   **Adding a schema version (from M2):** bump `AppDatabase.currentSchema`, write the migration step, then run `dart run drift_dev make-migrations` and commit `app/drift_schemas/` and `app_database.steps.dart`.

## Licence

Not yet chosen.
