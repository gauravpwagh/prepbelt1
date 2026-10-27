# PrepBelt: Implementation Plan

*   **Design:** [docs/designs/prepbelt.md](../designs/prepbelt.md). Section numbers like §3 refer to that design document.
*   **Repository:** `https://github.com/gauravpwagh/prepbelt.git`, remote `origin`, branch `main`
*   **Status:** Approved for implementation. Re-audit fixes and the §8a review are applied. M1 (`prep_core`) is written; see the repository.
*   **Date:** 2026-10-26

--------------------------------------------------------------------------------

## Conventions

### Names and platform

*   **App name:** PrepBelt.
*   **Android application id and namespace:** `io.github.gauravpwagh.prepbelt`.
*   **Package names:** the Flutter app is `prepbelt`, and the shared core package is `prep_core`.
*   **Android SDK levels:** `minSdk = 26`, `targetSdk = 36`, `compileSdk = 36`.

### Repository and dependencies

*   **Repository layout:** a Dart pub workspace.
    *   The root `pubspec.yaml` lists `app` and `packages/prep_core`.
    *   Each member declares `resolution: workspace`.
*   **Dependency versions:** pinned by the committed `pubspec.lock`. Named versions are current as of 2026-10-26.
*   **What is committed and what is not:**
    *   `*.g.dart` files are not committed.
    *   `app/drift_schemas/` and the generated `app_database.steps.dart` are committed.

### Single owners

Each concern below has exactly one owner:

| Concern | Owner |
| --- | --- |
| Reading the system time | `SystemClock` |
| Today | `LocalDayClock` |
| Ladder | `Belt` |
| Exam cap | `effectiveDue` |
| Multi-exam rule | `resolveDeadline` |
| Wiring | `app/lib/core/providers.dart` |
| Folder access | `FolderAccess` |
| Event writes | `StudyWriter` |
| Exam file format | `ExamPackage` |

### Text, formats and native code

*   **User-facing text:** the grade definitions, explanation templates, summary format and notification text are specified in design §3, §4, §9 and §10.
*   **UI dates:** `d MMM` (for example "14 Mar"), formatted with `intl`.
*   **Native code:** exactly one small Kotlin `MethodChannel` (item 41). Everything else uses plugins.

--------------------------------------------------------------------------------

## Target Files to Create/Modify

### Repository root

1.  **`pubspec.yaml`** (Create)
    *   `name: prepbelt_workspace`
    *   `publish_to: none`
    *   `environment: sdk: ^3.6.0`
    *   `workspace: [app, packages/prep_core]`
    *   `dev_dependencies: coverage`
2.  **`analysis_options.yaml`** (Create)
    *   `include: package:flutter_lints/flutter.yaml`
    *   `analyzer.language: {strict-casts: true, strict-raw-types: true}`
    *   Rules: `avoid_print`, `prefer_final_locals`.
3.  **`tool/check_imports.dart`** (Create). Exits non-zero in two cases:
    *   **(a)** a file under `packages/prep_core/lib/` imports `dart:io`.
    *   **(b)** a file under `app/lib/features/<x>/` imports from `app/lib/features/<y>/`, where `y ≠ x`. Both relative imports and `package:prepbelt/features/<y>/…` imports count.
4.  **`tool/coverage_gate.dart`** (Create)
    *   **Usage:** `dart run tool/coverage_gate.dart <prep_core lcov> <app lcov>`. The thresholds are hard-coded.
    *   **Path normalisation:** each `SF:` path is turned into a repository-relative path.
        *   An absolute path containing `packages/prep_core/` keeps only the part from `packages/prep_core/` onwards.
        *   A relative path from the app's lcov file gets `app/` added in front.
    *   **Calculation:** sums `LF` and `LH` per file.
    *   **Fails when any of these is not met:**
        *   overall coverage of `packages/prep_core/lib/` is at least 90%;
        *   each of `belt_policy.dart`, `effective_due.dart`, `planner.dart`, `catch_up.dart` and `exam_package.dart` is at 100%;
        *   overall coverage of `app/lib/application/` is at least 80%.
    *   **Output:** prints a table of the results.
5.  **`.github/workflows/ci.yaml`** (Create)
    *   **Environment:**
        *   runner: `ubuntu-latest`;
        *   Flutter: `subosito/flutter-action@v2`, stable channel, with the version pinned in `env.FLUTTER_VERSION`;
        *   Java: `actions/setup-java@v4`, Java 17.
    *   **Steps:**
        1.  `flutter pub get`
        2.  `dart run tool/check_imports.dart`
        3.  `cd app && dart run build_runner build -d`
        4.  `flutter analyze`
        5.  `cd packages/prep_core && dart pub global activate coverage && dart pub global run coverage:test_with_coverage`
        6.  `cd app && flutter test --coverage`
        7.  `dart run tool/coverage_gate.dart packages/prep_core/coverage/lcov.info app/coverage/lcov.info`
        8.  `cd app && dart run drift_dev make-migrations && git diff --exit-code drift_schemas lib/data/db/app_database.steps.dart`
        9.  `cd app && flutter build apk --release`
        10. This step fails if the release APK contains the INTERNET permission:

            ```sh
            AAPT2="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)/aapt2"
            ! "$AAPT2" dump permissions app/build/app/outputs/flutter-apk/app-release.apk | grep -q 'android.permission.INTERNET'
            ```

6.  **`.gitignore`** (Create): Flutter defaults, plus `*.g.dart` and `coverage/`.
7.  **`README.md`** (Create): setup, commands, layering rules, how to add a schema version, and links to the design and this plan.
8.  **`docs/designs/prepbelt.md`**, **`docs/plans/prepbelt_implementation.md`** (Create): these documents.

### `packages/prep_core` (pure Dart)

9.  **`pubspec.yaml`** (Create)
    *   `name: prep_core`
    *   `resolution: workspace`
    *   `environment: sdk: ^3.6.0`
    *   `dependencies: meta, collection`
    *   `dev_dependencies: test` (property tests use seeded `dart:math` `Random`, so no extra package)
10. **`lib/prep_core.dart`** (Create): exports everything below.
11. **`lib/src/local_date.dart`** (Create): `LocalDate(year, month, day)` with these members:
    *   `plusDays`, `daysUntil`
    *   `compareTo`, `==`, `hashCode`
    *   `toIso()`, `LocalDate.parse()`
12. **`lib/src/clock.dart`** (Create)
    *   `abstract interface class Clock { DateTime nowUtc(); }`
    *   `typedef OffsetFn = Duration Function(DateTime utc);`
    *   `LocalDayClock(Clock, OffsetFn, int dayStartHour)` with:
        *   `today()`
        *   `dayOf(DateTime utc)`, computed as the date of `utc + offset(utc) − dayStartHour`.
    *   `FixedClock` with `advance(Duration)`.
