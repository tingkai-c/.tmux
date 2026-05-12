#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Prefer modules next to this script; this keeps the XDG checkout self-contained.
script_path="$script_dir/$(basename -- "$0")"
core="$script_dir/lib/pane-menu/core.sh"
if [ ! -f "$core" ]; then
  echo "pane menu core not found: $core" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$core"

pane=${1:-}
choice=${2:-0}
action=${3:-}

tmp_model=${TMPDIR:-/tmp}/pane-menu-model-$$.tsv
cleanup() {
  rm -f "$tmp_model"
}
trap cleanup EXIT HUP INT TERM

usage() {
  cat <<'USAGE'
Usage:
  pane-menu.sh [target-pane-id] [selected-action-index] [action]
  pane-menu.sh --popup [target-pane-id] [selected-action-index]
  pane-menu.sh --model
  pane-menu.sh --render [target-pane-id]
  pane-menu.sh --render-fixture <fixture.tsv> [target-pane-id]
  pane-menu.sh --pane-for-index <pane-index>
  pane-menu.sh --action <pane-id> <action>
USAGE
}

read_key() {
  old=$(stty -g 2>/dev/null || true)
  if [ -n "$old" ]; then
    stty raw -echo min 1 time 0 2>/dev/null || true
  fi
  key=$(dd bs=1 count=1 2>/dev/null || true)
  esc=$(printf '\033')
  if [ "$key" = "$esc" ] && [ -n "$old" ]; then
    stty raw -echo min 0 time 1 2>/dev/null || true
    rest=$(dd bs=1 count=2 2>/dev/null || true)
    key=$key$rest
  fi
  if [ -n "$old" ]; then
    stty "$old" 2>/dev/null || true
  fi

  up=$(printf '\033[A')
  down=$(printf '\033[B')
  cr=$(printf '\r')
  nl=$(printf '\n')
  case "$key" in
    "$up"|k) printf 'up\n' ;;
    "$down"|j) printf 'down\n' ;;
    "$cr"|"$nl"|'') printf 'enter\n' ;;
    +) printf 'increase\n' ;;
    -) printf 'decrease\n' ;;
    q|Q|"$esc") printf 'quit\n' ;;
    [0-9]) printf 'pane:%s\n' "$key" ;;
    *) printf 'unknown\n' ;;
  esac
}

is_positive_int() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "$1" -gt 0 ] ;;
  esac
}

detect_screen_size() {
  screen_w=${PANE_MENU_SCREEN_WIDTH:-}
  screen_h=${PANE_MENU_SCREEN_HEIGHT:-}
  if is_positive_int "$screen_w" && is_positive_int "$screen_h"; then
    return 0
  fi

  size=$(stty size 2>/dev/null || true)
  set -- $size
  if [ $# -eq 2 ] && is_positive_int "$1" && is_positive_int "$2"; then
    screen_h=$1
    screen_w=$2
    return 0
  fi

  cols=$(tput cols 2>/dev/null || true)
  lines=$(tput lines 2>/dev/null || true)
  if is_positive_int "$cols" && is_positive_int "$lines"; then
    screen_w=$cols
    screen_h=$lines
    return 0
  fi

  screen_w=80
  screen_h=24
}

strip_ansi() {
  esc=$(printf '\033')
  sed "s/${esc}\\[[0-9;?]*[A-Za-z]//g"
}

visible_width() {
  printf '%s' "$1" | strip_ansi | wc -c | tr -d ' '
}

print_centered() {
  width=$1
  line=${2:-}
  visible=$(visible_width "$line")
  pad=$(( (width - visible) / 2 ))
  [ "$pad" -lt 0 ] && pad=0
  printf '%*s%s\n' "$pad" '' "$line"
}

render_actions() {
  selected_action=$1
  screen_width=$2
  i=0
  count=$(pane_menu_action_count)
  while [ "$i" -lt "$count" ]; do
    act=$(pane_menu_action_at "$i")
    name=$(pane_menu_action_name "$act")
    if [ "$i" -eq "$selected_action" ]; then
      print_centered "$screen_width" "> $name"
    else
      print_centered "$screen_width" "  $name"
    fi
    i=$((i + 1))
  done
}

render_screen() {
  selected_pane=$1
  selected_action=$2
  pane_menu_model > "$tmp_model"
  detect_screen_size
  reserved_rows=9
  avail_w=$((screen_w - 4))
  [ "$avail_w" -lt 1 ] && avail_w=1
  preview_w=$avail_w
  [ "$preview_w" -gt 100 ] && preview_w=100
  avail_h=$((screen_h - reserved_rows))
  [ "$avail_h" -lt 1 ] && avail_h=1
  preview_h=$avail_h
  [ "$preview_h" -gt 30 ] && preview_h=30
  PANE_MENU_PREVIEW_WIDTH=$preview_w
  PANE_MENU_PREVIEW_HEIGHT=$preview_h

  clear 2>/dev/null || printf '\033[H\033[2J'
  pane_menu_render_preview "$tmp_model" "$selected_pane" | while IFS= read -r line; do
    print_centered "$screen_w" "$line"
  done
  selected_index=$(pane_menu_pane_index_for_id "$selected_pane" 2>/dev/null || printf '?')
  printf '\n'
  print_centered "$screen_w" "Selected pane: [$selected_index] ($selected_pane)"
  print_centered "$screen_w" 'Nums:pane +/-:resize Enter:run q:quit'
  render_actions "$selected_action" "$screen_w"
}

popup_loop() {
  selected_pane=$(pane_menu_selected_or_active "${1:-}")
  selected_action=${2:-0}
  action_count=$(pane_menu_action_count)

  while :; do
    render_screen "$selected_pane" "$selected_action"
    key=$(read_key)
    case "$key" in
      up)
        selected_action=$((selected_action - 1))
        [ "$selected_action" -lt 0 ] && selected_action=$((action_count - 1))
        ;;
      down)
        selected_action=$((selected_action + 1))
        [ "$selected_action" -ge "$action_count" ] && selected_action=0
        ;;
      increase|decrease)
        act=$(pane_menu_action_at "$selected_action") || act=select
        case "$act:$key" in
          resize-height:increase) pane_menu_resize_abs "$selected_pane" height 2 ;;
          resize-height:decrease) pane_menu_resize_abs "$selected_pane" height -2 ;;
          resize-width:increase) pane_menu_resize_abs "$selected_pane" width 5 ;;
          resize-width:decrease) pane_menu_resize_abs "$selected_pane" width -5 ;;
          *) pane_menu_tmux display-message 'Select Adjust height/width before using + or -' 2>/dev/null || true ;;
        esac
        ;;
      pane:*)
        idx=${key#pane:}
        if new_pane=$(pane_menu_pane_id_for_index "$idx" 2>/dev/null); then
          selected_pane=$new_pane
        else
          pane_menu_tmux display-message "No pane numbered $idx" 2>/dev/null || true
        fi
        ;;
      enter)
        act=$(pane_menu_action_at "$selected_action") || act=select
        case "$act" in
          resize-height|resize-width)
            pane_menu_tmux display-message 'Use + or - to adjust the selected pane size' 2>/dev/null || true
            continue
            ;;
        esac
        if pane_menu_action "$selected_pane" "$act"; then
          case "$act" in
            remove)
              selected_pane=$(pane_menu_selected_or_active "" 2>/dev/null || true)
              [ -n "$selected_pane" ] || exit 0
              ;;
            split-vertical|split-horizontal)
              # Keep operating on the original pane; tmux leaves it valid.
              ;;
          esac
        else
          sleep 1
        fi
        ;;
      quit)
        exit 0
        ;;
    esac
  done
}

