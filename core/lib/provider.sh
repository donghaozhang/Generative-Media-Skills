#!/bin/bash
# Provider abstraction for MUAPI and FAL.ai
# Source this file in any core script: source "$(dirname "$0")/../lib/provider.sh"

# --- Constants ---
MUAPI_BASE="https://api.muapi.ai/api/v1"
FAL_QUEUE_BASE="https://queue.fal.run"
FAL_STORAGE_INITIATE="https://rest.alpha.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"

# --- Provider Detection ---
# Priority: --provider flag > auto-detect (whichever key is set)
detect_provider() {
    if [ -n "$PROVIDER" ]; then echo "$PROVIDER"; return; fi
    if [ -n "$FAL_KEY" ] && [ -n "$MUAPI_KEY" ]; then echo "fal"; return; fi
    if [ -n "$FAL_KEY" ]; then echo "fal"; return; fi
    if [ -n "$MUAPI_KEY" ]; then echo "muapi"; return; fi
    echo "none"
}

# --- Auth Headers (as array for curl) ---
get_headers() {
    local provider=$(detect_provider)
    case $provider in
        fal)   HEADERS=(-H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json") ;;
        muapi) HEADERS=(-H "x-api-key: $MUAPI_KEY" -H "Content-Type: application/json") ;;
    esac
}

# --- Endpoint Resolution ---
# Maps a model name to the correct provider endpoint
resolve_endpoint() {
    local model="$1"
    local provider=$(detect_provider)
    local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    case $provider in
        fal)
            local fal_endpoint=$(jq -r ".[\"$model\"] // empty" "$lib_dir/fal-endpoints.json" 2>/dev/null)
            if [ -n "$fal_endpoint" ]; then
                echo "$fal_endpoint"
            else
                echo "fal-ai/$model"
            fi
            ;;
        muapi)
            local schema="$lib_dir/../../schema_data.json"
            if [ -f "$schema" ]; then
                local ep=$(jq -r ".[] | select(.name == \"$model\") | .input_schema.schemas.input_data.endpoint_url" "$schema" 2>/dev/null)
                if [ -n "$ep" ] && [ "$ep" != "null" ]; then
                    echo "$ep"
                else
                    echo "$model"
                fi
            else
                echo "$model"
            fi
            ;;
    esac
}

# --- Submit Request ---
submit_request() {
    local endpoint="$1"
    local payload="$2"
    local provider=$(detect_provider)

    get_headers

    case $provider in
        fal)
            curl -s -X POST "${FAL_QUEUE_BASE}/${endpoint}" "${HEADERS[@]}" -d "$payload"
            ;;
        muapi)
            curl -s -X POST "${MUAPI_BASE}/${endpoint}" "${HEADERS[@]}" -d "$payload"
            ;;
    esac
}

# --- Extract Request ID ---
extract_request_id() {
    local response="$1"
    echo "$response" | jq -r '.request_id // empty'
}

# --- Poll for Result ---
# Args: request_id, endpoint, max_wait, poll_interval, json_only, submit_response_json
poll_result() {
    local request_id="$1"
    local endpoint="$2"
    local max_wait="${3:-600}"
    local poll_interval="${4:-5}"
    local json_only="${5:-false}"
    local submit_response="${6:-}"
    local provider=$(detect_provider)

    get_headers

    # FAL: use status_url/response_url from submit response (paths differ from endpoint)
    local fal_status_url=""
    local fal_response_url=""
    if [ "$provider" = "fal" ] && [ -n "$submit_response" ]; then
        fal_status_url=$(echo "$submit_response" | jq -r '.status_url // empty' 2>/dev/null)
        fal_response_url=$(echo "$submit_response" | jq -r '.response_url // empty' 2>/dev/null)
    fi
    # Fallback to constructed URLs if not available
    if [ "$provider" = "fal" ] && [ -z "$fal_status_url" ]; then
        fal_status_url="${FAL_QUEUE_BASE}/${endpoint}/requests/${request_id}/status"
        fal_response_url="${FAL_QUEUE_BASE}/${endpoint}/requests/${request_id}"
    fi

    local elapsed=0
    local last_status=""

    while [ $elapsed -lt $max_wait ]; do
        sleep $poll_interval
        elapsed=$((elapsed + poll_interval))

        case $provider in
            fal)
                local status_json=$(curl -s "$fal_status_url" "${HEADERS[@]}")
                local status=$(echo "$status_json" | jq -r '.status // empty')

                if [ "$status" = "COMPLETED" ]; then
                    local result=$(curl -s "$fal_response_url" "${HEADERS[@]}")
                    echo "$result"
                    return 0
                elif [ "$status" = "FAILED" ]; then
                    local err=$(echo "$status_json" | jq -r '.error // "Generation failed"')
                    echo "{\"status\":\"failed\",\"error\":\"$err\"}"
                    return 1
                fi

                if [ "$status" != "$last_status" ] && [ "$json_only" = "false" ]; then
                    echo "Status: $status (${elapsed}s)" >&2
                    last_status="$status"
                fi
                ;;
            muapi)
                local result=$(curl -s -X GET "${MUAPI_BASE}/predictions/${request_id}/result" "${HEADERS[@]}")
                local status=$(echo "$result" | jq -r '.status // empty')

                if [ "$status" = "completed" ]; then
                    echo "$result"
                    return 0
                elif [ "$status" = "failed" ]; then
                    echo "$result"
                    return 1
                fi

                if [ "$status" != "$last_status" ] && [ "$json_only" = "false" ]; then
                    echo "Status: $status (${elapsed}s)" >&2
                    last_status="$status"
                fi
                ;;
        esac
    done

    echo "{\"status\":\"timeout\",\"error\":\"Timeout after ${max_wait}s\",\"request_id\":\"$request_id\"}"
    return 1
}

