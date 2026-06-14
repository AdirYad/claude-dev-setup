#!/usr/bin/env bash
#
# claude-dev-setup - macOS + Linux
#
# Installs git, Node.js LTS, Antigravity IDE, the Claude Code and Claude RTL
# Code extensions for Antigravity, and the Claude Code CLI.
#
# Re-running is safe: anything already installed is upgraded in place when an
# immediate upgrade is available (brew upgrade / claude update), otherwise it is
# left alone. PATH is always fixed so the tools work in a fresh terminal.
#
#   curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.sh | bash
#
set -euo pipefail

# Keep apt/dpkg from launching interactive prompts (e.g. tzdata) that would read
# the script's stdin - important when run via `curl ... | bash`. Harmless on macOS.
export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
EXT_CLAUDE_CODE="Anthropic.claude-code"
EXT_CLAUDE_RTL="AdirYad.claude-rtl-code"
RTL_VSIX_VERSION="1.0.9"
RTL_VSIX_URL="https://open-vsx.org/api/AdirYad/claude-rtl-code/${RTL_VSIX_VERSION}/file/AdirYad.claude-rtl-code-${RTL_VSIX_VERSION}.vsix"
CLAUDE_BIN_DIR="$HOME/.local/bin"

# Known-good macOS build for the no-Homebrew fallback (brew gets newer).
ANTIGRAVITY_MAC_VER1="2.1.4"
ANTIGRAVITY_MAC_VER2="6481382726303744"

# Optional override: point at a downloaded Antigravity .deb to auto-install on Linux.
LINUX_ANTIGRAVITY_DEB_URL="${LINUX_ANTIGRAVITY_DEB_URL:-}"

# Internal/testing only flag.
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        *) ;;
    esac
    shift
done

# --------------------------------------------------------------------------
# Pretty output
# --------------------------------------------------------------------------
if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_GRAY=$'\033[90m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_GRAY=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
CHECK=$'\xe2\x9c\x93'   # check mark
CROSS=$'\xe2\x9c\x97'   # ballot x

banner() {
    local rule; rule="$(printf '\xe2\x94\x80%.0s' $(seq 1 52))"
    printf '\n  %sClaude Dev Setup%s\n' "$C_CYAN" "$C_RESET"
    printf '  %sGetting your computer ready to build with Claude%s\n' "$C_GRAY" "$C_RESET"
    printf '  %s%s%s\n\n' "$C_GRAY" "$rule" "$C_RESET"
}

rule_line() { printf '  %s%s%s\n' "$C_GRAY" "$(printf '\xe2\x94\x80%.0s' $(seq 1 52))" "$C_RESET"; }

# A finished checklist line: green check (or red cross) + name + soft description.
check_row() {
    local ok="$1" name="$2" desc="$3" mark color
    if [ "$ok" = 1 ]; then mark="$CHECK"; color="$C_GREEN"; else mark="$CROSS"; color="$C_RED"; fi
    printf '  %s%s%s  %-19s%s%s%s\n' "$color" "$mark" "$C_RESET" "$name" "$C_GRAY" "$desc" "$C_RESET"
}

note() { printf '  %s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
has_command() { command -v "$1" >/dev/null 2>&1; }

# Run a command with root privileges: directly when already root, via sudo
# otherwise (credentials are pre-authorized once in main).
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif has_command sudo; then
        sudo "$@"
    else
        return 1
    fi
}

# Run a command behind a clean inline spinner, hiding its output. In a real
# terminal we capture output and animate; otherwise (CI/logs) we run it plainly
# so the output stays visible. Always returns 0 - the final checklist is the
# source of truth for what actually succeeded.
run_quiet() {
    local label="$1"; shift
    $DRY_RUN && return 0
    if [ -t 1 ]; then
        local log; log="$(mktemp)"
        ( "$@" >"$log" 2>&1 ) &
        local pid=$! frames="|/-\\" i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s  %s...   ' "${frames:$((i % 4)):1}" "$label"
            i=$((i + 1)); sleep 0.12
        done
        printf '\r%*s\r' 64 ''
        wait "$pid" 2>/dev/null || true
        rm -f "$log"
    else
        printf '  %s...\n' "$label"
        "$@" || true
    fi
    return 0
}

