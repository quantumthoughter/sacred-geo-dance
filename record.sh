#!/bin/bash
# record.sh — One-command automated video + audio rendering for Sacred Geometry Dance
# Usage: ./record.sh [duration_seconds] [output_name]

set -e
cd "$(dirname "$0")"

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
DURATION="${1:-180}"
NAME="${2:-sacred_dance}"
AUDIO="music/the num singularity immersion.mp3"

echo "🌙 Recording ${NAME} — ${DURATION}s of sacred geometry..."
echo "   (offline render — will take a few minutes)"

# Step 1: Render video-only AVI with Godot MovieWriter
echo "🎬 Rendering frames..."
$GODOT --path . --write-movie "${NAME}.avi" &
GODOT_PID=$!
sleep "$DURATION"
kill $GODOT_PID 2>/dev/null
wait $GODOT_PID 2>/dev/null
echo "   ✓ Frames captured"

# Step 2: Extract audio segment matching video duration
echo "🔊 Extracting audio..."
ffmpeg -y -i "${NAME}.avi" -i "$AUDIO" \
  -map 0:v -map 1:a \
  -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  -shortest \
  "${NAME}.mp4" 2>&1 | tail -1

echo "✨ Done: ${NAME}.mp4"
ls -lh "${NAME}.mp4"