13. **`lib/src/belt.dart`** (Create): `enum Belt { unread, red, orange, yellow, lightGreen, green }`.
    *   **Fields:** `key`, with stored keys `unread`, `red`, `orange`, `yellow`, `light_green`, `green`.
    *   **Members:** `step`, `interval?`, `shakyInterval?`, `label`, `up()`, `down()`, `fromKey()`.
    *   **Values:** taken from the ladder in design §3.
14. **`lib/src/grade.dart`** (Create): `enum Grade { forgot, shaky, solid }`, each with a `key` and a `definition` (design §10).
15. **`lib/src/events.dart`** (Create)
    *   `sealed class StudyEvent { id, nodeId, atUtc, localDate, tzId, Outcome? outcome }`, with these subclasses:
        *   `FirstStudy(int minutes, String? sessionId)`
        *   `Review(Grade grade, int minutes, String? sessionId)`
        *   `Reschedule(LocalDate newLadderDue, String batchId)`
        *   `Undo(String targetId)`, which has a null outcome.
    *   `Outcome(Belt beltBefore, Belt beltAfter, int? intervalDays, LocalDate? ladderDue, String explanation)`.
16. **`lib/src/item_state.dart`** (Create)
    *   `ItemState(belt, ladderDue?, lastReviewDate?, reviewCount)` and `ItemState.unread`.
    *   `deriveState(List<StudyEvent>)` applies the rules in design §2.
    *   `undoableEvent(List<StudyEvent>)` returns the event that Undo would reverse.
17. **`lib/src/belt_policy.dart`** (Create)
    *   `Outcome firstStudy(LocalDate date)`
    *   `Outcome review(ItemState state, Grade grade, LocalDate date)`
    *   `Outcome reschedule(ItemState state, LocalDate newDue)`
    *   `String dropMessage(Belt belt)`
    *   `const schedulerVersion = 1`
    *   Rules and explanation templates are in design §3.
18. **`lib/src/deadline.dart`** (Create)
    *   `ExamRef(id, name, LocalDate date, bool archived)`
    *   `Deadline(examId, examName, LocalDate date)`
    *   `resolveDeadline(Iterable<ExamRef> exams, LocalDate today)` returns the earliest exam that is not archived and has `date > today`.
19. **`lib/src/effective_due.dart`** (Create)
    *   `LocalDate? effectiveDue(ItemState state, Deadline? deadline)` returns:
        *   `ladderDue` when there is no deadline, or when `deadline − 1 ≤ lastReviewDate`;
        *   otherwise `min(ladderDue, deadline − 1)`.
    *   `String? capSuffix(ItemState state, Deadline? deadline, String Function(LocalDate) fmt)` returns the suffix only when the cap changed the date.
20. **`lib/src/hierarchy.dart`** (Create)
    *   **Enums:**
        *   `enum NodeKind { topic, task, subtask }`
        *   `enum TaskKind { reading, pyq, other }`, with `defaultBaseMinutes` of 30, 40 and 20.
    *   **Structure rules:**
        *   `canAttach(NodeKind child, NodeKind? parent)`
        *   `canAddChild(NodeKind parent, int parentEventCount)`: subtasks may be added under a task only when `parentEventCount == 0`.
        *   `canSplit(int eventCount)`
        *   `isReviewable(NodeKind kind, int liveChildCount)`
    *   **Sort key:** `SortKey(subjectOrder, topicOrder, taskOrder, subtaskOrder, createdAtUtc, id)`, implementing `Comparable` in that field order. This is design §4.
    *   **Rollup:**
        *   `Rollup(Belt? weakestStarted, Map<Belt, int> counts, int total)`
        *   `rollup(Iterable<Belt>)`
        *   `rollupLabel(Rollup)` returns "0/{total} started" or "Weakest: {label} · {greens}/{total} Green".
21. **`lib/src/split.dart`** (Create)
    *   **Specs:** `sealed SplitSpec` with three cases: `Chapters(from, to)`, `PageChunks(from, to, size)`, `Custom(titles)`.
    *   **`split(SplitSpec)`** returns `List<SplitPart(title, positionText)>`.
        *   `Chapters` produces positions "Ch 1", "Ch 2", …
        *   `PageChunks` produces positions "pp. 1–20", "pp. 21–40", …
        *   Throws `ArgumentError` if `from > to` or `size < 1`.
22. **`lib/src/planner.dart`** (Create)
    *   **Input types:**
        *   `PlanItem(nodeId, ItemState state, int baseMinutes, Deadline? deadline, SortKey sortKey, bool newestIsReschedule)`
        *   `DoneRow(nodeId, RowType type, int minutes)`
        *   `PlanInput(LocalDate today, int budget, List<PlanItem> items, List<DoneRow> done)`
    *   **Output types:**
        *   `enum RowType { review, firstRead }`
        *   `enum Reason { due, overdue, deadlineRisk, catchUp, firstRead }`
        *   `PlanRow(nodeId, type, minutes, reason)`
        *   `DayPlan(rows, reviewMinutes, firstReadMinutes, waitingCount, waitingMinutes, waitingNodeIds, reviewShare, splitSuggested, summary)`
    *   **Functions:**
        *   `reviewCost(int base)`
        *   `buildPlan(PlanInput)` follows design §4. It includes subtracting done rows and the second pass. Done items are never selected again.
23. **`lib/src/catch_up.dart`** (Create)
    *   `Proposal(List<(String nodeId, LocalDate date)> assignments, int days, Map<String, int> wontFit)`
    *   `bool shouldOffer(DayPlan plan)` returns `plan.waitingCount > 0`.
    *   `Proposal propose(PlanInput input, DayPlan today, {int horizon = 14})`. It assigns only `today.waitingNodeIds`, to days `d = 1…13`, following design §4.
24. **`lib/src/defaults.dart`** (Create): constants.

    | Constant | Value |
    | --- | --- |
    | `dailyMinutes` | 90 (range 15–600) |
    | `dayStartHour` | 4 |
    | `baseMin` / `baseMax` | 10 / 50 |
    | `reserveFraction` | 0.30 |
    | `reviewFraction` | 0.25 |
    | `minReviewMinutes` | 3 |
    | `catchUpHorizon` | 14 |
    | `deadlineRiskDays` | 7 |
    | `staleSession(base)` | `max(240, 3 * base)` |
    | `stillReadingAfter(base)` | `2 * base` |

