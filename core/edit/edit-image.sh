#!/bin/bash
# Image Editing — prompt-based (MUAPI + FAL)
# Usage: ./edit-image.sh --image-url URL --prompt "..." [--model MODEL] [--provider fal|muapi]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

IMAGE_URL=""
IMAGE_FILE=""
PROMPT=""
EFFECT=""
MODEL="flux-kontext-pro"
PROVIDER=""
ASPECT_RATIO="1:1"
NUM_IMAGES=1
ASYNC=false
JSON_ONLY=false
MAX_WAIT=300
POLL_INTERVAL=3

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --image-url) IMAGE_URL="$2"; shift 2 ;;
        --file) IMAGE_FILE="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --effect) EFFECT="$2"; shift 2 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --aspect-ratio) ASPECT_RATIO="$2"; shift 2 ;;
        --num-images) NUM_IMAGES="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Image Edit (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./edit-image.sh --image-url URL --prompt \"...\" [options]" >&2
            echo "" >&2
            echo "Models (--model):" >&2
            echo "  flux-kontext-dev, flux-kontext-pro (default), flux-kontext-max (FAL + MUAPI)" >&2
            echo "  gpt4o, gpt4o-edit, reve, seededit, midjourney (MUAPI only)" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --provider      fal or muapi (auto-detect if omitted)" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider

CURRENT_PROVIDER=$(detect_provider)

# Check MUAPI-only models
MUAPI_ONLY_MODELS="gpt4o gpt4o-edit reve midjourney midjourney-style midjourney-omni qwen"
for m in $MUAPI_ONLY_MODELS; do
    if [ "$MODEL" = "$m" ] && [ "$CURRENT_PROVIDER" = "fal" ]; then
        echo "Error: Model '$MODEL' is MUAPI-only. Set MUAPI_KEY or use --provider muapi." >&2
        exit 1
    fi
done

# Auto-upload local file
if [ -n "$IMAGE_FILE" ]; then
    IMAGE_URL=$(upload_file "$IMAGE_FILE" "$JSON_ONLY")
fi

if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url or --file is required" >&2; exit 1; fi
IMAGE_URL_CLEAN=$(echo "$IMAGE_URL" | tr -d '"')

PROMPT_JSON=$(echo "${PROMPT:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    ENDPOINT=$(resolve_endpoint "$MODEL")
    # FAL Kontext payload
    PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\""
    if [ "$NUM_IMAGES" -gt 1 ] 2>/dev/null; then
        PAYLOAD="$PAYLOAD, \"num_images\": $NUM_IMAGES"
    fi
    PAYLOAD="$PAYLOAD}"
else
    # MUAPI model-to-endpoint mapping
    case $MODEL in
        flux-kontext-dev)
            ENDPOINT="flux-kontext-dev-i2i"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"images_list\": [\"$IMAGE_URL_CLEAN\"], \"aspect_ratio\": \"$ASPECT_RATIO\", \"num_images\": $NUM_IMAGES}" ;;
        flux-kontext-pro)
            ENDPOINT="flux-kontext-pro-i2i"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"images_list\": [\"$IMAGE_URL_CLEAN\"], \"aspect_ratio\": \"$ASPECT_RATIO\", \"num_images\": $NUM_IMAGES}" ;;
        flux-kontext-max)
            ENDPOINT="flux-kontext-max-i2i"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"images_list\": [\"$IMAGE_URL_CLEAN\"], \"aspect_ratio\": \"$ASPECT_RATIO\", \"num_images\": $NUM_IMAGES}" ;;
        flux-kontext-effects)
            ENDPOINT="flux-kontext-effects"
            EFFECT_VAL="${EFFECT:-$PROMPT}"
            EFFECT_JSON=$(echo "$EFFECT_VAL" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\", \"effect\": $EFFECT_JSON}" ;;
        gpt4o)
            ENDPOINT="gpt4o-image-to-image"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        gpt4o-edit)
            ENDPOINT="gpt4o-edit"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        reve)
            ENDPOINT="reve-image-edit"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        seededit)
            ENDPOINT="bytedance-seededit-image"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        midjourney)
            ENDPOINT="midjourney-v7-image-to-image"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        midjourney-style)
            ENDPOINT="midjourney-v7-style-reference"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"style_reference_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        midjourney-omni)
            ENDPOINT="midjourney-v7-omni-reference"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"omni_reference_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        qwen)
            ENDPOINT="qwen-image-edit"
            PAYLOAD="{\"prompt\": $PROMPT_JSON, \"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        *)
            echo "Error: Unknown model '$MODEL'" >&2; exit 1 ;;
    esac
fi

[ "$JSON_ONLY" = false ] && echo "Submitting to $ENDPOINT ($(detect_provider))..." >&2

SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
    ERR=$(echo "$SUBMIT" | jq -r '.error // .detail // empty')
    [ -n "$ERR" ] && { echo "Error: $ERR" >&2; exit 1; }
fi

REQUEST_ID=$(extract_request_id "$SUBMIT")
if [ -z "$REQUEST_ID" ]; then echo "Error: No request_id" >&2; echo "$SUBMIT" >&2; exit 1; fi
[ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2

if [ "$ASYNC" = true ]; then
    [ "$JSON_ONLY" = false ] && echo "Check: bash check-result.sh --id \"$REQUEST_ID\" --provider $(detect_provider)" >&2
    echo "$SUBMIT"; exit 0
fi

[ "$JSON_ONLY" = false ] && echo "Waiting for completion..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "image")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Done! Image URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Editing failed" >&2
    echo "$RESULT" >&2; exit 1
fi
