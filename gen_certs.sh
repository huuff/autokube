#!/usr/bin/env bash
# shellcheck disable=1090
# Generate certs for all components and distribute them to the servers

CERT_C=$(jq -r '.certs.C' "$CONF")
CERT_L=$(jq -r '.certs.L' "$CONF")
CERT_OU=$(jq -r '.cluster.name' "$CONF")
declare join_by
source "$join_by"
declare workers_hostnames
declare -A workers_addresses
declare -A workers_users
declare controllers_hostnames
declare -A controllers_addresses
declare -A controllers_users

mkdir certs
cd certs || exit 1
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
      "OU": "${3:-$CERT_OU}"
    } 
  ]
}
EOF
}

function csr_filename {
  echo "$1-csr.json"
}

function sign_csr {
  # $1: id of entity (hostname for nodes/masters, service name for services)
  # $2: hostname to be set in cert
  # TODO: DRY, I could pass an empty -hostname, but I don't know
  # what cfssl will do in that case, so I'm just being careful here
  if [ -z "$2" ] # empty or unset
  then
    cfssl gencert \
      -loglevel=4 \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=kubernetes \
      "$(csr_filename "$1")" | cfssljson -bare "$1"
  else
    cfssl gencert \
      -loglevel=4 \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname="$2" \
      -profile=kubernetes \
      "$(csr_filename "$1")" | cfssljson -bare "$1"
  fi
}

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
gen_csr "admin" "system:masters" > "$(csr_filename "admin")"
sign_csr "admin"

echo ">>> Generating kubelet client certificates"
for worker_hostname in "${workers_hostnames[@]}"; do
  echo ">>>>>> Generating for $worker_hostname"
  worker_address=${workers_addresses["$worker_hostname"]}
  gen_csr "system:node:$worker_hostname" "system:nodes" > "$(csr_filename "$worker_hostname")"
  sign_csr "$worker_hostname" "$worker_hostname,$worker_address"
done

echo ">>> Generating the controller-manager client certificate"
gen_csr "system:kube-controller-manager" "system:kube-controller-manager" > "$(csr_filename "kube-controller-manager")"
sign_csr "kube-controller-manager"

echo ">>> Generating the kube-proxy client certificate"
gen_csr "system:kube-proxy" "system:node-proxier" > "$(csr_filename "kube-proxy")"
sign_csr "kube-proxy"

echo ">>> Generating the scheduler client certificate"
gen_csr "system:kube-scheduler" "system:kube-scheduler" > "$(csr_filename "kube-scheduler")"
sign_csr "kube-scheduler"

echo ">>> Generating the apiserver certificate"
KUBERNETES_HOSTNAMES="10.32.0.1,$(join_by , "${controllers_addresses[@]}"),$(join_by , "${controllers_hostnames[@]}"),127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local"
gen_csr "kubernetes" "Kubernetes" > "$(csr_filename "kubernetes")"
sign_csr "kubernetes" "$KUBERNETES_HOSTNAMES"

echo ">>> Generating the service account key pair"
gen_csr "service-accounts" "Kubernetes" > "$(csr_filename "service-account")"
sign_csr "service-account"

echo ">>> Distributing all generated certs"
for worker in "${workers_hostnames[@]}"; do
  address="${workers_addresses["$worker"]}"
  user="${workers_users["$worker"]}"
  echo ">>>>>> Distributing for ${worker}:${address}"
  scp -q ca.pem "${worker}.pem" "${worker}-key.pem" "${user}@${address}:~/"
done

for controller in "${controllers_hostnames[@]}"; do
  address="${controllers_addresses["$controller"]}"
  user="${controllers_users["$controller"]}"
  echo ">>>>>> Distributing for ${controller}:${address}"
  scp -q ca.pem ca-key.pem kubernetes.pem kubernetes-key.pem service-account.pem service-account-key.pem "${user}@${address}:~/"
done
