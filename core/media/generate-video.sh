#!/bin/bash
# Text-to-Video Generation (MUAPI + FAL)
# Usage: ./generate-video.sh --prompt "..." [--model MODEL] [--provider fal|muapi] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

SCHEMA_FILE="$SCRIPT_DIR/../../schema_data.json"

# Defaults
PROMPT=""
MODEL="minimax-pro"
PROVIDER=""
ASPECT_RATIO="16:9"
DURATION=5
GENERATE_AUDIO=true
ASYNC=false
VIEW=false
JSON_ONLY=false
MAX_WAIT=600
POLL_INTERVAL=5
ACTION="generate"
REQUEST_ID=""

# Check for .env
if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --aspect-ratio) ASPECT_RATIO="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --no-audio) GENERATE_AUDIO=false; shift ;;
        --async) ASYNC=true; shift ;;
        --view) VIEW=true; shift ;;
        --status) ACTION="status"; REQUEST_ID="$2"; shift 2 ;;
        --result) ACTION="result"; REQUEST_ID="$2"; shift 2 ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Text-to-Video (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./generate-video.sh --prompt \"...\" [options]" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --prompt, -p    Text description (required)" >&2
            echo "  --model, -m     Model name (default: minimax-pro)" >&2
            echo "  --provider      fal or muapi (auto-detect if omitted)" >&2
            echo "  --aspect-ratio  16:9, 9:16, 1:1" >&2
            echo "  --duration      Length in seconds (3-15)" >&2
            echo "  --no-audio      Disable audio generation" >&2
            echo "  --async         Return request_id immediately" >&2
            echo "  --view          Download and open video (macOS only)" >&2
            echo "  --status ID     Check status of a request" >&2
            echo "  --json          Raw JSON output only" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider

CURRENT_PROVIDER=$(detect_provider)

# Handle status/result actions
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

if [ -z "$PROMPT" ]; then echo "Error: --prompt is required" >&2; exit 1; fi

ENDPOINT=$(resolve_endpoint "$MODEL")

# Build Payload
PROMPT_JSON=$(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    PAYLOAD="{\"prompt\": $PROMPT_JSON"
    PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"$ASPECT_RATIO\""
    PAYLOAD="$PAYLOAD, \"duration\": $DURATION"
    PAYLOAD="$PAYLOAD}"
else
    # MUAPI — schema-driven
    if [ -f "$SCHEMA_FILE" ]; then
        MODEL_DATA=$(jq -r ".[] | select(.name == \"$MODEL\")" "$SCHEMA_FILE")
        if [ -n "$MODEL_DATA" ]; then
            ENDPOINT=$(echo "$MODEL_DATA" | jq -r '.input_schema.schemas.input_data.endpoint_url')
            PARAMS=$(echo "$MODEL_DATA" | jq -r '.input_schema.schemas.input_data.properties | keys[]')
        fi
    fi

    PAYLOAD="{\"prompt\": $PROMPT_JSON"
    if [ -n "$PARAMS" ]; then
        if echo "$PARAMS" | grep -w "aspect_ratio" >/dev/null; then PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"$ASPECT_RATIO\""; fi
        if echo "$PARAMS" | grep -w "duration" >/dev/null; then PAYLOAD="$PAYLOAD, \"duration\": $DURATION"; fi
        if echo "$PARAMS" | grep -w "generate_audio" >/dev/null; then PAYLOAD="$PAYLOAD, \"generate_audio\": $GENERATE_AUDIO"; fi
    else
        PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"$ASPECT_RATIO\", \"duration\": $DURATION"
    fi
    PAYLOAD="$PAYLOAD}"
fi

# --- EXECUTION ---
[ "$JSON_ONLY" = false ] && echo "Submitting to $ENDPOINT ($(detect_provider))..." >&2

SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
    ERR=$(echo "$SUBMIT" | jq -r '.error // .detail // empty')
    [ -n "$ERR" ] && { echo "Error: $ERR" >&2; exit 1; }
fi

REQUEST_ID=$(extract_request_id "$SUBMIT")
if [ "$ASYNC" = true ]; then echo "$SUBMIT"; exit 0; fi

# Polling
[ "$JSON_ONLY" = false ] && echo "Waiting for completion (Request ID: $REQUEST_ID)..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "video")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Video generation complete!" >&2
    [ "$JSON_ONLY" = false ] && echo "Video URL: $URL" >&2
    if [ "$VIEW" = true ]; then
        download_and_view "$URL" "mp4" "$JSON_ONLY"
    fi
    echo "$RESULT"; exit 0
else
    echo "Error: Generation failed" >&2
    echo "$RESULT" >&2; exit 1
fi
