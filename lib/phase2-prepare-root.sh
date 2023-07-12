#!/bin/bash

# input GENTOO_MIRROR
# input GENTOO_STAGE3
# input GENTOO_ARCH
# input TARGET_DISK
# input PARTITION_BOOT_SIZE
# input PARTITION_SWAP_SIZE
# input USE_LIVECD_KERNEL
# input CURL_OPTS

set -e

################################################################################

#einfo "Synchronizing time..."

#eexec ntpd -gq

################################################################################

einfo "Preparing disk..."

eindent

einfo "Creating partitions..."

eqexec sfdisk --label dos "${TARGET_DISK}" << END
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

unset STAGE3_PATH_PROFILE
case "${GENTOO_PROFILE}" in
	*musl*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-musl"
		else
			STAGE3_PATH_PROFILE="musl"
		fi
		;&
	*clang*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-clang"
		else
			STAGE3_PATH_PROFILE="clang"
		fi
		;&
	*hardened*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-hardened"
		else
			STAGE3_PATH_PROFILE="hardened"
		fi
		;&
	*nomultilib*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-nomultilib"
		else
			STAGE3_PATH_PROFILE="nomultilib"
		fi
		;&
	*selinux*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-selinux"
		else
			STAGE3_PATH_PROFILE="selinux"
		fi
		;&
	*desktop*)
		if [[ -n $STAGE3_PATH_PROFILE ]]; then
			STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-desktop"
		else
			STAGE3_PATH_PROFILE="desktop"
		fi
		;&
esac


if eon "$GENTOO_SYSTEMD"; then
	if [[ $STAGE3_PATH_PROFILE ]]; then
		STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-systemd"
	else
		STAGE3_PATH_PROFILE="systemd"
	fi
else
	if [[ $STAGE3_PATH_PROFILE ]]; then
		STAGE3_PATH_PROFILE="${STAGE3_PATH_PROFILE}-openrc"
	else
		STAGE3_PATH_PROFILE="openrc"
	fi
fi


eecho "Specified Profile: $GENTOO_PROFILE"
eecho "Download Profile:  $STAGE3_PATH_PROFILE"

STAGE3_PATH_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/latest-stage3-$GENTOO_STAGE3-$STAGE3_PATH_PROFILE.txt"
STAGE3_PATH="$(curl -s "$STAGE3_PATH_URL" | grep -v "^#" | cut -d" " -f1)"
STAGE3_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/$STAGE3_PATH"
STAGE3_FILE="$(basename "$STAGE3_URL")"

einfo "Downloading: $STAGE3_URL ..."

download_distfile_safe "$STAGE3_URL" "$STAGE3_FILE"

einfo "Extracting..."

eexec tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner

einfo "Cleaning up..."

eexec rm stage3-*

eoutdent

################################################################################

einfo "Installing LiveCD's kernel configuration..."

eexec mkdir -p /mnt/gentoo/etc/kernels
eexec cp -v /etc/kernels/* /mnt/gentoo/etc/kernels

################################################################################

if eon "$USE_LIVECD_KERNEL"; then
    einfo "Installing LiveCD's kernel/initramfs/modules..."

    LIVECD_KERNEL_VERSION=$(cut -d " " -f 3 < /proc/version)

    eexec cp -v "/mnt/cdrom/boot/gentoo" "/mnt/gentoo/boot/vmlinuz-$LIVECD_KERNEL_VERSION"
    eexec cp -v "/mnt/cdrom/boot/gentoo.igz" "/mnt/gentoo/boot/initramfs-$LIVECD_KERNEL_VERSION.img"
    eexec cp -vR "/lib/modules/$LIVECD_KERNEL_VERSION" "/mnt/gentoo/lib/modules/"
fi

################################################################################

einfo "Copying network options..."

eexec cp -v /etc/resolv.conf /mnt/gentoo/etc/

################################################################################

einfo "Configuring fstab..."

cat >> /mnt/gentoo/etc/fstab << END

# added by gentoo-vbox-builder
LABEL=boot /boot ext4 noauto,noatime 1 2
LABEL=swap none  swap sw             0 0
LABEL=root /     ext4 noatime        0 1
END

################################################################################

einfo "Mounting proc/sys/dev..."

eexec mount -t proc none /mnt/gentoo/proc
eexec mount -t sysfs none /mnt/gentoo/sys
eexec mount -o bind /dev /mnt/gentoo/dev
eexec mount -o bind /dev/pts /mnt/gentoo/dev/pts
eexec mount -o bind /dev/shm /mnt/gentoo/dev/shm

################################################################################
