# AGENTS.md — Recipe App

## Project
Cross-platform Flutter recipe database/reader with AI transcoding.
Recipes = `.md` files with YAML frontmatter. State = Riverpod. UI = M3.

## Architecture
- Feature-first layout (`lib/features/<feature>/`)
- Data layer: models + repositories (file I/O + REST)
- Presentation: providers + screens + widgets
- No domain layer abstraction (keep simple — models are the domain)
- See `architecture.md` for full detail

## Conventions

### File naming
- `snake_case.dart` for all files
- Screens suffixed `_screen`, widgets suffixed with role, providers suffixed `_providers`
- Model classes in `data/models/` or `domain/models/`

### Code style
- NO comments in production code unless explaining a non-obvious workaround
- Use Material 3 widgets (`Card`, `ListTile`, `NavigationBar`)
- Prefer `ConsumerWidget` / `ConsumerStatefulWidget` over `StatelessWidget` when reading providers
- Riverpod without code-gen: use `Provider`, `StateProvider`, `StateNotifierProvider` directly

### Riverpod patterns
```dart
final myProvider = Provider<Type>((ref) => ...);
final myState = StateProvider<Type>((ref) => initialValue);
final myNotifier = StateNotifierProvider<MyNotifier, State>((ref) => MyNotifier());
```

### Imports
- Relative imports within the same feature
- Package imports (`package:recipe_app/...`) for cross-feature references
- Keep import sections: Flutter SDK → packages → project

### Error handling
- File read failures → return null / empty list (silent fail for browsing)
- LM Studio network errors → show snackbar with message
- No try-catch on file writes (let crash during dev, catch only in release)

## Testing
- Unit tests for `RecipeModel.fromMarkdown()` / `toMarkdown()` roundtrip
- Unit tests for `LmStudioRepository.parseResponse()`
- Widget tests for critical screens (RecipeScreen, FolderBrowserScreen)
- No golden-file tests (not worth maintenance)

Test files go in `test/features/<feature>/`.

## Adding a new feature
1. Create `lib/features/<name>/` with `data/`, `presentation/`, `domain/` subdirs
2. Model → Repository → Providers → Screens → Widgets
3. Register any new providers in `app.dart` if needed (most are self-registering)
4. Add GoRouter route in `app.dart`

## Key packages (versions in pubspec.yaml)
- flutter_riverpod: state
- go_router: routing
- flutter_smooth_markdown: render .md with checkboxes, tables, mermaid
- image_picker: camera/gallery
- http: LM Studio REST
- wakelock_plus: keep screen on
- file_picker: choose recipe directory
- shared_preferences: settings
- yaml: parse frontmatter
- path_provider: OS paths
- path: path manipulation

## LM Studio API
- Base URL: stored in SharedPreferences (default `http://localhost:1234`)
- Endpoints: `GET /v1/models`, `POST /v1/chat/completions`
- Auth: none (local server)
- Vision: send image as base64 data URL in messages content
- See `assets/prompts/recipe-system-prompt.md` for the system prompt
