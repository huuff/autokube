#!/usr/bin/env bash

CERT_C=$(jq -r '.certs.C' "$CONF")
CERT_L=$(jq -r '.certs.L' "$CONF")
CERT_OU=$(jq -r '.cluster.name' "$CONF")
declare -A workers
declare -A controllers
function gen_csr {
  cat <<EOF
{
  "CN": "$1",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$CERT_C",
      "L": "$CERT_L",
      "O": "$2",
      "OU": "${3:-CERT_OU}"
    } 
  ]
}
EOF
}

# Joins arguments with first argument as separator
# I use it for associative arrays as `join_by , "${FOO[@]}"`
function join_by {
  local IFS="$1"
  shift
  echo -n "$*"
}

echo "Step 0: Generating certs"
echo ">>> Generating CA certificate"
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [ "signing", "key encipherment", "server auth", "client auth" ],
        "expiry": "8760h"
      }
    }
  } 
}
EOF

gen_csr "Kubernetes" "Kubernetes" "CA" > ca-csr.json
cfssl gencert -loglevel=4 -initca ca-csr.json | cfssljson -bare ca

echo ">>> Generating admin client certificate"
gen_csr "admin" "system:masters" > admin-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

echo ">>> Generating kubelet client certificates"
for worker_hostname in "${!workers[@]}"; do
  worker_ip=${workers["$worker_hostname"]}
  echo ">>>>>> Generating for $worker_hostname:$worker_ip"
  gen_csr "system:node:$worker_hostname" "system:nodes" > "$worker_hostname-csr.json"
  cfssl gencert \
    -loglevel=4 \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname="$worker_hostname,$worker_ip" \
    -profile=kubernetes \
    "$worker_hostname-csr.json" | cfssljson -bare "$worker_hostname"
done

echo ">>> Generating the controller-manager client certificate"
gen_csr "system:kube-controller-manager" "system:kube-controller-manager" "$CERT_OU" > kube-controller-manager-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

echo ">>> Generating the kube-proxy client certificate"
gen_csr "system:kube-proxy" "system:node-proxier" > kube-proxy-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

echo ">>> Generating the scheduler client certificate"
gen_csr "system:kube-scheduler" "system:kube-scheduler" > kube-scheduler-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

echo ">>> Generating the apiserver certificate"
KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local
gen_csr "kubernetes" "Kubernetes" > kubernetes-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname="10.32.0.1,$(join_by , "${controllers[@]}"),127.0.0.1,$KUBERNETES_HOSTNAMES" \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

echo ">>> Generating the service account key pair"
gen_csr "service-accounts" "Kubernetes" > service-account-csr.json
cfssl gencert \
  -loglevel=4 \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account
ls
