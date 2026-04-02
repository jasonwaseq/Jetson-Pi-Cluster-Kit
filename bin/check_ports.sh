#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

if (( $# == 0 )); then
  set -- 22 8443 6817 6818
fi

printf "%-15s" "IP"
for port in "$@"; do
  printf " %-8s" "${port}"
done
printf "\n"

for ip in "${PI_NODES[@]}"; do
  printf "%-15s" "${ip}"
  for port in "$@"; do
    if port_open "${ip}" "${port}"; then
      printf " %-8s" "open"
    else
      printf " %-8s" "closed"
    fi
  done
  printf "\n"
done
