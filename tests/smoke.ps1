#Requires -Version 5.1
# Smoke test: the installer must parse and complete a dry run with exit 0,
# without touching the system.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'install.ps1'

Write-Host '== parse check =='
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_.Message }
    throw "FAIL: install.ps1 has parse errors"
}

Write-Host '== -DryRun =='
# The installer prints via Write-Host (PowerShell information stream #6), so we
# must merge ALL streams (*>&1), not just stderr (2>&1), to capture its output.
$out = & $script -DryRun *>&1 | Out-String
Write-Host $out

if ($out -notmatch 'DRY RUN') { throw 'FAIL: dry-run banner missing' }

Write-Host 'PASS: install.ps1 dry run completed cleanly'
