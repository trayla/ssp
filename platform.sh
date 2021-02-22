#!/bin/bash

BASEDIR=$(dirname "$0")
ACTION=$1
DATADEVICE1=$2
DATADEVICE2=$3

RED=`tput setaf 1`
GREEN=`tput setaf 2`
NC=`tput sgr0`

# Install Linux packages which are necessary to determine configuration parameters
apt install python3-pip -y && pip3 install pyyaml

IPPREFIX=`$BASEDIR/python/read-value-ipprefix.py`
ADMINPASSWORD=`$BASEDIR/python/read-value-adminpassword.py`
STORAGEWORKERSIZE=`$BASEDIR/python/read-value-storageworkersize.py`

SSP_PREFIX=ssp
CONSOLE_IPADDR=$IPPREFIX.2
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

function create_masternode() {
  # Create the Kubernetes master
  $BASEDIR/scripts/deploy-vm.sh kubemaster 4096 2 50G $ADMINPASSWORD $KUBEMASTER_IPADDR net-tools,openssh-server,aptitude,curl
  ssh-keygen -f "/root/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $KUBEMASTER_IPADDR
}

function create_datanode () {
  IPADDR=$IPPREFIX.$2

  # Create the virtual machine
  $BASEDIR/scripts/deploy-vm.sh kubenode$1 $WORKERSRAM $CPUS $STORAGEWORKERSIZE $ADMINPASSWORD $IPADDR net-tools,openssh-server,aptitude,curl

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible kubenode$1 -i $BASEDIR/python/get-ansible-inventory.py -a "apt install -y lvm2 xfsprogs software-properties-common open-iscsi nfs-common"

  # Attach the disk to the virtual machine
  echo "Attaching a disk $3 from the host to the virtual machine ..."
  virsh attach-disk ${SSP_PREFIX}_kubenode$1 --persistent $3 vdb
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

if [ "$ACTION" == "prepare" ]; then
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

elif [ "$ACTION" == "install" ]; then
  WORKERSRAM=`$BASEDIR/python/read-value-workersram.py`

  # Check if the passed data devices exist

  echo "Checking passed data devices $DATADEVICE2 and $DATADEVICE2 ..."

  if [ -e $DATADEVICE1 ]; then
    echo "${GREEN}$DATADEVICE1 exists ... ${GREEN}ok${NC}"
  else
    echo "${RED}$DATADEVICE1 does not exist ... ${RED}aborting${NC}"
    exit 0
  fi

  if [ -e $DATADEVICE2 ]; then
    echo "$DATADEVICE2 exists ... ${GREEN}ok${NC}"
  else
    echo "$DATADEVICE2 does not exist ... ${RED}aborting${NC}"
    exit 0
  fi

  # Check if the passed data devcies unused

  if [[ $(findmnt -rno SOURCE,TARGET "$DATADEVICE1") ]]; then
    echo "$DATADEVICE1 is currently in use ... ${RED}aborting${NC}"
    exit 0
  else
    echo "$DATADEVICE1 is not in use ... ${GREEN}ok${NC}"
  fi

  if [[ $(findmnt -rno SOURCE,TARGET "$DATADEVICE2") ]]; then
    echo "$DATADEVICE2 is currently in use ... ${RED}aborting${NC}"
    exit 0
  else
    echo "$DATADEVICE2 is not in use ... ${GREEN}ok${NC}"
  fi

  # Install some prerequisites
  write_title "Executing ansible/host-prerequisites.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prerequisites.yaml

  # Prepare the host especially with some basic
  write_title "Executing ansible/host-prepare.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prepare.yaml

  # Create the console machine
  write_title "Creating console"
  create_console

  # Create the master node
  write_title "Creating Kubernetes master node"
  create_masternode

  # Create the first data node
  write_title "Creating Kubernetes data node 1"
  create_datanode 1 11 $DATADEVICE1

  # Create the second data node
  write_title "Creating Kubernetes data node 2"
  create_datanode 2 12 $DATADEVICE2

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

  # Install the monitoring solution
  write_title "Executing ansible/kubernetes-monitoring.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-monitoring.yaml

  # Install the Ingress implementation
  write_title "Executing ansible/kubernetes-ingress.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-ingress.yaml

  # Define the host firewall
  write_title "Executing ansible/host-firewall.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-firewall.yaml

  # Create port forwarding rules into the Kubernetes cluster
  write_title "Executing ansible/kubernetes-firewall.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-firewall.yaml

  # Install the Docker Registry
  write_title "Executing ansible/kubernetes-dockerreg.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-dockerreg.yaml

  # Deploy custom namespaces
  write_title "Executing ansible/kubernetes-customns.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/kubernetes-customns.yaml

elif [ "$ACTION" == "remove" ]; then
  # Clean the host especially with the Hypervisor environment
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-cleanup.yaml
  rm /vmpool/${SSP_PREFIX}_*

else
  echo "Deploys a Kubernetes cluster"
  echo "Usage:"
  echo "  platform.sh prepare"
  echo "  platform.sh install"
  echo "  platform.sh remove"

fi
