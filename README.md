~~~
git clone https://github.com/tingkai-c/.tmux.git "${XDG_CONFIG_HOME:-$HOME/.config}/tmux" && "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/install.sh"
~~~

Rerun `${XDG_CONFIG_HOME:-$HOME/.config}/tmux/install.sh` after pulling updates. The repository lives directly at tmux's XDG config path, so future config fixes are used without copying or symlinking the main config.

If migrating from another checkout, the installer only reuses an existing XDG target when it can identify it as this repo; otherwise it refuses to overwrite the directory.

This config keeps tmux's default detached-session behavior: sessions remain available after their last client detaches.
