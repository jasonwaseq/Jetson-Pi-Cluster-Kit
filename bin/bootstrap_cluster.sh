#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Preflight =="
"${SCRIPT_DIR}/preflight.sh"

echo
echo "== Health check =="
"${SCRIPT_DIR}/check_cluster.sh"

echo
echo "== Incus mesh setup =="
"${SCRIPT_DIR}/setup_incus_mesh.sh"

echo
echo "== Slurm setup =="
"${SCRIPT_DIR}/setup_slurm_cluster.sh"

echo
echo "== Final health check =="
"${SCRIPT_DIR}/check_cluster.sh"
