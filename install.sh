#!/bin/sh
# claude-kit installer (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.sh | sh
#
# Adds every marketplace in the kit, installs the plugins listed against each,
# registers the MCP servers, and wires up the statusline that reads what those
# plugins write. Safe to re-run: an already added marketplace is refreshed
# rather than duplicated, an already installed plugin is updated, and an already
# configured statusline is left alone.

set -eu

# ---- the lists to edit when something joins the kit -----------------------
# Everything below them is generic. Rows are "repo|marketplace-name|plugin ...".

# Mine: forks of caveman and ponytail, each published as its own marketplace
# straight from its repo. Not catalogued in a marketplace.json here, because a
# plugin entry pointing at another GitHub repo is cloned over SSH by Claude Code
# 2.1.233 with no HTTPS fallback, so it fails on any machine without a GitHub
# key. The marketplace clone path does fall back, hence one marketplace each.
MINE='
FanFantom9452/caveman|caveman-per-session|caveman
FanFantom9452/ponytail|ponytail-per-session|ponytail
'

# Everyone else's. Their updates arrive on their schedule; nothing here goes
# stale behind them.
#
# Names are the ids the marketplaces actually publish, which are not always what
# their docs call them — karpathy-guidelines is andrej-karpathy-skills, the LSPs
# drop the -lsp suffix.
UPSTREAM='
obra/superpowers|superpowers-dev|superpowers
anthropics/claude-code|claude-code-plugins|frontend-design security-guidance
Leonxlnx/taste-skill|taste-skill|taste-skill
Owl-Listener/designer-skills|designer-skills|interaction-design ux-strategy
pbakaus/impeccable|impeccable|impeccable
multica-ai/andrej-karpathy-skills|karpathy-skills|andrej-karpathy-skills
Piebald-AI/claude-code-lsps|claude-code-lsps|typescript-language-server pyright rust-analyzer
'

# MCP servers are not plugins and install through a different command entirely.
# "name|command args..."
MCP_SERVERS='
playwright|npx @playwright/mcp@latest
context7|npx -y @upstash/context7-mcp
'

STATUSLINE_URL='https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.sh'
# Modes these plugins start in on a fresh machine. The point of the kit is that
# they are switched on per window when wanted, not left running everywhere.
DORMANT_TOOLS='caveman ponytail'

command -v claude >/dev/null 2>&1 || {
    echo "claude was not found on PATH. Install Claude Code first, then re-run this." >&2
    exit 1
}

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
echo "Config dir : $CFG"
echo

failed=''

# `add` fails when the marketplace is already configured, which on a re-run is
# the normal case rather than an error — refresh it instead, so a re-run picks up
# whatever has been added to it since last time.
add_marketplace() {
    claude plugin marketplace add "$1" && return 0
    echo "  already added - refreshing instead"
    claude plugin marketplace update "$2"
}

# -y because stdout is not a TTY when piped into sh, and install refuses to
# prompt there. Same shape as above: already installed means update, not fail.
install_plugin() {
    echo "  $1@$2"
    claude plugin install "$1@$2" -y && return 0
    claude plugin update "$1@$2"
}

# ---- replace the upstream copies of my forks ------------------------------
# caveman and ponytail exist upstream under the same plugin name, and two copies
# of one plugin means two sets of slash commands, two SessionStart hooks, and two
# writers for the same flag file. Installing the kit is a statement about which
# copy should win, so the other is removed first — and said out loud, because it
# is the one destructive thing this script does.
mine_markets=$(printf '%s\n' "$MINE" | cut -d'|' -f2 | tr '\n' ' ')
mine_plugins=$(printf '%s\n' "$MINE" | cut -d'|' -f3 | tr '\n' ' ')
installed=$(claude plugin list 2>&1 || true)
for p in $mine_plugins; do
    for id in $(printf '%s\n' "$installed" | grep -o "$p@[^ ]*" | sort -u); do
        from=${id#*@}
        case " $mine_markets " in *" $from "*) continue ;; esac
        echo "Replacing $id  (conflicts with my fork)"
        claude plugin uninstall "$id" || true
    done
done

# ---- marketplaces and their plugins ---------------------------------------
# Fed by here-doc rather than a pipe: a piped `while` runs in a subshell, so
# every failure recorded in $failed would be discarded at the end of the loop
# and the summary below would report success it never had.
while IFS='|' read -r repo name plugins; do
    [ -n "$repo" ] || continue
    echo
    echo "$repo:"
    if ! add_marketplace "$repo" "$name"; then
        failed="$failed $name(marketplace)"
        continue
    fi
    for p in $plugins; do
        install_plugin "$p" "$name" || failed="$failed $p@$name"
    done
done <<MARKETPLACES_EOF
$MINE
$UPSTREAM
MARKETPLACES_EOF

# ---- MCP servers ----------------------------------------------------------
# Not plugins: different command, different registry, no marketplace involved.
# `add` fails when the name is taken, which on a re-run means it is already
# there — nothing to do, so that is not counted as a failure.
#
# -s user, because `mcp add` defaults to `local`, which scopes the server to
# whatever directory the installer happened to run in. A one-line setup script
# runs from wherever the terminal opened; the servers belong to the machine.
echo
echo "MCP servers:"
mcp_existing=$(claude mcp list 2>&1 || true)
while IFS='|' read -r name cmd; do
    [ -n "$name" ] || continue
    if printf '%s\n' "$mcp_existing" | grep -q "^[[:space:]]*$name[[:space:]]*:"; then
        echo "  $name - already configured"
        continue
    fi
    echo "  $name"
    # shellcheck disable=SC2086 -- cmd is a deliberate word-split argv
    claude mcp add -s user "$name" -- $cmd || failed="$failed $name(mcp)"
done <<MCP_EOF
$MCP_SERVERS
MCP_EOF

# ---- start dormant --------------------------------------------------------
# Only written when there is no config yet, so a default you set yourself is
# never overwritten by a re-run.
for tool in $DORMANT_TOOLS; do
    tool_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$tool"
    [ -f "$tool_dir/config.json" ] && continue
    mkdir -p "$tool_dir"
    printf '{ "defaultMode": "off" }\n' > "$tool_dir/config.json"
    echo "Dormant    : $tool (defaultMode=off, switch on per window)"
done

# ---- statusline -----------------------------------------------------------
# Skipped when already wired, so re-running to pick up a new plugin does not
# rewrite settings.json and leave another backup behind for no reason.
echo
if grep -q 'statusline\.sh' "$CFG/settings.json" 2>/dev/null; then
    echo "Statusline : already wired, left alone"
else
    echo "Statusline : installing ..."
    curl -fsSL "$STATUSLINE_URL" | sh
fi

echo
if [ -n "$failed" ]; then
    echo "These did not install:$failed" >&2
    echo "Re-run the matching command by hand to see why." >&2
else
    echo "Done. Restart Claude Code to load it."
fi
echo "Switch a mode on for the current window with /caveman ultra or /ponytail full."
