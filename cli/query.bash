#!/usr/bin/env bash

set -euo pipefail

function usage_and_die {
    echo >&2 "usage: $0 (read | write) QUERY"
    exit 1
}

function quote {
    printf "'%s'\n" "$(sed "s/'/''/g")"
}

if (( $# != 2 )); then
    usage_and_die
fi

case "$1" in
    read) safe=yes ;;
    write) safe= ;;
    *) usage_and_die ;;
esac

query="$2"

if [[ -z "${safe}" ]]; then
    query="${query}; INSERT INTO journal VALUES ($(uuidgen -r | tr -d -- - | quote), $(quote <<< "${query}"), $(( $(date +%-s%N) / 1000000 )))"
fi

query="BEGIN TRANSACTION; ${query}; COMMIT TRANSACTION"

sqlite3 "${SHALLAN_HOME}/library.sqlite3" "${query}"
