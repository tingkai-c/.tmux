~~~
git clone https://github.com/tingkai-c/.tmux.git ~/.tmux && ~/.tmux/install.sh
~~~

Rerun `~/.tmux/install.sh` after pulling updates. The installer links `~/.tmux.conf` to this repository's `tmux.conf` instead of copying it, so future config fixes are actually used.

This config keeps tmux's default detached-session behavior: sessions remain available after their last client detaches.
