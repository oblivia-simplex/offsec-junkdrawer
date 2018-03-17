#! /usr/bin/env bash

bin=$1
joblimit=16
flags=--no-check-certificate

## ANSI escape sequences for colours
DARKGREEN=$'\e[00;32m'
GREEN=$'\e[01;32m'
TEAL=$'\e[00;36m'
DARKGREY=$'\e[01;30m'
CYAN=$'\e[01;36m'
LIGHTGREY=$'\e[00;37m'
RED=$'\e[00;31m' #?
PINK=$'\e[01;31m' #?
BLACK=$'\e[00;30m'
BLUE=$'\e[01;34m'
DARKBLUE=$'\e[00;34m'
WHITE=$'\e[01;38m'
RESET=$'\e[0m'
YELLOW=$'\e[01;33m'
MAGENTA=$'\e[01;35m'
PURPLE=$'\e[00;35m'

[ -n "$bin" ] || bin=ghostbin

loot="${bin}-loot"
[ -d "$loot" ] || mkdir -p $loot

case "$bin" in
  ghostbin)
    n=5
    charset=a-z0-9
    prefix="https://ghostbin.com/paste"
    suffix="download"
  ;;
  termbin)
    n=4
    charset=a-z0-9
    prefix="http://termbin.com"
    suffix=""
  ;;
  pasteee)
    n=5
    charset=a-zA-Z0-9
    prefix="https://paste.ee/d"
    suffix="0"
  ;;
  pipfi)
    n=4
    charset=A-Za-z0-9
    prefix="http://p.ip.fi"
    suffix=""
  ;;
esac
 

function makeurl ()
{
  echo "${prefix}/${1}/${suffix}" | sed "s,/$,,"
}

function postop ()
{
  [ -n "$suffix" ] && mv $suffix $1
}

cd $loot

function throttle () {
  joblimit=$1
  joblist=($(jobs -p))
  echo "${BLUE}[ throttle: ${#joblist[*]}/$joblimit ]${RESET}"
  while (( ${#joblist[*]} >= $joblimit )); do
    sleep 1
    joblist=($(jobs -p))
  done
}

function action () {
  key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
  grep -q $key ../keys-tried.txt && echo "[tried $key]" && continue
  echo $key >> ../keys-tried.txt
  #[ -f ./${key} ] && continue
  url=$(makeurl $key)
  echo "${RESET} [$(ls | wc -l)] =====${WHITE} $url ${RESET}===="
  wget $flags $url 2> /tmp/${bin}-brute.err || continue
  postop $key
  md5=$(cat $key | md5sum | awk '{print $1}')
  if [ -f "$md5" ]; then
    echo "${PINK}[X] Redundant${RESET} (deleting)"
    rm $key
  else
    echo "${CYAN}[*] Renamed $key -> $md5 ($(wc -c $key | awk '{print $1}') bytes)"
    mv $key $md5
    echo -n ${GREEN} && head -n 16 ${md5} 
    rem=$(( $(wc -l $md5 | awk '{print $1}') - 16 ))
    if (( $rem > 0 )); then
      (( $rem > 16 )) && rem=16
      echo -n ${DARKGREEN} && tail -n $rem ${md5}
    fi
    echo
  fi
}

function cleanup ()
{
  trap - INT
  echo "${MAGENTA}[*] Cleaning up...${RESET}"
  jobs
  while jobs | grep -q action; do
    echo -n "." 
    sleep 1
  done
  echo
  exit
}

trap cleanup INT

while :; do
  action &
  throttle $joblimit
done
