#!/bin/bash
# Audio & Music Generation (MUAPI only — Suno)
# Usage: ./create-music.sh --op create --style "lo-fi" --prompt "chill beats"

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

OP="create"
STYLE=""
PROMPT=""
SUNO_MODEL="V5"
AUDIO_URL=""
AUDIO_FILE=""
VIDEO_URL=""
VIDEO_FILE=""
DURATION=10
PROVIDER=""
ASYNC=false
JSON_ONLY=false
MAX_WAIT=300
POLL_INTERVAL=5

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --op) OP="$2"; shift 2 ;;
        --style) STYLE="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --suno-model) SUNO_MODEL="$2"; shift 2 ;;
        --audio-url) AUDIO_URL="$2"; shift 2 ;;
        --audio-file) AUDIO_FILE="$2"; shift 2 ;;
        --video-url) VIDEO_URL="$2"; shift 2 ;;
        --video-file) VIDEO_FILE="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Audio & Music Generation (MUAPI only)" >&2
            echo "" >&2
            echo "Operations (--op):" >&2
            echo "  create       Suno music creation (default)" >&2
            echo "  remix        Suno remix (requires --audio-url)" >&2
            echo "  extend       Suno extend (requires --audio-url)" >&2
            echo "  text-to-audio  MMAudio from text prompt" >&2
            echo "  video-to-audio MMAudio from video (requires --video-url)" >&2
            echo "" >&2
            echo "Note: Music generation requires MUAPI (Suno). Not available on FAL." >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  bash create-music.sh --style \"lo-fi hip hop\" --prompt \"chill beats\"" >&2
            echo "  bash create-music.sh --op text-to-audio --prompt \"thunderstorm\" --duration 15" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
require_muapi "Music generation (Suno)"

PROMPT_JSON=$(echo "${PROMPT:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')
STYLE_JSON=$(echo "${STYLE:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

# Auto-upload local files
if [ -n "$AUDIO_FILE" ]; then AUDIO_URL=$(upload_file "$AUDIO_FILE" "$JSON_ONLY"); fi
if [ -n "$VIDEO_FILE" ]; then VIDEO_URL=$(upload_file "$VIDEO_FILE" "$JSON_ONLY"); fi

case $OP in
    create)
        if [ -z "$STYLE" ]; then echo "Error: --style is required for create" >&2; exit 1; fi
        ENDPOINT="suno-create-music"
        PAYLOAD="{\"style\": $STYLE_JSON, \"prompt\": $PROMPT_JSON, \"model\": \"$SUNO_MODEL\"}" ;;
    remix)
        if [ -z "$AUDIO_URL" ]; then echo "Error: --audio-url is required for remix" >&2; exit 1; fi
        AUDIO_CLEAN=$(echo "$AUDIO_URL" | tr -d '"')
        ENDPOINT="suno-remix-music"
        PAYLOAD="{\"audio_url\": \"$AUDIO_CLEAN\", \"style\": $STYLE_JSON, \"prompt\": $PROMPT_JSON, \"model\": \"$SUNO_MODEL\"}" ;;
    extend)
        if [ -z "$AUDIO_URL" ]; then echo "Error: --audio-url is required for extend" >&2; exit 1; fi
        AUDIO_CLEAN=$(echo "$AUDIO_URL" | tr -d '"')
        ENDPOINT="suno-extend-music"
        PAYLOAD="{\"audio_url\": \"$AUDIO_CLEAN\", \"prompt\": $PROMPT_JSON, \"model\": \"$SUNO_MODEL\"}" ;;
    text-to-audio)
        if [ -z "$PROMPT" ]; then echo "Error: --prompt is required for text-to-audio" >&2; exit 1; fi
        ENDPOINT="mmaudio-v2/text-to-audio"
        PAYLOAD="{\"prompt\": $PROMPT_JSON, \"duration\": $DURATION}" ;;
    video-to-audio)
        if [ -z "$VIDEO_URL" ]; then echo "Error: --video-url is required for video-to-audio" >&2; exit 1; fi
        VIDEO_CLEAN=$(echo "$VIDEO_URL" | tr -d '"')
        ENDPOINT="mmaudio-v2/video-to-video"
        PAYLOAD="{\"video_url\": \"$VIDEO_CLEAN\", \"prompt\": $PROMPT_JSON}" ;;
    *)
        echo "Error: Unknown operation '$OP'" >&2
        echo "Valid: create, remix, extend, text-to-audio, video-to-audio" >&2
        exit 1 ;;
esac

[ "$JSON_ONLY" = false ] && echo "Submitting $OP to $ENDPOINT (muapi)..." >&2

SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
    ERR=$(echo "$SUBMIT" | jq -r '.error // .detail // empty')
    [ -n "$ERR" ] && { echo "Error: $ERR" >&2; exit 1; }
fi

REQUEST_ID=$(extract_request_id "$SUBMIT")
if [ -z "$REQUEST_ID" ]; then echo "Error: No request_id" >&2; echo "$SUBMIT" >&2; exit 1; fi
[ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2

if [ "$ASYNC" = true ]; then
    [ "$JSON_ONLY" = false ] && echo "Music generation takes 30-90s. Check: bash check-result.sh --id \"$REQUEST_ID\"" >&2
    echo "$SUBMIT"; exit 0
fi

[ "$JSON_ONLY" = false ] && echo "Generating (30-90 seconds)..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "audio")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Audio generation complete!" >&2
    [ "$JSON_ONLY" = false ] && echo "Audio URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Generation failed" >&2
    echo "$RESULT" >&2; exit 1
fi