OS=""
detect_os() {
    case "$(uname -s)" in
        Darwin) OS="mac" ;;
        Linux) OS="linux" ;;
        *) note "Sorry, this only supports macOS and Linux."; exit 1 ;;
    esac
}

PKG=""
detect_linux_pkg() {
    for p in apt-get dnf yum pacman zypper apk; do
        if has_command "$p"; then PKG="$p"; return 0; fi
    done
    PKG=""
}

# Ask for the password once up front (so the spinner never hides a sudo prompt),
# then keep the credentials warm in the background during the install.
SUDO_KEEPALIVE_PID=""
ensure_sudo() {
    $DRY_RUN && return 0
    [ "$(id -u)" -eq 0 ] && return 0
    has_command sudo || return 0
    [ "$OS" = mac ] && has_command brew && return 0   # brew needs no sudo
    note "You may be asked for your password to install software."
    sudo -v 2>/dev/null || true
    ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
}

# Quietly make sure a directory is on PATH (session + shell rc), once.
persist_path() {
    local dir="$1" rc
    [ -z "$dir" ] && return 0
    $DRY_RUN && return 0
    local files=()
    case "${SHELL:-}" in
        *zsh) files+=("$HOME/.zshrc") ;;
        *bash) files+=("$HOME/.bashrc") ;;
    esac
    files+=("$HOME/.profile")
    for rc in "${files[@]}"; do
        [ -f "$rc" ] || touch "$rc"
        if ! grep -qF "$dir" "$rc" 2>/dev/null; then
            # $PATH is written literally on purpose: it must expand at shell
            # startup, not now.
            # shellcheck disable=SC2016
            printf '\n# claude-dev-setup\nexport PATH="%s:$PATH"\n' "$dir" >> "$rc"
        fi
    done
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
}

pkg_install() {
    local pkg="$1"
    case "$PKG" in
        apt-get) as_root apt-get install -y "$pkg" ;;
        dnf) as_root dnf install -y "$pkg" ;;
        yum) as_root yum install -y "$pkg" ;;
        pacman) as_root pacman -S --needed --noconfirm "$pkg" ;;
        zypper) as_root zypper install -y "$pkg" ;;
        apk) as_root apk add "$pkg" ;;
        *) return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------
install_git() {
    if has_command git; then
        [ "$OS" = mac ] && has_command brew && run_quiet "Checking Git" brew upgrade git
        return 0
    fi
    if [ "$OS" = mac ]; then
        if has_command brew; then run_quiet "Installing Git" brew install git
        else note "Opening Apple developer tools installer (a window may appear)."; xcode-select --install >/dev/null 2>&1 || true; fi
    else
        run_quiet "Installing Git" pkg_install git
    fi
}

# --------------------------------------------------------------------------
# Node.js LTS
# --------------------------------------------------------------------------
install_node_mac_pkg() {
    local ver arch pkg
    ver="$(curl -fsSL https://nodejs.org/dist/index.json \
        | tr -d ' ' | tr '{' '\n' \
        | grep '"lts":"' | grep -v '"lts":false' \
        | head -1 | sed -E 's/.*"version":"(v[0-9.]+)".*/\1/')"
    [ -z "$ver" ] && return 1
    pkg="$(mktemp -d)/node-${ver}.pkg"
    arch="$(uname -m)"; : "$arch"
    curl -fsSL "https://nodejs.org/dist/${ver}/node-${ver}.pkg" -o "$pkg"
    as_root installer -pkg "$pkg" -target /
}

install_node_nodesource() {
    local setup_url="$1" setup
    setup="$(mktemp -d)/nodesource_setup.sh"
    curl -fsSL "$setup_url" -o "$setup"
    as_root bash "$setup"
    as_root "$PKG" install -y nodejs
}

