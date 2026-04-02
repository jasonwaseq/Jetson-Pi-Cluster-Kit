#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

OUT_DIR="${SCRIPT_DIR}/../diagnostics/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT_DIR}"

log "Collecting Jetson-side diagnostics into ${OUT_DIR}"
ip -br addr > "${OUT_DIR}/jetson-ip-br-addr.txt" 2>&1 || true
ip route > "${OUT_DIR}/jetson-ip-route.txt" 2>&1 || true
ip neigh show dev "${JETSON_INTERFACE}" > "${OUT_DIR}/jetson-ip-neigh.txt" 2>&1 || true
ss -tulpn > "${OUT_DIR}/jetson-ss.txt" 2>&1 || true
systemctl status munge slurmctld --no-pager > "${OUT_DIR}/jetson-services.txt" 2>&1 || true

for ip in "${PI_NODES[@]}"; do
  name="$(node_name_for_ip "${ip}")"
  if ! ssh_ready "${ip}"; then
    log "Skipping remote diagnostics for ${name} (${ip}): SSH unavailable"
    continue
  fi

  log "Collecting remote diagnostics from ${name} (${ip})"
  ssh_node "${ip}" "
hostname
ip -br addr
ip route
ss -tulpn
systemctl status ssh munge slurmd incus --no-pager || true
" > "${OUT_DIR}/${name}-${ip}.txt" 2>&1 || true
done

log "Diagnostics complete: ${OUT_DIR}"
