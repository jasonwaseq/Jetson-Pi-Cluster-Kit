# Jetson Pi Cluster Kit

Jetson Pi Cluster Kit turns a Jetson Orin Nano into a controller for a Raspberry Pi compute cluster on a private Ethernet fabric. It provides repeatable setup scripts for Incus, Slurm, Munge, and cluster diagnostics so the Jetson can manage and observe the Pi fleet from one place.

## Features

- Incus installation on every SSH-reachable Pi
- Jetson-side Incus remote registration for each Pi
- Optional full Incus clustering across the Pis
- Slurm controller setup on the Jetson with Pi worker enrollment
- Munge key generation and distribution
- Health checks for ping, SSH, Incus, Slurm, and Munge
- Port probes, live monitoring, remote command fan-out, and diagnostic collection

## Repository Layout

- `bin/preflight.sh`: validate local dependencies, interface visibility, and node reachability
- `bin/bootstrap_cluster.sh`: one-command setup wrapper for preflight, Incus mesh, and Slurm
- `bin/setup_incus_mesh.sh`: install Incus on all SSH-reachable Pis and add them as Incus remotes on the Jetson
- `bin/setup_incus_cluster.sh`: optional Incus cluster bootstrap across the Pi nodes
- `bin/setup_slurm_cluster.sh`: install Munge and Slurm and generate a cluster-wide `slurm.conf`
- `bin/check_cluster.sh`: cluster health table for ping, SSH, Incus, Slurm, and Munge
- `bin/check_ports.sh`: test one or more ports across all nodes
- `bin/collect_diagnostics.sh`: collect Jetson and Pi diagnostics into timestamped files
- `bin/watch_cluster.sh`: refreshing cluster health dashboard
- `bin/run_on_all.sh`: run a shell command on every SSH-reachable Pi
- `config/cluster.env.example`: example inventory and settings file
- `lib/common.sh`: shared helpers for SSH, SCP, ping, ports, and host inventory

## Requirements

- Jetson host running Ubuntu with `sudo`
- Raspberry Pis reachable from the Jetson over Ethernet
- Password-based SSH access from the Jetson to the Pis for initial setup
- Internet access on nodes when installing packages
- A local config file at `config/cluster.env`

## Quick Start

```bash
git clone git@github.com:jasonwaseq/Jetson-Pi-Cluster-Kit.git
cd Jetson-Pi-Cluster-Kit
cp config/cluster.env.example config/cluster.env
chmod +x bin/*.sh
```

Edit `config/cluster.env` and set:

- `SSH_USER`
- `PI_PASSWORD`
- `INCUS_TRUST_PASSWORD`
- any node names or IPs you want to change

Run a readiness check:

```bash
bin/preflight.sh
bin/check_cluster.sh
```

Run the standard setup path:

```bash
bin/bootstrap_cluster.sh
```

Or run the major steps manually:

```bash
bin/setup_incus_mesh.sh
bin/setup_slurm_cluster.sh
```

If you want a full Incus cluster instead of separate Incus nodes with Jetson remotes:

```bash
bin/setup_incus_cluster.sh
```

## Typical Operations

Watch cluster status:

```bash
bin/watch_cluster.sh 10
```

Check important ports:

```bash
bin/check_ports.sh 22 8443 6817 6818
```

Run a command on every reachable Pi:

```bash
bin/run_on_all.sh "hostname && uptime"
```

Collect diagnostics into timestamped files:

```bash
bin/collect_diagnostics.sh
```

## GitHub Safety

This repository is prepared so secrets stay local:

- `config/cluster.env` is ignored by Git
- `config/cluster.env.example` is safe to commit
- generated files, diagnostics, and local runtime output are ignored

Before pushing, verify:

```bash
git status
```

You should not see `config/cluster.env` in the tracked file list.

## Current Cluster Note

`10.0.0.172` is currently reachable by ping but not by SSH. The setup scripts skip SSH-unreachable nodes, so that Pi will not be configured until SSH is fixed.

## Design Notes

- Slurm is configured with the Jetson as controller and the Pis as workers.
- The Incus mesh setup is the safer default.
- Full Incus clustering is more sensitive to node availability and should be used only after the network is stable.
- The toolkit is intentionally shell-based so it can be audited and modified quickly on the Jetson itself.
