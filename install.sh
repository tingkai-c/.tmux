#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config_src="$repo_dir/tmux.conf"
config_dst="$HOME/.tmux.conf"
plugins_dir="$repo_dir/plugins"
tpm_dir="$plugins_dir/tpm"

if [ ! -f "$config_src" ]; then
  echo "tmux config not found: $config_src" >&2
  exit 1
fi

if [ -e "$config_dst" ] && [ ! -L "$config_dst" ]; then
  if ! cmp -s "$config_dst" "$config_src"; then
    backup="$config_dst.bak-$(date +%Y%m%d%H%M%S)"
    cp "$config_dst" "$backup"
    echo "Backed up existing $config_dst to $backup"
  fi
fi

ln -sfn "$config_src" "$config_dst"
echo "Linked $config_dst -> $config_src"

mkdir -p "$plugins_dir"
if [ ! -d "$tpm_dir/.git" ]; then
  git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
fi

if [ -x "$tpm_dir/bin/install_plugins" ]; then
  "$tpm_dir/bin/install_plugins"
fi

echo "Install/update complete. New tmux servers will load $config_src."
echo "Existing tmux servers are not reloaded automatically because this config intentionally destroys unattached sessions."
