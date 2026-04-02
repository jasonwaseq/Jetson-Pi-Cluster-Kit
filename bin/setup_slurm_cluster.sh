#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

require_binary sshpass sudo awk sed grep

GENERATED_DIR="${SCRIPT_DIR}/../generated"
SLURM_CONF="${GENERATED_DIR}/slurm.conf"
mkdir -p "${GENERATED_DIR}"

log "Installing local Slurm controller dependencies on the Jetson"
ensure_local_packages sshpass munge libmunge2 libmunge-dev slurmctld slurm-client slurmd slurm-wlm-basic-plugins

log "Ensuring controller-side hosts entries are present"
ensure_hosts_block "" "local"

if [[ ! -f /etc/munge/munge.key ]]; then
  log "Generating MUNGE key on the Jetson"
  sudo /usr/sbin/mungekey
fi

sudo chown -R munge: /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 0700 /etc/munge /var/log/munge /var/lib/munge
sudo chmod 0755 /run/munge
sudo chmod 0400 /etc/munge/munge.key
sudo systemctl enable munge
sudo systemctl restart munge

reachable_ips=()
reachable_names=()
node_lines=()

for i in "${!PI_NODES[@]}"; do
  ip="${PI_NODES[$i]}"
  name="${PI_NAMES[$i]}"

  if ! ping_node "${ip}"; then
    log "Skipping ${name} (${ip}): no ping response"
    continue
  fi
  if ! ssh_ready "${ip}"; then
    log "Skipping ${name} (${ip}): SSH unavailable"
    continue
  fi

  log "Installing Slurm worker dependencies on ${name} (${ip})"
  run_remote_sudo_script "${ip}" "
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y munge libmunge2 libmunge-dev slurmd slurm-client slurm-wlm-basic-plugins
mkdir -p ${SLURM_SPOOLDIR}
chown slurm:slurm ${SLURM_SPOOLDIR}
chmod 0755 ${SLURM_SPOOLDIR}
systemctl enable munge
"

  ensure_hosts_block "${ip}" "remote"
  scp_to_node "/etc/munge/munge.key" "${ip}" "/tmp/munge.key"
  run_remote_sudo_script "${ip}" "
cp /tmp/munge.key /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 0400 /etc/munge/munge.key
systemctl restart munge
"

  cpus="$(ssh_node "${ip}" "nproc")"
  mem_mb="$(ssh_node "${ip}" "awk '/MemTotal/ {print int(\$2/1024) - 256}' /proc/meminfo")"
  if [[ -z "${mem_mb}" || "${mem_mb}" -lt 256 ]]; then
    mem_mb=512
  fi

  node_lines+=("NodeName=${name} NodeAddr=${ip} NodeHostname=${name} CPUs=${cpus} RealMemory=${mem_mb} State=UNKNOWN")
  reachable_ips+=("${ip}")
  reachable_names+=("${name}")
done

(( ${#node_lines[@]} > 0 )) || die "No SSH-reachable Pi nodes available for Slurm setup"

log "Writing generated Slurm config to ${SLURM_CONF}"
{
  printf 'ClusterName=%s\n' "${SLURM_CLUSTER_NAME}"
  printf 'SlurmctldHost=%s(%s)\n' "${JETSON_HOSTNAME}" "${JETSON_CLUSTER_IP}"
  printf 'MpiDefault=none\n'
  printf 'ProctrackType=proctrack/cgroup\n'
  printf 'ReturnToService=2\n'
  printf 'SlurmctldPidFile=/run/slurmctld.pid\n'
  printf 'SlurmctldPort=6817\n'
  printf 'SlurmdPidFile=/run/slurmd.pid\n'
  printf 'SlurmdPort=6818\n'
  printf 'SlurmdSpoolDir=%s\n' "${SLURM_SPOOLDIR}"
  printf 'StateSaveLocation=%s\n' "${SLURM_STATE_SAVE_DIR}"
  printf 'SwitchType=switch/none\n'
  printf 'TaskPlugin=task/affinity,task/cgroup\n'
  printf 'InactiveLimit=0\n'
  printf 'KillWait=30\n'
  printf 'MinJobAge=300\n'
  printf 'Waittime=0\n'
  printf 'SchedulerType=sched/backfill\n'
  printf 'SelectType=select/cons_tres\n'
  printf 'SelectTypeParameters=CR_Core\n'
  printf 'AuthType=auth/munge\n'
  printf 'CryptoType=crypto/munge\n'
  printf 'SlurmUser=slurm\n'
  printf 'SlurmdUser=root\n'
  printf 'SlurmctldTimeout=120\n'
  printf 'SlurmdTimeout=300\n'
  printf '\n'
  printf '# Compute nodes\n'
  printf '%s\n' "${node_lines[@]}"
  printf 'PartitionName=%s Nodes=%s Default=YES MaxTime=INFINITE State=UP\n' \
    "${SLURM_PARTITION_NAME}" \
    "$(IFS=,; printf '%s' "${reachable_names[*]}")"
} > "${SLURM_CONF}"

sudo mkdir -p /etc/slurm "${SLURM_STATE_SAVE_DIR}" "${SLURM_SPOOLDIR}"
sudo chown slurm:slurm "${SLURM_STATE_SAVE_DIR}" "${SLURM_SPOOLDIR}"
sudo chmod 0755 "${SLURM_STATE_SAVE_DIR}" "${SLURM_SPOOLDIR}"
sudo cp "${SLURM_CONF}" /etc/slurm/slurm.conf

log "Starting Slurm controller on the Jetson"
sudo systemctl enable slurmctld
sudo systemctl restart slurmctld

for ip in "${reachable_ips[@]}"; do
  name="$(node_name_for_ip "${ip}")"
  log "Pushing Slurm config to ${name} (${ip})"
  scp_to_node "${SLURM_CONF}" "${ip}" "/tmp/slurm.conf"
  run_remote_sudo_script "${ip}" "
mkdir -p /etc/slurm ${SLURM_SPOOLDIR}
cp /tmp/slurm.conf /etc/slurm/slurm.conf
chown slurm:slurm ${SLURM_SPOOLDIR}
chmod 0755 ${SLURM_SPOOLDIR}
systemctl enable slurmd
systemctl restart slurmd
"
done

log "Slurm node summary"
sinfo || true
