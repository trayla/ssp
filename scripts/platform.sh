#!/bin/bash

BASEDIR=$(dirname "$0")

KUBEMASTER_IPADDR="10.88.20.109"

function attach_arbiterdisk () {
  VM=kubenode$1
  DEVICE=$2
  SIZE=$3
  FILE=/vmpool/kubenode$1_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  virsh attach-disk $VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "pvcreate /dev/$DEVICE"
}

function attach_datadisk () {
  VM=kubenode$1
  DEVICE=$2
  SIZE=$3
  FILE=/data$1/kubenode$1_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  virsh attach-disk $VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "pvcreate /dev/$DEVICE"
}

function create_datanode () {
  IPADDR=10.88.20.$2

  # Create the virtual machine
  $BASEDIR/deploy-vm.sh kubenode$1 4096 2 20G pw $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_datadisk $1 vdb 100G

  # Create a volume group
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "vgcreate vg0 /dev/vdb"

  # Create a logical volume
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "lvcreate -n lv0 -l 100%VG vg0"

  # Create a partition
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "echo ';' | sfdisk /dev/vg0/lv0"

  # Format the disk
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "mkfs.xfs /dev/vg0/lv0"

  # Create the data directory
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -m file --args='path=/data state=directory mode=0755'

  # Mount the data partition
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -m mount --args='path=/data src=/dev/vg0/lv0 fstype=xfs state=mounted'
}

function create_arbiternode () {
  IPADDR=10.88.20.$2

  # Create the virtual machine
  $BASEDIR/../scripts/deploy-vm.sh kubenode$1 1024 2 20G pw $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_arbiterdisk $1 vdb 10G

  # Create a volume group
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "vgcreate vg0 /dev/vdb"

  # Create a logical volume
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "lvcreate -n lv0 -l 100%VG vg0"

  # Create a partition
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "echo ';' | sfdisk /dev/vg0/lv0"

  # Format the disk
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "mkfs.xfs /dev/vg0/lv0"

  # Create the data directory
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -m file --args='path=/data state=directory mode=0755'

  # Mount the data partition
  # ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -m mount --args='path=/data src=/dev/vg0/lv0 fstype=xfs state=mounted'
}

function add_disk () {
  # Attach a new disk
  attach_datadisk $1 $2 100G

  # Add the new physical volume to the volume group
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "vgextend vg0 /dev/$2"

  # Add the new physical volume to the logical volume
  ansible kubenode$1 -i $BASEDIR/../ansible/inventory.yaml -a "lvextend /dev/vg0/lv0 /dev/$2 -r"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

if [ "$1" == "install" ]; then
  # Create the Kubernetes master
  $BASEDIR/../scripts/deploy-vm.sh kubemaster 2048 4 20G pw $KUBEMASTER_IPADDR
  ssh-keygen -f "/root/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $KUBEMASTER_IPADDR

  # Create the arbiter node
  create_arbiternode 0 110

  # Create the first data node
  create_datanode 1 111

  # Create the second data node
  create_datanode 2 112

  # Add the nodes to the hosts file of each node
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-hosts.yaml

  # Prepare all nodes with a basic install like Docker
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-base.yaml

  # Install the master node
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-master.yaml

  # Install the worker nodes
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-nodes.yaml

  # Install the Kubernetes management along with Docker on the host
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-mgmt.yaml

  # Install the GlusterFS Cluster
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-gluster.yaml

  # Install Heketi, the storage API for GlusterFS
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-heketi.yaml

  # Install the Ingress based on NGINX
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-nginx.yaml

  # Install the monitoring solution
  ansible-playbook -i $BASEDIR/../ansible/inventory.yaml $BASEDIR/../ansible/kubernetes-monitoring.yaml

elif [ "$1" == "remove" ]; then
  virsh destroy kubemaster
  virsh undefine kubemaster

  virsh destroy kubenode0
  virsh undefine kubenode0

  virsh destroy kubenode1
  virsh undefine kubenode1

  virsh destroy kubenode2
  virsh undefine kubenode2

  rm /vmpool/kube*
  rm /data1/kube*
  rm /data2/kube*

elif [ "$1" == "add-disk" ]; then
  add_disk 1 $2
  add_disk 2 $2

elif [ "$1" == "create-volume" ]; then
  NS=$2
  NAME=$3

  ansible kubenodes -i $BASEDIR/../ansible/inventory.yaml -m file --args="path=/data/$NS/$NAME state=directory mode=0755"
  ansible kubenode0 -i $BASEDIR/../ansible/inventory.yaml -a "gluster volume create $NS-$NAME replica 2 arbiter 1 kubenode1:/data/$NS/$NAME kubenode2:/data/$NS/$NAME kubenode0:/data/$NS/$NAME --mode=script"
  ansible kubenode0 -i $BASEDIR/../ansible/inventory.yaml -a "gluster volume start $NS-$NAME --mode=script"

elif [ "$1" == "remove-volume" ]; then
  NS=$2
  NAME=$3

  ansible kubenode0 -i $BASEDIR/../ansible/inventory.yaml -a "gluster volume stop $NS-$NAME --mode=script"
  ansible kubenode0 -i $BASEDIR/../ansible/inventory.yaml -a "gluster volume delete $NS-$NAME --mode=script"
  ansible kubenodes -i $BASEDIR/../ansible/inventory.yaml -m file --args="path=/data/$NS/$NAME state=absent"

else
  echo "Deploys a Kubernetes cluster"
  echo "Usage:"
  echo "  kubernetes.sh install"
  echo "  kubernetes.sh add-disk vd[c-z]"
  echo "  kubernetes.sh create-volume <namespace> <volname>"
  echo "  kubernetes.sh remove-volume <namespace> <volname>"
  echo "  kubernetes.sh remove"
fi
