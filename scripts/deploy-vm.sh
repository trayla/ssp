#!/bin/bash

BASEDIR=$(dirname "$0")
SSP_PREFIX=ssp
HOSTNAME=$1
RAM=$2
CPUS=$3
DISKSIZE=$4
PASSWORD=$5
IPADDR=$6
APTPKGS=$7
DISKFILE=/vmpool/${SSP_PREFIX}_${HOSTNAME}_root.qcow2

# Generate the startup file which will be called the first time the virtual machines wakes up
tee /tmp/startup.sh > /dev/null << EOF
#!/bin/bash
dpkg-reconfigure openssh-server
/usr/sbin/update-grub
netplan generate && netplan apply
useradd -m -u 999 -p "" -s /bin/bash sysadm && usermod -aG sudo sysadm
echo -e $PASSWORD"\n"$PASSWORD | passwd sysadm
EOF

# Exit in case the image file already exists
if [ -f "$DISKFILE" ]; then
  echo "Disk image $DISKFILE already exists!"
  exit 1
fi

# Create the root image
virt-builder ubuntu-18.04 \
  --size=$DISKSIZE \
  --format qcow2 --output $DISKFILE \
  --hostname $HOSTNAME \
  --timezone UTC \
  --root-password password:$PASSWORD \
  --ssh-inject root:file:/root/.ssh/id_rsa.pub \
  --ssh-inject root:file:/home/sysadm/.ssh/id_rsa.pub \
  --install $APTPKGS \
  --firstboot /tmp/startup.sh

guestmount -a $DISKFILE -i --rw /mnt

sed -i '/^GRUB_CMDLINE_LINUX=/d' /mnt/etc/default/grub
sed -i '/^GRUB_TERMINAL=/d' /mnt/etc/default/grub
sed -i '/^GRUB_SERIAL_COMMAND=/d' /mnt/etc/default/grub
sed -i '/^#/d' /mnt/etc/default/grub
sed -i '/^$/d' /mnt/etc/default/grub
echo "GRUB_CMDLINE_LINUX='console=tty0 console=ttyS0,19200n8'" >> /mnt/etc/default/grub
echo "GRUB_TERMINAL=serial" >> /mnt/etc/default/grub
echo "GRUB_SERIAL_COMMAND='serial --speed=19200 --unit=0 --word=8 --parity=no --stop=1'" >> /mnt/etc/default/grub

tee /mnt/etc/netplan/01-netcfg.yaml > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens2:
      dhcp4: no
      addresses: [$IPADDR/24]
      gateway4: 10.88.20.1
      nameservers:
        addresses: [8.8.8.8]
EOF

umount /mnt

virt-install \
  --name ${SSP_PREFIX}_${HOSTNAME} \
  --import \
  --ram $RAM \
  --vcpu $CPUS \
  --disk path=$DISKFILE,format=qcow2 \
  --os-type linux \
  --os-variant ubuntu17.10 \
  --graphics none \
  --network bridge=virbr1,model=virtio \
  --noautoconsole

sleep 20

virsh shutdown ${SSP_PREFIX}_${HOSTNAME}

sleep 10

virsh start ${SSP_PREFIX}_${HOSTNAME}
