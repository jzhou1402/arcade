# shellcheck shell=bash
# Shared config + helpers for the ghostty-linear workflow.
# Sourced by every gl-* script. Not meant to be executed directly.

# Ghostty is a GUI app: when launched from the Dock/Finder it inherits
# launchd's minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin), and its launch
# wrapper (login ... bash --noprofile --norc) never sources a profile to
# restore it. Without this, Homebrew tools (tmux, gh) and ~/.local/bin
# (claude) aren't found and gl-start dies with `exec: : not found`. Prepend
# the known locations so every gl-* script and spawned claude can find them.
for _d in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
  esac
done
unset _d
export PATH

GL_VERSION="0.2.0"
GL_CODENAME="arcade"

GL_CONFIG_DIR="${GL_CONFIG_DIR:-$HOME/.config/ghostty-linear}"
GL_BIN="$GL_CONFIG_DIR/bin"
GL_CACHE="${GL_CACHE:-$HOME/.cache/ghostty-linear}"
GL_TICKETS="$GL_CACHE/tickets.json"
GL_SELECTED="$GL_CACHE/selected"
GL_BRIEFS="$GL_CACHE/briefs"

GL_REPO="${GL_REPO:-$HOME/hazel}"
GL_WORKTREE_BASE="${GL_WORKTREE_BASE:-$HOME/worktrees}"
GL_BASE_BRANCH="${GL_BASE_BRANCH:-main}"

GL_SESSION="${GL_SESSION:-hazel}"
GL_DASHBOARD_WINDOW="dashboard"

TMUX_BIN="${TMUX_BIN:-$(command -v tmux)}"

GL_KEYCHAIN_SERVICE="ghostty-linear-token"

mkdir -p "$GL_CACHE" "$GL_BRIEFS" "$GL_WORKTREE_BASE" 2>/dev/null || true

# Linear personal API key, resolved from the macOS Keychain (falls back to env).
gl_token() {
  if [ -n "${LINEAR_API_KEY:-}" ]; then
    printf '%s' "$LINEAR_API_KEY"
    return 0
  fi
  security find-generic-password -s "$GL_KEYCHAIN_SERVICE" -w 2>/dev/null
}

# APP-223 -> app-223  (lowercase, safe for paths and branch matching)
gl_slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Absolute worktree path for a ticket id.
gl_worktree() { printf '%s/%s' "$GL_WORKTREE_BASE" "$(gl_slug "$1")"; }

gl_brief_path() { printf '%s/%s.md' "$GL_BRIEFS" "$(gl_slug "$1")"; }

# Read a field for a ticket id out of the cached tickets.json.
# usage: gl_ticket_field APP-223 .title
gl_ticket_field() {
  [ -f "$GL_TICKETS" ] || return 1
  jq -r --arg id "$1" --arg f "$2" \
    'map(select(.id == $id)) | .[0] | getpath($f | ltrimstr(".") | split(".")) // ""' \
    "$GL_TICKETS" 2>/dev/null
}

# First N words of a string.
gl_first_words() {
  local n="$1"; shift
  printf '%s' "$*" | tr -s '[:space:]' ' ' | cut -d' ' -f1-"$n"
}

# Custom terminal/window title: "APP-223 three words ·#42"
gl_title() {
  local id="$1"
  local title pr words
  title="$(gl_ticket_field "$id" .title)"
  pr="$(gl_ticket_field "$id" .pr.number)"
  words="$(gl_first_words 3 "$title")"
  if [ -n "$pr" ] && [ "$pr" != "null" ]; then
    printf '%s %s ·#%s' "$id" "$words" "$pr"
  else
    printf '%s %s' "$id" "$words"
  fi
}

# Index of the window for a ticket: matches the @ticket option, or (after a
# resurrect restore, which drops custom options) the window-name prefix.
gl_window_for() {
  [ -n "$TMUX_BIN" ] || return 1
  "$TMUX_BIN" list-windows -t "$GL_SESSION" -F '#{window_index}|#{@ticket}|#{window_name}' 2>/dev/null \
    | awk -F'|' -v id="$1" '$2 == id || index($3, id " ") == 1 || $3 == id { print $1; exit }'
}