# --- Extract Output URL from Result ---
extract_output_url() {
    local result="$1"
    local media_type="${2:-auto}"
    local provider=$(detect_provider)

    case $provider in
        fal)
            local url=""
            if [ "$media_type" = "image" ] || [ "$media_type" = "auto" ]; then
                url=$(echo "$result" | jq -r '.images[0].url // empty' 2>/dev/null)
            fi
            if [ -z "$url" ] && ([ "$media_type" = "video" ] || [ "$media_type" = "auto" ]); then
                url=$(echo "$result" | jq -r '.video.url // empty' 2>/dev/null)
            fi
            if [ -z "$url" ] && ([ "$media_type" = "audio" ] || [ "$media_type" = "auto" ]); then
                url=$(echo "$result" | jq -r '.audio.url // empty' 2>/dev/null)
            fi
            if [ -z "$url" ]; then
                url=$(echo "$result" | jq -r '.output.url // .url // .data.url // empty' 2>/dev/null)
            fi
            echo "$url"
            ;;
        muapi)
            echo "$result" | jq -r '.outputs[0] // empty'
            ;;
    esac
}

# --- Upload File ---
upload_file() {
    local file_path="$1"
    local json_only="${2:-false}"
    local provider=$(detect_provider)

    if [ ! -f "$file_path" ]; then
        echo "Error: File not found: $file_path" >&2
        return 1
    fi

    [ "$json_only" = "false" ] && echo "Uploading $(basename "$file_path")..." >&2

    case $provider in
        fal)
            local filename=$(basename "$file_path")
            local ext="${filename##*.}"
            local content_type="application/octet-stream"
            case $ext in
                jpg|jpeg) content_type="image/jpeg" ;;
                png) content_type="image/png" ;;
                mp4) content_type="video/mp4" ;;
                mp3) content_type="audio/mpeg" ;;
                wav) content_type="audio/wav" ;;
                webp) content_type="image/webp" ;;
                gif) content_type="image/gif" ;;
                mov) content_type="video/quicktime" ;;
                webm) content_type="video/webm" ;;
            esac

            local init_resp=$(curl -s -X POST "$FAL_STORAGE_INITIATE" \
                -H "Authorization: Key $FAL_KEY" \
                -H "Content-Type: application/json" \
                -d "{\"file_name\":\"$filename\",\"content_type\":\"$content_type\"}")

            local upload_url=$(echo "$init_resp" | jq -r '.upload_url // empty')
            local file_url=$(echo "$init_resp" | jq -r '.file_url // empty')

            if [ -z "$upload_url" ] || [ -z "$file_url" ]; then
                echo "Error: FAL upload initiate failed" >&2
                return 1
            fi

            curl -s -X PUT "$upload_url" -H "Content-Type: $content_type" --data-binary "@$file_path" >/dev/null
            echo "$file_url"
            ;;
        muapi)
            local resp=$(curl -s -X POST "${MUAPI_BASE}/upload_file" \
                -H "x-api-key: $MUAPI_KEY" \
                -F "file=@${file_path}")
            local url=$(echo "$resp" | jq -r '.url // empty')
            if [ -z "$url" ]; then
                local err=$(echo "$resp" | jq -r '.error // .detail // "Upload failed"')
                echo "Error: $err" >&2
                return 1
            fi
            echo "$url"
            ;;
    esac
}

# --- Validate Provider ---
validate_provider() {
    local provider=$(detect_provider)
    if [ "$provider" = "none" ]; then
        echo "Error: No API key set. Set FAL_KEY or MUAPI_KEY." >&2
        echo "  export FAL_KEY=your_fal_key" >&2
        echo "  export MUAPI_KEY=your_muapi_key" >&2
        echo "  Or run: bash core/platform/setup.sh --add-key fal YOUR_KEY" >&2
        exit 1
    fi
    [ "$JSON_ONLY" = "false" ] 2>/dev/null && echo "Provider: $provider" >&2 || true
}

# --- Download and View ---
download_and_view() {
    local url="$1"
    local default_ext="${2:-bin}"
    local json_only="${3:-false}"

    local ext="${url##*.}"
    [[ "$ext" == http* ]] || [ -z "$ext" ] && ext="$default_ext"
    ext="${ext%%\?*}"

    local output_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../media_outputs"
    mkdir -p "$output_dir"
    local temp_file="$output_dir/gen_$(date +%s).$ext"

    [ "$json_only" = "false" ] && echo "Downloading to $temp_file..." >&2
    curl -s -o "$temp_file" "$url"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$temp_file"
    fi

    echo "$temp_file"
}

# --- Require MUAPI ---
# Call in scripts that only work with MUAPI (music, lipsync, etc.)
require_muapi() {
    local feature="$1"
    if [ "$(detect_provider)" = "fal" ]; then
        echo "Error: $feature requires MUAPI. Set MUAPI_KEY or use --provider muapi." >&2
        exit 1
    fi
}
