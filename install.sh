#!/bin/sh
# claude-kit installer (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.sh | sh
#
# Adds every marketplace in the kit, installs the plugins listed against each,
# registers the MCP servers, and wires up the statusline that reads what those
# plugins write. Safe to re-run: an already added marketplace is refreshed
# rather than duplicated, an already installed plugin is updated, and an already
# wired statusline has its script re-downloaded while settings.json is left alone.

set -eu

# ---- the lists to edit when something joins the kit -----------------------
# Everything below them is generic. Rows are "repo|marketplace-name|plugin ...".

# Mine: two forks and one plugin of my own, each published as its own
# marketplace straight from its repo. Not catalogued in a marketplace.json here,
# because a plugin entry pointing at another GitHub repo is cloned over SSH by
# Claude Code 2.1.233 with no HTTPS fallback, so it fails on any machine without
# a GitHub key. The marketplace clone path does fall back, hence one marketplace
# each.
#
# fankeel's marketplace has no suffix because there is no upstream to sit beside.
MINE='
FanFantom9452/caveman|caveman-per-session|caveman
FanFantom9452/FanKeel|fankeel|fankeel
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

# Marketplaces left on manual update. Claude Code refreshes a marketplace on
# startup only when its known_marketplaces.json entry says autoUpdate, and it
# fills that field in from a hardcoded list of Anthropic's own marketplaces —
# nothing here is on it. The block at the bottom turns it on for everything
# installed above except these. The LSP marketplace ships language-server
# binaries, which are worth taking deliberately rather than on a startup you
# did not plan for.
NO_AUTO_UPDATE='claude-code-lsps'

# MCP servers are not plugins and install through a different command entirely.
# "name|command args..."
MCP_SERVERS='
playwright|npx @playwright/mcp@latest
context7|npx -y @upstash/context7-mcp
'

STATUSLINE_URL='https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.sh'
# The script on its own, for the already-wired case at the bottom. A kit whose
# whole promise is "latest" is no use if the one file that runs on every render
# is the one thing it never updates.
STATUSLINE_SCRIPT='https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/statusline.sh'
# Modes these plugins start in on a fresh machine. The point of the kit is that
# they are switched on per window when wanted, not left running everywhere.
DORMANT_TOOLS='caveman ponytail'   # not fankeel: its mode is owning a task

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
echo
if grep -q 'statusline\.sh' "$CFG/settings.json" 2>/dev/null; then
    # Update the file the wired command actually runs. An install kept outside the
    # config dir would otherwise be shadowed by a fresh copy next to it that
    # nothing reads, and the run would report success. perl is what the statusline
    # itself needs, so it is normally here; the config-dir default covers the rest.
    sl=$(perl -MJSON::PP -e '
        open my $fh, "<", $ARGV[0] or exit 1;
        local $/; my $c = <$fh>; close $fh;
        $c =~ s/^\xEF\xBB\xBF//;
        my $j = eval { JSON::PP->new->decode($c) } or exit 1;
        my $cmd = $j->{statusLine}{command};
        exit 1 unless defined $cmd;
        # Most explicit first. The bare-path branch has to test -e rather than
        # just trusting the tail: TokenBar writes the path alone, which may well
        # contain a space, but "sh /some/where/statusline.sh" ends the same way
        # and taking all of that as the path writes the file into nowhere.
        if ($cmd =~ m{"([^"]*statusline\.sh)"})    { print $1;   exit 0 }
        if (-e $cmd && $cmd =~ m{statusline\.sh$}) { print $cmd; exit 0 }
        if ($cmd =~ m{(\S*statusline\.sh)})        { print $1;   exit 0 }
        exit 1;
    ' "$CFG/settings.json" 2>/dev/null) || sl=''
    [ -n "$sl" ] || sl="$CFG/statusline.sh"

    echo "Statusline : already wired - updating the script, settings.json left alone"
    echo "             $sl"
    echo "             (local edits to its toggle block are overwritten)"
    # Fetched beside the target and moved into place, so a transfer that dies
    # halfway cannot leave a half-written script rendering on every keystroke.
    if { command -v curl >/dev/null 2>&1 && curl -fsSL "$STATUSLINE_SCRIPT" -o "$sl.new"; } ||
       { command -v wget >/dev/null 2>&1 && wget -qO "$sl.new" "$STATUSLINE_SCRIPT"; }; then
        mv "$sl.new" "$sl"
        chmod +x "$sl"
    else
        rm -f "$sl.new"
        failed="$failed statusline(script)"
    fi
else
    echo "Statusline : installing ..."
    curl -fsSL "$STATUSLINE_URL" | sh
fi

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
#
# perl again, for the same reason the statusline branch uses it: it is what the
# statusline itself needs, so it is already here, and JSON::PP has been core
# since 5.14. A settings.json that does not parse is reported rather than
# rewritten — better to leave auto-update off than to flatten a file by guessing.
echo
echo "Auto-update:"
if ! { printf '%s\n%s\n' "$MINE" "$UPSTREAM" | perl -MJSON::PP -e '
    my ($path, $skiplist) = @ARGV;
    my %skip = map { ($_ => 1) } split " ", $skiplist;

    my ($doc, $old) = ({}, "");
    if (open my $fh, "<", $path) {
        local $/;
        $old = <$fh>;
        close $fh;
        $old = "" unless defined $old;
        my $c = $old;
        $c =~ s/^\xEF\xBB\xBF//;
        if ($c =~ /\S/) {
            $doc = eval { JSON::PP->new->decode($c) };
            unless (ref $doc eq "HASH") {
                print STDERR "  settings.json does not parse - left alone\n";
                exit 1;
            }
        }
    }

    my $known = $doc->{extraKnownMarketplaces} ||= {};
    while (<STDIN>) {
        chomp;
        next unless /\S/;
        my ($repo, $name) = split /\|/;
        my $on = $skip{$name} ? JSON::PP::false : JSON::PP::true;
        $known->{$name} = { source => { source => "github", repo => $repo },
                            autoUpdate => $on };
        printf "  %-22s %s\n", $name, ($skip{$name} ? "manual" : "on");
    }

    # canonical so a re-run that changes nothing produces byte-identical output,
    # and therefore neither rewrites the file nor leaves a fresh backup.
    my $new = JSON::PP->new->pretty->canonical->encode($doc);
    if ($new eq $old) {
        print "  settings.json already says this\n";
        exit 0;
    }
    if (length $old) {
        open my $b, ">", "$path.bak-kit" or die "cannot write backup: $!\n";
        print $b $old;
        close $b;
    }
    open my $out, ">", $path or die "cannot write $path: $!\n";
    print $out $new;
    close $out;
' "$CFG/settings.json" "$NO_AUTO_UPDATE"; }; then
    failed="$failed auto-update(settings.json)"
fi

echo
if [ -n "$failed" ]; then
    echo "These did not install:$failed" >&2
    echo "Re-run the matching command by hand to see why." >&2
else
    echo "Done. Restart Claude Code to load it."
fi
echo "Switch a mode on for the current window with /caveman ultra or /ponytail full."
