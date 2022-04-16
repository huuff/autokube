#!/usr/bin/env bash

declare controllers_hostnames
declare -A controllers_users
declare -A controllers_addresses
declare -A controllers_passwords

KUBERNETES_VERSION="v1.21.0"

mkdir controllers
cd controllers || exit 1

echo ">>> Preparing kubernetes binaries"
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl

for controller in "${controllers_hostnames[@]}"; do
  address=${controllers_addresses["$controller"]}
  user=${controllers_users["$controller"]}
  password=${controllers_passwords["$controller"]}
  
done
