#!/bin/bash

set -e

GENTOO_RELEASES_URL=http://distfiles.gentoo.org/releases

GENTOO_ARCH=amd64
GENTOO_VARIANT=amd64

TARGET_DISK=/dev/sda

PARTITION_BOOT_SIZE=100M
PARTITION_SWAP_SIZE=1G

GRUB_PLATFORMS=pc

USE_LIVECD_KERNEL=${USE_LIVECD_KERNEL:-1}

SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}

echo "### Checking configuration..."

if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "SSH_PUBLIC_KEY variable is not set"
    exit 1
fi

echo "### Setting time..."

ntpd -gq

echo "### Creating partitions..."

sfdisk ${TARGET_DISK} << END
size=$PARTITION_BOOT_SIZE,bootable
size=$PARTITION_SWAP_SIZE
;
END

echo "### Formatting partitions..."

yes | mkfs.ext4 ${TARGET_DISK}1
yes | mkswap ${TARGET_DISK}2
yes | mkfs.ext4 ${TARGET_DISK}3

echo "### Labeling partitions..."

e2label ${TARGET_DISK}1 boot
swaplabel ${TARGET_DISK}2 -L swap
e2label ${TARGET_DISK}3 root

echo "### Mounting partitions..."

swapon ${TARGET_DISK}2

mkdir -p /mnt/gentoo
mount ${TARGET_DISK}3 /mnt/gentoo

mkdir -p /mnt/gentoo/boot
mount ${TARGET_DISK}1 /mnt/gentoo/boot

echo "### Setting work directory..."

cd /mnt/gentoo

echo "### Installing stage3..."

STAGE3_PATH_URL=$GENTOO_RELEASES_URL/$GENTOO_ARCH/autobuilds/latest-stage3-$GENTOO_VARIANT.txt
STAGE3_PATH=$(curl -s $STAGE3_PATH_URL | grep -v "^#" | cut -d" " -f1)
STAGE3_URL=$GENTOO_RELEASES_URL/$GENTOO_ARCH/autobuilds/$STAGE3_PATH

wget $STAGE3_URL

tar xvpf $(basename $STAGE3_URL)

echo "### Installing portage..."

mkdir -p /etc/portage/repos.conf
cp -f /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
emerge-webrsync

if [ "$USE_LIVECD_KERNEL" != 0 ]; then
    echo "### Installing LiveCD kernel..."

    LIVECD_KERNEL_VERSION=$(cat /proc/version | cut -d" " -f3)
    KERNEL_ARCH_SUFFIX=$(echo $GENTOO_ARCH | sed "s/^amd64$/x86_64/")

    cp -v /mnt/cdrom/boot/gentoo \
        /mnt/gentoo/boot/kernel-genkernel-$KERNEL_ARCH_SUFFIX-$LIVECD_KERNEL_VERSION
    cp -v /mnt/cdrom/boot/gentoo.igz \
        /mnt/gentoo/boot/initramfs-genkernel-$KERNEL_ARCH_SUFFIX-$LIVECD_KERNEL_VERSION
    cp -vR /lib/modules/$LIVECD_KERNEL_VERSION /mnt/gentoo/lib/modules/
fi

echo "### Installing kernel configuration..."

mkdir -p /mnt/gentoo/etc/kernels
cp -v /etc/kernels/* /mnt/gentoo/etc/kernels

echo "### Copying network options..."

cp -v /etc/resolv.conf /mnt/gentoo/etc/

echo "### Configuring fstab..."

cat >> /mnt/gentoo/etc/fstab << END

# added by gentoo installer
LABEL=boot /boot ext4 noauto,noatime 1 2
LABEL=swap none  swap sw             0 0
LABEL=root /     ext4 noatime        0 1
END

echo "### Mounting proc/sys/dev/pts..."

mount -t proc none /mnt/gentoo/proc
mount -t sysfs none /mnt/gentoo/sys
mount -o bind /dev /mnt/gentoo/dev
mount -o bind /dev/pts /mnt/gentoo/dev/pts

echo "### Changing root..."

cat > /mnt/gentoo/root/gentoo-init.sh << END
#!/bin/bash

set -e

echo "### Upading configuration..."

env-update && source /etc/profile

echo "### Installing kernel sources..."

emerge sys-kernel/gentoo-sources

if [ "$USE_LIVECD_KERNEL" = 0 ]; then
    echo "### Installing kernel..."

    echo "sys-apps/util-linux static-libs" > /etc/portage/package.use/genkernel

    emerge sys-kernel/genkernel

    genkernel all --kernel-config=/etc/kernels/kernel-config-*
fi

echo "### Installing bootloader..."

emerge grub

cat >> /etc/portage/make.conf << IEND

# added by gentoo installer
GRUB_PLATFORMS="$GRUB_PLATFORMS"
IEND

cat >> /etc/default/grub << IEND

# added by gentoo installer
GRUB_CMDLINE_LINUX="net.ifnames=0"
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
IEND

grub-install ${TARGET_DISK}
grub-mkconfig -o /boot/grub/grub.cfg

echo "### Configuring network..."

ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
rc-update add net.eth0 default

echo "### Configuring SSH..."

rc-update add sshd default

passwd -d -l root

mkdir /root/.ssh
touch /root/.ssh/authorized_keys
chmod 750 /root/.ssh
chmod 640 /root/.ssh/authorized_keys
echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
END

chmod +x /mnt/gentoo/root/gentoo-init.sh

chroot /mnt/gentoo /root/gentoo-init.sh

echo "### Cleaning..."

rm /mnt/gentoo/$(basename $STAGE3_URL)
rm /mnt/gentoo/$(basename $PORTAGE_URL)
rm /mnt/gentoo/root/gentoo-init.sh

echo "### Rebooting..."

# signal that installation is completed before rebooting
for i in `seq 1 10`; do tput bel; done

reboot
