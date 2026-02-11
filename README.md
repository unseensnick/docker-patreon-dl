# docker-patreon-dl

Docker image for [patreon-dl-gui](https://github.com/patrickkfkan/patreon-dl-gui) with browser-based access via noVNC.

Runs the Electron-based patreon-dl-gui application inside a headless container and exposes it over VNC (port 5900) and a web interface (port 6080). All required tools (ffmpeg, yt-dlp, Deno) are pre-installed.

## What It Downloads

- Posts by a creator, in a collection, or a single post (including patron-only content with an active subscription)
- Products purchased from a creator's shop
- Media types: videos, images, audio, attachments
- Embedded videos from YouTube, Vimeo, and SproutVideo

## Quick Start

### Using Docker Compose (recommended)

```bash
git clone https://github.com/unseensnick/docker-patreon-dl.git
cd docker-patreon-dl
docker-compose up -d
```

Open http://localhost:6080 in your browser.

### Using Docker Run

```bash
docker run --rm -it \
  --name patreon-dl-gui \
  -p 5900:5900 \
  -p 6080:6080 \
  -v $(pwd)/downloads:/downloads \
  -v $(pwd)/appdata:/appdata \
  --shm-size=4g \
  unseensnick/patreon-dl-gui:latest
```

## Usage

1. Open the noVNC web interface at http://localhost:6080
2. Load the `template-preset` from `/appdata` to populate the ffmpeg, Deno, and yt-dlp paths in the GUI. Without this, those fields will be empty on a fresh start.
3. In the embedded browser within patreon-dl-gui, navigate to the Patreon page you want to download from. Log in if downloading patron-only content.
4. The app identifies downloadable targets automatically and shows them in the editor panel with the required cookie data.
5. Configure download options as needed (use Help menu > "Show Help Icons" for option descriptions).
6. Click the play button in the toolbar to start downloading.
7. Configurations can be saved to `/appdata` as preset files for reuse.

### Embedded Video Downloads

Vimeo and SproutVideo embeds use a helper script powered by yt-dlp (pre-installed in the container):

1. In patreon-dl-gui, go to "Embeds -> Vimeo" or "Embeds -> SproutVideo"
2. Select "Use helper script" for "Download method"
3. Set "Path to yt-dlp" to `/usr/local/bin/yt-dlp`

YouTube embeds use a built-in downloader. Deno (pre-installed) is recommended for sandboxing code from YouTube/Google servers — without it, code runs without isolation.

### Browsing Downloaded Content

Downloaded content (v2.2.0+) can be browsed through a web server:

1. Open the `patreon-dl-gui (Server Console)` from the Utilities menu
2. Click "Add" and set the data directory to `/downloads`
3. Start the server and open the provided URL

## Building from Source

```bash
# Default version
docker build -t patreon-dl-gui .

# Specific upstream version
docker build --build-arg VERSION=2.7.0 -t patreon-dl-gui .
```

To build locally with docker-compose, uncomment the `build` line in `docker-compose.yml`.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOLUTION` | `1920x1080` | Virtual display resolution (`1920x1080`, `2560x1440`, `3840x2160`, etc.) |
| `DPI` | `96` | Display DPI. Increase to `120` or `144` for sharper text on HiDPI displays |
| `COLOR_DEPTH` | `24` | Display color depth. Set to `16` to reduce VNC bandwidth on slow connections |
| `VNC_PASSWORD` | *(empty)* | Set to require a password for VNC/noVNC access. Empty = no password |
| `TZ` | `UTC` | Container timezone (e.g. `America/New_York`, `Europe/London`) |
| `FFMPEG_PATH` | `/usr/bin/ffmpeg` | Path to ffmpeg binary |
| `YTDLP_PATH` | `/usr/local/bin/yt-dlp` | Path to yt-dlp binary |
| `DENO_PATH` | `/usr/local/bin/deno` | Path to deno binary |

### Volumes

| Container Path | Purpose |
|---------------|---------|
| `/downloads` | Download output directory |
| `/appdata` | Preset configuration files |

### Presets

Place preset files in the `appdata/` directory. See `appdata/template-preset` for all available options. Presets are INI-style config files compatible with the [patreon-dl CLI](https://github.com/patrickkfkan/patreon-dl) (with minor exceptions — single target only, single file logger only).

Key preset sections:
- `[downloader]` — target URL, cookies, ffmpeg/deno paths, status cache, stop conditions, dry run, max video resolution
- `[output]` — output directory, directory/filename format templates, file-exists conflict actions
- `[include]` — locked content, tier/media type filters, date ranges, campaign/content info, media variants, thumbnails, filename filters, comments
- `[request]` — max retries, concurrency, rate limiting (min time), proxy, user agent
- `[embed.downloader.*]` — custom executables for YouTube, Vimeo, SproutVideo embeds
- `[logger.console]` / `[logger.file.1]` — log level, date format, color, file output
- `[patreon.dl.gui]` — YouTube connection, Vimeo/SproutVideo downloader type and yt-dlp settings

## Included Tools

| Tool | Purpose | Container Path |
|------|---------|---------------|
| **ffmpeg** | Required for most Patreon-hosted videos | `/usr/bin/ffmpeg` |
| **yt-dlp** | Downloads embedded Vimeo and SproutVideo content via helper script | `/usr/local/bin/yt-dlp` |
| **Deno** | Sandboxes YouTube downloader code for security | `/usr/local/bin/deno` |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 5900 | VNC | Direct VNC client connection |
| 6080 | HTTP | noVNC web interface |

## Resource Recommendations

The `docker-compose.yml` is configured with:
- `shm_size: 4gb` — shared memory for the Electron app
- `mem_limit: 8g` — memory cap
- `cpus: 4.0` — CPU limit

Adjust these based on your system. Lower-spec setups can reduce these values.

## Automated Builds

A GitHub Actions workflow checks the upstream [patreon-dl-gui releases](https://github.com/patrickkfkan/patreon-dl-gui/releases) daily and automatically builds and pushes a new Docker image to Docker Hub when a new version is detected.
