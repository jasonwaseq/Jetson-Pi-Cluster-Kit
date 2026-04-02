#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

printf "%-15s %-8s %-8s %-8s %-8s %-8s\n" "IP" "PING" "SSH" "INCUS" "SLURMD" "MUNGE"
printf "%-15s %-8s %-8s %-8s %-8s %-8s\n" "---------------" "--------" "--------" "--------" "--------" "--------"

for ip in "${PI_NODES[@]}"; do
  ping_status="fail"
  ssh_status="down"
  incus_status="closed"
  slurmd_status="closed"
  munge_status="closed"

  if ping_node "${ip}"; then
    ping_status="ok"
  fi
  if ssh_ready "${ip}"; then
    ssh_status="ok"
  fi
  if port_open "${ip}" 8443; then
    incus_status="open"
  fi
  if port_open "${ip}" 6818; then
    slurmd_status="open"
  fi
  if ssh_ready "${ip}" && ssh_node "${ip}" "systemctl is-active munge >/dev/null 2>&1"; then
    munge_status="active"
  fi

  printf "%-15s %-8s %-8s %-8s %-8s %-8s\n" "${ip}" "${ping_status}" "${ssh_status}" "${incus_status}" "${slurmd_status}" "${munge_status}"
done
