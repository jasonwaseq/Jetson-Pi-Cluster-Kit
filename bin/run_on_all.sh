#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

(( $# > 0 )) || die "Usage: $0 <command>"

for ip in "${PI_NODES[@]}"; do
  name="$(node_name_for_ip "${ip}")"
  log "Running on ${name} (${ip})"
  if ! ssh_ready "${ip}"; then
    log "Skipping ${name}: SSH unavailable"
    continue
  fi
  ssh_node "${ip}" "$*" || true
done
