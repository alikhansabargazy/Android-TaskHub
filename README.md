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

## Web version

Build the browser app and serve it together with the API from the repository root:

```bash
flutter pub get
flutter build web --release
TASKHUB_DB=./data/taskhub.sqlite3 TASKHUB_WEB_DIR=./build/web python3 -m backend.app
```

Open `http://127.0.0.1:8000`. The web app uses the same origin for API calls,
so no separate CORS configuration is needed. On a wide screen it displays a
side navigation rail; on a narrow screen it uses bottom navigation. The map
opens in a new browser tab. On the web, local deadline notifications are not
available. Personal schedule and deadlines are kept in this browser's local
storage; the Groups tab uses the server.

For a public deployment, place the server behind an HTTPS reverse proxy and
set `TASKHUB_HOST=127.0.0.1`. Browser secure token storage and account login
require a secure context (HTTPS, or localhost for development). Keep the SQLite
database outside the public `build/web` directory. A ready-to-upload web build
is also attached to successful GitHub Actions runs as `taskhub-web`.

### Deploy from macOS

Point a domain's A record to `51.77.53.215`, then on a Mac with Flutter installed,
from the repository root run:

```bash
./scripts/deploy-macos.sh app.example.com
```

The script checks Flutter and backend tests, builds the web app, uploads it over
SSH port 2977, installs the Python API as a systemd service and configures Caddy
to serve the site over HTTPS. SSH asks for the server password interactively;
the password is not stored in the script. The SQLite database remains under
`/var/lib/taskhub/` on repeat deployments. The server must run Debian/Ubuntu
with systemd and allow inbound ports 80 and 443.

Release builds need your own application ID and signing configuration:
`android/app/build.gradle.kts` still uses `com.example.taskhub` and debug
signing for release. Configure these before distributing the APK.
