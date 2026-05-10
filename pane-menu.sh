#!/bin/sh

# Reopening pane menu for tmux.
# tmux display-menu always closes after an action; this script reopens it with
# -C so the previously chosen item stays selected.
#
# Usage:
#   pane-menu.sh <target-pane-id> [selected-index] [action]

menu="$HOME/.config/tmux/pane-menu.sh"
pane=${1:-}
choice=${2:-0}
action=${3:-}

if [ -z "$pane" ]; then
  pane=$(tmux display-message -p '#{pane_id}')
fi

run() {
  tmux "$@" 2>/dev/null || true
}

resize_abs() {
  dim=$1
  delta=$2
  if [ "$dim" = width ]; then
    current=$(tmux display-message -p -t "$pane" '#{pane_width}')
    min=5
    new=$((current + delta))
    [ "$new" -lt "$min" ] && new=$min
    run resize-pane -t "$pane" -x "$new"
  else
    current=$(tmux display-message -p -t "$pane" '#{pane_height}')
    min=3
    new=$((current + delta))
    [ "$new" -lt "$min" ] && new=$min
    run resize-pane -t "$pane" -y "$new"
  fi
}

case "$action" in
  wider) resize_abs width 5 ;;
  narrower) resize_abs width -5 ;;
  taller) resize_abs height 5 ;;
  shorter) resize_abs height -5 ;;
  even-horizontal) run select-layout -t "$pane" even-horizontal ;;
  even-vertical) run select-layout -t "$pane" even-vertical ;;
  tiled) run select-layout -t "$pane" tiled ;;
  main-vertical) run select-layout -t "$pane" main-vertical ;;
  main-horizontal) run select-layout -t "$pane" main-horizontal ;;
  swap-up) run swap-pane -t "$pane" -U ;;
  swap-down) run swap-pane -t "$pane" -D ;;
  zoom) run resize-pane -t "$pane" -Z ;;
  done) exit 0 ;;
esac

# Choice indexes are zero-based and include separators.
tmux display-menu -t "$pane" -T "Pane Menu" -C "$choice" \
  "Wider"  l "run-shell -b '$menu $pane 0 wider'" \
  "Narrower" h "run-shell -b '$menu $pane 1 narrower'" \
  "Taller" k "run-shell -b '$menu $pane 2 taller'" \
  "Shorter" j "run-shell -b '$menu $pane 3 shorter'" \
  "" \
  "Left/Right Layout"  "|" "run-shell -b '$menu $pane 5 even-horizontal'" \
  "Top/Bottom Layout" "-" "run-shell -b '$menu $pane 6 even-vertical'" \
  "Tiled Layout"      t "run-shell -b '$menu $pane 7 tiled'" \
  "Main Left"         L "run-shell -b '$menu $pane 8 main-vertical'" \
  "Main Top"          T "run-shell -b '$menu $pane 9 main-horizontal'" \
  "" \
  "Swap Up"   u "run-shell -b '$menu $pane 11 swap-up'" \
  "Swap Down" d "run-shell -b '$menu $pane 12 swap-down'" \
  "Zoom"      z "run-shell -b '$menu $pane 13 zoom'" \
  "" \
  "Done"      q "run-shell -b '$menu $pane 15 done'"
