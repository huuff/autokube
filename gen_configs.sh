#!/usr/bin/env bash
declare CLUSTER_ID
declare workers_hostnames
declare -A workers_addresses
declare -A workers_users
declare controllers_hostnames
declare -A controllers_addresses
declare -A controllers_users

# TODO: Is this ok? surely not, addresses of other controllers
# must be valid, not only the first one
API_ADDRESS="${controllers_addresses[${controllers_hostnames[0]}]}"

mkdir config
cd config || exit 1

function gen_config {
  # $1: identifier of the entity (i.e. hostname for nodes/masters or service names for service)
  # $2: user identifier
  # $3: server address, or API_ADDRESS by default
  kubectl config set-cluster "$CLUSTER_ID" \
    --certificate-authority=../certs/ca.pem \
    --embed-certs=true \
    --server="https://${3:-$API_ADDRESS}:6443" \
    --kubeconfig="$1.kubeconfig" > /dev/null

  kubectl config set-credentials "$2" \
    --client-certificate="../certs/$1.pem" \
    --client-key="../certs/$1-key.pem" \
    --embed-certs=true \
    --kubeconfig="$1.kubeconfig" > /dev/null

  kubectl config set-context default \
    --cluster="$CLUSTER_ID" \
    --user="$2" \
    --kubeconfig="$1.kubeconfig" > /dev/null

  kubectl config use-context default --kubeconfig="$1.kubeconfig" > /dev/null
}

echo ">>> Generating worker auth configs"
for worker in "${workers_hostnames[@]}"; do
  echo ">>>>>> Generating config for ${worker}"
  gen_config "$worker" "system:node:$worker"
done

echo ">>> Generating kube-proxy auth config"
gen_config "kube-proxy" "system:kube-proxy"

echo ">>> Generating kube-controller-manager auth config"
gen_config "kube-controller-manager" "system:kube-controller-manager" "127.0.0.1"

echo ">>> Generating kube-scheduler auth config"
gen_config "kube-scheduler" "system:kube-scheduler" "127.0.0.1"

echo ">>> Generating admin auth config"
gen_config "admin" "admin" "127.0.0.1"

# TODO: Distribute the configs!
ls
