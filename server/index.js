import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function parseArgs() {
  const args = process.argv.slice(2);
  let dir = process.env.RECIPES_DIR || '';
  let host = process.env.HOST || '0.0.0.0';
  let port = Number(process.env.PORT || 2211);
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if ((a === '--dir' || a === '--recipes') && args[i + 1]) {
      dir = args[++i];
    } else if (a.startsWith('--dir=')) {
      dir = a.slice('--dir='.length);
    } else if (a.startsWith('--recipes=')) {
      dir = a.slice('--recipes='.length);
    } else if ((a === '--host') && args[i + 1]) {
      host = args[++i];
    } else if (a.startsWith('--host=')) {
      host = a.slice('--host='.length);
    } else if ((a === '--port' || a === '-p') && args[i + 1]) {
      port = Number(args[++i]);
    } else if (a.startsWith('--port=')) {
      port = Number(a.slice('--port='.length));
    } else if (!isNaN(Number(a)) && String(Number(a)) === a) {
      port = Number(a);
    }
  }
  if (!dir) dir = path.join(os.homedir(), 'Recipes');
  return { dir: path.resolve(dir.replace(/^~/, os.homedir())), host, port };
}

const { dir: recipesDirRaw, host, port } = parseArgs();
const recipesRoot = path.resolve(recipesDirRaw);
if (!fs.existsSync(recipesRoot)) {
  console.log(`Creating recipes dir ${recipesRoot}`);
  fs.mkdirSync(recipesRoot, { recursive: true });
}
console.log(`Recipes root: ${recipesRoot}`);

const webBuildDir = path.resolve(__dirname, '../build/web');

const app = express();
app.use(cors({ origin: '*', methods: ['GET','POST','PUT','DELETE','OPTIONS'], allowedHeaders: ['Content-Type','Authorization'] }));

// Body parsers: JSON for /api/file wrapper, text for markdown PUT
app.use('/api/file', express.text({ type: ['text/*', 'text/markdown'], limit: '20mb' }));
app.use(express.json({ limit: '20mb' }));
app.use(express.urlencoded({ extended: true }));

function safePath(folder, filename) {
  try {
    const f = folder ? decodeURIComponent(folder) : '';
    const fn = filename ? decodeURIComponent(filename) : null;
    if (f.includes('..') || (fn && fn.includes('..'))) return null;
    if (f.startsWith('/') || f.startsWith('\\')) return null;
    if (fn !== null && (fn.includes('/') || fn.includes('\\'))) return null;
    const base = recipesRoot;
    const joined = fn === null ? path.join(base, f) : path.join(base, f, fn);
    const resolved = path.resolve(joined);
    const rel = path.relative(base, resolved);
    if (rel.startsWith('..') || path.isAbsolute(rel) && !resolved.startsWith(base)) {
      // also check that resolved is inside base
      if (resolved !== base && !resolved.startsWith(base + path.sep)) return null;
    }
    // Ensure inside base
    if (resolved !== base && !resolved.startsWith(base + path.sep)) return null;
    return resolved;
  } catch {
    return null;
  }
}

function sendJson(res, obj, code = 200) {
  res.status(code).json(obj);
}
function sendText(res, text, code = 200, ctype = 'text/markdown; charset=utf-8') {
  res.status(code).type(ctype).send(text);
}

// --- API ---

app.get('/api/health', (req, res) => sendJson(res, { ok: true, root: recipesRoot }));
app.get('/api', (req, res) => sendJson(res, { service: 'bakedown-server', root: recipesRoot, endpoints: ['/api/folders','/api/folders/<folder>','/api/file/<folder>/<file>','/files/<folder>/<file>'] }));
app.get('/api/', (req, res) => sendJson(res, { service: 'bakedown-server', root: recipesRoot }));

