#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_dir/pane-menu.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2
  message=$3
  printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null || fail "$message"
}

assert_not_contains() {
  haystack=$1
  needle=$2
  message=$3
  printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null && fail "$message"
  return 0
}

strip_ansi() {
  esc=$(printf '\033')
  sed "s/${esc}\\[[0-9;?]*[A-Za-z]//g"
}

visible_max_width() {
  printf '%s\n' "$1" | strip_ansi | awk '{ if (length($0) > max) max = length($0) } END { print max + 0 }'
}

# Renderer fixture checks.
out=$($script --render-fixture "$repo_dir/tests/fixtures/single.tsv" '%1')
assert_contains "$out" '[[1]]' 'single fixture should label selected pane index 1 with double brackets'
assert_not_contains "$out" '#' 'selected pane should not use hash borders'

out=$($script --render-fixture "$repo_dir/tests/fixtures/side-by-side.tsv" '%2')
assert_contains "$out" '[1]' 'side-by-side fixture should show pane index 1'
assert_contains "$out" '[[2]]' 'side-by-side fixture should show selected pane index 2'
assert_not_contains "$out" '#' 'side-by-side fixture should not use hash borders'

out=$($script --render-fixture "$repo_dir/tests/fixtures/stacked.tsv" '%2')
assert_contains "$out" '[1]' 'stacked fixture should show pane index 1'
assert_contains "$out" '[[2]]' 'stacked fixture should show selected pane index 2'
assert_not_contains "$out" '#' 'stacked fixture should not use hash borders'

out=$($script --render-fixture "$repo_dir/tests/fixtures/uneven.tsv" '%3')
assert_contains "$out" '[1]' 'uneven fixture should preserve 1-based pane numbering'
assert_contains "$out" '[2]' 'uneven fixture should show second pane'
assert_contains "$out" '[[3]]' 'uneven fixture should show selected third pane'
assert_not_contains "$out" '#' 'uneven fixture should not use hash borders'

out=$($script --render-fixture "$repo_dir/tests/fixtures/multi-digit.tsv" '%10')
assert_contains "$out" '[[10]]' 'multi-digit fixture should show selected pane index 10'
assert_contains "$out" '[11]' 'multi-digit fixture should show pane index 11'
assert_not_contains "$out" '#' 'multi-digit fixture should not use hash borders'

# Static checks.
sh -n "$script"
sh -n "$repo_dir/install.sh"
find "$repo_dir/lib/pane-menu" -name '*.sh' -exec sh -n {} \;


# Binding regression checks.
grep -F 'bind p run-shell -b' "$repo_dir/tmux.conf" >/dev/null || fail 'tmux.conf should bind prefix+p'
grep -F '${XDG_CONFIG_HOME:-$HOME/.config}/tmux/pane-menu.sh' "$repo_dir/tmux.conf" >/dev/null || fail 'prefix+p binding should try the XDG pane menu path'
grep -F '$HOME/.tmux/pane-menu.sh' "$repo_dir/tmux.conf" >/dev/null || fail 'prefix+p binding should fall back to the legacy ~/.tmux path'
grep -F '"#{pane_id}" 0' "$repo_dir/tmux.conf" >/dev/null || fail 'prefix+p binding should pass pane_id'
grep -F 'set-window-option -g pane-base-index 1' "$repo_dir/tmux.conf" >/dev/null || fail 'tmux.conf should keep pane-base-index 1'

# Isolated tmux smoke checks. Skip cleanly if tmux is unavailable.
command -v tmux >/dev/null 2>&1 || {
  echo 'SKIP: tmux not found'
  exit 0
}

sock="pane-menu-test-$$"
cleanup() {
  tmux -L "$sock" kill-server >/dev/null 2>&1 || true
  rm -rf "$repo_dir/.tmp pane menu smoke"
  rm -f /tmp/pane-menu-model-$$.txt /tmp/pane-menu-popup-$$.txt
}
trap cleanup EXIT HUP INT TERM

space_dir="$repo_dir/.tmp pane menu smoke"
mkdir -p "$space_dir"
tmux -L "$sock" -f /dev/null new-session -d -s pane-menu-test -x 120 -y 40 -c "$space_dir"
tmux -L "$sock" set-option -g base-index 1
tmux -L "$sock" set-window-option -g pane-base-index 1
PANE_MENU_TMUX_SOCKET="$sock" $script --model >/tmp/pane-menu-model-$$.txt
model=$(cat /tmp/pane-menu-model-$$.txt)
rm -f /tmp/pane-menu-model-$$.txt
assert_contains "$model" "$space_dir" 'model should include pane_current_path with spaces'

