# Bakedown — Ubuntu Desktop (Web) Guide

Flutter already installed. This is the **web** target — runs in Chrome/Chromium on your Ubuntu desktop, with real folder access via Chrome's File System Access API (no SMB plugin needed).

---

### 1. Get the code

```bash
git clone <your-repo-url> recipe-app
cd recipe-app
flutter pub get
```

> Requires Flutter ≥3.44 (Dart ≥3.12). Check: `flutter --version`

### 2. Run in Chrome (developer)

```bash
flutter run -d chrome --no-wasm-dry-run
# or pick a port:
flutter run -d chrome --web-port 54545 --no-wasm-dry-run
```

* Must be **Chrome or Edge** (Firefox/Safari don't support `showDirectoryPicker`).
* Must be `http://localhost:*` (secure context). `flutter run -d chrome` already is.
* First screen → **Pick Folder on Disk** → select `~/Recipes` or `//server/share` (see §4 for NAS). Grant **Read & Write**.
* Files are real `.md` on disk at the folder you picked. `http://localhost:<port>` shows `rootName` (e.g. `Recipes`).

**Where is "root"?**

| Mode | `RecipeRepository` | `rootPath` | Actual storage |
|---|---|---|---|
| Web + picked folder | `WebFsRecipeRepository` (`lib/features/recipes/data/repositories/web_fs_recipe_repository.dart:5`) | `WebFsHelper.rootName` | Real OS folder you picked (`~/Recipes`, `/mnt/nas/recipes`, `//nas/share`) |
| Web fallback (no FS API) | `WebRecipeRepository` (`lib/features/recipes/data/repositories/web_recipe_repository.dart:7`) | `web` | Browser `localStorage` (`DevTools > Application > Local Storage > http://localhost:XXXX` keys `web_recipe_*`) |
| HTTP Bridge | `HttpRecipeRepository` | `http://host:8787` | Disk on bridge machine |

Web handle is in-memory — reload → re-pick. (Persist to IndexedDB via handle storage is next step.)

### 3. Build for production (optimized)

```bash
# Release build (tree-shaken icons, canvaskit cached, PWA manifest)
flutter build web --release --no-wasm-dry-run

# Subpath deploy e.g. https://user.github.io/recipe-app/
flutter build web --release --base-href /recipe-app/ --no-wasm-dry-run
```

Output: `build/web/` (55 MB total, 26 MB canvaskit, 12 MB assets — cached `31536000s` via `web/_headers:1`).

* SPA fallback already: `web/_redirects:1` (`/* /index.html 200`), `firebase.json:5` rewrites, `vercel.json:4`.
* `web/index.html:1` has SEO, splash (`#splash`), `flutter-first-frame` hide, theme `#E85D04`.
* `web/manifest.json:1` PWA `standalone`, `background_color #FFF8F0`.

Disable the `wasm` dry-run warnings for now — `sherpa_onnx:1.13.3` pulls `dart:ffi` (voice is stubbed on web via `lib/features/voice/sherpa_engine.dart:1` `if (dart.library.html)`). JS build is tree-shaken; wasm would need `--enable-experimental-ffi` and full stub.

### 4. Network share (Samba) on web — no plugin

**Just pick it:**

1. Mount or ensure share visible in Nautilus: `Files > Other Locations > smb://nas.local/share` → Enter creds → **Remember forever**. Or `gio mount smb://nas.local/share` or `sudo mount -t cifs //nas/share /mnt/nas -o credentials=...`
2. In Bakedown web: **Pick Folder on Disk** → file dialog → left sidebar **Network** or navigate to `/run/user/1000/gvfs/smb-share:server=nas.local,share=share` or `/mnt/nas`.
3. That's it — `FileSystemDirectoryHandle.getDirectoryHandle` is OS SMB, not `smb_connect`.

> No `Host/Share/User/Pass` fields anymore (removed `lib/features/settings/presentation/screens/settings_screen.dart:426`). Old prefs with `smb_enabled` are ignored; `recipe_providers.dart:19` now just uses `LocalRecipeRepository(dir)` for any `dir` (including `//server/share` or `/mnt/nas`).

**If picker says “No bridge / denied”:**
* Use Chrome/Edge, not Firefox.
* Must be `localhost` or `https://` (not `http://192.168.x.x` without HTTPS) for `showDirectoryPicker`.
* Ensure share is mounted/authenticated in OS first.

### 5. HTTP Bridge (optional — headless/NAS)

For a Pi/NAS that serves recipes over HTTP to all devices:

```bash
python3 bridge/server.py --dir ~/Recipes --port 8787 --allow-cors
# or: dart run bridge/server.dart
```

Then in Bakedown **Settings > HTTP Bridge** → `http://<bridge-host>:8787` → **Test Bridge**. `HttpRecipeRepository` takes priority over FS picker.

Discovery (`lib/features/settings/presentation/providers/settings_providers.dart:180`) now only scans HTTP bridges.

### 6. Deploy the `build/web` folder

* **Netlify/Cloudflare Pages:** Drag `build/web` — `_headers`/`_redirects` auto-applied. Or `netlify deploy --prod --dir=build/web`.
* **Vercel:** `vercel --prod` (reads `vercel.json` rewrites). Set Output `build/web`.
* **Firebase:** `firebase deploy --only hosting` (uses `firebase.json` rewrites/headers).
* **GitHub Pages:** `flutter build web --base-href /recipe-app/` → push `build/web` to `gh-pages`.
* **Self-host Nginx:**
  ```nginx
  server { root /var/www/bakedown; try_files $uri $uri/ /index.html; }
  ```

### 7. Troubleshooting

* `SyntaxError: Identifier 'PromiseCompleter' has already been declared` → fixed via `wakelock_plus-1.5.2/lib/assets/no_sleep.js:3` guard + `settings_providers.dart:24` `if(kIsWeb) return` . If old service worker cached, **Ctrl+Shift+R** or `DevTools > Application > Clear storage`.
* `FileSystemAccess not supported` → use Chrome ≥86 on `localhost` or deploy to `https://`.
* Empty after reload on web → handle not persisted yet — re-pick folder.

### 8. Next steps

* `flutter analyze` → 0 errors, `flutter test` → 20/20.
* To make FS handle persist across reloads, store handle in IndexedDB (structured clone) — ask to enable.

