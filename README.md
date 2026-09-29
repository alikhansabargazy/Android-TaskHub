# TaskHub

TaskHub is a Flutter student planner with a weekly class schedule, deadlines,
custom subject colors and icons, and the AITU campus map.

Schedule and deadlines are stored **on this device** using SharedPreferences.
The Flutter client currently has no account sign-in or cloud sync. A separate
account and planner API is available in [`backend/README.md`](backend/README.md);
the client is not yet connected to it. There is no Firebase configuration.

## Requirements

- Flutter SDK with Dart 3.13.4 or newer (`flutter --version`)
- Platform toolchain and a connected device or simulator (`flutter doctor -v`,
  `flutter devices`). Android needs its SDK; iOS and macOS require Xcode;
  Windows requires Visual Studio C++ desktop tools; Linux requires the Flutter
  Linux desktop dependencies.
- Internet access for package downloads and the AITU map.

## Run

From the repository root:

```bash
git clone https://github.com/alikhansabargazy/Android-TaskHub.git
cd Android-TaskHub
flutter pub get
flutter devices
flutter run -d <device-id>
```

Choose an actual ID printed by `flutter devices`. For example, use
`flutter run -d windows` on a configured Windows machine. Run `flutter test`
and `flutter analyze` to check changes. For an Android APK use
`flutter build apk`; the result is in `build/app/outputs/flutter-apk/`.
Run Flutter commands in the repository root, where `pubspec.yaml` is located;
Gradle commands from an unrelated Android project do not build this app.

## Platform behavior

- Android, iOS and macOS display the AITU map inside the app. Windows, Linux
  and web open it in the default browser; the map itself is hosted at
  `https://yuujiso.github.io/aitumap` and needs a connection.
- Android, iOS and macOS schedule a device notification at each future,
  incomplete deadline's due time. Grant notification permission when prompted.
  Notifications are local reminders, not server-sent push messages. Completing
  or deleting a deadline updates the schedule. Exact delivery can vary with
  system power settings. Windows, Linux and web currently do not schedule
  deadline notifications.
- Data lives only in this app's local storage; uninstalling the app can remove
  it. The schedule's “Import / create” button opens the manual class editor;
  importing a file is not implemented.

Release builds need your own application ID and signing configuration:
`android/app/build.gradle.kts` still uses `com.example.taskhub` and debug
signing for release. Configure these before distributing the APK.
