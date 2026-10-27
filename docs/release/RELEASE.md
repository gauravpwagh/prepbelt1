# Releasing PrepBelt to the Play internal-testing track

The design's rollout rule is internal testing first, and the steps below follow it. Some steps can only be done by the author: creating the upload key, owning the Play Console account, and pressing **Release**. Those are marked **(you)**.

## 1. Create the upload key (you, once)

Keep the keystore and its passwords outside the repository and back them up. If you lose them, you can't ship updates under the same upload key without a Play reset request.

```sh
keytool -genkeypair -v -keystore %USERPROFILE%\keys\prepbelt-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
```

Then create `app/android/key.properties`. It is gitignored, as is `*.jks`:

```properties
storeFile=C:/Users/<you>/keys/prepbelt-upload.jks
storePassword=<the store password>
keyAlias=upload
keyPassword=<the key password>
```

`app/android/app/build.gradle.kts` signs release builds with this file. Without it, it falls back to the debug key and logs a warning. That fallback is what CI uses, and Play rejects debug-signed bundles.

In Play Console, use **Play App Signing** (the default). Google holds the app signing key, and your key above is only the *upload* key.

## 2. Bump the version (each upload)

In `app/pubspec.yaml`, `version: 0.1.0+1` is `versionName+versionCode`. Every upload needs a higher `versionCode`, the number after `+`. Keep `app/lib/core/app_info.dart` (`appVersion`) equal to the version name.

## 3. Check and build

From the repository root:

```sh
flutter pub get
dart run tool/check_imports.dart
(cd packages/prep_core && dart analyze --fatal-infos && dart test)
(cd app && dart run build_runner build && flutter analyze && flutter test)
(cd app && dart run drift_dev make-migrations) # must leave no git changes
(cd app && flutter build appbundle --release)
```

The bundle is at `app/build/app/outputs/bundle/release/app-release.aab`.

Confirm the release permissions, either with bundletool or on the APK from `flutter build apk --release`:

```sh
aapt2 dump permissions app/build/app/outputs/flutter-apk/app-release.apk
```

The expected list is `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE` (added by the notification plugin) and the AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. There must be **no** `INTERNET`, no exact-alarm permission, and no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

## 4. Play Console (you)

1. **Create app:** name "PrepBelt", app (not game), free.
2. **App content:**
    * **Privacy policy:** host [privacy-policy.md](privacy-policy.md), for example on GitHub Pages, and enter its URL.
    * **Ads:** no.
    * **App access:** all features are available without special access (no login).
    * **Content rating:** questionnaire, category Education/Reference. No violence, user interaction or location sharing. Expected rating: Everyone / PEGI 3.
    * **Target audience:** 18 and over is the simplest. Competitive-exam aspirants are adults, and choosing under-13 brings in Families policy requirements.
    * **Data safety:** see the answers below.
    * **Government app, financial features, health:** no.
3. **Store listing:** use the text in [store-listing.md](store-listing.md). The 512×512 icon is ready: [play-icon-512.png](play-icon-512.png), drawn from the launcher icon in `app/android/app/src/main/res/drawable/ic_launcher_foreground.xml`. Graphics you still need to make:
    * a 1024×500 feature graphic;
    * at least two phone screenshots (Today, Library and the grade sheet work well).
4. **Testing → Internal testing:** create an email list of testers, upload `app-release.aab`, paste the release notes from [store-listing.md](store-listing.md), then **Review and roll out**.
5. Send testers the opt-in link and [test-checklist.md](test-checklist.md).

### Data safety answers

* **Does your app collect or share any of the required user data types?** No.
    * Everything stays in the app's private storage on the phone.
    * The app has no internet permission.
    * Backups and exam files are written only to folders the user picks, and leave the phone only when the user shares them.
    * Shared logs go out only through the system share sheet, when the user chooses.
* **Is all user data encrypted in transit?** Not applicable: nothing is transmitted.
* **Can users request data deletion?** Uninstalling removes all app data. Within the app, Exams → Archive → Export and remove deletes an exam's data.

## 5. After the internal release

* Collect Share logs zips from testers when something goes wrong. They contain logs and device facts, never the database.
* Before promoting to closed or open testing, run the manual release checks in the implementation plan's Verification Plan on a Xiaomi, Oppo or Vivo phone, and measure the NFR performance numbers in a profile build (`flutter run --profile`, with `app/test/perf/seed_5k.dart` for data).
* Migrations only add. Any schema change bumps `AppDatabase.currentSchema` and commits the new `make-migrations` snapshot; the pre-migration backup runs automatically on upgrade.

## Pre-flight already done (2026-10-27)

On the Pixel 9 API 35 emulator, the release build (R8-shrunk, debug-signed) was run through:

* **Onboarding (CUJ 1):** the first item shows as a done row at Red.
* **Permissions:** the notification permission prompt, and the battery optimisation settings screen.
* **Backup folder:** picked through SAF, and the first backup was written there.
* **Daily reminder:** scheduled as an inexact alarm at 07:00 local time.
* **Session:** Start showed the ongoing notification with Done. Reopening the app brought the Finish sheet back; Finish wrote the first study and cleared the notification.
* **Errors:** none in the log.