25. **`lib/src/share_classifier.dart`** (Create)
    *   **Types:**
        *   `SharedFile(String? name, int? size)`
        *   `enum SourceType`, which mirrors `source_type`
        *   `ShareDraft(title, SourceType type, url?, excerpt?, SharedFile? file)`
    *   **`classifyShare({String? text, String? subject, List<SharedFile> files = const []})`**:
        *   **Drafts produced:** one per file. If there is text, one more draft for the text. A share with only text gives exactly one draft.
        *   **URL:** the first `https?://\S+` match in the text.
        *   **AI-chat detection:** the host, with any leading `www.` removed, matches a list entry if it equals the entry or ends with `.` followed by the entry. The entries are `claude.ai`, `chatgpt.com`, `chat.openai.com`, `gemini.google.com`, `perplexity.ai` and `copilot.microsoft.com`.
        *   **Excerpt:** the text, capped at 20,000 characters.
        *   **Title fallbacks**, in this order:
            1.  the subject;
            2.  the first non-empty line, cut to 80 characters with "…";
            3.  the file name without its extension;
            4.  the URL host;
            5.  "Shared PDF" for a file, "Shared note" for text.
        *   **Task kind:** always `reading`.
26. **`lib/src/exam_package.dart`** and **`lib/src/exam_import_rules.dart`** (Create). These implement the pure model and the rules for design §8a.
    *   **Model (`exam_package.dart`):**
        *   Types: `ExamPackage`, `PkgExam`, `PkgSubject`, `PkgNode`, `PkgSource`, `PkgEvent`, and the enum `PackageMode`.
        *   `PkgEvent.toStudyEvent()` converts an imported event so `deriveState` can use it.
        *   `toJson` / `encode` write snake_case keys explicitly.
        *   `ExamPackage.decode` refuses files over 20 MB, files that aren't JSON, and files whose `format` isn't `prepbelt-exam`. Unknown enum values throw `FormatException`.
    *   **Rules (`exam_import_rules.dart`):**
        *   `validate`: every check listed in §8a step 1. A newer `format_version` returns only "Update the app…".
        *   `applyPrivacy(includeNotes)`: drops excerpts, location notes, `ai_chat` URLs and `also_used_by`.
        *   `planIds(package, ExistingIds)`: decides per subject (`linkExisting` / `keepIds` / `copy`) and says whether the exam needs a new id.
        *   `remapSubjects(package, subjectIds, newId)`: gives new IDs to the chosen subjects, their nodes and their events. It also rewrites references, `undoes_event_id` and batch IDs.
        *   `allIds`, `firstFreeName` and `shiftTopLevel`: helpers.

#### `prep_core` tests (`packages/prep_core/test/`)

27. **`belt_policy_test.dart`**: every belt × grade, plus `firstStudy` and `reschedule`, checking the outcomes and the exact explanation strings.
28. **`effective_due_test.dart`**: the expected values in the EffectiveDue row of design §12, and `capSuffix`.
29. **`deadline_test.dart`**: two exams; an archived exam; an exam today, which is ignored; a past exam; no exam.
30. **`item_state_test.dart`**: no events; one event; an undone review; two undos in a row; an undone first study; `undoableEvent` skipping undo events.
31. **`properties_test.dart`**: the properties listed in design §12, run over seeded random sequences (200 review chains, 2,000 cap cases, 300 random plans).
32. **`hierarchy_test.dart`**: the `canAttach` matrix, `canAddChild`, `canSplit`, reviewability, `SortKey` ordering, and the rollup labels.
33. **`split_test.dart`**: a short last chunk, a single chapter, and invalid ranges.
34. **`planner_test.dart`**:
    *   **Budget:** the plan stays within budget, counting done rows.
    *   **Reserve:** the reserve fits the next unread item, both at 90/30 and at 30/30.
    *   **Selection:** the second pass; each reason rule; done items are excluded.
    *   **Output:** the summary strings, and deterministic order.
35. **`catch_up_test.dart`**:
    *   `shouldOffer`;
    *   today's plan is not changed;
    *   capacity starts at `d = 1`;
    *   assignments stay within the `latest` bound;
    *   `wontFit` counts, including exam-tomorrow items;
    *   items with no deadline stay waiting;
    *   the number of days.
36. **`clock_test.dart`**: 03:59 vs 04:00 IST; an offset change; Europe/London across 29 Mar 2026 and 25 Oct 2026, using a fixed offset table in the test.
37. **`share_classifier_test.dart`**:
    *   each AI-chat host, with and without `www.`;
    *   a plain web URL;
    *   text with no URL;
    *   two URLs, where the first wins;
    *   two PDFs;
    *   each title fallback, including "Shared PDF";
    *   the 80-character and 20,000-character caps.
38. **`exam_package_test.dart`**: covers each of the following.
    *   **JSON:** a round trip; structure files have no `events` key; decode errors.
    *   **Validation:** every `validate` rule.
    *   **Privacy:** `applyPrivacy`.
    *   **`planIds`:** structure mode, a fresh phone, an existing subject, node and event ID clashes, and an exam ID clash.
    *   **`remapSubjects`:** no old ID survives; other subjects are untouched; undo targets still point to the right event; derived state is unchanged; batches are remapped consistently.
    *   **Helpers:** `firstFreeName` and `shiftTopLevel`.
39. **`simulation_test.dart`**: 300 items, 2 exams (days 45 and 80, sharing one subject), a budget of 90, 15% missed days, grades split 60/30/10, catch-up accepted whenever offered, over 90 days. Runs seeds 1–20 and asserts Goal 5 as restated by D12. The same model is ported to `tool/sim/planner_check.py`.

### `app/` setup and Android

40. **Generate** (Create)
    *   Run `flutter create --org io.github.gauravpwagh --project-name prepbelt --platforms android app`.
    *   Replace `app/analysis_options.yaml` with `include: ../analysis_options.yaml`.
