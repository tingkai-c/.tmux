# Core helpers for the advanced tmux pane menu.
# POSIX sh; sourced by pane-menu.sh and tests.

: "${TMUX_BIN:=tmux}"
: "${PANE_MENU_TMUX_SOCKET:=}"
: "${PANE_MENU_PREVIEW_WIDTH:=56}"
: "${PANE_MENU_PREVIEW_HEIGHT:=14}"

pane_menu_tmux() {
  if [ -n "$PANE_MENU_TMUX_SOCKET" ]; then
    tmux -L "$PANE_MENU_TMUX_SOCKET" "$@"
  else
    "$TMUX_BIN" "$@"
  fi
}

pane_menu_shell_quote() {
  quoted=$(printf '%s\n' "$1" | sed "s/'/'\\''/g")
  printf "'%s'" "$quoted"
}

pane_menu_model() {
  pane_menu_tmux list-panes -F '#{pane_id}	#{pane_index}	#{pane_left}	#{pane_top}	#{pane_width}	#{pane_height}	#{pane_active}	#{pane_current_path}'
}

pane_menu_active_pane() {
  pane_menu_tmux display-message -p '#{pane_id}'
}

pane_menu_pane_exists() {
  pane_menu_model | awk -F '\t' -v id="$1" '$1 == id { found = 1 } END { exit found ? 0 : 1 }'
}

pane_menu_selected_or_active() {
  selected=$1
  if [ -n "$selected" ] && pane_menu_pane_exists "$selected"; then
    printf '%s\n' "$selected"
  else
    pane_menu_model | awk -F '\t' '$7 == "1" { print $1; found = 1; exit } END { if (!found) exit 1 }'
  fi
}

pane_menu_pane_id_for_index() {
  index=$1
  pane_menu_model | awk -F '\t' -v idx="$index" '$2 == idx { print $1; found = 1; exit } END { exit found ? 0 : 1 }'
}

pane_menu_pane_index_for_id() {
  pane_id=$1
  pane_menu_model | awk -F '\t' -v id="$pane_id" '$1 == id { print $2; found = 1; exit } END { exit found ? 0 : 1 }'
}

pane_menu_pane_cwd() {
  pane_id=$1
  pane_menu_model | awk -F '\t' -v id="$pane_id" '$1 == id { print $8; found = 1; exit } END { exit found ? 0 : 1 }'
}

pane_menu_pane_count() {
  pane_id=${1:-}
  if [ -n "$pane_id" ]; then
    pane_menu_tmux list-panes -t "$pane_id" | awk 'END { print NR + 0 }'
  else
    pane_menu_model | awk 'END { print NR + 0 }'
  fi
}

pane_menu_render_preview() {
  model_file=$1
  selected=${2:-}
  awk -F '\t' -v selected="$selected" -v out_w="$PANE_MENU_PREVIEW_WIDTH" -v out_h="$PANE_MENU_PREVIEW_HEIGHT" '
    function max(a, b) { return a > b ? a : b }
    function put(x, y, ch) {
      if (x >= 1 && x <= out_w && y >= 1 && y <= out_h) canvas[y, x] = ch
    }
    function text(x, y, s,    i) {
      for (i = 1; i <= length(s); i++) put(x + i - 1, y, substr(s, i, 1))
    }
    {
      n++
      id[n] = $1; idx[n] = $2; left[n] = $3 + 0; top[n] = $4 + 0
      width[n] = max($5 + 0, 1); height[n] = max($6 + 0, 1); active[n] = $7
      max_x = max(max_x, left[n] + width[n]); max_y = max(max_y, top[n] + height[n])
    }
    END {
      if (n == 0) { print "(no panes)"; exit }
      if (max_x < 1) max_x = 1
      if (max_y < 1) max_y = 1
      for (y = 1; y <= out_h; y++) for (x = 1; x <= out_w; x++) canvas[y, x] = " "

      for (i = 1; i <= n; i++) {
        x1 = int(left[i] * (out_w - 1) / max_x) + 1
        y1 = int(top[i] * (out_h - 1) / max_y) + 1
        x2 = int((left[i] + width[i]) * (out_w - 1) / max_x) + 1
        y2 = int((top[i] + height[i]) * (out_h - 1) / max_y) + 1
        if (x2 <= x1) x2 = x1 + 1
        if (y2 <= y1) y2 = y1 + 1
        if (x2 > out_w) x2 = out_w
        if (y2 > out_h) y2 = out_h
        h = (id[i] == selected ? "#" : "-")
        v = (id[i] == selected ? "#" : "|")
        c = (id[i] == selected ? "#" : "+")
        for (x = x1; x <= x2; x++) { put(x, y1, h); put(x, y2, h) }
        for (y = y1; y <= y2; y++) { put(x1, y, v); put(x2, y, v) }
        put(x1, y1, c); put(x2, y1, c); put(x1, y2, c); put(x2, y2, c)
        label = " " idx[i] (active[i] == "1" ? "*" : " ")
        text(x1 + 1, y1 + 1, label)
      }

      for (y = 1; y <= out_h; y++) {
        line = ""
        for (x = 1; x <= out_w; x++) line = line canvas[y, x]
        sub(/[ ]+$/, "", line)
        print line
      }
    }
  ' "$model_file"
}

