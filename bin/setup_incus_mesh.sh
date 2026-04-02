#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_binary sshpass curl gpg sudo

log "Installing local client dependencies on the Jetson"
ensure_local_packages sshpass curl gpg incus-client

install_incus_node() {
  local ip="$1"
  local name
  name="$(node_name_for_ip "${ip}")"

  log "Installing and initializing Incus on ${name} (${ip})"
  run_remote_sudo_script "${ip}" "
install -d -m 0755 /etc/apt/keyrings
apt-get update
apt-get install -y curl gpg
curl -fsSL https://pkgs.zabbly.com/key.asc | gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg
cat > /etc/apt/sources.list.d/zabbly-incus-stable.sources <<SOURCES
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: \$(. /etc/os-release && echo \$VERSION_CODENAME)
Components: main
Architectures: \$(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.gpg
SOURCES
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y incus
id -nG '${SSH_USER}' | grep -qw incus-admin || usermod -aG incus-admin '${SSH_USER}'
systemctl enable incus.socket
systemctl restart incus.socket
if ! incus admin sql global 'select 1' >/dev/null 2>&1; then
  cat > /tmp/incus-preseed.yaml <<PRESEED
config:
  core.https_address: ${ip}:${INCUS_CLUSTER_ADDRESS_PORT}
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
cluster: null
PRESEED
  incus admin init --preseed < /tmp/incus-preseed.yaml
fi
incus config set core.https_address ${ip}:${INCUS_CLUSTER_ADDRESS_PORT}
incus config set core.trust_password ${INCUS_TRUST_PASSWORD}
"

  if incus remote list --format csv | awk -F, '{print $1}' | grep -qx "${name}"; then
    incus remote remove "${name}" >/dev/null 2>&1 || true
  fi

  log "Registering ${name} as an Incus remote on the Jetson"
  incus remote add "${name}" "https://${ip}:${INCUS_CLUSTER_ADDRESS_PORT}" --accept-certificate --password "${INCUS_TRUST_PASSWORD}"
}

for ip in "${PI_NODES[@]}"; do
  if ! ping_node "${ip}"; then
    log "Skipping ${ip}: no ping response"
    continue
  fi
  if ! ssh_ready "${ip}"; then
    log "Skipping ${ip}: SSH is not available"
    continue
  fi
  install_incus_node "${ip}"
done

log "Incus remote summary"
incus remote list
