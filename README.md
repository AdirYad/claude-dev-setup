# claude-dev-setup

One click sets up a complete Claude Code development environment on Windows, macOS, and Linux.

## Easiest way (no terminal)

Just download one file and double-click it. It opens a window and installs everything for you.

- **Windows:** download **[install.bat](https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.bat)**, then double-click it.
  The first time, Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**.
- **macOS:** download **[install.command](https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.command)**, then **right-click it and choose Open** (the first time only).

That is it. A window opens, everything installs, and you see a checklist of green checks when it is done.

## For the terminal (alternative)

If you prefer the terminal, paste one line:

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex
```

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.sh | bash
```

You can run the command again any time. Anything already installed is upgraded in place when an upgrade is available, otherwise it is left untouched, so re-running is always safe.

## What it installs

| Software | What it is |
|----------|------------|
| **git** | Version control. Tracks changes in your projects and is required by most modern dev tooling. |
| **Node.js (LTS)** | JavaScript runtime plus `npm`. Powers most web tooling and many command line tools. |
| **Antigravity IDE** | Google's agentic code editor (a VS Code based IDE). This is where you write code. |
| **Claude Code extension** | Brings Claude Code straight into Antigravity, so you can chat with Claude and let it edit your project from inside the editor. |
| **Claude RTL Code extension** | Adds proper right to left support to the editor, so Hebrew and Arabic text renders and edits correctly. |
| **Claude Code CLI** | The `claude` command in your terminal. Run Claude Code from any project folder, no editor needed. |

## Good to know

* **Safe to re-run.** Every component is checked first. Missing ones are installed, already installed ones are upgraded when there is an easy upgrade, otherwise they are skipped.
* **Your terminal just works.** Each tool's folder is added to your PATH (permanently and for the current session), so `claude`, `node`, and `git` work in a fresh terminal. On Windows the PowerShell execution policy is set to `RemoteSigned` for your user only if it was blocking scripts, so the `claude` command can run.
* **Antigravity sign in.** Antigravity needs a Google account. You sign in once the first time you open it. If the editor has never been opened, its command line tool may not exist yet, so the two extensions are skipped. Open Antigravity once, then run the install command again.
* **Homebrew is never installed for you.** On macOS, Homebrew is used only if you already have it. Otherwise the official downloads from nodejs.org and Google are used.
* **Linux and Antigravity.** The Antigravity editor is not installed automatically on Linux. Grab it from [antigravity.google/download/linux](https://antigravity.google/download/linux). Everything else installs normally.
* **Claude Code account.** Claude Code needs a Pro, Max, Team, Enterprise, or Console account. You log in the first time you run `claude`.

## License

[MIT](LICENSE)
