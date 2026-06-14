<#
.SYNOPSIS
    One-command Claude Code dev environment for Windows.

.DESCRIPTION
    Installs (idempotently): git, Node.js LTS, Antigravity IDE, the Claude Code
    and Claude RTL Code extensions for Antigravity, and the Claude Code CLI.
    Already-installed components are skipped unless -Upgrade is given.

.PARAMETER DryRun
    Print every action without changing the system.
.PARAMETER Upgrade
    Upgrade components that are already installed (otherwise present == skip).
.PARAMETER Skip
    Components to skip: git, node, antigravity, extensions, claude.
.PARAMETER Verify
    Run only the verification/doctor step.
.PARAMETER ApiKey
    Persist an Anthropic API key to the user environment (optional).
.PARAMETER Help
    Show usage and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1))) -DryRun
#>
[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $Upgrade,
    [string[]] $Skip = @(),
    [switch] $Verify,
    [string] $ApiKey,
    [switch] $Help
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

function Show-Usage {
    @'
claude-dev-setup (Windows)

Usage:
  install.ps1 [-DryRun] [-Upgrade] [-Skip git,node,...] [-Verify] [-ApiKey <key>] [-Help]

Flags:
  -DryRun     Print actions, change nothing.
  -Upgrade    Upgrade components already installed.
  -Skip       Comma list: git,node,antigravity,extensions,claude.
  -Verify     Run only the verification step.
  -ApiKey     Persist an Anthropic API key to the user environment.
  -Help       This help.
'@ | Write-Host
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Test-CommandExists {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ShouldSkip {
    param([string] $Component)
    return ($Skip -contains $Component)
}

# Run an action unless in dry-run mode.
function Invoke-Action {
    param(
        [string] $Description,
        [scriptblock] $Action
    )
    if ($DryRun) {
        Write-Dry $Description
        return $true
    }
    & $Action
    return $true
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
    else {
        if ($DryRun) {
            Write-Dry "add $Directory to User PATH"
        }
        else {
            $newPath = (@($parts + $Directory) | Where-Object { $_ }) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Ok "added $Directory to User PATH"
        }
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

# winget install/upgrade with sane non-interactive flags.
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
        Invoke-Action "set CurrentUser ExecutionPolicy to RemoteSigned (was $current)" {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        } | Out-Null
        if (-not $DryRun) { Write-Ok 'ExecutionPolicy = RemoteSigned (CurrentUser)' }
    }
    else {
        Write-Skip "ExecutionPolicy already permissive ($current)"
    }
}

# ----------------------------------------------------------------------------
# Components
# ----------------------------------------------------------------------------
function Install-Git {
    if (Test-ShouldSkip 'git') { Write-Skip 'git (skipped)'; return }
    Write-Step 'git'
    if (Test-CommandExists 'git') {
        if ($Upgrade) { Invoke-Winget -Id 'Git.Git' -DoUpgrade | Out-Null; Write-Ok 'git upgraded' }
        else { Write-Skip "git already installed ($(git --version))" }
        return
    }
    if (-not (Test-Winget)) { return }
    Invoke-Winget -Id 'Git.Git' | Out-Null
    Update-SessionPath
    if (-not $DryRun) { Write-Ok 'git installed' }
}

function Install-Node {
    if (Test-ShouldSkip 'node') { Write-Skip 'node (skipped)'; return }
    Write-Step 'Node.js LTS'
    if (Test-CommandExists 'node') {
        if ($Upgrade) { Invoke-Winget -Id 'OpenJS.NodeJS.LTS' -DoUpgrade | Out-Null; Write-Ok 'Node upgraded' }
        else { Write-Skip "Node already installed ($(node --version))" }
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
    if (Test-ShouldSkip 'antigravity') { Write-Skip 'Antigravity (skipped)'; return }
    Write-Step 'Antigravity IDE'
    $cli = Find-AntigravityCli
    if ($cli) {
        if ($Upgrade) { Invoke-Winget -Id 'Google.Antigravity' -DoUpgrade | Out-Null; Write-Ok 'Antigravity upgraded' }
        else { Write-Skip 'Antigravity already installed' }
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
# itself idempotent (no-op when already current), which is why there is no
# separate "already installed" pre-check (its --list-extensions is unreliable).
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
    if (Test-ShouldSkip 'extensions') { Write-Skip 'extensions (skipped)'; return }
    Write-Step 'Antigravity extensions'
    $cli = Find-AntigravityCli
    if (-not $cli -and -not $DryRun) {
        Write-Warn 'Antigravity CLI not found; open Antigravity once, then re-run with -Skip git,node,antigravity,claude'
        return
    }
    Install-AntigravityExtension -ExtId $script:ExtClaudeCode -Cli $cli -VsixUrl $null
    Install-AntigravityExtension -ExtId $script:ExtClaudeRtl  -Cli $cli -VsixUrl $script:RtlVsixUrl
}

function Install-ClaudeCli {
    if (Test-ShouldSkip 'claude') { Write-Skip 'Claude CLI (skipped)'; return }
    Write-Step 'Claude Code CLI'
    $claudeExe = Join-Path $script:ClaudeBinDir 'claude.exe'
    if ((Test-CommandExists 'claude') -or (Test-Path $claudeExe)) {
        if ($Upgrade) {
            Invoke-Action 'claude update' { & claude update | Out-Host } | Out-Null
            if (-not $DryRun) { Write-Ok 'Claude CLI updated' }
        }
        else { Write-Skip 'Claude CLI already installed' }
        Add-ToUserPath $script:ClaudeBinDir
        return
    }
    Invoke-Action 'install Claude Code CLI (claude.ai/install.ps1)' {
        $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
        & ([scriptblock]::Create($installer))
    } | Out-Null
    # The native installer drops claude in %USERPROFILE%\.local\bin - guarantee PATH.
    Add-ToUserPath $script:ClaudeBinDir
    if (-not $DryRun) { Write-Ok 'Claude CLI installed' }
}

function Set-ApiKeyIfProvided {
    $key = $ApiKey
    if (-not $key) { $key = $env:ANTHROPIC_API_KEY }
    if (-not $key) { return }
    Write-Step 'Anthropic API key'
    if ($DryRun) { Write-Dry 'persist ANTHROPIC_API_KEY to User environment'; return }
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $key, 'User')
    $env:ANTHROPIC_API_KEY = $key
    Write-Ok 'ANTHROPIC_API_KEY set (User)'
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
        Write-Warn 'Open a NEW terminal (PATH changes apply to new shells). If Antigravity/extensions are missing, open Antigravity once then re-run with -Verify.'
        return $false
    }
    Write-Ok 'all components present'
    return $true
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Main {
    if ($Help) { Show-Usage; return }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Err "PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))."
        return
    }

    Write-Host 'claude-dev-setup (Windows)' -ForegroundColor White
    if ($DryRun) { Write-Warn 'DRY RUN - nothing will be installed' }

    if ($Verify) { [void](Invoke-Verify); return }

    Set-ExecutionPolicyIfRestricted
    Install-Git
    Install-Node
    Install-Antigravity
    Install-Extensions
    Install-ClaudeCli
    Set-ApiKeyIfProvided

    $ok = Invoke-Verify
    Write-Host ''
    if ($ok) {
        Write-Host 'Done. Open a NEW terminal and run: claude' -ForegroundColor Green
    }
    else {
        Write-Host 'Finished with warnings - see above. Open a new terminal and re-run with -Verify.' -ForegroundColor Yellow
    }
}

Main
