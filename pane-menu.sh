#!/bin/sh

# Reopening pane menu for tmux.
# tmux display-menu always closes after an action; this script reopens it with
# -C so the previously chosen item stays selected.
#
# Usage:
#   pane-menu.sh <target-pane-id> [selected-index] [action]

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
menu="$config_home/tmux/pane-menu.sh"
pane=${1:-}
choice=${2:-0}
action=${3:-}

shell_quote() {
  quoted=$(printf '%s\n' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$quoted"
}

menu_command() {
  selected=$1
  next_action=$2
  printf 'run-shell -b "%s %s %s %s"' "$menu_arg" "$pane_arg" "$selected" "$next_action"
}

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

menu_arg=$(shell_quote "$menu")
pane_arg=$(shell_quote "$pane")

# Choice indexes are zero-based and include separators.
tmux display-menu -t "$pane" -T "Pane Menu" -C "$choice" \
  "Wider"  l "$(menu_command 0 wider)" \
  "Narrower" h "$(menu_command 1 narrower)" \
  "Taller" k "$(menu_command 2 taller)" \
  "Shorter" j "$(menu_command 3 shorter)" \
  "" \
  "Left/Right Layout"  "|" "$(menu_command 5 even-horizontal)" \
  "Top/Bottom Layout" "-" "$(menu_command 6 even-vertical)" \
  "Tiled Layout"      t "$(menu_command 7 tiled)" \
  "Main Left"         L "$(menu_command 8 main-vertical)" \
  "Main Top"          T "$(menu_command 9 main-horizontal)" \
  "" \
  "Swap Up"   u "$(menu_command 11 swap-up)" \
  "Swap Down" d "$(menu_command 12 swap-down)" \
  "Zoom"      z "$(menu_command 13 zoom)" \
  "" \
  "Done"      q "$(menu_command 15 done)"
