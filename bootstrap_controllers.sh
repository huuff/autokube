#!/usr/bin/env bash
# shellcheck disable=1090

declare controllers_hostnames
declare -A controllers_users
declare -A controllers_addresses
declare -A controllers_passwords

declare main_controller_address
declare main_controller_user

declare join_by
source "$join_by"

declare KUBERNETES_VERSION
# TODO: Should this be the IP of the load balancer in front of the controllers?
KUBERNETES_PUBLIC_ADDRESS="$main_controller_address"


function gen_apiserver_unit {
  # $1 controller hostname
  # $2 controller ip

  declare ETCD_SERVERS
  for hostname in "${controllers_hostnames[@]}"; do
    ETCD_SERVERS+=("https://${controllers_addresses["$hostname"]}:2379") 
  done
  ETCD_SERVERS_STRING=$(join_by , "${ETCD_SERVERS[@]}")
  UNIT_FILE="kube-apiserver.$1.service"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=$2 \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=${ETCD_SERVERS_STRING} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$UNIT_FILE"
}

function gen_controller_manager_unit {
  # $1 hostname
  UNIT_FILE="kube-controller-manager.service"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$UNIT_FILE"
}

function gen_scheduler_config {
  CONFIG_FILE="kube-scheduler.yaml"
  cat > "$CONFIG_FILE" <<EOF
apiVersion: kubescheduler.config.k8s.io/v1beta1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
  echo -n "$CONFIG_FILE"
}

function gen_scheduler_unit {
  UNIT_FILE="kube-scheduler.service"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo -n "$UNIT_FILE"
}

mkdir controllers
cd controllers || exit 1

echo ">>> Downloading kubernetes binaries"
wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/$KUBERNETES_VERSION/bin/linux/amd64/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl

echo ">>> Generating configs and systemd units"
controller_manager_unit=$(gen_controller_manager_unit)
scheduler_config=$(gen_scheduler_config)
scheduler_unit=$(gen_scheduler_unit)

for controller in "${controllers_hostnames[@]}"; do
  address=${controllers_addresses["$controller"]}
  user=${controllers_users["$controller"]}
  password=${controllers_passwords["$controller"]}
  ssh_target="${user}@${address}"
  apiserver_unit=$(gen_apiserver_unit "$controller" "$address")

  echo ">>>>>> Removing any controller leftovers from previous installations"
  ssh -tt "$ssh_target" "\
    { sudo rm -rf /etc/kubernetes || true; } \
    && { sudo rm -rf /var/lib/kubernetes || true; } \
    && { sudo rm /etc/systemd/system/{kube-controller-manager,kube-scheduler,kube-apiserver}.service || true; } \
    && { sudo systemctl disable kube-controller-manager kube-scheduler kube-apiserver || true; } \\
    && { sudo systemctl stop kube-controller-manager kube-scheduler kube-apiserver || true; }
  " <<< "$password"
 
  echo ">>>>>> Uploading to $controller"
  scp kube-apiserver kube-controller-manager kube-scheduler kubectl "${ssh_target}:~/"
  scp "$apiserver_unit" "${ssh_target}:~/kube-apiserver.service"
  scp "$controller_manager_unit" "${ssh_target}:~/"
  scp "$scheduler_config" "${ssh_target}:~/"
  scp "$scheduler_unit" "${ssh_target}:~/"
  echo ">>>>>> Configuring $controller"
  ssh -tt "$ssh_target" "\
    sudo mkdir -p /etc/kubernetes/config \
    && sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin \
    && sudo mv kube-apiserver.service /etc/systemd/system/ \
    && sudo mkdir -p /var/lib/kubernetes \
    && sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes \
    && sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes \
    && sudo mv kube-controller-manager.service /etc/systemd/system/ \
    && sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes \
    && sudo mv \"$scheduler_config\" /etc/kubernetes/config \
    && sudo mv \"$scheduler_unit\" /etc/systemd/system/kube-scheduler.service \
    && sudo systemctl daemon-reload \
    && sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler \
    && sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler 
  " <<< "$password"
done

echo ">>> Configuring RBAC permissions for the Kubelet API"
ssh_target="${main_controller_user}@${main_controller_address}"

cat > kube-apiserver-to-kubelet-role.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*" 
EOF

cat > kube-apiserver-to-kubelet-binding.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

sleep 10
scp -q kube-apiserver-to-kubelet-{role,binding}.yaml "${ssh_target}:~/"
ssh "${ssh_target}" "\
  kubectl --kubeconfig admin.kubeconfig apply -f kube-apiserver-to-kubelet-role.yaml \
  && kubectl --kubeconfig admin.kubeconfig apply -f kube-apiserver-to-kubelet-binding.yaml
"
