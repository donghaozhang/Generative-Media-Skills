#!/bin/bash
# Platform Setup (MUAPI + FAL)
# Usage: ./setup.sh --add-key fal|muapi [KEY] | --show-config | --test

set -e

ACTION="help"
KEY_PROVIDER=""
KEY_VALUE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --add-key)
            ACTION="add-key"
            if [[ -n "$2" && ("$2" = "fal" || "$2" = "muapi") ]]; then
                KEY_PROVIDER="$2"
                shift
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    KEY_VALUE="$2"
                    shift
                fi
            elif [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                # Legacy: --add-key VALUE (assume muapi)
                KEY_PROVIDER="muapi"
                KEY_VALUE="$2"
                shift
            else
                KEY_PROVIDER="muapi"
            fi
            shift ;;
        --show-config)
            ACTION="show-config"
            shift ;;
        --test)
            ACTION="test"
            shift ;;
        --help|-h)
            echo "Platform Setup (MUAPI + FAL)" >&2
            echo "" >&2
            echo "Usage:" >&2
            echo "  ./setup.sh --add-key fal [KEY]    Save FAL_KEY to .env" >&2
            echo "  ./setup.sh --add-key muapi [KEY]  Save MUAPI_KEY to .env" >&2
            echo "  ./setup.sh --add-key [KEY]        Save MUAPI_KEY (legacy)" >&2
            echo "  ./setup.sh --show-config           Show current configuration" >&2
            echo "  ./setup.sh --test                  Test API key validity" >&2
            exit 0 ;;
        *) shift ;;
    esac
done

if [ -f ".env" ]; then source .env 2>/dev/null || true; fi

case $ACTION in
    add-key)
        if [ "$KEY_PROVIDER" = "fal" ]; then
            ENV_VAR="FAL_KEY"
            PROMPT_MSG="Enter your FAL.ai API key (get one at https://fal.ai/dashboard/keys):"
        else
            ENV_VAR="MUAPI_KEY"
            PROMPT_MSG="Enter your muapi.ai API key (get one at https://muapi.ai/dashboard):"
        fi

        if [ -z "$KEY_VALUE" ]; then
            echo "$PROMPT_MSG"
            read -r KEY_VALUE
        fi
        if [ -z "$KEY_VALUE" ]; then
            echo "Error: No API key provided" >&2; exit 1
        fi

        grep -v "^${ENV_VAR}=" .env > .env.tmp 2>/dev/null || true
        mv .env.tmp .env 2>/dev/null || true
        echo "${ENV_VAR}=$KEY_VALUE" >> .env
        echo "${ENV_VAR} saved to .env"
        echo ""
        echo "You can now use scripts with --provider $KEY_PROVIDER. Example:"
        echo "  bash generate-image.sh --prompt \"a sunset\" --provider $KEY_PROVIDER" ;;

    show-config)
        echo "Media Skills Configuration"
        echo "=========================="
        echo ""
        echo "--- MUAPI ---"
        if [ -n "$MUAPI_KEY" ]; then
            MASKED="${MUAPI_KEY:0:8}...${MUAPI_KEY: -4}"
            echo "MUAPI_KEY: $MASKED"
            echo "Status: Configured"
        else
            echo "MUAPI_KEY: Not set"
        fi
        echo "Base URL: https://api.muapi.ai/api/v1"
        echo ""
        echo "--- FAL ---"
        if [ -n "$FAL_KEY" ]; then
            MASKED="${FAL_KEY:0:8}...${FAL_KEY: -4}"
            echo "FAL_KEY: $MASKED"
            echo "Status: Configured"
        else
            echo "FAL_KEY: Not set"
        fi
        echo "Base URL: https://queue.fal.run"
        echo ""
        # Auto-detect
        if [ -n "$FAL_KEY" ] || [ -n "$MUAPI_KEY" ]; then
            if [ -n "$FAL_KEY" ] && [ -n "$MUAPI_KEY" ]; then
                echo "Auto-detect: FAL (preferred when both set)"
            elif [ -n "$FAL_KEY" ]; then
                echo "Auto-detect: FAL"
            else
                echo "Auto-detect: MUAPI"
            fi
        else
            echo "Auto-detect: No keys configured"
            echo "Run: bash setup.sh --add-key fal YOUR_KEY"
            echo "  or bash setup.sh --add-key muapi YOUR_KEY"
        fi ;;

    test)
        TESTED=false
        if [ -n "$MUAPI_KEY" ]; then
            echo "Testing MUAPI key..."
            RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "x-api-key: $MUAPI_KEY" \
                "https://api.muapi.ai/api/v1/predictions/test-connection/result")
            if [ "$RESPONSE" = "401" ]; then
                echo "MUAPI: Invalid or expired key" >&2
            elif [ "$RESPONSE" = "404" ] || [ "$RESPONSE" = "200" ]; then
                echo "MUAPI: Key is valid!"
            else
                echo "MUAPI: Unexpected response: $RESPONSE (may still be valid)"
            fi
            TESTED=true
        fi
        if [ -n "$FAL_KEY" ]; then
            echo "Testing FAL key..."
            RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: Key $FAL_KEY" \
                "https://queue.fal.run/fal-ai/flux/dev/requests/test-connection/status")
            if [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "403" ]; then
                echo "FAL: Invalid or expired key" >&2
            elif [ "$RESPONSE" = "404" ] || [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "422" ]; then
                echo "FAL: Key is valid!"
            else
                echo "FAL: Unexpected response: $RESPONSE (may still be valid)"
            fi
            TESTED=true
        fi
        if [ "$TESTED" = false ]; then
            echo "Error: No API keys set. Run: bash setup.sh --add-key fal|muapi" >&2
            exit 1
        fi ;;

    *)
        echo "Platform Setup (MUAPI + FAL)" >&2
        echo "Usage: ./setup.sh --add-key fal|muapi [KEY] | --show-config | --test" >&2
        exit 0 ;;
esac
