# Recipe App — Architecture

## Overview
Cross-platform (Windows, Web, Android) Flutter recipe database/reader.
Recipes stored as local `.md` files with YAML frontmatter. AI transcoding
via LM Studio REST API (vision model). User-chosen root directory.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | Flutter 3.41 / Dart 3.11 |
| State | Riverpod (flutter_riverpod) |
| UI | Material Design 3 |
| Routing | GoRouter |
| Markdown | flutter_smooth_markdown |
| AI | LM Studio REST API (http) |
| Screen-on | wakelock_plus |
| Persistence | SharedPreferences (settings) + file system (recipes) |

---

## Project Structure (feature-first)

```
lib/
├── main.dart                    # Entry point, ProviderScope
├── app.dart                     # MaterialApp.router, GoRouter config
├── core/
│   ├── theme/app_theme.dart     # Light/dark M3 theme
│   ├── constants/app_constants.dart
│   └── utils/yaml_parser.dart   # YAML frontmatter helpers
├── features/
│   ├── recipes/
│   │   ├── data/
│   │   │   ├── models/recipe_model.dart       # Recipe data class + markdown parse/serialize
│   │   │   └── repositories/recipe_repository.dart  # CRUD on .md files
│   │   └── presentation/
│   │       ├── providers/recipe_providers.dart      # Riverpod providers
│   │       ├── screens/
│   │       │   ├── folder_browser_screen.dart       # Folder tree
│   │       │   ├── recipe_list_screen.dart          # Recipes in folder
│   │       │   └── recipe_screen.dart               # Split view (reader + editor)
│   │       └── widgets/
│   │           ├── recipe_card.dart
│   │           ├── folder_tree.dart
│   │           ├── markdown_reader.dart
│   │           └── markdown_editor.dart
│   ├── ai_transcoder/
│   │   ├── data/repositories/lm_studio_repository.dart  # LM Studio REST client
│   │   ├── domain/models/lm_studio_model.dart
│   │   └── presentation/
│   │       ├── providers/ai_providers.dart
│   │       ├── screens/ai_transcode_screen.dart         # Camera/gallery -> AI -> save
│   │       └── widgets/model_dropdown.dart
│   └── settings/
│       ├── data/repositories/settings_repository.dart
│       ├── domain/models/app_settings.dart
│       └── presentation/
│           ├── providers/settings_providers.dart
│           └── screens/settings_screen.dart
├── shared/
│   └── widgets/confirmation_dialog.dart
assets/
└── prompts/
    └── recipe-system-prompt.md   # LLM system prompt
```

---

## Data Flow

1. **First launch**: User picks recipe directory via file_picker → stored in SharedPreferences
2. **Browse**: File system scan of chosen dir → folders shown → tap folder → .md files listed → tap file → parsed + displayed
3. **Edit**: Markdown editor (plain text) → save → writes .md file → repo rebuilds
4. **AI Transcode**: Camera/gallery → base64 image → POST /v1/chat/completions (system prompt + image) → returned markdown → user reviews → save as new .md
5. **Settings**: SharedPreferences-backed, exposed via Riverpod

---

## Recipe Markdown Format

```markdown
---
title: "Recipe Name"
prep_time: "15 min"
cook_time: "30 min"
total_time: "45 min"
servings: 4
difficulty: "easy"
tags: [italian, pasta]
source: "https://example.com"
created: "2026-06-22"
---

## Ingredients
- [ ] 2 cups flour
- [ ] 1 cup water

## Instructions
1. Mix dry ingredients
2. Combine wet & dry

## Notes
Optional section.
```

---

## LM Studio Integration

- Base URL: configurable (default `http://localhost:1234`)
- Model: selectable from `GET /v1/models` response
- Chat: `POST /v1/chat/completions` with vision model
  - System prompt → defines recipe markdown format
  - Image → base64 data URL in user message
  - Response → markdown recipe shown to user
- Full REST API docs: https://lmstudio.ai/docs/developer/rest

---

## State Management

- `StateProvider` for simple strings (directory, current folder)
- `Provider` for derived state (folder list, recipe list)
- `StateNotifierProvider` for mutable settings
- No code-gen (pure Riverpod, no riverpod_generator)

---

## Platforms

- **Windows**: Full support via Visual Studio build tools
- **Web**: Edge browser via `flutter run -d edge`
- **Android**: SDK 36, need `flutter doctor --android-licenses` first run

Keep-screen-on: `wakelock_plus` — works on all 3 platforms.
