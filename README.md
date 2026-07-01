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
| `cmd+Y` | anywhere | toggle the **cockpit split**: dashboard pinned left, selected ticket on the right. Press again to close |
| `` cmd+` `` | split | **cycle** the right pane to the next ticket (cursor stays on the right) |
| `cmd+Return` | anywhere | start the ticket's session if it has none; if it already has one, full-screen (zoom) it |
| `cmd+Escape` | anywhere | jump focus back to the dashboard (also un-zooms) |
| `Enter` | dashboard | same as cmd+Return for the highlighted ticket |
| `r` | dashboard | refresh tickets from Linear + GitHub now |
| `o` | dashboard | open the selected ticket in the browser |
| `q` | dashboard | detach (reopen Ghostty to reattach) |

**Cockpit split (single window).** `cmd+Y` opens a split you live in: the
dashboard pinned on the left, a ticket on the right. **`` cmd+` `` cycles the
right pane through your tickets** (wrapping); the cursor stays on the right so
you can just start typing. A ticket that already has a claude session shows it;
one that doesn't shows a blank pane prompting **`cmd+Enter` to start** a session.
`cmd+Enter` on an existing session full-screens (zooms) it; `cmd+Escape` or
`C-b z` restores the split. Arrowing the dashboard directly (focus it with
`C-b ←`) also previews on the right, focus staying on the left. The layout is
fixed (dashboard always left), so a pane can't get stuck out of place — it snaps
back on the next cycle/toggle.

These `cmd` chords are Ghostty keybinds that send the tmux prefix (`C-b`) +
`n`/`g`/`c`/`y`; the matching bindings live in `tmux.conf`. (`cmd+Return`
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
  bin/gl-open          # cmd+Enter: start the ticket's session (or zoom it)
  bin/gl-preview       # dashboard-nav preview into the split (claude or blank)
  bin/gl-cycle         # cmd+`: cycle the split's right pane to the next ticket
  bin/gl-placeholder   # blank right-pane hint for ticketless tickets
  bin/gl-brief         # build the per-ticket markdown brief
  bin/gl-split         # toggle the cockpit split
  bin/gl-return        # cmd+Escape: back to dashboard (un-zooms)
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