install_node() {
    if has_command node; then
        [ "$OS" = mac ] && has_command brew && run_quiet "Checking Node.js" brew upgrade node
        return 0
    fi
    if [ "$OS" = mac ]; then
        if has_command brew; then run_quiet "Installing Node.js" brew install node
        else run_quiet "Installing Node.js" install_node_mac_pkg; fi
    else
        case "$PKG" in
            apt-get) run_quiet "Installing Node.js" install_node_nodesource 'https://deb.nodesource.com/setup_lts.x' ;;
            dnf|yum) run_quiet "Installing Node.js" install_node_nodesource 'https://rpm.nodesource.com/setup_lts.x' ;;
            pacman) run_quiet "Installing Node.js" bash -c 'pkg_install nodejs && pkg_install npm' ;;
            zypper) run_quiet "Installing Node.js" pkg_install nodejs ;;
            apk) run_quiet "Installing Node.js" bash -c 'pkg_install nodejs && pkg_install npm' ;;
        esac
    fi
}

# --------------------------------------------------------------------------
# Antigravity IDE
# --------------------------------------------------------------------------
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

install_antigravity_mac_dmg() {
    local arch url dmg vol
    arch="$(uname -m)"
    case "$arch" in arm64) arch="arm" ;; x86_64) arch="x64" ;; esac
    url="https://storage.googleapis.com/antigravity-public/antigravity-hub/${ANTIGRAVITY_MAC_VER1}-${ANTIGRAVITY_MAC_VER2}/darwin-${arch}/Antigravity.dmg"
    dmg="$(mktemp -d)/Antigravity.dmg"
    curl -fsSL "$url" -o "$dmg"
    vol="$(hdiutil attach "$dmg" -nobrowse -quiet | grep -o '/Volumes/.*' | head -1)"
    [ -z "$vol" ] && return 1
    cp -R "$vol/Antigravity.app" /Applications/ 2>/dev/null || as_root cp -R "$vol/Antigravity.app" /Applications/
    hdiutil detach "$vol" -quiet || true
}

install_antigravity_deb() {
    local deb
    deb="$(mktemp -d)/antigravity.deb"
    curl -fsSL "$LINUX_ANTIGRAVITY_DEB_URL" -o "$deb"
    as_root dpkg -i "$deb" || as_root apt-get install -f -y
}

install_antigravity() {
    if find_antigravity_cli >/dev/null 2>&1; then
        [ "$OS" = mac ] && has_command brew && run_quiet "Checking Antigravity" brew upgrade --cask antigravity
        return 0
    fi
    if [ "$OS" = mac ]; then
        if has_command brew; then run_quiet "Installing Antigravity" brew install --cask antigravity
        else run_quiet "Installing Antigravity" install_antigravity_mac_dmg; fi
    else
        if [ -n "$LINUX_ANTIGRAVITY_DEB_URL" ] && [ "$PKG" = "apt-get" ]; then
            run_quiet "Installing Antigravity" install_antigravity_deb
        fi
        # Otherwise Antigravity is left for the user to install (see final note).
    fi
}

