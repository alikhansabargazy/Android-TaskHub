# TaskHub

TaskHub is a Flutter student planner with a weekly class schedule, deadlines,
custom subject colors and icons, and the AITU campus map.

Schedule and deadlines are stored **on this device** using SharedPreferences.
The personal Schedule and Deadlines tabs use local SharedPreferences. The Groups
tab connects to the account and group API described in
[`backend/README.md`](backend/README.md). There is no Firebase configuration.

## Requirements

- Flutter SDK with Dart 3.13.4 or newer (`flutter --version`)
- Platform toolchain and a connected device or simulator (`flutter doctor -v`,
  `flutter devices`). Android needs its SDK; iOS and macOS require Xcode;
  Windows requires Visual Studio C++ desktop tools; Linux requires the Flutter
  Linux desktop dependencies.
- Internet access for package downloads and the AITU map.
- To use Groups, start the backend and set its URL with
  `--dart-define=TASKHUB_API_URL=http://10.0.2.2:8000` for an Android emulator.
  For Windows/Linux/macOS desktop on the same machine use
  `http://127.0.0.1:8000`. A physical phone needs your computer's LAN address
  and `TASKHUB_HOST=0.0.0.0`. iOS and production builds should use an HTTPS URL;
  the Android debug build alone allows cleartext HTTP for local development.

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
- Group owners add classes and deadlines in the Groups tab; other members join
  by invite code and can mark a shared deadline complete for themselves.
  Group data comes from the backend. The personal Schedule/Deadlines tabs are
  still local to this device.
- Data lives only in this app's local storage; uninstalling the app can remove
  it. The schedule's “Import / create” button opens the manual class editor;
  importing a file is not implemented.

Release builds need your own application ID and signing configuration:
`android/app/build.gradle.kts` still uses `com.example.taskhub` and debug
signing for release. Configure these before distributing the APK.
