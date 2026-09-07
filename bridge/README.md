# Bakedown HTTP Bridge

Browser `web` builds **cannot** speak raw SMB (TCP 445) — the sandbox blocks it.
This bridge exposes a local folder (your recipe share, or an SMB mount) over HTTP
with CORS so `Bakedown Web` can use it as a drop-in SMB replacement.

## Quick start

```bash
# Point at your recipe folder directly
python bridge/server.py --dir /srv/recipes --port 8787 --host 0.0.0.0

# Or mount SMB first, then point at the mount
sudo mount -t cifs //192.168.1.50/recipes /mnt/recipes -o username=dan,uid=$(id -u)
python bridge/server.py --dir /mnt/recipes --port 8787
```

Windows:

```powershell
python bridge/server.py --dir "Z:\Recipes" --port 8787
# Z: is a mapped drive to \\192.168.1.50\recipes
```

Then in Bakedown (web or desktop):

1. Settings → **HTTP Bridge** → enable → `http://192.168.1.100:8787` → **Test Bridge**
2. Browse → folders now come from the bridge (CORS already enabled)

The bridge also answers `/api/discover` so **Network scan** on native can find it
as `_http._tcp` + subnet probe.

## API

- `GET /api/folders` → `["Desserts","Mains"]`
- `GET /api/folders/<folder>` → `["cake.md",...]`
- `GET /api/file/<folder>/<file>` → `text/markdown`
- `PUT /api/file/<folder>/<file>` (body = markdown) → create/update
- `DELETE /api/file/<folder>/<file>` / `DELETE /api/folder/<name>` / `POST /api/folder/<name>`
- `GET /files/<folder>/<file>` → raw bytes (images)
- `GET /api/discover` → `[{"name","host","port":8787}]`

All endpoints send `Access-Control-Allow-Origin: *`.

## Why not direct SMB on web?

- `package:smb_connect` uses `dart:io Socket` (raw TCP). Browsers forbid it.
- `file_picker` `getDirectoryPath()` is not implemented on web.
- `nsd` mDNS multicast is blocked.

The bridge is the supported path for web. On native (Android/Windows) you can
still use direct **Network Share** SMB — discovery now scans `_smb._tcp`,
`_microsoft-ds._tcp`, `_adisk._tcp`, `_afpovertcp._tcp` + subnet `445` probe (32 parallel,
250 ms timeout) and aggregates via `nsd` + fallback, so auto-discovery finds
more servers than before.

## Systemd service

```ini
[Unit]
Description=Bakedown Bridge
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/bakedown/bridge/server.py --dir /srv/recipes --host 0.0.0.0 --port 8787
Restart=always

[Install]
WantedBy=multi-user.target
```

## Security

- No auth by default — run on trusted LAN only. Put behind reverse proxy with
  basic-auth if exposed.
- Path traversal blocked (`..` rejected, resolved path must stay under root).
