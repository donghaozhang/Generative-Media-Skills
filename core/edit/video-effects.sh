#!/bin/bash
# Video Effects (MUAPI only)
# Usage: ./video-effects.sh --op face-swap --video-url URL --face-url URL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

OP=""
VIDEO_URL=""
VIDEO_FILE=""
IMAGE_URL=""
IMAGE_FILE=""
FACE_URL=""
FACE_FILE=""
AUDIO_URL=""
AUDIO_FILE=""
PROMPT=""
EFFECT=""
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
        --video-url) VIDEO_URL="$2"; shift 2 ;;
        --video-file) VIDEO_FILE="$2"; shift 2 ;;
        --image-url) IMAGE_URL="$2"; shift 2 ;;
        --image-file) IMAGE_FILE="$2"; shift 2 ;;
        --face-url) FACE_URL="$2"; shift 2 ;;
        --face-file) FACE_FILE="$2"; shift 2 ;;
        --audio-url) AUDIO_URL="$2"; shift 2 ;;
        --audio-file) AUDIO_FILE="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --effect) EFFECT="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Video Effects (MUAPI only)" >&2
            echo "" >&2
            echo "Operations (--op):" >&2
            echo "  wan-effects    Wan AI effects on image" >&2
            echo "  video-effect   Named effect on video" >&2
            echo "  image-effect   Named effect on image" >&2
            echo "  dance          Dance animation" >&2
            echo "  face-swap      Face swap in video" >&2
            echo "  dress-change   Change outfit" >&2
            echo "  luma-modify    Modify video with prompt" >&2
            echo "  luma-reframe   Reframe video" >&2
            echo "  vidu-reference Vidu character reference" >&2
            echo "" >&2
            echo "Note: Video effects require MUAPI. Not available on FAL." >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
if [ -z "$OP" ]; then echo "Error: --op is required" >&2; exit 1; fi
require_muapi "Video effects"

PROMPT_JSON=$(echo "${PROMPT:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')
EFFECT_JSON=$(echo "${EFFECT:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

clean_url() { echo "$1" | tr -d '"'; }

# Auto-upload local files
if [ -n "$VIDEO_FILE" ]; then VIDEO_URL=$(upload_file "$VIDEO_FILE" "$JSON_ONLY"); fi
if [ -n "$IMAGE_FILE" ]; then IMAGE_URL=$(upload_file "$IMAGE_FILE" "$JSON_ONLY"); fi
if [ -n "$FACE_FILE" ]; then FACE_URL=$(upload_file "$FACE_FILE" "$JSON_ONLY"); fi
if [ -n "$AUDIO_FILE" ]; then AUDIO_URL=$(upload_file "$AUDIO_FILE" "$JSON_ONLY"); fi

case $OP in
    wan-effects)
        if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url required" >&2; exit 1; fi
        ENDPOINT="generate_wan_ai_effects"
        PAYLOAD="{\"image_url\": \"$(clean_url "$IMAGE_URL")\", \"prompt\": $PROMPT_JSON}" ;;
    video-effect)
        if [ -z "$VIDEO_URL" ]; then echo "Error: --video-url required" >&2; exit 1; fi
        ENDPOINT="video-effects"
        PAYLOAD="{\"video_url\": \"$(clean_url "$VIDEO_URL")\", \"effect\": $EFFECT_JSON}" ;;
    image-effect)
        if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url required" >&2; exit 1; fi
        ENDPOINT="image-effects"
        PAYLOAD="{\"image_url\": \"$(clean_url "$IMAGE_URL")\", \"effect\": $EFFECT_JSON}" ;;
    dance)
        if [ -z "$IMAGE_URL" ] || [ -z "$AUDIO_URL" ]; then
            echo "Error: --image-url and --audio-url are required for dance" >&2; exit 1
        fi
        ENDPOINT="ai-dance-effects"
        PAYLOAD="{\"image_url\": \"$(clean_url "$IMAGE_URL")\", \"audio_url\": \"$(clean_url "$AUDIO_URL")\"}" ;;
    face-swap)
        if [ -z "$VIDEO_URL" ] || [ -z "$FACE_URL" ]; then
            echo "Error: --video-url and --face-url are required for face-swap" >&2; exit 1
        fi
        ENDPOINT="ai-video-face-swap"
        PAYLOAD="{\"video_url\": \"$(clean_url "$VIDEO_URL")\", \"face_image_url\": \"$(clean_url "$FACE_URL")\"}" ;;
    dress-change)
        if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url required" >&2; exit 1; fi
        ENDPOINT="ai-dress-change"
        PAYLOAD="{\"image_url\": \"$(clean_url "$IMAGE_URL")\", \"prompt\": $PROMPT_JSON}" ;;
    luma-modify)
        if [ -z "$VIDEO_URL" ]; then echo "Error: --video-url required" >&2; exit 1; fi
        ENDPOINT="luma-modify-video"
        PAYLOAD="{\"video_url\": \"$(clean_url "$VIDEO_URL")\", \"prompt\": $PROMPT_JSON}" ;;
    luma-reframe)
        if [ -z "$VIDEO_URL" ]; then echo "Error: --video-url required" >&2; exit 1; fi
        ENDPOINT="luma-flash-reframe"
        PAYLOAD="{\"video_url\": \"$(clean_url "$VIDEO_URL")\", \"prompt\": $PROMPT_JSON}" ;;
    vidu-reference)
        if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url required" >&2; exit 1; fi
        ENDPOINT="vidu-q1-reference"
        PAYLOAD="{\"image_url\": \"$(clean_url "$IMAGE_URL")\", \"prompt\": $PROMPT_JSON}" ;;
    *)
        echo "Error: Unknown operation '$OP'" >&2; exit 1 ;;
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
    [ "$JSON_ONLY" = false ] && echo "Check: bash check-result.sh --id \"$REQUEST_ID\"" >&2
    echo "$SUBMIT"; exit 0
fi

[ "$JSON_ONLY" = false ] && echo "Processing..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "auto")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Done! Result URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Operation failed" >&2
    echo "$RESULT" >&2; exit 1
fi
