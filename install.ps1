# claude-kit installer (Windows)
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.ps1 | iex"
#
# Adds every marketplace in the kit, installs the plugins listed against each,
# registers the MCP servers, and wires up the statusline that reads what those
# plugins write. Safe to re-run: an already added marketplace is refreshed
# rather than duplicated, an already installed plugin is updated, and an already
# wired statusline has its script re-downloaded while settings.json is left alone.
#
# No `exit` anywhere on purpose — this script is meant to be piped into `iex`,
# where `exit` would take the caller's shell down with it. Fatal problems throw.

# Not 'Stop'. Under 'Stop', anything a native exe writes to stderr becomes a
# terminating error the moment `2>&1` merges it into the success stream, so a
# single plugin that fails to install would abort the whole run — and the
# $failed summary below, whose entire job is to report those, would never
# print. Failures are collected explicitly; genuinely fatal states `throw`.
$ErrorActionPreference = 'Continue'

# ---- the lists to edit when something joins the kit -----------------------
# Everything below them is generic.

# Mine: two forks and one plugin of my own, each published as its own
# marketplace straight from its repo. Not catalogued in a marketplace.json here,
# because a plugin entry pointing at another GitHub repo is cloned over SSH by
# Claude Code 2.1.233 with no HTTPS fallback, so it fails on any machine without
# a GitHub key. The marketplace clone path does fall back, hence one marketplace
# each.
#
# fankeel's marketplace has no suffix because there is no upstream to sit beside.
$Mine = @(
    @{ Repo = 'FanFantom9452/caveman';  Name = 'caveman-per-session';  Plugins = @('caveman') }
    @{ Repo = 'FanFantom9452/FanKeel';  Name = 'fankeel';              Plugins = @('fankeel') }
    @{ Repo = 'FanFantom9452/ponytail'; Name = 'ponytail-per-session'; Plugins = @('ponytail') }
)

# Everyone else's. Their updates arrive on their schedule; nothing here goes
# stale behind them.
#
# Names are the ids the marketplaces actually publish, which are not always what
# their docs call them — karpathy-guidelines is andrej-karpathy-skills, the LSPs
# drop the -lsp suffix.
$Upstream = @(
    @{ Repo = 'obra/superpowers';                  Name = 'superpowers-dev';     Plugins = @('superpowers') }
    @{ Repo = 'anthropics/claude-code';            Name = 'claude-code-plugins'; Plugins = @('frontend-design', 'security-guidance') }
    @{ Repo = 'Leonxlnx/taste-skill';              Name = 'taste-skill';         Plugins = @('taste-skill') }
    @{ Repo = 'Owl-Listener/designer-skills';      Name = 'designer-skills';     Plugins = @('interaction-design', 'ux-strategy') }
    @{ Repo = 'pbakaus/impeccable';                Name = 'impeccable';          Plugins = @('impeccable') }
    @{ Repo = 'multica-ai/andrej-karpathy-skills'; Name = 'karpathy-skills';     Plugins = @('andrej-karpathy-skills') }
    @{ Repo = 'Piebald-AI/claude-code-lsps';       Name = 'claude-code-lsps';    Plugins = @('typescript-language-server', 'pyright', 'rust-analyzer') }
)

# Marketplaces left on manual update. Claude Code refreshes a marketplace on
# startup only when its known_marketplaces.json entry says autoUpdate, and it
# fills that field in from a hardcoded list of Anthropic's own marketplaces —
# nothing here is on it. The block at the bottom turns it on for everything
# installed above except these. The LSP marketplace ships language-server
# binaries, which are worth taking deliberately rather than on a startup you
# did not plan for.
$NoAutoUpdate = @('claude-code-lsps')

# MCP servers are not plugins and install through a different command entirely.
$McpServers = @(
    @{ Name = 'playwright'; Args = @('npx', '@playwright/mcp@latest') }
    @{ Name = 'context7';   Args = @('npx', '-y', '@upstash/context7-mcp') }
)

