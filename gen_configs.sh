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

echo ">>> Generating worker auth configs"
for worker in "${workers_hostnames[@]}"; do
  echo ">>>>>> Generating config for ${worker}"
  kubectl config set-cluster "$CLUSTER_ID" \
    --certificate-authority=../certs/ca.pem \
    --embed-certs=true \
    --server="https://${API_ADDRESS}:6443" \
    --kubeconfig="${worker}.kubeconfig" > /dev/null

  kubectl config set-credentials "system:node:$worker" \
    --client-certificate="../certs/${worker}.pem" \
    --client-key="../certs/${worker}-key.pem" \
    --embed-certs=true \
    --kubeconfig="${worker}.kubeconfig" > /dev/null

  kubectl config set-context default \
    --cluster="$CLUSTER_ID" \
    --user="system:node:$worker" \
    --kubeconfig="${worker}.kubeconfig" > /dev/null
done

echo ">>> Generating kube-config auth config"

ls
