# CLAUDE.md — PrepBelt

Context for Claude Code working in this repository. Read this first.

## What this is

PrepBelt is an offline Android app, built in Flutter, for competitive-exam preparation. It does four things:

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

| Milestone | State |
| --- | --- |
| M1 `packages/prep_core` (pure Dart rules and tests) | **Verified locally** (Flutter 3.41.6 / Dart 3.11.4): `dart analyze --fatal-infos` clean, 145 tests pass, coverage gate passes, `tool/sim/planner_check.py` exits 0. CI not yet confirmed green, so `flutter-version` is not pinned. |
| M2–M7 (app, data, UI, platform) | Not started |

## First tasks, in order

1.  **Resolve and check.** Run:

    ```sh
    flutter pub get
    dart run tool/check_imports.dart
    cd packages/prep_core
    dart analyze --fatal-infos
    dart test
    ```

    Fix every analyzer issue and every failing test.
    *   When a test's expected value disagrees with the rule in the design doc, the design doc wins.
    *   If the design itself looks wrong, ask the author.
2.  **Coverage.** Run `dart pub global run coverage:test_with_coverage` in `packages/prep_core`, then `dart run tool/coverage_gate.dart packages/prep_core/coverage/lcov.info` from the repository root. Add tests until the gate passes.
3.  **Push and pin.**
    *   Push to `https://github.com/gauravpwagh/prepbelt.git` (branch `main`).
    *   Once CI is green, pin `flutter-version` in `.github/workflows/ci.yaml` to the stable release that passed.
4.  **Start M2, the data layer**, following plan items 36–64 and design §2 and §8. Before you start:
    *   run `flutter create --org io.github.gauravpwagh --project-name prepbelt --platforms android app`;
    *   add `app` to the `workspace:` list in the root `pubspec.yaml`.

## Rules that must not be broken

*   `prep_core` imports no Flutter, Drift, platform code or `dart:io`. IDs and time-zone offsets are passed in.
*   Feature folders under `app/lib/features/` never import each other. `tool/check_imports.dart` enforces this.
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
