# claude-kit installer (Windows)
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.ps1 | iex"
#
# Adds this marketplace, installs everything listed in it, and wires up the
# statusline that reads what those plugins write. Safe to re-run: an already
# added marketplace is refreshed rather than duplicated, an already installed
# plugin is updated, and an already configured statusline is left alone.
#
# No `exit` anywhere on purpose — this script is meant to be piped into `iex`,
# where `exit` would take the caller's shell down with it. Fatal problems throw.

$ErrorActionPreference = 'Stop'

# The list to edit when something joins the kit. Everything below is generic.
$MarketplaceRepo = 'FanFantom9452/claude-kit'
$MarketplaceName = 'kit'
$Plugins         = @('caveman', 'ponytail')
$StatuslineUrl   = 'https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.ps1'
# Modes these plugins start in on a fresh machine. The point of the kit is that
# they are switched on per window when wanted, not left running everywhere.
$DormantTools    = @('caveman', 'ponytail')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'claude was not found on PATH. Install Claude Code first, then re-run this.'
}

$Cfg = if ($env:CLAUDE_CONFIG_DIR)  { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)               { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)    { Join-Path $env:USERPROFILE '.claude' }
       else { throw 'Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry.' }

Write-Host "Config dir : $Cfg"
Write-Host "Marketplace: $MarketplaceRepo"
Write-Host ''

# ---- marketplace ----------------------------------------------------------
# `add` fails when it is already configured, which on a re-run is the normal
# case rather than an error — refresh it instead, so a re-run picks up entries
# added to marketplace.json since last time.
& claude plugin marketplace add $MarketplaceRepo 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "Already added - refreshing instead."
    & claude plugin marketplace update $MarketplaceName 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not add or refresh marketplace '$MarketplaceName'." }
}

# ---- replace conflicting installs -----------------------------------------
# The same plugin name from another marketplace collides with this one: same
# slash commands, same hooks, same flag files. Installing the kit is a statement
# about which copy should win, so the other is removed first — and said out loud,
# because it is the one destructive thing this script does.
$installed = (& claude plugin list 2>&1) -join "`n"
foreach ($p in $Plugins) {
    foreach ($hit in [regex]::Matches($installed, "\b$([regex]::Escape($p))@(\S+)")) {
        $from = $hit.Groups[1].Value
        if ($from -eq $MarketplaceName) { continue }
        Write-Host "Replacing  : $p@$from  (conflicts with $p@$MarketplaceName)"
        & claude plugin uninstall "$p@$from" 2>&1 | Out-Host
    }
}

# ---- plugins --------------------------------------------------------------
# -y because stdout is not a TTY under `irm | iex`, and install refuses to
# prompt there. Same fallback shape: installed already means update, not fail.
$failed = @()
foreach ($p in $Plugins) {
    Write-Host ''
    Write-Host "Installing $p@$MarketplaceName ..."
    & claude plugin install "$p@$MarketplaceName" -y 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        & claude plugin update "$p@$MarketplaceName" 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { $failed += $p }
    }
}

# ---- start dormant --------------------------------------------------------
# Only written when there is no config yet, so a default you set yourself is
# never overwritten by a re-run.
foreach ($tool in $DormantTools) {
    $toolDir  = Join-Path $env:APPDATA $tool
    $toolCfg  = Join-Path $toolDir 'config.json'
    if (Test-Path $toolCfg) { continue }
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    [System.IO.File]::WriteAllText($toolCfg, "{ `"defaultMode`": `"off`" }`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "Dormant    : $tool (defaultMode=off, switch on per window)"
}

# ---- statusline -----------------------------------------------------------
# Skipped when already wired, so re-running to pick up a new plugin does not
# rewrite settings.json and leave another backup behind for no reason.
$Settings = Join-Path $Cfg 'settings.json'
$wired = $false
if (Test-Path $Settings) {
    try {
        $raw = (Get-Content -LiteralPath $Settings -Raw).TrimStart([char]0xFEFF)
        if ($raw.Trim()) {
            $cmd = ($raw | ConvertFrom-Json).statusLine.command
            if ($cmd -and $cmd -like '*statusline.ps1*') { $wired = $true }
        }
    } catch { }
}

Write-Host ''
if ($wired) {
    Write-Host "Statusline : already wired, left alone"
} else {
    Write-Host "Statusline : installing ..."
    Invoke-RestMethod -Uri $StatuslineUrl | Invoke-Expression
}

Write-Host ''
if ($failed.Count) {
    Write-Warning ("These did not install: " + ($failed -join ', ') + ". Run 'claude plugin install <name>@$MarketplaceName -y' to see why.")
} else {
    Write-Host "Done. Restart Claude Code to load it."
}
Write-Host "Switch a mode on for the current window with /caveman ultra or /ponytail full."
