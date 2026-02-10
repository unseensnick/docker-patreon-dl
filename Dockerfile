# Dockerfile for patreon-dl-gui
# Uses the official .deb package for a stable, production-ready build

FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
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
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Install Deno (optional)
RUN curl -fsSL https://deno.land/install.sh | sh \
    && mv /root/.deno/bin/deno /usr/local/bin/ \
    || echo "Deno installation skipped"

# Download and install patreon-dl-gui
RUN wget https://github.com/patrickkfkan/patreon-dl-gui/releases/download/v2.7.0/patreon-dl-gui_2.7.0_amd64.deb \
    && apt-get update \
    && apt-get install -y ./patreon-dl-gui_2.7.0_amd64.deb \
    && rm patreon-dl-gui_2.7.0_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /downloads /app-data

# Environment
ENV DISPLAY=:99
ENV ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Create improved startup script with better logging
RUN cat > /start.sh <<'STARTSCRIPT'
#!/bin/bash
set -e

echo "============================================"
echo "Patreon-DL-GUI Docker Container Starting"
echo "============================================"

# Cleanup function
cleanup() {
    echo "Cleaning up processes..."
    pkill -9 patreon-dl-gui 2>/dev/null || true
    pkill -9 Xvfb 2>/dev/null || true
    pkill -9 x11vnc 2>/dev/null || true
    pkill -9 fluxbox 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# Clean stale files
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true

# Start Xvfb
echo "[1/5] Starting virtual display (Xvfb)..."
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
echo "       Xvfb started with PID $XVFB_PID"

# Wait for X server
echo "[2/5] Waiting for X server to be ready..."
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

# Start fluxbox
echo "[3/5] Starting window manager (fluxbox)..."
fluxbox 2>/dev/null &
FLUXBOX_PID=$!
echo "       Fluxbox started with PID $FLUXBOX_PID"
sleep 1

# Start VNC server
echo "[4/5] Starting VNC server on port 5900..."
x11vnc -display :99 -forever -shared -rfbport 5900 -passwd patreon -noxdamage &
VNC_PID=$!
echo "       VNC server started with PID $VNC_PID"

# Verify VNC is running
sleep 2
if ! kill -0 $VNC_PID 2>/dev/null; then
    echo "       ERROR: VNC server failed to start"
    exit 1
fi

# Check if VNC port is listening
echo "       Checking VNC port 5900..."
if netstat -tuln 2>/dev/null | grep -q ":5900 "; then
    echo "       ✓ VNC server listening on port 5900"
else
    echo "       ⚠ Warning: VNC port 5900 may not be accessible"
fi

echo ""
echo "============================================"
echo "Services are ready!"
echo "============================================"
echo "VNC Direct:  localhost:5900 (password: patreon)"
echo "Web Browser: http://localhost:8080"
echo "============================================"
echo ""

# Find and start patreon-dl-gui
echo "[5/5] Starting patreon-dl-gui application..."

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
    echo "Searched locations:"
    echo "  - /opt/patreon-dl-gui/patreon-dl-gui"
    echo "  - /usr/local/bin/patreon-dl-gui"
    echo "  - PATH"
    exit 1
fi

echo "       Found application at: $APP_PATH"
echo "       Launching..."
echo ""

# Run the application with --no-sandbox flag (required when running as root in Docker)
exec "$APP_PATH" --no-sandbox
STARTSCRIPT

RUN chmod +x /start.sh

EXPOSE 5900

VOLUME ["/downloads", "/app-data"]

CMD ["/start.sh"]