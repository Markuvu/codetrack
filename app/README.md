# CodeTrack — Flutter app

This folder contains the Dart source only. Generate platform folders once:

```bash
flutter create . --project-name codetrack
flutter pub get
```

## ⚠️ Required: Android build config (do this after `flutter create`)

The generated `android/` folder needs two tweaks or the build fails with
"requires core library desugaring" / NDK version warnings
(`flutter_local_notifications` needs them).

Edit `android/app/build.gradle.kts`:

1. Inside the `android { ... }` block, pin the NDK version:

```kotlin
ndkVersion = "27.0.12077973"
```

2. In the `compileOptions { ... }` block, enable desugaring:

```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}
```

3. At the bottom of the file (outside the `android { }` block), add:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Then build and run:

```bash
flutter run
```

## Backend URL

Set your backend URL in the app's Settings screen (gear icon).

- Android emulator: `http://10.0.2.2:3000` (default)
- Physical device: `http://<your-computer-LAN-IP>:3000` (same Wi-Fi network)

## Notes

For scheduled contest reminders on Android 12+, you may also want to add
`SCHEDULE_EXACT_ALARM` / use exact scheduling later; the MVP uses inexact
scheduling which requires no extra permissions.
