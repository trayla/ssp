#!/bin/bash

BASEDIR=$(dirname "$0")

KUBEMASTER_IPADDR="10.88.20.120"

function create_node () {
  IPADDR=10.88.20.$2

  # Create the virtual machine
  $BASEDIR/deploy-vm.sh kubenode$1 4096 4 20G pw $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

if [ "$1" == "" ]; then
  echo "Deploys a Kubernetes cluster"
  echo "Usage:"
  echo "  kubernetes.sh install"
  echo "  kubernetes.sh remove"
fi

if [ "$1" == "install" ]; then
  # Create the Kubernetes master
  $BASEDIR/deploy-vm.sh kubemaster 4096 4 20G pw $KUBEMASTER_IPADDR
  ssh-keygen -f "/root/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $KUBEMASTER_IPADDR

  # Create the first cluster node
  create_node 1 121

  # Create the second cluster node
  create_node 2 122

  # Prepare all nodes with a basic install like Docker
  ansible-playbook -i $BASEDIR/inventory.yaml $BASEDIR/kubernetes-base.yaml

  # Install the master node
  ansible-playbook -i $BASEDIR/inventory.yaml $BASEDIR/kubernetes-master.yaml

  # Install the worker nodes
  ansible-playbook -i $BASEDIR/inventory.yaml $BASEDIR/kubernetes-nodes.yaml
fi

if [ "$1" == "remove" ]; then
  virsh destroy kubemaster
  virsh undefine kubemaster

  virsh destroy kubenode1
  virsh undefine kubenode1

  virsh destroy kubenode2
  virsh undefine kubenode2

  rm /vmpool/kube*
fi
