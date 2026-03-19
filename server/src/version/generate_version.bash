#!/usr/bin/env bash

set -euo pipefail

server="$(git rev-parse --show-toplevel)/server"
ver="$(< "${server}/out/version")"

cat <<EOF > generated.go
package version

const Version = "${ver}"
EOF
