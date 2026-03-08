#!/bin/bash
# Expert Skill: Seedance 2 Cinema Expert (MUAPI only)
# Translates creative intent into 'Director-Level' technical directives for Seedance 2.0.
# Modes: t2v (text-to-video), i2v (image-to-video), extend (video extension)
# Note: Seedance 2.0 is MUAPI-exclusive.

SUBJECT=""
INTENT="cinematic"
ASPECT="16:9"
DURATION=5
QUALITY="basic"
AUDIO_FLAG=""
VIEW=false
MODE="t2v"
IMAGE_URLS=()
IMAGE_FILES=()
EXTEND_REQUEST_ID=""
PROVIDER=""
ASYNC=false
JSON_ONLY=false
MAX_WAIT=600
POLL_INTERVAL=5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../core/lib/provider.sh"

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --subject) SUBJECT="$2"; shift 2 ;;
        --intent) INTENT="$2"; shift 2 ;;
        --aspect) ASPECT="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --quality) QUALITY="$2"; shift 2 ;;
        --no-audio) AUDIO_FLAG="--no-audio"; shift ;;
        --view) VIEW=true; shift ;;
        --image|--image-url) IMAGE_URLS+=("$2"); shift 2 ;;
        --file|--image-file) IMAGE_FILES+=("$2"); shift 2 ;;
        --request-id) EXTEND_REQUEST_ID="$2"; shift 2 ;;
        --async) ASYNC=true; shift ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "Seedance 2 Cinema Expert (MUAPI only)"
            echo "Usage: bash generate-seedance.sh [--mode t2v|i2v|extend] [options]"
            echo ""
            echo "Note: Seedance 2.0 requires MUAPI. Not available on FAL."
            echo ""
            echo "Modes:"
            echo "  t2v     Text-to-Video (default)"
            echo "  i2v     Image-to-Video"
            echo "  extend  Extend an existing video"
            echo ""
            echo "Common Options:"
            echo "  --subject     Scene description (required for t2v)"
            echo "  --intent      reveal|tense|epic|narrative (default: cinematic)"
            echo "  --aspect      16:9|9:16|4:3|3:4 (default: 16:9)"
            echo "  --duration    5|10|15 in seconds (default: 5)"
            echo "  --quality     basic|high (default: basic)"
            echo "  --async       Return request_id immediately"
            echo "  --json        Raw JSON output only"
            echo "  --view        Download and open the video (macOS only)"
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider
require_muapi "Seedance 2.0"

# --- Director's Cinematography Grammar ---
case $INTENT in
    "reveal")
        MOVEMENT="Slow crane up and tilt down, wide establishing shot."
        LIGHTING="Volumetric god rays, golden hour atmosphere, warm bloom."
        OPTICS="Deep focus, anamorphic widescreen, ultra-high clarity."
        ;;
    "tense")
        MOVEMENT="Handheld jittery movement, dutch angle close-up, unstable framing."
        LIGHTING="Low key, harsh shadows, flickering magenta neon, split lighting."
        OPTICS="Shallow depth of field, anamorphic lens flare, slight motion blur."
        ;;
    "epic")
        MOVEMENT="Dolly in with circular orbit, low hero angle, sweeping arc."
        LIGHTING="Dramatic rim lighting, high contrast cinematic grade, specular highlights."
        OPTICS="Anamorphic 35mm, sharp focus on subject, chromatic aberration edges."
        ;;
    "narrative")
        MOVEMENT="Smooth tracking shot following subject, natural Steadicam motion."
        LIGHTING="Natural soft light, blue hour tones, practical light sources."
        OPTICS="Standard 50mm, realistic bokeh, minimal distortion."
        ;;
    *)
        MOVEMENT="Smooth cinematic pan, balanced stable framing."
        LIGHTING="Natural studio lighting, balanced highlights and shadows."
        OPTICS="Standard cinematic lens, high-fidelity optics."
        ;;
esac

# --- Validate API key ---
get_headers

# ============================================================
# MODE: t2v
# ============================================================
if [ "$MODE" = "t2v" ]; then
    if [ -z "$SUBJECT" ]; then
        echo "Error: --subject is required for t2v mode." >&2; exit 1
    fi

    DIRECTOR_PROMPT="[SCENE] $SUBJECT. [LIGHTING] $LIGHTING [ACTION] Fluid continuous motion. [CAMERA] $MOVEMENT [STYLE] $OPTICS High-fidelity production grade, 24fps. Maintain high character consistency, zero flicker."

    CORE_SCRIPT="$SCRIPT_DIR/../../../../core/media/generate-video.sh"
    if [ ! -f "$CORE_SCRIPT" ]; then
        echo "Error: Core script not found at $CORE_SCRIPT" >&2; exit 1
    fi

    VIEW_FLAG=""
    [ "$VIEW" = true ] && VIEW_FLAG="--view"
    ASYNC_FLAG=""
    [ "$ASYNC" = true ] && ASYNC_FLAG="--async"
    JSON_FLAG=""
    [ "$JSON_ONLY" = true ] && JSON_FLAG="--json"

    bash "$CORE_SCRIPT" \
        --prompt "$DIRECTOR_PROMPT" \
        --model "seedance-v2.0-t2v" \
        --aspect-ratio "$ASPECT" \
        --duration "$DURATION" \
        --provider muapi \
        $AUDIO_FLAG $VIEW_FLAG $ASYNC_FLAG $JSON_FLAG

