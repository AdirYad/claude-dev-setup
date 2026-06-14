#!/usr/bin/env bash
#
# claude-dev-setup — macOS + Linux
#
# Installs (idempotently): git, Node.js LTS, Antigravity IDE, the Claude Code
# and Claude RTL Code extensions for Antigravity, and the Claude Code CLI.
# Already-installed components are skipped unless --upgrade is given.
#
#   curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.sh | bash
#
set -euo pipefail

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
# Flags
# --------------------------------------------------------------------------
DRY_RUN=false
UPGRADE=false
VERIFY_ONLY=false
API_KEY=""
SKIP=""

usage() {
    cat <<'EOF'
claude-dev-setup (macOS + Linux)

Usage:
  install.sh [--dry-run] [--upgrade] [--skip git,node,...] [--verify] [--api-key KEY] [--help]

Flags:
  --dry-run     Print actions, change nothing.
  --upgrade     Upgrade components already installed.
  --skip        Comma list: git,node,antigravity,extensions,claude.
  --verify      Run only the verification step.
  --api-key     Persist an Anthropic API key to your shell profile.
  --help        This help.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --upgrade) UPGRADE=true ;;
        --verify) VERIFY_ONLY=true ;;
        --skip) SKIP="${2:-}"; shift ;;
        --skip=*) SKIP="${1#*=}" ;;
        --api-key) API_KEY="${2:-}"; shift ;;
        --api-key=*) API_KEY="${1#*=}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown flag: $1" >&2; usage; exit 2 ;;
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

should_skip() {
    case ",$SKIP," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
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
        apt-get) step_run "apt-get install $pkg" sudo apt-get install -y "$pkg" ;;
        dnf) step_run "dnf install $pkg" sudo dnf install -y "$pkg" ;;
        yum) step_run "yum install $pkg" sudo yum install -y "$pkg" ;;
        pacman) step_run "pacman -S $pkg" sudo pacman -S --needed --noconfirm "$pkg" ;;
        zypper) step_run "zypper install $pkg" sudo zypper install -y "$pkg" ;;
        apk) step_run "apk add $pkg" sudo apk add "$pkg" ;;
        *) err "no supported package manager found for $pkg"; return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------
