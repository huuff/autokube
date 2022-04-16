#!/usr/bin/env bash
declare controllers_hostnames
declare -A controllers_users
declare -A controllers_addresses

echo ">>> Generating encryption config"
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

echo ">>> Distributing encryption to controller"
for controller in "${controllers_hostnames[@]}"; do
  echo ">>>>>> Distributing to $controller"
  user=${controllers_users["$controller"]}
  address=${controllers_addresses["$controller"]}
  scp -q encryption-config.yaml "${user}@${address}:~/"
done
