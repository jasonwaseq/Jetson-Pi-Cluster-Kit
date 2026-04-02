#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_binary incus awk

"${SCRIPT_DIR}/setup_incus_mesh.sh"

leader_ip=""
leader_name=""
cluster_ips=()
cluster_names=()

for ip in "${PI_NODES[@]}"; do
  if ssh_ready "${ip}"; then
    cluster_ips+=("${ip}")
    cluster_names+=("$(node_name_for_ip "${ip}")")
  fi
done

(( ${#cluster_ips[@]} >= 3 )) || die "Need at least 3 SSH-reachable Pi nodes for an Incus cluster"

leader_ip="${cluster_ips[0]}"
leader_name="${cluster_names[0]}"

log "Bootstrapping Incus cluster leader ${leader_name} (${leader_ip})"
run_remote_sudo_script "${leader_ip}" "
cat > /tmp/incus-cluster-leader.yaml <<PRESEED
config:
  core.https_address: ${leader_ip}:${INCUS_CLUSTER_ADDRESS_PORT}
  core.trust_password: ${INCUS_TRUST_PASSWORD}
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  description: ''
  name: ${INCUS_BRIDGE_NAME}
  type: bridge
storage_pools:
- config: {}
  description: ''
  name: ${INCUS_STORAGE_POOL}
  driver: dir
profiles:
- config: {}
  description: Default Incus profile
  devices:
    eth0:
      name: eth0
      network: ${INCUS_BRIDGE_NAME}
      type: nic
    root:
      path: /
      pool: ${INCUS_STORAGE_POOL}
      type: disk
  name: default
project: default
cluster:
  enabled: true
  server_name: ${leader_name}
PRESEED
incus admin init --preseed < /tmp/incus-cluster-leader.yaml || true
"

for i in "${!cluster_ips[@]}"; do
  if (( i == 0 )); then
    continue
  fi

  member_ip="${cluster_ips[$i]}"
  member_name="${cluster_names[$i]}"
  log "Adding Incus cluster member ${member_name} (${member_ip})"

  token="$(ssh_node "${leader_ip}" "printf '%s\n' '${PI_PASSWORD}' | sudo -S incus cluster add ${member_name} | tail -n 1")"
  if [[ -z "${token}" ]]; then
    die "Failed to retrieve cluster token for ${member_name}"
  fi

  run_remote_sudo_script "${member_ip}" "
cat > /tmp/incus-cluster-join.yaml <<PRESEED
config:
  core.https_address: ${member_ip}:${INCUS_CLUSTER_ADDRESS_PORT}
cluster:
  enabled: true
  server_name: ${member_name}
  cluster_address: ${leader_ip}:${INCUS_CLUSTER_ADDRESS_PORT}
  cluster_token: ${token}
PRESEED
incus admin init --preseed < /tmp/incus-cluster-join.yaml || true
"
done

log "Incus cluster view from ${leader_name}"
ssh_node "${leader_ip}" "printf '%s\n' '${PI_PASSWORD}' | sudo -S incus cluster list"
