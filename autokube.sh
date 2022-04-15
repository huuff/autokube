#!/usr/bin/env bash
set -euo pipefail
WORKDIR=$(mktemp -d)
CONF=$(realpath "$1")
cd "$WORKDIR" || exit 1

echo "Step 0: Generating certs"
CERT_C=$(jq -r '.certs.C' "$CONF")
CERT_L=$(jq -r '.certs.L' "$CONF")
CERT_O=$(jq -r '.certs.O' "$CONF")
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

cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$CERT_C",
      "L": "$CERT_L",
      "O": "$CERT_O",
      "OU": "CA"
    } 
  ]
}
EOF

cfssl gencert -loglevel=4 -initca ca-csr.json | cfssljson -bare ca

echo ">>> Generating admin client certificate"