41. **`app/android/app/src/main/kotlin/io/github/gauravpwagh/prepbelt/MainActivity.kt`** (Modify). About 40 lines.
    *   `MainActivity : FlutterActivity()` registers a `MethodChannel("prepbelt/device")` in `configureFlutterEngine`.
    *   **`isIgnoringBatteryOptimizations`** returns `(getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)`.
    *   **`takeShareSubject`** returns, then clears, the `Intent.EXTRA_SUBJECT` that was stored from the last `ACTION_SEND`/`ACTION_SEND_MULTIPLE` intent. It is stored in `onCreate` and in `onNewIntent`, where the code then calls `super.onNewIntent(intent)`.
    *   This channel exists for two reasons. `permission_handler` only reports the battery state when `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is declared, which design NFR forbids. And `receive_sharing_intent` does not pass `EXTRA_SUBJECT` through.
42. **`app/pubspec.yaml`** (Modify)
    *   **Package settings:** `resolution: workspace` and `publish_to: none`.
    *   **Dependencies:**
        *   `prep_core: any`
        *   state, routing and data: `flutter_riverpod`, `go_router`, `drift`, `drift_flutter`, `sqlite3` (for the raw pre-migration check)
        *   notifications and time: `flutter_local_notifications`, `timezone`, `flutter_timezone`
        *   opening and sharing: `url_launcher`, `android_intent_plus` (6.1.0), `saf` (^2.1.2), `receive_sharing_intent` (1.9.0)
        *   utilities: `device_info_plus`, `uuid`, `logging`, `path_provider`, `path`, `archive`, `share_plus`, `intl`
    *   **Dev dependencies:** `drift_dev`, `build_runner`, `flutter_test`, `integration_test`, `flutter_lints`.
    *   **Not used:**
        *   `sqlite3_flutter_libs`, which is end-of-life;
        *   `permission_handler`, because the notification permission comes from `flutter_local_notifications` and the battery state comes from item 41.
43. **`app/build.yaml`** (Create)

    ```yaml
    targets:
      $default:
        builders:
          drift_dev:
            options:
              databases:
                app_database: lib/data/db/app_database.dart
              schema_dir: drift_schemas/
              test_dir: test/drift/
    ```

44. **`app/android/app/build.gradle.kts`** (Modify)
    *   `namespace = "io.github.gauravpwagh.prepbelt"`
    *   `compileSdk = 36`
    *   `defaultConfig { applicationId = "io.github.gauravpwagh.prepbelt"; minSdk = 26; targetSdk = 36 }`
    *   `compileOptions { isCoreLibraryDesugaringEnabled = true; sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }`
    *   `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`
45. **`app/android/app/src/main/AndroidManifest.xml`** (Modify)
    *   **`<application>` attributes:** `android:allowBackup="false"` and `android:label="PrepBelt"`.
    *   **Permissions:** `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED` only.
    *   **Receivers from `flutter_local_notifications`:**
        *   `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver` (`exported=false`)
        *   `ScheduledNotificationBootReceiver` (`exported=false`), with filters for `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON` and `com.htc.intent.action.QUICKBOOT_POWERON`
        *   `ActionBroadcastReceiver` (`exported=false`)
    *   **`<queries>`:** `VIEW` with `https`, and `VIEW` with `application/pdf`.
    *   **`MainActivity`:**
        *   `android:launchMode="singleTask"`.
        *   Intent filters, each with `category.DEFAULT`:
            *   `SEND` with `text/plain`
            *   `SEND` with `application/pdf`
            *   `SEND_MULTIPLE` with `application/pdf`
            *   `SEND` with `application/json`
            *   `SEND` with `application/octet-stream`

### `app/lib/core`

46. **`main.dart`** (Create)
    1.  `await bootstrap()`.
    2.  `runApp(ProviderScope(overrides: bootstrapOverrides, child: const PrepBeltApp()))`.
47. **`bootstrap.dart`** (Create). Runs before the first frame, in this order:
    1.  `WidgetsFlutterBinding.ensureInitialized()`
    2.  `initLogging()`
    3.  Install the error hooks.
    4.  `tz.initializeTimeZones()`, then `FlutterTimezone.getLocalTimezone()`, and use its `.identifier`.
    5.  `PreMigrationBackup.runIfNeeded(dbFile)`
    6.  Open `AppDatabase`.
    7.  `ensureInbox()`
    8.  If onboarding is done, run `BuildTodayPlan.get()`.

    It returns the provider overrides.
48. **`app.dart`** (Create)
    *   **Shell:** `MaterialApp.router` with the light and dark themes and the router.
    *   **After the first frame**, run in order:
        1.  `RunIntegrityCheck`
        2.  `ReconcileNotifications`
        3.  `RunBackup.ifDue`
    *   **Session listener:** on app resume, shows the Finish sheet if a session is open.
    *   **Share listener:** listens to `ShareReceiver.shares` and routes each share:
        *   an exam file goes to the Import screen;
        *   anything else goes to the Share capture sheet.

        If onboarding is not done, it holds the latest share until onboarding finishes.
49. **`router.dart`** (Create)
    *   **Routes:** the ones in design §10, plus `/exams/import`.
    *   **Redirect:** goes to `/onboarding` while `onboarding_done` is false.
    *   **Notifications:** the notification payload is a route string, passed to `router.go`.
50. **`core/providers.dart`** (Create): the root providers.
    *   **Database and data access:** the database, the DAOs and `StudyWriter`.
    *   **Time and IDs:** `clockProvider` (`SystemClock`); `localDayClockProvider`, whose offset is `tz.local.timeZone(ms).offset`; `idGeneratorProvider` (`Uuid().v7`).
    *   **Platform and app logic:** the platform ports and the use cases.
    *   **Restore:** restore calls `ref.invalidate(appDatabaseProvider)`.
51. **`core/theme/app_theme.dart`** and **`belt_colors.dart`** (Create)
    *   **Theme:** Material 3, light and dark.
    *   **Belt colours:**

        | Belt | Colour |
        | --- | --- |
        | red | `#C62828` |
        | orange | `#EF6C00` |
        | yellow | `#F9A825` |
        | light green | `#7CB342` |
        | green | `#2E7D32` |
        | unread | `#9E9E9E` |

    *   **Contrast:** the text colour on each chip is chosen for a contrast ratio of at least 3:1.
52. **`core/widgets/belt_chip.dart`**, **`rollup_bar.dart`**, **`minutes_text.dart`**, and **`core/format.dart`** (Create)
    *   `belt_chip.dart`: "{label} · {step}/5"
    *   `rollup_bar.dart`: a stacked bar
    *   `format.dart`: `formatShortDate` using `DateFormat('d MMM')`

### `app/lib/data`

53. **`db/converters.dart`** (Create): `UtcMillisConverter` (int), `LocalDateConverter` (ISO text), `BeltConverter`, `GradeConverter`.
54. **`db/tables.dart`** (Create): the tables from design §2.
    *   **Columns:**
        *   Instant columns use `IntColumn().map(UtcMillisConverter())`.
        *   `source_folders.tree_uri` is `nullable()`. Null means "pick again".
    *   **Checks:**
        *   `base_minutes` is between 10 and 50, or null for topics.
        *   A per-`event_type` CHECK enforces the event table in design §2. For example, `first_study` requires `minutes` to be set and allows `session_id` to be null.
        *   `interval_days` is null or at least 1.
    *   **Indexes:**
        *   `item_state(ladder_due)`, `item_state(belt)`
        *   `study_nodes(parent_id)`, `study_nodes(subject_id)`
        *   `review_events(node_id, at_utc)`
        *   a partial unique index on `study_sessions` where `ended_at_utc IS NULL`, so at most one session is open
55. **`db/app_database.dart`** (Create)
    *   **Class:** `@DriftDatabase(...)` with `static const currentSchema = 1;` and `int get schemaVersion => currentSchema;`.
    *   **File:** opened with `driftDatabase(name: 'prepbelt')`. On Android it lands at `files/app_flutter/prepbelt.sqlite`.
    *   **`beforeOpen`:** sets `foreign_keys = ON`, `journal_mode = WAL` and `busy_timeout = 5000`.
    *   **Migrations:** `stepByStep(...)`, with no destructive fallback.
