#!/bin/busybox sh
set -x

busybox mount -t proc none /proc
busybox mount -t sysfs none /sys
busybox mount -t devtmpfs none /dev

# Install all the busybox sym links
/bin/busybox --install

# Wait a bit for the kernel to stop spitting out messages
echo "Waiting for kernel"
sleep 10s

# Attempt to mount my encrypted root disk
echo "Enter password for encrypted root disk"
cryptsetup luksOpen --allow-discards /dev/nvme0n1p2 crypt-internal \
	|| cryptsetup luksOpen --allow-discards /dev/sdb2 crypt-internal \
	|| exec busybox sh

mount -t btrfs -o discard,subvol=roots/gentoo /dev/mapper/crypt-internal /mnt \
    || exec busybox sh

# Clean up so these can be mounted by the proper init later
umount /proc
umount /sys

# If it works then go ahead and try to enter the new root
exec busybox switch_root /mnt /sbin/init
