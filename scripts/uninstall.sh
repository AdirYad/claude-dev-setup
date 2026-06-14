#!/usr/bin/env bash
#
# claude-dev-setup - Uninstall (macOS + Linux)
#
# Removes the Claude Code CLI and the Claude Code + Claude RTL extensions from
# Antigravity. It leaves git, Node.js, and Antigravity in place, since other
# software may rely on them.
#
#   curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/uninstall.sh | bash
#
set -euo pipefail

EXT_CLAUDE_CODE="Anthropic.claude-code"
EXT_CLAUDE_RTL="AdirYad.claude-rtl-code"
CLAUDE_BIN_DIR="$HOME/.local/bin"
CLAUDE_SHARE_DIR="$HOME/.local/share/claude"

DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in --dry-run) DRY_RUN=true ;; *) ;; esac
    shift
done

if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_GRAY=$'\033[90m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_GRAY=""; C_RED=""; C_RESET=""
fi
CHECK=$'\xe2\x9c\x93'; CROSS=$'\xe2\x9c\x97'; BULLET=$'\xe2\x80\xa2'

banner() {
    local rule; rule="$(printf '\xe2\x94\x80%.0s' $(seq 1 52))"
    printf '\n  %sClaude Dev Setup - Uninstall%s\n' "$C_CYAN" "$C_RESET"
    printf '  %sRemoving the Claude parts (keeping git, Node, Antigravity)%s\n' "$C_GRAY" "$C_RESET"
    printf '  %s%s%s\n\n' "$C_GRAY" "$rule" "$C_RESET"
}
rule_line() { printf '  %s%s%s\n' "$C_GRAY" "$(printf '\xe2\x94\x80%.0s' $(seq 1 52))" "$C_RESET"; }
row() {
    local mark="$1" color="$2" name="$3" detail="$4"
    printf '  %s%s%s  %-19s%s%s%s\n' "$color" "$mark" "$C_RESET" "$name" "$C_GRAY" "$detail" "$C_RESET"
}

has_command() { command -v "$1" >/dev/null 2>&1; }

# Spinner that leaves a persistent checkmark line (see install.sh).
run_quiet() {
    local label="$1"; shift
    $DRY_RUN && return 0
    if [ -t 1 ]; then
        local log; log="$(mktemp)"
        ( "$@" >"$log" 2>&1 ) &
        local pid=$! frames="|/-\\" i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s  %s   ' "${frames:$((i % 4)):1}" "$label"
            i=$((i + 1)); sleep 0.12
        done
        wait "$pid" 2>/dev/null || true
        rm -f "$log"
        printf '\r  %s%s%s  %s\n' "$C_GREEN" "$CHECK" "$C_RESET" "$label"
    else
        "$@" >/dev/null 2>&1 || true
        printf '  %s%s%s  %s\n' "$C_GREEN" "$CHECK" "$C_RESET" "$label"
    fi
    return 0
}

find_antigravity_cli() {
    if has_command antigravity; then command -v antigravity; return 0; fi
    local c
    for c in \
        "/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity" \
        "/usr/share/antigravity/bin/antigravity" \
        "/usr/bin/antigravity" \
        "/opt/antigravity/bin/antigravity" \
        "$HOME/.local/share/antigravity/bin/antigravity"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

antigravity_extensions() {
    local cli="$1"
    [ -z "$cli" ] && return 0
    "$cli" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

remove_extension() {
    local ext_id="$1" cli="$2" id_lc
    id_lc="$(printf '%s' "$ext_id" | tr '[:upper:]' '[:lower:]')"
    [ -z "$cli" ] && return 0
    antigravity_extensions "$cli" | grep -qx "$id_lc" || return 0
    "$cli" --uninstall-extension "$ext_id" >/dev/null 2>&1 || true
}

main() {
    banner
    local cli
    cli="$(find_antigravity_cli 2>/dev/null || true)"

    if ! $DRY_RUN; then
        [ -n "$cli" ] && run_quiet "Removing Claude in editor" remove_extension "$EXT_CLAUDE_CODE" "$cli"
        [ -n "$cli" ] && run_quiet "Removing Hebrew support" remove_extension "$EXT_CLAUDE_RTL" "$cli"
        if [ -x "$CLAUDE_BIN_DIR/claude" ]; then
            run_quiet "Removing the Claude command" rm -f "$CLAUDE_BIN_DIR/claude"
        fi
        rm -rf "$CLAUDE_SHARE_DIR" 2>/dev/null || true
    fi

    local exts code_gone=1 rtl_gone=1 claude_gone=1
    exts="$(antigravity_extensions "$cli")"
    printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_CODE" | tr '[:upper:]' '[:lower:]')" && code_gone=0
    printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_RTL" | tr '[:upper:]' '[:lower:]')" && rtl_gone=0
    [ -x "$CLAUDE_BIN_DIR/claude" ] && claude_gone=0

    mark() { if [ "$1" = 1 ]; then printf '%s' "$CHECK"; else printf '%s' "$CROSS"; fi; }
    color() { if [ "$1" = 1 ]; then printf '%s' "$C_GREEN"; else printf '%s' "$C_RED"; fi; }

    echo
    printf '  %sRemoved%s\n' "$C_CYAN" "$C_RESET"; rule_line
    row "$(mark "$code_gone")" "$(color "$code_gone")" "Claude in editor" "extension"
    row "$(mark "$rtl_gone")" "$(color "$rtl_gone")" "Hebrew support" "extension"
    row "$(mark "$claude_gone")" "$(color "$claude_gone")" "Claude command" "CLI"
    echo
    printf '  %sKept (other software may use these)%s\n' "$C_CYAN" "$C_RESET"; rule_line
    row "$BULLET" "$C_GRAY" "Git" "remove with your package manager"
    row "$BULLET" "$C_GRAY" "Node.js" "remove with your package manager"
    row "$BULLET" "$C_GRAY" "Antigravity" "remove with your package manager"
    rule_line
    printf '\n  %sDone. The Claude parts have been removed.%s\n\n' "$C_GREEN" "$C_RESET"
}

main
