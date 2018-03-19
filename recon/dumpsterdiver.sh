#!/usr/bin/env bash

bin=$1
db=$2
useragent=$3

joblimit=2

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
        result=$(sqlite3 $1 "${2}" 2>&1)
        if [ "${result}" = "Error: database is locked" ]; then
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
    sqlite_execute $db "create table urls(id integer primary key autoincrement, url varchar(2083) unique, response integer, pii integer, hashes_id integer);"
    sqlite_execute $db "create table hashes(id integer primary key autoincrement, hash varchar(32) unique);"
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
    reg_cc="(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})"
    reg_email="[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}"
    reg_pii="${reg_email}|${reg_cc}"
    grep -Ei "${reg_pii}" "${file}" > ${file}.pii \
        && echo 0 \
            || echo 1
}

function action(){
    while :; do
        url=$(makeurl)
        db_url=$(sqlite_execute $db "select url from urls where url = '${url}'")
        if [ "${url}" = "${db_url}" ]; then
            mecho "${YELLOW}[*] ${url} has already visited; generating another..."
        else
            break
        fi
    done
    response=$(curl -A "${useragent}" --write-out %{http_code} -I --silent --output /dev/null "${url}")
    mecho -en "\r${RESET} [$(ls $loot | wc -l | awk '{print $1}')] ====${WHITE} $url ${RESET}==== [${response}] "
    if [ "$response" = "200" ]; then
        echo
        tmp=$(mktemp)
        curl -s -A "${useragent}" "${url}" > $tmp
        md5=$(md5sum $tmp | cut -d ' ' -f 1)
        echo ">>> md5: $md5"
        data_pii=$(pii $tmp)
        db_md5=$(sqlite_execute $db "select hash from hashes where hash = '${md5}';")
        if [ "${db_md5}" != "${md5}" ]; then
            sqlite3 $db "insert into hashes(hash) values('${md5}');"
            hashes_id=$(sqlite_execute $db "select id from hashes where hash = '${md5}'")
            if (( "${data_pii}" )); then
                sqlite3 $db "insert into urls(url, response, pii, hashes_id) values('${url}', '${response}', 0, ${hashes_id});"
            else
                mecho -e "\n${PINK}[*] found potential pii${RED}"
                mcat ${tmp}.pii
                echo "${RESET}"
                echo ">> url: $url"
                echo ">> response: $response"
                echo ">> hashes_id: $hashes_id"
                sqlite3 $db "insert into urls(url, response, pii, hashes_id) values('${url}', '${response}', 1, ${hashes_id});"
            fi
            file=${loot}/${md5}
            mecho "${CYAN}[+] ${url} -> ${file}${RESET}"
            mv $tmp $file
            rm ${tmp}.pii
            (echo -n ${GREEN} && head -n 16 $file) | mcat
            rem=$(( $(wc -l $file | awk '{print $1}') - 16 ))
            if (( $rem > 0 )); then
                (( $rem > 16 )) && rem=16
                (echo -n ${DARKGREEN} && tail -n $rem ${file}) | mcat
            fi
        else
            mecho "${YELLOW}[*] fetched ${url} however data alredy collected for hash ${md5}"
        fi
    else
        sqlite_execute $db "insert into urls(url, response, pii) values('${url}', '${response}', 0);"
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
