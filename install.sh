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

# --------------------------------------------------------------------------
# Flags (internal/testing only: --dry-run. Users never need a flag.)
# --------------------------------------------------------------------------
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        *) ;;
    esac
    shift
done

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_GRAY=$'\033[90m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_MAGENTA=$'\033[35m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_GRAY=""; C_YELLOW=""; C_RED=""; C_MAGENTA=""; C_RESET=""
fi

step() { printf '\n%s=> %s%s\n' "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf '   %s[ok]   %s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
skip() { printf '   %s[skip] %s%s\n' "$C_GRAY" "$1" "$C_RESET"; }
warn() { printf '   %s[warn] %s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
err()  { printf '   %s[err]  %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }
dry()  { printf '   %s[dry]  would %s%s\n' "$C_MAGENTA" "$1" "$C_RESET"; }
info() { printf '   %s\n' "$1"; }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
has_command() { command -v "$1" >/dev/null 2>&1; }

# Run a command with root privileges: directly when already root (e.g. inside a
# container), via sudo otherwise. Fails clearly when neither is possible.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif has_command sudo; then
        sudo "$@"
    else
        err "this step needs root (install sudo or run as root): $*"
        return 1
    fi
}

# step_run "description" cmd args...   (respects --dry-run)
step_run() {
    local desc="$1"; shift
    if $DRY_RUN; then dry "$desc"; return 0; fi
    "$@"
}

OS=""
detect_os() {
    case "$(uname -s)" in
        Darwin) OS="mac" ;;
        Linux) OS="linux" ;;
        *) err "unsupported OS: $(uname -s)"; exit 1 ;;
    esac
}

PKG=""
detect_linux_pkg() {
    for p in apt-get dnf yum pacman zypper apk; do
        if has_command "$p"; then PKG="$p"; return 0; fi
    done
    PKG=""
}

# Persist a directory onto PATH (session + shell rc) once.
persist_path() {
    local dir="$1" rc
    [ -z "$dir" ] && return 0

    local files=()
    case "${SHELL:-}" in
        *zsh) files+=("$HOME/.zshrc") ;;
        *bash) files+=("$HOME/.bashrc") ;;
    esac
    files+=("$HOME/.profile")

    for rc in "${files[@]}"; do
        if [ ! -f "$rc" ]; then
            $DRY_RUN || touch "$rc"
        fi
        if grep -qF "$dir" "$rc" 2>/dev/null; then
            skip "PATH in $(basename "$rc") already has $dir"
        elif $DRY_RUN; then
            dry "add $dir to PATH in $(basename "$rc")"
        else
            # $PATH is written literally on purpose: it must expand at shell
            # startup, not now.
            # shellcheck disable=SC2016
            printf '\n# claude-dev-setup\nexport PATH="%s:$PATH"\n' "$dir" >> "$rc"
            ok "added $dir to PATH in $(basename "$rc")"
        fi
    done

    case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$dir:$PATH"; export PATH ;;
    esac
}

# Install a Linux package using whatever package manager exists.
linux_pkg_install() {
    local pkg="$1"
    case "$PKG" in
        apt-get) step_run "apt-get install $pkg" as_root apt-get install -y "$pkg" ;;
        dnf) step_run "dnf install $pkg" as_root dnf install -y "$pkg" ;;
        yum) step_run "yum install $pkg" as_root yum install -y "$pkg" ;;
        pacman) step_run "pacman -S $pkg" as_root pacman -S --needed --noconfirm "$pkg" ;;
        zypper) step_run "zypper install $pkg" as_root zypper install -y "$pkg" ;;
        apk) step_run "apk add $pkg" as_root apk add "$pkg" ;;
        *) err "no supported package manager found for $pkg"; return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------
