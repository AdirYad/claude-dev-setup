<#
.SYNOPSIS
    One-command Claude Code dev environment for Windows.

.DESCRIPTION
    Installs git, Node.js LTS, Antigravity IDE, the Claude Code and Claude RTL
    Code extensions for Antigravity, and the Claude Code CLI.

    Re-running is safe: anything already installed is upgraded in place when an
    immediate upgrade is available (winget upgrade / claude update), otherwise
    it is left alone. Extensions already present are skipped. PATH and the
    PowerShell ExecutionPolicy are always fixed so the tools work in a fresh
    terminal.

.PARAMETER DryRun
    Internal/testing only: print every action without changing the system.

.EXAMPLE
    irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # no Invoke-WebRequest progress bars
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { Write-Verbose 'console encoding unchanged' }

# PS7-only: stop non-zero native exit codes becoming terminating errors.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
$script:ExtClaudeCode  = 'Anthropic.claude-code'
$script:ExtClaudeRtl   = 'AdirYad.claude-rtl-code'
$script:RtlVsixVersion = '1.0.9'
$script:RtlVsixUrl     = "https://open-vsx.org/api/AdirYad/claude-rtl-code/$($script:RtlVsixVersion)/file/AdirYad.claude-rtl-code-$($script:RtlVsixVersion).vsix"
$script:ClaudeBinDir   = Join-Path $env:USERPROFILE '.local\bin'
$script:WingetExe      = $null

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
function Write-Step { param([string] $Message) Write-Host "`n=> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "   [ok]   $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "   [skip] $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string] $Message) Write-Host "   [warn] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string] $Message) Write-Host "   [err]  $Message" -ForegroundColor Red }
function Write-Dry  { param([string] $Message) Write-Host "   [dry]  would $Message" -ForegroundColor Magenta }

# ----------------------------------------------------------------------------
# Run an external program with a clean inline spinner, capturing its output to
# files so it can neither spam the console nor turn its stderr into a crash.
# ----------------------------------------------------------------------------
function Invoke-Capture {
    param(
        [string]   $Label,
        [string]   $FilePath,
        [string[]] $Arguments = @(),
        [switch]   $Quiet
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $animate = (-not $Quiet) -and (-not [Console]::IsOutputRedirected)
        $frames = '|', '/', '-', '\'
        $i = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            if ($animate) {
                Write-Host ("`r   [{0}] {1} ({2}s)   " -f $frames[$i % 4], $Label, [int]$sw.Elapsed.TotalSeconds) -NoNewline -ForegroundColor Cyan
                $i++
            }
            Start-Sleep -Milliseconds 120
        }
        $p.WaitForExit()
        if ($animate) { Write-Host ("`r" + (' ' * 72) + "`r") -NoNewline }
        $so = if (Test-Path $outFile) { [string](Get-Content $outFile -Raw -ErrorAction SilentlyContinue) } else { '' }
        $se = if (Test-Path $errFile) { [string](Get-Content $errFile -Raw -ErrorAction SilentlyContinue) } else { '' }
        return [pscustomobject]@{ StdOut = $so; StdErr = $se }
    }
    finally {
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Test-CommandExists {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Add-ToUserPath {
    param([string] $Directory)
    if (-not $Directory) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ } }
    $already = $parts | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }
    if ($already) {
        Write-Skip "PATH already contains $Directory"
    }
    elseif ($DryRun) {
        Write-Dry "add $Directory to User PATH"
    }
    else {
        $newPath = (@($parts + $Directory) | Where-Object { $_ }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Ok "added $Directory to User PATH"
    }
    if (($env:Path -split ';') -notcontains $Directory) { $env:Path = "$($env:Path);$Directory" }
}

function Get-WingetExe {
    if (-not $script:WingetExe) {
        $script:WingetExe = (Get-Command winget -ErrorAction SilentlyContinue).Source
    }
    return $script:WingetExe
}

# winget install/upgrade. Output is captured (no console spam); success is
# confirmed by the verification step at the end, not the exit code.
function Invoke-Winget {
    param([string] $Label, [string] $Verb, [string] $Id)
    $exe = Get-WingetExe
    if (-not $exe) { Write-Err 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'; return $false }
    if ($DryRun) { Write-Dry "$Label (winget $Verb $Id)"; return $true }
    [void](Invoke-Capture -Label $Label -FilePath $exe -Arguments @(
            $Verb, '--id', $Id, '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'))
    return $true
}

# ----------------------------------------------------------------------------
# ExecutionPolicy (npm .ps1 shims need RemoteSigned at CurrentUser)
# ----------------------------------------------------------------------------
function Set-ExecutionPolicyIfRestricted {
    Write-Step 'PowerShell ExecutionPolicy'
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if (@('Restricted', 'AllSigned', 'Undefined') -contains [string]$current) {
        if ($DryRun) { Write-Dry "set CurrentUser ExecutionPolicy to RemoteSigned (was $current)" }
        else { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; Write-Ok 'ExecutionPolicy = RemoteSigned (CurrentUser)' }
    }
    else { Write-Skip "ExecutionPolicy already permissive ($current)" }
}

# ----------------------------------------------------------------------------
# Components
# ----------------------------------------------------------------------------
function Install-Git {
    Write-Step 'git'
    if (Test-CommandExists 'git') {
        [void](Invoke-Winget -Label 'Upgrading git' -Verb 'upgrade' -Id 'Git.Git')
        if (-not $DryRun) { Write-Ok "git up to date ($(git --version))" }
        return
    }
    if (-not (Invoke-Winget -Label 'Installing git' -Verb 'install' -Id 'Git.Git')) { return }
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'git installed' }
}

