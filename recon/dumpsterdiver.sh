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
[ -n "$useragent" ] || useragent="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
loot=$bin-loot
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
    mecho "${result}"
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
            mecho "${prefix}/${key}"
            ;;
        pastebin)
            n=8
            charset=a-z0-9
            prefix="https://pastebin.com/raw"
            key=$(cat /dev/urandom  | tr -dc $charset | head -c $n)
            mecho "${prefix}/${key}"
            ;;
        ghostbin)
            n=5
            charset=a-z0-9
            prefix="https://ghostbin.com/paste"
            key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
            suffix="raw"
            mecho "${prefix}/${key}/${suffix}"
            ;;
        pasteee)
            n=5
            charset=a-z0-9
            prefix="https://paste.ee/p"
            key=$(cat /dev/urandom  | tr -dc $charset | head -c $n)
            mecho "${prefix}/${key}"
            ;;
        pipfi)
            n=4
            charset=a-z0-9
            prefix="http://p.ip.fi"
            key=$(cat /dev/urandom | tr -dc $charset | head -c $n)
            mecho "${prefix}/${key}"
            ;;
    esac
}

function pii(){
    reg_cc_amex="3[47][0-9]{13}"
    reg_cc_visa="4[0-9]{12}(?:[0-9]{3})?"
    reg_cc_mastercard="5[1-5][0-9]{14}"
    reg_cc_unionpay="62[0-9]{14,17}"
    reg_cc_instapayment="63[7-9][0-9]{13}"
    reg_cc_dinersclub="3(?:0[0-5]|[68][0-9])[0-9]{11}"
    reg_ssn="[0-9]{3}-[0-9]{2}-[0-9]{4}"
    reg_email="[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}"
    reg_pii="${reg_email}|${reg_cc_amex}|${reg_cc_visa}|${reg_cc_mastercard}|${reg_cc_instapayment}|${reg_cc_unionpay}|${reg_cc_dinersclub}|${reg_ssn}"
    data_pii=$(mecho $data | grep -Eio $reg_pii)
    if mecho $data | grep -Eiq $reg_pii
        then mecho $data_pii
        else mecho 1
    fi
}

function action(){
    while :; do
        url=$(makeurl)
        db_url=$(sqlite_execute $db "select url from urls where url = '${url}'")
        if [ "${url}" = "${db_url}" ]; then
            mecho "${YELLOW}[*] ${url} has already visited generating another"
        else
            break
        fi
    done
    response=$(curl -A "${useragent}" --write-out %{http_code} --silent --output /dev/null "${url}")
    if [ "$response" = "200" ]; then
        data=$(curl -s -A "${useragent}" "${url}")
        md5=$(mecho -e "${data}" | md5sum | cut -d ' ' -f 1)
        data_pii=$(pii)
        db_md5=$(sqlite_execute $db "select hash from hashes where hash = '${md5}';")
        if [ "${db_md5}" != "${md5}" ]; then
            sqlite3 $db "insert into hashes(hash) values('${md5}');"
            hashes_id=$(sqlite_execute $db "select id from hashes where hash = '${md5}'")
            if [ "${data_pii}" = "1" ]; then
                sqlite3 $db "insert into urls(url, response, pii, hashes_id) values('${url}', '${response}', 0, ${hashes_id});"
            else
                mecho "${PINK}[*] found potential pii"
                sqlite3 $db "insert into urls(url, response, pii, hashes_id) values('${url}', '${response}', 1, ${hashes_id});"
            fi
            mecho "${GREEN}[-] fetched ${url} with response ${response} and md5sum of ${md5}"
            mecho "${BLUE}---BEGIN DATA---"
            mecho "${BLUE}${data}"
            mecho "${BLUE}---END DATA---"
            mecho "${BLUE}[-] writing loot to ${loot}/${md5}"
            mecho "${data}" > $loot/$md5
        else
            mecho "${YELLOW}[*] fetched ${url} however data alredy collected for hash ${md5}"
        fi
    else
        sqlite_execute $db "insert into urls(url, response, pii) values('${url}', '${response}', 0);"
        mecho "${RED}[x] fetching ${url} failed with response ${response}"
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