install_git() {
    step "git"
    if has_command git; then
        if [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade git" brew upgrade git || true
            ok "git up to date"
        else
            skip "git already installed ($(git --version 2>/dev/null))"
        fi
        return 0
    fi
    if [ "$OS" = mac ]; then
        if has_command brew; then
            step_run "brew install git" brew install git
        else
            warn "git missing and no Homebrew; triggering Xcode Command Line Tools"
            step_run "xcode-select --install" xcode-select --install || true
            info "finish the Xcode CLT prompt, then re-run"
        fi
    else
        linux_pkg_install git
    fi
    if has_command git; then ok "git installed"; fi
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
    if [ -z "$ver" ]; then
        err "could not resolve latest Node LTS version"
        return 1
    fi
    pkg="$(mktemp -d)/node-${ver}.pkg"
    arch="$(uname -m)"
    info "downloading Node ${ver} (${arch}) official pkg"
    curl -fsSL "https://nodejs.org/dist/${ver}/node-${ver}.pkg" -o "$pkg"
    as_root installer -pkg "$pkg" -target /
}

# NodeSource setup script (run as root), then install nodejs. Avoids piping
# curl straight into sudo so it works as root (no sudo) and as a normal user.
install_node_nodesource() {
    local setup_url="$1" setup
    setup="$(mktemp -d)/nodesource_setup.sh"
    curl -fsSL "$setup_url" -o "$setup"
    as_root bash "$setup"
    as_root "$PKG" install -y nodejs
}

install_node() {
    step "Node.js LTS"
    if has_command node; then
        if [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade node" brew upgrade node || true
            ok "Node up to date"
        else
            skip "Node already installed ($(node --version 2>/dev/null))"
        fi
        return 0
    fi
    if [ "$OS" = mac ]; then
        if has_command brew; then
            step_run "brew install node" brew install node
        else
            step_run "install Node LTS from nodejs.org" install_node_mac_pkg
        fi
    else
        case "$PKG" in
            apt-get)
                step_run "NodeSource setup + apt install nodejs" \
                    install_node_nodesource 'https://deb.nodesource.com/setup_lts.x'
                ;;
            dnf|yum)
                step_run "NodeSource setup + ${PKG} install nodejs" \
                    install_node_nodesource 'https://rpm.nodesource.com/setup_lts.x'
                ;;
            pacman) linux_pkg_install nodejs && linux_pkg_install npm ;;
            zypper) linux_pkg_install nodejs ;;
            apk) linux_pkg_install nodejs && linux_pkg_install npm ;;
            *) err "no package manager for Node"; return 1 ;;
        esac
    fi
    if has_command node; then ok "Node installed ($(node --version 2>/dev/null))"; fi
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
    case "$arch" in
        arm64) arch="arm" ;;
        x86_64) arch="x64" ;;
    esac
    url="https://storage.googleapis.com/antigravity-public/antigravity-hub/${ANTIGRAVITY_MAC_VER1}-${ANTIGRAVITY_MAC_VER2}/darwin-${arch}/Antigravity.dmg"
    dmg="$(mktemp -d)/Antigravity.dmg"
    info "downloading Antigravity ($url)"
    curl -fsSL "$url" -o "$dmg"
    vol="$(hdiutil attach "$dmg" -nobrowse -quiet | grep -o '/Volumes/.*' | head -1)"
    if [ -z "$vol" ]; then err "could not mount Antigravity dmg"; return 1; fi
    cp -R "$vol/Antigravity.app" /Applications/ 2>/dev/null || as_root cp -R "$vol/Antigravity.app" /Applications/
    hdiutil detach "$vol" -quiet || true
}

# Download and install an Antigravity .deb (apt systems only).
install_antigravity_deb() {
    local deb
    deb="$(mktemp -d)/antigravity.deb"
    curl -fsSL "$LINUX_ANTIGRAVITY_DEB_URL" -o "$deb"
    as_root dpkg -i "$deb" || as_root apt-get install -f -y
}