open_popup() {
  selected_pane=$(pane_menu_selected_or_active "${1:-}")
  selected_action=${2:-0}
  quoted_script=$(pane_menu_shell_quote "$script_path")
  quoted_pane=$(pane_menu_shell_quote "$selected_pane")
  cmd="$quoted_script --popup $quoted_pane $selected_action"
  pane_menu_tmux display-popup -E -w 80% -h 75% -T 'Pane Menu' "$cmd"
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --model)
    pane_menu_model
    exit 0
    ;;
  --render)
    pane_menu_model > "$tmp_model"
    pane_menu_render_preview "$tmp_model" "${2:-$(pane_menu_active_pane)}"
    exit 0
    ;;
  --render-fixture)
    [ $# -ge 2 ] || { usage >&2; exit 2; }
    pane_menu_render_preview "$2" "${3:-}"
    exit 0
    ;;
  --pane-for-index)
    [ $# -eq 2 ] || { usage >&2; exit 2; }
    pane_menu_pane_id_for_index "$2"
    exit 0
    ;;
  --action)
    [ $# -eq 3 ] || { usage >&2; exit 2; }
    pane_menu_action "$2" "$3"
    exit $?
    ;;
  --popup)
    popup_loop "${2:-}" "${3:-0}"
    exit 0
    ;;
  --fallback-menu)
    # Degraded fallback only: static row menu, not near-exact preview.
    selected_pane=$(pane_menu_selected_or_active "${2:-}")
    script_arg=$(pane_menu_shell_quote "$script_path")
    pane_arg=$(pane_menu_shell_quote "$selected_pane")
    pane_menu_tmux display-menu -t "$selected_pane" -T 'Pane Menu (fallback)' \
      'Select/focus pane' s "run-shell -b \"$script_arg --action $pane_arg select\"" \
      'Remove pane'      x "run-shell -b \"$script_arg --action $pane_arg remove\"" \
      'Split vertical'   v "run-shell -b \"$script_arg --action $pane_arg split-vertical\"" \
      'Split horizontal' h "run-shell -b \"$script_arg --action $pane_arg split-horizontal\"" \
      'Wider (static fallback)'   l "run-shell -b \"$script_arg --action $pane_arg wider\"" \
      'Narrower (static fallback)' Left "run-shell -b \"$script_arg --action $pane_arg narrower\"" \
      'Taller (static fallback)'  k "run-shell -b \"$script_arg --action $pane_arg taller\"" \
      'Shorter (static fallback)' j "run-shell -b \"$script_arg --action $pane_arg shorter\""
    exit 0
    ;;
esac

if [ -n "$action" ]; then
  selected_pane=$(pane_menu_selected_or_active "$pane")
  pane_menu_action "$selected_pane" "$action"
  exit $?
fi

open_popup "$pane" "$choice"
