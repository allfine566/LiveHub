#!/bin/bash
set -u

INPUT="LiveStreams.json"
OUTPUT="live.json"
TEMP="/tmp/live_results.json"

# Start with an empty array
echo "[]" > "$TEMP"

COUNT=$(jq '.channels | length' "$INPUT")
echo "Checking $COUNT channels from $INPUT..."
echo ""

for i in $(seq 0 $((COUNT - 1))); do
  ID=$(jq -r ".channels[$i].id"   "$INPUT")
  NAME=$(jq -r ".channels[$i].name" "$INPUT")
  URL=$(jq -r ".channels[$i].url"  "$INPUT")

  # Convert the /streams URL to /live (which resolves to the active stream, if any)
  LIVE_URL=$(echo "$URL" | sed 's|/streams$|/live|')

  echo "→ $NAME  ($LIVE_URL)"

  # Query yt-dlp for metadata. It exits non-zero if there's no live stream.
  INFO=$(yt-dlp \
    --no-warnings \
    --no-playlist \
    --skip-download \
    --socket-timeout 20 \
    --dump-single-json \
    "$LIVE_URL" 2>/dev/null) || INFO=""

  if [ -n "$INFO" ]; then
    STATUS=$(echo "$INFO" | jq -r '.live_status // "unknown"' 2>/dev/null)
    if [ "$STATUS" = "is_live" ]; then
      VIDEO_ID=$(echo "$INFO" | jq -r '.id')
      TITLE=$(echo "$INFO"    | jq -r '.title')
      echo "   ✓ LIVE  (video: $VIDEO_ID)"
      echo "     $TITLE"
      jq --arg id "$ID" --arg name "$NAME" \
         --arg vid "$VIDEO_ID" --arg title "$TITLE" \
         '. + [{id: $id, name: $name, video_id: $vid, title: $title}]' \
         "$TEMP" > "${TEMP}.new" && mv "${TEMP}.new" "$TEMP"
    else
      echo "   ✗ not live (status: $STATUS)"
    fi
  else
    echo "   ✗ not live (no active stream)"
  fi

  echo ""
  sleep 1   # Small pause to avoid rate-limiting YouTube
done

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n --arg ts "$TIMESTAMP" --slurpfile live "$TEMP" \
  '{updated_at: $ts, live: $live[0]}' > "$OUTPUT"

echo "──────────────────────────────────────────"
echo "Wrote $OUTPUT with $(jq '.live | length' "$OUTPUT") live stream(s)."
