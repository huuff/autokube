#!/usr/bin/env bash
# shellcheck disable=2029,2087,1090

# TODO: Create a new dir and cd into it

declare join_by
source "$join_by"
declare controllers_hostnames
declare -A controllers_users
declare -A controllers_addresses
declare -A controllers_passwords

function cluster_addresses {
  declare CLUSTER_ADDRESSES
  for controller in "${controllers_hostnames[@]}"; do
    address=${controllers_addresses["$controller"]}
    CLUSTER_ADDRESSES+=("$controller=https://$address:2380")
  done
  join_by , "${CLUSTER_ADDRESSES[@]}"
}

function gen_etcd_unit {
  # $1 hostname
  # $2 address
  FILENAME="$1.etcd.service"
  cat > "$FILENAME" <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name $1 \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://$2:2380 \\
  --listen-peer-urls https://$2:2380 \\
  --listen-client-urls https://$2:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://$2:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster $(cluster_addresses) \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$FILENAME"
}

mkdir etcd
cd etcd || exit 1

ETCD_VERSION="v3.4.15"
ETCD_PATH="etcd-$ETCD_VERSION-linux-amd64"
ETCD_FILENAME="$ETCD_PATH.tar.gz"
echo ">>> Downloading etcd $ETCD_VERSION"
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/$ETCD_VERSION/$ETCD_FILENAME"

for controller in "${controllers_hostnames[@]}"; do
  echo ">>>>>> Bootstrapping etcd in $controller"
  user=${controllers_users["$controller"]}
  address=${controllers_addresses["$controller"]}
  password=${controllers_passwords["$controller"]}
  etcd_unit=$(gen_etcd_unit "$controller" "$address")
  ssh_target="${user}@${address}"

  echo ">>>>>>>>> Uploading etcd"
  scp "$ETCD_FILENAME" "${ssh_target}:~/"
  scp "$etcd_unit" "${ssh_target}:~/"
  echo ">>>>>>>>> Removing any etcd leftovers from previous installations"
  ssh -tt "$ssh_target" "\
    { sudo rm -rf /etc/etcd /var/lib/etcd || true; } \
    && { sudo systemctl disable etcd || true; } \
    && { sudo systemctl stop etcd || true; }
  " <<< "$password"
  echo ">>>>>>>>> Starting etcd"
  ssh "$ssh_target" "tar -xf $ETCD_FILENAME"
  ssh -tt "$ssh_target" "\
    sudo cp $ETCD_PATH/etcd* /usr/local/bin \
    && sudo mkdir -p /etc/etcd /var/lib/etcd \
    && sudo chmod 700 /var/lib/etcd \
    && sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd \
    && sudo cp \"$etcd_unit\" /etc/systemd/system/etcd.service \
    && sudo systemctl daemon-reload \
    && sudo systemctl enable etcd \
    && sudo systemctl start etcd \
    && sudo ETCDCTL_API=3 etcdctl member list \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/etcd/ca.pem \
        --cert=/etc/etcd/kubernetes.pem \
        --key=/etc/etcd/kubernetes-key.pem
  " <<< "$password"
done