app.get('/api/folders', (req, res) => {
  try {
    const entries = fs.readdirSync(recipesRoot, { withFileTypes: true });
    const folders = entries.filter(e => e.isDirectory()).map(e => e.name).sort();
    sendJson(res, folders);
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.get('/api/discover', (req, res) => {
  sendJson(res, [{ name: `Bakedown @ ${os.hostname()}`, host: `http://${req.headers.host}`, port }]);
});

// subfolders vs files: /api/folders/:folder  and /api/folders/:folder/subfolders
app.get('/api/folders/:folder/subfolders', (req, res) => {
  const p = safePath(req.params.folder);
  if (!p || !fs.existsSync(p) || !fs.statSync(p).isDirectory()) return sendJson(res, { error: 'folder not found' }, 404);
  try {
    const entries = fs.readdirSync(p, { withFileTypes: true });
    const folders = entries.filter(e => e.isDirectory()).map(e => e.name).sort();
    sendJson(res, folders);
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.get('/api/folders/:folder', (req, res) => {
  const p = safePath(req.params.folder);
  if (!p || !fs.existsSync(p) || !fs.statSync(p).isDirectory()) return sendJson(res, { error: 'folder not found' }, 404);
  try {
    const entries = fs.readdirSync(p, { withFileTypes: true });
    const folders = entries.filter(e => e.isDirectory()).map(e => e.name).sort();
    const files = entries.filter(e => e.isFile()).map(e => e.name).sort();
    sendJson(res, { folders, files });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.get('/api/file/:folder/:filename', (req, res) => {
  const p = safePath(req.params.folder, req.params.filename);
  if (!p || !fs.existsSync(p) || !fs.statSync(p).isFile()) return sendJson(res, { error: 'file not found' }, 404);
  try {
    const text = fs.readFileSync(p, 'utf-8');
    sendText(res, text);
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

// raw files (images, md as raw)
app.get('/files/:folder/:filename', (req, res) => {
  const p = safePath(req.params.folder, req.params.filename);
  if (!p || !fs.existsSync(p) || !fs.statSync(p).isFile()) return sendJson(res, { error: 'file not found' }, 404);
  const ext = path.extname(p).toLowerCase();
  let mime = 'application/octet-stream';
  if (ext === '.jpg' || ext === '.jpeg') mime = 'image/jpeg';
  else if (ext === '.png') mime = 'image/png';
  else if (ext === '.webp') mime = 'image/webp';
  else if (ext === '.gif') mime = 'image/gif';
  else if (ext === '.bmp') mime = 'image/bmp';
  else if (ext === '.heic' || ext === '.heif') mime = 'image/heic';
  else if (ext === '.avif') mime = 'image/avif';
  else if (ext === '.svg') mime = 'image/svg+xml';
  else if (ext === '.md') mime = 'text/markdown; charset=utf-8';
  res.type(mime);
  res.sendFile(p);
});

app.put('/api/file/:folder/:filename', (req, res) => {
  const p = safePath(req.params.folder, req.params.filename);
  if (!p) return sendJson(res, { error: 'invalid path' }, 400);
  const body = typeof req.body === 'string' ? req.body : (req.body ? String(req.body) : '');
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, body, 'utf-8');
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

// Binary image upload — web HttpRepo writeBytes hits this (raw bytes, e.g. image/jpeg)
app.put('/files/:folder/:filename', express.raw({ type: '*/*', limit: '20mb' }), (req, res) => {
  const p = safePath(req.params.folder, req.params.filename);
  if (!p) return sendJson(res, { error: 'invalid path' }, 400);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    const data = req.body;
    if (Buffer.isBuffer(data)) {
      fs.writeFileSync(p, data);
    } else if (typeof data === 'string') {
      // fallback: base64 or plain text sent via this route
      try {
        const buf = Buffer.from(data, 'base64');
        // heuristic: if base64 round-trip length matches, treat as base64
        if (buf.toString('base64') === data.replace(/\s/g, '')) {
          fs.writeFileSync(p, buf);
        } else {
          fs.writeFileSync(p, data, 'utf-8');
        }
      } catch {
        fs.writeFileSync(p, String(data), 'utf-8');
      }
    } else if (data) {
      fs.writeFileSync(p, Buffer.from(data));
    } else {
      fs.writeFileSync(p, Buffer.alloc(0));
    }
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.post('/api/file', (req, res) => {
  const { folder = '', filename = '', content = '' } = req.body || {};
  const p = safePath(String(folder), String(filename));
  if (!p) return sendJson(res, { error: 'invalid path' }, 400);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, String(content), 'utf-8');
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.post('/api/folder/:name', (req, res) => {
  const p = safePath(req.params.name);
  if (!p) return sendJson(res, { error: 'invalid path' }, 400);
  try {
    fs.mkdirSync(p, { recursive: true });
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});
app.post('/api/folders', (req, res) => {
  const name = req.body?.name || '';
  if (!name) return sendJson(res, { error: 'name required' }, 400);
  const p = safePath(String(name));
  if (!p) return sendJson(res, { error: 'invalid path' }, 400);
  try {
    fs.mkdirSync(p, { recursive: true });
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

app.delete('/api/file/:folder/:filename', (req, res) => {
  const p = safePath(req.params.folder, req.params.filename);
  if (!p || !fs.existsSync(p)) return sendJson(res, { error: 'not found' }, 404);
  try {
    fs.unlinkSync(p);
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});
app.delete('/api/folder/:name', (req, res) => {
  const p = safePath(req.params.name);
  if (!p || !fs.existsSync(p)) return sendJson(res, { error: 'not found' }, 404);
  try {
    fs.rmSync(p, { recursive: true, force: true });
    sendJson(res, { ok: true });
  } catch (e) {
    sendJson(res, { error: String(e) }, 500);
  }
});

// Serve Flutter web static if exists
if (fs.existsSync(webBuildDir)) {
  app.use(express.static(webBuildDir, { fallthrough: true }));
  // SPA fallback for non-API routes
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api/') || req.path.startsWith('/files/')) return next();
    const index = path.join(webBuildDir, 'index.html');
    if (fs.existsSync(index)) return res.sendFile(index);
    return next();
  });
  console.log(`Serving Flutter web from ${webBuildDir}`);
} else {
  console.log(`No build/web found at ${webBuildDir} — API only. Run: flutter build web`);
  app.get('/', (req, res) => sendJson(res, { service: 'bakedown-server', root: recipesRoot, note: 'build/web not found — run flutter build web', webBuildDir }));
}

app.use((req, res) => sendJson(res, { error: 'not found' }, 404));

app.listen(port, host, () => {
  const displayHost = host === '0.0.0.0' ? '0.0.0.0 (all interfaces)' : host;
  console.log(`Bakedown server serving ${recipesRoot} at http://${displayHost}:${port}`);
  console.log(`  LAN: http://<this-host-ip>:${port}  (all devices share same recipes)`);
  console.log(`  Local: http://localhost:${port}`);
  console.log(`API at /api/folders — CORS enabled`);
});
