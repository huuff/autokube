#!/usr/bin/env bash
set -euo pipefail
set -- "${1:-./sample-cluster.json}"

GEN_CERTS_SCRIPT=$(realpath ./gen_certs.sh)
GEN_CONFIGS_SCRIPT=$(realpath ./gen_configs.sh)
GEN_ENCRYPTION_SCRIPT=$(realpath ./gen_encryption.sh)

CONF=$(realpath "$1")
CLUSTER_ID=$(jq -r '.cluster.id' "$CONF")

WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

declare workers_hostnames
declare -A workers_addresses
declare -A workers_users
for hostname in $(jq -r '.workers[].hostname' "$CONF"); do
  workers_hostnames+=("$hostname")
  # shellcheck disable=2034
  workers_addresses["$hostname"]=$(jq -r --arg h "$hostname" '.workers[] | select(.hostname == $h) | .address' "$CONF")
  # shellcheck disable=2034
  workers_users["$hostname"]=$(jq -r --arg h "$hostname" '.workers[] | select(.hostname == $h) | .user' "$CONF")
done

declare controllers_hostnames
declare -A controllers_addresses
declare -A controllers_users
for hostname in $(jq -r '.controllers[].hostname' "$CONF"); do
  controllers_hostnames+=("$hostname")
  # shellcheck disable=2034
  controllers_addresses["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .address' "$CONF")
  # shellcheck disable=2034
  controllers_users["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .user' "$CONF")
done

echo "Step 1: Generate and distribute certs"
echo "=========="
# shellcheck disable=1090,1091
source "$GEN_CERTS_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 2: Generate and distribute auth configs"
echo "=========="
# shellcheck disable=1090,1091
source "$GEN_CONFIGS_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 3: Generating and distributing encryption config"
# shellcheck disable=1090,1091
source "$GEN_ENCRYPTION_SCRIPT"
cd "$WORKDIR" || exit 1