gl_session_exists() {
  "$TMUX_BIN" has-session -t "$GL_SESSION" 2>/dev/null
}

gl_log() { printf '[ghostty-linear] %s\n' "$*" >&2; }

# --- cockpit / split-view helpers --------------------------------------------
# The "cockpit" is the dashboard window: the dashboard is pinned on the left,
# and the currently-selected ticket's claude pane is joined in on the right.
# gl-dashboard marks its own window with @cockpit=1 and stores its pane id in
# @dashpane at startup. @shown (set on the cockpit) is the ticket id currently
# displayed on the right, or empty when the dashboard is full-screen.

# Window index of the cockpit (the dashboard window).
gl_cockpit_window() {
  [ -n "$TMUX_BIN" ] || return 1
  "$TMUX_BIN" list-windows -t "$GL_SESSION" -F '#{window_index}|#{@cockpit}' 2>/dev/null \
    | awk -F'|' '$2 == "1" { print $1; exit }'
}

# Ticket currently shown on the cockpit's right (empty if none).
gl_shown_ticket() {
  local cockpit="$1"
  "$TMUX_BIN" show-window-options -t "$GL_SESSION:$cockpit" -v @shown 2>/dev/null || true
}

# True when the cockpit is currently split (a ticket is shown on the right).
gl_split_active() {
  local cockpit; cockpit="$(gl_cockpit_window)" || return 1
  [ -n "$cockpit" ] && [ -n "$(gl_shown_ticket "$cockpit")" ]
}

# The cockpit's right-hand (claude) pane: the pane that is NOT the dashboard.
gl_cockpit_claude_pane() {
  local cockpit="$1" dash
  dash="$("$TMUX_BIN" show-window-options -t "$GL_SESSION:$cockpit" -v @dashpane 2>/dev/null || true)"
  "$TMUX_BIN" list-panes -t "$GL_SESSION:$cockpit" -F '#{pane_id}' 2>/dev/null \
    | grep -vx "$dash" | head -1
}

# Ensure a tmux window running claude exists for a ticket; echo its window id
# (e.g. @5). Creates the worktree + window if missing, like the original gl-open.
gl_ensure_window() {
  local id="$1"
  local existing branch current_branch wt brief claude_bin shell title prompt launch win
  existing="$(gl_window_for "$id")"
  if [ -n "$existing" ]; then
    "$TMUX_BIN" display-message -p -t "$GL_SESSION:$existing" '#{window_id}'
    return 0
  fi

  branch="$(gl_ticket_field "$id" .branch)"
  [ -n "$branch" ] && [ "$branch" != "null" ] || branch="$(gl_slug "$id")"

  current_branch="$(git -C "$GL_REPO" branch --show-current 2>/dev/null || true)"
  wt="$(gl_worktree "$id")"
  if [ "$current_branch" = "$branch" ]; then
    wt="$GL_REPO"
  elif [ ! -d "$wt" ]; then
    gl_log "Creating worktree $wt on branch $branch ..."
    if git -C "$GL_REPO" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$GL_REPO" worktree add "$wt" "$branch"
    elif git -C "$GL_REPO" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      git -C "$GL_REPO" fetch origin "$branch" >/dev/null 2>&1 || true
      git -C "$GL_REPO" worktree add --track -b "$branch" "$wt" "origin/$branch"
    else
      git -C "$GL_REPO" worktree add -b "$branch" "$wt" "origin/$GL_BASE_BRANCH" 2>/dev/null \
        || git -C "$GL_REPO" worktree add -b "$branch" "$wt" "$GL_BASE_BRANCH"
    fi
  fi

  brief="$("$GL_BIN/gl-brief" "$id" 2>/dev/null || true)"
  [ -z "$brief" ] && brief="$(gl_brief_path "$id")"

  claude_bin="${GL_CLAUDE:-$(command -v claude || printf '%s' "$HOME/.local/bin/claude")}"
  shell="${SHELL:-/bin/zsh}"
  title="$(gl_title "$id")"

  prompt="You are working on Linear ticket ${id}.
1. Use the Linear MCP to read the FULL ticket: its description, every comment, any sub-issues/relations, its project and milestone, and any linked documents or spec files — follow every reference, don't stop at the summary.
2. The ticket links a GitHub PR through its Linear attachments. Use the GitHub MCP to read that PR — its diff, changed files, CI/check status, and review comments — so you understand the ACTUAL current implementation, not just the description.
3. A quick local orientation brief is cached at ${brief} if you want a fast overview before the MCP calls.
Then give me a concise summary of the task and its current state (Linear status + PR/CI/review status) and propose a short plan BEFORE changing any code. If node_modules is missing in this worktree, run pnpm install first."

  launch="$(printf '%q ' "$claude_bin") --dangerously-skip-permissions -n $(printf '%q' "$id") $(printf '%q' "$prompt"); exec $(printf '%q' "$shell") -l"

  win="$("$TMUX_BIN" new-window -t "$GL_SESSION" -n "$title" -c "$wt" -P -F '#{window_id}' "$launch")"
  "$TMUX_BIN" set-window-option -t "$win" @ticket "$id" >/dev/null
  "$TMUX_BIN" set-window-option -t "$win" automatic-rename off >/dev/null
  "$TMUX_BIN" set-window-option -t "$win" allow-rename off >/dev/null
  printf '%s' "$win"
}

