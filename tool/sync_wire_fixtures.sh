#!/usr/bin/env bash
# Copy the server's golden wire fixtures into this repo, or check they match.
# The server repo (DecTog/dectog) owns them: apps/worker/test/wire-contract.test.ts
# holds every live v1 response to their shape; test/wire_contract_test.dart
# parses the same files here.
#
#   tool/sync_wire_fixtures.sh            copy from ../dectog
#   tool/sync_wire_fixtures.sh --check    exit 1 when they differ
#   DECTOG_REPO=/path/to/dectog tool/sync_wire_fixtures.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
server="${DECTOG_REPO:-$here/../dectog}/apps/worker/test/fixtures/wire"
local_dir="$here/test/fixtures/wire"
[ -d "$server" ] || { echo "server fixtures not found at $server (set DECTOG_REPO)" >&2; exit 2; }
if [ "${1:-}" = "--check" ]; then
  diff -r "$server" "$local_dir" && echo "wire fixtures in sync"
else
  rm -f "$local_dir"/*.json
  cp "$server"/*.json "$local_dir"/
  echo "copied $(ls "$server"/*.json | wc -l | tr -d ' ') fixtures from $server"
fi
