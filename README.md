# ghostty-linear

Turn Ghostty into a tmux-backed Linear cockpit: boot into a status page of your
active Linear tickets, spin up `claude` sessions per ticket (each in its own git
worktree, briefed via the Linear + GitHub MCPs), and flip between them.

## One-time setup

1. **Store your Linear key** (from <https://linear.app/settings/api>):
   ```
   ~/.config/ghostty-linear/bin/gl-setup
   ```
   Stored in the macOS Keychain (service `ghostty-linear-token`). This also runs
   the first ticket fetch.

2. **Restart Ghostty**, then type **`arcade`** to start (or reattach to) the
   cockpit. It prints a short version banner and drops you into the dashboard.
   (Ghostty opens a normal shell now; to boot straight into the dashboard
   instead, uncomment the `command =` line in `~/.config/ghostty/config`.) The
   first `claude` you open installs nothing extra — the `linear` and `github`
   MCP servers were registered into `~/.claude.json` at user scope during
   install.

## Keys

| Key | Where | Action |
|-----|-------|--------|
| `↑`/`↓` (or `j`/`k`) | dashboard | move selection (paginates the list) |
| `Enter` | dashboard | open the selected ticket — attach if live, else create it. In split view, full-screens (zooms) its claude |
| `cmd+Return` | anywhere | open/attach the selected ticket (same as Enter, works from inside a session) |
| `` cmd+` `` | anywhere | jump back to the dashboard (sessions keep running) |
| `cmd+Y` | anywhere | toggle the **cockpit split**: dashboard pinned left, the selected ticket's claude on the right. Press again to close it |
| `r` | dashboard | refresh tickets from Linear + GitHub now |
| `o` | dashboard | open the selected ticket in the browser |
| `q` | dashboard | detach (reopen Ghostty to reattach) |

**Cockpit split (single window).** `cmd+Y` puts the dashboard on the left and the
selected ticket's claude on the right, in one window you stay in. While it's
open, **moving the selection live-previews that ticket's claude on the right**
(after a brief settle) — but only for tickets that already have a running
session. Press **`Enter` to full-screen (zoom) the selected ticket's claude**
(starting it first if needed); `` cmd+` `` (back to dashboard) or `C-b z`
restores the split. Focus stays on the dashboard while cycling; click the right
pane (or `C-b →`) to type into claude. The layout is fixed (dashboard always
left), so if a pane ever ends up out of place it snaps back on the next
toggle/preview.

`cmd+Return`/`` cmd+` ``/`cmd+Y` are Ghostty keybinds that send the tmux prefix
(`C-b`) + `n/g/y`; the matching tmux bindings live in `tmux.conf`. (`cmd+Return`
overrides Ghostty's default fullscreen toggle.)

## What a spawned session gets

- Its own **git worktree** at `~/worktrees/<ticket>` on the ticket's branch
  (Linear's `gitBranchName`). If that branch is already checked out in `~/hazel`,
  it works there in place instead.
- A `claude --dangerously-skip-permissions` session **named with the ticket**,
  seeded with a prompt to: read the full ticket via the **Linear MCP** (incl.
  comments, sub-issues, linked docs/specs), then read the linked **GitHub PR**
  via the **GitHub MCP** (diff, CI, reviews) before proposing a plan.
- A window titled `APP-223 first three words ·#<PR>`.

## How the data is sourced (no custom database)

A "task" is just its Linear ticket. Everything else is derived live:

- **Linear** → which tickets (assigned + active) and which PR is linked (the
  attachment URL — the reliable join).
- **GitHub** (`gh`) → the PR's live state Linear can't see: open/merged, draft,
  CI checks, review decision, mergeable, size.
- **tmux** → which tickets currently have a live session (the `●` badge).

Cache: `~/.cache/ghostty-linear/tickets.json` (regenerable any time with `r`).

## Persistence

TPM + tmux-resurrect + tmux-continuum auto-save every 15 min and restore on
launch, so windows survive a reboot. claude windows restore in their worktree;
resurrect attempts `claude --continue` to resume the conversation.

## Files

```
~/.config/ghostty-linear/
  tmux.conf            # prefix bindings, titles, resurrect/continuum
  bin/gl-lib.sh        # shared paths + helpers (incl. GL_VERSION, cockpit/split)
  bin/arcade           # user entry point: version banner -> attach tmux dashboard
  bin/gl-setup         # store Linear key in Keychain
  bin/gl-fetch         # Linear + GitHub -> tickets.json
  bin/gl-dashboard     # the curses status page
  bin/gl-open          # ensure worktree + claude window; swap into split or switch
  bin/gl-preview       # live-preview a live ticket in the split (no creation)
  bin/gl-brief         # build the per-ticket markdown brief
  bin/gl-split         # toggle the cockpit split
  bin/gl-return        # back to dashboard
  bin/gl-start         # attach/create the tmux session + dashboard (run by arcade)
```

`arcade` is symlinked onto your PATH at `~/.local/bin/arcade`.

## Tuning (env vars, override in your shell profile)

- `GL_REPO` (default `~/hazel`), `GL_WORKTREE_BASE` (`~/worktrees`),
  `GL_BASE_BRANCH` (`main`), `GL_SESSION` (`hazel`), `GL_CLAUDE` (the claude binary).

## Uninstall

Remove the `command =` and `keybind = cmd+n/g/y` lines from
`~/.config/ghostty/config`, `rm ~/.local/bin/arcade`, then
`rm -rf ~/.config/ghostty-linear`. Optionally
`claude mcp remove github -s user` and delete the Keychain item
(`security delete-generic-password -s ghostty-linear-token`).
