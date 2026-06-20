#!/bin/bash

RESET=$'\033[0m'
MAGENTA=$'\033[35m'
WHITE=$'\033[37m'
GRAY=$'\033[90m'
YELLOW=$'\033[33m'
BRIGHT_CYAN=$'\033[96m'
BRIGHT_GREEN=$'\033[38;2;0;255;0m'
DISK_USAGE_COLOR=$'\033[48;2;0;255;0;30m'
PURGE_PROMPT_COLOR=$'\033[41;97m'

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

show_docker_usage() {
    echo
    local usage
    if ! usage="$(docker system df 2>&1)"; then
        printf '%s\n' "$usage" >&2
        echo "Unable to read Docker disk usage. Is Docker running?" >&2
        exit 1
    fi

    local lines=("Docker disk usage:")
    local line
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$usage"

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

run_docker_prune() {
    local description="$1"
    shift

    echo
    echo "$description"
    if ! docker "$@"; then
        echo "$description failed." >&2
        exit 1
    fi
}

stop_running_containers() {
    local container_ids
    container_ids="$(docker ps -q)"
    if [[ "$?" -ne 0 ]]; then
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
    if ! docker stop $container_ids; then
        echo "Stopping running containers failed." >&2
        exit 1
    fi
}

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI was not found. Install Docker or add it to PATH." >&2
    exit 1
fi

print_color "$MAGENTA" "~*~*--=== A ROBUST, COMPLETE DOCKER PURGE SCRIPT ===--*~*~"
print_color "$WHITE" "by Vernard Mercader (https://github.com/vince7488)"
echo
print_color "$GRAY" "*WAW, very convenient much!*"
echo
print_color "$YELLOW" "These commands are destructive. Option 1 stops all running containers, kills all stopped containers, strips all unreferenced images, clears unused networks, removes unused named and anonymous volumes, and clears the build cache. Data residing in unused volumes will be permanently erased. Proceed with caution."
echo
echo
print_color "$BRIGHT_CYAN" "1. Purge all unused Docker resources [1]"
print_color "$BRIGHT_CYAN" "2. One by one [2]"
prompt_input "$BRIGHT_CYAN" "Select option: " choice

if [[ "$choice" == "1" ]]; then
    show_docker_usage

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

    show_docker_usage
    echo
    echo "Complete Docker purge done."
elif [[ "$choice" == "2" ]]; then
    ran_any=0
    show_docker_usage

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
        show_docker_usage
        echo
        echo "Selected Docker purge steps done."
    else
        echo "No prune commands selected."
    fi
else
    echo "Invalid choice. Exiting."
fi
