#!/usr/bin/env bash
set -euo pipefail
CONF=$(realpath "$1")
CERT_C=$(jq -r '.certs.C' "$CONF")
CERT_L=$(jq -r '.certs.L' "$CONF")
WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

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
      "OU": "$3"
    } 
  ]
}
EOF
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

gen_csr Kubernetes Kubernetes CA > ca-csr.json
cfssl gencert -loglevel=4 -initca ca-csr.json | cfssljson -bare ca

echo ">>> Generating admin client certificate"
