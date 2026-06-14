# Contributing

Thanks for your interest in improving Claude Dev Setup.

## Layout

```
claude-dev-setup/
├── scripts/
│   ├── install.ps1     Windows installer
│   └── install.sh      macOS + Linux installer
├── tests/
│   ├── smoke.ps1       parses install.ps1 and runs it in --dry-run
│   └── smoke.sh        parses install.sh and runs it in --dry-run
├── .github/
│   ├── workflows/ci.yml
│   └── linters/PSScriptAnalyzerSettings.psd1
├── README.md
└── LICENSE
```

## Design rules

- **The two installers are self-contained on purpose.** They are downloaded and
  piped straight into a shell (`irm ... | iex` / `curl ... | bash`), so they must
  not depend on any other file at runtime. There is no shared library to import.
- **`install.sh` covers both macOS and Linux** and detects which at runtime.
  There is no single command for every OS, because PowerShell and POSIX shells
  are different languages.
- **No flags for users.** The only flag is `--dry-run`, used by the tests/CI to
  exercise the logic without installing anything.
- **Always leave the system usable.** Already-installed tools are upgraded in
  place when there is an easy upgrade, otherwise skipped. PATH and (on Windows)
  the execution policy are fixed so the tools work in a fresh terminal.

## Testing locally

Run the dry-run smoke tests (they install nothing):

```bash
# macOS / Linux
bash tests/smoke.sh
```

```powershell
# Windows
.\tests\smoke.ps1
```

Lint before opening a PR:

```bash
shellcheck -S style scripts/install.sh tests/smoke.sh
```

```powershell
Invoke-ScriptAnalyzer -Path .\scripts\install.ps1 -Settings .\.github\linters\PSScriptAnalyzerSettings.psd1
```

CI runs all of the above on Windows, macOS, and Ubuntu, plus a real end-to-end
install of `install.sh` in a clean `ubuntu:24.04` container.
