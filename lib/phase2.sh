#!/bin/bash

# input GENTOO_MIRROR
# input GENTOO_PROFILE
# input GENTOO_ARCH
# input TARGET_DISK
# input PARTITION_BOOT_SIZE
# input PARTITION_SWAP_SIZE
# input USE_LIVECD_KERNEL
# input WGET_OPTS

set -e

################################################################################

einfo "Setting time..."

eexec ntpd -gq

################################################################################

einfo "Preparing disk..."

eindent

einfo "Creating partitions..."

eqexec sfdisk "${TARGET_DISK}" << END
size=$PARTITION_BOOT_SIZE,bootable
size=$PARTITION_SWAP_SIZE
;
END

einfo "Formatting partitions..."

eexec mkfs.ext4 -q "${TARGET_DISK}1"
yes | eqexec mkswap "${TARGET_DISK}2"
eexec mkfs.ext4 -q "${TARGET_DISK}3"

einfo "Labeling partitions..."

eexec e2label "${TARGET_DISK}1" boot
eexec swaplabel "${TARGET_DISK}2" -L swap
eexec e2label "${TARGET_DISK}3" root

eoutdent

################################################################################

einfo "Mounting disk..."

eexec swapon "${TARGET_DISK}2"

eexec mkdir -p /mnt/gentoo
eexec mount "${TARGET_DISK}3" /mnt/gentoo

eexec mkdir -p /mnt/gentoo/boot
eexec mount "${TARGET_DISK}1" /mnt/gentoo/boot

################################################################################

einfo "Setting work directory..."

eexec cd /mnt/gentoo

################################################################################

einfo "Installing stage3..."

eindent

einfo "Downloading..."

STAGE3_PATH_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/latest-stage3-$GENTOO_PROFILE.txt"
STAGE3_PATH="$(curl -s "$STAGE3_PATH_URL" | grep -v "^#" | cut -d" " -f1)"
STAGE3_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/$STAGE3_PATH"

eexec wget $WGET_OPTS "$STAGE3_URL"

einfo "Extracting..."

eexec tar xpf "$(basename "$STAGE3_URL")" --xattrs-include='*.*' --numeric-owner

einfo "Cleaning up..."

eexec rm "$(basename "$STAGE3_URL")"

eoutdent

################################################################################

einfo "Installing portage repo..."

eindent

einfo "Initializing..."

eexec mkdir -p /mnt/gentoo/etc/portage/repos.conf
eexec cp /mnt/gentoo/usr/share/portage/config/repos.conf \
    /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

einfo "Downloading..."

PORTAGE_URL="$GENTOO_MIRROR/releases/snapshots/current/portage-latest.tar.xz"
eexec wget $WGET_OPTS "$PORTAGE_URL"

einfo "Extracting..."

eexec tar xf "$(basename "$PORTAGE_URL")" -C usr --xattrs-include='*.*' --numeric-owner

einfo "Cleaning up..."

eexec rm "$(basename "$PORTAGE_URL")"

eoutdent

################################################################################

if eon "$USE_LIVECD_KERNEL"; then
    einfo "Installing LiveCD kernel..."

    LIVECD_KERNEL_VERSION=$(cat /proc/version | cut -d" " -f3)
    KERNEL_ARCH_SUFFIX=$(echo "$GENTOO_ARCH" | sed "s/^amd64$/x86_64/")

    eexec cp -v "/mnt/cdrom/isolinux/gentoo" \
        "/mnt/gentoo/boot/kernel-genkernel-$KERNEL_ARCH_SUFFIX-$LIVECD_KERNEL_VERSION"

    eexec cp -v "/mnt/cdrom/isolinux/gentoo.igz" \
        "/mnt/gentoo/boot/initramfs-genkernel-$KERNEL_ARCH_SUFFIX-$LIVECD_KERNEL_VERSION"

    eexec cp -vR "/lib/modules/$LIVECD_KERNEL_VERSION" "/mnt/gentoo/lib/modules/"
fi

################################################################################

einfo "Installing LiveCD's kernel configuration..."

eexec mkdir -p /mnt/gentoo/etc/kernels
eexec cp -v /etc/kernels/* /mnt/gentoo/etc/kernels

################################################################################

einfo "Copying network options..."

eexec cp -v /etc/resolv.conf /mnt/gentoo/etc/

################################################################################

einfo "Configuring fstab..."

cat >> /mnt/gentoo/etc/fstab << END

# added by gentoo vbox builder
LABEL=boot /boot ext4 noauto,noatime 1 2
LABEL=swap none  swap sw             0 0
LABEL=root /     ext4 noatime        0 1
END

################################################################################

einfo "Mounting proc/sys/dev/pts..."

eexec mount -t proc none /mnt/gentoo/proc
eexec mount -t sysfs none /mnt/gentoo/sys
eexec mount -o bind /dev /mnt/gentoo/dev
eexec mount -o bind /dev/pts /mnt/gentoo/dev/pts

################################################################################
