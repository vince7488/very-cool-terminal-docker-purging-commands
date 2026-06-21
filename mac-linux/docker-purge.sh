#!/bin/bash

PREVIEW_ONLY=0
NO_COLOR_FLAG=0
DOCKER_BIN="${DOCKER_PURGE_DOCKER_BIN:-docker}"

RESET=$'\033[0m'
MAGENTA=$'\033[35m'
WHITE=$'\033[37m'
GRAY=$'\033[90m'
YELLOW=$'\033[33m'
BRIGHT_CYAN=$'\033[96m'
BRIGHT_GREEN=$'\033[38;2;0;255;0m'
DISK_USAGE_COLOR=$'\033[48;2;0;255;0;30m'
PURGE_PROMPT_COLOR=$'\033[41;97m'

show_usage() {
    cat <<'USAGE'
Usage:
  ./docker-purge.sh [--preview|--dry-run] [--no-color] [--help]

Options:
  --preview   Show Docker context, disk usage, containers, images, volumes, networks, and build cache without deleting anything.
  --dry-run   Same as --preview. No Docker resources are changed.
  --no-color  Disable ANSI colors. You can also set NO_COLOR=1.
  --help      Show this help text.
USAGE
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --preview | --dry-run)
            PREVIEW_ONLY=1
            ;;
        --no-color)
            NO_COLOR_FLAG=1
            ;;
        -h | --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n "${NO_COLOR:-}" || "$NO_COLOR_FLAG" -eq 1 ]]; then
    RESET=''
    MAGENTA=''
    WHITE=''
    GRAY=''
    YELLOW=''
    BRIGHT_CYAN=''
    BRIGHT_GREEN=''
    DISK_USAGE_COLOR=''
    PURGE_PROMPT_COLOR=''
fi

print_color() {
    local color="$1"
    local text="$2"

    printf '%b%s%b\n' "$color" "$text" "$RESET"
}

prompt_input() {
    local color="$1"
    local prompt="$2"
    local result_var="$3"

    printf '%b%s%b' "$color" "$prompt" "$RESET"
    read -r "$result_var"
}

prompt_yes_no() {
    local prompt="$1"
    local result_var="$2"

    printf '%b%s%b' "$BRIGHT_GREEN" "$prompt" "$RESET"
    printf '%b%s%b ' "$YELLOW" " (y/N)" "$RESET"
    read -r "$result_var"
}

