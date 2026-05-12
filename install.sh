#!/bin/sh
set -eu

repo_url="https://github.com/tingkai-c/.tmux.git"
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
xdg_config_home=${XDG_CONFIG_HOME:-$HOME/.config}
target_dir="$xdg_config_home/tmux"
legacy_config="$HOME/.tmux.conf"
config_src="$repo_dir/tmux.conf"
pane_menu_src="$repo_dir/pane-menu.sh"
plugins_dir="$repo_dir/plugins"
tpm_dir="$plugins_dir/tpm"

backup_path() {
  path=$1
  stamp=$(date +%Y%m%d%H%M%S)
  backup="$path.bak-$stamp"
  i=1
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="$path.bak-$stamp-$i"
    i=$((i + 1))
  done
  printf '%s\n' "$backup"
}

dir_is_empty() {
  [ -z "$(find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | sed -n '1p')" ]
}

git_remote() {
  git -C "$1" config --get remote.origin.url 2>/dev/null || true
}

is_managed_checkout() {
  checkout=$1
  expected_remote=$2

  [ -d "$checkout/.git" ] || return 1
  [ -x "$checkout/install.sh" ] || return 1
  [ -f "$checkout/tmux.conf" ] || return 1
  [ -x "$checkout/pane-menu.sh" ] || return 1

  checkout_remote=$(git_remote "$checkout")
  [ -n "$checkout_remote" ] || return 1
  [ "$checkout_remote" = "$expected_remote" ] || [ "$checkout_remote" = "$repo_url" ]
}

repo_real=$(CDPATH= cd -- "$repo_dir" && pwd -P)
remote=$(git_remote "$repo_dir")
[ -n "$remote" ] || remote=$repo_url

if [ -d "$target_dir" ]; then
  target_real=$(CDPATH= cd -- "$target_dir" && pwd -P)
else
  target_real=$target_dir
fi

if [ "$repo_real" != "$target_real" ]; then
  if [ -d "$target_dir" ] && is_managed_checkout "$target_dir" "$remote"; then
    echo "Using existing XDG tmux checkout: $target_dir"
    exec "$target_dir/install.sh" "$@"
  fi

  if [ -e "$target_dir" ] && { [ ! -d "$target_dir" ] || ! dir_is_empty "$target_dir"; }; then
    echo "XDG tmux config path already exists and is not an empty checkout: $target_dir" >&2
    echo "Move or back it up, then clone this repo there:" >&2
    echo "  git clone $repo_url \"$target_dir\"" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "$target_dir")"
  echo "Cloning tmux config into XDG path: $target_dir"
  git clone "$remote" "$target_dir"
  exec "$target_dir/install.sh" "$@"
fi

if [ ! -f "$config_src" ]; then
  echo "tmux config not found: $config_src" >&2
  exit 1
fi

if [ ! -x "$pane_menu_src" ]; then
  echo "pane menu script not executable: $pane_menu_src" >&2
  exit 1
fi

if [ -e "$legacy_config" ] || [ -L "$legacy_config" ]; then
  backup=$(backup_path "$legacy_config")
  mv "$legacy_config" "$backup"
  echo "Backed up legacy tmux config $legacy_config to $backup"
fi

mkdir -p "$plugins_dir"
if [ ! -d "$tpm_dir/.git" ]; then
  git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
fi

if [ -x "$tpm_dir/bin/install_plugins" ]; then
  TMUX_PLUGIN_MANAGER_PATH="$plugins_dir/" "$tpm_dir/bin/install_plugins"
fi

echo "Install/update complete. New tmux servers will load $config_src."
echo "Existing tmux servers are not reloaded automatically; run:"
echo "  tmux source-file \"$config_src\""
