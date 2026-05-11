~~~
git clone https://github.com/tingkai-c/.tmux.git ~/.tmux && ~/.tmux/install.sh
~~~

Rerun `~/.tmux/install.sh` after pulling updates. The installer links `~/.tmux.conf` to this repository's `tmux.conf` instead of copying it, so future config fixes are actually used.

This config sets `destroy-unattached` so sessions are destroyed after their last client detaches. That keeps `tmux ls` from showing orphaned sessions left behind by closed terminals. If you intentionally keep long-running detached sessions, override it with `set -g destroy-unattached off`.
