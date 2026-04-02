# Cluster Kit

This repository turns a Jetson Orin Nano into the controller for a 10-node Raspberry Pi cluster on `10.0.0.0/24`.

It includes:

- Incus installation across the Pi nodes
- Jetson-side Incus remote registration
- Optional Incus clustering across the Pis
- Slurm + Munge setup with the Jetson as controller
- Cluster health checks and network debug helpers
- Fan-out command execution and diagnostic collection

## Repository layout

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

## Setup

1. Clone the repository onto the Jetson.
2. Create your local config file:

```bash
cp config/cluster.env.example config/cluster.env
```

3. Edit `config/cluster.env` and set:
- `SSH_USER`
- `PI_PASSWORD`
- `INCUS_TRUST_PASSWORD`
- any node names or IPs you want to change

4. Make the scripts executable:

```bash
chmod +x bin/*.sh
```

## Recommended workflow

Run these from the Jetson:

```bash
bin/check_cluster.sh
bin/setup_incus_mesh.sh
bin/setup_slurm_cluster.sh
```

If you want a full Incus cluster instead of separate Incus nodes with Jetson remotes:

```bash
bin/setup_incus_cluster.sh
```

## Publishing to GitHub

This repository is prepared so secrets stay local:

- `config/cluster.env` is ignored by Git
- `config/cluster.env.example` is safe to commit
- generated files, diagnostics, and local runtime output are ignored

Before pushing, verify:

```bash
git status
```

You should not see `config/cluster.env` in the tracked file list.

## Current cluster note

`10.0.0.172` is currently reachable by ping but not by SSH. The setup scripts skip SSH-unreachable nodes, so that Pi will not be configured until SSH is fixed.

## Design notes

- Slurm is configured with the Jetson as controller and the Pis as workers.
- The Incus mesh setup is the safer default.
- Full Incus clustering is more sensitive to node availability and should be used only after the network is stable.