56. **`db/app_database.steps.dart`** and **`app/drift_schemas/app_database/drift_schema_v1.json`** (Generated, committed).
57. **`daos/`** (Create). One file per DAO. Each returns `prep_core` types.

    | DAO | Methods |
    | --- | --- |
    | `exams_dao` | CRUD, `watchActive`, `examsForSubject` |
    | `subjects_dao` | CRUD, `ensureInbox`, `link`/`unlink`, `findByName` |
    | `nodes_dao` | CRUD with soft delete; `children`; `watchTree`; `leafBelts` (recursive CTE); `sortKeys` |
    | `sources_dao` | CRUD; folders CRUD; `relinkCandidates`, which returns `needs_relink` sources plus `not_linked` PDFs that have a `file_name` |
    | `events_dao` | `eventsFor`, `lastN`, `byBatch`, `countFor(nodeId)` (no update or delete) |
    | `item_state_dao` | `upsert`, `watch`, `allReviewable` |
    | `sessions_dao` | `open`, `start`, `finish`, `discard` |
    | `plans_dao` | `planFor`, `savePlan`, `markDone`, `clearDone`, `doneRows`, `setCatchUp` |
    | `settings_dao` | typed get and set for the settings keys in design §2 |

58. **`study_writer.dart`** (Create). The only code that writes events. Each method runs in one transaction that does three things: appends the event, upserts `item_state` using `deriveState`, and updates the plan row.

    | Method | Notes |
    | --- | --- |
    | `writeFirstStudy(nodeId, minutes, sessionId?)` | |
    | `writeReview(nodeId, grade, minutes, sessionId?)` | |
    | `writeUndoLatest(nodeId)` | Refuses when `undoableEvent` returns null |
    | `writeRescheduleBatch(assignments, batchId)` | |
    | `undoBatch(batchId)` | |
    | `deleteSubjectsHard(Set<String> subjectIds)` | The only hard delete, used by "Archive and remove". Deletes in this order: plan rows, events, `study_sessions`, `item_state`, sources, nodes, `exam_subjects`, subjects. In the same transaction it clears `last_used_subject_id` and `last_used_topic_id` when they point at deleted rows. |

59. **`backup/backup_service.dart`** (Create)
    *   **Methods:** `runRoutine()`, `writeSafety()`, `writeTo(prefix)`. They follow design §8.
    *   **Destination:**
        *   with a backup folder chosen: `FolderAccess.writeFile`, keeping 7 backups;
        *   without one: `getApplicationSupportDirectory()/backups`, keeping 3.
60. **`backup/pre_migration_backup.dart`** (Create). `runIfNeeded(File db)`:
    1.  Opens the file with `sqlite3.open(path, mode: OpenMode.readOnly)`.
    2.  Reads `user_version`.
    3.  If that is below `AppDatabase.currentSchema`, runs `VACUUM INTO` to a cache file named `prepbelt-premigration-…` and copies it out.
    4.  Closes the file.
61. **`backup/restore_service.dart`** (Create). Follows design §8.
    *   **Result:** sealed `RestoreResult`: `ok | unknownFormat | newerSchema | corrupt | ioError`.
    *   **After the file swap:**
        *   sets every `source_folders.tree_uri` to null;
        *   clears `backup_folder_id`;
        *   sets PDF sources to `needs_relink`.
62. **`exchange/exam_exporter.dart`** (Create). `Future<File> export(examId, PackageMode mode, {required bool includeNotes})`.
    *   **What goes in:** builds an `ExamPackage` from the database, following design §8a.
        *   The Inbox is never included.
        *   `folder_id` and `relative_path` are left out.
        *   `session_id` is dropped.
        *   `also_used_by` is filled in.
    *   **Privacy:** then applies `applyPrivacy(includeNotes)`.
    *   **Output:** writes `<exam name>.prepbelt.json` (pretty JSON) to the cache.
63. **`exchange/exam_importer.dart`** (Create)
    *   **`preview(File) → ImportPreview`**
        *   Runs `decode` and `validate`.
        *   Builds `ExistingIds` from the database, including soft-deleted rows and event IDs, then runs `planIds`.
        *   Returns: the exam name and date; subject and item counts; the mode; the per-subject actions; and, for each subject that will be inserted, any name clash, together with the other exams that use the clashing subject.
        *   The Inbox is never offered as a clash target.
    *   **`import(ImportPreview, examName, examDate, Map<subjectId, ClashChoice>, {bool forceSeparate = false})`**
        *   Runs in one transaction.
        *   Applies `remapSubjects` to the subjects marked `copy`, and gives the exam a new ID if needed.
        *   Subjects marked `linkExisting`: links the exam to the existing subject and skips that subject's nodes, sources and events.
        *   "Add to existing": inserts no subject row, sets `subject_id` on every imported node to the existing subject, and applies `shiftTopLevel`.
        *   "Keep separate" (or `forceSeparate`): inserts the subject under `firstFreeName`, with `is_inbox = false`.
        *   PDF sources are set to `not_linked`.
        *   Events are inserted, then `item_state` is derived for each node.
        *   Returns the new exam ID.
64. **`integrity.dart`** (Create): runs `PRAGMA integrity_check`, `PRAGMA foreign_key_check` and a count of open sessions.

### `app/lib/platform`

65. **`clock.dart`** (Create): `SystemClock`. The only place that calls `DateTime.now()`.
66. **`notification_port.dart`** (Create). Built on `flutter_local_notifications`.
    *   **Channels:**
        *   `reminders`: default importance;
        *   `session`: low importance, no sound.
    *   **Methods:**
        *   `init(onTap)`
        *   `showOngoingSession(id, title, startedAtUtc)`:
            *   `ongoing: true`, `autoCancel: false`
            *   `usesChronometer: true`, `when: startedAt.millisecondsSinceEpoch`
            *   one action: `AndroidNotificationAction('done', 'Done', showsUserInterface: true)`
        *   `scheduleStillReading(at, title)`: `zonedSchedule` with `AndroidScheduleMode.inexactAllowWhileIdle`
        *   `scheduleDailyReminder(TimeOfDay)`: the same, plus `matchDateTimeComponents: DateTimeComponents.time`
        *   `cancelSession()`
        *   `requestPermission()` uses `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission()`.
        *   `permissionGranted()` uses `areNotificationsEnabled()`.
        *   `pending()`
