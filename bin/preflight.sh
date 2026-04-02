#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_binary bash ssh sshpass scp ping timeout awk sed grep sudo

printf "%-20s %-8s %-40s\n" "CHECK" "STATUS" "DETAIL"
printf "%-20s %-8s %-40s\n" "--------------------" "--------" "----------------------------------------"

check_row() {
  printf "%-20s %-8s %-40s\n" "$1" "$2" "$3"
}

check_row "config-file" "ok" "${CLUSTER_CONFIG}"
check_row "jetson-interface" "ok" "${JETSON_INTERFACE}"

if ip -br addr show "${JETSON_INTERFACE}" >/dev/null 2>&1; then
  jetson_ip="$(ip -br addr show "${JETSON_INTERFACE}" | awk '{print $3}')"
  check_row "interface-present" "ok" "${jetson_ip:-no-ip}"
else
  check_row "interface-present" "fail" "${JETSON_INTERFACE} missing"
fi

for bin in incus sinfo munge sshpass arp-scan; do
  if command -v "${bin}" >/dev/null 2>&1; then
    check_row "binary:${bin}" "ok" "$(command -v "${bin}")"
  else
    check_row "binary:${bin}" "warn" "not installed locally"
  fi
done

ping_count=0
ssh_count=0

for ip in "${PI_NODES[@]}"; do
  name="$(node_name_for_ip "${ip}")"
  if ping_node "${ip}"; then
    ((ping_count+=1))
    if ssh_ready "${ip}"; then
      ((ssh_count+=1))
      check_row "node:${name}" "ok" "${ip} ping+ssh"
    else
      check_row "node:${name}" "warn" "${ip} ping only"
    fi
  else
    check_row "node:${name}" "fail" "${ip} unreachable"
  fi
done

check_row "summary" "ok" "${ping_count}/${#PI_NODES[@]} ping, ${ssh_count}/${#PI_NODES[@]} ssh"
