# claude-dev-setup — Design

One command sets up a complete Claude Code development environment on **Windows, macOS, and Linux**.

## What it installs

| # | Component | Why |
|---|-----------|-----|
| 1 | **git** | version control |
| 2 | **Node.js (LTS) + npm** | JS runtime / tooling |
| 3 | **Antigravity IDE** (Google) | the editor |
| 4 | **Claude Code extension** (`Anthropic.claude-code`) | Claude inside Antigravity |
| 5 | **Claude RTL Code extension** (`AdirYad.claude-rtl-code`) | RTL support in the editor |
| 6 | **Claude Code CLI** | `claude` in the terminal |

## Principles

- **Idempotent / install-once.** Every component checks if it is already present *first*. If installed → **skip** (no reinstall). Upgrades happen **only** with the explicit `--upgrade` flag.
- **No Homebrew auto-install.** On macOS we use Homebrew *only if the user already has it* (fast path). Otherwise we use official direct downloads. We never install Homebrew for the user.
- **Self-contained scripts.** `install.ps1` and `install.sh` have no runtime file dependencies, so the `curl | bash` / `irm | iex` one-liners work with zero setup (same model as rustup/homebrew).
- **PATH is guaranteed.** Each tool's bin directory is added to PATH **persistently and for the current session**, so `claude`, `node`, `git`, and `antigravity` work in a fresh terminal — not just the one that ran the installer.
- **Verifiable.** A `--verify` doctor step opens a *fresh* shell and runs each tool's `--version`, proving PATH + ExecutionPolicy actually took effect.

## Platform matrix

| Step | Windows | macOS | Linux |
|------|---------|-------|-------|
| Package manager | winget (built-in) | brew **if present**, else direct | apt / dnf / pacman / zypper / apk |
| git | `winget Git.Git` | brew, else Xcode CLT | distro pkg |
| Node LTS | `winget OpenJS.NodeJS.LTS` | brew, else official `.pkg` | NodeSource, else distro pkg |
| Antigravity | `winget Google.Antigravity` (silent) | brew cask, else `.dmg` | apt repo, else `.deb`, else tarball |
| Extensions | `antigravity --install-extension <id>` | same | same |
| Claude CLI | `irm https://claude.ai/install.ps1 \| iex` | `curl -fsSL https://claude.ai/install.sh \| bash` | same |

## Antigravity specifics

- Antigravity is a VS Code fork → it uses the **open-vsx** registry and its **own** CLI binary (NOT `code`).
- CLI locations probed (in order): `PATH`, then known per-OS paths:
  - macOS: `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`
  - Windows: `%LOCALAPPDATA%\Programs\Antigravity\bin\antigravity.cmd`
  - Linux: `/usr/share/antigravity/bin/antigravity`, `/usr/bin/antigravity`
- Extension install uses `--install-extension <id>`; if the open-vsx fetch fails we fall back to downloading the VSIX and installing from the local file.
  - Claude RTL pinned VSIX: `https://open-vsx.org/api/AdirYad/claude-rtl-code/<ver>/file/AdirYad.claude-rtl-code-<ver>.vsix`
- Guard for [anthropics/claude-code#22360](https://github.com/anthropics/claude-code/issues/22360): the Claude Code companion extension is installed **explicitly** before first CLI launch; the verify step reports if Antigravity is missing it.

## Windows specifics

- After Node is installed, npm-installed `.ps1` shims (and other tools) fail to run under the default Restricted/AllSigned PowerShell policy. The installer checks `Get-ExecutionPolicy -Scope CurrentUser` and, only if restrictive, runs `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`. Idempotent.
- Claude CLI binary: `%USERPROFILE%\.local\bin\claude.exe` → that dir is added to the **User** PATH.

## Environment / secrets

- Claude Code authenticates by interactive login (Pro/Max/Team/Console). **No API key required by default.**
- Optional: if `--api-key <key>` is passed (or `ANTHROPIC_API_KEY` is already set), the installer persists it to the user environment. Otherwise this step is skipped.

## Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | print every action, install nothing |
| `--upgrade` | upgrade components that are already installed |
| `--skip a,b` | skip named components (`git,node,antigravity,extensions,claude`) |
| `--verify` | run only the doctor / verification step |
| `--api-key <k>` | persist an Anthropic API key to the environment |
| `--help` | usage |

(PowerShell uses `-DryRun`, `-Upgrade`, `-Skip`, `-Verify`, `-ApiKey`, `-Help`.)

## Verification strategy

- **Local (your machine):** `--dry-run` + `bash -n` / `shellcheck` (sh) + PSScriptAnalyzer (ps1). No real installs.
- **Cross-OS truth:** GitHub Actions matrix (windows / macos / ubuntu) runs each installer in `--dry-run` plus linters on every push. This is how macOS/Linux behaviour is proven without a local machine.

## Repo layout

```
claude-dev-setup/
  README.md                  one-liners + manual steps + troubleshooting
  install.ps1                Windows entry (self-contained)
  install.sh                 macOS + Linux entry (self-contained, OS-detecting)
  docs/DESIGN.md             this file
  tests/smoke.ps1            runs install.ps1 -DryRun and asserts exit 0
  tests/smoke.sh             runs install.sh --dry-run and asserts exit 0
  .github/workflows/ci.yml   dry-run matrix + shellcheck + PSScriptAnalyzer
  PSScriptAnalyzerSettings.psd1
  LICENSE  .gitignore  .editorconfig
```