67. **`folder_access.dart`** (Create). Interface `FolderAccess`, implemented by `SafFolderAccess` on `saf` ^2.1.2.
    *   **Methods:**
        *   `pickFolder() → FolderGrant?`
        *   `persisted() → List<String>`
        *   `walk(treeUri) → Stream<FolderEntry(relativePath, name, size, uri)>`
        *   `resolve(treeUri, relativePath) → String?` (walks the folder and caches results for the session)
        *   `writeFile(treeUri, name, localPath)`
        *   `delete(uri)`
        *   `copyToLocal(uri, localPath)`
    *   **Errors:** `SafPermissionException` becomes `FolderError.noPermission`, and `SafNotFoundException` becomes `FolderError.notFound`.
68. **`source_opener.dart`** (Create). `open(Source) → OpenResult (ok | notFound | noApp)`.
    *   **File sources:**
        1.  `uri = FolderAccess.resolve(...)`. If that returns null or throws `FolderError`, return `notFound`.
        2.  Build an `AndroidIntent` with `action: 'action_view'`, `data: uri`, `type` and flags `FLAG_GRANT_READ_URI_PERMISSION` and `FLAG_ACTIVITY_NEW_TASK`.
        3.  If `canResolveActivity()` returns false, return `noApp`.
        4.  Call `launch()`. If it throws `PlatformException`, return `noApp`.
    *   **URL sources:** `launchUrl(mode: externalApplication)`. A `false` result returns `noApp`.
    *   **`not_linked` sources:** return `ok` and do nothing.
69. **`device_status.dart`** (Create)
    *   `batteryOptimizationIgnored()` calls `prepbelt/device#isIgnoringBatteryOptimizations`.
    *   `openBatterySettings()` sends an `AndroidIntent` with `action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS'`.
    *   `deviceSummary()` uses `device_info_plus`.
70. **`share_receiver.dart`** (Create)
    *   **Interface:** `ShareReceiver` with a `Stream<IncomingShare> shares`.
    *   **Shared data types:**
        *   `IncomingShare(text?, subject?, List<SharedCopy> files)`
        *   `SharedCopy(String cachePath, String? name, int? size)`
    *   **Implementation:** `IntentShareReceiver`, built on `receive_sharing_intent` 1.9.0.
        *   **Sources:** merges `getInitialMedia()` and `getMediaStream()`.
        *   **Text:** comes from text and url items.
        *   **Files:** the plugin copies each shared file into the app cache, and `path` is that copy. The name is `basename(path)`; a name matching `^FILE_\d+\.` counts as unknown (null). The size is `File(path).lengthSync()`.
        *   **Subject:** read from `prepbelt/device#takeShareSubject`.
        *   **Cleanup:** calls `reset()` after delivering each share.
        *   **Known limitation:** a single `SEND` with both a PDF and text delivers only the file.
    *   **Routing (in `app.dart`):** each shared file is sorted as follows.
        *   A file of 20 MB or less that parses as an exam file goes to the Import screen.
        *   A PDF goes to the capture sheet.
        *   Anything else shows "Unsupported file".
        *   Exam files that arrive before onboarding are held, the same way as captures.
    *   **Cache copies:** deleted after capture or import finishes, or when the sheet is dismissed. The design's "never copied into the app" means never *kept*.
71. **`logging.dart`** (Create)
    *   **Log files:** a rotating `FileLogSink`, 2 files of 1 MB each, in `getApplicationSupportDirectory()/logs`.
    *   **Crashes:** written to `crash.log`.
    *   **`shareLogs()`:** zips the logs, `crash.log` and `meta.txt` (versions, device, time zone, permission states) with `archive`, then shares the zip through `share_plus`.

105. **`local_files.dart`** (Create, added after M7). `LocalFiles` (`length`, `readString`, `writeString`, `readHead`, `deleteIfExists`) with `IoLocalFiles`, plus `appCacheDir()` and `appPrivateDir()`.
    *   **Rule:** in `app/lib`, only `data/` and `platform/` import `dart:io`. Everything above them names local files by path (`String`) and goes through `LocalFiles`, `FolderAccess` or `FileSharer`. `tool/check_imports.dart` enforces this, so a port to iOS or the web swaps only those two layers.

### `app/lib/application` (use cases, one class each)

72. **`start_session.dart`**
    1.  Refuses if a session is already open.
    2.  Inserts the session and shows the ongoing notification.
    3.  Schedules "Still reading?".
    4.  Calls `SourceOpener.open`. A `notFound` result sets the source to `needs_relink` and is returned to the UI.
73. **`finish_session.dart`**
    *   Applies the stale rule. A negative elapsed time counts as 0.
    *   Returns `NeedsFirstStudy(minutes)` or `NeedsGrade(minutes)`.
74. **`discard_session.dart`**: discards the open session.
75. **`mark_studied.dart`**
    *   **Minutes:** if there is no session, they default to the base time and can be edited.
    *   **Writing:** calls `writeFirstStudy`.
    *   **Plan row:** if the item is not in today's plan, adds a done `first_read` row.
76. **`grade_review.dart`**: if there is no session, the minutes default to the review cost.
77. **`undo_latest.dart`**: undoes the item's latest event.
78. **`add_item.dart`**
    *   **Validation:** checks `canAttach`. A subtask also requires `canAddChild` on its parent, where the event count comes from `EventsDao.countFor`.
    *   **Defaults:** with no subject, the item goes to the Inbox. It gets the default base time.
    *   **Remembers** the last-used subject and topic.
79. **`split_item.dart`**: requires `canSplit`, then creates the subtasks.
80. **`build_today_plan.dart`**
    *   `get()` returns the saved plan, or builds and saves one.
    *   `refresh()` builds a new plan using the done rows as `PlanInput.done`.
    *   **Input** comes from `item_state`, the nodes and their `SortKey`s, and the exams through `resolveDeadline`.
81. **`accept_catch_up.dart`**: runs `propose`, then `writeRescheduleBatch`, then `refresh()`.
82. **`undo_catch_up.dart`**: runs `undoBatch`, then `refresh()`. Available only on the same study day.
83. **`capture_shared.dart`**
    *   **For each draft:** if it has a file with a known name and size, walk the granted source folders.
        *   **One or more matches:** pick the first by folder `granted_at`, then by `relativePath`. The source is set to `ok` with the folder and path.
        *   **No match:** the source is set to `not_linked` with the note "Shared from another app — locate later".
    *   **Creation:** each draft becomes a Planned task in the chosen subject.
    *   **Cleanup:** deletes the cache copies.
84. **`export_exam.dart`**: calls the exporter, then sends the file through `share_plus` or saves it with `FolderAccess.writeFile`, whichever the user chooses. Progress exports sent through the share sheet first show "Includes your notes and history".
85. **`import_exam.dart`**: runs `preview`, then (after the user confirms) `import`, then `refresh()`. Afterwards it offers "Re-link by folder" if any PDF sources were imported.
86. **`copy_as_new_attempt.dart`**: exports the exam in structure mode in memory, then imports it with the new name and date using `forceSeparate: true`, so it never merges into the old attempt.
87. **`archive_and_remove.dart`**
    1.  **Refuse to start** unless a writable backup folder is chosen. Also refuse while a session is open on any node that would be removed.
    2.  **Export with progress** (notes always on) into the backup folder.
    3.  **Read the file back:** `decode`, `validate`, and compare its node and event counts with the database. Stop on any mismatch.
    4.  **Typed confirmation** of the exam name.
    5.  **Delete, in one transaction:** run `deleteSubjectsHard` on the subjects no other exam uses, then delete the exam's `exam_subjects` rows and the exam itself.
    6.  **Refresh:** `refresh()`.