# ============================================================
# MODE: i2v
# ============================================================
elif [ "$MODE" = "i2v" ]; then
    for FPATH in "${IMAGE_FILES[@]}"; do
        URL=$(upload_file "$FPATH" "$JSON_ONLY")
        IMAGE_URLS+=("$URL")
    done

    if [ ${#IMAGE_URLS[@]} -eq 0 ]; then
        echo "Error: --image URL or --file PATH is required for i2v mode." >&2; exit 1
    fi
    if [ ${#IMAGE_URLS[@]} -gt 9 ]; then
        echo "Error: Maximum 9 images allowed." >&2; exit 1
    fi

    if [ -n "$SUBJECT" ]; then
        DIRECTOR_PROMPT="[ACTION] $SUBJECT. [CAMERA] $MOVEMENT [STYLE] $OPTICS Fluid continuous motion. Maintain high character consistency, zero flicker."
    else
        DIRECTOR_PROMPT="[CAMERA] $MOVEMENT [STYLE] $OPTICS Fluid continuous motion. Animate the provided image with cinematic realism."
    fi

    IMAGES_JSON="["
    for i in "${!IMAGE_URLS[@]}"; do
        [ $i -gt 0 ] && IMAGES_JSON="${IMAGES_JSON},"
        IMAGES_JSON="${IMAGES_JSON}\"${IMAGE_URLS[$i]}\""
    done
    IMAGES_JSON="${IMAGES_JSON}]"

    PROMPT_JSON=$(echo "$DIRECTOR_PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')
    PAYLOAD="{\"prompt\": $PROMPT_JSON, \"images_list\": $IMAGES_JSON, \"aspect_ratio\": \"$ASPECT\", \"duration\": $DURATION, \"quality\": \"$QUALITY\"}"

    ENDPOINT="seedance-v2.0-i2v"
    [ "$JSON_ONLY" = false ] && echo "Submitting to $ENDPOINT (${#IMAGE_URLS[@]} image(s), muapi)..." >&2
    SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

    if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
        ERR=$(echo "$SUBMIT" | jq -r '.error // .detail')
        echo "Error: $ERR" >&2; exit 1
    fi

    REQUEST_ID=$(extract_request_id "$SUBMIT")
    if [ -z "$REQUEST_ID" ] || [ "$REQUEST_ID" = "null" ]; then
        echo "Error: No request_id in response" >&2; echo "$SUBMIT" >&2; exit 1
    fi

    [ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2
    if [ "$ASYNC" = true ]; then echo "$SUBMIT"; exit 0; fi

    [ "$JSON_ONLY" = false ] && echo "Waiting for completion..." >&2
    RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
    POLL_STATUS=$?

    URL=$(extract_output_url "$RESULT" "video")
    if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
        [ "$JSON_ONLY" = false ] && echo "Success! URL: $URL" >&2
        if [ "$VIEW" = true ]; then
            download_and_view "$URL" "mp4" "$JSON_ONLY"
        fi
        echo "$RESULT"; exit 0
    else
        echo "Error: Generation failed" >&2
        echo "$RESULT" >&2; exit 1
    fi

# ============================================================
# MODE: extend
# ============================================================
elif [ "$MODE" = "extend" ]; then
    if [ -z "$EXTEND_REQUEST_ID" ]; then
        echo "Error: --request-id is required for extend mode." >&2; exit 1
    fi

    if [ -n "$SUBJECT" ]; then
        EXT_PROMPT="[CONTINUATION] $SUBJECT. [CAMERA] $MOVEMENT [STYLE] $OPTICS Seamless continuation of previous scene."
        PROMPT_JSON=$(echo "$EXT_PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')
        PAYLOAD="{\"request_id\": \"$EXTEND_REQUEST_ID\", \"prompt\": $PROMPT_JSON, \"duration\": $DURATION, \"quality\": \"$QUALITY\"}"
    else
        PAYLOAD="{\"request_id\": \"$EXTEND_REQUEST_ID\", \"duration\": $DURATION, \"quality\": \"$QUALITY\"}"
    fi

    ENDPOINT="seedance-v2.0-extend"
    [ "$JSON_ONLY" = false ] && echo "Submitting extend for request: $EXTEND_REQUEST_ID (muapi)..." >&2
    SUBMIT=$(submit_request "$ENDPOINT" "$PAYLOAD")

    if echo "$SUBMIT" | jq -e '.error // .detail' >/dev/null 2>&1; then
        ERR=$(echo "$SUBMIT" | jq -r '.error // .detail')
        echo "Error: $ERR" >&2; exit 1
    fi

    REQUEST_ID=$(extract_request_id "$SUBMIT")
    if [ -z "$REQUEST_ID" ] || [ "$REQUEST_ID" = "null" ]; then
        echo "Error: No request_id in response" >&2; echo "$SUBMIT" >&2; exit 1
    fi

    [ "$JSON_ONLY" = false ] && echo "Request ID: $REQUEST_ID" >&2
    if [ "$ASYNC" = true ]; then echo "$SUBMIT"; exit 0; fi

    [ "$JSON_ONLY" = false ] && echo "Waiting for completion..." >&2
    RESULT=$(poll_result "$REQUEST_ID" "$ENDPOINT" "$MAX_WAIT" "$POLL_INTERVAL" "$JSON_ONLY" "$SUBMIT")
    POLL_STATUS=$?

    URL=$(extract_output_url "$RESULT" "video")
    if [ $POLL_STATUS -eq 0 ] && [ -n "$URL" ]; then
        [ "$JSON_ONLY" = false ] && echo "Success! URL: $URL" >&2
        if [ "$VIEW" = true ]; then
            download_and_view "$URL" "mp4" "$JSON_ONLY"
        fi
        echo "$RESULT"; exit 0
    else
        echo "Error: Extension failed" >&2
        echo "$RESULT" >&2; exit 1
    fi

else
    echo "Error: Unknown mode '$MODE'. Use t2v, i2v, or extend." >&2; exit 1
fi
