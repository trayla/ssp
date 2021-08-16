#!/bin/bash

BASEDIR=$(dirname "$0")
ACTION=$1

RED=`tput setaf 1`
GREEN=`tput setaf 2`
NC=`tput sgr0`

# Install Linux packages which are necessary to determine configuration parameters
apt install python3-pip -y && pip3 install pyyaml

IPPREFIX=`$BASEDIR/python/read-value-ipprefix.py`
ADMINPASSWORD=`$BASEDIR/python/read-value-adminpassword.py`

SSP_PREFIX=ssp
CPUS=`grep -c processor /proc/cpuinfo`

function write_title() {
  echo
  printf "     *"; for ((i=0; i<${#1}; i++)); do printf "*"; done; printf "*"; echo
  printf "***** $1 "; for ((i=0; i<`tput cols` - ${#1} - 7; i++));do printf "*"; done; echo
  echo
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

elif [ "$ACTION" == "install" ]; then
  WORKERSRAM=`$BASEDIR/python/read-value-workersram.py`

  # Install some prerequisites
  write_title "Executing ansible/host-prerequisites.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prerequisites.yaml

  # Prepare the host especially with some basic
  write_title "Executing ansible/host-prepare.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-prepare.yaml

  # Define the host firewall
  write_title "Executing ansible/host-firewall.yaml"
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-firewall.yaml

  # Create the console machine
  write_title "Creating console"
  $BASEDIR/scripts/deploy-vm.sh console 2048 1 30G $ADMINPASSWORD $IPPREFIX 2 net-tools,openssh-server,aptitude,ansible,curl
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPPREFIX.2

elif [ "$ACTION" == "add-vm" ]; then
  NAME=$2
  IPADDR=$IPPREFIX.$3
  RAM=$4
  CPUS=$5
  STORAGESIZE=$6

  # Create the virtual machine
  $BASEDIR/scripts/deploy-vm.sh $2 $RAM $CPUS $STORAGESIZE $ADMINPASSWORD $IPPREFIX $IPADDR net-tools,openssh-server,aptitude,curl

  # Reset locally cached SSH keys for the new virtual machine
  ssh-keygen -f "/root/.ssh/known_hosts" -R $IPADDR
  ssh-keygen -f "/home/sysadm/.ssh/known_hosts" -R $IPADDR

  # Install the Logical Volume Manager (LVM)
  ansible $2 -i $BASEDIR/python/get-ansible-inventory.py -a "apt install -y lvm2 xfsprogs software-properties-common open-iscsi nfs-common"

elif [ "$ACTION" == "remove" ]; then
  # Clean the host especially with the Hypervisor environment
  ansible-playbook -i $BASEDIR/python/get-ansible-inventory.py $BASEDIR/ansible/host-cleanup.yaml
  rm /vmpool/${SSP_PREFIX}_*

else
  echo "Deploys a single server cluster"
  echo "Usage:"
  echo "  platform.sh prepare"
  echo "  platform.sh install"
  echo "  platform.sh add-vm <name> <ip-suffix:3-199> <ram:4096> <cpus:2> <storage:30G>"
  echo "  platform.sh remove"

fi