88. **`run_backup.dart`**, **`restore_backup.dart`**, **`relink_sources.dart`**, **`reconcile_notifications.dart`**, **`run_integrity_check.dart`**, **`archive_exam.dart`**: each calls its matching service.
    *   `relink_sources` matches `relinkCandidates` by `file_name` and `file_size` from `FolderAccess.walk`.

### `app/lib/features`

Each feature has its own screens or sheets, providers and widgets, with the contents described in design §10.

89. **`onboarding/`**
    *   `onboarding_screen.dart`, with the steps in this order:
        1.  Start fresh, or Restore.
        2.  Exam, subject, minutes, first item.
        3.  Build the plan.
        4.  Mark the first item studied if chosen.
        5.  Notification permission.
        6.  Battery explainer.
        7.  Backup folder prompt.
    *   `onboarding_providers.dart`
90. **`today/`**
    *   `today_screen.dart`, `today_providers.dart`
    *   widgets: `plan_row_tile`, `summary_bar`, `waiting_line`, `catch_up_card`, `backup_banner`
91. **`library/`**: `library_screen.dart`, `library_providers.dart`, `widgets/node_tile.dart`
92. **`item/`**
    *   `item_screen.dart`, `item_providers.dart`
    *   widgets: `why_due_panel`, `history_list`, `source_card`
93. **`capture/`**
    *   `add_item_screen.dart`, `quick_add_sheet.dart`, `split_sheet.dart`, `source_picker_sheet.dart`, `capture_providers.dart`
    *   `share_capture_sheet.dart`:
        *   one card per draft, with an editable title and a source preview;
        *   a row of subject chips (Inbox first, then the last-used subjects);
        *   Save.
94. **`session/`**: `finish_sheet.dart`, `session_providers.dart`
95. **`grade/`**: `grade_sheet.dart`
96. **`exams/`**
    *   `exams_screen.dart`, `exam_form.dart`, `exams_providers.dart`
    *   `export_sheet.dart`
        *   A mode choice and the "Include notes and excerpts" switch.
        *   The "also used by" notice.
        *   A choice between Share and Save to folder. Share shows the history warning for progress exports.
    *   `import_screen.dart`
        *   A preview, the name and date fields, and per-subject notices ("linked to existing", "copied").
        *   One clash choice per clashing subject, each showing the other exams that use it.
        *   Import.
    *   `archive_sheet.dart`
        *   Archive (keep in app), or Export and remove.
        *   Export and remove requires a backup folder, checks that no session is running, and asks the user to type the exam name to confirm.
97. **`settings/`**: `settings_screen.dart`, `settings_providers.dart`
98. **`diagnostics/`**: `diagnostics_screen.dart`, `diagnostics_providers.dart`

### App tests

99. **`app/test/drift/`** (Generated, committed): the migration tests.
100. **`app/test/data/`**:
    *   `daos_test.dart`: the rollup CTE, the event CHECKs (including `first_study` with a null `session_id`) and the open-session index.
    *   `study_writer_test.dart`, including `deleteSubjectsHard`.
    *   `backup_restore_test.dart`: a round trip; a newer schema is refused; side files are removed; `tree_uri` values are cleared.
    *   `pre_migration_backup_test.dart`
    *   `exam_exchange_test.dart`:
        *   export and import in both modes;
        *   re-importing an archive links to kept subjects without duplicating them;
        *   copy mode with progress;
        *   both clash choices, with "add to existing" shifting `sort_order`;
        *   the Inbox is never a clash target;
        *   `forceSeparate`;
        *   the state after import matches the source;
        *   an invalid file writes nothing.
101. **`app/test/application/`**: `finish_session`, `grade_review`, `mark_studied`, `build_today_plan`, `accept_catch_up`, `split_item`, `add_item`, `capture_shared`, `archive_and_remove`. They run against in-memory Drift with a `FixedClock` and fake ports.
    *   `archive_and_remove` checks:
        *   shared subjects survive;
        *   sessions are deleted;
        *   it is blocked when a session is open or no backup folder is chosen;
        *   nothing is deleted if the export or the read-back check fails;
        *   `last_used_*` settings are cleared.
102. **`app/test/features/`**: `today_screen`, `grade_sheet`, `finish_sheet`, `library_screen`, `share_capture_sheet` and `import_screen`, all using fake receivers.
103. **`app/integration_test/`**:
    *   `session_flow_test.dart`
    *   `backup_restore_flow_test.dart`
    *   `exam_export_import_test.dart`: exports with progress, wipes, imports, and compares the belts.
104. **`app/test/perf/seed_5k.dart`**: seeds 5,000 items with history for profiling.

### M8: adaptive layouts (design D14, §13)

106. **`app/lib/core/layout.dart`** (Create): `WindowClass { compact, medium, expanded }` and `windowClassOf(context)` from `MediaQuery.sizeOf(context).width` (600 and 840 logical pixels). The only place that reads the breakpoints. Also:
    *   `ReadingWidth`, which centres a child at 640 dp at most;
    *   `selectedItemProvider` (a family by pane name) and the `ItemPane` inherited widget;
    *   `openItem` (select in the pane when expanded, else push `/item/:id`), `closeItem` (clear the pane, else pop) and `isOpenInPane` (row highlight).
107. **`app/lib/router.dart`** (Modify): `HomeShell` shows a `NavigationBar` when compact and a `NavigationRail` otherwise, with the same branches. No new routes.
108. **`app/lib/core/widgets/two_pane.dart`** (Create): `TwoPane(pane, list, placeholder)`. Expanded shows both, with the Item screen from the `itemDetailProvider` slot (`core/slots.dart`, filled in `app.dart`, so Library and Today never import the item feature). Otherwise only the list; a selection left over from a wider window is pushed as `/item/:id` and cleared.
109. **`features/library`, `features/today` and `features/item`** (Modify): Library and Today wrap their scaffolds in `TwoPane`; row taps call `openItem` and rows show `selected`. In the Item screen, child taps call `openItem` and Delete calls `closeItem`.
110. **Forms and settings** (Modify): the bodies of onboarding, Add, Split, Item, Exams, Import, Settings and Diagnostics are wrapped in `ReadingWidth`. Bottom sheets already stop at 640 dp in Material 3.
111. **`app/test/features/layout_test.dart`** (Create): the shell, Today, Library and Item at 390 × 844, 800 × 1280 and 1280 × 800; rail versus bar; one or two panes; the selection survives a resize.

