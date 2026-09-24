#!/bin/sh
# Use a private socket and config; never touch the user's tmux server.
set -eu

scratch=$(mktemp -d /tmp/te-tmux.XXXXXX)
socket=$scratch/socket
output=$scratch/output
cleanup() {
    tmux -S "$socket" kill-server >/dev/null 2>&1 || :
    rm -f "$socket" "$output"
    rmdir "$scratch"
}
trap cleanup EXIT

pane=$(tmux -S "$socket" -f /dev/null new-session -d -P -F '#{pane_id}' -s te-probe 'sleep 30')
other=$(tmux -S "$socket" -f /dev/null new-session -d -P -F '#{pane_id}' -s te-probe-other 'sleep 30')
other_pid=$(tmux -S "$socket" display-message -p -t "$other" '#{pane_pid}')
tmux -S "$socket" set-option -p -t "$pane" remain-on-exit on
tmux -S "$socket" pipe-pane -t "$pane" "cat > '$output'"
tmux -S "$socket" respawn-pane -k -t "$pane" "printf 'TE_E01_BEGIN\nTE_E01_END\n'; sleep 2"

attempt=0
until [ -f "$output" ] && rg -q TE_E01_END "$output"; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 40 ] || { echo 'pipe-pane capture timed out' >&2; exit 1; }
    sleep 0.1
done
tmux -S "$socket" capture-pane -p -t "$pane" | rg -q TE_E01_END
tmux -S "$socket" display-message -p -t "$pane" 'pane=#{pane_id} size=#{pane_width}x#{pane_height}'
tmux -S "$socket" kill-session -t '=te-probe'
if tmux -S "$socket" has-session -t '=te-probe' 2>/dev/null; then
    echo 'closed session remained available' >&2
    exit 1
fi
tmux -S "$socket" has-session -t '=te-probe-other'
[ "$(tmux -S "$socket" display-message -p -t "$other" '#{pane_pid}')" = "$other_pid" ]
printf 'capture_before_workload=PASS\n'
printf 'isolated_session_close=PASS\n'
