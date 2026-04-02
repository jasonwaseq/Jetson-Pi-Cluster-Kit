#!/usr/bin/env bash

set -o pipefail

CLUSTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_ROOT="$(cd "${CLUSTER_LIB_DIR}/.." && pwd)"
CLUSTER_CONFIG="${CLUSTER_CONFIG:-${CLUSTER_ROOT}/config/cluster.env}"

if [[ ! -f "${CLUSTER_CONFIG}" ]]; then
  echo "Missing cluster config: ${CLUSTER_CONFIG}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${CLUSTER_CONFIG}"

if [[ "${#PI_NODES[@]}" -ne "${#PI_NAMES[@]}" ]]; then
  echo "PI_NODES and PI_NAMES must have the same length" >&2
  exit 1
fi

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}"
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=2
)

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_binary() {
  local missing=0
  local bin
  for bin in "$@"; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "${bin}" >&2
      missing=1
    fi
  done
  (( missing == 0 )) || exit 1
}

node_name_for_ip() {
  local ip="$1"
  local i
  for i in "${!PI_NODES[@]}"; do
    if [[ "${PI_NODES[$i]}" == "${ip}" ]]; then
      printf '%s\n' "${PI_NAMES[$i]}"
      return 0
    fi
  done
  return 1
}

node_ip_for_name() {
  local name="$1"
  local i
  for i in "${!PI_NAMES[@]}"; do
    if [[ "${PI_NAMES[$i]}" == "${name}" ]]; then
      printf '%s\n' "${PI_NODES[$i]}"
      return 0
    fi
  done
  return 1
}

ping_node() {
  local ip="$1"
  ping -c 1 -W 1 "${ip}" >/dev/null 2>&1
}

ssh_node() {
  local ip="$1"
  shift
  sshpass -p "${PI_PASSWORD}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "$@"
}

scp_to_node() {
  local src="$1"
  local ip="$2"
  local dest="$3"
  sshpass -p "${PI_PASSWORD}" scp "${SSH_OPTS[@]}" "${src}" "${SSH_USER}@${ip}:${dest}"
}

scp_from_node() {
  local ip="$1"
  local src="$2"
  local dest="$3"
  sshpass -p "${PI_PASSWORD}" scp "${SSH_OPTS[@]}" "${SSH_USER}@${ip}:${src}" "${dest}"
}

ssh_ready() {
  local ip="$1"
  sshpass -p "${PI_PASSWORD}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "true" >/dev/null 2>&1
}

port_open() {
  local ip="$1"
  local port="$2"
  timeout 2 bash -lc "</dev/tcp/${ip}/${port}" >/dev/null 2>&1
}

reachable_nodes() {
  local ip
  for ip in "${PI_NODES[@]}"; do
    if ping_node "${ip}"; then
      printf '%s\n' "${ip}"
    fi
  done
}

ssh_nodes() {
  local ip
  for ip in "${PI_NODES[@]}"; do
    if ssh_ready "${ip}"; then
      printf '%s\n' "${ip}"
    fi
  done
}

run_remote_script() {
  local ip="$1"
  local script="$2"
  sshpass -p "${PI_PASSWORD}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "bash -s" <<EOF
${script}
EOF
}

run_remote_sudo_script() {
  local ip="$1"
  local script="$2"
  sshpass -p "${PI_PASSWORD}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "bash -s" <<EOF
set -euo pipefail
printf '%s\n' '${PI_PASSWORD}' | sudo -S bash <<'REMOTE_EOF'
${script}
REMOTE_EOF
EOF
}

ensure_hosts_block() {
  local target="$1"
  local mode="$2"
  local tmp
  tmp="$(mktemp)"
  {
    printf '# CLUSTER-KIT START\n'
    printf '%s %s\n' "${JETSON_CLUSTER_IP}" "${JETSON_HOSTNAME}"
    local i
    for i in "${!PI_NODES[@]}"; do
      printf '%s %s\n' "${PI_NODES[$i]}" "${PI_NAMES[$i]}"
    done
    printf '# CLUSTER-KIT END\n'
  } > "${tmp}"

  if [[ "${mode}" == "local" ]]; then
    sudo awk '
      BEGIN {skip=0}
      /^# CLUSTER-KIT START$/ {skip=1; next}
      /^# CLUSTER-KIT END$/ {skip=0; next}
      skip==0 {print}
    ' /etc/hosts > "${tmp}.base"
    cat "${tmp}.base" "${tmp}" | sudo tee /etc/hosts >/dev/null
    rm -f "${tmp}.base"
  else
    scp_to_node "${tmp}" "${target}" "/tmp/cluster-hosts.block"
    ssh_node "${target}" "printf '%s\n' '${PI_PASSWORD}' | sudo -S bash -lc \"awk 'BEGIN {skip=0} /^# CLUSTER-KIT START$/ {skip=1; next} /^# CLUSTER-KIT END$/ {skip=0; next} skip==0 {print}' /etc/hosts > /tmp/hosts.base && cat /tmp/hosts.base /tmp/cluster-hosts.block > /tmp/hosts.merged && cp /tmp/hosts.merged /etc/hosts && rm -f /tmp/hosts.base /tmp/hosts.merged /tmp/cluster-hosts.block\""
  fi

  rm -f "${tmp}"
}

ensure_local_packages() {
  sudo apt-get update
  sudo apt-get install -y "$@"
}

remote_install_packages() {
  local ip="$1"
  shift
  ssh_node "${ip}" "printf '%s\n' '${PI_PASSWORD}' | sudo -S apt-get update && printf '%s\n' '${PI_PASSWORD}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y $*"
}
