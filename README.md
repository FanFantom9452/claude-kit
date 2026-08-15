# claude-kit

My Claude Code setup, in one command. New machine, one line, done.

## Install

**Windows** — works in both CMD and PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.ps1 | iex"
```

**Linux / macOS**:

```sh
curl -fsSL https://raw.githubusercontent.com/FanFantom9452/claude-kit/main/install.sh | sh
```

Restart Claude Code afterwards.

Safe to re-run — that is how you pick up anything added to the kit since last
time. An already added marketplace is refreshed rather than duplicated, an
installed plugin is updated, and a statusline that is already wired is left
alone instead of rewriting `settings.json` for nothing.

## What it installs

**Mine** — forks, each published as its own marketplace:

| Marketplace | Plugin | |
|---|---|---|
| [caveman-per-session](https://github.com/FanFantom9452/caveman) | `caveman` | Ultra-compressed prose |
| [ponytail-per-session](https://github.com/FanFantom9452/ponytail) | `ponytail` | Lazy senior dev — YAGNI, stdlib first, shortest diff |

Forks of [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) and
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail), each with
one change: the mode flag is keyed by session id instead of being one file per
machine. Upstream keeps it in `~/.claude/.caveman-active`, shared by every
window, so switching mode in one switched it in all of them and opening a new
window reset the others to the default. Forked so each terminal carries its own
level.

The marketplace name carries the `-per-session` suffix so a machine that already
has upstream's `caveman` or `ponytail` marketplace can keep it. The plugin name
does not — it is still `caveman`, which really does collide, so the installer
uninstalls the other copy before installing this one and says so when it does.

**Everyone else's** — listed in the installers, so their updates arrive on their
schedule and nothing goes stale behind them:

| Marketplace | Plugins |
|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | `superpowers` — brainstorming, TDD, debugging, verification |
| [anthropics/claude-code](https://github.com/anthropics/claude-code) | `frontend-design`, `security-guidance` |
| [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) | `taste-skill` — anti-slop frontend direction |
| [Owl-Listener/designer-skills](https://github.com/Owl-Listener/designer-skills) | `interaction-design`, `ux-strategy` (2 of its 33) |
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | `impeccable` — design-language audit / harden / critique |
| [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | `andrej-karpathy-skills` — guard-rails for LLM coding mistakes |
| [Piebald-AI/claude-code-lsps](https://github.com/Piebald-AI/claude-code-lsps) | `typescript-language-server`, `pyright`, `rust-analyzer` |

Published ids, not the names the docs use — `karpathy-guidelines` is really
`andrej-karpathy-skills`, and the language servers drop the `-lsp` suffix.

**MCP servers** — a different command and a different registry, no marketplace
involved: `playwright` and `context7`. context7 works unauthenticated for a
while and then wants a key; set `CONTEXT7_API_KEY` if you hit its rate limit.

**Statusline** — [TokenBar](https://github.com/FanFantom9452/ClaudeCodeCLI-TokenBar):
context window, 5h and 7d quota, git state, and a badge per active mode.

### Deliberately not here

`explanatory-output-style` pulls the opposite way from caveman — one wants more
explanation, the other wants less — so running both just makes them argue. The
official workflow plugins (`code-review`, `commit-commands`, `feature-dev`,
`pr-review-toolkit`, …) overlap what Claude Code and superpowers already do.
`github`, `greptile` and the Hugging Face bundle are situational rather than
per-machine. All of them are one `claude plugin install` away when wanted.

## They start switched off

Both plugins are installed dormant (`defaultMode: "off"`), because the point of
having them per-session is to switch them on where you want them:

```
/caveman ultra      this window, until you change it
/ponytail full      likewise
```

Only written on a fresh machine — a default you have set yourself is never
overwritten by a re-run. To change it:

```
%APPDATA%\caveman\config.json      { "defaultMode": "off" }
%APPDATA%\ponytail\config.json     Linux/macOS: ~/.config/<name>/config.json
```

The statusline shows which window is in which mode, reading the flags each
plugin writes at `~/.claude/modes/<session_id>/`:

```
[CAVEMAN:ULTRA] | [PONYTAIL:FULL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
ctx ███▊░░░░░░  38%    ·    5h ██████▌░░░  66%   ↻ 1h 46m    ·    7d █████▊░░░░  58%   ↻ 2d 12h 30m    -6%
```

## Uninstall

```
claude plugin uninstall caveman@caveman-per-session
claude plugin uninstall ponytail@ponytail-per-session
claude plugin marketplace remove caveman-per-session
claude plugin marketplace remove ponytail-per-session
```

Each plugin removes its own flags on the way out, including the per-session ones,
and leaves any other plugin's alone. The statusline has its own uninstaller in the
TokenBar repo.

## Adding to the kit

One row, in both installers — `$Mine` / `$Upstream` in `install.ps1`, `MINE` /
`UPSTREAM` in `install.sh`:

```
repo  |  marketplace name  |  plugins to install from it
```

The marketplace name is the `name` field inside that repo's
`.claude-plugin/marketplace.json`, not the repo name, and it is what
`<plugin>@<marketplace>` resolves against. Machines that already have the kit
pick the new row up on the next re-run.

A plugin written from scratch goes in its own repo with its own
`marketplace.json`, then gets a row like any other. It cannot be catalogued here
and pointed at another repo: Claude Code 2.1.233 clones a cross-repo plugin
`source` over SSH with no HTTPS fallback, so that route fails on any machine
without a GitHub key. Marketplace clones do fall back, which is why every entry
above is one marketplace of its own.
