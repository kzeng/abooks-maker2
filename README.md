# Abooks Maker

Cross-platform ebook-to-audiobook application for Ubuntu 22.04 and Android.

The first release targets EPUB, TXT, and text-based PDF files. It uses Edge TTS voices and produces chapter MP3 files. The current Flutter UI is the Material 3 workspace foundation; file parsing, TTS, audio encoding, and Android background conversion are being added incrementally.

## Development

```bash
source scripts/dev-env.sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

See [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) for Ubuntu packages, Android SDK setup, proxy handling, and wireless debugging. Product scope and trade-offs are recorded in [docs/PRODUCT_DECISIONS.md](docs/PRODUCT_DECISIONS.md).

## CI

GitHub Actions runs formatting, analysis, tests, Android AAB builds, and Linux release builds. Android signing and Play Console credentials must be provided through repository secrets when release publishing is enabled.