### M9: iOS (design D13, §13)

Starts after the Android internal test, and after the author answers the design's Open Questions 1–4.

112. **`app/ios/`** (Create with `flutter create --platforms=ios`): bundle id `io.github.gauravpwagh.prepbelt`, deployment target from Open Question 1, display name PrepBelt, the app icon from `tool/make_icon.py`, `PrivacyInfo.xcprivacy`, a document type for `.prepbelt.json`, and no background modes.
113. **`app/ios/Runner/FilesChannel.swift`** (Create): the `prepbelt/files` channel. `pickFolder`, `bookmarks`, `walk`, `list`, `copyToLocal`, `writeFile`, `delete`, each inside `startAccessingSecurityScopedResource`, with `NSFileCoordinator` for iCloud files.
114. **`app/lib/platform/folder_access.dart`** (Modify): `BookmarkFolderAccess` on that channel, chosen on iOS in `core/providers.dart`. A bookmark is stored in `source_folders.tree_uri`; no schema change.
115. **`app/lib/platform/source_opener.dart`** (Modify): `IosSourceOpener`, with PDFs in Quick Look and links through `url_launcher`.
116. **Share Extension** (Create): the target and App Group that `receive_sharing_intent` needs; `IntentShareReceiver` skips `takeShareSubject` on iOS.
117. **`app/lib/platform/notification_port.dart`** and **`device_status.dart`** (Modify): Darwin settings; `showOngoingSession` does nothing on iOS; `batteryOptimizationIgnored()` returns null, and the battery explainer and Diagnostics row are hidden.
118. **CI** (Modify `.github/workflows/ci.yaml`): a macOS job that runs the app tests and `flutter build ios --no-codesign`, plus a check of the privacy manifest and the absence of networking entitlements.
119. **Release docs** (Create `docs/release/RELEASE-ios.md`): signing, TestFlight, App Store privacy answers.

### M10: organising items (design D15, §10a)

120. **`app/lib/application/delete_item.dart`** (Modify): `DeleteItem(nodeId, keepChildren:)` returns a `DeleteReceipt` (rows as they were, copied sources, how many moved to the Inbox); `undo(receipt)` writes them back. `refile(db, node, subjectId, parentId, kind)` moves a node to the end of its new siblings and its whole subtree to the new subject.
121. **`app/lib/application/move_item.dart`** (Create): `MoveItem(nodeId, MoveTarget)` with the rules of §10a: `canAttach`, `canAddChild`, a subtask made a task gets a copy of its old task's source.
122. **`app/lib/application/save_exam.dart`** (Modify): `createSubject(name, examIds:)`, `renameSubject`, `deleteSubject(id, keepItems:)`; the Inbox is refused. **`nodes_dao.dart`** (Modify): `subtree`, `liveSubtree`, `allRoots`, `replaceNode`.
123. **`app/lib/core/widgets/new_subject_dialog.dart`** (Create): `showNewSubjectDialog` (name and optional open exams) and `showNameDialog`. Used by the capture and Library features.
124. **`features/capture`** (Modify): the Add form's subject and topic menus end with "+ New subject…" and "+ New topic…", and the topic menu always shows for tasks; Quick add and the Share sheet get a "New" chip. Created subjects and topics are kept in the form's state, so nothing typed is lost.
125. **`features/item`** (Modify): the menu has Move… (`widgets/move_sheet.dart`, `moveChoicesProvider`) and Delete, which asks when the item has children and offers Undo. **`features/library`** (Modify): a menu per subject (Rename, Delete subject) and a New subject row.
126. **Tests** (Modify `test/application/use_cases_test.dart`, Create `test/features/organize_test.dart`): the rules in the design's "Organising (D15)" test row.

### M11: Today in three sections (design D16, §4)

127. **`packages/prep_core/lib/src/today_lists.dart`** (Create): `todayLists(PlanInput, plannedIds)` returns the due and unread items below the line and Coming up (`UpcomingItem`, by date then planner order); `upcomingBucket` groups days 1–7, 8–14 and later. Pure, with tests.
128. **`app/lib/application/grade_review.dart`** (Modify): a review of an item that is not in today's plan adds a done `review` row, as `MarkStudied` does for first readings. **`build_today_plan.dart`** (Modify): `inputWithNodes` also returns the planned nodes.
129. **`app/lib/data/daos/settings_dao.dart`** (Modify): `today_open_sections` with `todayOpenSections(date)` and `setTodayOpenSections`. **`nodes_dao.dart`** (Modify): `titlesOf(ids)`.
130. **`features/today/today_providers.dart`** (Modify): `TodayView` with the header, Due now and Up next (plan rows, then the rows below the line), Coming up groups with done-today marks; `todayOpenSectionsProvider`.
131. **`features/today/today_screen.dart`** (Modify): collapsible sections with saved open state, 5 rows then "Show all", the dashed line, view-only Coming up rows, the all-done line. The waiting line is removed.
132. **Tests** (Create `test/features/today_sections_test.dart`, `packages/prep_core/test/today_lists_test.dart`; Modify `test/features/widgets_test.dart`): the design's "Today sections (D16)" test row.

--------------------------------------------------------------------------------

## Verification Plan

*   **Layering:** `dart run tool/check_imports.dart` exits 0 (no cross-feature imports; in the app, `dart:io` only in `data/` and `platform/`).
*   **Codegen and analysis:** `build_runner` succeeds, and `flutter analyze` reports zero issues.
*   **Unit tests:**
    *   `prep_core`: `coverage:test_with_coverage`.
    *   app: `flutter test --coverage`.
    *   `tool/coverage_gate.dart` passes.
*   **Migrations:** `make-migrations` leaves no uncommitted diff, and the generated tests pass.
*   **Integration:** `flutter test integration_test` on API 26 and API 36 emulators.
*   **Release:** the APK builds, and the CI step for the INTERNET permission passes.
*   **Performance:** a profile build with `seed_5k.dart`, recording the four numbers listed in the design's NFR.
*   **Manual release checks:**
    *   Run CUJs 1–12 on a Xiaomi, Oppo or Vivo phone with default battery settings.
    *   Kill the app during a session and relaunch.
    *   Swipe the session notification away, then reopen the app.
    *   Restore on a second device and pick the folders again.
    *   Share into PrepBelt:
        *   links from Claude and ChatGPT;
        *   a page from Chrome;
        *   a PDF inside a granted folder, and one outside;
        *   a `.prepbelt.json` file from WhatsApp;
        *   a share sent before onboarding.
    *   Export an exam on phone A and import it with progress on phone B.

--------------------------------------------------------------------------------

*Drafted with EGM*
