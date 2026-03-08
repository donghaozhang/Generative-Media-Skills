#!/bin/bash
# Image-to-Video Generation (MUAPI + FAL)
# Usage: ./image-to-video.sh --image-url URL --prompt "..." [--model MODEL] [--provider fal|muapi] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

# Defaults
IMAGE_URL=""
IMAGE_FILE=""
LAST_IMAGE_URL=""
LAST_IMAGE_FILE=""
PROMPT=""
MODEL="kling-pro"
PROVIDER=""
ASPECT_RATIO="16:9"
DURATION=5
ASYNC=false
JSON_ONLY=false
MAX_WAIT=600
POLL_INTERVAL=5
ACTION="generate"
REQUEST_ID=""

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --image-url) IMAGE_URL="$2"; shift 2 ;;
        --file|--image) IMAGE_FILE="$2"; shift 2 ;;
        --last-image-url) LAST_IMAGE_URL="$2"; shift 2 ;;
        --last-image-file) LAST_IMAGE_FILE="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --aspect-ratio) ASPECT_RATIO="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --status) ACTION="status"; REQUEST_ID="$2"; shift 2 ;;
        --result) ACTION="result"; REQUEST_ID="$2"; shift 2 ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Image-to-Video (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./image-to-video.sh --image-url URL --prompt \"...\" [options]" >&2
            echo "" >&2
            echo "Models (--model):" >&2
            echo "  kling-std, kling-pro (default), kling-master" >&2
            echo "  veo3, veo3-fast, wan2, minimax-std, minimax-pro" >&2
            echo "  seedance-pro, seedance-lite (MUAPI only)" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --provider      fal or muapi (auto-detect if omitted)" >&2
            echo "  --image-url URL         Input image URL" >&2
            echo "  --file PATH             Local file (auto-uploads)" >&2
            echo "  --last-image-url URL    End frame URL (start+end interpolation)" >&2
            echo "  --last-image-file PATH  Local end frame (auto-uploads)" >&2
            echo "  --prompt TEXT           Motion description" >&2
            echo "  --aspect-ratio          16:9, 9:16, 1:1 (default: 16:9)" >&2
            echo "  --duration              5 or 10 seconds (default: 5)" >&2
            echo "  --async                 Return request_id immediately" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider

CURRENT_PROVIDER=$(detect_provider)

# Status/result check
if [ "$ACTION" = "status" ] || [ "$ACTION" = "result" ]; then
    if [ -z "$REQUEST_ID" ]; then echo "Error: Request ID required" >&2; exit 1; fi
    get_headers
    if [ "$CURRENT_PROVIDER" = "fal" ]; then
        ENDPOINT=$(resolve_endpoint "$MODEL")
        RESULT=$(curl -s "${FAL_QUEUE_BASE}/${ENDPOINT}/requests/${REQUEST_ID}/status" "${HEADERS[@]}")
    else
        RESULT=$(curl -s -X GET "${MUAPI_BASE}/predictions/${REQUEST_ID}/result" "${HEADERS[@]}")
    fi
    echo "$RESULT"; exit 0
fi

# Auto-upload local files
if [ -n "$IMAGE_FILE" ]; then IMAGE_URL=$(upload_file "$IMAGE_FILE" "$JSON_ONLY"); fi
if [ -n "$LAST_IMAGE_FILE" ]; then LAST_IMAGE_URL=$(upload_file "$LAST_IMAGE_FILE" "$JSON_ONLY"); fi

if [ -z "$IMAGE_URL" ]; then
    echo "Error: --image-url or --file is required" >&2
    exit 1
fi

IMAGE_URL_CLEAN=$(echo "$IMAGE_URL" | tr -d '"')

# Resolve endpoint
ENDPOINT=$(resolve_endpoint "$MODEL")

# Build payload
PROMPT_JSON=$(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    # FAL payload
    PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\""
    PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"$ASPECT_RATIO\", \"duration\": $DURATION"
    if [ -n "$LAST_IMAGE_URL" ]; then
        LAST_JSON=$(echo "$LAST_IMAGE_URL" | tr -d '"')
        PAYLOAD="$PAYLOAD, \"last_image_url\": \"$LAST_JSON\""
    fi
    PAYLOAD="$PAYLOAD}"
else
    # MUAPI payload — model-specific endpoint mapping
    case $MODEL in
        kling-std)     ENDPOINT="kling-v2.1-standard-i2v" ;;
        kling-pro)     ENDPOINT="kling-v2.1-pro-i2v" ;;
        kling-master)  ENDPOINT="kling-v2.1-master-i2v" ;;
        veo3)          ENDPOINT="veo3-image-to-video" ;;
        veo3-fast)     ENDPOINT="veo3-fast-image-to-video" ;;
        wan2)          ENDPOINT="wan2.1-image-to-video" ;;
        wan22)         ENDPOINT="wan2.2-image-to-video" ;;
        seedance-pro)  ENDPOINT="seedance-pro-i2v" ;;
        seedance-lite) ENDPOINT="seedance-lite-i2v" ;;
        hunyuan)       ENDPOINT="hunyuan-image-to-video" ;;
        runway)        ENDPOINT="runway-image-to-video" ;;
        pixverse)      ENDPOINT="pixverse-v4.5-i2v" ;;
        vidu)          ENDPOINT="vidu-v2.0-i2v" ;;
        midjourney)    ENDPOINT="midjourney-v7-image-to-video" ;;
        minimax-std)   ENDPOINT="minimax-hailuo-02-standard-i2v" ;;
        minimax-pro)   ENDPOINT="minimax-hailuo-02-pro-i2v" ;;
    esac

    if [ -n "$LAST_IMAGE_URL" ]; then
        LAST_JSON=$(echo "$LAST_IMAGE_URL" | tr -d '"')
        PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\", \"last_image\": \"$LAST_JSON\", \"aspect_ratio\": \"$ASPECT_RATIO\", \"duration\": $DURATION}"
    elif [[ "$ENDPOINT" == *"veo3"* ]]; then
        PAYLOAD="{\"prompt\": $PROMPT_JSON, \"images_list\": [\"$IMAGE_URL_CLEAN\"], \"aspect_ratio\": \"$ASPECT_RATIO\"}"
    else
        PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\", \"aspect_ratio\": \"$ASPECT_RATIO\", \"duration\": $DURATION}"
    fi
fi

[ "$JSON_ONLY" = false ] && echo "Submitting to $ENDPOINT ($(detect_provider))..." >&2

SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
    ERR=$(echo "$SUBMIT" | jq -r '.error // .detail // empty')
    [ -n "$ERR" ] && { echo "Error: $ERR" >&2; exit 1; }
fi

REQUEST_ID=$(extract_request_id "$SUBMIT")

if [ -z "$REQUEST_ID" ]; then
    echo "Error: No request_id in response" >&2
    echo "$SUBMIT" >&2; exit 1
fi

[ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2

if [ "$ASYNC" = true ]; then
    [ "$JSON_ONLY" = false ] && echo "Check: bash check-result.sh --id \"$REQUEST_ID\" --provider $(detect_provider)" >&2
    echo "$SUBMIT"; exit 0
fi

[ "$JSON_ONLY" = false ] && echo "Waiting for completion..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "video")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Video generation complete!" >&2
    [ "$JSON_ONLY" = false ] && echo "Video URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Generation failed" >&2
    echo "$RESULT" >&2; exit 1
fi
