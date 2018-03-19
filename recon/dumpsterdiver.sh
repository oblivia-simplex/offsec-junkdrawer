#!/usr/bin/env bash

bin=$1
db=$2
useragent=$3

joblimit=16

DARKGREEN=$'\e[00;32m'
GREEN=$'\e[01;32m'
TEAL=$'\e[00;36m'
DARKGREY=$'\e[01;30m'
CYAN=$'\e[01;36m'
LIGHTGREY=$'\e[00;37m'
RED=$'\e[00;31m'
PINK=$'\e[01;31m'
BLACK=$'\e[00;30m'
BLUE=$'\e[01;34m'
DARKBLUE=$'\e[00;34m'
WHITE=$'\e[01;38m'
RESET=$'\e[0m'
YELLOW=$'\e[01;33m'
MAGENTA=$'\e[01;35m'
PURPLE=$'\e[00;35m'

MUTEX=0

[ -n "$bin" ] || bin=ghostbin
loot=$bin-loot
[ -n "$useragent" ] || useragent="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
[ -d "$loot" ] || mkdir $loot
[ -n "$db" ] || db=visited.db

function mecho ()
{
  while (( $MUTEX )); do
    sleep 0.1
  done
  MUTEX=1
  echo $@
  MUTEX=0
}

function mcat ()
{
  while (( $MUTEX )); do
    sleep 0.1
  done
  MUTEX=1
  cat $@
  MUTEX=0
}

function sqlite_execute(){
    while :; do
        result=$(sqlite3 $1 "${2}" 2>&1) #| tee /dev/stderr)
        if [ "${result}" = "Error: database is locked" ]; then
            sleep 0.01
            continue
        else
            break
        fi
    done
    #mecho "${result}"
}

if [ ! -f $db ]; then
    mecho "${YELLOW}[*] dumpsterdiver database not found creating a new one"
    touch $db
    sqlite_execute $db "create table urls(id integer primary key autoincrement, url varchar(512) unique, response integer, pii integer, md5 varchar(32));"
fi

function makeurl(){
    case "$bin" in
        termbin)
            n=4
            charset=a-z0-9
            prefix="http://termbin.com"
            key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
            echo "${prefix}/${key}"
            ;;
        pastebin)
            n=8
            charset=a-z0-9
            prefix="https://pastebin.com/raw"
            key=$(cat /dev/urandom  | tr -dc $charset | head -c $n)
            echo "${prefix}/${key}"
            ;;
        ghostbin)
            n=5
            charset=a-z0-9
            prefix="https://ghostbin.com/paste"
            key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
            suffix="download"
            echo "${prefix}/${key}/${suffix}"
            ;;
        pasteee)
            n=5
            charset=a-z0-9
            prefix="https://paste.ee/p"
            key=$(cat /dev/urandom  | tr -dc $charset | head -c $n)
            suffix="0"
            echo "${prefix}/${key}"
            ;;
        pipfi)
            n=4
            charset=a-z0-9
            prefix="http://p.ip.fi"
            key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
            echo "${prefix}/${key}"
            ;;
    esac
}

function pii(){
    file=$1
    hits=0
    #reg_cc="(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})"
    cat $file \
      | grep -P "([0-9]{1,3}\.){3}[0-9]{1,3}" \
      | grep -vP "(127(\.[0-9]{1,3}){3}|0\.0\.0\.0)" \
      >> ${file}.pii \
      && hits=$(( hits + 1 ))
    
    # now look for cryptocurrency keys
    cat $file \
      | grep -wP '[5KL][1-9A-HJ-NP-Za-km-z]{50,51}' \
      >> ${file}.pii \
      && hits=$(( hits + 1 ))

    # email
    cat $file \
      | grep -P "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}" \
      >> ${file}.pii \
      && hits=$(( hits + 1 ))

    # private keys and credentials
    cat $file \
      | grep -P "(PRIVATE KEY|password|credential|0day)" \
      >> ${file}.pii \
      && hits=$(( hits + 1 ))
    
    echo $hits
}

function action(){
    while :; do
      url=$(makeurl)
      db_url=$(sqlite_execute $db "select url from urls where url = '${url}'")
      if [ "${url}" = "${db_url}" ]; then
          mecho -e "\n${YELLOW}--- Already visited ${url} ---"
      else
          break
      fi
    done
    tmp=$(mktemp)
    response=$(curl -A "${useragent}" --write-out %{http_code} --silent --output $tmp "${url}")
    mecho -en "\r${RESET} [$(ls $loot | wc -l | awk '{print $1}')] ====${WHITE} $url ${RESET}==== [${response}] "
    if [ "$response" = "200" ]; then
      echo
      #curl -s -A "${useragent}" "${url}" > $tmp
      md5=$(md5sum $tmp | cut -d ' ' -f 1)
      file=${loot}/${md5}
      if ! [ -f "$file" ]; then
        data_pii=0 #data_pii=$(pii $tmp)
        if ! (( "${data_pii}" )); then
          echo -n "$MAGENTA"
          sqlite3 $db "insert into urls(url, response, pii, md5) values('${url}', '${response}', 0, '${md5}');"
        else
          mecho -e "\n${PINK}[*] found $data_pii potential pii${RED}"
          mcat ${tmp}.pii
          echo -n "${RESET}"
          sqlite3 $db "insert into urls(url, response, pii, md5) values('${url}', '${response}', 1, '${md5}');"
        fi
        mecho -e "\n${CYAN}${url} ---> ${file}${RESET}"
        mv $tmp $file
        #rm ${tmp}.pii
        (echo -n ${GREEN} && head -n 16 $file) | mcat
        rem=$(( $(wc -l $file | awk '{print $1}') - 16 ))
        if (( $rem > 0 )); then
            (( $rem > 16 )) && rem=16
            (echo -n ${DARKGREEN} && tail -n $rem ${file}) | mcat
        fi
      else
          mecho -e "\n${YELLOW}[*] fetched ${url}, but data redundant"
      fi
    else
        sqlite_execute $db "insert into urls(url, response, pii) values('${url}', '${response}', 0);"
        rm -f $tmp
        #mecho "${RED}[x] fetching ${url} failed with response ${response}"
    fi
}

function throttle(){
  joblimit=$1
  joblist=($(jobs -p))
  while (( ${#joblist[*]} >= $joblimit )); do
    sleep 1
    joblist=($(jobs -p))
  done
}

if [ "${joblimit}" = "1" ]; then
    while :; do
        action
    done
else
    while :; do
        action &
        throttle $joblimit
    done
fi
