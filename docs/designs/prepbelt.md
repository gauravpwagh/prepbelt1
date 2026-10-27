# PrepBelt: Exam Prep with Spaced Review and Belts

*   **Author:** vijwagh31@gmail.com
*   **Status:** Approved for implementation. Goldfish review round 1, the re-check and a focused review of §8a (exam export and import) are all resolved. D12 was added during M1.
*   **Amendment (2026-10-27):** iOS and tablet layouts brought into scope by the author (D13, D14, §13, M8, M9). The amendment's open questions are listed below; it has not had a Goldfish review yet.
*   **Date:** 2026-10-26
*   **Predecessor:** [concepts_brief.md](../../claude/concepts_brief.md)
*   **Implementation plan:** [docs/plans/prepbelt_implementation.md](../plans/prepbelt_implementation.md)
*   **Repository:** [github.com/gauravpwagh/prepbelt](https://github.com/gauravpwagh/prepbelt)

--------------------------------------------------------------------------------

## Overview

PrepBelt is an offline app for Android, built with Flutter, for students preparing for one or more competitive exams. An iOS version (iPhone and iPad) follows the Android release (D13), and every screen adapts to tablets and foldables (D14). The student creates exams with dates. They add study items (reading, previous-year-question practice and similar) under subjects and topics, and they split large sources into chapters or page ranges.

When an item is first studied, it enters a review schedule. After each review the student grades it **Forgot**, **Shaky** or **Solid**.

*   **Scheduling.** A fixed ladder of growing intervals sets the next review date. While the item's next exam is at least two days away, the date is pulled in to no later than the day before that exam.
*   **Progress.** Progress is shown as a belt:
    *   Red when first read;
    *   up through Orange, Yellow and Light green to Green with good reviews;
    *   down one belt when the student forgets.
*   **Daily list.** Each day the app shows one list that fits the student's study minutes. Due reviews come first, and part of the day is always kept for items not yet read.
*   **Missed days.** After missed days, the extra reviews are shown as a single count, and the app offers to spread them over the next few days.

In short, the app does four things:

*   it records when each item was first studied;
*   it schedules reviews on an explainable ladder that respects exam dates;
*   it builds a daily plan sized in minutes;
*   it shows progress as belts.

Nothing leaves the phone except files the user creates on purpose: backups saved to a folder they choose, and exam files they export. An exam file can share a syllabus structure, start a new attempt, move an exam with its progress to another phone, or archive a finished exam. Every grade is kept in a permanent history.

## Glossary

| Term | Meaning |
| --- | --- |
| **Item / node** | Anything below a subject: a topic, task or subtask. |
| **Reviewable item** | A task with no subtasks, or a subtask. Only these get belts and reviews. |
| **Planned / Unread** | The same state: added but not yet studied. The belt is `unread`. |
| **Base time** | Minutes to study an item the first time (10–50). Defaults: Reading 30, PYQ 40, Other 20. |
| **Review cost** | `max(3, ceil(base time × 0.25))` minutes. |
| **Ladder due** | The next review date the belt ladder produces. This is the date that is stored. |
| **Deadline** | For an item, the earliest exam that is linked to its subject, not archived, and dated after today. |
| **Effective due** | The ladder due date with the exam cap applied when it is read (§3). This is the date the user sees. It is never stored. |
| **Review share / reserve** | The two parts of the daily budget: minutes for reviews, and minutes kept for first readings (§4). |
| **Waiting** | Due reviews that did not fit today's review share. Today shows them as one count line. |
| **Inbox** | A built-in subject that holds quick captures and items shared from other apps that are not yet filed. It is linked to no exam and is left out of the plan. |
| **Study day** | The local date, where the day starts at the day-start hour (default 4 AM). |

--------------------------------------------------------------------------------

## The Problem

A student preparing for a competitive exam (for example UPSC, MPSC or a state PSC) studies from many sources: PDFs, books, web pages, conversations with AI assistants, videos and notes. Today they face four problems.

1.  **They lose track of what they have read.** Progress lives in their head, in scattered notebooks, or in a to-do app that can tick a chapter off but never brings it back.
2.  **They forget what they read.** Without revision at growing intervals, much of a chapter is gone within weeks. Deciding *what* to revise *today* across hundreds of chapters is a planning job that students don't do.
3.  **Flashcard apps don't fit how they study.** Apps like Anki schedule small question–answer cards. A student's real unit of work is a chapter, a page range or a set of previous-year questions, taking 10–50 minutes. Anki also doesn't know the exam date, and it counts cards, not minutes.
4.  **Revision competes with new reading.** With fixed hours each day, the student splits time between revising old material and covering the rest of the syllabus. After a few missed days, the revision pile is larger than one day's time.

--------------------------------------------------------------------------------

## Goals

1.  **Daily plan in minutes.** The Today screen shows one list whose estimated total never exceeds the daily study minutes.
    *   While unread items exist, the reserve (§4) goes to first readings and always fits at least the next unread item.
    *   The remaining minutes go to reviews.
2.  **Exam-aware scheduling.** When an item's deadline is at least two days after its last review, its effective due date is no later than the day before that exam.
3.  **Belt rules.** Each reviewable item:
    *   moves up one belt on Solid;
    *   keeps its belt on Shaky;
    *   drops one belt on Forgot.

    These rules live in one `BeltPolicy`, with tests for every belt × grade pair and every exam-cap case (§12).
4.  **Explainable decisions.**
    *   For any item, "Why is this due?" shows the rule that produced the date and the last 5 events.
    *   Today shows a one-line summary of how the minutes were split.
5.  **Limited backlog** (D12). The 90-day simulation (§12) runs with 15% missed days across 20 seeds. In every run:
    *   outside the 7 days before an exam, each day's `waiting_minutes` is at most 3 × that day's review share;
    *   every item first studied at least 3 days before its deadline either appears as a planned review row on at least one non-missed study day before that exam, or is counted in `wontFit`.
    *   inside those 7 days, the backlog is not bounded. Reviewing everything before an exam can need more time than the daily budget, so the app reports the shortfall instead (D12).
6.  **Fast capture.**
    *   A new item needs a title plus at most 3 taps.
    *   A document can be split into chapter or page-range subtasks in one action.
    *   Sharing a link, text or PDF from another app to PrepBelt saves an Inbox item with one tap on Save. Filing it under a subject first is one extra tap on a subject chip.
7.  **Fast first value.** A new user sees a non-empty Today list within 2 minutes of first opening the app.
8.  **No data loss.**
    *   Every grade is stored in an append-only event log.
    *   A rotating backup (newest 7 kept) is written automatically.
    *   A backup from any earlier app version can be restored into the current version.
9.  **Timer that works across apps.**
    *   The user can start a session, read in another app and finish later.
    *   The minutes are always shown for confirmation or editing before they are saved.
    *   Killing the app does not lose the session.
10. **Performance on low-end phones.** On a 4 GB Android phone holding 5,000 items:
    *   cold start to the first useful frame ≤ 1.5 s;
    *   the Library tree renders in ≤ 100 ms.
11. **Debuggable without a server.**
    *   Diagnostics shows the notification and battery-optimisation status.
    *   "Share logs" produces the log files and the app and OS versions.

## Non-Goals

These are out of scope for version 1. Where later support needs data, that data is already recorded.

*   **Scheduler:**
    *   No FSRS or other adaptive scheduler.
    *   No pluggable scheduler interface.
*   **Timer:**
    *   No Pause button. The editable minutes cover breaks.
    *   No automatic base-time calibration from sessions. The sessions are still stored.
*   **Daily plan:**
    *   No per-weekday budgets. There is one daily-minutes number.
    *   No review cost that varies by belt. It is a flat 25%.
*   **PYQs:**
    *   No recording of PYQ scores, and scores are never turned into grades. The student always grades by hand.
    *   No solving PYQs inside the app: no question bank and no score import (see D1).
*   **Sources:** no separate Source table, and no source files inside backups.
*   **Sharing:** no sharing of images or videos into the app, and no sharing *out* of the app.
*   **Backups and imports:**
    *   No merging a whole-app backup into existing data. Restore replaces everything, after taking a safety backup.
    *   Exam imports never merge rows that already exist. They only add new rows (§8a).
*   **Permissions-heavy features:** no floating timer overlay, and no automatic detection of reading time.
*   **Platform and sync:** no cloud sync, accounts, web version or network access. (iOS and tablet layouts were moved into scope by D13 and D14. A web version was considered and left out: the app's files-on-the-device, no-network design does not fit a browser.)
*   **Flashcards:** no flashcards or question–answer content.
*   **Diagnostics extras:**
    *   No debug bundle containing the database.
    *   No crash-exit detection.
    *   No automatic fix actions for data problems.

## Decisions

*   **D1: PYQ practice is tracked here and done elsewhere.**
    *   *PYQ practice* is a task kind, and its source points to wherever the questions live: an app, a web page or a PDF of the paper.
    *   **Start** opens that source and runs the timer. After the attempt, the student grades the task by hand, and it follows the same ladder as reading.
    *   The PYQ grade sheet adds the line: "Grade on the questions you got wrong last time, or on a fresh set." The repeated-questions risk is listed under Risks.
*   **D2: Minimum Android version is 8.0 (API 26).** Newer-only features are guarded at runtime, for example the notification permission on API 33+.
*   **D3: Default base times.** Reading 30 min, PYQ practice 40 min, Other 20 min.
*   **D4: Naming.**
    *   App: **PrepBelt**.
    *   Android application id: `io.github.gauravpwagh.prepbelt`. It becomes permanent after the first Play Store upload.
    *   Flutter package: `prepbelt`. Core package: `prep_core`.
*   **D5: Scheduler is a fixed ladder.** It is chosen for explainability. FSRS can be reconsidered later, using the event log as history.
*   **D6: Parents show "Weakest: X · n/N Green"** with a stacked bar. Unread children appear in the bar but are not counted when finding the weakest belt.
*   **D7: Catch-up stays in v1** (§4). It moves due dates and never changes belts.
*   **D8: File access uses the [`saf`](https://pub.dev/packages/saf) package (^2.1.2) plus [`android_intent_plus`](https://pub.dev/packages/android_intent_plus).**
    *   If `saf` is abandoned, the fallback is a Kotlin channel behind the same Dart interface (see Risks).
    *   The only hand-written Kotlin is one small channel in `MainActivity` with two methods:
        *   it reads the battery-optimisation state, because `permission_handler` only reports that state when the restricted battery permission is declared;
        *   it passes on a share's subject line, which `receive_sharing_intent` does not deliver.
*   **D9: Android Auto Backup is off.** The app's own backups are the only backup path.
*   **D10: Share to app is in v1** (author decision).
    *   PrepBelt receives shared text, links and PDFs from other apps into the Inbox (§7).
    *   It uses [`receive_sharing_intent`](https://pub.dev/packages/receive_sharing_intent) 1.9.0 (verified publisher, released June 2026).

*   **D11: Exam export and import is in v1** (author decision). It covers four needs:
    *   sharing a syllabus structure with others;
    *   reusing an exam for a new attempt;
    *   moving one exam, with its progress, to another phone;
    *   archiving a finished exam to a file and removing it from the app.

    It does **not** replace the whole-app backup (§8), which stays automatic. See §8a.

*   **D12: In exam week, the app reports the shortfall instead of hiding it** (decided during M1, from the simulation).
    *   **What the simulation showed.** A Python port of the planner (`tool/sim/planner_check.py`) found two things:
        *   Outside the last 7 days before an exam, the waiting backlog never exceeded 1.3 × a day's review share.
        *   Inside those 7 days it reached about 10 ×. Every studied item needs a final review before the exam, and that can take more minutes than the budget allows.
    *   **Spreading didn't help.** Spreading capped items over the last 5 days did not fix it, and it caused missed reviews. So the cap rule stays as it is.
    *   **What the app does instead.**
        *   Goal 5 bounds the backlog only outside exam week.
        *   In exam week, the catch-up prompt states the shortfall in minutes, for example: "3 reviews can't fit before MPSC Prelims at 90 min/day — about 15 more min/day would fit them."
        *   The figure is `ceil(minutes that don't fit / days left before the exam)`, computed by `Proposal.extraMinutesPerDay`.

*   **D13: iOS is in scope, after the Android release** (author decision, 2026-10-27).
    *   **Same app.** One Flutter codebase. `prep_core`, the Drift schema, the event log, the belt rules, the planner and every CUJ stay the same. iOS differs only in `app/lib/platform/` and the iOS project, as set out in §13.
    *   **Devices.** iPhone and iPad.
    *   **Bundle identifier.** `io.github.gauravpwagh.prepbelt`, the same as the Android id (D4). It becomes permanent after the first App Store Connect upload.
    *   **Native code on iOS.** One Swift channel for folder access (§13). It is the iOS counterpart of D8 and is kept as small as the Kotlin one.
    *   **Order.** iOS work starts after the Android internal test (M9). The Android release does not wait for it.
*   **D14: Layouts adapt to the window size** (author decision, 2026-10-27).
    *   It applies to Android tablets, foldables, split-screen windows and iPad. Layout follows the window width, never the device type.
    *   **Compact (< 600 dp):** today's phone layout, unchanged.
    *   **Medium (600–839 dp):** a navigation rail replaces the bottom bar, and content is centred with a maximum width.
    *   **Expanded (≥ 840 dp):** the rail, plus two panes for Library and Today: the list on the left and the selected item on the right.
    *   Behaviour, routes and data are unchanged; only presentation differs (§13).

## Open Questions

These belong to the 2026-10-27 amendment (D13, D14). Each has a proposed answer.

1.  **Lowest iOS version.** Proposed: iOS 15. It covers almost all phones in use, and every plugin in the stack supports it.
2.  **iOS device backup.** On Android, Auto Backup is off (D9). On iOS, iCloud and computer backups include the app's files by default, and users expect a restored iPhone to bring its apps' data back. Proposed: leave iOS device backup on, and keep the app's own backups as the main path. The alternative is to exclude the database from device backup, matching D9.
3.  **The ongoing timer on iOS.** iOS has no ongoing notification with a chronometer. Proposed for M9: no live timer outside the app. The open session lives in the database; reopening the app shows the Finish sheet, and the "Still on…?" reminder still fires. A Live Activity on the Lock Screen is a Future Improvement.
4.  **Mac and Apple account.** iOS builds need a Mac with Xcode, and TestFlight needs an Apple Developer Program membership. The development PC is Windows. Proposed: CI builds and tests iOS on a macOS runner without signing, and signed builds wait until a Mac and an account are available.

--------------------------------------------------------------------------------

## Critical User Journeys (CUJs)

### CUJ 1: First run to first plan

*   **Given**: a fresh install.
*   **When**: the user opens the app and does the following:
    1.  Chooses "Start fresh". The alternative, "Restore from backup", leads to CUJ 7.
    2.  Enters an exam ("MPSC Prelims", 2027-03-14), one subject ("Polity"), a daily time (90 min) and one item ("Laxmikant Ch 1–5").
    3.  Chooses "Studied today".
*   **Then**:
    *   Today opens. "Laxmikant Ch 1–5" shows as a done first-reading row at Red, next review tomorrow.
    *   The remaining 60 minutes are offered to unread items. The first time, this shows as an empty state with an "Add more items" action.
    *   The app asks once for notification permission. It then explains why turning off battery optimisation helps, and opens the system settings screen, where the user finds PrepBelt.
    *   After the first item is saved, the app asks for a backup folder. The user can skip this; a banner then reminds them.
    *   The flow up to Today takes under 2 minutes.

### CUJ 2: Capture a document and split it into chapters

*   **Given**: an exam and a subject exist, and the user has granted access to a folder that holds a 12-chapter PDF.
*   **When**: the user does the following:
    1.  Taps Add and types "Laxmikant Polity".
    2.  Picks the PDF from the in-app folder browser.
    3.  Chooses "Split into chapters 1–12".
    4.  Saves it as Planned.
*   **Then**:
    *   One task with 12 Unread subtasks is created.
    *   Each subtask inherits the PDF, holds its own position ("Ch 1" … "Ch 12") and gets the default base time.
    *   The parent shows "0/12 started".
    *   Splitting is offered only for tasks with no review history. A task that already has reviews offers "Create a new task with chapters" instead.

### CUJ 2b: Share an AI chat into PrepBelt

*   **Given**: the user is in the Claude app, looking at a conversation about the Preamble.
*   **When**: they tap Share and choose PrepBelt.
*   **Then**:
    *   PrepBelt opens a capture sheet.
    *   The title is pre-filled from the shared subject or first line. The source is "AI chat" with the link. The shared text is kept as the excerpt.
    *   The subject is Inbox unless the user picks another.
    *   One tap on Save creates the item as Planned, and the user is returned to the Claude app.

### CUJ 2c: Share a PDF into PrepBelt

*   **Given**: the user has granted PrepBelt access to their "UPSC" folder. A PDF reader is showing "Polity_notes.pdf", which is inside that folder.
*   **When**: they share the file to PrepBelt.
*   **Then**:
    *   The share plugin makes a temporary copy of the file in the app's cache. PrepBelt reads the name and size from that copy.
    *   It searches the granted folders for a file with the same name and size. On a match, the source is linked to that file.
    *   With no match, the item is saved with a PDF source marked "not linked" and the note "Shared from another app — locate later". The user can link it later with Re-link.
    *   The temporary copy is deleted after capture. PrepBelt never keeps its own copy of the file.

### CUJ 3a: Study in another app with the timer

*   **Given**: subtask "Ch 3" is on Today as a first reading.
*   **When**:
    1.  The user taps Start. The PDF opens in their PDF reader, and a notification shows a running clock.
    2.  38 minutes later they come back to PrepBelt.
*   **Then**:
    *   On return, the Finish sheet shows "Studied 38 min", with the minutes editable.
    *   The user confirms, and "Ch 3" becomes Red with its next review tomorrow.
    *   The session's start and end times are stored.
    *   **Ways back:** reopening the app always brings back the Finish sheet. Tapping the notification also works, but the notification is a convenience: it may have been swiped away (Android 14+) or removed by the phone's battery manager.
    *   **App killed while reading:** the session is still found on next launch and finished the same way.
    *   **Wrong item:** if the session was started on the wrong item, "Discard session" ends it without saving anything.

### CUJ 3b: PYQ practice in another app

*   **Given**: task "Polity PYQ 2019–2023" (kind *PYQ practice*) is due, and its source is a link to the user's test-series page.
*   **When**: the user taps Start, attempts the questions in that app or page, then returns.
*   **Then**:
    *   The Finish sheet shows the editable minutes.
    *   The grade sheet shows the PYQ guidance line.
    *   The task moves on the same ladder as any reading task.

### CUJ 3c: Studying from a source that is not on the phone

*   **Given**: task "Spectrum Modern History" has a printed-book source with the note "Printed copy, shelf 2", and subtask "Ch 9 · pp. 210–236" is due.
*   **When**: the user taps Start.
*   **Then**:
    *   Nothing opens.
    *   The timer starts, and the notification reads "Spectrum Modern History (printed) · Ch 9 · pp. 210–236".
    *   Finishing and grading work as in CUJ 3a and CUJ 4.
    *   The source is never shown as broken.

### CUJ 4: Daily review and grading

*   **Given**: Today holds 4 reviews and 2 first readings, 85 of 90 minutes.
*   **When**: the user does two reviews:
    *   reviews "Ch 1" (Orange) and grades it **Solid**;
    *   reviews "Ch 2" (Yellow) and grades it **Forgot**.
*   **Then**:
    *   Before tapping, each grade button showed its definition and the resulting next date.
    *   "Ch 1" becomes Yellow, due in 7 days.
    *   "Ch 2" drops to Orange, due tomorrow, with the message "Back to Orange — quick look tomorrow."
    *   The newest grade on each item can be undone.
    *   The parent "Laxmikant Polity" shows "Weakest: Red · 0/12 Green", because Ch 3 is still Red.

### CUJ 5: Returning after missed days

*   **Given**:
    *   The user missed 5 days.
    *   18 reviews (about 190 minutes) are now due or overdue.
    *   The review share is 63 minutes a day.
    *   About 25 minutes of other reviews fall due on each of the next few days.
*   **When**: the user opens the app.
*   **Then**:
    *   Today shows the reviews that fit today's review share, in priority order (§4), plus the reserved first reading.
    *   The rest appears as one line: "12 reviews waiting".
    *   A prompt offers: "Spread 18 overdue reviews over the next 6 days?"
        *   The day count already includes the reviews that fall due on those days.
        *   If some reviews cannot fit before an exam, the prompt adds: "3 can't fit before MPSC Prelims at 90 min/day — about 15 more min/day would fit them." (D12)
    *   **Accepting:**
        *   Gives each overdue review a new due date within those days.
        *   Leaves belts unchanged.
        *   Can be undone with "Undo catch-up" until the end of that study day.
    *   **Declining:** hides the prompt until the next study day.
    *   No row is marked as late.

### CUJ 6: Understand why something is due

*   **Given**: subtask "Ch 7" is on Today.
*   **When**: the user opens it and taps "Why is this due?".
*   **Then**: the app shows the rule and the last 5 events (date, grade, belt change, minutes). For example: "Shaky at Orange: 3 days halved → 2 days. Capped by MPSC Prelims on 14 Mar."

### CUJ 7: New phone — restore

*   **Given**:
    *   The old phone saved backups into a folder that the user's cloud-drive app syncs.
    *   The PDFs were copied to the new phone.
*   **When**:
    1.  On first launch the user chooses "Restore from backup" and picks the backup folder.
    2.  They pick the newest `prepbelt-…db` file.
*   **Then**:
    *   All exams, items, belts and history come back.
    *   An older backup is upgraded first.
    *   Folder permissions do not move between phones, so the app asks the user to pick the backup folder and each PDF folder again.
    *   "Re-link by folder" matches PDF sources by file name and size, and lists any it can't match.

### CUJ 8: Exam passes

*   **Given**: MPSC Prelims (14 Mar) and UPSC Prelims (24 May) share the subject Polity.
*   **When**: 14 Mar arrives.
*   **Then**:
    *   From that day, Polity items are capped by 24 May instead, with no database change.
    *   The app offers to archive MPSC Prelims. Archived exams don't cap anything, but their history stays.

--------------------------------------------------------------------------------

### CUJ 9: Share a syllabus structure with a friend

*   **Given**: the user's "MPSC Prelims" exam has 6 subjects and about 300 chapters, with sources and progress.
*   **When**: they open the exam, tap **Export → Structure only**, and share the file over WhatsApp.
*   **Then**:
    *   The file `MPSC Prelims.prepbelt.json` contains the exam name and date, its subjects, topics, tasks and subtasks, base times, and sources (links, file names, location notes).
    *   It contains no belts, review history, sessions or settings.
    *   Excerpts, location notes, AI-chat links and the names of the user's other exams are left out unless the user turns on "Include notes and excerpts".
    *   A subject that is also used by another exam is included in full. The export screen says so, for example: "Polity is also used by UPSC Prelims."

### CUJ 10: Import a structure, or reuse it for a new attempt

*   **Given**: a friend's structure file. Or the user's own exam, which they want to start again for next year.
*   **When**: the user does one of these:
    *   shares the file to PrepBelt;
    *   picks it in **Exams → Import**;
    *   taps **Exams → MPSC Prelims → Copy as new attempt**, which exports and imports in one step.
*   **Then**:
    *   An import screen shows the exam name, an editable exam date, the subject count and the item count.
    *   Every imported row gets a new ID, and every item starts Unread.
    *   **Import from a file:** if a subject with the same name already exists, the app asks once per subject. The choices are "Add these items to your existing Polity" (the screen shows which other exams use it) or "Keep a separate copy (Polity 2)".
    *   **Copy as new attempt:** this never asks. Subjects are always kept separate ("Polity 2"), so the new attempt can't mix with the old one.
    *   The new exam then appears in Library and in the plan.

### CUJ 11: Move an exam with its progress to another phone

*   **Given**: the user wants "UPSC Prelims" on a second phone, with its belts and history.
*   **When**: they do the following:
    1.  Export **With progress** on the old phone.
    2.  Open the file on the new phone.
    3.  Confirm the import.
*   **Then**:
    *   **Fresh phone.** On a phone where none of the file's IDs exist, everything is inserted with its original IDs. Belts and due dates are worked out again from the events.
    *   **Subjects already present.** IDs are decided per subject. For example, if Polity came over earlier with another exam, the new exam is simply linked to the existing Polity. Polity's items and history in the file are skipped, so nothing is duplicated.
    *   **Other ID clashes.** If some other subject's IDs clash, only that subject is copied, with new IDs.
    *   **PDF sources** arrive as "not linked", with their file names. "Re-link by folder" connects them.

### CUJ 12: Archive a finished exam to a file

*   **Given**: "MPSC Prelims 2027" has passed.
*   **When**: the user taps **Archive → Export and remove**.
*   **Then**:
    *   The app checks that a backup folder is chosen and that no session is running on the exam's items.
    *   It writes a with-progress export, with notes included, into the backup folder. It reads the file back and checks it before anything is deleted.
    *   The user confirms by typing the exam name. The exam is then deleted, along with its items, events and sessions.
    *   A subject that another exam still uses is kept, together with everything in it.
    *   Importing the file later brings the exam back with its history. It re-links to any subjects that were kept, with no duplicates.
    *   The existing **Archive (keep in app)** option still only hides the exam from planning.

## Technical Plan (Architecture)

### 1. Shape of the system

The app has four layers, and dependencies point only downward. The scheduling and planning rules live in a pure Dart package, so they can be tested without Flutter, a device or a database.

```text
┌──────────────────────────────────────────────────────────────────────┐
│  app/ (Flutter): features/ onboarding · today · library · item ·     │
│  capture · session · grade · exams · settings · diagnostics          │
│  Widgets + Riverpod providers. No business rules.                    │
└───────────────┬──────────────────────────────────────────────────────┘
                │ calls
┌───────────────▼──────────────────────────────────────────────────────┐
│  app/lib/application/: use cases, one class each                     │
│  StartSession · FinishSession · DiscardSession · MarkStudied ·       │
│  GradeReview · UndoLatest · AddItem · SplitItem · BuildTodayPlan ·   │
│  CaptureShared · AcceptCatchUp · UndoCatchUp · RunBackup ·           │
│  RestoreBackup · RelinkSources · ReconcileNotifications · Integrity  │
└───────┬───────────────────────┬───────────────────────────┬──────────┘
        │ pure rules            │ storage                   │ OS
┌───────▼────────────┐  ┌───────▼────────────────┐  ┌───────▼─────────────────┐
│ packages/prep_core │  │ app/lib/data/          │  │ app/lib/platform/       │
│ Belt, BeltPolicy,  │  │ Drift database, DAOs   │  │ NotificationPort        │
│ EffectiveDue,      │  │ (map rows ⇄ prep_core  │  │ FolderAccess (saf)      │
│ DeadlineResolver,  │  │ types), backup/restore │  │ SourceOpener (intents,  │
│ Planner, CatchUp,  │  │                        │  │  url_launcher)          │
│ Hierarchy, Split,  │  │                        │  │ ShareReceiver, Device-  │
│ ShareClassifier,   │  │                        │  │ Status, Logging         │
│ LocalDayClock      │  │                        │  │                         │
└────────────────────┘  └────────────────────────┘  └─────────────────────────┘
```

**Dependency rules:**

*   `prep_core` depends on no Flutter, Drift, platform or `dart:io` code. IDs and time-zone offsets are passed into it.
*   Feature folders never import each other.
*   A CI script enforces both rules.

### 2. Data model (Drift / SQLite)

**Rules that apply to every table:**

*   Primary keys are UUID v7 stored as `TEXT`. They are generated in the app layer.
*   Instants are UTC **milliseconds**, stored in `INTEGER` columns through a converter.
*   Study days are stored as `TEXT 'YYYY-MM-DD'`.
*   Foreign keys are on, the journal is WAL, and the busy timeout is 5 s.

| Table | Purpose | Columns |
| --- | --- | --- |
| `exams` | Exams | `id`, `name`, `exam_date`, `archived_at` (null), `created_at` |
| `subjects` | Subjects, which can be shared between exams | `id`, `name`, `sort_order`, `is_inbox` (bool; exactly one row is true), `created_at` |
| `exam_subjects` | Many-to-many link | `exam_id`, `subject_id` (composite PK) |
| `study_nodes` | Topics, tasks and subtasks | `id`, `subject_id`, `parent_id` (null), `kind` (`topic`/`task`/`subtask`), `task_kind` (`reading`/`pyq`/`other`; null for topics), `title`, `position_text` (null), `base_minutes` (10–50; null for topics), `sort_order`, `created_at`, `deleted_at` (null) |
| `node_sources` | Optional source on a task; its subtasks inherit it | `node_id` (PK), `source_type` (`pdf`/`book`/`web`/`ai_chat`/`video`/`notes`/`lecture`/`app`/`other_device`), `url` (null), `folder_id` (null), `relative_path` (null), `file_name` (null), `file_size` (null), `location_note` (null), `excerpt` (null, ≤ 20,000 chars), `link_status` (`ok`/`needs_relink`/`not_linked`) |
| `source_folders` | Folders the user granted access to | `id`, `tree_uri` (null = pick again, after a restore), `display_name`, `purpose` (`sources`/`backup`), `granted_at` |
| `review_events` | **Append-only event log** | `id`, `node_id`, `event_type` (`first_study`/`review`/`reschedule`/`undo`), `at_utc`, `local_date`, `tz_id`, `grade` (null), `minutes` (null), `session_id` (null), `belt_before` (null), `belt_after` (null), `interval_days` (null), `ladder_due_after` (null), `explanation` (null), `undoes_event_id` (null), `batch_id` (null), `scheduler` (`ladder`), `scheduler_version` (1) |
| `item_state` | Current state per reviewable node, written in the same transaction as each event | `node_id` (PK), `belt`, `ladder_due` (null), `last_review_date` (null), `review_count`; indexes on `ladder_due` and `belt` |
| `study_sessions` | Timer sessions | `id`, `node_id`, `started_at_utc`, `ended_at_utc` (null), `confirmed_minutes` (null), `edited` (bool), `discarded` (bool); partial unique index allowing at most one row with `ended_at_utc IS NULL` |
| `day_plans` | Frozen plan header | `local_date` (PK), `budget_minutes`, `review_minutes`, `first_read_minutes`, `waiting_count`, `waiting_minutes`, `catch_up_state` (`none`/`offered`/`accepted`/`declined`), `catch_up_batch_id` (null), `built_at_utc` |
| `day_plan_rows` | Frozen plan rows | `local_date`, `position`, `node_id`, `row_type` (`review`/`first_read`), `estimated_minutes`, `reason` (`due`/`overdue`/`deadline_risk`/`catch_up`/`first_read`), `done_at_utc` (null) |
| `settings` | Key–value settings | `key`, `value` (see the settings table below) |
| `backup_meta` | One row, carried into every backup | `format_version`, `schema_version`, `app_version`, `created_at_utc` |

**Which columns each event type fills.** CHECK constraints enforce this per `event_type`.

| `event_type` | `grade` | `minutes` / `session_id` | `belt_before` → `belt_after` | `interval_days` | `ladder_due_after` | `undoes_event_id` | `batch_id` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `first_study` | null | `minutes` set; `session_id` null when there was no timer | `unread` → `red` | 1 | date + 1 | null | null |
| `review` | set | `minutes` set; `session_id` null when there was no timer | from the grade rule (§3) | ≥ 1 | date + interval | null | null |
| `reschedule` | null | null | unchanged → unchanged | null | the new date | null | set |
| `undo` | null | null | null | null | null | the target event | null |

**Append-only, with one exception.** No code updates or deletes `review_events` rows. The one exception is "Archive and remove" (§8a), which hard-deletes all rows of the removed subjects after their export has succeeded.

**Minutes without a timer.** Marking an item studied, or grading it, without a session records the minutes the user confirms. The field is pre-filled with the base time for a first study, and with the review cost for a review.

**Rules for deriving state from events:**

*   **`item_state`** is the outputs (`belt_after`, `ladder_due_after`) of the newest event of that node that is not an `undo` and has not been undone. If no such event exists, the state is `unread` with no due date.
*   **`review_count`** counts `review` events that have not been undone.
*   **`last_review_date`** is the `local_date` of the newest `first_study` or `review` event that has not been undone.
*   `item_state` is updated in the same transaction as each event.

**Never stored:**

*   effective due dates and the exam cap;
*   a parent's weakest belt and belt counts;
*   whether an item is reviewable.

**Depth rule** (enforced in `prep_core`):

*   Below a subject there is an optional topic, then a task, then an optional subtask, so the maximum depth is 3.
*   Topics hold tasks, tasks hold subtasks, and subtasks hold nothing.
*   A task that has any `review_events` cannot gain subtasks, whether through Split or by adding one directly. The app offers "Create a new task with chapters" instead (`canAddChild` in `prep_core`).

**Settings:**

| Key | Default |
| --- | --- |
| `daily_minutes` | 90 (allowed 15–600) |
| `day_start_hour` | 4 |
| `reminder_time` | 07:00 |
| `backup_folder_id` | null |
| `last_backup_at_utc` | null |
| `onboarding_done` | false |
| `last_used_subject_id` | null |
| `last_used_topic_id` | null |

### 3. Belt policy and the exam cap (in `prep_core`)

```text
Ladder (scheduler_version = 1)
  belt         step  interval_days   shaky_interval (= ceil(interval/2), min 1)
  unread        0        –               –
  red           1        1               1
  orange        2        3               2
  yellow        3        7               4
  light_green   4       16               8
  green         5       35              18
```

**`BeltPolicy.apply(state, event, date) → Transition(beltAfter, intervalDays, ladderDue, explanation)`**

*   **first_study:** the belt goes from Unread to Red, and the interval is 1.
*   **Solid:** up one belt (Green stays Green). The interval is the ladder value of the new belt.
*   **Shaky:** the belt stays. The interval is the Shaky value of the current belt. Because it comes from the ladder, repeated Shaky grades never shrink it further.
*   **Forgot:** down one belt (Red stays Red). The interval is 1.
*   **Date base:** `ladderDue = date of the review + interval`. A late review is not penalised twice.

**Exam cap, applied when a date is read:**

```text
deadline     = DeadlineResolver(exams linked to subject, today)
               → earliest exam with archived_at = null and exam_date > today, else none
effectiveDue = ladderDue                    if no deadline, or deadline − 1 ≤ lastReviewDate
             = min(ladderDue, deadline − 1)  otherwise
```

*   **Where the cap is used:** the Planner, the grade-sheet preview and "Why is this due?" all call `effectiveDue`.
*   **What happens when exams change:** editing, archiving or passing an exam changes the cap at once, with no database write.
*   **Exam tomorrow:** if the item was last reviewed on or after the day before its exam, no cap applies and the ladder date stands. This matches Goal 2, which only applies when the deadline is at least two days after the last review. Because the cap disappears the moment it can no longer be met, the date never changes overnight.

**Undo:**

*   Only the newest event of a node that is not an `undo` and has not been undone can be undone. Repeating Undo steps back one more event each time.
*   An `undo` event itself cannot be undone.
*   Undoing a `first_study` returns the item to Unread.
*   Undo also clears `done_at_utc` on that item's row in today's plan.

**Split:** a task with any events cannot be split or gain subtasks (see the depth rule in §2).

**Explanation templates.** The stored part comes from the event. The cap suffix is added when the explanation is read. Dates are written like "14 Mar".

| Case | Text |
| --- | --- |
| first_study | "First read → Red. Next review in 1 day." |
| Solid | "Solid at {from} → {to}. Next review in {n} days." |
| Solid at Green | "Solid at Green → stays Green. Next review in 35 days." |
| Shaky | "Shaky at {belt}: {full} days halved → {n} days." (Red: "Shaky at Red: next review in 1 day.") |
| Forgot | "Forgot at {from} → {to}. Quick look tomorrow." |
| Forgot at Red | "Forgot at Red → stays Red. Quick look tomorrow." |
| reschedule | "Moved by catch-up to {date}." |
| cap suffix (read time) | " Capped by {exam} on {date}." |

**After a drop**, the grade sheet shows: "Back to {belt} — quick look tomorrow."

### 4. Daily planner and catch-up (in `prep_core`)

`Planner.build(PlanInput) → DayPlan` is a pure function.

**Inputs:**

*   `today`, `budget`;
*   every reviewable item in a non-Inbox subject, with its state, base time, deadline and sort key;
*   today's existing done rows.

**Sort key.** A tuple, compared in order:

1.  subject `sort_order`;
2.  topic `sort_order` (0 if there is no topic);
3.  task `sort_order`;
4.  subtask `sort_order` (0 for a task);
5.  `created_at`;
6.  `id`.

**Done rows count first.**
*   Before step 1, the `estimated_minutes` of today's done rows are subtracted.
*   Done `review` rows come out of the review share, and done `first_read` rows come out of the reserve. Both shares bottom out at 0.
*   Done items are not selected again.

Goal 1 therefore covers planned rows plus done rows. A row added by "Mark studied" outside the plan can push the day over budget, in which case the next refresh plans fewer new rows.

**Costs:**

*   A first reading costs its base time.
*   A review costs `max(3, ceil(base × 0.25))`.

**Steps:**

1.  **Reserve.** If any item is unread:
    *   `reserve = min(budget, max(ceil(0.30 × budget), base of the first unread item in sort order))`.

    If no item is unread, the reserve is 0. Then `reviewShare = budget − reserve`.
2.  **Reviews.** An item is due when `effectiveDue ≤ today`. Due items are sorted by:
    1.  days to deadline, ascending (no deadline sorts last);
    2.  days overdue, descending;
    3.  belt step, ascending;
    4.  sort key.

    Add them in this order while they fit the review share, skipping any that don't fit. Each row's reason is the first that applies:
    *   `catch_up` if the item's newest event is a `reschedule`;
    *   `deadline_risk` if the deadline is ≤ 7 days away;
    *   `overdue` if `effectiveDue < today`;
    *   `due` otherwise.
3.  **First readings.** Unread items in sort order fill the reserve plus any unused review share. Items that don't fit are skipped. The reason is `first_read`.
4.  **Second pass.** If any reserve is left unused, it goes to due reviews that are still unplaced, in the same order.
5.  **Waiting.** Due reviews still not placed become "waiting", stored as `waiting_count` and `waiting_minutes`.
6.  **Split suggestion.** An unread item whose base time alone exceeds the budget is flagged "split suggested".
7.  **Summary.** "{r} min reviews · {f} min new reading". If waiting > 0, add " · {n} waiting". If no rows are planned: "Nothing due today", or "Nothing fits today · {n} waiting" when reviews are waiting.

**Freezing the plan:**

*   The plan is built the first time Today opens on a study day, and saved. Onboarding builds it at its last step, before writing the onboarding item's first-study row.
*   Finishing or grading an item marks its row done, and the plan is not rebuilt.
*   "Mark studied" on an item that is not in the plan (for example during onboarding) adds a done `first_read` row.
*   Refresh rebuilds the plan and keeps the done rows. Changing daily minutes or the day-start hour also triggers a refresh.

**Catch-up:**

`CatchUp.propose(PlanInput, horizon = 14) → Proposal(assignments: [(nodeId, date)], days, wontFit: {examId: count})`

*   **Offer.** The offer appears when today's plan has waiting reviews (`waiting_count > 0`). It is shown once per study day.
*   **Today is fixed.** Reviews already placed in today's plan, done or not, stay where they are. Only the waiting items are assigned, to days `d = 1…13`.
*   **Capacity.** For `d` in 1…13:
    *   `capacity[d] = reviewShare − projected review minutes of items whose effectiveDue = today + d`.
    *   The projection uses current states and assumes no new grades.
*   **Assignment.** Waiting items are assigned in planner order. Each goes to the earliest day `d` with `capacity[d] ≥ cost` and `today + d ≤ latest`. Here `latest = deadline − 1` if a deadline exists, otherwise `today + 13`. The item's cost is then subtracted from that day.
*   **No room.** If no day has room:
    *   an item with a deadline goes on `latest` anyway, over capacity, and is counted in `wontFit` for that exam;
    *   if `latest ≤ today` (the exam is tomorrow), the item stays waiting today and is counted in `wontFit`;
    *   an item without a deadline, or whose deadline is beyond the 14-day horizon, stays waiting today.
*   **Days.** `days = max(d) + 1`. Today counts as day 1.
*   **Accept.** Accepting writes one `reschedule` event per assigned item. All of them share one `batch_id`, and belts are unchanged. Today's plan is then refreshed (done rows kept).
*   **Undo catch-up.** Available until the end of that study day. It writes `undo` events for every event in the batch that is still its node's newest, then refreshes today's plan.
*   **Decline.** Hides the offer until the next study day.

### 5. Time and "today"

*   `prep_core` defines `Clock` (current UTC instant) and `LocalDayClock`. `LocalDayClock` takes a clock, an offset function `Duration Function(DateTime utc)` and the day-start hour.
*   **Study day** = the local date of (now − day-start hour). So 00:30 still counts as the previous day.
*   Each event stores the time-zone identifier (`tz_id`) at the moment it was written.
*   Only `platform/clock.dart` reads the system time. Tests inject clocks.

### 6. Study timer and sessions

```text
Start ─► StartSession
          ├─ refuse if a session is open (offer to finish or discard it)
          ├─ insert study_sessions(started_at_utc)
          ├─ show ongoing notification: chronometer from started_at,
          │    title "{task} · {position}", action "Done" (opens the app)
          ├─ schedule "Still on {title}? Tap to finish." at start + 2×base (inexact)
          └─ open the source if it is linked; otherwise open nothing

App launch / resume / notification tap, with an open session
          ─► Finish sheet over Today
               elapsed = now − started_at (negative → 0)
               stale if elapsed > max(4 h, 3×base): asks "Did you finish?",
                     pre-fills base time instead of elapsed
            ├─ Confirm minutes → ended_at, confirmed_minutes, edited
            │     Unread item → MarkStudied (first_study)
            │     otherwise   → Grade sheet → GradeReview (review); event.session_id set
            ├─ Discard → ended_at, discarded = true, nothing else written
            └─ cancel session notifications
```

*   **One writer.** All database writes happen in the app's UI process. The notification's Done action only opens the app.
*   **No Pause in v1.**
*   **Page positions.** PDF readers can't reliably be opened at a page, so the position text is shown in the notification and on the item.

### 7. Sources and folder access

*   **Folders, not files.** The user grants access to folders (`saf.pickDirectory`, kept as a persisted permission). A PDF source stores the folder, its relative path, the file name and the file size. This avoids Android's limit on how many individual files an app can keep access to.
*   **Picking a file.** Files are picked from an in-app browser built on `saf.walk`, which lists the granted folder. Every pick is therefore inside a granted folder.
*   **Opening a source.**
    *   A PDF or file opens with `ACTION_VIEW` on its content URI, with read permission granted to the viewer, through `android_intent_plus`.
    *   Web, AI-chat and app sources open through `url_launcher` in external-application mode.
*   **Broken links.** If opening fails, the source becomes `needs_relink`. The item stays usable, and a "Re-link" action is offered.
*   **Not on the phone.** Printed books, notes, lectures and files on other devices have no link. Their status is `not_linked`, and an optional location note says where they are.
    *   Start only runs the timer.
    *   Re-link and the integrity check ignore these sources.
    *   A link can be added later without losing history.
*   **Re-link by folder.** Matches `needs_relink` sources, and PDF sources that are `not_linked` and have a file name, against a chosen folder by file name and size. It lists the ones it can't match.
*   **Share to app (D10).**
    *   **What it accepts.** The manifest declares three intent filters:
        *   `SEND` with `text/plain`;
        *   `SEND` with `application/pdf`;
        *   `SEND_MULTIPLE` with `application/pdf`.
        *   For exam files (§8a): `SEND` with `application/json` and with `application/octet-stream`.

        `MainActivity` uses `launchMode="singleTask"`. Images and videos are not accepted.
    *   **How a share is turned into a draft.** The pure function `classifyShare(text, subject, files)` (in `prep_core`) produces one draft per shared item:
        *   **Text that contains a URL** becomes a draft with that URL as its source.
            *   The source type is `ai_chat` if the host is one of `claude.ai`, `chatgpt.com`, `chat.openai.com`, `gemini.google.com`, `perplexity.ai` or `copilot.microsoft.com`. Otherwise it is `web`.
            *   The full shared text is kept as the excerpt.
        *   **Text without a URL** becomes a `notes` source, with the text kept as the excerpt.
        *   **Each shared PDF** becomes a `pdf` source. Its `file_name` and `file_size` are read immediately, before the temporary access ends.
    *   **URL rule.** The URL is the first `https?://…` match in the text. Any later URLs stay in the excerpt only.
    *   **Host match.** A host matches an AI-chat entry if it equals that entry or ends with `.` + the entry. For example, `www.perplexity.ai` matches `perplexity.ai`.
    *   **Title.** Taken from the first of these that exists:
        1.  the share subject;
        2.  the first non-empty line of text, cut to 80 characters;
        3.  the file name without its extension;
        4.  the URL host;
        5.  "Shared PDF" or "Shared note".
    *   **Base time and status.** The default base time for the task kind; Reading is the default. Status is Planned.
    *   **Matching a shared PDF.**
        *   PrepBelt walks every granted source folder looking for a file with the same name and size. If several files match, it uses the first, ordered by the folder's `granted_at` and then by relative path.
        *   On a match, it fills in `folder_id` and `relative_path`, with `link_status = ok`.
        *   With no match, it sets `link_status = not_linked` and `location_note = "Shared from another app — locate later"`.
        *   The share plugin's temporary cache copy is deleted after capture, and the app never keeps a copy. A single share that has both a PDF and text delivers only the PDF; this is a limitation of the plugin.
    *   **Capture sheet.**
        *   Shows the title, the source preview and the subject (Inbox by default).
        *   Subjects appear as a single row of chips: the Inbox chip first, then the last-used subjects. Save takes one tap. Tapping a chip first adds one tap.
        *   Several shared PDFs create one Inbox task each.
    *   **Before onboarding.** If a share arrives before onboarding is finished, it is held in memory, onboarding runs first, and the capture sheet then opens.

### 8. Backup, restore, migrations and integrity

**Backup files.** All backups are written to the backup folder through `saf.writeFileStream`.

*   `prepbelt-YYYYMMDD-HHMM-s{schema}.db` — rotating; the newest 7 are kept.
*   `prepbelt-premigration-…` and `prepbelt-safety-…` — never rotated; the user deletes them.

**No backup folder chosen yet.** Rotating backups go to app-private storage, the newest 3 are kept, and Today shows a banner until a folder is chosen.

**Routine backup** (`RunBackup`):

*   **When:** after the first frame, if the last backup is more than 20 hours old; and on "Back up now".
*   **Steps:**
    1.  Update `backup_meta`.
    2.  `VACUUM INTO` a temporary cache file. This makes a consistent copy while the app keeps running.
    3.  Copy it to the backup folder.
    4.  Rotate old files.
    5.  Record `last_backup_at_utc`.

**Before a migration** (runs before Drift opens the database):

1.  Open the file with raw `sqlite3` and read `PRAGMA user_version`.
2.  If it is lower than the current schema version, `VACUUM INTO` a `prepbelt-premigration-…` copy and save it out.
3.  Close the file, then open it with Drift. Drift's migrations then run.

**Restore** (`RestoreBackup`):

1.  The user picks the backup folder, then a `prepbelt-*.db` file from it.
2.  The file is copied to the cache with `saf.copyToLocalFile` and opened read-only.
3.  Checks: `format_version` must be known, `schema_version` must not be newer than the app's (otherwise "Update the app to restore this backup"), and `PRAGMA integrity_check` must pass.
4.  A safety backup of the current data is written.
5.  `db.close()`, the `-wal` and `-shm` files are deleted, the restored file is renamed into place, and the database provider is reset. Migrations run on open.
6.  Folder permissions from the old phone are invalid, so the backup folder and each source folder are marked "pick again". After that, "Re-link by folder" runs.

**Migrations:**

*   Every schema version has a committed Drift `make-migrations` snapshot and a generated test.
*   Migrations only add.
*   Release builds never drop and recreate the database.

**Integrity check:** `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, and "at most one open session".

*   **When:** after the first frame on startup, and after a restore.
*   **On failure:** the result goes to the log and to Diagnostics. Nothing is changed automatically.

**Startup order:**

1.  **Before the first frame:**
    1.  the pre-migration check — normally just one `user_version` read;
    2.  open the database;
    3.  read today's frozen plan, or build it if missing.
2.  **After the first frame:**
    1.  integrity check;
    2.  reconcile notifications;
    3.  backup if due.

Drift runs its queries in a background isolate.

### 8a. Exam export and import

**Two backup tools.** The whole-app backup (§8) and the exam file have different jobs:

| | Whole-app backup | Exam file |
| --- | --- | --- |
| Purpose | Recover from a lost phone, corruption or a failed update | Share, reuse, move or archive one exam |
| Trigger | Automatic | User action |
| Format | SQLite copy | Versioned JSON |
| Restore | Replaces everything | Adds rows only, never merges existing rows |

**File: `<exam name>.prepbelt.json`.** Keys are snake_case and written explicitly, never generated from Dart field names.

```text
{
  "format": "prepbelt-exam",  "format_version": 1,
  "app_version": "...",       "exported_at_utc": 1761...,
  "mode": "structure" | "progress",
  "exam":     { id, name, exam_date },
  "subjects": [ { id, name, sort_order, also_used_by?: [exam names] } ],
  "nodes":    [ { id, subject_id, parent_id, kind, task_kind, title, position_text,
                  base_minutes, sort_order, created_at_utc } ],
  "sources":  [ { node_id, source_type, url?, file_name, file_size, location_note?,
                  excerpt? } ],
  "events":   [ ...progress mode only: review_events rows minus session_id... ]
}
```

#### Export rules

*   **Scope.** The file includes the exam, every subject linked to it, and every live (not deleted) node under those subjects, together with their sources. The Inbox is never exported.
*   **Phone-specific fields are dropped.** `folder_id` and `relative_path` only make sense on this phone. `file_name` and `file_size` are kept so the source can be re-linked.
*   **"Include notes and excerpts"** is a switch on the export screen. It controls four kinds of private content: excerpts, location notes, `ai_chat` URLs (often private shared-chat links) and `also_used_by` (the names of your other exams). All four are written only when the switch is on.
    *   Structure exports: off by default.
    *   Progress exports: on by default.
    *   Archives: always on (see below).
*   **Progress mode** adds every `review_events` row for those nodes, with `session_id` set to null.
    *   An undo always stays in the file together with the event it undoes, because both belong to the same node.
    *   A catch-up batch (`batch_id`) may appear only partly in the file. That is harmless, because a batch only groups events for undo.
*   **Never exported:** sessions, plans and settings.
*   **Progress exports sent through the share sheet** show one warning line first: "Includes your notes and history".

#### Import rules (`ImportExam`)

1.  **Read and check.**
    *   Only files of 20 MB or less are parsed.
    *   `format` must be `prepbelt-exam`.
    *   A `format_version` newer than the app knows is rejected with "Update the app to import this file".
    *   `validate` then checks:
        *   every reference (`subject_id`, `parent_id`, `node_id`, `undoes_event_id`) points inside the file;
        *   a node's parent is in the same subject;
        *   no ID appears twice in the file;
        *   the depth rule holds, and no task has both subtasks and events;
        *   events sit only on reviewable nodes;
        *   each event's columns follow the event-type rules, and an `undoes_event_id` points to an earlier, non-undo event on the same node;
        *   enum values are known, `base_minutes` is between 10 and 50, excerpts are no longer than 20,000 characters, and `scheduler_version` is 1.
    *   Any failure rejects the whole file with a specific message, and nothing is written.
2.  **Decide IDs per subject** (progress mode).
    *   **Subject already on this phone** (same ID; this happens when you re-import an archive, or move a second exam that shares a subject): the exam is linked to the existing subject. That subject's nodes, sources and events in the file are skipped, and existing rows are never changed.
    *   **Subject not on this phone, and none of its node or event IDs exist here, including soft-deleted rows:** insert it with its original IDs.
    *   **Otherwise:** give that subject, its nodes and its events new IDs (remap).
    *   The exam keeps its ID unless that ID already exists, in which case it gets a new one.
    *   In **structure mode**, everything always gets new IDs.
3.  **Name clashes.** This step applies to every subject that is about to be inserted, in both ID modes.
    *   If its name matches an existing subject, the user chooses:
        *   **Add to existing.** No subject row is inserted. Every imported node gets the existing `subject_id`. The exam is linked to the existing subject. Imported top-level `sort_order` values are shifted so they come after the existing maximum. The import screen shows which other exams already use that subject.
        *   **Keep separate.** The subject is inserted under the first free name of the form "{name} 2", "{name} 3", and so on.
    *   The Inbox is never offered as a clash target and is never linked to an exam. A file subject named "Inbox" is always kept separate, as "Inbox 2".
    *   Imported subjects are always inserted with `is_inbox = false`. New subjects are sorted after the existing ones.
4.  **Write everything in one transaction.**
    *   Insert the exam (with the date the user chose), the subjects, `exam_subjects`, nodes and sources.
    *   PDF sources arrive as `not_linked`, and URL sources as `ok`.
    *   In progress mode, insert the events, then compute `item_state` with `deriveState`. State in the file is never trusted.
    *   In structure mode, every item starts Unread.
5.  **After import.** Refresh today's plan, then offer "Re-link by folder" if PDF sources were imported.

#### Copy as new attempt

This runs a structure-mode export and import in memory, with the new exam name and date the user enters. There is no clash step: subjects are always kept separate, under the first free name "{name} 2", "{name} 3", and so on. This keeps the new attempt from mixing with the old one.

#### Archive and remove (`ArchiveAndRemove`)

1.  **Check first.**
    *   A backup folder must be chosen and writable.
    *   No session may be open on an item that would be removed. If one is: "Finish or discard the running session first".
2.  **Export.** Write a progress-mode export, with notes always included, into the backup folder.
3.  **Read the file back.** Parse it, run `validate`, and compare its node and event counts with the database. Any mismatch stops the archive, and nothing is deleted.
4.  **Confirm.** The user confirms by typing the exam name. The confirmation shows where the file was saved.
5.  **Delete, in one transaction**, the exam, its `exam_subjects` rows, and every subject linked to no other exam. For those subjects, delete in this order:
    1.  plan rows
    2.  events
    3.  `study_sessions`
    4.  `item_state`
    5.  sources
    6.  nodes
    7.  the subjects themselves

    In the same transaction, `last_used_subject_id` and `last_used_topic_id` are cleared if they point at removed rows.
6.  **What survives.** Subjects that another exam still uses are kept, unchanged. Re-importing the archive later links back to them (step 2 above). This is the only hard delete in the app.

#### Receiving exam files

*   Exam files arrive by Share to app, through `SEND` filters for `application/json` and `application/octet-stream`.
*   **Sorting a shared file:**
    *   A JSON file of 20 MB or less with `"format": "prepbelt-exam"` opens the Import screen.
    *   A PDF follows §7.
    *   Any other file is rejected with "Unsupported file".
*   An exam file shared before onboarding is held, like a capture, and the Import screen opens once onboarding finishes.
*   **Exams → Import** picks a `.prepbelt.json` file from a granted folder.

### 9. Notifications and reminders

`NotificationPort` is built on `flutter_local_notifications`. All scheduled notifications are inexact, and the app never asks for the exact-alarm permission.

| Notification | Content | When |
| --- | --- | --- |
| Daily reminder | "Your study plan is ready" | Daily at `reminder_time` (default 07:00) |
| Ongoing session | "{task} · {position}", chronometer, Done action | While a session is open |
| Still reading? | "Still on {title}? Tap to finish." | Start + 2 × base time |

*   **Reconcile.** `ReconcileNotifications` reschedules everything on app open, after writes that affect sessions, after a reboot, and after an app update. The last two are handled by the plugin's boot and update receivers.
*   **Permissions.** During onboarding the app requests the notification permission (Android 13+). For battery optimisation, it explains why turning it off helps and opens `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`.

### 10. Navigation, state and screens

*   **State.** Riverpod, with plain `Notifier` / `AsyncNotifier` classes and no code generator. Screens watch narrow Drift queries. Today watches the frozen plan rows.
*   **Navigation.** go_router routes: `/onboarding`, `/today`, `/library`, `/item/:id`, `/add`, `/exams`, `/settings`, `/diagnostics`. Notification taps carry a route.
*   **Session sheets.** The Finish and Grade sheets are bottom sheets shown over Today, not routes.

#### Screens

| Screen | Contents |
| --- | --- |
| Onboarding | Start fresh or Restore; exam, subject, daily minutes, first item; permissions; battery explainer |
| Today | Plan list (title, belt chip, minutes, Start), summary line, waiting line, catch-up prompt / Undo catch-up, backup banner, Refresh |
| Library | Exam filter; subject → topic/task/subtask tree with "Weakest: X · n/N Green" and a stacked bar; Inbox section |
| Item | Details, source card (open / re-link / location note), "Why is this due?", last 5 events, Undo latest |
| Add / Quick add | Title + up to 3 taps (last-used subject and topic preselected); full form; split tool (only for tasks with no history); in-app folder browser |
| Share capture sheet | Opens when content is shared to PrepBelt; pre-filled title, source preview, subject (Inbox by default), Save |
| Finish sheet | Editable minutes, "Did you finish?" when stale, Discard |
| Grade sheet | Forgot / Shaky / Solid, each with its definition and next date; PYQ line; drop message |
| Exams | Create, edit and link subjects; Archive (keep in app) or Archive → Export and remove; Export (Structure only / With progress, with an "Include notes and excerpts" switch); Import; Copy as new attempt |
| Import screen | File summary, editable exam name and date, ID mode notice, one subject-clash choice per clashing subject, Import |
| Settings | Daily minutes, day-start hour, reminder time, backup folder, Back up now, Restore, source folders, Re-link by folder |
| Diagnostics | Notification permission, battery-optimisation status with a settings button, last reminder scheduled, Send test notification, integrity result, Share logs |

**Grade definitions:**

*   **Forgot** — "Couldn't recall the main points."
*   **Shaky** — "Recalled some, with gaps or after peeking."
*   **Solid** — "Could explain it without looking."

### 11. Logging

*   **Log files.** `package:logging` writes to a rotating file sink: 2 × 1 MB in app-private storage. It records scheduler decisions, plan builds, sessions, notification scheduling, backups, restores, migrations and errors.
*   **Crashes.** `FlutterError.onError` and `PlatformDispatcher.instance.onError` write to `crash.log`.
*   **Share logs.** Zips the logs, `crash.log`, the app and schema versions, the device and OS version (`device_info_plus`), the time zone and the permission states. The zip goes out through the share sheet. The database is not included, and nothing is uploaded automatically.

### 12. Testing strategy

| Layer | Tests |
| --- | --- |
| BeltPolicy | Example table for every belt × grade pair, plus `first_study`, plus every explanation template |
| EffectiveDue | Last review on T, ladder due T+7. Expected: no deadline → T+7; exam T+40 → T+7; exam T+3 → T+2; exam T+2 → T+1; exam T+1 → T+7 (no cap); exam on T → ignored by the resolver → T+7; exam passed or archived → T+7 |
| Properties | For random event sequences: `interval ≥ 1`; `ladderDue > review date`; the belt stays within the ladder; if `deadline ≥ lastReview + 2` then `effectiveDue ≤ deadline − 1`; state derived from events matches the state written per event; undo restores the previous outputs |
| Planner | Never over budget; at least one first reading whenever unread items exist and the next one fits the budget; second pass; reason rules; summary strings; deterministic order |
| CatchUp | Capacity projection; assignments respect `latest`; `wontFit` counts; no-deadline items stay waiting; batch undo |
| Simulation | 300 items, 2 exams (days 45 and 80, one shared subject), budget 90, 90 days, 15% missed days, random grades (60% Solid / 30% Shaky / 10% Forgot), catch-up accepted when offered, 20 seeds; asserts Goal 5 as restated by D12. A Python port (`tool/sim/planner_check.py`) runs the same model where Dart isn't available |
| Clock | 03:59/04:00 IST, a time-zone change, Europe/London across DST |
| Data | In-memory Drift: DAOs, rollup query, event CHECK constraints, open-session index, backup → restore round trip, refusing a newer schema, generated migration tests |
| ShareClassifier | AI-chat hosts, plain web URL, text without a URL, text with several URLs (first one wins), PDFs, title fallbacks, 80-character cut |
| ExamPackage | Round trip in both modes; remapping of references, `undoes_event_id` and `batch_id`; per-subject ID decision (existing subject linked and skipped; clean subject keeps IDs; clashing subject copied); every `validate` rule; newer format version; privacy fields dropped when notes are off; "add to existing" moves `sort_order` and never targets the Inbox; first free name; Copy as new attempt never merges; `item_state` after import equals the source phone's state |
| Archive and remove | Shared subjects survive; unshared subjects and their data (including sessions) are removed; nothing is deleted if the export or the read-back check fails; blocked by an open session or a missing backup folder; `last_used_*` cleared |
| Widgets | Today, Grade sheet, Finish sheet, Library label, Share capture sheet, Import screen |
| Device | Emulator integration tests on API 26 and API 36: session start → finish, backup → restore. Kill-and-relaunch is a manual release check |
| Layouts (D14) | Widget tests of the shell, Today, Library and Item at 390 × 844, 800 × 1280 and 1280 × 800: the bottom bar or rail, one or two panes, and the selected item kept across a resize |
| iOS (D13) | The same unit and widget tests on a macOS CI runner; integration tests on an iOS simulator; manual checks of folder access, Share Extension, notifications and restore on a real iPhone |

### 13. iOS and tablet layouts (D13, D14)

#### Platform layer on iOS

Every row below is an implementation of an interface that already exists in `app/lib/platform/`. Since the 2026-10-27 cleanup, only `data/` and `platform/` touch `dart:io` (implementation plan item 105), so nothing above them changes.

| Interface | Android (today) | iOS |
| --- | --- | --- |
| `FolderAccess` | `saf`: persisted tree URIs | Swift channel `prepbelt/files`: the folder picker (`UIDocumentPickerViewController` for folders), security-scoped bookmarks stored in place of tree URIs, and list, walk, read-copy, write and delete inside a bookmarked folder. iCloud Drive files that are not downloaded are fetched through `NSFileCoordinator` |
| `SourceOpener` | `ACTION_VIEW` intent through `android_intent_plus` | PDFs open in an in-app Quick Look preview, with the system "Open in…" menu for other readers. Web, AI-chat and app links use `url_launcher`, as on Android |
| `ShareReceiver` | `receive_sharing_intent` with Android intent filters | The same plugin with a Share Extension target and an App Group. The share subject line is not available, so titles use the other fallbacks in §7 |
| `NotificationPort` | Ongoing chronometer notification, "Still on…?", daily reminder | Daily reminder and "Still on…?" as local notifications. No ongoing notification (Open Question 3) |
| `DeviceStatus` | Battery-optimisation state through the Kotlin channel | Not applicable. The battery explainer is hidden, and Diagnostics shows "Not applicable on iOS" |
| `FileSharer`, `LocalFiles` | `share_plus`, `dart:io` | The same; the share sheet needs a source rectangle on iPad |

*   **Folders, not files, still holds.** A folder bookmark covers every file below it, which is the iOS counterpart of §7's reason for granting folders.
*   **Exam files.** PrepBelt declares a document type for `.prepbelt.json`, so tapping one in Files or Mail offers PrepBelt, and it arrives through the same Import flow as a share (§8a "Receiving exam files").
*   **Restore on a new iPhone.** Bookmarks don't move between devices, just as tree URIs don't on Android. Restore marks folders "pick again", and Re-link by folder works unchanged (CUJ 7).
*   **Database location.** Application Support, the same `prepbelt.sqlite`. Device backup follows Open Question 2.
*   **Privacy.** No network use, as on Android: no networking code and no App Transport Security exceptions. The app ships a privacy manifest (`PrivacyInfo.xcprivacy`) declaring the required-reason APIs the plugins use. The App Store privacy label is "Data Not Collected".
*   **Release rules for iOS**, the counterpart of the Android rules: no network entitlement or background modes, local notifications only, and no tracking.

#### Adaptive layouts

*   **Window classes.** Read from `MediaQuery.sizeOf(context).width` in one place (`core/layout.dart`): compact < 600, medium 600–839, expanded ≥ 840 logical pixels.
*   **Navigation.** Compact keeps the bottom `NavigationBar`. Medium and expanded use a `NavigationRail` with the same destinations, in the same `StatefulShellRoute`.
*   **Two panes (expanded).**
    *   **Library:** the tree on the left (400 dp wide); the selected item's screen on the right. Selecting a row shows the item instead of pushing `/item/:id`. The selection is screen state, kept per tab, not a route; `/item/:id` and notification routes are unchanged.
    *   **Today:** the plan list on the left, the selected item on the right. Start, the Finish sheet and the Grade sheet behave as on the phone.
    *   Inside the right pane, opening a child item replaces the pane, and deleting the item clears it.
    *   With nothing selected, the right pane shows a short hint.
    *   On a resize below expanded, a selected item becomes a pushed Item screen, and Back returns to the list. A pushed Item screen stays pushed when the window grows again.
*   **Reading width.** Forms, Settings, Exams, Diagnostics and onboarding are centred, with a maximum content width of 640 dp.
*   **Sheets.** Bottom sheets stay bottom sheets, with Material 3's default maximum width of 640 dp. Dialogs keep their Material size.
*   **Orientation.** Both orientations on every device. The app does not lock orientation.
*   **Input.** Hardware keyboards and pointers work through the Material widgets' defaults. Enter submits Quick add.

--------------------------------------------------------------------------------

## Alternatives Considered

Each entry records a rejected option and why it was rejected. Reopen one only if its reason no longer holds.

### Product

#### Alternative A: Use AnkiDroid with one card per chapter

*   **Pros:**
    *   Exists already: offline, a mature scheduler, backups and reminders.
    *   No development cost.
*   **Cons:**
    *   No exam dates.
    *   Daily load is counted in cards, not minutes.
    *   No chapter hierarchy, no timer, no "planned" state, no belts.
*   **Reason for rejection:** The three things this app exists for are exam-date capping, a plan in minutes, and progress per chapter. Anki has none of them.

#### Alternative B: Cloud sync with accounts

*   **Pros:**
    *   Use on more than one device.
    *   Backups kept off the phone.
*   **Cons:**
    *   Needs a network, accounts, privacy handling and server costs.
    *   Needs conflict resolution for the event log.
*   **Reason for rejection:** The author requires fully offline use. Backups to a folder that the user's own cloud-drive app syncs cover the risk of losing the phone.

### Scheduling and planning

#### Alternative C: FSRS scheduler in v1

*   **Pros:**
    *   Better model of forgetting.
    *   Handles late reviews well.
    *   A package exists.
*   **Cons:**
    *   Its intervals are hard to explain.
    *   Belts would become an arbitrary mapping onto its numbers.
    *   It is tuned for flashcards.
*   **Reason for rejection:** Author decision (D5), favouring explainability. The event log keeps a switch later possible.

#### Alternative D: A swappable scheduler interface now

*   **Pros:**
    *   A later switch to another scheduler is smaller.
*   **Cons:**
    *   An abstraction with only one implementation.
*   **Reason for rejection:** Add it when a second scheduler is written.

#### Alternative E: Plan by item count instead of minutes

*   **Pros:**
    *   Simpler.
    *   Familiar from other apps.
*   **Cons:**
    *   Items take 10–50 minutes, so a count says little about time.
    *   It can't hold back time for new reading.
*   **Reason for rejection:** The core requirement is to split a fixed daily time.

#### Alternative F: Rebuild Today live on every change

*   **Pros:**
    *   Always current.
    *   No plan tables.
*   **Cons:**
    *   The list reshuffles while the student is working through it.
    *   The day's summary and catch-up state have nowhere to live.
*   **Reason for rejection:** A plan frozen once per day, with Refresh, stays stable and explainable.

#### Alternative G: Carry-over only, with no catch-up action

*   **Pros:**
    *   Less code.
    *   The daily cap and deadline-first ordering already limit what is shown.
*   **Cons:**
    *   After a long gap, the student can't see how many days the backlog will take or whether it fits before the exam.
*   **Reason for rejection:** Author decision (D7) to keep catch-up. It is limited to moving due dates in one batch that can be undone, and it never changes belts.

#### Alternative H: Parent shows only the lowest child belt, or only the counts

*   **Pros:**
    *   Simpler display.
*   **Cons:**
    *   Lowest only: one forgotten chapter colours the whole book.
    *   Counts only: hides the weak spot.
*   **Reason for rejection:** Author decision (D6) to show both.

#### Alternative H2: Store the exam-capped due date

*   **Pros:**
    *   The planner reads a single column.
*   **Cons:**
    *   Every exam edit, archive or passing date leaves stale stored dates.
    *   Replaying history would need past exam dates.
*   **Reason for rejection:** Applying the cap when a date is read costs one `min` per item and keeps stored data correct.

### Data and storage

#### Alternative I: Store only current state, with no event log

*   **Pros:**
    *   Fewer tables.
*   **Cons:**
    *   No undo, no explanations, no recovery after a bad migration, and no path to FSRS.
*   **Reason for rejection:** None of those can be added later for data that was never recorded.

#### Alternative I2: Rebuild state by replaying the whole log

*   **Pros:**
    *   Undo at any point in history.
    *   A self-check that state matches history.
*   **Cons:**
    *   Needs historical exam dates.
    *   Gives false mismatches after exam edits.
    *   Adds complexity that only mid-history undo needs.
*   **Reason for rejection:** v1 undoes only the newest event and reads state from the stored outputs of the last valid event.

#### Alternative J: Five typed tables (Exam, Subject, Topic, Task, Subtask)

*   **Pros:**
    *   A strict type for each level.
*   **Cons:**
    *   Five copies of the move, delete and roll-up logic.
*   **Reason for rejection:** Typed exams and subjects plus one `study_nodes` tree keep type safety where it matters.

#### Alternative K: A fully generic tree

*   **Pros:**
    *   One table, unlimited depth.
*   **Cons:**
    *   A subject shared between exams fits a tree badly.
    *   Validation moves into code.
*   **Reason for rejection:** The many-to-many link between exams and subjects is a requirement.

#### Alternative L: Isar, Hive or ObjectBox instead of Drift

*   **Pros:**
    *   Fast.
    *   No SQL.
*   **Cons:**
    *   The data is relational, roll-ups need recursive queries, and Isar has had periods without releases.
*   **Reason for rejection:** Drift fits the data, has a tested migration workflow and produces a standard SQLite file.

#### Alternative M: JSON export as the backup format

*   **Pros:**
    *   Human-readable.
*   **Cons:**
    *   A second format to version.
    *   Loads the whole database into memory.
    *   Renaming a field changes the file.
*   **Reason for rejection:** A `VACUUM INTO` copy plus `backup_meta` and the existing migrations already gives versioned backups.

#### Alternative N0: Per-exam export instead of a whole-app backup

*   **Pros:**
    *   One file format instead of two.
    *   Users choose what to keep.
*   **Cons:**
    *   It only happens when the user remembers to do it.
    *   Subjects shared between exams would be imported twice.
    *   The Inbox, settings and unlinked subjects would be lost.
    *   A lost phone would mean importing exams one by one.
*   **Reason for rejection:** Per-exam export is for sharing, reuse, moving and archiving (D11). Recovering from a disaster still needs the automatic whole-app backup.

#### Alternative N: Merge an imported backup into existing data

*   **Pros:**
    *   Combines data from two phones.
*   **Cons:**
    *   Needs conflict rules for every table.
*   **Reason for rejection:** Not needed with one device. UUIDs keep it possible later.

#### Alternative O: Android Auto Backup as a second backup

*   **Pros:**
    *   Free, and survives losing the phone.
*   **Cons:**
    *   It copies the live WAL database, so the copy can be inconsistent.
    *   On reinstall it restores silently, skipping every restore check.
    *   It has a 25 MB cap.
    *   It contradicts the privacy statement.
*   **Reason for rejection:** D9. The app's own backups to a synced folder cover the same risk.

### Sources and files

#### Alternative P: Keep access to each PDF file separately

*   **Pros:**
    *   The simplest picker.
*   **Cons:**
    *   Android limits kept file permissions to 128, or 512 on Android 11+.
    *   Each file must be re-linked after a restore.
*   **Reason for rejection:** Folder grants avoid the limit and allow re-linking in bulk.

#### Alternative Q: A hand-written Kotlin channel for file access

*   **Pros:**
    *   No third-party dependency.
*   **Cons:**
    *   About 300 lines of native code.
    *   Activity-result handling in `FlutterActivity`.
    *   Two more native channels.
*   **Reason for rejection:** D8. As of 2026-10-26, `saf` 2.1.x covers picking a folder, keeping its permission, walking it with relative paths, writing, deleting and copying to a local file, with typed errors. `android_intent_plus` covers opening a file in another app. A Kotlin file-access channel is the fallback if `saf` is abandoned. The only Kotlin in v1 is the small two-method channel described in D8.

#### Alternative R: Copy source files into the app

*   **Pros:**
    *   Links never break.
*   **Cons:**
    *   Doubles storage.
    *   Large backups.
    *   Ignores the student's own folders.
*   **Reason for rejection:** The cost outweighs the benefit in v1.

#### Alternative S: A separate Source table

*   **Pros:**
    *   One record per book, reusable anywhere.
*   **Cons:**
    *   More screens and links between records.
*   **Reason for rejection:** Subtasks inheriting the task's source covers the main case.

### Timer and notifications

#### Alternative T: A foreground service, or saving "Done" in the background

*   **Pros:**
    *   Finishing a session needs no screen.
*   **Cons:**
    *   Android 14 restricts foreground service types.
    *   Uses battery.
    *   A second isolate writing to SQLite risks lock errors.
*   **Reason for rejection:** Storing the start time and finishing in the app is simpler and keeps one writer.

#### Alternative U: Usage-stats detection, or a floating timer

*   **Pros:**
    *   Fewer taps.
*   **Cons:**
    *   Needs special permissions that Play reviews.
    *   Usage stats can't tell which document is open.
*   **Reason for rejection:** The ongoing notification covers most of the need.

#### Alternative V: Exact alarms

*   **Pros:**
    *   Reminders arrive on time.
*   **Cons:**
    *   Denied by default on Android 14+.
    *   Play limits the permission to alarm and calendar apps.
*   **Reason for rejection:** Nothing in the app breaks if a reminder is delayed.

### Flutter stack

#### Alternative W: Bloc or ChangeNotifier instead of Riverpod

*   **Pros:**
    *   Bloc: explicit events and states.
    *   ChangeNotifier: no extra dependency.
*   **Cons:**
    *   Bloc: per-screen event and state classes.
    *   ChangeNotifier: awkward with Drift streams and with test overrides.
*   **Reason for rejection:** Riverpod with plain notifiers gives dependency injection and stream handling without code generation. Any of the three would work.

#### Alternative X: freezed and riverpod_generator

*   **Pros:**
    *   Less hand-written equality and provider code.
*   **Cons:**
    *   Two more code generators.
    *   Domain models duplicated next to Drift's.
*   **Reason for rejection:** Dart 3 sealed classes and records are enough.

#### Alternative Y: Plain Navigator instead of go_router

*   **Pros:**
    *   One fewer dependency.
*   **Cons:**
    *   Opening a screen from a notification tap is awkward.
*   **Reason for rejection:** go_router is maintained by the Flutter team and handles this case.

--------------------------------------------------------------------------------

## Risks & Mitigations

| # | Risk | Impact | Mitigation | Section |
| --- | --- | --- | --- | --- |
| R1 | The PYQ app shows the same questions each time, so early reviews test memory of answers | Belts overstate understanding for PYQ tasks | PYQ guidance line on the grade sheet; split papers by year | D1 |
| R2 | Phone-maker battery managers (Xiaomi, Oppo, Vivo) or Android 14 swipe-dismissal remove notifications and alarms | Missed reminders; the session notification disappears | Sessions live in the database, and reopening the app always finds them; battery explainer; Diagnostics status; reconcile on every open | §6, §9 |
| R3 | Folder permissions don't move to a new phone | Sources and backups stop working after restore | Restore marks the folders "pick again"; Re-link by folder; CUJ 7 | §7, §8 |
| R4 | SQLite file corruption | Data loss | WAL; `VACUUM INTO` backups (7 rotating, plus pre-migration and safety copies); integrity check on startup and after restore | §8 |
| R5 | `saf` is a single-maintainer package and could be abandoned | Blocked Flutter upgrades | All file access sits behind `FolderAccess`; the fallback is a Kotlin channel with the same interface | D8, §7 |
| R6 | Performance on 2–4 GB phones with thousands of items | Slow start, janky lists | Frozen plan read before the first frame; other work after it; indexed queries; profiling on a 5,000-item seed | §8, NFR |
| R7 | Play policy changes on permissions or target SDK | Rejected update | Only notification and boot permissions; no exact alarms, battery exemption request, usage access or overlay; target SDK kept current | NFR |
| R8 | The student taps Solid when unsure | The schedule drifts from real recall | Grade definitions and next-date preview; Undo; parent shows counts as well as the weakest belt | §3, D6 |
| R9 | The user never picks a backup folder | Losing the phone loses the data | Private backups kept; Today banner until a folder is chosen | §8 |
| R10 | `receive_sharing_intent` is abandoned, or Android revokes a shared file's access before it is read | Sharing stops working, or a shared PDF arrives without its name and size | Sharing sits behind the `ShareReceiver` interface, so the plugin can be swapped; name and size are read the moment the share arrives; a PDF that can't be read is saved as a not-linked source titled from the share subject | D10, §7 |
| R11 | An exam file leaks private content, or an import goes wrong | Private excerpts, AI-chat links or exam names leak when sharing; data is duplicated or corrupted | Private fields are off by default in structure exports; progress shares show a warning; imports are fully validated and run in one transaction; IDs are decided per subject, and existing rows are never changed | §8a |
| R12 | "Export and remove" deletes data the user wanted to keep | Permanent loss of exam history | A backup folder is required; the file is read back and checked before any delete; the user types the exam name to confirm; shared subjects are kept; running sessions block the archive | §8a |
| R13 | iOS folder bookmarks go stale, or an iCloud Drive file is not downloaded when opened | Sources and backups fail on iPhone | Stale bookmarks are refreshed when iOS allows it, and otherwise the folder shows "pick again"; files are fetched through `NSFileCoordinator`; Re-link by folder | §13 |
| R14 | With no ongoing notification on iOS, students forget a running timer | Inflated or discarded minutes | The "Still on…?" reminder; the Finish sheet on every open; the stale-session rule in §6 | §6, §13 |
| R15 | The Windows development PC cannot build or run iOS | iOS problems are found late | macOS CI builds and tests every change once M9 starts; manual checks on a real iPhone before TestFlight | D13 |

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Privacy:**
    *   The release build declares no `INTERNET` permission.
    *   Android Auto Backup is off (`allowBackup="false"`).
    *   No analytics, crash upload or ads.
    *   Nothing leaves the phone except backup files and shared logs, which the user creates on purpose.
*   **Play policy:**
    *   No exact-alarm permissions.
    *   No `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
    *   No usage-access or overlay permissions.
    *   Target SDK 36, which Play has required for updates since 31 Aug 2026.
*   **Performance**, measured in profile mode on a 5,000-item seed on a 4 GB device:
    *   cold start to first useful frame ≤ 1.5 s;
    *   Library ≤ 100 ms;
    *   plan build ≤ 50 ms;
    *   backup ≤ 3 s.
*   **Accessibility:**
    *   Every belt chip shows its name and step ("Orange · 2/5").
    *   TalkBack labels on all controls.
    *   Layouts work at 200% font scale.
*   **Rollout:**
    *   Play internal-testing track first.
    *   Migrations only add.
    *   A pre-migration backup is taken before each schema change.
    *   Play does not allow downgrades, so fixes ship as new releases.

--------------------------------------------------------------------------------

## Milestones

| # | Milestone | Proves |
| --- | --- | --- |
| M1 | `prep_core`: belts, policy, effective due, deadlines, hierarchy, split, planner, catch-up, simulation | Goals 1–5 without any UI |
| M2 | Data layer: Drift schema v1, DAOs, event rules, integrity check, migration setup | Storage rules |
| M3 | Today, Library, Item, Add, Split, Grade sheet, Exams, onboarding | CUJ 1, 2, 4, 6, 8 |
| M4 | Timer, Finish sheet, notifications, reconcile | CUJ 3a–3c |
| M5 | Folder access (`saf`), folder browser, source opening, re-link, Share to app | CUJ 2, 2b, 2c, CUJ 7 (re-link) |
| M6 | Backups, pre-migration backup, restore, catch-up UI | CUJ 5, CUJ 7 |
| M6b | Exam export and import, copy as new attempt, archive and remove | CUJ 9–12 |
| M7 | Diagnostics, logging, Share logs, performance pass | Goals 10, 11 |
| M8 | Adaptive layouts: window classes, navigation rail, two panes for Library and Today, reading width (D14) | Every CUJ on a tablet, a foldable and in split screen |
| M9 | iOS: project, Swift folder channel, Quick Look opener, Share Extension, notifications, privacy manifest, macOS CI (D13) | Every CUJ on iPhone and iPad, except the live timer outside the app |

The file-by-file plan, conventions and verification commands are in the [implementation plan](../plans/prepbelt_implementation.md).

--------------------------------------------------------------------------------

## Future Improvements

*   FSRS scheduler, seeded from `review_events`.
*   Pause; per-weekday budgets; base-time calibration from sessions; review cost by belt.
*   Backups that include source files; JSON export; merge on import.
*   Debug bundle with a redacted database; crash-exit detection.
*   A Live Activity for the running timer on iOS.

--------------------------------------------------------------------------------

*Drafted with EGM*
