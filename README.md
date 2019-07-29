# Single Server Platform - Base

### CAUTION: This repository is still in progress! Do not use it right now!

## Prerequisits

### Hardware requirements

- A running bare metal machine with a plain Ubuntu 18.04 Server installation and root access (virtual machines are not supported)
- Minimum 8 GB RAM (16 GB recommended) 
- Minimum 100 GB storage (250 GB recommended)

### Knowledge

- A understanding of Linux based system management and command line tools
- A understanding of virtualization with KVM
- Knowledge about operating a Kubernetes platform
- A basic understanding about Gluster

### Necessary preliminaries

#### Storage

Your system has to provide three directories which will be used as KVM storage pools and therefore populated with disk images for the upcoming virtual machines. The following directories hav to be create prior to the start of the installation procedure:

#### Basic Linux packages

Install necessary Ubuntu packages
~~~~
apt install -y \
  xfsprogs \
  bridge-utils sysstat apt-transport-https ca-certificates curl software-properties-common \
  qemu-kvm libvirt-clients libvirt-daemon-system virt-manager
~~~~

##### /vmpool

This directory is going to be used as the default storage pool for the KVM environment. It is recommended to provide here a redundant disk array, but according to your needs you are free here.

The minimum is to create just the directory like this:
~~~~
mkdir -p /vmpool
~~~~

##### /data1 and /data2

These directories are going to be used as redundancy nodes for the storage cluster and should be on sperate storage disks. Using a high available disk setup like RAID 1 or 5 is not necessary here due to the redenundany of the upcoming storage cluster.

A sample setup could be to use a free partition on two independent disks, either directly or like described here with a customizable LVM base. In the following example we are using XFS as the file system. This is not necessary but a good choice. 

Create the first data disk (replace /dev/sda4 by your partition device and "50g" by a storage size of your choice in giga bytes):

~~~~
mkdir -p /data1
~~~~

~~~~
pvcreate /dev/sda4
vgcreate vgdata1 /dev/sda4
lvcreate --size 50g -n lv0 vgdata1
mkfs.xfs /dev/vgdata1/lv0
echo "/dev/vgdata1/lv0 /data1 xfs defaults 0 0" >> /etc/fstab
mount /data1
~~~~

Create the second data disk (replace /dev/sdb4 by your partition device and "50g" by a storage size of your choice in giga bytes):

~~~~
mkdir -p /data2
~~~~

~~~~
pvcreate /dev/sdb4
vgcreate vgdata2 /dev/sdb4
lvcreate --size 50g -n lv0 vgdata2
mkfs.xfs /dev/vgdata2/lv0
echo "/dev/vgdata2/lv0 /data2 xfs defaults 0 0" >> /etc/fstab
mount /data2
~~~~

#### A sudo user for system administration

Create a system administrator user and disable root
~~~~
adduser sysadm
usermod -aG sudo sysadm
passwd -l root
~~~~

#### An up to date Ubuntu distribution

Ensure all updates have been applied
~~~~
apt update && apt upgrade -y
~~~~

#### A working setup of the Ansible automation package

Install Ansible and clone this GitHub repository on your local machine:
~~~~
apt-add-repository ppa:ansible/ansible
apt update
apt install ansible
mkdir -p /opt/mgmt/ssp-base
git clone https://github.com/trayla/ssp-base.git /opt/mgmt/ssp-base
chown -R sysadm:sysadm /opt/mgmt
~~~~
