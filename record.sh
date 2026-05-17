#!/bin/bash
# record.sh — Clean recording at 30fps, 960x540, auto audio merge
set -e
cd "$(dirname "$0")"

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
NAME="${1:-sacred_dance}"
AUDIO="music/the num singularity immersion.mp3"
AVI="${NAME}.avi"
MP4="${NAME}.mp4"

echo "🎬 Recording at 30fps 960x540..."
echo "   ~6-8 min render for ~3.3 min video"

$GODOT --path . --write-movie "$AVI" 2>/dev/null

if [ ! -f "$AVI" ]; then
  echo "❌ Recording failed"
  exit 1
fi

echo "✅ Video: $(ls -lh "$AVI" | awk '{print $5}')"
echo "🔊 Merging audio..."

ffmpeg -y -i "$AVI" -i "$AUDIO" \
  -map 0:v -map 1:a \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -shortest \
  "$MP4" 2>/dev/null

echo "✨ $MP4 — $(ls -lh "$MP4" | awk '{print $5}')"
