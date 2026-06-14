# claude-dev-setup

One command sets up a complete **Claude Code** development environment on **Windows, macOS, and Linux**.

It installs — and skips anything you already have:

1. **git**
2. **Node.js (LTS)** + npm
3. **Antigravity IDE** (Google)
4. **Claude Code** extension for Antigravity (`Anthropic.claude-code`)
5. **Claude RTL Code** extension for Antigravity (`AdirYad.claude-rtl-code`)
6. **Claude Code CLI** (`claude` in your terminal)

---

## Install

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex
```

### macOS / Linux (Terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.sh | bash
```

Then **open a new terminal** and run:

```bash
claude
```

---

## What makes it safe to re-run

- **Just re-run it.** No flags, no options. Every component is checked first: if it's missing it's installed; if it's already there and an immediate upgrade is available (winget upgrade / brew upgrade / `claude update`) it's upgraded in place; otherwise it's left alone.
- **PATH is guaranteed.** Each tool's bin directory is added to your PATH persistently *and* for the current session, so `claude`, `node`, and `git` work in a fresh terminal.
- **Windows ExecutionPolicy** is set to `RemoteSigned` (CurrentUser) only if it was restrictive — so npm-installed `.ps1` shims (including `claude`) actually run.
- **No Homebrew is ever installed for you.** On macOS, Homebrew is used only if you already have it; otherwise official direct downloads are used.
- The installer always ends with a verification table showing every tool and its version.

---

## Notes & limitations

- **Antigravity needs a Google account** — you log in once when you first open the IDE (this can't be automated).
- **Antigravity extensions** are installed through Antigravity's own CLI (`antigravity --install-extension`), which uses the [open-vsx](https://open-vsx.org) registry. If the registry install fails, the installer falls back to downloading the extension's `.vsix`. If the Antigravity CLI isn't found (IDE never opened yet), open Antigravity once and re-run.
- **Linux + Antigravity:** the installer does **not** auto-add an apt repository/signing key (a deliberate security choice). Install Antigravity from <https://antigravity.google/download/linux>, or set `LINUX_ANTIGRAVITY_DEB_URL=<deb-url>` before running to auto-install a `.deb` on apt systems. Every other component installs normally on Linux.
- **macOS without Homebrew:** Node is installed from the official `nodejs.org` package and Antigravity from Google's official `.dmg`. Installing Homebrew first (then re-running) gives you auto-updating installs.
- Claude Code requires a Pro / Max / Team / Enterprise / Console account. The native CLI auto-updates itself in the background.

---

## How it's tested

Every push runs a GitHub Actions matrix (Windows · macOS · Ubuntu) that:
- runs each installer in `--dry-run` (asserts exit 0, no real installs),
- lints `install.sh` with **shellcheck** and `bash -n`,
- lints `install.ps1` with **PSScriptAnalyzer**.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design.

## License

[MIT](LICENSE)
