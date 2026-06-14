# Claude Dev Setup

**Everything you need to start building with Claude, installed by one command.**

It sets up Git, Node.js, the Antigravity editor, the Claude extensions, and the `claude` command line tool, on Windows, macOS, and Linux. Re-running is always safe.

[![CI](https://github.com/AdirYad/claude-dev-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/AdirYad/claude-dev-setup/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux-blue)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## Install

**Windows** (open PowerShell and paste):

```powershell
irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/install.ps1 | iex
```

**macOS / Linux** (open Terminal and paste):

```bash
curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/install.sh | bash
```

That is the whole thing. You will see a checklist of green checks when it is done.

---

## What it installs

| | Software | What it is |
|---|----------|------------|
| 📦 | **Git** | Keeps track of your code. Required by most modern dev tools. |
| ⚙️ | **Node.js (LTS)** | The engine that runs a huge amount of dev tooling, plus `npm`. |
| ✨ | **Antigravity** | Google's AI code editor (built on VS Code). This is where you write code. |
| 💬 | **Claude Code extension** | Chat with Claude and let it edit your project from inside the editor. |
| 🔤 | **Claude RTL Code extension** | Right to left support, so Hebrew and Arabic render and edit correctly. |
| ⌨️ | **Claude Code CLI** | The `claude` command for your terminal. Run Claude from any project folder. |

---

## Good to know

- **Safe to re-run.** Each component is checked first. Missing ones are installed, ones that have an easy upgrade are upgraded, the rest are left alone.
- **Your terminal just works.** Every tool is added to your PATH (permanently and for the current session), so `claude`, `node`, and `git` work in a fresh terminal. On Windows the PowerShell execution policy is relaxed for your user only if it was blocking scripts.
- **Antigravity sign in.** Antigravity needs a Google account. You sign in once the first time you open it. If you have never opened it, the two extensions are skipped, so open it once and run the command again.
- **No Homebrew is installed for you.** On macOS, Homebrew is used only if you already have it. Otherwise the official downloads from nodejs.org and Google are used.
- **Linux and Antigravity.** The editor is not installed automatically on Linux. Get it from [antigravity.google/download/linux](https://antigravity.google/download/linux). Everything else installs normally.
- **Claude account.** Claude Code needs a Pro, Max, Team, Enterprise, or Console account. You log in the first time you run `claude`.

---

## Uninstall

Removes the Claude Code CLI and the two Antigravity extensions. It keeps git, Node.js, and Antigravity, since other software may rely on them.

**Windows**

```powershell
irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/uninstall.ps1 | iex
```

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/uninstall.sh | bash
```

---

## License

[MIT](LICENSE) © Adir Yadaev
