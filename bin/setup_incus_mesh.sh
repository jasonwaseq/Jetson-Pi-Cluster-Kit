#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_binary sshpass curl gpg sudo

install_local_incus() {
  log "Installing local Incus client dependencies on the Jetson"
  sudo install -d -m 0755 /etc/apt/keyrings
  sudo apt-get update
  sudo apt-get install -y sshpass curl gpg
  sudo rm -f /etc/apt/sources.list.d/zabbly-incus-stable.list
  curl -fsSL https://pkgs.zabbly.com/key.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/zabbly.gpg
  sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.sources >/dev/null <<SOURCES
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.gpg
SOURCES
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y incus-client
}

if ! command -v incus >/dev/null 2>&1; then
  install_local_incus
fi

install_incus_node() {
  local ip="$1"
  local name
  name="$(node_name_for_ip "${ip}")"

  log "Installing and initializing Incus on ${name} (${ip})"
  run_remote_sudo_script "${ip}" "
wait_for_apt() {
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    sleep 3
  done
}

install -d -m 0755 /etc/apt/keyrings
wait_for_apt
apt-get update
wait_for_apt
apt-get install -y curl gpg
rm -f /etc/apt/sources.list.d/zabbly-incus-stable.list
curl -fsSL https://pkgs.zabbly.com/key.asc | gpg --batch --yes --dearmor -o /etc/apt/keyrings/zabbly.gpg
cat > /etc/apt/sources.list.d/zabbly-incus-stable.sources <<SOURCES
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: \$(. /etc/os-release && echo \$VERSION_CODENAME)
Components: main
Architectures: \$(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.gpg
SOURCES
wait_for_apt
apt-get update
wait_for_apt
DEBIAN_FRONTEND=noninteractive apt-get install -y incus
id -nG '${SSH_USER}' | grep -qw incus-admin || usermod -aG incus-admin '${SSH_USER}'
if command -v ufw >/dev/null 2>&1; then
  ufw allow 8443/tcp || true
fi
systemctl enable incus.socket
systemctl restart incus.socket
if ! incus admin sql global 'select 1' >/dev/null 2>&1; then
  cat > /tmp/incus-preseed.yaml <<PRESEED
config:
  core.https_address: ${ip}:${INCUS_CLUSTER_ADDRESS_PORT}
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
"

  if incus remote list --format csv | awk -F, '{print $1}' | grep -qx "${name}"; then
    log "Incus remote ${name} already exists on the Jetson"
    return 0
  fi

  log "Registering ${name} as an Incus remote on the Jetson"
  token="$(ssh_node "${ip}" "printf '%s\n' '${PI_PASSWORD}' | sudo -S incus config trust add jetson-${name} --quiet" 2>/dev/null || true)"
  if [[ -z "${token}" ]]; then
    die "Failed to get Incus trust token from ${name} (${ip})"
  fi
  if ! incus remote add "${name}" "https://${ip}:${INCUS_CLUSTER_ADDRESS_PORT}" --accept-certificate --token "${token}" >/tmp/incus-remote-add.${name}.log 2>&1; then
    if grep -q "Client is already trusted" "/tmp/incus-remote-add.${name}.log"; then
      incus remote add "${name}" "https://${ip}:${INCUS_CLUSTER_ADDRESS_PORT}" --accept-certificate
    else
      cat "/tmp/incus-remote-add.${name}.log" >&2
      rm -f "/tmp/incus-remote-add.${name}.log"
      die "Failed to add Incus remote ${name} (${ip})"
    fi
  fi
  rm -f "/tmp/incus-remote-add.${name}.log"
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
