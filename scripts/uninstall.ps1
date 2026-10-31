<#
.SYNOPSIS
    Remove the Claude-specific parts added by claude-dev-setup (Windows).

.DESCRIPTION
    Removes the Claude Code CLI and the Claude Code + Claude RTL extensions from
    Antigravity. It deliberately leaves git, Node.js, and Antigravity in place,
    since other software on your computer may rely on them. To remove those, use
    "winget uninstall <id>".

.PARAMETER DryRun
    Internal/testing only: print every action without changing the system.

.EXAMPLE
    irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/uninstall.ps1 | iex
#>
[CmdletBinding()]
param(
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { Write-Verbose 'console encoding unchanged' }
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$script:ExtClaudeCode = 'Anthropic.claude-code'
$script:ExtClaudeRtl  = 'AdirYad.claude-rtl-code'
$script:ClaudeBinDir  = Join-Path $env:USERPROFILE '.local\bin'
$script:ClaudeShare   = Join-Path $env:USERPROFILE '.local\share\claude'
$script:Check = [char]0x2713
$script:Cross = [char]0x2717
$script:Bullet = [char]0x2022

function Write-Banner {
    $rule = ([char]0x2500).ToString() * 52
    Write-Host ''
    Write-Host '  Claude Dev Setup - Uninstall' -ForegroundColor Cyan
    Write-Host '  Removing the Claude parts (keeping git, Node, Antigravity)' -ForegroundColor Gray
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Row {
    param([string] $Mark, [string] $Color, [string] $Name, [string] $Detail)
    Write-Host ("  {0}  " -f $Mark) -ForegroundColor $Color -NoNewline
    Write-Host ("{0,-19}" -f $Name) -ForegroundColor White -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
}

function Write-Note { param([string] $Message) Write-Host "  $Message" -ForegroundColor Yellow }

# Delete temp files without ever aborting the run (see install.ps1 for why
# Remove-Item is unsafe here under $ErrorActionPreference = 'Stop').
function Remove-FileQuiet {
    param([string[]] $Path)
    foreach ($p in $Path) {
        if (-not $p) { continue }
        try { [System.IO.File]::Delete($p) } catch { Write-Verbose "could not delete $p" }
    }
}

# Run a program behind a spinner that leaves a persistent line (see install.ps1).
function Invoke-Capture {
    param([string] $Label, [string] $FilePath, [string[]] $Arguments = @(), [switch] $Quiet)
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $frames = '|', '/', '-', '\'
        $i = 0
        while (-not $p.HasExited) {
            if (-not $Quiet) { Write-Host ("`r  {0}  {1}   " -f $frames[$i % 4], $Label) -NoNewline -ForegroundColor Cyan; $i++ }
            Start-Sleep -Milliseconds 120
        }
        $p.WaitForExit()
        if (-not $Quiet) {
            Write-Host "`r  " -NoNewline
            Write-Host $script:Check -NoNewline -ForegroundColor Green
            Write-Host ("  {0}" -f $Label) -ForegroundColor Gray
        }
        $so = if (Test-Path $outFile) { [string](Get-Content $outFile -Raw -ErrorAction SilentlyContinue) } else { '' }
        return [pscustomobject]@{ StdOut = $so }
    }
    finally { Remove-FileQuiet @($outFile, $errFile) }
}

# Same lookup as install.ps1: 2.x "Antigravity IDE" first, 1.x as fallback.
function Find-AntigravityCli {
    foreach ($name in 'antigravity-ide', 'antigravity') {
        $cmd = Get-Command "$name.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity IDE'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity'),
        (Join-Path ${env:ProgramFiles} 'Antigravity IDE'),
        (Join-Path ${env:ProgramFiles} 'Antigravity')
    )
    foreach ($hive in 'HKCU', 'HKLM') {
        $roots += Get-ItemProperty "${hive}:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Antigravity*' -and $_.InstallLocation } |
            ForEach-Object { $_.InstallLocation }
    }
    foreach ($r in $roots) {
        foreach ($name in 'antigravity-ide.cmd', 'antigravity.cmd') {
            $p = Join-Path $r "bin\$name"
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Get-AntigravityExtensions {
    param([string] $Cli)
    if (-not $Cli) { return @() }
    $r = Invoke-Capture -Label 'list' -FilePath $Cli -Arguments @('--list-extensions') -Quiet
    return @($r.StdOut -split "`r?`n" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
}

function Remove-Extension {
    param([string] $ExtId, [string] $Cli)
    if (-not $Cli) { return }
    if ((Get-AntigravityExtensions -Cli $Cli) -notcontains $ExtId.ToLower()) { return }
    if ($DryRun) { return }
    [void](Invoke-Capture -Label "Removing $ExtId" -FilePath $Cli -Arguments @('--uninstall-extension', $ExtId))
}

function Main {
    Write-Banner

    $cli = Find-AntigravityCli
    if (-not $DryRun) {
        Remove-Extension -ExtId $script:ExtClaudeCode -Cli $cli
        Remove-Extension -ExtId $script:ExtClaudeRtl -Cli $cli

        if (Test-Path (Join-Path $script:ClaudeBinDir 'claude.exe')) {
            Write-Host "  $($script:Bullet)  Removing the Claude command" -ForegroundColor Cyan
            Remove-Item (Join-Path $script:ClaudeBinDir 'claude.exe') -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $script:ClaudeShare -Recurse -Force -ErrorAction SilentlyContinue
        # install.ps1 falls back to npm when claude.ai is unreachable.
        $npm = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if ($npm -and (Test-Path (Join-Path $env:APPDATA 'npm\claude.cmd'))) {
            [void](Invoke-Capture -Label 'Removing the Claude command (npm)' -FilePath $npm -Arguments @('uninstall', '-g', '@anthropic-ai/claude-code'))
        }
    }

    # Results
    $exts = Get-AntigravityExtensions -Cli $cli
    $codeGone = ($exts -notcontains $script:ExtClaudeCode.ToLower())
    $rtlGone = ($exts -notcontains $script:ExtClaudeRtl.ToLower())
    $claudeGone = -not ((Test-Path (Join-Path $script:ClaudeBinDir 'claude.exe')) -or (Test-Path (Join-Path $env:APPDATA 'npm\claude.cmd')))

    $rule = ([char]0x2500).ToString() * 52
    Write-Host ''
    Write-Host '  Removed' -ForegroundColor Cyan
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Row ($(if ($codeGone) { $script:Check } else { $script:Cross })) ($(if ($codeGone) { 'Green' } else { 'Red' })) 'Claude in editor'  'extension'
    Write-Row ($(if ($rtlGone) { $script:Check } else { $script:Cross }))  ($(if ($rtlGone) { 'Green' } else { 'Red' }))  'Hebrew support'    'extension'
    Write-Row ($(if ($claudeGone) { $script:Check } else { $script:Cross })) ($(if ($claudeGone) { 'Green' } else { 'Red' })) 'Claude command'    'CLI'
    Write-Host ''
    Write-Host '  Kept (other software may use these)' -ForegroundColor Cyan
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Row $script:Bullet 'DarkGray' 'Git'         'winget uninstall Git.Git'
    Write-Row $script:Bullet 'DarkGray' 'Node.js'     'winget uninstall OpenJS.NodeJS.LTS'
    Write-Row $script:Bullet 'DarkGray' 'Antigravity' 'winget uninstall Google.AntigravityIDE'
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Done. The Claude parts have been removed.' -ForegroundColor Green
    Write-Host ''
}

Main
