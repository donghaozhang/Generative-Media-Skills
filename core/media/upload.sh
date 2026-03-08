#!/bin/bash
# File Upload (MUAPI + FAL)
# Usage: ./upload.sh --file /path/to/file.jpg [--provider fal|muapi]
# Returns: CDN URL

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/provider.sh"

FILE=""
PROVIDER=""
JSON_ONLY=false

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider) PROVIDER="$2"; shift 2 ;;
        --file|-f) FILE="$2"; shift 2 ;;
        --json) JSON_ONLY=true; shift ;;
        --help|-h)
            echo "File Upload (MUAPI + FAL)" >&2
            echo "Usage: ./upload.sh --file /path/to/file.jpg [--provider fal|muapi]" >&2
            echo "Returns the CDN URL of the uploaded file." >&2
            echo "" >&2
            echo "Supported: jpg, jpeg, png, gif, webp, mp4, mov, webm, mp3, wav" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

validate_provider

if [ -z "$FILE" ]; then
    echo "Error: --file is required" >&2
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE" >&2
    exit 1
fi

CDN_URL=$(upload_file "$FILE" "$JSON_ONLY")

if [ -z "$CDN_URL" ] || [[ "$CDN_URL" == Error* ]]; then
    echo "Error: Upload failed" >&2
    exit 1
fi

[ "$JSON_ONLY" = false ] && echo "Uploaded: $CDN_URL" >&2

if [ "$JSON_ONLY" = true ]; then
    echo "{\"url\": \"$CDN_URL\", \"provider\": \"$(detect_provider)\"}"
else
    echo "$CDN_URL"
fi
