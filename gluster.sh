#!/bin/bash

BASEDIR=$(dirname "$0")

function attach_datadisk () {
  VM=gluster$1
  DEVICE=$2
  SIZE=$3
  FILE=/data$1/gluster$1_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  virsh attach-disk $VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "pvcreate /dev/$DEVICE"
}

function attach_arbiterdisk () {
  VM=gluster$1
  DEVICE=$2
  SIZE=$3
  FILE=/vmpool/gluster$1_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  virsh attach-disk $VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "pvcreate /dev/$DEVICE"
}

function create_datanode () {
  IPADDR=10.88.20.$2

  # Create the virtual machine
  $BASEDIR/deploy-vm.sh gluster$1 1024 2 20G pw $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_datadisk $1 vdb 100G

  # Create a volume group
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "vgcreate vg0 /dev/vdb"

  # Create a logical volume
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "lvcreate -n lv0 -l 100%VG vg0"

  # Create a partition
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "echo ';' | sfdisk /dev/vg0/lv0"

  # Format the disk
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "mkfs.xfs /dev/vg0/lv0"

  # Create the data directory
  ansible gluster$1 -i $BASEDIR/inventory.yaml -m file --args='path=/data state=directory mode=0755'

  # Mount the data partition
  ansible gluster$1 -i $BASEDIR/inventory.yaml -m mount --args='path=/data src=/dev/vg0/lv0 fstype=xfs state=mounted'
}

function create_arbiternode () {
  IPADDR=10.88.20.$2

  # Create the virtual machine
  $BASEDIR/deploy-vm.sh gluster$1 1024 2 20G pw $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_arbiterdisk $1 vdb 10G

  # Create a volume group
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "vgcreate vg0 /dev/vdb"

  # Create a logical volume
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "lvcreate -n lv0 -l 100%VG vg0"

  # Create a partition
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "echo ';' | sfdisk /dev/vg0/lv0"

  # Format the disk
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "mkfs.xfs /dev/vg0/lv0"

  # Create the data directory
  ansible gluster$1 -i $BASEDIR/inventory.yaml -m file --args='path=/data state=directory mode=0755'

  # Mount the data partition
  ansible gluster$1 -i $BASEDIR/inventory.yaml -m mount --args='path=/data src=/dev/vg0/lv0 fstype=xfs state=mounted'  
}

function add_disk () {
  # Attach a new disk
  attach_datadisk $1 $2 100G

  # Add the new physical volume to the volume group
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "vgextend vg0 /dev/$2"

  # Add the new physical volume to the logical volume
  ansible gluster$1 -i $BASEDIR/inventory.yaml -a "lvextend /dev/vg0/lv0 /dev/$2 -r"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
exit
fi

if [ "$1" == "" ]; then
  echo "Deploys a GlusterFS based cluster"
  echo "Usage:"
  echo "  gluster.sh install"
  echo "  gluster.sh add-disk vd[c-z]"
  echo "  gluster.sh create-volume <namespace> <volname>"
  echo "  gluster.sh remove-volume <namespace> <volname>"
  echo "  gluster.sh remove"
fi

if [ "$1" == "install" ]; then
  # Create the arbiter node
  create_arbiternode 0 110

  # Create the first data node
  create_datanode 1 111

  # Create the second data node
  create_datanode 2 112

  # Add the Gluster nodes to the hosts file of each node
  ansible-playbook -i $BASEDIR/inventory.yaml $BASEDIR/gluster-hosts.yaml

  # Install the GlusterFS Cluster
  ansible-playbook -i $BASEDIR/inventory.yaml $BASEDIR/gluster-cluster.yaml
fi

if [ "$1" == "remove" ]; then
  virsh destroy gluster0
  virsh undefine gluster0

  virsh destroy gluster1
  virsh undefine gluster1
  rm /data1/gluster*

  virsh destroy gluster2
  virsh undefine gluster2
  rm /data2/gluster*

  rm /vmpool/gluster*
fi

if [ "$1" == "add-disk" ]; then
  add_disk 1 $2
  add_disk 2 $2
fi

if [ "$1" == "create-volume" ]; then
  NS=$2
  NAME=$3

  ansible gluster -i $BASEDIR/inventory.yaml -m file --args="path=/data/$NS/$NAME state=directory mode=0755"
  ansible gluster0 -i $BASEDIR/inventory.yaml -a "gluster volume create $NS-$NAME replica 2 arbiter 1 gluster1:/data/$NS/$NAME gluster2:/data/$NS/$NAME gluster0:/data/$NS/$NAME --mode=script"
  ansible gluster0 -i $BASEDIR/inventory.yaml -a "gluster volume start $NS-$NAME --mode=script"
fi

if [ "$1" == "remove-volume" ]; then
  NS=$2
  NAME=$3

  ansible gluster0 -i $BASEDIR/inventory.yaml -a "gluster volume stop $NS-$NAME --mode=script"
  ansible gluster0 -i $BASEDIR/inventory.yaml -a "gluster volume delete $NS-$NAME --mode=script"
  ansible gluster -i $BASEDIR/inventory.yaml -m file --args="path=/data/$NS/$NAME state=absent"
fi
