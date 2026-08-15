#!/bin/sh
# claude-kit installer (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.sh | sh
#
# Adds this marketplace, installs everything listed in it, and wires up the
# statusline that reads what those plugins write. Safe to re-run: an already
# added marketplace is refreshed rather than duplicated, an already installed
# plugin is updated, and an already configured statusline is left alone.

set -eu

# The list to edit when something joins the kit. Everything below is generic.
MARKETPLACE_REPO='FanFantom9452/claude-kit'
MARKETPLACE_NAME='kit'
PLUGINS='caveman ponytail'
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
echo "Marketplace: $MARKETPLACE_REPO"
echo

# ---- marketplace ----------------------------------------------------------
# `add` fails when it is already configured, which on a re-run is the normal
# case rather than an error — refresh it instead, so a re-run picks up entries
# added to marketplace.json since last time.
if ! claude plugin marketplace add "$MARKETPLACE_REPO"; then
    echo "Already added - refreshing instead."
    claude plugin marketplace update "$MARKETPLACE_NAME" || {
        echo "Could not add or refresh marketplace '$MARKETPLACE_NAME'." >&2
        exit 1
    }
fi

# ---- plugins --------------------------------------------------------------
# -y because stdout is not a TTY when piped into sh, and install refuses to
# prompt there. Same fallback shape: installed already means update, not fail.
failed=''
for p in $PLUGINS; do
    echo
    echo "Installing $p@$MARKETPLACE_NAME ..."
    if ! claude plugin install "$p@$MARKETPLACE_NAME" -y; then
        claude plugin update "$p@$MARKETPLACE_NAME" || failed="$failed $p"
    fi
done

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
    echo "These did not install:$failed. Run 'claude plugin install <name>@$MARKETPLACE_NAME -y' to see why." >&2
else
    echo "Done. Restart Claude Code to load it."
fi
echo "Switch a mode on for the current window with /caveman ultra or /ponytail full."
