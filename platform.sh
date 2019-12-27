#!/bin/bash

BASEDIR=$(dirname "$0")

IPPREFIX=`$BASEDIR/python/read-value-ipprefix.py`
ADMINPASSWORD=`$BASEDIR/python/read-value-adminpassword.py`

KUBEMASTER_IPADDR=$IPPREFIX.110

function attach_datadisk () {
  VM=kubenode$1
  DEVICE=$2
  SIZE=$3
  FILE=/data/data$1/kubenode$1_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  echo 'Create a disk image ...'
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  echo 'Attaching the newly created disk to the virtual machine ...'
  virsh attach-disk $VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  echo 'Create a physical volume on the newly created disk ...'
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "pvcreate /dev/$DEVICE"
}

function create_datanode () {
  IPADDR=$IPPREFIX.$2

  # Create the virtual machine
  $BASEDIR/scripts/deploy-vm.sh kubenode$1 $WORKERSRAM 4 30G $ADMINPASSWORD $IPADDR

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_datadisk $1 vdb 200G
  attach_datadisk $1 vdc 200G
  attach_datadisk $1 vdd 200G
  attach_datadisk $1 vde 200G
}

function add_disk () {
  # Attach a new disk
  attach_datadisk $1 $2 100G

  # Add the new physical volume to the volume group
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "vgextend vg0 /dev/$2"

  # Add the new physical volume to the logical volume
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "lvextend /dev/vg0/lv0 /dev/$2 -r"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

if [ "$1" == "prepare" ]; then
   # Install aptitude which is necessary for Ansible
  apt install aptitude python-pip -y

  # Install Python packages
  pip install pyyaml

  # Install the latest version of Ansible from the PPA repository
  apt-add-repository ppa:ansible/ansible
  apt update
  apt install ansible -y

  # Create SSH key pair for the root user
  ssh-keygen -f /root/.ssh/id_rsa -N ""
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

  # Create SSH key pair for the sysadm user
  mkdir -p /home/sysadm/.ssh
  ssh-keygen -f /home/sysadm/.ssh/id_rsa -N ""
  chown -R sysadm:sysadm /home/sysadm/.ssh

  # Create the LVM
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prepare.yaml

elif [ "$1" == "install" ]; then
  WORKERSRAM=`$BASEDIR/python/read-value-workersram.py`

  # Create the Kubernetes master
  $BASEDIR/scripts/deploy-vm.sh kubemaster 2048 4 20G $ADMINPASSWORD $KUBEMASTER_IPADDR
  ssh-keygen -f "/root/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $KUBEMASTER_IPADDR

  # Create the first data node
  create_datanode 1 111

  # Create the second data node
  create_datanode 2 112

  # Add the nodes to the hosts file of each node
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-hosts.yaml

  # Prepare all nodes with a basic install like Docker
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-prepare.yaml

  # Install the master node
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-master.yaml

  # Install the worker nodes
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-nodes.yaml

  # Install the base components
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-base.yaml

  # Install the GlusterFS Cluster
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-gluster.yaml

  # Install Heketi, the storage API for GlusterFS
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-heketi.yaml

  # Install the Ingress based on Nginx
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-nginx.yaml

  # Install the monitoring solution
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-monitoring.yaml

  # Install Weave
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-weave.yaml

  # Install the Docker Registry
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-dockerreg.yaml

  # Deploy custom namespaces
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-customns.yaml

  # Deploy the Stash backup
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/kubernetes/stash/pb-install.yaml

  reboot

elif [ "$1" == "remove" ]; then
  virsh destroy kubemaster
  virsh undefine kubemaster

  virsh destroy kubenode1
  virsh undefine kubenode1

  virsh destroy kubenode2
  virsh undefine kubenode2

  rm /vmpool/kube*
  rm /data/data1/kube*
  rm /data/data2/kube*

  reboot

elif [ "$1" == "add-disk" ]; then
  add_disk 1 $2
  add_disk 2 $2

else
  echo "Deploys a Kubernetes cluster"
  echo "Usage:"
  echo "  platform.sh prepare"
  echo "  platform.sh install"
  echo "  platform.sh add-disk vd[c-z]"
  echo "  platform.sh remove"
fi
