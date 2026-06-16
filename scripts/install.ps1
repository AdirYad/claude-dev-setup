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
    irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/scripts/install.ps1 | iex
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

$script:Check = [char]0x2713   # check mark
$script:Cross = [char]0x2717   # ballot x

# ----------------------------------------------------------------------------
# Pretty output
# ----------------------------------------------------------------------------
function Write-Banner {
    $rule = ([char]0x2500).ToString() * 52
    Write-Host ''
    Write-Host '  Claude Dev Setup' -ForegroundColor Cyan
    Write-Host '  Getting your computer ready to build with Claude' -ForegroundColor Gray
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Host ''
}

# A finished checklist line: green check (or red cross) + name + soft description.
function Write-Check {
    param([string] $Name, [string] $Description, [bool] $Ok = $true)
    $mark = if ($Ok) { $script:Check } else { $script:Cross }
    # When output is captured/redirected, -NoNewline segments split across lines,
    # so write the whole line at once; only colorize in a real console.
    if ([Console]::IsOutputRedirected) {
        Write-Host ("  {0}  {1,-19}{2}" -f $mark, $Name, $Description)
        return
    }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0}  " -f $mark) -ForegroundColor $color -NoNewline
    Write-Host ("{0,-19}" -f $Name) -ForegroundColor White -NoNewline
    Write-Host $Description -ForegroundColor DarkGray
}

function Write-Note { param([string] $Message) Write-Host "  $Message" -ForegroundColor Yellow }

# Delete temp files without ever aborting the run. Remove-Item can raise an
# Argument-class error (e.g. a TEMP path under a non-resolving 8.3 short name)
# that -ErrorAction SilentlyContinue does NOT suppress while $ErrorActionPreference
# is 'Stop'. [System.IO.File]::Delete is literal, is a no-op on a missing file,
# and ignores the preference; the try/catch covers an invalid directory.
function Remove-FileQuiet {
    param([string[]] $Path)
    foreach ($p in $Path) {
        if (-not $p) { continue }
        try { [System.IO.File]::Delete($p) } catch { Write-Verbose "could not delete $p" }
    }
}

# ----------------------------------------------------------------------------
# Run an external program, capturing its output to files so it can neither spam
# the console nor turn its stderr into a crash. Shows an animated spinner that
# overwrites itself in place ("/ Checking Git") and then leaves a persistent
# "checkmark + label" line, so the progress log stays on screen. We do NOT gate
# on [Console]::IsOutputRedirected (it is True under `irm | iex` yet the console
# still handles the carriage return just fine).
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
        $frames = '|', '/', '-', '\'
        $i = 0
        while (-not $p.HasExited) {
            if (-not $Quiet) {
                Write-Host ("`r  {0}  {1}   " -f $frames[$i % 4], $Label) -NoNewline -ForegroundColor Cyan
                $i++
            }
            Start-Sleep -Milliseconds 120
        }
        $p.WaitForExit()
        if (-not $Quiet) {
            Write-Host "`r  " -NoNewline
            Write-Host $script:Check -NoNewline -ForegroundColor Green
            Write-Host ("  {0}" -f $Label) -ForegroundColor Gray
        }
        $so = if (Test-Path $outFile) { [string](Get-Content $outFile -Raw -ErrorAction SilentlyContinue) } else { '' }
        $se = if (Test-Path $errFile) { [string](Get-Content $errFile -Raw -ErrorAction SilentlyContinue) } else { '' }
        return [pscustomobject]@{ StdOut = $so; StdErr = $se }
    }
    finally {
        Remove-FileQuiet @($outFile, $errFile)
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

# Quietly make sure a directory is on the persistent User PATH (and the session).
function Add-ToUserPath {
    param([string] $Directory)
    if (-not $Directory -or $DryRun) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ } }
    $already = $parts | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }
    if (-not $already) {
        $newPath = (@($parts + $Directory) | Where-Object { $_ }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
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
    if (-not $exe) { Write-Note 'Windows package installer (winget) was not found. Install "App Installer" from the Microsoft Store, then run this again.'; return $false }
    if ($DryRun) { return $true }
    [void](Invoke-Capture -Label $Label -FilePath $exe -Arguments @(
            $Verb, '--id', $Id, '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'))
    return $true
}

# Quietly allow npm-installed .ps1 shims (including claude) to run.
function Set-ExecutionPolicyIfRestricted {
    if ($DryRun) { return }
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if (@('Restricted', 'AllSigned', 'Undefined') -contains [string]$current) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }
}

