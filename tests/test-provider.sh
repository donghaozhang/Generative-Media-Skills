#!/bin/bash
# Test provider abstraction without hitting real APIs
# Tests provider detection, endpoint resolution, and output extraction

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../core/lib/provider.sh"

PASS=0
FAIL=0

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $test_name (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Provider Detection Tests ==="

# Test 1: No keys -> none
unset FAL_KEY MUAPI_KEY PROVIDER
result=$(detect_provider)
assert_eq "No keys -> none" "none" "$result"

# Test 2: MUAPI only
export MUAPI_KEY="test_muapi"
unset FAL_KEY PROVIDER
result=$(detect_provider)
assert_eq "MUAPI only -> muapi" "muapi" "$result"

# Test 3: FAL only
unset MUAPI_KEY PROVIDER
export FAL_KEY="test_fal"
result=$(detect_provider)
assert_eq "FAL only -> fal" "fal" "$result"

# Test 4: Both keys -> FAL preferred
export MUAPI_KEY="test_muapi"
export FAL_KEY="test_fal"
unset PROVIDER
result=$(detect_provider)
assert_eq "Both keys -> fal preferred" "fal" "$result"

# Test 5: --provider override
export PROVIDER="muapi"
result=$(detect_provider)
assert_eq "PROVIDER=muapi override" "muapi" "$result"
unset PROVIDER

echo ""
echo "=== Endpoint Resolution Tests ==="

# Test 6: FAL endpoint mapping - flux-dev
export FAL_KEY="test"
unset MUAPI_KEY PROVIDER
result=$(resolve_endpoint "flux-dev")
assert_eq "flux-dev -> fal-ai/flux/dev" "fal-ai/flux/dev" "$result"

# Test 7: FAL endpoint mapping - veo3
result=$(resolve_endpoint "veo3")
assert_eq "veo3 -> fal-ai/veo3" "fal-ai/veo3" "$result"

# Test 8: FAL endpoint mapping - minimax-pro
result=$(resolve_endpoint "minimax-pro")
assert_eq "minimax-pro -> fal-ai/minimax/hailuo-02/pro/text-to-video" "fal-ai/minimax/hailuo-02/pro/text-to-video" "$result"

# Test 9: Unknown model falls back to fal-ai/ prefix
result=$(resolve_endpoint "unknown-model")
assert_eq "unknown -> fal-ai/unknown-model" "fal-ai/unknown-model" "$result"

echo ""
echo "=== Output URL Extraction Tests ==="

# Test 10: FAL image response
export FAL_KEY="test"
unset MUAPI_KEY PROVIDER
result=$(extract_output_url '{"images":[{"url":"https://fal.ai/img.png"}]}' "image")
assert_eq "FAL image extraction" "https://fal.ai/img.png" "$result"

# Test 11: FAL video response
result=$(extract_output_url '{"video":{"url":"https://fal.ai/vid.mp4"}}' "video")
assert_eq "FAL video extraction" "https://fal.ai/vid.mp4" "$result"

# Test 12: FAL audio response
result=$(extract_output_url '{"audio":{"url":"https://fal.ai/audio.mp3"}}' "audio")
assert_eq "FAL audio extraction" "https://fal.ai/audio.mp3" "$result"

# Test 13: FAL auto-detect image
result=$(extract_output_url '{"images":[{"url":"https://fal.ai/auto.png"}]}' "auto")
assert_eq "FAL auto-detect image" "https://fal.ai/auto.png" "$result"

# Test 14: MUAPI response
unset FAL_KEY PROVIDER
export MUAPI_KEY="test"
result=$(extract_output_url '{"outputs":["https://muapi.ai/out.mp4"]}' "video")
assert_eq "MUAPI output extraction" "https://muapi.ai/out.mp4" "$result"

echo ""
echo "=== Auth Header Tests ==="

# Test 15: FAL headers
export FAL_KEY="test_key_123"
unset MUAPI_KEY PROVIDER
get_headers
header_str="${HEADERS[*]}"
if [[ "$header_str" == *"Authorization: Key test_key_123"* ]]; then
    echo "PASS: FAL auth header contains 'Authorization: Key'"
    PASS=$((PASS + 1))
else
    echo "FAIL: FAL auth header incorrect: $header_str"
    FAIL=$((FAIL + 1))
fi

# Test 16: MUAPI headers
unset FAL_KEY PROVIDER
export MUAPI_KEY="test_key_456"
get_headers
header_str="${HEADERS[*]}"
if [[ "$header_str" == *"x-api-key: test_key_456"* ]]; then
    echo "PASS: MUAPI auth header contains 'x-api-key'"
    PASS=$((PASS + 1))
else
    echo "FAIL: MUAPI auth header incorrect: $header_str"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Validate Provider Tests ==="

# Test 17: validate_provider with no keys should exit
unset FAL_KEY MUAPI_KEY PROVIDER
set +e
result=$(validate_provider 2>&1)
exit_code=$?
set -e
if [ $exit_code -ne 0 ]; then
    echo "PASS: validate_provider exits with error when no keys"
    PASS=$((PASS + 1))
else
    echo "FAIL: validate_provider should exit when no keys"
    FAIL=$((FAIL + 1))
fi

# Test 18: require_muapi with FAL should exit
export FAL_KEY="test"
unset MUAPI_KEY PROVIDER
set +e
result=$(require_muapi "Music" 2>&1)
exit_code=$?
set -e
if [ $exit_code -ne 0 ]; then
    echo "PASS: require_muapi exits when provider is FAL"
    PASS=$((PASS + 1))
else
    echo "FAIL: require_muapi should exit when provider is FAL"
    FAIL=$((FAIL + 1))
fi

# Test 19: require_muapi with MUAPI should pass
unset FAL_KEY PROVIDER
export MUAPI_KEY="test"
set +e
result=$(require_muapi "Music" 2>&1)
exit_code=$?
set -e
if [ $exit_code -eq 0 ]; then
    echo "PASS: require_muapi passes when provider is MUAPI"
    PASS=$((PASS + 1))
else
    echo "FAIL: require_muapi should pass when provider is MUAPI"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Script Help Tests ==="

# Test 20: All core scripts should accept --help
SKILLS_DIR="$SCRIPT_DIR/.."
SCRIPTS=(
    "core/media/generate-image.sh"
    "core/media/generate-video.sh"
    "core/media/image-to-video.sh"
    "core/media/create-music.sh"
    "core/media/upload.sh"
    "core/edit/edit-image.sh"
    "core/edit/enhance-image.sh"
    "core/edit/lipsync.sh"
    "core/edit/video-effects.sh"
    "core/platform/setup.sh"
    "core/platform/check-result.sh"
)

for script in "${SCRIPTS[@]}"; do
    set +e
    output=$(bash "$SKILLS_DIR/$script" --help 2>&1)
    exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "PASS: $script --help exits cleanly"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $script --help failed (exit $exit_code)"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
