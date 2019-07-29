# Single Server Platform - Base

### This repository is still in progress! Do not use it right now!

Ubuntu 18.04

Create system administrator and disable root
~~~~
adduser sysadm
usermod -aG sudo sysadm
passwd -l root
~~~~

Ensure all updates have been applied
~~~~
apt update && apt upgrade -y
~~~~

Install necessary Linux packages
~~~~
apt install -y xfsprogs qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virt-manager sysstat apt-transport-https ca-certificates curl software-properties-common
~~~~

Install Ansible
~~~~
apt-add-repository ppa:ansible/ansible
apt update
apt install ansible
mkdir -p /opt/mgmt/ssp-base
git clone https://github.com/trayla/ssp-base.git /opt/mgmt/ssp-base
chown -R sysadm:sysadm /opt/mgmt
~~~~

Create the VM pool disk
~~~~
mkdir -p /vmpool
~~~~

Create the first data disk
~~~~
pvcreate /dev/sda4
vgcreate vgdata1 /dev/sda4
lvcreate --size 500g -n lv0 vgdata1
mkfs.xfs /dev/vgdata1/lv0
mkdir -p /data1
echo "/dev/vgdata1/lv0    /data1  xfs     defaults        0       0" >> /etc/fstab
mount /data1
~~~~

Create the second data disk
~~~~
pvcreate /dev/sdb4
vgcreate vgdata2 /dev/sdb4
lvcreate --size 500g -n lv0 vgdata2
mkfs.xfs /dev/vgdata2/lv0
mkdir -p /data2
echo "/dev/vgdata2/lv0    /data2  xfs     defaults        0       0" >> /etc/fstab
mount /data2
~~~~
