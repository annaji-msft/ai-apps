#!/usr/bin/env bash
# Bootstrap a minimal Linux desktop inside a fresh `ubuntu` sandbox:
#   - Xvfb on display :99 (1280x800)
#   - Chromium (kiosk-launched at the demo form)
#   - xdotool for keyboard/mouse synthesis
#   - x11vnc -> noVNC on :6080 so the operator can watch in a browser
#   - FastAPI control server on :7000 exposing the computer-use primitives
#     (/screenshot /click /double_click /move /drag /type /key /scroll /wait)
#     plus the demo form on :8080 and a submission sink at /submission
#
# Designed to be uploaded into a freshly booted sandbox and run via
# `sandbox.exec("bash /opt/desktop/setup.sh")`. Idempotent — re-running
# only restarts the services.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DISPLAY=:99

mkdir -p /opt/desktop /var/log/desktop

# ----------------------------------------------------------------------------
# Packages. Kept minimal; the heavy hitters are Chromium and noVNC.
# ----------------------------------------------------------------------------
if ! command -v Xvfb >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    xvfb x11vnc xdotool scrot imagemagick \
    python3 python3-pip python3-venv \
    chromium-browser \
    novnc websockify \
    fonts-dejavu-core ca-certificates curl \
    >/var/log/desktop/apt.log 2>&1
fi

# Some Ubuntu images ship `chromium` instead of `chromium-browser`.
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium || true)"
if [ -z "$CHROMIUM_BIN" ]; then
  echo "ERROR: no chromium binary found" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Python venv for the control server. We isolate to avoid clobbering whatever
# the user's agent script may install separately.
# ----------------------------------------------------------------------------
if [ ! -d /opt/desktop/venv ]; then
  python3 -m venv /opt/desktop/venv
  /opt/desktop/venv/bin/pip install --quiet --upgrade pip
  /opt/desktop/venv/bin/pip install --quiet fastapi 'uvicorn[standard]' pillow
fi

# ----------------------------------------------------------------------------
# Kill any prior instances so this script is safe to re-run.
# ----------------------------------------------------------------------------
pkill -f "Xvfb :99"              2>/dev/null || true
pkill -f "x11vnc"                2>/dev/null || true
pkill -f "websockify"            2>/dev/null || true
pkill -f "control_server"        2>/dev/null || true
pkill -f "chromium"              2>/dev/null || true
sleep 1

# ----------------------------------------------------------------------------
# Xvfb — a virtual X server. 1280x800x24 matches what we tell the model.
# ----------------------------------------------------------------------------
nohup Xvfb :99 -screen 0 1280x800x24 -ac \
  >/var/log/desktop/xvfb.log 2>&1 &

# Wait for the X server to be ready.
for _ in $(seq 1 30); do
  if xdotool getdisplaygeometry >/dev/null 2>&1; then break; fi
  sleep 0.2
done

# ----------------------------------------------------------------------------
# Control server — must be up before the form URL works.
# ----------------------------------------------------------------------------
nohup /opt/desktop/venv/bin/uvicorn \
    --app-dir /opt/desktop control_server:app \
    --host 0.0.0.0 --port 7000 \
  >/var/log/desktop/control.log 2>&1 &

# Demo form server (separate uvicorn, separate port, separate FastAPI app
# inside the same module). We split ports so the agent's "navigate to
# localhost:8080" instruction lines up with what the human watching the
# noVNC tab also sees in the URL bar.
nohup /opt/desktop/venv/bin/uvicorn \
    --app-dir /opt/desktop control_server:form_app \
    --host 0.0.0.0 --port 8080 \
  >/var/log/desktop/form.log 2>&1 &

# Wait for control server.
for _ in $(seq 1 40); do
  if curl -sf http://127.0.0.1:7000/healthz >/dev/null; then break; fi
  sleep 0.25
done

# ----------------------------------------------------------------------------
# Chromium — kiosk-launched at the demo form. --no-sandbox is required
# inside containers without user namespaces.
# ----------------------------------------------------------------------------
nohup "$CHROMIUM_BIN" \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --no-first-run \
    --no-default-browser-check \
    --disable-features=Translate \
    --start-maximized \
    --window-size=1280,800 \
    --window-position=0,0 \
    --app=http://localhost:8080/ \
  >/var/log/desktop/chromium.log 2>&1 &

# ----------------------------------------------------------------------------
# x11vnc -> noVNC on :6080. -forever survives client disconnects;
# -shared lets multiple noVNC tabs attach; -nopw is fine because the
# only way to reach :6080 is via the ACA-minted public URL on the
# sandbox's add_port, and the agent is in an isolated sandbox anyway.
# ----------------------------------------------------------------------------
nohup x11vnc -display :99 -forever -shared -nopw -quiet -bg \
  >/var/log/desktop/x11vnc.log 2>&1 || true

nohup websockify --web=/usr/share/novnc 6080 localhost:5900 \
  >/var/log/desktop/novnc.log 2>&1 &

# Give Chromium a moment to draw the first frame.
sleep 3

echo "desktop ready"
echo "  control: http://127.0.0.1:7000/healthz"
echo "  form:    http://127.0.0.1:8080/"
echo "  noVNC:   http://127.0.0.1:6080/vnc.html"
