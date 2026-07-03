# CodeTrack — Flutter app

This folder contains the Dart source only. Generate platform folders once:

```bash
flutter create . --project-name codetrack
flutter pub get
flutter run
```

Then set your backend URL in the app's Settings screen (gear icon).

- Android emulator: `http://10.0.2.2:3000` (default)
- Physical device: `http://<your-computer-LAN-IP>:3000` (same Wi-Fi network)

For scheduled contest reminders on Android 12+, you may also want to add
`SCHEDULE_EXACT_ALARM` / use exact scheduling later; the MVP uses inexact
scheduling which requires no extra permissions.