# Collapse the split: break the currently-shown claude pane back out to its own
# standalone window (restoring its @ticket + title) and clear @shown.
gl_collapse_cockpit() {
  local cockpit shown right title newwin
  cockpit="$(gl_cockpit_window)" || return 0
  [ -n "$cockpit" ] || return 0
  shown="$(gl_shown_ticket "$cockpit")"
  [ -n "$shown" ] || return 0

  right="$(gl_cockpit_claude_pane "$cockpit")"
  if [ -n "$right" ]; then
    title="$(gl_title "$shown")"
    newwin="$("$TMUX_BIN" break-pane -d -s "$right" -n "$title" -P -F '#{window_id}')"
    "$TMUX_BIN" set-window-option -t "$newwin" @ticket "$shown" >/dev/null 2>&1 || true
    "$TMUX_BIN" set-window-option -t "$newwin" automatic-rename off >/dev/null 2>&1 || true
    "$TMUX_BIN" set-window-option -t "$newwin" allow-rename off >/dev/null 2>&1 || true
  fi
  "$TMUX_BIN" set-window-option -t "$GL_SESSION:$cockpit" -u @shown >/dev/null 2>&1 || true
}

# Show ticket $1 on the cockpit's right, swapping out whatever was there.
# Keeps focus on the dashboard so the user can keep navigating.
gl_show_in_cockpit() {
  local id="$1" cockpit shown winid srcpane dash
  cockpit="$(gl_cockpit_window)" || { gl_log "No cockpit window."; return 1; }
  [ -n "$cockpit" ] || { gl_log "No cockpit window."; return 1; }
  shown="$(gl_shown_ticket "$cockpit")"
  [ "$shown" = "$id" ] && return 0           # already displayed

  gl_collapse_cockpit                        # park the previous ticket
  winid="$(gl_ensure_window "$id")"
  srcpane="$("$TMUX_BIN" list-panes -t "$winid" -F '#{pane_id}' | head -1)"
  dash="$("$TMUX_BIN" show-window-options -t "$GL_SESSION:$cockpit" -v @dashpane 2>/dev/null || true)"
  [ -n "$dash" ] || { gl_log "Cockpit has no dashboard pane."; return 1; }

  "$TMUX_BIN" join-pane -h -l '55%' -s "$srcpane" -t "$dash"
  "$TMUX_BIN" set-window-option -t "$GL_SESSION:$cockpit" @shown "$id" >/dev/null
  "$TMUX_BIN" select-window -t "$GL_SESSION:$cockpit" >/dev/null
  "$TMUX_BIN" select-pane -t "$dash" >/dev/null    # keep focus on the dashboard
}
