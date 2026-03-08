#!/bin/bash
# Text-to-Image Generation (MUAPI + FAL)
# Usage: ./generate-image.sh --prompt "..." [--model MODEL] [--provider fal|muapi] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

SCHEMA_FILE="$SCRIPT_DIR/../../schema_data.json"

# Defaults
PROMPT=""
MODEL="flux-dev"
PROVIDER=""
WIDTH=1024
HEIGHT=1024
ASPECT_RATIO=""
RESOLUTION="1k"
NUM_IMAGES=1
ASYNC=false
VIEW=false
JSON_ONLY=false
MAX_WAIT=300
POLL_INTERVAL=3

# Check for .env and setup
if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --width) WIDTH="$2"; shift 2 ;;
        --height) HEIGHT="$2"; shift 2 ;;
        --aspect-ratio) ASPECT_RATIO="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --num-images) NUM_IMAGES="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --view) VIEW=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Text-to-Image (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./generate-image.sh --prompt \"...\" [options]" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --prompt, -p    Text description (required)" >&2
            echo "  --model, -m     Model name (default: flux-dev)" >&2
            echo "  --provider      fal or muapi (auto-detect if omitted)" >&2
            echo "  --aspect-ratio  1:1, 16:9, 9:16, 4:3, 3:4, 21:9" >&2
            echo "  --resolution    1k, 2k, 4k (for supported models)" >&2
            echo "  --width/--height Manual pixel override" >&2
            echo "  --async         Return request_id immediately" >&2
            echo "  --view          Download and open image (macOS only)" >&2
            echo "  --json          Raw JSON output only" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
if [ -z "$PROMPT" ]; then echo "Error: --prompt is required" >&2; exit 1; fi

CURRENT_PROVIDER=$(detect_provider)
ENDPOINT=$(resolve_endpoint "$MODEL")

# Build Payload
PROMPT_JSON=$(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    # FAL payload — simpler structure
    PAYLOAD="{\"prompt\": $PROMPT_JSON"
    if [ -n "$ASPECT_RATIO" ]; then
        PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"$ASPECT_RATIO\""
    fi
    if [ "$NUM_IMAGES" -gt 1 ] 2>/dev/null; then
        PAYLOAD="$PAYLOAD, \"num_images\": $NUM_IMAGES"
    fi
    PAYLOAD="$PAYLOAD}"
else
    # MUAPI payload — schema-driven
    if [ ! -f "$SCHEMA_FILE" ]; then echo "Error: schema_data.json not found at $SCHEMA_FILE" >&2; exit 1; fi

    MODEL_DATA=$(jq -r ".[] | select(.name == \"$MODEL\")" "$SCHEMA_FILE")
    if [ -z "$MODEL_DATA" ]; then
        echo "Error: Model '$MODEL' not found in schema_data.json" >&2
        echo "Available models: $(jq -r '.[] | .name' "$SCHEMA_FILE" | head -10)..." >&2
        exit 1
    fi

    ENDPOINT=$(echo "$MODEL_DATA" | jq -r '.input_schema.schemas.input_data.endpoint_url')
    PARAMS=$(echo "$MODEL_DATA" | jq -r '.input_schema.schemas.input_data.properties | keys[]')

    # Auto-map aspect ratio to width/height if model doesn't support aspect_ratio field
    SUPPORTS_AR=$(echo "$PARAMS" | grep -w "aspect_ratio" || true)
    if [ -n "$ASPECT_RATIO" ] && [ -z "$SUPPORTS_AR" ]; then
        case $ASPECT_RATIO in
            "1:1")   WIDTH=1024; HEIGHT=1024 ;;
            "16:9")  WIDTH=1344; HEIGHT=768 ;;
            "9:16")  WIDTH=768;  HEIGHT=1344 ;;
            "4:3")   WIDTH=1152; HEIGHT=896 ;;
            "3:4")   WIDTH=896;  HEIGHT=1152 ;;
            "21:9")  WIDTH=1536; HEIGHT=640 ;;
        esac
    fi

    PAYLOAD="{\"prompt\": $PROMPT_JSON"
    if echo "$PARAMS" | grep -w "num_images" >/dev/null; then PAYLOAD="$PAYLOAD, \"num_images\": $NUM_IMAGES"; fi
    if echo "$PARAMS" | grep -w "width" >/dev/null && [ -z "$SUPPORTS_AR" ]; then PAYLOAD="$PAYLOAD, \"width\": $WIDTH, \"height\": $HEIGHT"; fi
    if [ -n "$SUPPORTS_AR" ]; then PAYLOAD="$PAYLOAD, \"aspect_ratio\": \"${ASPECT_RATIO:-1:1}\""; fi
    if echo "$PARAMS" | grep -w "resolution" >/dev/null; then PAYLOAD="$PAYLOAD, \"resolution\": \"$RESOLUTION\""; fi
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
[ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2

if [ "$ASYNC" = true ]; then echo "$SUBMIT"; exit 0; fi

# Polling
[ "$JSON_ONLY" = false ] && echo "Waiting for completion..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "image")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Success! URL: $URL" >&2
    [ "$VIEW" = true ] && download_and_view "$URL" "jpg" "$JSON_ONLY"
    echo "$RESULT"; exit 0
else
    echo "Error: Generation failed" >&2
    echo "$RESULT" >&2; exit 1
fi
