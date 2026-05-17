#!/bin/bash
# record.sh — Smooth 30fps recording + audio merge
# Usage: ./record.sh [duration_sec] [output_name]
set -e
cd "$(dirname "$0")"

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
DURATION="${1:-199}"
NAME="${2:-sacred_dance}"
AUDIO="music/the num singularity immersion.mp3"
AVI="${NAME}.avi"
MP4="${NAME}.mp4"

echo "🎬 Recording ${DURATION}s at 30fps 1280x720..."
echo "   Render takes ~3x real-time"

$GODOT --path . --write-movie "$AVI" --fixed-fps 30 2>/dev/null

if [ ! -f "$AVI" ]; then
  echo "❌ No AVI created"
  exit 1
fi

SIZE=$(ls -lh "$AVI" | awk '{print $5}')
echo "✅ Video: $SIZE"
echo "🔊 Merging audio..."

ffmpeg -y -i "$AVI" -i "$AUDIO" \
  -t "$DURATION" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  "$MP4" 2>/dev/null

echo "✨ $MP4 — $(ls -lh "$MP4" | awk '{print $5}')"
