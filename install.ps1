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

# ---- the lists to edit when something joins the kit -----------------------
# Everything below them is generic.

# Mine: the two forks, catalogued in this repo's own marketplace.json.
$MarketplaceRepo = 'FanFantom9452/claude-kit'
$MarketplaceName = 'kit'
$Plugins         = @('caveman', 'ponytail')

# Everyone else's. Listed here rather than re-catalogued in marketplace.json, so
# upstream stays the source of truth: their updates arrive on their schedule and
# nothing here goes stale behind them.
#
# Names are the ids the marketplaces actually publish, which are not always what
# their docs call them — karpathy-guidelines is andrej-karpathy-skills, the LSPs
# drop the -lsp suffix.
$Upstream = @(
    @{ Repo = 'obra/superpowers';                 Name = 'superpowers-dev';      Plugins = @('superpowers') }
    @{ Repo = 'anthropics/claude-code';           Name = 'claude-code-plugins';  Plugins = @('frontend-design', 'security-guidance') }
    @{ Repo = 'Leonxlnx/taste-skill';             Name = 'taste-skill';          Plugins = @('taste-skill') }
    @{ Repo = 'Owl-Listener/designer-skills';     Name = 'designer-skills';      Plugins = @('interaction-design', 'ux-strategy') }
    @{ Repo = 'pbakaus/impeccable';               Name = 'impeccable';           Plugins = @('impeccable') }
    @{ Repo = 'multica-ai/andrej-karpathy-skills'; Name = 'karpathy-skills';     Plugins = @('andrej-karpathy-skills') }
    @{ Repo = 'Piebald-AI/claude-code-lsps';      Name = 'claude-code-lsps';     Plugins = @('typescript-language-server', 'pyright', 'rust-analyzer') }
)

# MCP servers are not plugins and install through a different command entirely.
$McpServers = @(
    @{ Name = 'playwright'; Args = @('npx', '@playwright/mcp@latest') }
    @{ Name = 'context7';   Args = @('npx', '-y', '@upstash/context7-mcp') }
)

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

$failed = @()

# `add` fails when the marketplace is already configured, which on a re-run is
# the normal case rather than an error — refresh it instead, so a re-run picks up
# whatever has been added to it since last time.
function Add-Marketplace($repo, $name) {
    & claude plugin marketplace add $repo 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Host "  already added - refreshing instead"
    & claude plugin marketplace update $name 2>&1 | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# -y because stdout is not a TTY under `irm | iex`, and install refuses to prompt
# there. Same shape as above: already installed means update, not fail.
function Install-Plugin($plugin, $market) {
    Write-Host "  $plugin@$market"
    & claude plugin install "$plugin@$market" -y 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { return $true }
    & claude plugin update "$plugin@$market" 2>&1 | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# ---- mine -----------------------------------------------------------------
Write-Host "Mine:"
if (-not (Add-Marketplace $MarketplaceRepo $MarketplaceName)) {
    throw "Could not add or refresh marketplace '$MarketplaceName'."
}

# The same plugin name from another marketplace collides with this one: same
# slash commands, same hooks, same flag files. Installing the kit is a statement
# about which copy should win, so the other is removed first — and said out loud,
# because it is the one destructive thing this script does.
$installed = (& claude plugin list 2>&1) -join "`n"
foreach ($p in $Plugins) {
    foreach ($hit in [regex]::Matches($installed, "\b$([regex]::Escape($p))@(\S+)")) {
        $from = $hit.Groups[1].Value
        if ($from -eq $MarketplaceName) { continue }
        Write-Host "  replacing $p@$from  (conflicts with $p@$MarketplaceName)"
        & claude plugin uninstall "$p@$from" 2>&1 | Out-Host
    }
}
foreach ($p in $Plugins) {
    if (-not (Install-Plugin $p $MarketplaceName)) { $failed += "$p@$MarketplaceName" }
}

# ---- everyone else's ------------------------------------------------------
foreach ($m in $Upstream) {
    Write-Host ''
    Write-Host "$($m.Repo):"
    if (-not (Add-Marketplace $m.Repo $m.Name)) {
        $failed += "$($m.Name) (marketplace)"
        continue
    }
    foreach ($p in $m.Plugins) {
        if (-not (Install-Plugin $p $m.Name)) { $failed += "$p@$($m.Name)" }
    }
}

# ---- MCP servers ----------------------------------------------------------
# Not plugins: different command, different registry, no marketplace involved.
# `add` fails when the name is taken, which on a re-run means it is already
# there — nothing to do, so that is not counted as a failure.
Write-Host ''
Write-Host "MCP servers:"
$mcpExisting = (& claude mcp list 2>&1) -join "`n"
foreach ($s in $McpServers) {
    if ($mcpExisting -match "(?m)^\s*$([regex]::Escape($s.Name))\s*:") {
        Write-Host "  $($s.Name) - already configured"
        continue
    }
    Write-Host "  $($s.Name)"
    & claude mcp add $s.Name -- @($s.Args) 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { $failed += "$($s.Name) (mcp)" }
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
