#!/bin/bash
# record.sh — One-command video recording with music
# Usage: ./record.sh [output_name]

set -e
cd "$(dirname "$0")"

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
NAME="${1:-sacred_dance}"
AUDIO="music/the num singularity immersion.mp3"

echo "🎬 Recording full sacred geometry dance (~3.3 min video, ~8 min render)..."
echo "   Godot will exit automatically when done."

$GODOT --path . --write-movie "${NAME}.avi" 2>/dev/null

if [ ! -f "${NAME}.avi" ]; then
  echo "❌ Recording failed"
  exit 1
fi

echo "✅ Video rendered: $(ls -lh "${NAME}.avi" | awk '{print $5}')"
echo "🔊 Merging audio..."

ffmpeg -y -i "${NAME}.avi" -i "$AUDIO" \
  -map 0:v -map 1:a \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -shortest \
  "${NAME}.mp4" 2>/dev/null

echo "✨ ${NAME}.mp4 — $(ls -lh "${NAME}.mp4" | awk '{print $5}')"
