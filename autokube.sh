#!/usr/bin/env bash
set -euo pipefail
set -- "${1:-./sample-cluster.json}"
GEN_CERTS_SCRIPT=$(realpath ./gen_certs.sh)
CONF=$(realpath "$1")

WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

declare -A workers
for hostname in $(jq -r '.workers[].hostname' "$CONF"); do
  workers["$hostname"]=$(jq -r --arg h "$hostname" '.workers[] | select(.hostname == $h) | .address' "$CONF")
done

declare -A controllers
for hostname in $(jq -r '.controllers[].hostname' "$CONF"); do
  controllers["$hostname"]=$(jq -r --arg h "$hostname" '.controllers[] | select(.hostname == $h) | .address' "$CONF")
done

# shellcheck disable=1090,1091
source "$GEN_CERTS_SCRIPT"
