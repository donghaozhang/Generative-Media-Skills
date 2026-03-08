#!/bin/bash
# Check Prediction Result (MUAPI + FAL)
# Usage: ./check-result.sh --id REQUEST_ID [--provider fal|muapi] [--endpoint ENDPOINT] [--once]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

REQUEST_ID=""
PROVIDER=""
FAL_ENDPOINT=""
ONCE=false
JSON_ONLY=false
MAX_WAIT=600
POLL_INTERVAL=5

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --id) REQUEST_ID="$2"; shift 2 ;;
        --endpoint) FAL_ENDPOINT="$2"; shift 2 ;;
        --once) ONCE=true; shift ;;
        --timeout) MAX_WAIT="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Check Prediction Result (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage: ./check-result.sh --id REQUEST_ID [options]" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  --id ID         Request ID to check (required)" >&2
            echo "  --provider      fal or muapi (auto-detect if omitted)" >&2
            echo "  --endpoint EP   FAL endpoint (required for FAL polling)" >&2
            echo "  --once          Check once and return (no polling)" >&2
            echo "  --timeout N     Max wait seconds (default: 600)" >&2
            echo "  --json          Output raw JSON only" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider

if [ -z "$REQUEST_ID" ]; then
    echo "Error: --id is required" >&2
    exit 1
fi

CURRENT_PROVIDER=$(detect_provider)

# FAL requires endpoint for polling
if [ "$CURRENT_PROVIDER" = "fal" ] && [ -z "$FAL_ENDPOINT" ]; then
    echo "Error: --endpoint is required for FAL polling (e.g. --endpoint fal-ai/flux/dev)" >&2
    exit 1
fi

get_headers

# Single check mode
if [ "$ONCE" = true ]; then
    if [ "$CURRENT_PROVIDER" = "fal" ]; then
        RESULT=$(curl -s "${FAL_QUEUE_BASE}/${FAL_ENDPOINT}/requests/${REQUEST_ID}/status" "${HEADERS[@]}")
        STATUS=$(echo "$RESULT" | jq -r '.status // empty')
        [ "$JSON_ONLY" = false ] && echo "Status: $STATUS" >&2
        if [ "$STATUS" = "COMPLETED" ]; then
            RESULT=$(curl -s "${FAL_QUEUE_BASE}/${FAL_ENDPOINT}/requests/${REQUEST_ID}" "${HEADERS[@]}")
            URL=$(extract_output_url "$RESULT" "auto")
            [ -n "$URL" ] && [ "$JSON_ONLY" = false ] && echo "Result URL: $URL" >&2
        fi
    else
        RESULT=$(curl -s -X GET "${MUAPI_BASE}/predictions/${REQUEST_ID}/result" "${HEADERS[@]}")
        STATUS=$(echo "$RESULT" | jq -r '.status // empty')
        [ "$JSON_ONLY" = false ] && echo "Status: $STATUS" >&2
        if [ "$STATUS" = "completed" ]; then
            URL=$(extract_output_url "$RESULT" "auto")
            [ -n "$URL" ] && [ "$JSON_ONLY" = false ] && echo "Result URL: $URL" >&2
        fi
    fi
    echo "$RESULT"
    exit 0
fi

# Poll mode
[ "$JSON_ONLY" = false ] && echo "Polling result for $REQUEST_ID ($(detect_provider))..." >&2

if [ "$CURRENT_PROVIDER" = "fal" ]; then
    RESULT=$(poll_result "$REQUEST_ID" "$FAL_ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY")
else
    RESULT=$(poll_result "$REQUEST_ID" "" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY")
fi
POLL_STATUS=$?

URL=$(extract_output_url "$RESULT" "auto")

if [ $POLL_STATUS -eq 0 ]; then
    [ "$JSON_ONLY" = false ] && echo "Done!" >&2
    [ -n "$URL" ] && [ "$JSON_ONLY" = false ] && echo "Result URL: $URL" >&2
    echo "$RESULT"; exit 0
else
    echo "Error: Polling failed" >&2
    echo "$RESULT" >&2; exit 1
fi