pane_menu_resize_abs() {
  pane_id=$1
  dim=$2
  delta=$3
  if [ "$dim" = width ]; then
    current=$(pane_menu_tmux display-message -p -t "$pane_id" '#{pane_width}')
    min=5
    new=$((current + delta))
    [ "$new" -lt "$min" ] && new=$min
    pane_menu_tmux resize-pane -t "$pane_id" -x "$new"
  else
    current=$(pane_menu_tmux display-message -p -t "$pane_id" '#{pane_height}')
    min=3
    new=$((current + delta))
    [ "$new" -lt "$min" ] && new=$min
    pane_menu_tmux resize-pane -t "$pane_id" -y "$new"
  fi
}

pane_menu_action() {
  pane_id=$1
  action=$2
  [ -n "$pane_id" ] || return 1

  case "$action" in
    select)
      pane_menu_tmux select-pane -t "$pane_id"
      ;;
    remove)
      count=$(pane_menu_pane_count "$pane_id")
      if [ "$count" -le 1 ]; then
        pane_menu_tmux display-message 'Cannot remove the last pane' 2>/dev/null || true
        return 2
      fi
      pane_menu_tmux kill-pane -t "$pane_id"
      ;;
    split-vertical)
      cwd=$(pane_menu_pane_cwd "$pane_id") || cwd=$PWD
      # User-facing vertical split: creates left/right panes with a vertical divider.
      pane_menu_tmux split-window -t "$pane_id" -c "$cwd" -h
      ;;
    split-horizontal)
      cwd=$(pane_menu_pane_cwd "$pane_id") || cwd=$PWD
      # User-facing horizontal split: creates top/bottom panes with a horizontal divider.
      pane_menu_tmux split-window -t "$pane_id" -c "$cwd" -v
      ;;
    wider)
      pane_menu_resize_abs "$pane_id" width 5
      ;;
    narrower)
      pane_menu_resize_abs "$pane_id" width -5
      ;;
    taller)
      pane_menu_resize_abs "$pane_id" height 2
      ;;
    shorter)
      pane_menu_resize_abs "$pane_id" height -2
      ;;
    *)
      pane_menu_tmux display-message "Unknown pane menu action: $action" 2>/dev/null || true
      return 1
      ;;
  esac
}

pane_menu_action_name() {
  case "$1" in
    select) printf 'Select/focus pane' ;;
    remove) printf 'Remove pane' ;;
    split-vertical) printf 'Split vertical (left/right)' ;;
    split-horizontal) printf 'Split horizontal (top/bottom)' ;;
    taller) printf 'Taller' ;;
    shorter) printf 'Shorter' ;;
    wider) printf 'Wider' ;;
    narrower) printf 'Narrower' ;;
    *) printf '%s' "$1" ;;
  esac
}

pane_menu_action_at() {
  case "$1" in
    0) printf 'select' ;;
    1) printf 'remove' ;;
    2) printf 'split-vertical' ;;
    3) printf 'split-horizontal' ;;
    4) printf 'taller' ;;
    5) printf 'shorter' ;;
    6) printf 'wider' ;;
    7) printf 'narrower' ;;
    *) return 1 ;;
  esac
}

pane_menu_action_count() {
  printf '8\n'
}
