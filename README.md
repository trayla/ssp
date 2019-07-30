# Single Server Platform - Base

### CAUTION: This repository is still in progress! Do not use it for now!

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

Your system has to provide two directories which will be used as KVM storage pools and therefore populated with disk images for the upcoming virtual machines. The following directories have to be create prior to the start of the installation procedure:

##### /data1 and /data2

These directories are going to be used as redundancy nodes for the storage cluster and should be on seperate storage disks. Using a high available disk setup like RAID 1 or 5 is not necessary here due to the redenundany of the upcoming storage cluster.

A sample setup could be to use a free partition on two independent disks, either directly or like described here with a customizable LVM base. In the following example we are using XFS as the file system. This is not necessary but a good choice. In order to use it on a Ubuntu server you have to install the appropriate package:

~~~~ShellSession
apt install -y xfsprogs
~~~~

Create the first data disk (replace /dev/sda4 by your partition device and "50g" by a storage size of your choice in giga bytes):

```ShellSession
mkdir -p /data1
```

```ShellSession
pvcreate /dev/sda4
vgcreate vgdata1 /dev/sda4
lvcreate --size 50g -n lv0 vgdata1
mkfs.xfs /dev/vgdata1/lv0
echo "/dev/vgdata1/lv0 /data1 xfs defaults 0 0" >> /etc/fstab
mount /data1
```

Create the second data disk (replace /dev/sdb4 by your partition device and "50g" by a storage size of your choice in giga bytes):

```ShellSession
mkdir -p /data2
```

```ShellSession
pvcreate /dev/sdb4
vgcreate vgdata2 /dev/sdb4
lvcreate --size 50g -n lv0 vgdata2
mkfs.xfs /dev/vgdata2/lv0
echo "/dev/vgdata2/lv0 /data2 xfs defaults 0 0" >> /etc/fstab
mount /data2
```

#### A sudo user for system administration

Create a system administrator user and disable root
```ShellSession
adduser sysadm
usermod -aG sudo sysadm
passwd -l root
```

#### Installed scripts

In order to execute the scripts you have to clone this GitHub repository to your server into the directory /opt/mgmt/ssp-base by issuing the following commands:
```ShellSession
mkdir -p /opt/mgmt/ssp-base
git clone https://github.com/trayla/ssp-base.git /opt/mgmt/ssp-base
chown -R sysadm:sysadm /opt/mgmt
```

## Usage

Call the setup stages from a root context with the following commands.

Initialize the host setup by the following command. This installs and configures the KVM virtualization engine along with Ansible and the host firewall:
```ShellSession
/opt/mgmt/ssp-base/host.sh prepare
```

Setting up the Gluster based storage cluster with the following command:
```ShellSession
/opt/mgmt/ssp-base/gluster.sh install
```

Setting up the Kubernetes cluster with the following command:
```ShellSession
/opt/mgmt/ssp-base/kubernetes.sh install
```

## Result

If everything worked as expected you should have the following setting on your machine.

### Architectural Overview

This picture shows an architectural overview of the desired platform:

![system landscape](https://trayla.github.com/docs/systemlandscape.svg)

### Virtual machines:

The virtual machines are available through the KVM standard command line tools:
- `virsh list --all` lists all virtual machines
- `virsh pool-list --all` lists all storage pools
- `virsh pool-info <poolname>` shows the details of the desired storage pool
- `virsh --help` shows all available commands of the virtual machine management

You can gain shell access to the desired virtual machine either by opening a KVM console
```ShellSession
virsh console <vmname>
```
or by connection to the virtual machine over SSH (password is "pw")
```ShellSession
ssh sysadm@<ipaddr>
```

#### gluster0

Purpose: Arbiter node of the Gluster storage cluster

IP Address: 10.88.20.110

#### gluster1

Purpose: First data node of the Gluster storage cluster

IP Address: 10.88.20.111

#### gluster2

Purpose: Second data node of the Gluster storage cluster

IP Address: 10.88.20.112

#### kubemaster

Purpose: Kubernetes master

IP Address: 10.88.20.120

#### kubenode1

Purpose: First Kubernetes worker node

IP Address: 10.88.20.121

#### kubenode2

Purpose: Second Kubernetes worker node

IP Address: 10.88.20.122
