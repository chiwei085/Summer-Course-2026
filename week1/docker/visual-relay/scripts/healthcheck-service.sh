#!/bin/sh
set -eu

port="${1:?usage: healthcheck-service.sh PORT}"

if nc -w 1 127.0.0.1 "$port" <<EOF | grep -q 'ready=true'
GET /ready HTTP/1.1
Host: 127.0.0.1
Connection: close

EOF
then
    exit 0
fi

exit 1
