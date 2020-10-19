#!/bin/bash

# input USE_LIVECD_KERNEL
# input TARGET_DISK
# input SSH_PUBLIC_KEY
# input ROOT_PASSWORD
# input EMERGE_OPTS
# input GENKERNEL_OPTS
# input GENTOO_ARCH
# input GENTOO_STAGE3
# input GENTOO_PROFILE

set -e

################################################################################

# detect if target is systemd
GENTOO_SYSTEMD="$(
    (echo "$GENTOO_PROFILE" | grep -q 'systemd' \
        || echo "$GENTOO_STAGE3" | grep -q 'systemd') \
        && echo yes || echo no
)"

# detect kernel config file that should be used for bootstrap
KERNEL_CONFIG="$(find /etc/kernels -type f | head -n 1)"

# detect current Gentoo profile (from stage3)
CURRENT_PROFILE="$(readlink /etc/portage/make.profile | sed 's!^.*/profiles/!!')"

# https://www.gentoo.org/support/news-items/2017-12-26-experimental-amd64-17-1-profiles.html
NO_SYMLINK_LIB_MIGRATION=no
if [ "$GENTOO_ARCH" = "amd64" ] \
    && ! echo "$CURRENT_PROFILE" | grep -q '17\.1' \
    && echo "$GENTOO_PROFILE" | grep -q '17\.1'
then
    NO_SYMLINK_LIB_MIGRATION=yes
fi

################################################################################

einfo "Updating configuration..."

eexec env-update
eexec source /etc/profile

################################################################################

einfo "Tuning compiler options..."

CPU_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)
MAKE_THREADS=$(expr $CPU_COUNT + 1)
MAKE_OPTS="-j$MAKE_THREADS"

cat >> /etc/portage/make.conf << END

# added by gentoo-vbox-builder
CFLAGS="-O2 -pipe -mtune=generic"
CXXFLAGS="\$CFLAGS"
MAKEOPTS="$MAKE_OPTS"
END

################################################################################

einfo "Installing portage repo..."

eexec mkdir -p /etc/portage/repos.conf
eexec cp -f /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
eexec emerge-webrsync

################################################################################

if [ -n "$GENTOO_PROFILE" ]; then
    if eon "$NO_SYMLINK_LIB_MIGRATION"; then
        einfo "Migrating current profile $CURRENT_PROFILE..."
        einfo "  see more: https://www.gentoo.org/support/news-items/2017-12-26-experimental-amd64-17-1-profiles.html"

        eexec emerge -1 $EMERGE_OPTS "app-portage/unsymlink-lib"

        eexec unsymlink-lib --analyze
        eexec unsymlink-lib --migrate
        eexec unsymlink-lib --finish
    fi

    einfo "Switching profile to $GENTOO_PROFILE..."
    eexec eselect profile set "$GENTOO_PROFILE"

    if eon "$NO_SYMLINK_LIB_MIGRATION"; then
        # very slow, will trigger rebuild for gcc/glib
        einfo "Rebuilding packages referencing lib32..."
        eexec emerge -1 $EMERGE_OPTS /usr/lib/gcc /lib32 /usr/lib32
    fi
fi

################################################################################

einfo "Rebuilding the world..."

# rebuild whole world with new compiler options, could be probably useful for x32
# eexec emerge $EMERGE_OPTS -e @world

eexec emerge $EMERGE_OPTS --update --deep --newuse --with-bdeps=y @world
eexec emerge $EMERGE_OPTS --depclean

################################################################################

einfo "Installing kernel sources..."

eexec emerge $EMERGE_OPTS "sys-kernel/gentoo-sources"

################################################################################