# --------------------------------------------------------------------------
# Extensions
# --------------------------------------------------------------------------
# Antigravity's CLI prints a harmless analytics warning to stderr; its real
# output goes to stdout. Drop stderr to read the clean list of extension ids.
antigravity_extensions() {
    local cli="$1"
    [ -z "$cli" ] && return 0
    "$cli" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

ext_is_installed() {
    local cli="$1" id_lc="$2"
    antigravity_extensions "$cli" | grep -qx "$id_lc"
}

install_one_extension() {
    local ext_id="$1" cli="$2" vsix_url="$3" existing="$4" id_lc
    id_lc="$(printf '%s' "$ext_id" | tr '[:upper:]' '[:lower:]')"
    printf '%s\n' "$existing" | grep -qx "$id_lc" && return 0
    "$cli" --install-extension "$ext_id" --force >/dev/null 2>&1 || true
    ext_is_installed "$cli" "$id_lc" && return 0
    if [ -n "$vsix_url" ]; then
        local vsix; vsix="$(mktemp -d)/ext.vsix"
        if curl -fsSL "$vsix_url" -o "$vsix" 2>/dev/null; then
            "$cli" --install-extension "$vsix" --force >/dev/null 2>&1 || true
        fi
    fi
}

install_extensions() {
    $DRY_RUN && return 0
    local cli existing
    cli="$(find_antigravity_cli 2>/dev/null || true)"
    [ -z "$cli" ] && return 0
    existing="$(antigravity_extensions "$cli")"
    run_quiet "Adding Claude to the editor" install_one_extension "$EXT_CLAUDE_CODE" "$cli" "" "$existing"
    run_quiet "Adding Hebrew/Arabic support" install_one_extension "$EXT_CLAUDE_RTL" "$cli" "$RTL_VSIX_URL" "$existing"
}

# --------------------------------------------------------------------------
# Claude Code CLI
# --------------------------------------------------------------------------
claude_install_cmd() { curl -fsSL https://claude.ai/install.sh | bash; }

install_claude_cli() {
    if has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; then
        run_quiet "Checking Claude" claude update
        persist_path "$CLAUDE_BIN_DIR"
        return 0
    fi
    run_quiet "Installing Claude" claude_install_cmd
    persist_path "$CLAUDE_BIN_DIR"
}

# --------------------------------------------------------------------------
# Results checklist
# --------------------------------------------------------------------------
show_results() {
    local ok_git=0 ok_node=0 ok_claude=0 ok_ag=0 ok_code=0 ok_rtl=0 cli
    has_command git && ok_git=1
    has_command node && ok_node=1
    { has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; } && ok_claude=1
    cli="$(find_antigravity_cli 2>/dev/null || true)"
    [ -n "$cli" ] && ok_ag=1
    if [ -n "$cli" ]; then
        local exts; exts="$(antigravity_extensions "$cli")"
        printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_CODE" | tr '[:upper:]' '[:lower:]')" && ok_code=1
        printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_RTL" | tr '[:upper:]' '[:lower:]')" && ok_rtl=1
    fi

    echo
    check_row "$ok_git" "Git" "keeps track of your code"
    check_row "$ok_node" "Node.js" "runs your tools"
    check_row "$ok_ag" "Antigravity" "your code editor"
    check_row "$ok_code" "Claude in editor" "chat with Claude while you build"
    check_row "$ok_rtl" "Hebrew support" "right-to-left text in the editor"
    check_row "$ok_claude" "Claude command" "use Claude from the terminal"
    rule_line

    if [ "$ok_git" = 1 ] && [ "$ok_node" = 1 ] && [ "$ok_ag" = 1 ] && [ "$ok_code" = 1 ] && [ "$ok_rtl" = 1 ] && [ "$ok_claude" = 1 ]; then
        printf '\n  %sYou are all set. Everything is installed and ready to go.%s\n\n' "$C_GREEN" "$C_RESET"
    else
        echo
        if [ "$OS" = linux ] && [ "$ok_ag" = 0 ]; then
            note "Almost there. On Linux, install the Antigravity editor yourself:"
            note "  https://antigravity.google/download/linux"
            note "Then run this command again to add the Claude extensions."
        else
            note "Almost there. A few things did not finish installing."
            note "Please run this command again. If it keeps happening, restart and retry."
            if { [ "$ok_code" = 0 ] || [ "$ok_rtl" = 0 ]; } && [ "$ok_ag" = 1 ]; then
                note "If Antigravity is new, open it once (sign in with Google), then run this again."
            fi
        fi
        echo
    fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    detect_os
    [ "$OS" = linux ] && detect_linux_pkg

    banner
    $DRY_RUN && note "DRY RUN - nothing will be installed."

    ensure_sudo
    install_git || true
    install_node || true
    install_antigravity || true
    install_extensions || true
    install_claude_cli || true
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi

    show_results
}

main