install_git() {
    should_skip git && { skip "git (skipped)"; return 0; }
    step "git"
    if has_command git; then
        if $UPGRADE && [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade git" brew upgrade git || true
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
            info "finish the Xcode CLT prompt, then re-run with --skip node,antigravity,extensions,claude"
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
    sudo installer -pkg "$pkg" -target /
}

install_node() {
    should_skip node && { skip "node (skipped)"; return 0; }
    step "Node.js LTS"
    if has_command node; then
        if $UPGRADE && [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade node" brew upgrade node || true
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
                step_run "NodeSource setup + apt install nodejs" bash -c \
                    'curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs'
                ;;
            dnf|yum)
                step_run "NodeSource setup + ${PKG} install nodejs" bash -c \
                    "curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - && sudo $PKG install -y nodejs"
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
    cp -R "$vol/Antigravity.app" /Applications/ 2>/dev/null || sudo cp -R "$vol/Antigravity.app" /Applications/
    hdiutil detach "$vol" -quiet || true
}

install_antigravity() {
    should_skip antigravity && { skip "Antigravity (skipped)"; return 0; }
    step "Antigravity IDE"
    if find_antigravity_cli >/dev/null 2>&1; then
        if $UPGRADE && [ "$OS" = mac ] && has_command brew; then
            step_run "brew upgrade --cask antigravity" brew upgrade --cask antigravity || true
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
            local deb
            deb="$(mktemp -d)/antigravity.deb"
            step_run "download + dpkg -i Antigravity .deb" bash -c \
                "curl -fsSL '$LINUX_ANTIGRAVITY_DEB_URL' -o '$deb' && sudo dpkg -i '$deb' || sudo apt-get install -f -y"
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
# warning and may exit non-zero even when the extension installs fine, so judge
# success by the output text, not the exit code. --install-extension is itself
# idempotent (no-op when already current); its --list-extensions is unreliable,
# so there is no separate "already installed" pre-check.
ext_via_cli() {
    local cli="$1" target="$2" out
    out="$("$cli" --install-extension "$target" --force 2>&1 || true)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/   /'
    printf '%s' "$out" | grep -qiE 'successfully installed|already installed'
}

install_extension() {
    local ext_id="$1" cli="$2" vsix_url="$3"

    if [ -z "$cli" ]; then dry "install extension $ext_id via Antigravity CLI"; return 0; fi
    if $DRY_RUN; then dry "install extension $ext_id (open-vsx, VSIX fallback)"; return 0; fi

    if ext_via_cli "$cli" "$ext_id"; then
        ok "$ext_id installed"; return 0
    fi
    warn "registry install unconfirmed for $ext_id"

    if [ -n "$vsix_url" ]; then
        local vsix
        vsix="$(mktemp -d)/ext.vsix"
        if curl -fsSL "$vsix_url" -o "$vsix" && ext_via_cli "$cli" "$vsix"; then
            ok "$ext_id installed from VSIX"
        else
            err "failed to install $ext_id"
        fi
    else
        err "failed to confirm install of $ext_id"
    fi
}

install_extensions() {
    should_skip extensions && { skip "extensions (skipped)"; return 0; }
    step "Antigravity extensions"
    local cli=""
    cli="$(find_antigravity_cli 2>/dev/null || true)"
    if [ -z "$cli" ] && ! $DRY_RUN; then
        warn "Antigravity CLI not found; open Antigravity once, then re-run with --skip git,node,antigravity,claude"
        return 0
    fi
    install_extension "$EXT_CLAUDE_CODE" "$cli" ""
    install_extension "$EXT_CLAUDE_RTL" "$cli" "$RTL_VSIX_URL"
}

# --------------------------------------------------------------------------
# Claude Code CLI
# --------------------------------------------------------------------------
install_claude_cli() {
    should_skip claude && { skip "Claude CLI (skipped)"; return 0; }
    step "Claude Code CLI"
    if has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; then
        if $UPGRADE; then
            step_run "claude update" claude update || true
        else
            skip "Claude CLI already installed"
        fi
        persist_path "$CLAUDE_BIN_DIR"
        return 0
    fi
    step_run "install Claude Code CLI (claude.ai/install.sh)" bash -c \
        'curl -fsSL https://claude.ai/install.sh | bash'
    # Native installer drops claude in ~/.local/bin — guarantee PATH.
    persist_path "$CLAUDE_BIN_DIR"
    if has_command claude || [ -x "$CLAUDE_BIN_DIR/claude" ]; then ok "Claude CLI installed"; fi
}

# --------------------------------------------------------------------------
# Optional API key
# --------------------------------------------------------------------------
set_api_key() {
    local key="${API_KEY:-${ANTHROPIC_API_KEY:-}}"
    [ -z "$key" ] && return 0
    step "Anthropic API key"
    local rc="$HOME/.profile"
    case "${SHELL:-}" in
        *zsh) rc="$HOME/.zshrc" ;;
        *bash) rc="$HOME/.bashrc" ;;
    esac
    if grep -q 'ANTHROPIC_API_KEY' "$rc" 2>/dev/null; then
        skip "ANTHROPIC_API_KEY already in $(basename "$rc")"
    elif $DRY_RUN; then
        dry "persist ANTHROPIC_API_KEY to $(basename "$rc")"
    else
        printf '\n# claude-dev-setup\nexport ANTHROPIC_API_KEY="%s"\n' "$key" >> "$rc"
        export ANTHROPIC_API_KEY="$key"
        ok "ANTHROPIC_API_KEY set in $(basename "$rc")"
    fi
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
        # Antigravity's --list-extensions is unreliable (analytics dependency
        # error), so extensions cannot be confirmed from the CLI.
        report_row "extensions" "INFO" "installed via CLI; confirm in Antigravity Extensions panel"
    else
        report_row "antigravity" "MISSING" ""
        if [ "$OS" = mac ]; then missing=$((missing + 1)); fi
    fi

    echo
    if [ "$missing" -gt 0 ]; then
        warn "$missing required component(s) missing — open a NEW terminal (PATH applies to new shells) and re-run with --verify."
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

    if $VERIFY_ONLY; then verify || exit 1; exit 0; fi

    install_git
    install_node
    install_antigravity
    install_extensions
    install_claude_cli
    set_api_key

    echo
    if verify; then
        printf '%sDone. Open a NEW terminal and run: claude%s\n' "$C_GREEN" "$C_RESET"
    else
        printf '%sFinished with warnings - see above.%s\n' "$C_YELLOW" "$C_RESET"
    fi
}

main