$StatuslineUrl = 'https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.ps1'
# The script on its own, for the already-wired case at the bottom. A kit whose
# whole promise is "latest" is no use if the one file that runs on every render
# is the one thing it never updates.
$StatuslineScript = 'https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/statusline.ps1'
# Modes these plugins start in on a fresh machine. The point of the kit is that
# they are switched on per window when wanted, not left running everywhere.
$DormantTools  = @('caveman', 'ponytail')   # not fankeel: its mode is owning a task

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Everything this script runs writes UTF-8 — claude for its plugin and MCP
# output, and TokenBar for the statusline preview at the end — but the console
# renders those bytes in whatever code page it happens to be on, which is 950 on
# a Traditional Chinese Windows, 936 on a Simplified one, 932 on a Japanese one.
# Nothing here is non-ASCII itself, so the mojibake arrives entirely from the
# children, and one setting up front covers all of them.
#
# OutputEncoding only, never InputEncoding: that setter throws on Windows
# PowerShell when stdin is redirected, which is exactly how this script is run.
#
# Deliberately not put back afterwards. Claude Code writes UTF-8 too, so
# restoring the old page would only hand the mojibake to the thing you run next.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'claude was not found on PATH. Install Claude Code first, then re-run this.'
}

$Cfg = if ($env:CLAUDE_CONFIG_DIR)  { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)               { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)    { Join-Path $env:USERPROFILE '.claude' }
       else { throw 'Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry.' }

Write-Host "Config dir : $Cfg"
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

# ---- replace the upstream copies of my forks ------------------------------
# caveman and ponytail exist upstream under the same plugin name, and two copies
# of one plugin means two sets of slash commands, two SessionStart hooks, and two
# writers for the same flag file. Installing the kit is a statement about which
# copy should win, so the other is removed first — and said out loud, because it
# is the one destructive thing this script does.
$mineMarkets = $Mine | ForEach-Object { $_.Name }
$minePlugins = $Mine | ForEach-Object { $_.Plugins }
$installed = (& claude plugin list 2>&1) -join "`n"
foreach ($p in $minePlugins) {
    foreach ($hit in [regex]::Matches($installed, "\b$([regex]::Escape($p))@(\S+)")) {
        $from = $hit.Groups[1].Value
        if ($mineMarkets -contains $from) { continue }
        Write-Host "Replacing $p@$from  (conflicts with my fork)"
        & claude plugin uninstall "$p@$from" 2>&1 | Out-Host
    }
}