function Install-Node {
    Write-Step 'Node.js LTS'
    if (Test-CommandExists 'node') {
        [void](Invoke-Winget -Label 'Upgrading Node.js' -Verb 'upgrade' -Id 'OpenJS.NodeJS.LTS')
        if (-not $DryRun) { Write-Ok "Node up to date ($(node --version))" }
        return
    }
    if (-not (Invoke-Winget -Label 'Installing Node.js' -Verb 'install' -Id 'OpenJS.NodeJS.LTS')) { return }
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'Node installed' }
}

function Find-AntigravityCli {
    if (Test-CommandExists 'antigravity') { return (Get-Command 'antigravity' -ErrorAction SilentlyContinue).Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\bin\antigravity.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\bin\antigravity'),
        (Join-Path ${env:ProgramFiles} 'Antigravity\bin\antigravity.cmd')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

# Antigravity's CLI prints a harmless "antigravityAnalytics NOT registered"
# warning to stderr; its real output (the extension list) goes to stdout, which
# Invoke-Capture reads cleanly. Returned ids are lower-cased for comparison.
function Get-AntigravityExtensions {
    param([string] $Cli)
    if (-not $Cli) { return @() }
    $r = Invoke-Capture -Label 'listing extensions' -FilePath $Cli -Arguments @('--list-extensions') -Quiet
    return @($r.StdOut -split "`r?`n" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
}

function Install-AntigravityExtension {
    param([string] $ExtId, [string] $Cli, [string] $VsixUrl, [string[]] $Existing)
    if ($Existing -contains $ExtId.ToLower()) { Write-Skip "$ExtId already installed"; return }
    if ($DryRun) { Write-Dry "install extension $ExtId"; return }

    $r = Invoke-Capture -Label "Installing $ExtId" -FilePath $Cli -Arguments @('--install-extension', $ExtId, '--force')
    if (($r.StdOut + $r.StdErr) -match 'successfully installed' -or
        (Get-AntigravityExtensions -Cli $Cli) -contains $ExtId.ToLower()) {
        Write-Ok "$ExtId installed"; return
    }

    if ($VsixUrl) {
        Write-Warn "registry install unconfirmed for $ExtId, trying VSIX fallback"
        try {
            $tmp = Join-Path $env:TEMP ("{0}.vsix" -f ($ExtId -replace '[^\w.-]', '_'))
            Invoke-WebRequest -Uri $VsixUrl -OutFile $tmp -UseBasicParsing
            [void](Invoke-Capture -Label "Installing $ExtId (VSIX)" -FilePath $Cli -Arguments @('--install-extension', $tmp, '--force'))
            if ((Get-AntigravityExtensions -Cli $Cli) -contains $ExtId.ToLower()) { Write-Ok "$ExtId installed from VSIX" }
            else { Write-Err "failed to install $ExtId" }
        }
        catch { Write-Err "VSIX fallback failed for $ExtId ($($_.Exception.Message))" }
    }
    else { Write-Err "failed to confirm install of $ExtId" }
}

function Install-Extensions {
    Write-Step 'Antigravity extensions'
    if ($DryRun) { Write-Dry 'install Claude Code + Claude RTL extensions'; return }
    $cli = Find-AntigravityCli
    if (-not $cli) { Write-Warn 'Antigravity CLI not found; open Antigravity once, then re-run.'; return }
    $existing = Get-AntigravityExtensions -Cli $cli
    Install-AntigravityExtension -ExtId $script:ExtClaudeCode -Cli $cli -VsixUrl $null -Existing $existing
    Install-AntigravityExtension -ExtId $script:ExtClaudeRtl -Cli $cli -VsixUrl $script:RtlVsixUrl -Existing $existing
}

function Install-ClaudeCli {
    Write-Step 'Claude Code CLI'
    $claudeExe = Join-Path $script:ClaudeBinDir 'claude.exe'
    if ((Test-CommandExists 'claude') -or (Test-Path $claudeExe)) {
        if ($DryRun) { Write-Dry 'claude update' }
        else {
            $claudeCmd = (Get-Command claude -ErrorAction SilentlyContinue).Source
            if (-not $claudeCmd) { $claudeCmd = $claudeExe }
            [void](Invoke-Capture -Label 'Updating Claude CLI' -FilePath $claudeCmd -Arguments @('update'))
            Write-Ok 'Claude CLI up to date'
        }
        Add-ToUserPath $script:ClaudeBinDir
        return
    }
    if ($DryRun) { Write-Dry 'install Claude Code CLI (claude.ai/install.ps1)'; Add-ToUserPath $script:ClaudeBinDir; return }
    Write-Host '   installing Claude Code CLI...' -ForegroundColor DarkGray
    $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
    & ([scriptblock]::Create($installer))
    Add-ToUserPath $script:ClaudeBinDir
    if ((Test-CommandExists 'claude') -or (Test-Path $claudeExe)) { Write-Ok 'Claude CLI installed' }
    else { Write-Warn 'Claude CLI install did not complete; see output above' }
}

# ----------------------------------------------------------------------------
# Verification
# ----------------------------------------------------------------------------
function Get-FreshVersion {
    param([string] $Command, [string] $VersionArg = '--version')
    try {
        $out = & powershell -NoProfile -Command "& { (& $Command $VersionArg) 2>`$null }" 2>$null
        if ($out) { return ($out | Select-Object -First 1).ToString().Trim() }
    }
    catch { Write-Verbose "version probe failed for $Command" }
    return $null
}

function Invoke-Verify {
    Write-Step 'Verifying (fresh shell)'
    $rows = @()
    foreach ($name in 'git', 'node', 'npm', 'claude') {
        $v = Get-FreshVersion -Command $name
        $rows += [pscustomobject]@{ Tool = $name; Status = $(if ($v) { 'OK' } else { 'MISSING' }); Detail = $v }
    }

    $cli = Find-AntigravityCli
    $rows += [pscustomobject]@{ Tool = 'antigravity'; Status = $(if ($cli) { 'OK' } else { 'MISSING' }); Detail = $cli }

    if ($cli) {
        $exts = Get-AntigravityExtensions -Cli $cli
        $haveCode = $exts -contains $script:ExtClaudeCode.ToLower()
        $haveRtl = $exts -contains $script:ExtClaudeRtl.ToLower()
        $state = if ($haveCode -and $haveRtl) { 'OK' } elseif ($haveCode -or $haveRtl) { 'PARTIAL' } else { 'MISSING' }
        $rows += [pscustomobject]@{ Tool = 'extensions'; Status = $state; Detail = "claude-code=$haveCode rtl=$haveRtl" }
    }
    else {
        $rows += [pscustomobject]@{ Tool = 'extensions'; Status = 'MISSING'; Detail = 'Antigravity CLI not found' }
    }

    $rows | Format-Table -AutoSize | Out-Host

    $missing = $rows | Where-Object { $_.Status -eq 'MISSING' }
    if ($missing) {
        Write-Warn ('missing: ' + ($missing.Tool -join ', '))
        Write-Warn 'Open a NEW terminal (PATH changes apply to new shells). If Antigravity/extensions are missing, open Antigravity once then re-run.'
        return $false
    }
    Write-Ok 'all components present'
    return $true
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Invoke-Safe {
    param([string] $Name, [scriptblock] $Action)
    try { & $Action }
    catch { Write-Err "$Name step failed: $($_.Exception.Message)" }
}

function Main {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Err "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))."
        return
    }

    Write-Host 'claude-dev-setup (Windows)' -ForegroundColor White
    if ($DryRun) { Write-Warn 'DRY RUN - nothing will be installed' }

    Invoke-Safe 'ExecutionPolicy' { Set-ExecutionPolicyIfRestricted }
    Invoke-Safe 'git' { Install-Git }
    Invoke-Safe 'Node.js' { Install-Node }
    Invoke-Safe 'Antigravity' { Install-Antigravity }
    Invoke-Safe 'extensions' { Install-Extensions }
    Invoke-Safe 'Claude CLI' { Install-ClaudeCli }

    $ok = Invoke-Verify
    Write-Host ''
    if ($ok) { Write-Host 'Done. Open a NEW terminal and run: claude' -ForegroundColor Green }
    else { Write-Host 'Finished with warnings - see above. Open a new terminal to pick up PATH changes.' -ForegroundColor Yellow }
}

function Install-Antigravity {
    Write-Step 'Antigravity IDE'
    if (Find-AntigravityCli) {
        [void](Invoke-Winget -Label 'Upgrading Antigravity' -Verb 'upgrade' -Id 'Google.Antigravity')
        if (-not $DryRun) { Write-Ok 'Antigravity up to date' }
        return
    }
    if (-not (Invoke-Winget -Label 'Installing Antigravity' -Verb 'install' -Id 'Google.Antigravity')) { return }
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'Antigravity installed' }
}

Main
