# Bakedown — Ubuntu Web (Shared Host) Guide

**Web = shared host folder. Native apps unchanged.**

- **Web** (`flutter build web` → `node server/index.js`): every browser/device on `http://192.168.0.218:2211` reads/writes the **same** folder on this Ubuntu host (default `~/Recipes`, auto-created if missing). No per-browser `localStorage`, no `showDirectoryPicker`, works on plain `http` LAN.
- **Native** (Android/iOS/Desktop `flutter run`): still uses `LocalRecipeRepository` / SAF `content://` as before (`Settings > Recipe Directory` picker).

---

### 1. Get the code

```bash
git clone <your-repo-url> recipe-app
cd recipe-app
flutter pub get
```

Requires Flutter ≥3.44.

### 2. Run web — shared host (recommended)

```bash
# Build once
flutter build web --release --no-wasm-dry-run

# Install server deps once
npm --prefix server install

# Serve: app + recipes API on one port, plain http, CORS enabled
node server/index.js --port 2211
# → Recipes root: ~/Recipes (auto-created)
# → http://localhost:2211      (on this PC)
# → http://192.168.0.218:2211   (all phones/PCs on LAN — same recipes)

# Custom dir / port:
RECIPES_DIR=~/Desktop/bakedown-recipes node server/index.js --port 2211
node server/index.js --dir /mnt/nas/recipes --port 2211 --host 0.0.0.0
```

**Test:** open `http://192.168.0.218:2211` on phone + PC → create folder `Desserts` on one → appears on the other instantly. `curl http://192.168.0.218:2211/api/folders` → `["Desserts"]`.

Dev mode (hot reload, still shared):
```bash
flutter run -d chrome --web-port 2211 --no-wasm-dry-run
# + in another terminal:
node server/index.js --port 2211
# App at http://localhost:2211 uses http://localhost:2211/api/* (same origin)
```

### 3. Where is the source of truth?

| Target | `RecipeRepository` | `rootPath` | Storage |
|---|---|---|---|
| **Web** (this guide) | `HttpRecipeRepository(Uri.base.origin)` (`lib/features/recipes/presentation/providers/recipe_providers.dart:18`) | `http://192.168.0.218:2211` | Host disk `~/Recipes` via `server/index.js` (`GET /api/folders`, `PUT /api/file/:folder/:file`, etc.) |
| **Native** | `LocalRecipeRepository(dir)` / `AndroidSafRecipeRepository` | Settings `recipeDirectory` | Device disk / SAF |

Web no longer uses `WebRecipeRepository` (`localStorage`) or `WebFsRecipeRepository` (`showDirectoryPicker`) — those remain in code but are gated off for `kIsWeb`. No `Secure context required`, no `mkcert`, no `Import .md Files` needed.

### 4. Network share (NAS) as host folder

Point the server at the mount, not the browser picker:

```bash
gio mount smb://nas.local/share   # or: sudo mount -t cifs //nas/share /mnt/nas -o credentials=...
node server/index.js --dir /mnt/nas/recipes --port 2211
# or: --dir /run/user/1000/gvfs/smb-share:server=nas.local,share=share
```

All web clients then share the NAS via the host.

### 5. Production build

```bash
flutter build web --release --no-wasm-dry-run  # → build/web (PWA, _headers/_redirects already set)
node server/index.js --port 2211               # single process serves build/web + /api
```

For static hosting without shared semantics (Netlify/Vercel/Firebase) you lose shared host — use `node server/index.js` on a VM/VPS if you need LAN-share.

### 6. Troubleshooting

- `build/web not found — API only` → run `flutter build web` first; `server/index.js` falls back to API-only if build missing.
- `EACCES` / `EADDRINUSE` on `:2211` → `sudo lsof -i :2211` / pick another port: `node server/index.js --port 3000` → `http://192.168.0.218:3000`.
- Native app still asks for folder → expected, native is unchanged; pick folder in `Settings > Recipe Directory`.
- Want per-browser isolation on web again → change `recipe_providers.dart:18` back to `WebRecipeRepository` gating, but you lose cross-device sync.

### 7. Verify

```bash
flutter analyze  # 0 errors
flutter test     # 20/20
flutter build web
curl http://localhost:2211/api/health  # {"ok":true,"root":".../Recipes"}
```
