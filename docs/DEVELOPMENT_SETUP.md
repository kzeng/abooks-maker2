# Development Setup

## Installed user-space tools

- Flutter 3.47.5 / Dart 3.13.4: `$HOME/.local/flutter`
- Android SDK: `$HOME/Android/Sdk`
- Android platform 36, Build Tools 36.0.0, platform-tools
- Java 17: `$HOME/.local/java/jdk-17.0.19+10`

Load the project environment with:

```bash
source scripts/dev-env.sh
flutter doctor -v
```

## Required Ubuntu packages

Linux desktop builds additionally require administrator-installed packages:

```bash
./scripts/install-linux-deps.sh
```

The script runs the equivalent `sudo apt-get` installation for `clang`, `cmake`, `ninja-build`, `pkg-config`, GTK/LZMA development libraries, FFmpeg, and Android USB rules.

The current agent environment cannot enter the sudo password. Run the command manually if Linux release builds are needed locally; GitHub Actions installs the same dependencies in CI.

## Validation commands

```bash
source scripts/dev-env.sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build appbundle --release
flutter build linux --release
```

If the shell has an HTTP proxy, keep `127.0.0.1`, `localhost`, and `::1` in `NO_PROXY`; Flutter tests use a local VM service.

## Wireless Android debugging

```bash
source scripts/dev-env.sh
adb pair <pairing-address>
adb connect 192.168.0.102:39131
adb devices -l
flutter devices
```

The phone and computer must be on the same network, and the port can change when wireless debugging is restarted.
