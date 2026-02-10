# Dockerfile for patreon-dl-gui
# VERSION is passed in by CI (e.g. "2.7.0") or defaults to latest known
ARG VERSION=2.7.0

FROM ubuntu:22.04

ARG VERSION
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies including good fonts and font rendering
RUN apt-get update && apt-get install -y \
    wget \
    ca-certificates \
    unzip \
    xvfb \
    x11vnc \
    fluxbox \
    x11-utils \
    ffmpeg \
    curl \
    procps \
    novnc \
    websockify \
    net-tools \
    # Font packages for sharp text rendering
    fonts-liberation \
    fonts-dejavu-core \
    fonts-noto-core \
    fonts-noto-color-emoji \
    fontconfig \
    libfontconfig1 \
    # Better X rendering
    libxrender1 \
    libxext6 \
    xdotool \
    && rm -rf /var/lib/apt/lists/*

# Configure fontconfig for sharp rendering
RUN mkdir -p /etc/fonts/conf.d && cat > /etc/fonts/local.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Liberation Sans</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>DejaVu Sans Mono</family></prefer>
  </alias>
</fontconfig>
EOF
RUN fc-cache -fv

# Install yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Install Deno (optional)
RUN curl -fsSL https://deno.land/install.sh | sh \
    && mv /root/.deno/bin/deno /usr/local/bin/ \
    || echo "Deno installation skipped"

# Download and install patreon-dl-gui (version driven by build arg)
RUN wget https://github.com/patrickkfkan/patreon-dl-gui/releases/download/v${VERSION}/patreon-dl-gui_${VERSION}_amd64.deb \
    && apt-get update \
    && apt-get install -y ./patreon-dl-gui_${VERSION}_amd64.deb \
    && rm patreon-dl-gui_${VERSION}_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# Bake the version into the image as a label and env var
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.source="https://github.com/patrickkfkan/patreon-dl-gui"
ENV PATREON_DL_GUI_VERSION=${VERSION}

# Create directories
RUN mkdir -p /downloads /app-data

# Create custom noVNC landing page with auto-connect and sharp scaling
RUN cat > /usr/share/novnc/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Patreon-DL GUI</title>
    <meta charset="utf-8">
    <style>
        body {
            margin: 0;
            background: #1a1a2e;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        #loading {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #e0e0e0;
            font-size: 18px;
            z-index: 1000;
            background: #1a1a2e;
        }
        #loading.hidden { display: none; }
        #screen {
            width: 100vw;
            height: 100vh;
        }
        #toolbar {
            position: fixed;
            top: 0;
            right: 0;
            z-index: 100;
            display: flex;
            gap: 4px;
            padding: 6px;
            background: rgba(0,0,0,0.6);
            border-bottom-left-radius: 8px;
            opacity: 0;
            transition: opacity 0.2s;
        }
        #toolbar:hover { opacity: 1; }
        #toolbar button {
            background: rgba(255,255,255,0.15);
            border: none;
            color: white;
            padding: 4px 10px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 13px;
        }
        #toolbar button:hover { background: rgba(255,255,255,0.3); }
        #toolbar button.active { background: rgba(100,180,255,0.4); }
    </style>
</head>
<body>
    <div id="loading">Connecting to desktop...</div>
    <div id="toolbar">
        <button id="btn-scale" class="active" title="Toggle scaling mode">Fit</button>
        <button id="btn-quality" class="active" title="Toggle quality">Sharp</button>
        <button id="btn-fullscreen" title="Fullscreen">&#x26F6;</button>
    </div>
    <div id="screen"></div>

    <script type="module">
        import RFB from './core/rfb.js';

        const host = window.location.hostname;
        const port = window.location.port || 6080;
        const url = `ws://${host}:${port}/websockify`;

        const loading = document.getElementById('loading');
        let rfb;
        let scaleMode = 'scale';
        let qualityMode = 'sharp';

        function connect() {
            rfb = new RFB(document.getElementById('screen'), url, {});
            rfb.scaleViewport = true;
            rfb.resizeSession = false;
            rfb.qualityLevel = 9;
            rfb.compressionLevel = 0;

            rfb.addEventListener('connect', () => {
                loading.classList.add('hidden');
                applyCanvasSharpness();
            });

            rfb.addEventListener('disconnect', () => {
                loading.textContent = 'Disconnected. Reconnecting in 3s...';
                loading.classList.remove('hidden');
                setTimeout(connect, 3000);
            });
        }

        function applyCanvasSharpness() {
            setTimeout(() => {
                const canvas = document.querySelector('#screen canvas');
                if (canvas) {
                    canvas.style.imageRendering = qualityMode === 'sharp' ? 'pixelated' : 'auto';
                }
            }, 200);
        }

        document.getElementById('btn-scale').addEventListener('click', (e) => {
            if (scaleMode === 'scale') {
                scaleMode = 'native';
                rfb.scaleViewport = false;
                e.target.textContent = '1:1';
                e.target.classList.remove('active');
            } else {
                scaleMode = 'scale';
                rfb.scaleViewport = true;
                e.target.textContent = 'Fit';
                e.target.classList.add('active');
            }
        });

        document.getElementById('btn-quality').addEventListener('click', (e) => {
            if (qualityMode === 'sharp') {
                qualityMode = 'smooth';
                e.target.textContent = 'Smooth';
                e.target.classList.remove('active');
            } else {
                qualityMode = 'sharp';
                e.target.textContent = 'Sharp';
                e.target.classList.add('active');
            }
            applyCanvasSharpness();
        });

        document.getElementById('btn-fullscreen').addEventListener('click', () => {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen();
            } else {
                document.exitFullscreen();
            }
        });

        connect();
    </script>
</body>
</html>
HTMLEOF

# Environment
ENV DISPLAY=:99
ENV ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Configurable resolution and DPI via environment variables
ENV RESOLUTION=1920x1080
ENV DPI=96

# Create startup script
RUN cat > /start.sh <<'STARTSCRIPT'
#!/bin/bash
set -e

echo "============================================"
echo "Patreon-DL-GUI Docker Container"
echo "App Version: ${PATREON_DL_GUI_VERSION}"
echo "Resolution:  ${RESOLUTION} @ ${DPI} DPI"
echo "============================================"

cleanup() {
    echo "Cleaning up processes..."
    pkill -9 patreon-dl-gui 2>/dev/null || true
    pkill -9 Xvfb 2>/dev/null || true
    pkill -9 x11vnc 2>/dev/null || true
    pkill -9 fluxbox 2>/dev/null || true
    pkill -9 websockify 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true

# Start Xvfb with configurable resolution and DPI
echo "[1/6] Starting virtual display (${RESOLUTION}x24 @ ${DPI} DPI)..."
Xvfb :99 -screen 0 ${RESOLUTION}x24 -dpi ${DPI} -ac +extension GLX +extension RENDER -noreset &
XVFB_PID=$!

# Wait for X server
echo "[2/6] Waiting for X server..."
for i in {1..30}; do
    if xdpyinfo -display :99 >/dev/null 2>&1; then
        echo "       X server is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "       ERROR: X server timeout"
        exit 1
    fi
    sleep 1
done

# Set X resources for font rendering
xrdb -merge <<XRESOURCES
Xft.dpi: ${DPI}
Xft.antialias: true
Xft.hinting: true
Xft.hintstyle: hintslight
Xft.rgba: rgb
Xft.lcdfilter: lcddefault
XRESOURCES

# Start fluxbox
echo "[3/6] Starting window manager..."
fluxbox 2>/dev/null &
sleep 1

# Start VNC server with optimized settings
echo "[4/6] Starting VNC server on port 5900..."
x11vnc -display :99 \
    -forever \
    -shared \
    -rfbport 5900 \
    -nopw \
    -noxdamage \
    -cursor arrow \
    -noxfixes \
    -threads \
    &
VNC_PID=$!
sleep 2

if ! kill -0 $VNC_PID 2>/dev/null; then
    echo "       ERROR: VNC server failed to start"
    exit 1
fi
echo "       ✓ VNC server listening on port 5900"

# Start noVNC
echo "[5/6] Starting noVNC web client on port 6080..."
websockify --web /usr/share/novnc 6080 localhost:5900 &
NOVNC_PID=$!
sleep 1

if ! kill -0 $NOVNC_PID 2>/dev/null; then
    echo "       ERROR: noVNC/websockify failed to start"
    exit 1
fi
echo "       ✓ noVNC listening on port 6080"

echo ""
echo "============================================"
echo "Services are ready!"
echo "============================================"
echo "VNC Direct:  localhost:5900"
echo "Web Browser: http://localhost:6080"
echo "============================================"
echo ""

# Find and start patreon-dl-gui
echo "[6/6] Starting patreon-dl-gui application..."

APP_PATH=""
if [ -f /opt/patreon-dl-gui/patreon-dl-gui ]; then
    APP_PATH="/opt/patreon-dl-gui/patreon-dl-gui"
elif [ -f /usr/local/bin/patreon-dl-gui ]; then
    APP_PATH="/usr/local/bin/patreon-dl-gui"
elif command -v patreon-dl-gui >/dev/null 2>&1; then
    APP_PATH=$(which patreon-dl-gui)
fi

if [ -z "$APP_PATH" ]; then
    echo "ERROR: patreon-dl-gui executable not found!"
    exit 1
fi

echo "       Found application at: $APP_PATH"
echo "       Launching..."

# Force Electron to use exact 1x scaling (no fractional DPI scaling)
exec "$APP_PATH" --no-sandbox --force-device-scale-factor=1
STARTSCRIPT

RUN chmod +x /start.sh

EXPOSE 5900 6080

VOLUME ["/downloads", "/app-data"]

CMD ["/start.sh"]