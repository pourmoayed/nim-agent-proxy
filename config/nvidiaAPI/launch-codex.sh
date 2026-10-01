#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
CONFIG_FILE="$SCRIPT_DIR/litellm_config.yaml"
PORT=4000
PROXY_PID=""

load_nvidia_api_key() {
    printf '[1/3] Loading NVIDIA_API_KEY from .env...\n'
    if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
        return
    fi
    if [[ ! -f "$ENV_FILE" ]]; then
        printf 'Error: .env file not found at %s\n' "$ENV_FILE" >&2
        return 1
    fi

    local value
    value="$(sed -n '/^[[:space:]]*NVIDIA_API_KEY[[:space:]]*=/ { s/^[[:space:]]*NVIDIA_API_KEY[[:space:]]*=[[:space:]]*//; p; q; }' "$ENV_FILE")"
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
        value="${value:1:${#value}-2}"
    fi
    if [[ -z "$value" ]]; then
        printf 'Error: NVIDIA_API_KEY is missing or empty in %s\n' "$ENV_FILE" >&2
        return 1
    fi
    export NVIDIA_API_KEY="$value"
}

start_proxy() {
    printf '[2/3] Starting litellm proxy on port %s...\n' "$PORT"
    (cd "$REPO_ROOT" && exec pipenv run litellm --config "$CONFIG_FILE" --port "$PORT") &
    PROXY_PID=$!
}

wait_for_proxy() {
    local health_url="http://localhost:$PORT/health/liveliness"
    local deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if curl --fail --silent --max-time 5 "$health_url" >/dev/null 2>&1; then
            return
        fi
        if ! kill -0 "$PROXY_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    printf 'Warning: proxy did not answer on %s within 120s; continuing anyway.\n' "$health_url" >&2
}

stop_proxy() {
    if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
        pkill -TERM -P "$PROXY_PID" 2>/dev/null || true
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi
}

load_nvidia_api_key
trap stop_proxy EXIT
start_proxy
wait_for_proxy

printf '[3/3] Launching Codex! (exit Codex to stop the proxy)\n'
printf '%s\n' '-----------------------------------------------------------'
codex "$@"