<#
.SYNOPSIS
    One-command Claude Code dev environment for Windows.

.DESCRIPTION
    Installs git, Node.js LTS, Antigravity IDE, the Claude Code and Claude RTL
    Code extensions for Antigravity, and the Claude Code CLI.

    Re-running is safe: anything already installed is upgraded in place when an
    immediate upgrade is available (winget upgrade / claude update), otherwise
    it is left alone. PATH and the PowerShell ExecutionPolicy are always fixed
    so the tools work in a fresh terminal.

.PARAMETER DryRun
    Internal/testing only: print every action without changing the system.
    Used by CI; users never need it.

.EXAMPLE
    irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# Native tools (winget, antigravity) sometimes return a non-zero exit code even
# on success (e.g. Antigravity prints a harmless analytics warning). Stop PS7
# from turning those exit codes into terminating errors; we check results
# explicitly instead.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
$script:ExtClaudeCode = 'Anthropic.claude-code'
$script:ExtClaudeRtl  = 'AdirYad.claude-rtl-code'
$script:RtlVsixVersion = '1.0.9'
$script:RtlVsixUrl = "https://open-vsx.org/api/AdirYad/claude-rtl-code/$($script:RtlVsixVersion)/file/AdirYad.claude-rtl-code-$($script:RtlVsixVersion).vsix"
$script:ClaudeBinDir = Join-Path $env:USERPROFILE '.local\bin'

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
# Helpers
# ----------------------------------------------------------------------------
function Test-CommandExists {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Re-read PATH from machine + user scope into the current session.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Add a directory to the persistent User PATH (and the session) if missing.
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

    # Make it usable immediately in this session too.
    if (($env:Path -split ';') -notcontains $Directory) {
        $env:Path = "$($env:Path);$Directory"
    }
}

function Test-Winget {
    if (Test-CommandExists 'winget') { return $true }
    Write-Err 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
    return $false
}

# winget install/upgrade with non-interactive flags. Returns $true.
function Invoke-Winget {
    param(
        [string] $Id,
        [switch] $DoUpgrade
    )
    $verb = if ($DoUpgrade) { 'upgrade' } else { 'install' }
    if ($DryRun) { Write-Dry "winget $verb --id $Id"; return $true }
    winget $verb --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    return $true
}

# ----------------------------------------------------------------------------
# ExecutionPolicy (npm .ps1 shims need RemoteSigned at CurrentUser)
# ----------------------------------------------------------------------------
function Set-ExecutionPolicyIfRestricted {
    Write-Step 'PowerShell ExecutionPolicy'
    $current = Get-ExecutionPolicy -Scope CurrentUser
    $restrictive = @('Restricted', 'AllSigned', 'Undefined')
    if ($restrictive -contains [string]$current) {
        if ($DryRun) {
            Write-Dry "set CurrentUser ExecutionPolicy to RemoteSigned (was $current)"
        }
        else {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Ok 'ExecutionPolicy = RemoteSigned (CurrentUser)'
        }
    }
    else {
        Write-Skip "ExecutionPolicy already permissive ($current)"
    }
}

# ----------------------------------------------------------------------------
# Components (install when missing; upgrade in place when already present)
# ----------------------------------------------------------------------------
function Install-Git {
    Write-Step 'git'
    if (Test-CommandExists 'git') {
        Invoke-Winget -Id 'Git.Git' -DoUpgrade | Out-Null
        if (-not $DryRun) { Write-Ok "git up to date ($(git --version))" }
        return
    }
    if (-not (Test-Winget)) { return }
    Invoke-Winget -Id 'Git.Git' | Out-Null
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'git installed' }
}

function Install-Node {
    Write-Step 'Node.js LTS'
    if (Test-CommandExists 'node') {
        Invoke-Winget -Id 'OpenJS.NodeJS.LTS' -DoUpgrade | Out-Null
        if (-not $DryRun) { Write-Ok "Node up to date ($(node --version))" }
        return
    }
    if (-not (Test-Winget)) { return }
    Invoke-Winget -Id 'OpenJS.NodeJS.LTS' | Out-Null
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'Node installed' }
}

