#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/mac-linux/docker-purge.sh"
TMP_DIR="$(mktemp -d)"
FAKE_DOCKER="$TMP_DIR/docker"
LOG_FILE="$TMP_DIR/docker.log"
OUT_FILE="$TMP_DIR/output.txt"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$FAKE_DOCKER" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${DOCKER_PURGE_TEST_LOG:?}"

cmd="${1:-}"
if [[ "$#" -gt 0 ]]; then
    shift
fi

case "$cmd" in
    context)
        echo "test-context"
        ;;
    system)
        cat <<'EOF'
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          2         0         120MB     120MB (100%)
Containers      1         0         1kB       1kB (100%)
Local Volumes   1         0         20MB      20MB (100%)
Build Cache     1         0         15MB      15MB
EOF
        ;;
    ps)
        if [[ "${1:-}" == "-q" ]]; then
            echo "abc123"
        elif [[ "$*" == *"status=exited"* ]]; then
            printf 'NAMES\tIMAGE\tSTATUS\nold-app\talpine\tExited\n'
        else
            printf 'NAMES\tIMAGE\tSTATUS\tPORTS\nlive-app\tnginx\tUp 5 minutes\t80/tcp\n'
        fi
        ;;
    images)
        printf 'REPOSITORY\tTAG\tIMAGE ID\tSIZE\nnginx\tlatest\timg123\t80MB\n'
        ;;
    volume)
        if [[ "${1:-}" == "ls" ]]; then
            printf 'VOLUME NAME\tDRIVER\tSCOPE\nsample-volume\tlocal\tlocal\n'
        elif [[ "${1:-}" == "prune" ]]; then
            echo "Deleted volumes"
        else
            echo "Unexpected volume command: $*" >&2
            exit 42
        fi
        ;;
    network)
        if [[ "${1:-}" == "ls" ]]; then
            printf 'NAME\tDRIVER\tSCOPE\nsample-network\tbridge\tlocal\n'
        elif [[ "${1:-}" == "prune" ]]; then
            echo "Deleted networks"
        else
            echo "Unexpected network command: $*" >&2
            exit 42
        fi
        ;;
    builder)
        if [[ "${1:-}" == "du" ]]; then
            echo "ID          RECLAIMABLE     SIZE"
            echo "cache123    true            15MB"
        elif [[ "${1:-}" == "prune" ]]; then
            echo "Deleted build cache"
        else
            echo "Unexpected builder command: $*" >&2
            exit 42
        fi
        ;;
    stop)
        printf '%s\n' "$@"
        ;;
    container)
        echo "Deleted containers"
        ;;
    image)
        echo "Deleted images"
        ;;
    *)
        echo "Unexpected docker command: $cmd $*" >&2
        exit 42
        ;;
esac
FAKE_DOCKER
chmod +x "$FAKE_DOCKER"

run_script() {
    local input="$1"
    shift

    : > "$LOG_FILE"
    DOCKER_PURGE_TEST_LOG="$LOG_FILE" \
    DOCKER_PURGE_DOCKER_BIN="$FAKE_DOCKER" \
    NO_COLOR=1 \
    bash "$SCRIPT_PATH" "$@" <<< "$input" > "$OUT_FILE"
}

assert_output_contains() {
    local needle="$1"
    if ! grep -Fq "$needle" "$OUT_FILE"; then
        echo "Expected output to contain: $needle" >&2
        exit 1
    fi
}

assert_output_has_no_ansi() {
    if grep -q $'\033' "$OUT_FILE"; then
        echo "Expected output to contain no ANSI escape sequences." >&2
        exit 1
    fi
}

assert_log_contains() {
    local needle="$1"
    if ! grep -Fxq "$needle" "$LOG_FILE"; then
        echo "Expected docker log to contain: $needle" >&2
        echo "Actual log:" >&2
        cat "$LOG_FILE" >&2
        exit 1
    fi
}

assert_log_not_contains() {
    local needle="$1"
    if grep -Fxq "$needle" "$LOG_FILE"; then
        echo "Expected docker log not to contain: $needle" >&2
        cat "$LOG_FILE" >&2
        exit 1
    fi
}

assert_log_order() {
    local before="$1"
    local after="$2"
    local before_line
    local after_line

    before_line="$(grep -Fn "$before" "$LOG_FILE" | head -n 1 | cut -d: -f1)"
    after_line="$(grep -Fn "$after" "$LOG_FILE" | head -n 1 | cut -d: -f1)"

    if [[ -z "$before_line" || -z "$after_line" || "$before_line" -ge "$after_line" ]]; then
        echo "Expected '$before' to appear before '$after'." >&2
        cat "$LOG_FILE" >&2
        exit 1
    fi
}

run_script "" --preview --no-color
assert_output_contains "Preview complete. No Docker resources were changed."
assert_output_contains "test-context"
assert_output_has_no_ansi
assert_log_not_contains "stop abc123"
assert_log_not_contains "container prune -f"
assert_log_not_contains "image prune -a -f"
assert_log_not_contains "volume prune -a -f"
assert_log_not_contains "network prune -f"
assert_log_not_contains "builder prune -a -f"

run_script $'1\nPURGE\n' --no-color
assert_log_contains "stop abc123"
assert_log_contains "container prune -f"
assert_log_contains "image prune -a -f"
assert_log_contains "volume prune -a -f"
assert_log_contains "network prune -f"
assert_log_contains "builder prune -a -f"
assert_log_order "ps --format table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}" "stop abc123"
assert_log_order "stop abc123" "container prune -f"
assert_output_contains "Complete Docker purge done."

run_script $'2\ny\ny\ny\ny\ny\ny\n' --no-color
assert_log_contains "stop abc123"
assert_log_contains "container prune -f"
assert_log_contains "image prune -a -f"
assert_log_contains "volume prune -a -f"
assert_log_contains "network prune -f"
assert_log_contains "builder prune -a -f"
assert_output_contains "Selected Docker purge steps done."

echo "Bash mocked tests passed."
