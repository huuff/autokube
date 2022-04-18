#!/usr/bin/env bash

declare workers_hostnames
declare -A workers_addresses
declare -A workers_users
declare -A workers_passwords
declare controllers_hostnames
declare -A controllers_addresses
declare -A controllers_users
declare -A controllers_passwords

function generate_hosts {
  EXTRA_HOSTS_FILE="extrahosts"
  for controller in "${controllers_hostnames[@]}"; do
    address=${controllers_addresses["$controller"]}
    echo "$address $controller" >> "$EXTRA_HOSTS_FILE"
  done
  for worker in "${workers_hostnames[@]}"; do
    address="${workers_addresses["$worker"]}"
    echo "$address $worker" >> "$EXTRA_HOSTS_FILE"
  done
  echo -n "$EXTRA_HOSTS_FILE"
}

mkdir -p cni
cd cni || exit 1

EXTRA_HOSTS_FILE=$(generate_hosts)

echo ">>> Distributing hosts file to all nodes"
# TODO: Both loops are the same, DRY, but bash is really unergonomic
for controller in "${controllers_hostnames[@]}"; do
  address=${controllers_addresses["$controller"]}
  user=${controllers_users["$controller"]}
  password=${controllers_passwords["$controller"]}
  ssh_target=${user}@${address}

  echo ">>>>>> Distributing hosts file to $controller"
  scp "$EXTRA_HOSTS_FILE" "$ssh_target:~/" 

  echo ">>>>>> Installing hosts file on $controller"
  ssh -tt "$ssh_target" "sudo sh -c 'cat $EXTRA_HOSTS_FILE >> /etc/hosts'" <<< "$password"
done

for worker in "${workers_hostnames[@]}"; do
  address=${workers_addresses["$worker"]}
  user=${workers_users["$worker"]}
  password=${workers_passwords["$worker"]}
  ssh_target=${user}@${address}

  echo ">>>>>> Distributing hosts file to $worker"
  scp "$EXTRA_HOSTS_FILE" "$ssh_target:~/" 

  echo ">>>>>> Installing hosts file on $worker"
  # Touching /etc/hosts just so sudo doesn't prompt for a password, so hacky
  ssh -tt "$ssh_target" "\
    sudo sh -c 'cat $EXTRA_HOSTS_FILE >> /etc/hosts'
  " <<< "$password"

  echo ">>>>>> Enabling packer forwarding in $worker"
  ssh -tt "$ssh_target" "sudo sysctl net.ipv4.conf.all.forwarding=1" <<< "$password"
done

# TODO: Using master is too nondeterministic
echo ">>> Applying flannel"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