function Find-AntigravityCli {
    if (Test-CommandExists 'antigravity') {
        return (Get-Command 'antigravity' -ErrorAction SilentlyContinue).Source
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\bin\antigravity.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\bin\antigravity'),
        (Join-Path ${env:ProgramFiles} 'Antigravity\bin\antigravity.cmd')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Install-Antigravity {
    Write-Step 'Antigravity IDE'
    if (Find-AntigravityCli) {
        Invoke-Winget -Id 'Google.Antigravity' -DoUpgrade | Out-Null
        if (-not $DryRun) { Write-Ok 'Antigravity up to date' }
        return
    }
    if (-not (Test-Winget)) { return }
    Invoke-Winget -Id 'Google.Antigravity' | Out-Null
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'Antigravity installed' }
}

# Antigravity's CLI prints a harmless "antigravityAnalytics ... NOT registered"
# warning and may exit non-zero even when the extension installs fine, so we
# judge success by the output text, not the exit code. --install-extension is
# itself idempotent (installs or upgrades to the latest), which is why there is
# no separate "already installed" check (its --list-extensions is unreliable).
function Install-ExtViaCli {
    param([string] $Cli, [string] $Target)
    $output = (& $Cli --install-extension $Target --force 2>&1 | Out-String)
    if ($output.Trim()) { Write-Host $output.Trim() -ForegroundColor DarkGray }
    return ($output -match 'successfully installed' -or
            $output -match 'already installed' -or
            $LASTEXITCODE -eq 0)
}

function Install-AntigravityExtension {
    param(
        [string] $ExtId,
        [string] $Cli,
        [string] $VsixUrl
    )
    if (-not $Cli) { Write-Dry "install extension $ExtId via Antigravity CLI"; return }
    if ($DryRun) { Write-Dry "install extension $ExtId (open-vsx, VSIX fallback)"; return }

    if (Install-ExtViaCli -Cli $Cli -Target $ExtId) { Write-Ok "$ExtId installed"; return }

    if ($VsixUrl) {
        Write-Warn "registry install unconfirmed for $ExtId, trying VSIX fallback"
        try {
            $tmp = Join-Path $env:TEMP ("{0}.vsix" -f ($ExtId -replace '[^\w.-]', '_'))
            Invoke-WebRequest -Uri $VsixUrl -OutFile $tmp -UseBasicParsing
            if (Install-ExtViaCli -Cli $Cli -Target $tmp) { Write-Ok "$ExtId installed from VSIX" }
            else { Write-Err "failed to install $ExtId" }
        }
        catch { Write-Err "VSIX fallback failed for $ExtId ($($_.Exception.Message))" }
    }
    else {
        Write-Err "failed to confirm install of $ExtId"
    }
}

function Install-Extensions {
    Write-Step 'Antigravity extensions'
    $cli = Find-AntigravityCli
    if (-not $cli -and -not $DryRun) {
        Write-Warn 'Antigravity CLI not found; open Antigravity once, then re-run.'
        return
    }
    Install-AntigravityExtension -ExtId $script:ExtClaudeCode -Cli $cli -VsixUrl $null
    Install-AntigravityExtension -ExtId $script:ExtClaudeRtl  -Cli $cli -VsixUrl $script:RtlVsixUrl
}

function Install-ClaudeCli {
    Write-Step 'Claude Code CLI'
    $claudeExe = Join-Path $script:ClaudeBinDir 'claude.exe'
    if ((Test-CommandExists 'claude') -or (Test-Path $claudeExe)) {
        if ($DryRun) { Write-Dry 'claude update' }
        else { & claude update | Out-Host; Write-Ok 'Claude CLI up to date' }
        Add-ToUserPath $script:ClaudeBinDir
        return
    }
    if ($DryRun) {
        Write-Dry 'install Claude Code CLI (claude.ai/install.ps1)'
    }
    else {
        $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
        & ([scriptblock]::Create($installer))
    }
    # The native installer drops claude in %USERPROFILE%\.local\bin - guarantee PATH.
    Add-ToUserPath $script:ClaudeBinDir
    if (-not $DryRun) { Write-Ok 'Claude CLI installed' }
}

# ----------------------------------------------------------------------------
# Verification (fresh shell proves PATH + policy took effect)
# ----------------------------------------------------------------------------
function Get-FreshVersion {
    param([string] $Command, [string] $VersionArg = '--version')
    try {
        $out = & powershell -NoProfile -Command "& { (& $Command $VersionArg) 2>`$null }" 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1).ToString().Trim() }
    }
    catch { Write-Verbose "version probe failed for $Command" }
    return $null
}

function Invoke-Verify {
    Write-Step 'Verifying (fresh shell)'
    $rows = @()
    foreach ($tool in @(
        @{ Name = 'git'; Cmd = 'git' },
        @{ Name = 'node'; Cmd = 'node' },
        @{ Name = 'npm'; Cmd = 'npm' },
        @{ Name = 'claude'; Cmd = 'claude' }
    )) {
        $v = Get-FreshVersion -Command $tool.Cmd
        $rows += [pscustomobject]@{ Tool = $tool.Name; Status = if ($v) { 'OK' } else { 'MISSING' }; Version = $v }
    }

    $cli = Find-AntigravityCli
    $rows += [pscustomobject]@{ Tool = 'antigravity'; Status = if ($cli) { 'OK' } else { 'MISSING' }; Version = $cli }

    # Antigravity's --list-extensions is unreliable (analytics dependency error),
    # so extensions cannot be confirmed from the CLI. They are installed via the
    # idempotent --install-extension; verify visually in the IDE if needed.
    $rows += [pscustomobject]@{ Tool = 'extensions'; Status = 'INFO'; Version = 'installed via CLI; confirm in Antigravity Extensions panel' }

    $rows | Format-Table -AutoSize | Out-Host

    $missing = $rows | Where-Object { $_.Status -eq 'MISSING' }
    if ($missing) {
        Write-Warn ("missing: " + ($missing.Tool -join ', '))
        Write-Warn 'Open a NEW terminal (PATH changes apply to new shells). If Antigravity/extensions are missing, open Antigravity once then re-run.'
        return $false
    }
    Write-Ok 'all components present'
    return $true
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Main {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Err "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))."
        return
    }

    Write-Host 'claude-dev-setup (Windows)' -ForegroundColor White
    if ($DryRun) { Write-Warn 'DRY RUN - nothing will be installed' }

    Set-ExecutionPolicyIfRestricted
    Install-Git
    Install-Node
    Install-Antigravity
    Install-Extensions
    Install-ClaudeCli

    $ok = Invoke-Verify
    Write-Host ''
    if ($ok) {
        Write-Host 'Done. Open a NEW terminal and run: claude' -ForegroundColor Green
    }
    else {
        Write-Host 'Finished with warnings - see above. Open a new terminal to pick up PATH changes.' -ForegroundColor Yellow
    }
}

Main