# ----------------------------------------------------------------------------
# Components (each just does the work; the final checklist reports the result)
# ----------------------------------------------------------------------------
function Install-Git {
    if (Test-CommandExists 'git') { [void](Invoke-Winget -Label 'Checking Git' -Verb 'upgrade' -Id 'Git.Git'); return }
    if (Invoke-Winget -Label 'Installing Git' -Verb 'install' -Id 'Git.Git') { Update-SessionPath }
}

function Install-Node {
    if (Test-CommandExists 'node') { [void](Invoke-Winget -Label 'Checking Node.js' -Verb 'upgrade' -Id 'OpenJS.NodeJS.LTS'); return }
    if (Invoke-Winget -Label 'Installing Node.js' -Verb 'install' -Id 'OpenJS.NodeJS.LTS') { Update-SessionPath }
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

function Install-Antigravity {
    if (Find-AntigravityCli) { [void](Invoke-Winget -Label 'Checking Antigravity' -Verb 'upgrade' -Id 'Google.Antigravity'); return }
    if (Invoke-Winget -Label 'Installing Antigravity' -Verb 'install' -Id 'Google.Antigravity') { Update-SessionPath }
}

# Antigravity's CLI prints a harmless analytics warning to stderr; its real
# output (the extension list) goes to stdout. Returned ids are lower-cased.
# Pass -Label to show a spinner (used during install); omit it to run quietly.
function Get-AntigravityExtensions {
    param([string] $Cli, [string] $Label)
    if (-not $Cli) { return @() }
    $r = if ($Label) {
        Invoke-Capture -Label $Label -FilePath $Cli -Arguments @('--list-extensions')
    }
    else {
        Invoke-Capture -Label 'list' -FilePath $Cli -Arguments @('--list-extensions') -Quiet
    }
    return @($r.StdOut -split "`r?`n" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
}

function Install-AntigravityExtension {
    param([string] $ExtId, [string] $Cli, [string] $VsixUrl, [string[]] $Existing, [string] $Label)
    if ($Existing -contains $ExtId.ToLower()) { return }
    $r = Invoke-Capture -Label $Label -FilePath $Cli -Arguments @('--install-extension', $ExtId, '--force')
    if (($r.StdOut + $r.StdErr) -match 'successfully installed' -or
        (Get-AntigravityExtensions -Cli $Cli) -contains $ExtId.ToLower()) { return }
    if ($VsixUrl) {
        try {
            $tmp = Join-Path $env:TEMP ("{0}.vsix" -f ($ExtId -replace '[^\w.-]', '_'))
            Invoke-WebRequest -Uri $VsixUrl -OutFile $tmp -UseBasicParsing
            [void](Invoke-Capture -Label $Label -FilePath $Cli -Arguments @('--install-extension', $tmp, '--force'))
        }
        catch { Write-Verbose "VSIX fallback failed for $ExtId" }
    }
}

function Install-Extensions {
    if ($DryRun) { return }
    $cli = Find-AntigravityCli
    if (-not $cli) { return }
    $existing = Get-AntigravityExtensions -Cli $cli -Label 'Setting up editor extensions'
    Install-AntigravityExtension -ExtId $script:ExtClaudeCode -Cli $cli -VsixUrl $null -Existing $existing -Label 'Adding Claude to the editor'
    Install-AntigravityExtension -ExtId $script:ExtClaudeRtl -Cli $cli -VsixUrl $script:RtlVsixUrl -Existing $existing -Label 'Adding Hebrew/Arabic support'
}

function Install-ClaudeCli {
    $claudeExe = Join-Path $script:ClaudeBinDir 'claude.exe'
    if ((Test-CommandExists 'claude') -or (Test-Path $claudeExe)) {
        if (-not $DryRun) {
            $claudeCmd = (Get-Command claude -ErrorAction SilentlyContinue).Source
            if (-not $claudeCmd) { $claudeCmd = $claudeExe }
            [void](Invoke-Capture -Label 'Checking Claude' -FilePath $claudeCmd -Arguments @('update'))
        }
        Add-ToUserPath $script:ClaudeBinDir
        return
    }
    if ($DryRun) { return }
    $installerPath = Join-Path $env:TEMP 'claude-install.ps1'
    Invoke-WebRequest -Uri 'https://claude.ai/install.ps1' -OutFile $installerPath -UseBasicParsing
    [void](Invoke-Capture -Label 'Installing Claude' -FilePath 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installerPath))
    Add-ToUserPath $script:ClaudeBinDir
}

# ----------------------------------------------------------------------------
# Verification -> friendly checklist with versions
# ----------------------------------------------------------------------------
function Format-Detail {
    param([bool] $Ok, [string] $Version)
    if (-not $Ok) { return 'not found' }
    if ($Version) { return $Version }
    return 'installed'
}

function Show-Results {
    $cli = Find-AntigravityCli

    # Gather every version inside one child process so a single spinner can cover
    # the whole check. The child inherits this session's PATH.
    $gather = @'
$ErrorActionPreference = 'SilentlyContinue'
function V($exe, $a) { try { $o = & $exe $a 2>$null; if ($o) { return ([string](@($o)[0])).Trim() } } catch {} return '' }
$cli = '__CLI__'
'GIT=' + (V 'git' '--version')
'NODE=' + (V 'node' '--version')
'CLAUDE=' + (V 'claude' '--version')
'AG=' + $(if ($cli) { V $cli '--version' } else { '' })
'EXTSTART'
if ($cli) { & $cli --list-extensions --show-versions 2>$null }
'EXTEND'
'@
    $gather = $gather -replace '__CLI__', (([string]$cli) -replace "'", "''")
    $gatherPath = [System.IO.Path]::GetTempFileName()
    Set-Content -LiteralPath $gatherPath -Value $gather -Encoding UTF8
    $out = (Invoke-Capture -Label 'Checking everything is in place' -FilePath 'powershell' -Arguments @('-NoProfile', '-File', $gatherPath)).StdOut
    Remove-FileQuiet $gatherPath

    $gitRaw    = ([regex]::Match($out, 'GIT=(.*)')).Groups[1].Value.Trim()
    $nodeRaw   = ([regex]::Match($out, 'NODE=(.*)')).Groups[1].Value.Trim()
    $claudeRaw = ([regex]::Match($out, 'CLAUDE=(.*)')).Groups[1].Value.Trim()
    $agRaw     = ([regex]::Match($out, 'AG=(.*)')).Groups[1].Value.Trim()
    $extLower  = ''
    if ($out -match '(?s)EXTSTART(.*)EXTEND') { $extLower = $Matches[1].ToLower() }

    $gitVer    = ($gitRaw -replace '^git version ', '')
    $claudeVer = (($claudeRaw -split '\s+') | Select-Object -First 1)
    $agVer     = (($agRaw -split '\s+') | Select-Object -First 1)
    $codeVer   = ([regex]::Match($extLower, 'anthropic\.claude-code@(\S+)')).Groups[1].Value
    $rtlVer    = ([regex]::Match($extLower, 'adiryad\.claude-rtl-code@(\S+)')).Groups[1].Value

    $okGit = [bool]$gitRaw; $okNode = [bool]$nodeRaw; $okClaude = [bool]$claudeRaw
    $okAg = [bool]$cli; $okCode = [bool]$codeVer; $okRtl = [bool]$rtlVer

    $rule = ([char]0x2500).ToString() * 52
    Write-Host ''
    Write-Host '  Installed and ready' -ForegroundColor Cyan
    Write-Host "  $rule" -ForegroundColor DarkGray
    Write-Check 'Git'               (Format-Detail $okGit $gitVer)       $okGit
    Write-Check 'Node.js'           (Format-Detail $okNode $nodeRaw)     $okNode
    Write-Check 'Antigravity'       (Format-Detail $okAg $agVer)         $okAg
    Write-Check 'Claude in editor'  (Format-Detail $okCode $codeVer)     $okCode
    Write-Check 'Hebrew support'    (Format-Detail $okRtl $rtlVer)       $okRtl
    Write-Check 'Claude command'    (Format-Detail $okClaude $claudeVer) $okClaude
    Write-Host "  $rule" -ForegroundColor DarkGray

    $allOk = $okGit -and $okNode -and $okAg -and $okCode -and $okRtl -and $okClaude
    if ($allOk) {
        Write-Host ''
        Write-Host '  You are all set. Everything is installed and ready to go.' -ForegroundColor Green
        Write-Host ''
    }
    else {
        Write-Host ''
        Write-Note 'Almost there. A few things did not finish installing.'
        Write-Note 'Please run this command again. If it keeps happening, restart your computer and retry.'
        if (-not $okAg -or -not $okCode -or -not $okRtl) {
            Write-Note 'If Antigravity is new, open it once (you will sign in with Google), then run this again.'
        }
        Write-Host ''
    }
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Invoke-Safe {
    param([scriptblock] $Action)
    try { & $Action }
    catch { Write-Verbose "step failed: $($_.Exception.Message)" }
}

function Main {
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Note "This needs PowerShell 5.1 or newer (you have $($PSVersionTable.PSVersion))."
        return
    }

    Write-Banner
    if ($DryRun) { Write-Note 'DRY RUN - nothing will be installed.' }

    Invoke-Safe { Set-ExecutionPolicyIfRestricted }
    Invoke-Safe { Install-Git }
    Invoke-Safe { Install-Node }
    Invoke-Safe { Install-Antigravity }
    Invoke-Safe { Install-Extensions }
    Invoke-Safe { Install-ClaudeCli }

    Show-Results
}

Main