pane1=$(PANE_MENU_TMUX_SOCKET="$sock" $script --pane-for-index 1)
printf q | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=44 PANE_MENU_SCREEN_HEIGHT=12 $script --popup "$pane1" 0 >/tmp/pane-menu-popup-$$.txt
popup_out=$(cat /tmp/pane-menu-popup-$$.txt)
assert_contains "$popup_out" '[[1]]' 'popup loop should render selected pane label before quit'
assert_not_contains "$popup_out" 'Pane Menu — preview + keyboard MVP' 'popup should not render MVP title text'
assert_not_contains "$popup_out" '#' 'popup should not use hash borders'
max_width=$(visible_max_width "$popup_out")
[ "$max_width" -le 44 ] || fail 'tiny popup output should stay within requested visible width'
printf q | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=140 PANE_MENU_SCREEN_HEIGHT=50 $script --popup "$pane1" 0 >/tmp/pane-menu-popup-$$.txt
popup_out=$(cat /tmp/pane-menu-popup-$$.txt)
max_width=$(visible_max_width "$popup_out")
[ "$max_width" -le 140 ] || fail 'large popup output should stay within requested visible width'
rm -f /tmp/pane-menu-popup-$$.txt

PANE_MENU_TMUX_SOCKET="$sock" $script --action "$pane1" split-vertical
count=$(tmux -L "$sock" list-panes | wc -l | tr -d ' ')
[ "$count" -eq 2 ] || fail 'split-vertical should create a second pane'

pane2=$(tmux -L "$sock" list-panes -F '#{pane_id}' | sed -n '2p')
PANE_MENU_TMUX_SOCKET="$sock" $script --action "$pane2" split-horizontal
count=$(tmux -L "$sock" list-panes | wc -l | tr -d ' ')
[ "$count" -eq 3 ] || fail 'split-horizontal should create a third pane'

before=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
PANE_MENU_TMUX_SOCKET="$sock" $script --action "$pane1" narrower
after=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
[ "$after" -lt "$before" ] || fail 'narrower should decrease selected pane width'
height_before=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_height}')
PANE_MENU_TMUX_SOCKET="$sock" $script --action "$pane1" taller
height_after=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_height}')
[ "$height_after" -ge "$height_before" ] || fail 'taller should not decrease selected pane height'

width_before=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
printf -- '-q' | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=80 PANE_MENU_SCREEN_HEIGHT=24 $script --popup "$pane1" 5 >/tmp/pane-menu-popup-$$.txt
width_after=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
[ "$width_after" -lt "$width_before" ] || fail 'selected adjust-width action with - should decrease selected pane width'
width_before_enter=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
printf '\rq' | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=80 PANE_MENU_SCREEN_HEIGHT=24 $script --popup "$pane1" 5 >/tmp/pane-menu-popup-$$.txt
width_after_enter=$(tmux -L "$sock" display-message -p -t "$pane1" '#{pane_width}')
[ "$width_after_enter" -eq "$width_before_enter" ] || fail 'Enter on adjust-width should not resize'

height_before=$(tmux -L "$sock" display-message -p -t "$pane2" '#{pane_height}')
printf -- '+q' | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=80 PANE_MENU_SCREEN_HEIGHT=24 $script --popup "$pane2" 4 >/tmp/pane-menu-popup-$$.txt
height_after=$(tmux -L "$sock" display-message -p -t "$pane2" '#{pane_height}')
[ "$height_after" -gt "$height_before" ] || fail 'selected adjust-height action with + should increase selected pane height'
height_before_enter=$(tmux -L "$sock" display-message -p -t "$pane2" '#{pane_height}')
printf '\rq' | PANE_MENU_TMUX_SOCKET="$sock" PANE_MENU_SCREEN_WIDTH=80 PANE_MENU_SCREEN_HEIGHT=24 $script --popup "$pane2" 4 >/tmp/pane-menu-popup-$$.txt
height_after_enter=$(tmux -L "$sock" display-message -p -t "$pane2" '#{pane_height}')
[ "$height_after_enter" -eq "$height_before_enter" ] || fail 'Enter on adjust-height should not resize'
rm -f /tmp/pane-menu-popup-$$.txt

PANE_MENU_TMUX_SOCKET="$sock" $script --action "$pane2" remove
count=$(tmux -L "$sock" list-panes | wc -l | tr -d ' ')
[ "$count" -eq 2 ] || fail 'remove should kill selected pane'

# Last-pane guard.
for p in $(tmux -L "$sock" list-panes -F '#{pane_id}' | sed -n '2,$p'); do
  PANE_MENU_TMUX_SOCKET="$sock" $script --action "$p" remove || true
done
last=$(tmux -L "$sock" display-message -p '#{pane_id}')
if PANE_MENU_TMUX_SOCKET="$sock" $script --action "$last" remove; then
  fail 'remove should refuse to kill last pane'
fi
count=$(tmux -L "$sock" list-panes | wc -l | tr -d ' ')
[ "$count" -eq 1 ] || fail 'last-pane guard should leave one pane'

echo 'pane-menu tests passed'
