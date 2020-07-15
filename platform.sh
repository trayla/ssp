#!/bin/bash

BASEDIR=$(dirname "$0")

# Install Linux packages which are necessary to determine configuration parameters
apt install python3-pip -y && pip3 install pyyaml

IPPREFIX=`$BASEDIR/python/read-value-ipprefix.py`
ADMINPASSWORD=`$BASEDIR/python/read-value-adminpassword.py`
STORAGEDATASIZE=`$BASEDIR/python/read-value-storagedatasize.py`

SSP_PREFIX=ssp
CONSOLE_IPADDR=$IPPREFIX.2
HEKETI_IPADDR=$IPPREFIX.9
KUBEMASTER_IPADDR=$IPPREFIX.10
CPUS=`grep -c processor /proc/cpuinfo`

function write_title() {
  echo
  printf "     *"; for ((i=0; i<${#1}; i++)); do printf "*"; done; printf "*"; echo
  printf "***** $1 "; for ((i=0; i<`tput cols` - ${#1} - 7; i++));do printf "*"; done; echo
  echo
}

function create_console() {
  # Create the console machine
  $BASEDIR/scripts/deploy-vm.sh console 4096 2 50G $ADMINPASSWORD $CONSOLE_IPADDR net-tools,openssh-server,aptitude,ansible,curl
  ssh-keygen -f "/root/.ssh/known_hosts" -R $CONSOLE_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $CONSOLE_IPADDR
}

function create_heketi() {
  # Create the Heketi machine
  $BASEDIR/scripts/deploy-vm.sh heketi 1024 1 20G $ADMINPASSWORD $HEKETI_IPADDR net-tools,openssh-server,aptitude,curl
  ssh-keygen -f "/root/.ssh/known_hosts" -R $HEKETI_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $HEKETI_IPADDR
}

function create_masternode() {
  # Create the Kubernetes master
  $BASEDIR/scripts/deploy-vm.sh kubemaster 2048 2 20G $ADMINPASSWORD $KUBEMASTER_IPADDR net-tools,openssh-server,aptitude,curl
  ssh-keygen -f "/root/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
}

function attach_datadisk () {
  VM=kubenode$1
  DEVICE=$2
  SIZE=$3
  FILE=/data/data$1/${SSP_PREFIX}_${VM}_$2.qcow2

  if [ -f $FILE ]; then
    echo "Disk image $FILE already exists!"
    exit 1
  fi

  # Create some data disks
  echo 'Create a disk image ...'
  qemu-img create -f qcow2 $FILE $SIZE

  # Attach the disk to the virtual machine
  echo 'Attaching the newly created disk to the virtual machine ...'
  virsh attach-disk ${SSP_PREFIX}_$VM --source $FILE --target $DEVICE --persistent --subdriver qcow2

  # Create a physical volume for the newly attached disk
  echo 'Create a physical volume on the newly created disk ...'
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "pvcreate /dev/$DEVICE"
}

function create_datanode () {
  IPADDR=$IPPREFIX.$2

  # Create the virtual machine
  $BASEDIR/scripts/deploy-vm.sh kubenode$1 $WORKERSRAM $CPUS 30G $ADMINPASSWORD $IPADDR net-tools,openssh-server,aptitude,curl

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "apt install -y lvm2 xfsprogs software-properties-common"

  # Attach the first data disks
  attach_datadisk $1 vdb $STORAGEDATASIZE

  # Create the data volume group
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "vgcreate vgdata /dev/vdb"

  # Create the data logical volume
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "lvcreate -n lvdata -l 100%FREE vgdata"
}

function add_disk () {
  # Attach a new disk
  attach_datadisk $1 $2 100G

  # Add the new physical volume to the data volume group
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "vgextend vgdata /dev/$2"

  # Resize the logical data volume to the maximum available space
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "lvextend -l +100%FREE /dev/vgdata/lvdata"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

if [ "$1" == "prepare" ]; then
   # Install aptitude which is necessary for Ansible
  apt install aptitude python3-pip -y

  # Install Python packages
  pip install pyyaml

  # Install Ansible
  apt install ansible -y

  # Create SSH key pair for the root user
  ssh-keygen -f /root/.ssh/id_rsa -N ""
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

  # Create SSH key pair for the sysadm user
  mkdir -p /home/sysadm/.ssh
  ssh-keygen -f /home/sysadm/.ssh/id_rsa -N ""
  chown -R sysadm:sysadm /home/sysadm/.ssh

elif [ "$1" == "install" ]; then
  WORKERSRAM=`$BASEDIR/python/read-value-workersram.py`

  # Install some prerequisites
  write_title "Executing ansible/host-prerequisites.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prerequisites.yaml

  # Clean the host especially with the Hypervisor environment
  write_title "Executing ansible/host-cleanup.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-cleanup.yaml
  rm /vmpool/${SSP_PREFIX}_*
  rm /data/data1/${SSP_PREFIX}_*
  rm /data/data2/${SSP_PREFIX}_*

  # Prepare the host especially with some basic
  write_title "Executing ansible/host-prepare.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prepare.yaml

  # Create the console machine
  write_title "Creating console"
  create_console

  # Create the Heketi machine
  write_title "Creating Heketi"
  create_heketi

  # Create the master node
  write_title "Creating Kubernetes master node"
  create_masternode

  # Create the first data node
  write_title "Creating Kubernetes data node 1"
  create_datanode 1 11

  # Create the second data node
  write_title "Creating Kubernetes data node 2"
  create_datanode 2 12

  # Add the nodes to the hosts file of each virtual machine
  write_title "Executing ansible/hosts.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/hosts.yaml

  # Install Docker on each virtual machine
  write_title "Executing ansible/docker.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/docker.yaml

  # Prepare all Kubernetes nodes with a basic installation
  write_title "Executing ansible/kubernetes-prepare.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-prepare.yaml

  # Install the Kubernetes management
  write_title "Executing ansible/kubernetes-management.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-management.yaml

  # Install the worker nodes
  write_title "Executing ansible/kubernetes-nodes.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-nodes.yaml

  # Install the base components
  write_title "Executing ansible/kubernetes-base.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-base.yaml

  # Install the storage components
  write_title "Executing ansible/kubernetes-storage.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-storage.yaml

  # Install the Ingress based on Nginx
  write_title "Executing ansible/kubernetes-nginx.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-nginx.yaml

  # Define the host firewall
  write_title "Executing ansible/host-firewall.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-firewall.yaml

  # Create port forwarding rules into the Kubernetes cluster
  write_title "Executing ansible/kubernetes-firewall.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-firewall.yaml

  # Install the monitoring solution
  write_title "Executing ansible/kubernetes-monitoring.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-monitoring.yaml

  # Install the Docker Registry
  write_title "Executing ansible/kubernetes-dockerreg.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-dockerreg.yaml

  # Deploy custom namespaces
  write_title "Executing ansible/kubernetes-customns.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-customns.yaml

  # Deploy the Stash backup
  write_title "Executing ansible/kubernetes-backup.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-backup.yaml

  # Deploy the database management KubeDB
  write_title "Executing ansible/kubernetes-kubedb.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-kubedb.yaml

elif [ "$1" == "remove" ]; then
  # Clean the host especially with the Hypervisor environment
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-cleanup.yaml
  rm /vmpool/${SSP_PREFIX}_*
  rm /data/data1/${SSP_PREFIX}_*
  rm /data/data2/${SSP_PREFIX}_*

elif [ "$1" == "add-disk" ]; then
  add_disk 1 $2
  add_disk 2 $2

else
  echo "Deploys a Kubernetes cluster"
  echo "Usage:"
  echo "  platform.sh prepare"
  echo "  platform.sh install"
  echo "  platform.sh add-disk vd[e-z]"
  echo "  platform.sh remove"

fi
