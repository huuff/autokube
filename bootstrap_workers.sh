#!/usr/bin/env bash
# shellcheck disable=2029

declare workers_hostnames
declare -A workers_users
declare -A workers_addresses
declare -A workers_passwords

declare KUBERNETES_VERSION
CNI_PLUGINS_VERSION="v0.9.1"
CONTAINERD_VERSION="1.4.4"
RUNC_VERSION="v1.0.0-rc93"

# TODO: Make this configurable?
POD_CIDR="10.100.0.0/16"

function gen_cni_bridge_conf {
  FILENAME="10-bridge.conf"
  cat > "$FILENAME" <<EOF
{
    "cniVersion": "0.4.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
  echo -n "$FILENAME"
}

function gen_cni_loopback_conf {
  FILENAME="99-loopback.conf"
  cat > "$FILENAME" <<EOF
{
    "cniVersion": "0.4.0",
    "name": "lo",
    "type": "loopback"
}
EOF
  echo -n "$FILENAME"
}

function gen_containerd_conf {
  FILENAME="config.toml"
  cat > "$FILENAME" <<EOF
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
EOF
  echo -n "$FILENAME"
}

function gen_containerd_unit {
  FILENAME="containerd.service"
  cat > "$FILENAME" <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$FILENAME"
}

function gen_kubelet_conf {
  # $1 hostname
  FILENAME="kubelet-config.yaml"
  cat > "$FILENAME" <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "${POD_CIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/$1.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/$1-key.pem"
EOF
  echo -n "$FILENAME"
}

function gen_kubelet_unit {
  FILENAME="kubelet.service"
  cat > "$FILENAME" <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$FILENAME"
}

function gen_kube_proxy_conf {
  FILENAME="kube-proxy-config.yaml"
  cat > "$FILENAME" <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF
  echo -n "$FILENAME"
}

function gen_kube_proxy_unit {
  FILENAME="kube-proxy.service"
  cat > "$FILENAME" <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$FILENAME"
}

mkdir workers
cd workers || exit 1

CNI_BRIDGE_CONF=$(gen_cni_bridge_conf)
CNI_LOOPBACK_CONF=$(gen_cni_loopback_conf)
CONTAINERD_CONF=$(gen_containerd_conf)
CONTAINERD_UNIT=$(gen_containerd_unit)
KUBELET_UNIT=$(gen_kubelet_unit)
KUBE_PROXY_CONF=$(gen_kube_proxy_conf)
KUBE_PROXY_UNIT=$(gen_kube_proxy_unit)


# TODO: Cleanup binaries since they accummulate from run to run
for worker in "${workers_hostnames[@]}"; do
  echo ">>> Configuring $worker"
  address=${workers_addresses["$worker"]}
  user=${workers_users["$worker"]}
  password=${workers_passwords["$worker"]}
  ssh_target="${user}@${address}"
  kubelet_config=$(gen_kubelet_conf "$worker")

  echo ">>>>>> Removing any leftovers from previous installations"
  ssh -tt "$ssh_target" "\
    { sudo rm -rf /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes containerd || true; } \
      && { sudo systemctl stop containerd kubelet kube-proxy || true; } \
      && { sudo systemctl disable containerd kubelet kube-proxy || true; } \
      && { rm *.tgz *.tgz.* *.tar.gz *.tar.gz.* || true; }
  " <<< "$password"

  echo ">>>>>> Installing necessary packages and disabling swap"
  ssh -tt "$ssh_target" "\
    sudo apt-get update \
    && sudo apt-get -y install socat conntrack ipset \
    && sudo swapoff -a
  " <<< "$password"

  echo ">>>>>> Downloading binaries"
  ssh "$ssh_target" "\
    wget -nv --https-only \
      \"https://github.com/kubernetes-sigs/cri-tools/releases/download/$KUBERNETES_VERSION/crictl-$KUBERNETES_VERSION-linux-amd64.tar.gz\" \
      \"https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/runc.amd64\" \
      \"https://github.com/containernetworking/plugins/releases/download/$CNI_PLUGINS_VERSION/cni-plugins-linux-amd64-$CNI_PLUGINS_VERSION.tgz\" \
      \"https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-amd64.tar.gz\" \
      \"https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl\" \
      \"https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-proxy\" \
      \"https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kubelet\"
  "

  echo ">>>>>> Installing binaries"
  ssh -tt "$ssh_target" "\
    sudo mkdir -p /etc/cni/net.d /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes \
    && mkdir containerd \
    && tar -xf crictl-v1.21.0-linux-amd64.tar.gz \
    && tar -xf containerd-1.4.4-linux-amd64.tar.gz -C containerd \
    && sudo tar -xf cni-plugins-linux-amd64-v0.9.1.tgz -C /opt/cni/bin/ \
    && sudo mv runc.amd64 runc \
    && chmod +x crictl kubectl kube-proxy kubelet runc  \
    && sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/ \
    && sudo mv containerd/bin/* /bin/
  " <<< "$password"

  echo ">>>>>> Uploading all config"
  scp -q "$CNI_BRIDGE_CONF" "$CNI_LOOPBACK_CONF" "$CONTAINERD_CONF" "$CONTAINERD_UNIT" "$KUBELET_UNIT" "$KUBE_PROXY_CONF" "$KUBE_PROXY_UNIT" "$kubelet_config" "${ssh_target}:~/"

  echo ">>>>>> Setting all config"
  ssh -tt "$ssh_target" "\
    sudo mkdir -p /etc/containerd \
    && sudo cp \"$worker-key.pem\" \"$worker\".pem /var/lib/kubelet/ \
    && sudo cp \"$worker.kubeconfig\" /var/lib/kubelet/kubeconfig \
    && sudo cp ca.pem /var/lib/kubernetes/ \
    && sudo cp $CNI_BRIDGE_CONF /etc/cni/net.d/ \
    && sudo cp $CNI_LOOPBACK_CONF /etc/cni/net.d/ \
    && sudo cp $CONTAINERD_CONF /etc/containerd/ \
    && sudo cp $CONTAINERD_UNIT /etc/systemd/system/ \
    && sudo cp $kubelet_config /var/lib/kubelet/ \
    && sudo cp $KUBELET_UNIT /etc/systemd/system/ \
    && sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig \
    && sudo cp $KUBE_PROXY_CONF /var/lib/kube-proxy/ \
    && sudo cp $KUBE_PROXY_UNIT /etc/systemd/system/ 
  " <<< "$password"

  echo ">>>>>> Starting and enabling the services"
  ssh -tt "$ssh_target" "\
    sudo systemctl daemon-reload \
    && sudo systemctl enable containerd kubelet kube-proxy \
    && sudo systemctl start containerd kubelet kube-proxy
  " <<< "$password"
done

