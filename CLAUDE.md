# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker containerization of [patreon-dl-gui](https://github.com/patrickkfkan/patreon-dl-gui) — provides VNC and noVNC web access to the Electron-based GUI app running headless in a container. This is an infrastructure/DevOps project, not an application codebase.

## Build & Run Commands

```bash
# Build locally (default version)
docker build -t patreon-dl-gui .

# Build with specific upstream version
docker build --build-arg VERSION=2.8.0 -t patreon-dl-gui:2.8.0 .

# Run with docker-compose (recommended)
docker-compose up -d

# Run standalone
docker run --rm -it -p 5900:5900 -p 6080:6080 \
  -v $(pwd)/downloads:/downloads \
  -v $(pwd)/appdata:/appdata \
  patreon-dl-gui
```

Access via VNC client at `localhost:5900` (recommended) or web browser at `http://localhost:6080`.

## Architecture

The entire project centers on a single [Dockerfile](Dockerfile) that:

1. Starts from `ubuntu:22.04`
2. Sets up a headless desktop stack: **Xvfb** (virtual display) → **Fluxbox** (window manager) → **x11vnc** (VNC server) → **noVNC/websockify** (web client)
3. Downloads and installs the upstream `patreon-dl-gui` .deb package (version controlled via `VERSION` build arg)
4. Installs supporting tools: `yt-dlp`, `ffmpeg`, `Deno` (optional)
5. Embeds a custom noVNC landing page with auto-connect, scaling/quality toggles
6. Generates `/start.sh` — the container entrypoint that orchestrates all services in sequence

### Configuration

All docker-compose settings use `${VAR:-default}` substitution from a `.env` file. Without `.env`, defaults apply. See [.env.template](.env.template) for all options.

### Key Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RESOLUTION` | `1920x1080` | Virtual display resolution |
| `DPI` | `96` | Display DPI (96, 120, 144) |
| `COLOR_DEPTH` | `24` | Xvfb color depth (16 or 24) |
| `VNC_PORT` | `5900` | Host port for VNC |
| `NOVNC_PORT` | `6080` | Host port for noVNC web |
| `VNC_PASSWORD` | *(empty)* | VNC password; empty = no auth |
| `TZ` | `UTC` | Container timezone |
| `FFMPEG_PATH` | `/usr/bin/ffmpeg` | Path to ffmpeg binary |
| `YTDLP_PATH` | `/usr/local/bin/yt-dlp` | Path to yt-dlp binary |
| `DENO_PATH` | `/usr/local/bin/deno` | Path to deno binary |
| `SHM_SIZE` | `4gb` | Shared memory for Electron/Chromium |
| `MEM_LIMIT` | `4g` | Container memory cap |
| `CPUS` | `4.0` | CPU core limit |
| `PIDS_LIMIT` | `512` | Max process count |
| `PATREON_DL_GUI_VERSION` | set at build | Baked-in version label |

### Security Hardening

The container runs with these security measures (configured in docker-compose.yml):

- `cap_drop: ALL` + `cap_add: SYS_CHROOT, NET_BIND_SERVICE` — minimal capabilities
- `no-new-privileges:true` — prevents privilege escalation
- `seccomp:unconfined` — required for Electron/Chromium syscalls
- `pids_limit: 512` — fork bomb protection
- `tmpfs` on `/tmp` and `/var/tmp` with `noexec,nosuid,nodev`
- `/downloads` volume with `noexec,nosuid`
- Localhost-only port binding (`127.0.0.1`)
- Isolated bridge network

### Container Paths

- `/downloads` — download output (volume mount)
- `/appdata` — preset config files (volume mount)
- `/start.sh` — entrypoint script (generated in Dockerfile)
- `/opt/patreon-dl-gui/patreon-dl-gui` — application executable
- `/usr/share/novnc/index.html` — custom noVNC page (generated in Dockerfile)

### Ports

- `5900` — VNC direct (recommended for best experience)
- `6080` — noVNC web access

## CI/CD

[build-and-push.yml](.github/workflows/build-and-push.yml) automates Docker Hub publishing:

- **Release**: triggered by publishing a GitHub release (tag like `v2.7.0`)
- **Push**: triggers on Dockerfile changes to main (uses `ARG VERSION` from Dockerfile)
- **Manual**: `workflow_dispatch` with optional version input
- Creates `built-v{VERSION}` git tags after successful builds
- Pushes to `unseensnick/patreon-dl-gui:{version}` and `:latest`
- Requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets

## Presets

[appdata/template-preset](appdata/template-preset) is the reference config file. Presets are INI-style with sections: `[downloader]`, `[output]`, `[include]`, `[request]`, `[logger.console]`, `[logger.file.1]`, `[patreon.dl.gui]`. User-specific presets (like `asmr-download-preset`) are gitignored.

## Key Notes

- Windows heredocs in Dockerfiles produce CRLF line endings — `/start.sh` has a `sed` fix for this
- noVNC clipboard doesn't work with security hardening; recommend VNC client for copy/paste
- `.env` is gitignored; `.env.template` is the committed reference
