#!/bin/sh
# Interactive fixture: run only in the Ghostty pane explicitly chosen by its user.
set -eu
umask 077
[ -z "${TMUX:-}" ] || { printf 'nested_tmux=FAIL\n' >&2; exit 1; }

tmux_bin=${TERMEX_TMUX_BIN:-/opt/homebrew/bin/tmux}
[ -x "$tmux_bin" ] || { printf 'tmux_unavailable=FAIL\n' >&2; exit 1; }
scratch=$(mktemp -d /tmp/te-visible.XXXXXX)
socket=$scratch/socket
ready=$scratch/ready
matched=$scratch/matched
mux() { "$tmux_bin" -S "$socket" -f /dev/null "$@"; }
cleanup() {
    mux kill-server >/dev/null 2>&1 || :
    rm -f "$ready" "$matched" "$socket"
    rmdir "$scratch" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

pane=$(mux new-session -d -P -F '#{pane_id}' -s te-visible /bin/sleep 3600)
[ -n "$pane" ] || { printf 'pane_create=FAIL\n' >&2; exit 1; }
mux pipe-pane -t "$pane" ": > '$ready'; grep -q TE_GUI_ATTACH_OK && : > '$matched'"
attempt=0
until [ -f "$ready" ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 50 ] || { printf 'capture_gate=FAIL\n' >&2; exit 1; }
    sleep 0.1
done
[ "$(mux display-message -p -t "$pane" '#{pane_pipe}')" = 1 ] || {
    printf 'capture_pipe_before_workload=FAIL\n' >&2
    exit 1
}
if [ "${1:-}" = "--self-check" ]; then
    mux respawn-pane -k -t "$pane" /bin/sh -c "printf 'TE_GUI_ATTACH_%s\\n' OK; sleep 2"
    attempt=0
    until [ -f "$matched" ]; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 50 ] || { printf 'synthetic_capture=FAIL\n' >&2; exit 1; }
        sleep 0.1
    done
    printf 'synthetic_capture=PASS\n'
    exit 0
fi
mux respawn-pane -k -t "$pane" /bin/zsh -l
session=$(mux display-message -p -t "$pane" '#{session_id}')
pipe_before=$(mux display-message -p -t "$pane" '#{pane_pipe}')
[ "$pipe_before" = 1 ] || { printf 'capture_pipe_before_attach=FAIL\n' >&2; exit 1; }

printf 'Temporary tmux shell is ready. Run the test marker, then use tmux detach-client.\n'
mux attach-session -t "$session"
attempt=0
until [ -f "$matched" ] || [ "$attempt" -ge 20 ]; do
    attempt=$((attempt + 1))
    sleep 0.1
done
pipe_after=$(mux display-message -p -t "$pane" '#{pane_pipe}')
if mux capture-pane -p -t "$pane" | grep -q TE_GUI_ATTACH_OK; then
    printf 'gui_screen_marker=PASS\n'
else
    printf 'gui_screen_marker=NOT_OBSERVED\n'
fi
if [ -f "$matched" ]; then
    printf 'capture_pipe_marker=PASS\n'
else
    printf 'capture_pipe_marker=NOT_OBSERVED pipe_after=%s\n' "$pipe_after"
    exit 1
fi
