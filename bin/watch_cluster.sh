#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INTERVAL="${1:-10}"

while true; do
  clear
  printf 'Cluster watch at %s\n\n' "$(date)"
  "${SCRIPT_DIR}/check_cluster.sh"
  sleep "${INTERVAL}"
done
