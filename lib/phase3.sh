#!/bin/bash

# input USE_LIVECD_KERNEL
# input TARGET_DISK
# input SSH_PUBLIC_KEY
# input EMERGE_OPTS
# input GENKERNEL_OPTS

set -e

################################################################################

einfo "Upading configuration..."

eexec env-update
eexec source /etc/profile

################################################################################

einfo "Tuning compiler options..."

CPU_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)
MAKE_THREADS=$(expr $CPU_COUNT + 1)
MAKE_OPTS="-j$MAKE_THREADS"

cat >> /etc/portage/make.conf << END

# added by gentoo vbox builder
CFLAGS="-O2 -pipe -mtune=generic"
MAKEOPTS="$MAKE_OPTS"
END

################################################################################

einfo "Installing kernel sources..."

eexec emerge $EMERGE_OPTS "sys-kernel/gentoo-sources"

if eoff "$USE_LIVECD_KERNEL"; then
    einfo "Installing genkernel..."

    echo "sys-apps/util-linux static-libs" > /etc/portage/package.use/genkernel

    eexec emerge $EMERGE_OPTS "sys-kernel/genkernel"

    einfo "Installing kernel..."

    eexec genkernel $GENKERNEL_OPTS all --kernel-config=/etc/kernels/kernel-config-*
fi

################################################################################

einfo "Installing bootloader..."

cat >> /etc/portage/make.conf << END

# added by gentoo vbox builder
GRUB_PLATFORMS="pc"
END

eexec emerge $EMERGE_OPTS "sys-boot/grub"

cat >> /etc/default/grub << END

# added by gentoo vbox builder
GRUB_CMDLINE_LINUX="net.ifnames=0"
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
END

eexec grub-install "${TARGET_DISK}"
eexec grub-mkconfig -o /boot/grub/grub.cfg

################################################################################

einfo "Configuring network..."

eexec ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
eexec rc-update add net.eth0 default

################################################################################

einfo "Configuring SSH..."

eexec rc-update add sshd default

eexec passwd -d -l root

eexec mkdir /root/.ssh
eexec touch /root/.ssh/authorized_keys
eexec chmod 750 /root/.ssh
eexec chmod 640 /root/.ssh/authorized_keys
echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys

################################################################################

if eoff "$USE_LIVECD_KERNEL"; then
    einfo "Updating world..."

    eexec emerge $EMERGE_OPTS --update --deep --newuse @world
fi

################################################################################
