#!/usr/bin/env bash
# shellcheck disable=2034,1090,1091
set -euo pipefail
set -- "${1:-./sample-cluster.json}"

GEN_CERTS_SCRIPT=$(realpath ./gen_certs.sh)
GEN_CONFIGS_SCRIPT=$(realpath ./gen_configs.sh)
GEN_ENCRYPTION_SCRIPT=$(realpath ./gen_encryption.sh)
BOOTSTRAP_ETCD_SCRIPT=$(realpath ./bootstrap_etcd.sh)
BOOTSTRAP_CONTROLLERS_SCRIPT=$(realpath ./bootstrap_controllers.sh)

CONF=$(realpath "$1")
CLUSTER_ID=$(jq -r '.cluster.id' "$CONF")

join_by=$(realpath ./join_by.sh)

WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

declare workers_hostnames
declare -A workers_addresses
declare -A workers_users
for hostname in $(jq -r '.workers[].hostname' "$CONF"); do
  workers_hostnames+=("$hostname")
  workers_addresses["$hostname"]=$(jq -r --arg h "$hostname" '.workers[] | select(.hostname == $h) | .address' "$CONF")
  workers_users["$hostname"]=$(jq -r --arg h "$hostname" '.workers[] | select(.hostname == $h) | .user' "$CONF")
done

declare controllers_hostnames
declare -A controllers_addresses
declare -A controllers_users
declare -A controllers_passwords
for hostname in $(jq -r '.controllers[].hostname' "$CONF"); do
  controllers_hostnames+=("$hostname")
  controllers_addresses["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .address' "$CONF")
  controllers_users["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .user' "$CONF")
  controllers_passwords["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .sudoPassword' "$CONF")
done

main_controller_hostname=${controllers_hostnames[0]}
main_controller_address=${controllers_addresses["$main_controller_hostname"]}
main_controller_user=${controllers_users["$main_controller_hostname"]}

echo "Step 1: Generate and distribute certs"
echo "=========="
source "$GEN_CERTS_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 2: Generate and distribute auth configs"
echo "=========="
source "$GEN_CONFIGS_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 3: Generating and distributing encryption config"
echo "=========="
source "$GEN_ENCRYPTION_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 4: Bootstrap etcd"
echo "=========="
source "$BOOTSTRAP_ETCD_SCRIPT"
cd "$WORKDIR" || exit 1

echo "Step 5: Bootstrap controllers"
echo "=========="
source "$BOOTSTRAP_CONTROLLERS_SCRIPT"
cd "$WORKDIR" || exit 1

echo "$WORKDIR"