install_antigravity() {
    step "Antigravity IDE"
    if find_antigravity_cli >/dev/null 2>&1; then
        if [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade --cask antigravity" brew upgrade --cask antigravity || true
            ok "Antigravity up to date"
        else
            skip "Antigravity already installed"
        fi
        return 0
    fi

    if [ "$OS" = mac ]; then
        if has_command brew; then
            step_run "brew install --cask antigravity" brew install --cask antigravity
        else
            step_run "install Antigravity (dmg)" install_antigravity_mac_dmg
        fi
    else
        # Linux: prefer a user-provided .deb; otherwise guide (we do not add an
        # unverified apt repo / signing key automatically).
        if [ -n "$LINUX_ANTIGRAVITY_DEB_URL" ] && [ "$PKG" = "apt-get" ]; then
            step_run "download + dpkg -i Antigravity .deb" install_antigravity_deb
        else
            warn "Linux: automatic Antigravity install is not enabled by default."
            info "Install it from https://antigravity.google/download/linux (deb / tarball / official apt repo),"
            info "or set LINUX_ANTIGRAVITY_DEB_URL=<deb url> and re-run. Other components are installed normally."
            return 0
        fi
    fi
    if find_antigravity_cli >/dev/null 2>&1; then ok "Antigravity installed"; fi
}

# --------------------------------------------------------------------------
# Extensions
# --------------------------------------------------------------------------
# Antigravity's CLI prints a harmless "antigravityAnalytics ... NOT registered"
# warning to stderr; its real output goes to stdout. Drop stderr to read the
# clean list of installed extension ids, lower-cased for comparison.
antigravity_extensions() {
    local cli="$1"
    [ -z "$cli" ] && return 0
    "$cli" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

# Install an extension and judge success by the output text (the CLI may exit
# non-zero on the harmless warning) or by a re-listing afterwards.
ext_via_cli() {
    local cli="$1" target="$2" id_lc="$3" out
    out="$("$cli" --install-extension "$target" --force 2>&1 || true)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/   /'
    printf '%s' "$out" | grep -qiE 'successfully installed|already installed' && return 0
    antigravity_extensions "$cli" | grep -qx "$id_lc"
}

install_extension() {
    local ext_id="$1" cli="$2" vsix_url="$3" existing="$4" id_lc
    id_lc="$(printf '%s' "$ext_id" | tr '[:upper:]' '[:lower:]')"

    if [ -z "$cli" ]; then dry "install extension $ext_id via Antigravity CLI"; return 0; fi
    if printf '%s\n' "$existing" | grep -qx "$id_lc"; then skip "$ext_id already installed"; return 0; fi
    if $DRY_RUN; then dry "install extension $ext_id (open-vsx, VSIX fallback)"; return 0; fi

    if ext_via_cli "$cli" "$ext_id" "$id_lc"; then
        ok "$ext_id installed"; return 0
    fi
    warn "registry install unconfirmed for $ext_id"

    if [ -n "$vsix_url" ]; then
        local vsix
        vsix="$(mktemp -d)/ext.vsix"
        if curl -fsSL "$vsix_url" -o "$vsix" && ext_via_cli "$cli" "$vsix" "$id_lc"; then
            ok "$ext_id installed from VSIX"
        else
            err "failed to install $ext_id"
        fi
    else
        err "failed to confirm install of $ext_id"
    fi
}

install_extensions() {
    step "Antigravity extensions"
    if $DRY_RUN; then dry "install Claude Code + Claude RTL extensions"; return 0; fi
    local cli existing
    cli="$(find_antigravity_cli 2>/dev/null || true)"
    if [ -z "$cli" ]; then
        warn "Antigravity CLI not found; open Antigravity once, then re-run."
        return 0
    fi
    existing="$(antigravity_extensions "$cli")"
    install_extension "$EXT_CLAUDE_CODE" "$cli" "" "$existing"
    install_extension "$EXT_CLAUDE_RTL" "$cli" "$RTL_VSIX_URL" "$existing"
}

# --------------------------------------------------------------------------
# Claude Code CLI
# --------------------------------------------------------------------------
install_claude_cli() {
    step "Claude Code CLI"
    if has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; then
        step_run "claude update" claude update || true
        persist_path "$CLAUDE_BIN_DIR"
        ok "Claude CLI up to date"
        return 0
    fi
    step_run "install Claude Code CLI (claude.ai/install.sh)" bash -c \
        'curl -fsSL https://claude.ai/install.sh | bash'
    # Native installer drops claude in ~/.local/bin - guarantee PATH.
    persist_path "$CLAUDE_BIN_DIR"
    if has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; then ok "Claude CLI installed"; fi
}

# --------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------
report_row() { printf '   %-13s %-9s %s\n' "$1" "$2" "${3:-}"; }

verify() {
    step "Verifying"
    local missing=0 v cli

    for tool in git node npm claude; do
        if has_command "$tool"; then
            v="$("$tool" --version 2>/dev/null | head -1 || true)"
            report_row "$tool" "OK" "$v"
        else
            report_row "$tool" "MISSING" ""
            missing=$((missing + 1))
        fi
    done

    cli="$(find_antigravity_cli 2>/dev/null || true)"
    if [ -n "$cli" ]; then
        report_row "antigravity" "OK" "$cli"
        local exts hc=no hr=no
        exts="$(antigravity_extensions "$cli")"
        if printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_CODE" | tr '[:upper:]' '[:lower:]')"; then hc=yes; fi
        if printf '%s\n' "$exts" | grep -qx "$(printf '%s' "$EXT_CLAUDE_RTL" | tr '[:upper:]' '[:lower:]')"; then hr=yes; fi
        report_row "extensions" "INFO" "claude-code=$hc rtl=$hr"
    else
        report_row "antigravity" "MISSING" ""
        if [ "$OS" = mac ]; then missing=$((missing + 1)); fi
    fi

    echo
    if [ "$missing" -gt 0 ]; then
        warn "$missing required component(s) missing - open a NEW terminal (PATH applies to new shells) and re-run."
        return 1
    fi
    ok "all required components present"
    return 0
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    detect_os
    [ "$OS" = linux ] && detect_linux_pkg

    printf '%sclaude-dev-setup (%s)%s\n' "$C_RESET" "$OS" "$C_RESET"
    $DRY_RUN && warn "DRY RUN - nothing will be installed"

    install_git
    install_node
    install_antigravity
    install_extensions
    install_claude_cli

    echo
    if verify; then
        printf '%sDone. Open a NEW terminal and run: claude%s\n' "$C_GREEN" "$C_RESET"
    else
        printf '%sFinished with warnings - see above.%s\n' "$C_YELLOW" "$C_RESET"
    fi
}

main