if eon "$GENTOO_SYSTEMD"; then
    einfo "Tuning kernel configuration for systemd..."

    eexec cp -f "$KERNEL_CONFIG" "$KERNEL_CONFIG.bootstrap"

    eexec sed -i \
        -e '/CONFIG_AUTOFS4_FS/c\CONFIG_AUTOFS4_FS=y' \
        -e '/CONFIG_CHECKPOINT_RESTORE/c\CONFIG_CHECKPOINT_RESTORE=y' \
        -e '/CONFIG_FANOTIFY/c\CONFIG_FANOTIFY=y' \
        -e '/CONFIG_CRYPTO_USER_API_HASH/c\CONFIG_CRYPTO_USER_API_HASH=y' \
        -e '/CONFIG_CGROUP_BPF/c\CONFIG_CGROUP_BPF=y' \
        "$KERNEL_CONFIG.bootstrap"

    KERNEL_CONFIG="$KERNEL_CONFIG.bootstrap"
fi

################################################################################

if eon "$USE_LIVECD_KERNEL" && eon "$GENTOO_SYSTEMD"; then
    einfo "Detected systemd profile, LiveCD's kernel can't be used..."

    USE_LIVECD_KERNEL="off"
fi

################################################################################

if eoff "$USE_LIVECD_KERNEL"; then
    einfo "Installing genkernel..."

    echo "sys-kernel/genkernel -firmware" > /etc/portage/package.use/genkernel
    echo "sys-apps/util-linux static-libs" >> /etc/portage/package.use/genkernel
    eexec emerge $EMERGE_OPTS "sys-kernel/genkernel"
fi

################################################################################

if eoff "$USE_LIVECD_KERNEL"; then
    einfo "Installing kernel..."

    eexec genkernel all $GENKERNEL_OPTS --makeopts="$MAKE_OPTS" \
        --kernel-config="$KERNEL_CONFIG"
fi

################################################################################

einfo "Installing bootloader..."

cat >> /etc/portage/make.conf << END

# added by gentoo-vbox-builder
GRUB_PLATFORMS="pc"
END

eexec emerge $EMERGE_OPTS "sys-boot/grub"

GRUB_CMDLINE_LINUX="net.ifnames=0"
if eon "$GENTOO_SYSTEMD"; then
    GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX init=/lib/systemd/systemd"
fi

cat >> /etc/default/grub << END

# added by gentoo-vbox-builder
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX"
END

eexec grub-install "${TARGET_DISK}"
eexec grub-mkconfig -o /boot/grub/grub.cfg

################################################################################

# OpenRC won't react on acpi power button event without acpid daemon.
if eoff "$GENTOO_SYSTEMD"; then
    einfo "Installing acpid..."

    eexec emerge $EMERGE_OPTS "sys-power/acpid"
    eexec rc-update add acpid default
fi

################################################################################

# Machine ID setup is mandatory for systemd to make it work properly.
if eon "$GENTOO_SYSTEMD"; then
    einfo "Configuring systemd..."

    eexec systemd-machine-id-setup
fi

################################################################################

einfo "Configuring network..."

if eoff "$GENTOO_SYSTEMD"; then
    eexec ln -s /etc/init.d/net.lo /etc/init.d/net.eth0
    eexec rc-update add net.eth0 default
else
    cat > /etc/systemd/network/50-dhcp.network << END
[Match]
Name=*

[Network]
DHCP=yes
END
    eexec systemctl enable systemd-networkd

    eexec ln -snf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    eexec systemctl enable systemd-resolved
fi

################################################################################

if [ -z "$ROOT_PASSWORD" ]; then
    einfo "Removing root password..."
    eexec passwd -d -l root
else
    einfo "Configuring root password..."
    echo "root:$ROOT_PASSWORD" | eexec chpasswd
fi

################################################################################

einfo "Configuring SSH..."

if eoff "$GENTOO_SYSTEMD"; then
    eexec rc-update add sshd default
else
    eexec systemctl enable sshd
fi

################################################################################

einfo "Installing authorized SSH public key..."

eexec mkdir /root/.ssh
eexec touch /root/.ssh/authorized_keys
eexec chmod 750 /root/.ssh
eexec chmod 640 /root/.ssh/authorized_keys
echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys

################################################################################
