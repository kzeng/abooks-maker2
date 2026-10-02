# Initial Architecture

## Layers

```text
Flutter Material 3 UI
        |
Conversion application service
        |
Parser -> text normalizer -> TtsProvider -> audio encoder
        |
Platform adapters: Android / Linux
```

## Planned project layout

```text
lib/
  app/                 # routing, theme, localization
  features/library/    # book and chapter metadata
  features/import/     # file selection and format detection
  features/conversion/ # jobs, progress, retry, resume
  features/player/     # local audio playback
  features/settings/   # voice and output preferences
  core/                # models, storage, logging, platform channels
android/               # foreground service and Android TTS/audio integration
linux/                 # Linux process and packaging integration
test/                  # unit and widget tests
docs/                  # decisions and implementation notes
```

## Reference implementation mapping

The existing `/home/zengkai/Codes/abooks-maker` uses `ebooklib`, BeautifulSoup, `pypdf`, `edge-tts`, and FFmpeg. The Flutter version should preserve the user-facing behavior while isolating these responsibilities behind platform-neutral interfaces. EPUB/TXT/PDF parsing and Edge TTS behavior should be ported incrementally and covered with fixture-based tests.