# ---- marketplaces and their plugins ---------------------------------------
foreach ($m in ($Mine + $Upstream)) {
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
#
# -s user, because `mcp add` defaults to `local`, which scopes the server to
# whatever directory the installer happened to run in. A one-line setup script
# runs from wherever the terminal opened; the servers belong to the machine.
Write-Host ''
Write-Host "MCP servers:"
$mcpExisting = (& claude mcp list 2>&1) -join "`n"
foreach ($s in $McpServers) {
    if ($mcpExisting -match "(?m)^\s*$([regex]::Escape($s.Name))\s*:") {
        Write-Host "  $($s.Name) - already configured"
        continue
    }
    Write-Host "  $($s.Name)"
    & claude mcp add -s user $s.Name -- @($s.Args) 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { $failed += "$($s.Name) (mcp)" }
}

# ---- start dormant --------------------------------------------------------
# Only written when there is no config yet, so a default you set yourself is
# never overwritten by a re-run.
foreach ($tool in $DormantTools) {
    $toolDir = Join-Path $env:APPDATA $tool
    $toolCfg = Join-Path $toolDir 'config.json'
    if (Test-Path $toolCfg) { continue }
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    [System.IO.File]::WriteAllText($toolCfg, "{ `"defaultMode`": `"off`" }`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "Dormant    : $tool (defaultMode=off, switch on per window)"
}

# ---- statusline -----------------------------------------------------------
# The script is always re-downloaded; settings.json is only rewritten when
# nothing is wired yet. Those are two different questions and the old code
# answered both with one skip: re-running to pick up a new plugin would leave a
# fresh settings.json backup behind for a file whose contents did not change, but
# it also meant a machine that already had the statusline could never be given a
# fixed one. Running the full installer covers the first case; fetching the
# script alone covers the second.
#
# Overwriting the script discards local edits to the toggle block at its top.
# Said out loud rather than done quietly — it is the second destructive thing
# this script does.
$Settings = Join-Path $Cfg 'settings.json'
$wiredPath = $null
if (Test-Path $Settings) {
    try {
        $raw = (Get-Content -LiteralPath $Settings -Raw).TrimStart([char]0xFEFF)
        if ($raw.Trim()) {
            $cmd = ($raw | ConvertFrom-Json).statusLine.command
            if ($cmd -and $cmd -like '*statusline.ps1*') {
                # Update the file the wired command actually runs. An install kept
                # outside the config dir would otherwise be shadowed by a fresh copy
                # next to it that nothing reads, and the run would report success.
                $m = [regex]::Match($cmd, '"([^"]*statusline\.ps1)"')
                if (-not $m.Success) { $m = [regex]::Match($cmd, '([^\s"]*statusline\.ps1)') }
                $wiredPath = if ($m.Success) { $m.Groups[1].Value } else { Join-Path $Cfg 'statusline.ps1' }
            }
        }
    } catch { }
}

Write-Host ''
if ($wiredPath) {
    Write-Host "Statusline : already wired - updating the script, settings.json left alone"
    Write-Host "             $wiredPath"
    Write-Host "             (local edits to its toggle block are overwritten)"
    # Fetched beside the target and moved into place, so a transfer that dies
    # halfway cannot leave a half-written script rendering on every keystroke.
    $tmp = "$wiredPath.new"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $StatuslineScript -OutFile $tmp -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $wiredPath -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Write-Warning "  statusline script: $($_.Exception.Message)"
        $failed += 'statusline (script)'
    }
} else {
    Write-Host "Statusline : installing ..."
    Invoke-RestMethod -Uri $StatuslineUrl | Invoke-Expression
}

# ---- auto-update ----------------------------------------------------------
# Without this every marketplace above sits at the commit it was cloned at until
# someone re-runs this installer by hand, which is the opposite of what a kit is
# for. The kit's whole promise is that a machine stays current on its own.
#
# Written to settings.json rather than to plugins/known_marketplaces.json,
# because Claude Code copies the autoUpdate field out of extraKnownMarketplaces
# into that file at every session start. Declared here it re-asserts itself;
# written there it is one shot that the next `marketplace add` can quietly undo.
#
# Last in the script on purpose. The statusline branch above can hand
# settings.json to a second installer entirely, so this has to be the final word
# on that file rather than something that installer overwrites.
Write-Host ''
Write-Host "Auto-update:"
try {
    $doc = $null
    $old = ''
    if (Test-Path $Settings) {
        $old = Get-Content -LiteralPath $Settings -Raw
        $body = $old.TrimStart([char]0xFEFF)
        if ($body.Trim()) { $doc = $body | ConvertFrom-Json }
    }
    if (-not $doc) { $doc = [pscustomobject]@{} }

    $known = $doc.extraKnownMarketplaces
    if (-not $known) {
        $known = [pscustomobject]@{}
        $doc | Add-Member -NotePropertyName 'extraKnownMarketplaces' -NotePropertyValue $known -Force
    }
    foreach ($m in ($Mine + $Upstream)) {
        $on = -not ($NoAutoUpdate -contains $m.Name)
        $known | Add-Member -NotePropertyName $m.Name -NotePropertyValue ([pscustomobject]@{
            source     = [pscustomobject]@{ source = 'github'; repo = $m.Repo }
            autoUpdate = $on
        }) -Force
        Write-Host ("  {0,-22} {1}" -f $m.Name, $(if ($on) { 'on' } else { 'manual' }))
    }

    # Compared before writing so that a re-run which changes nothing does not
    # leave a fresh backup of a file whose contents are identical.
    $new = ($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    if ($new -ne $old) {
        if ($old) { Copy-Item -LiteralPath $Settings -Destination "$Settings.bak-kit" -Force }
        [System.IO.File]::WriteAllText($Settings, $new, [System.Text.UTF8Encoding]::new($false))
    } else {
        Write-Host "  settings.json already says this"
    }
} catch {
    Write-Warning "  auto-update: $($_.Exception.Message)"
    $failed += 'auto-update (settings.json)'
}

Write-Host ''
if ($failed.Count) {
    Write-Warning ("These did not install: " + ($failed -join ', ') + ". Run the matching 'claude plugin install <name>@<marketplace>' by hand to see why.")
} else {
    Write-Host "Done. Restart Claude Code to load it."
}
Write-Host "Switch a mode on for the current window with /caveman ultra or /ponytail full."
