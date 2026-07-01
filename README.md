# Bakedown

Offline-first recipe database and reader with voice control. Recipes stored as Markdown files with YAML frontmatter. Built with Flutter.

## Features

- **Voice control** — on-device wake word (sherpa-onnx KWS) + Android STT. Hands-free navigation: "hey recipe, go home", "set a timer for 5 minutes", "scroll down", "read ingredients".
- **Recipe browser** — browse folders, search, import from clipboard/URL.
- **AI transcoding** — paste any recipe URL, extract structured recipe via local LM Studio.
- **Timers** — multiple concurrent timers with custom alarm sounds.
- **TTS read-aloud** — read ingredients, instructions, or individual steps.
- **Material 3** — light/dark theme following system.

## Stack

- Flutter + Dart 3
- Riverpod (state)
- GoRouter (routing)
- sherpa-onnx (wake word detection)
- speech_to_text (Android on-device STT)
- flutter_smooth_markdown (recipe rendering)
- LM Studio API (recipe extraction, local)

## Requirements

- Android 8+ (API 26+)
- Offline English speech recognition pack must be installed in system settings
- LM Studio running on `http://localhost:1234` for AI transcoding (optional — manual recipe entry works without it)

## Quick Start

```bash
flutter pub get
flutter run
```

Set your recipe directory: **Settings → Recipe directory** (use File Picker to choose a folder of `.md` recipe files).

## Project Layout

```
lib/
  features/
    voice/        — wake-word engine, STT, command dispatch
    timer/        — multi-timer with alarm sounds
    settings/     — directory picker, voice toggle, theme
    recipe/       — browse, search, read recipes
    transcoding/  — LM Studio recipe extraction
    tts/          — text-to-speech read-aloud
  theme/          — Material 3 tokens, component themes
  core/           — shared utilities, routing
  app.dart        — app entry + router
```

## License

MIT
