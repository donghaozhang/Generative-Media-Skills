#!/bin/bash
# Image Enhancement — one-click operations (MUAPI + FAL)
# Usage: ./enhance-image.sh --op upscale --image-url URL [--provider fal|muapi]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

OP=""
IMAGE_URL=""
IMAGE_FILE=""
FACE_URL=""
FACE_FILE=""
MASK_URL=""
MASK_FILE=""
PROMPT=""
PROVIDER=""
ASYNC=false
JSON_ONLY=false
MAX_WAIT=300
POLL_INTERVAL=3

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --op) OP="$2"; shift 2 ;;
        --image-url) IMAGE_URL="$2"; shift 2 ;;
        --file) IMAGE_FILE="$2"; shift 2 ;;
        --face-url) FACE_URL="$2"; shift 2 ;;
        --face-file) FACE_FILE="$2"; shift 2 ;;
        --mask-url) MASK_URL="$2"; shift 2 ;;
        --mask-file) MASK_FILE="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Image Enhancement (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./enhance-image.sh --op OPERATION --image-url URL [--provider fal|muapi]" >&2
            echo "" >&2
            echo "Operations (--op):" >&2
            echo "  upscale          Upscale image (FAL + MUAPI)" >&2
            echo "  background-remove Remove background (FAL + MUAPI)" >&2
            echo "  face-swap        Swap face (MUAPI only, requires --face-url)" >&2
            echo "  skin-enhance     Smooth skin (MUAPI only)" >&2
            echo "  colorize         Colorize B&W (MUAPI only)" >&2
            echo "  ghibli           Ghibli style (MUAPI only)" >&2
            echo "  anime            Anime style (MUAPI only)" >&2
            echo "  extend           Outpaint image (MUAPI only)" >&2
            echo "  product-shot     Product background (MUAPI only)" >&2
            echo "  product-photo    Product photography (MUAPI only)" >&2
            echo "  object-erase     Erase object (MUAPI only, requires --mask-url)" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
if [ -z "$OP" ]; then echo "Error: --op is required" >&2; exit 1; fi

CURRENT_PROVIDER=$(detect_provider)

# Check MUAPI-only operations
MUAPI_ONLY_OPS="face-swap skin-enhance colorize ghibli anime extend product-shot product-photo object-erase"
for op in $MUAPI_ONLY_OPS; do
    if [ "$OP" = "$op" ] && [ "$CURRENT_PROVIDER" = "fal" ]; then
        echo "Error: Operation '$OP' is MUAPI-only. Set MUAPI_KEY or use --provider muapi." >&2
        exit 1
    fi
done

# Auto-upload local files
if [ -n "$IMAGE_FILE" ]; then IMAGE_URL=$(upload_file "$IMAGE_FILE" "$JSON_ONLY"); fi
if [ -n "$FACE_FILE" ]; then FACE_URL=$(upload_file "$FACE_FILE" "$JSON_ONLY"); fi
if [ -n "$MASK_FILE" ]; then MASK_URL=$(upload_file "$MASK_FILE" "$JSON_ONLY"); fi

if [ -z "$IMAGE_URL" ]; then echo "Error: --image-url or --file is required" >&2; exit 1; fi
IMAGE_URL_CLEAN=$(echo "$IMAGE_URL" | tr -d '"')

PROMPT_JSON=$(echo "${PROMPT:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    # FAL operations
    case $OP in
        upscale)
            ENDPOINT=$(resolve_endpoint "upscaler")
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        background-remove)
            ENDPOINT=$(resolve_endpoint "background-remove")
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        *)
            echo "Error: Operation '$OP' not available on FAL" >&2; exit 1 ;;
    esac
else
    # MUAPI operations
    case $OP in
        upscale)
            ENDPOINT="ai-image-upscale"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        background-remove)
            ENDPOINT="ai-background-remover"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        face-swap)
            if [ -z "$FACE_URL" ]; then echo "Error: --face-url is required for face-swap" >&2; exit 1; fi
            FACE_CLEAN=$(echo "$FACE_URL" | tr -d '"')
            ENDPOINT="ai-image-face-swap"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\", \"face_image_url\": \"$FACE_CLEAN\"}" ;;
        skin-enhance)
            ENDPOINT="ai-skin-enhancer"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        colorize)
            ENDPOINT="ai-color-photo"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        ghibli)
            ENDPOINT="ai-ghibli-style"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        anime)
            ENDPOINT="ai-anime-generator"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\", \"prompt\": $PROMPT_JSON}" ;;
        extend)
            ENDPOINT="ai-image-extension"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        product-shot)
            ENDPOINT="ai-product-shot"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\"}" ;;
        product-photo)
            ENDPOINT="ai-product-photography"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\", \"prompt\": $PROMPT_JSON}" ;;
        object-erase)
            if [ -z "$MASK_URL" ]; then echo "Error: --mask-url is required for object-erase" >&2; exit 1; fi
            MASK_CLEAN=$(echo "$MASK_URL" | tr -d '"')
            ENDPOINT="ai-object-eraser"
            PAYLOAD="{\"image_url\": \"$IMAGE_URL_CLEAN\", \"mask_url\": \"$MASK_CLEAN\"}" ;;
        *)
            echo "Error: Unknown operation '$OP'" >&2; exit 1 ;;
    esac
fi

[ "$JSON_ONLY" = false ] && echo "Submitting $OP to $ENDPOINT ($(detect_provider))..." >&2

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

[ "$JSON_ONLY" = false ] && echo "Processing..." >&2
RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "image")

if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
    [ "$JSON_ONLY" = false ] && echo "Done! Image URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Enhancement failed" >&2
    echo "$RESULT" >&2; exit 1
fi
