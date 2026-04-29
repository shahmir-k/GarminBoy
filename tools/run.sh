#!/bin/bash
# run.sh — build GarminBoy and launch it in the Connect IQ simulator

set -e

SDK_BASE="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"
SDK_VERSION=$(ls "$SDK_BASE" | sort -V | tail -1)
SDK="$SDK_BASE/$SDK_VERSION"
MONKEYC="$SDK/bin/monkeyc"
MONKEYDO="$SDK/bin/monkeydo"
CONNECTIQ="$SDK/bin/connectiq"

DEVICE="fenix7xpro"
KEY="$HOME/.garmin/developer_key.der"
OUT="build/GarminBoy.prg"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p build

echo "SDK:    $SDK_VERSION"
echo "Device: $DEVICE"
echo ""

# ── 1. Build ────────────────────────────────────────────────────────────────
echo "Building..."
"$MONKEYC" \
    -f monkey.jungle \
    -d "$DEVICE" \
    -o "$OUT" \
    -y "$KEY" \
    -l 0 \
    -r

echo "Build OK → $OUT"
echo ""

# ── 2. Launch simulator (if not already running) ────────────────────────────
if ! pgrep -f "ConnectIQ.app" > /dev/null; then
    echo "Starting simulator..."
    open "$SDK/bin/ConnectIQ.app"
    sleep 6
fi

# ── 3. Load app into simulator ───────────────────────────────────────────────
echo "Loading into simulator..."
"$MONKEYDO" "$OUT" "$DEVICE"
