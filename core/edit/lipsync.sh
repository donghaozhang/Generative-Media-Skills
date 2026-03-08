#!/bin/bash
# Lipsync (MUAPI only)
# Usage: ./lipsync.sh --video-url URL --audio-url URL [--model sync]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

VIDEO_URL=""
VIDEO_FILE=""
AUDIO_URL=""
AUDIO_FILE=""
MODEL="sync"
PROVIDER=""
ASYNC=false
JSON_ONLY=false
MAX_WAIT=300
POLL_INTERVAL=5

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --video-url) VIDEO_URL="$2"; shift 2 ;;
        --video-file) VIDEO_FILE="$2"; shift 2 ;;
        --audio-url) AUDIO_URL="$2"; shift 2 ;;
        --audio-file) AUDIO_FILE="$2"; shift 2 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Lipsync (MUAPI only)" >&2
            echo "" >&2
            echo "Usage: ./lipsync.sh --video-url URL --audio-url URL [options]" >&2
            echo "" >&2
            echo "Models (--model):" >&2
            echo "  sync      Sync Labs (default)" >&2
            echo "  latent    LatentSync" >&2
            echo "  creatify  Creatify" >&2
            echo "  veed      Veed" >&2
            echo "" >&2
            echo "Note: Lipsync requires MUAPI. Not available on FAL." >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
require_muapi "Lipsync"

# Auto-upload local files
if [ -n "$VIDEO_FILE" ]; then VIDEO_URL=$(upload_file "$VIDEO_FILE" "$JSON_ONLY"); fi
if [ -n "$AUDIO_FILE" ]; then AUDIO_URL=$(upload_file "$AUDIO_FILE" "$JSON_ONLY"); fi

if [ -z "$VIDEO_URL" ]; then echo "Error: --video-url or --video-file is required" >&2; exit 1; fi
if [ -z "$AUDIO_URL" ]; then echo "Error: --audio-url or --audio-file is required" >&2; exit 1; fi

VIDEO_CLEAN=$(echo "$VIDEO_URL" | tr -d '"')
AUDIO_CLEAN=$(echo "$AUDIO_URL" | tr -d '"')

case $MODEL in
    sync)     ENDPOINT="sync-lipsync" ;;
    latent)   ENDPOINT="latentsync-video" ;;
    creatify) ENDPOINT="creatify-lipsync" ;;
    veed)     ENDPOINT="veed-lipsync" ;;
    *)
        echo "Error: Unknown model '$MODEL'" >&2
        echo "Valid: sync, latent, creatify, veed" >&2
        exit 1 ;;
esac

PAYLOAD="{\"video_url\": \"$VIDEO_CLEAN\", \"audio_url\": \"$AUDIO_CLEAN\"}"

[ "$JSON_ONLY" = false ] && echo "Submitting lipsync (model: $MODEL, muapi)..." >&2

SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
    ERR=$(echo "$SUBMIT" | jq -r '.error // .detail // empty')
    [ -n "$ERR" ] && { echo "Error: $ERR" >&2; exit 1; }
fi

REQUEST_ID=$(extract_request_id "$SUBMIT")
if [ -z "$REQUEST_ID" ]; then echo "Error: No request_id" >&2; echo "$SUBMIT" >&2; exit 1; fi
[ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2

if [ "$ASYNC" = true ]; then
    [ "$JSON_ONLY" = false ] && echo "Lipsync takes 30-120s. Check: bash check-result.sh --id \"$REQUEST_ID\"" >&2
    echo "$SUBMIT"; exit 0
fi

[ "$JSON_ONLY" = false ] && echo "Processing lipsync (30-120s)..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "video")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Lipsync complete! Video URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Lipsync failed" >&2
    echo "$RESULT" >&2; exit 1
fi