write_preview_block() {
    local title="$1"
    local body="$2"
    local lines=("$title")
    local line

    if [[ -n "$body" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && lines+=("$line")
        done <<< "$body"
    fi

    if [[ "${#lines[@]}" -eq 1 ]]; then
        lines+=("(none)")
    fi

    local max_length=0
    for line in "${lines[@]}"; do
        if ((${#line} > max_length)); then
            max_length=${#line}
        fi
    done

    local separator
    printf -v separator '%*s' "$((max_length + 1))" ''
    separator=${separator// /=}

    local separator_length=${#separator}
    print_color "$DISK_USAGE_COLOR" "$separator"
    for line in "${lines[@]}"; do
        printf '%b%-*s%b\n' "$DISK_USAGE_COLOR" "$separator_length" "$line" "$RESET"
    done
    print_color "$DISK_USAGE_COLOR" "$separator"
}

show_docker_output_block() {
    local title="$1"
    shift
    local output

    echo
    if ! output="$("$DOCKER_BIN" "$@" 2>&1)"; then
        printf '%s\n' "$output" >&2
        echo "Unable to read $title" >&2
        exit 1
    fi

    write_preview_block "$title" "$output"
}

show_docker_preview() {
    show_docker_output_block "Docker context:" context show
    show_docker_output_block "Docker disk usage:" system df
    show_docker_output_block "Running containers:" ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    show_docker_output_block "Stopped containers:" ps -a --filter status=exited --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    show_docker_output_block "Images:" images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
    show_docker_output_block "Volumes:" volume ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'
    show_docker_output_block "Custom networks:" network ls --filter type=custom --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'
    show_docker_output_block "Build cache:" builder du
}

run_docker_prune() {
    local description="$1"
    shift

    echo
    echo "$description"
    if ! "$DOCKER_BIN" "$@"; then
        echo "$description failed." >&2
        exit 1
    fi
}

stop_running_containers() {
    local container_ids
    if ! container_ids="$("$DOCKER_BIN" ps -q 2>&1)"; then
        printf '%s\n' "$container_ids" >&2
        echo "Unable to list running containers." >&2
        exit 1
    fi

    if [[ -z "$container_ids" ]]; then
        echo
        echo "No running containers to stop."
        return
    fi

    echo
    echo "Stopping all running containers..."
    # Container IDs do not contain whitespace; word splitting preserves Docker's newline-separated ID list.
    # shellcheck disable=SC2086
    if ! "$DOCKER_BIN" stop $container_ids; then
        echo "Stopping running containers failed." >&2
        exit 1
    fi
}

prompt_purge_confirmation() {
    local result_var="$1"
    local skull=(
        '          .-.'
        '         (o o)'
        '         | O |'
        '          |=|'
        '      ___/| |\___'
        '     /   /   \   \'
        '    /___/     \___\'
    )

    echo
    echo
    for line in "${skull[@]}"; do
        print_color "$PURGE_PROMPT_COLOR" "$line"
    done

    echo
    printf '%b%s%b' "$PURGE_PROMPT_COLOR" "Type PURGE to run every prune command without more prompts: " "$RESET"
    read -r "$result_var"
}

print_intro() {
    print_color "$MAGENTA" "~*~*--=== A ROBUST, COMPLETE DOCKER PURGE SCRIPT ===--*~*~"
    print_color "$WHITE" "by Vernard Mercader (https://github.com/vince7488)"
    echo
    print_color "$GRAY" "*WAW, very convenient much!*"
    echo
    print_color "$YELLOW" "These commands are destructive. Option 1 stops all running containers, kills all stopped containers, strips all unreferenced images, clears unused networks, removes unused named and anonymous volumes, and clears the build cache. Data residing in unused volumes will be permanently erased. Proceed with caution."
    echo
}

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
    echo "Docker CLI was not found. Install Docker or add it to PATH." >&2
    exit 1
fi

print_intro

if [[ "$PREVIEW_ONLY" -eq 1 ]]; then
    show_docker_preview
    echo
    echo "Preview complete. No Docker resources were changed."
    exit 0
fi

echo
print_color "$BRIGHT_CYAN" "1. Purge all unused Docker resources [1]"
print_color "$BRIGHT_CYAN" "2. One by one [2]"
print_color "$BRIGHT_CYAN" "3. Preview only [3]"
prompt_input "$BRIGHT_CYAN" "Select option: " choice

if [[ "$choice" == "1" ]]; then
    show_docker_preview

    prompt_purge_confirmation confirm
    if [[ "$confirm" != "PURGE" ]]; then
        echo "Confirmation did not match. Exiting."
        exit 0
    fi

    stop_running_containers
    run_docker_prune "Purging stopped containers..." container prune -f
    run_docker_prune "Purging unused images..." image prune -a -f
    run_docker_prune "Purging unused named and anonymous volumes..." volume prune -a -f
    run_docker_prune "Purging unused networks..." network prune -f
    run_docker_prune "Purging build cache..." builder prune -a -f

    show_docker_preview
    echo
    echo "Complete Docker purge done."
elif [[ "$choice" == "2" ]]; then
    ran_any=0
    show_docker_preview

    prompt_yes_no "About to stop all running containers. Proceed?" runStop
    if [[ "$runStop" =~ ^[Yy]$ ]]; then
        stop_running_containers
        ran_any=1
    fi

    prompt_yes_no "About to purge all stopped containers. Proceed?" runCont
    if [[ "$runCont" =~ ^[Yy]$ ]]; then
        run_docker_prune "Purging stopped containers..." container prune -f
        ran_any=1
    fi

    prompt_yes_no "About to purge all unused images. Proceed?" runImg
    if [[ "$runImg" =~ ^[Yy]$ ]]; then
        run_docker_prune "Purging unused images..." image prune -a -f
        ran_any=1
    fi

    prompt_yes_no "About to clear all unused named and anonymous volumes. Proceed?" runVol
    if [[ "$runVol" =~ ^[Yy]$ ]]; then
        run_docker_prune "Purging unused named and anonymous volumes..." volume prune -a -f
        ran_any=1
    fi

    prompt_yes_no "About to clear all unused networks. Proceed?" runNet
    if [[ "$runNet" =~ ^[Yy]$ ]]; then
        run_docker_prune "Purging unused networks..." network prune -f
        ran_any=1
    fi

    prompt_yes_no "About to clear all build cache. Proceed?" runBld
    if [[ "$runBld" =~ ^[Yy]$ ]]; then
        run_docker_prune "Purging build cache..." builder prune -a -f
        ran_any=1
    fi

    if [[ "$ran_any" -eq 1 ]]; then
        show_docker_preview
        echo
        echo "Selected Docker purge steps done."
    else
        echo "No prune commands selected."
    fi
elif [[ "$choice" == "3" ]]; then
    show_docker_preview
    echo
    echo "Preview complete. No Docker resources were changed."
else
    echo "Invalid choice. Exiting."
fi
