# SSP - Single Server Platform

Note: The master branch may be in an unstable or even broken state during development. Please use releases instead of the master branch in order to get a stable set of binaries.

## Prerequisits

### Hardware requirements

- A running bare metal machine with a plain Ubuntu 20.04 Server installation and root access (virtual machines are not supported)
- Minimum 16 GB RAM (minimum 8 GB with slightly modified parameters)
- Minimum 1 TB storage (minimum 150 GB with slightly modified parameters)

### Knowledge

- An understanding of Linux based system management and command line tools
- An understanding of virtualization with KVM
- Knowledge about operating a Kubernetes platform
- A basic understanding of GlusterFS

### Necessary preliminaries

#### Storage

Your system has to provide one directory which will be used as a KVM storage pool and therefore populated with disk images for the upcoming virtual machines. The following directory has to be created prior to the start of the installation procedure. 

##### /vmpool

This directory is going to be used as the default storage pool for all virtual machine images except the data images. For redundancy reasons it is recommended to store this directory at least on a RAID 1 device.

Create the directory of the default storage pool:
```ShellSession
mkdir -p /vmpool
```

##### Data Devices

Furthermore we need two storage devices to hold the payload data for the cluster (one per worker node). Each worker node provides a Longhorn storage operator which needs one disk. It has to be a partition of an arbitrary block device such as a phisical disk or a LVM logical volume. You have to assign these devices while staring the installation procedure a bit later. Keep in mind that these devices will be erased during installation.

#### A sudo user for system administration

Create a system administrator user and disable root
```ShellSession
adduser -u 990 sysadm
usermod -aG sudo sysadm
passwd -l root
```

#### Install scripts

In order to execute the scripts you have to clone this GitHub repository to your server into the directory /opt/mgmt/ssp by issuing the following commands:
```ShellSession
mkdir -p /opt/mgmt/ssp
git clone https://github.com/trayla/ssp.git /opt/mgmt/ssp
chown -R sysadm:sysadm /opt/mgmt
```

The values file defines specific customizations of your own topology. A sample file is included in this repository. It should be copied to /opt/mgmt and customized before further installation.
```ShellSession
cp /opt/mgmt/ssp/values-default.yaml /opt/mgmt/values-ssp.yaml
```

#### Domain

The Single Server Platform provides a lot of services to the outside world. In order to access these services we are registering them as sub domains of a configurable main domain. The most comfortable way is to have a main domain like 'example.com' which points to your platform IP address by a wildcard DNS entry like this '*.example.com > 88.77.66.55'. In this case the platform can route any subdomain to the desired service by itself.

## Usage

Prepare your host with the following command. This is necessary only once while you can install and remove the platform from your host as much as you like.
```ShellSession
sudo /opt/mgmt/ssp/platform.sh prepare
```

Install the platform with the following command. Replace the storage devices /dev/sdx1 and /dev/sdy1 with the devices of your choice.
```ShellSession
sudo /opt/mgmt/ssp/platform.sh install /dev/sdx1 /dev/sdy1
```

This command removes the whole plattform from your host:
```ShellSession
sudo /opt/mgmt/ssp/platform.sh remove
```

After completion the system will be restarted. It takes a couple minutes until all virtual machines and services are up an running.

## Result

If everything worked as expected you should have the following setting on your machine.

### Architectural Overview

This picture shows an architectural overview of the desired platform:

![Diagram](docs/landscape.svg)

<a href="https://app.diagrams.net/#Htrayla%2Fssp%2Fmaster%2Fdocs%2Flandscape.svg" target="_blank">Edit</a>

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
or by connection to the virtual machine over SSH (password is "pw%ssp")
```ShellSession
ssh sysadm@<ipaddr>
```

#### console

Purpose: Management machine

IP Address: XX.ZZ.YY.2

#### kubemaster

Purpose: Kubernetes master

IP Address: XX.YY.ZZ.10

#### kubenode1

Purpose: First Kubernetes worker node with data storage

IP Address: XX.YY.ZZ.11

#### kubenode2

Purpose: Second Kubernetes worker node with data storage

IP Address: XX.YY.ZZ.12
