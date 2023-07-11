#!/bin/bash

# input GUEST_NAME
# input GUEST_OS_TYPE
# input GUEST_MEM_SIZE
# input GUEST_CPUS
# input HOST_SSH_PORT
# input GUEST_SSH_PORT
# input GUEST_DISK_FILENAME
# input GUEST_DISK_SIZE
# input GUEST_DVD_FILENAME
# input SSH_PUBLIC_KEY
# input GENTOO_MIRROR
# input GENTOO_ARCH
# input GENTOO_LIVECD_ISO
# input CURL_OPTS
# input GENTOO_GPG_SERVER
# input GENTOO_GPG_KEYS
# input USE_ADMINCD

# output GENTOO_LIVECD_TMP
# output GUEST_INIT_FILE

set -e

edebug "Debug Messages sucessfully enabled in Phase 1"

################################################################################

if VBoxManage list runningvms | grep -q '^"'"$GUEST_NAME"'"'; then
    einfo "Stopping existing guest..."

    eexec VBoxManage controlvm "$GUEST_NAME" poweroff

    sleep 5
fi

################################################################################

if VBoxManage list vms | grep -q '^"'"$GUEST_NAME"'"'; then
    einfo "Removing existing guest..."

    eexec VBoxManage unregistervm "$GUEST_NAME" --delete
fi

################################################################################

einfo "Checking if host SSH port is available..."

RUNNING_VMS="$(VBoxManage list runningvms | sed -e 's/^.*{\([^}]*\)}$/\1/')"

for VM in $RUNNING_VMS; do
    if VBoxManage showvminfo "$VM" \
        | grep -e 'NIC.*Rule' \
        | grep -e 'host port = \d\{1,\}' -o \
        | sed -e 's/^.* = //' \
        | grep -q "^$HOST_SSH_PORT\$"
    then
        VM_DESC="$(VBoxManage list vms | grep "$VM")"
        edie "The host port $HOST_SSH_PORT is busy by running guest $VM_DESC"
    fi
done



################################################################################

if [ -z "$GENTOO_LIVECD_ISO" ]; then
    einfo "Downloading Gentoo LiveCD..."

    eindent

    LIVECD_FILTER="$(eon "$USE_ADMINCD" && echo admincd || echo minimal)"

    GENTOO_LIVECD_META_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/latest-iso.txt"
    GENTOO_LIVECD_REL_PATH="$(curl -s "$GENTOO_LIVECD_META_URL" | grep -v "^#" | grep $LIVECD_FILTER | cut -d" " -f1)"
    GENTOO_LIVECD_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/$GENTOO_LIVECD_REL_PATH"
    GENTOO_LIVECD_TMP="/tmp/$(basename "$GENTOO_LIVECD_REL_PATH")"
    GENTOO_LIVECD_ISO="$GENTOO_LIVECD_TMP"

    einfo "Downloading: $GENTOO_LIVECD_URL ..."

    download_distfile_safe "$GENTOO_LIVECD_URL" "$GENTOO_LIVECD_TMP"

    eoutdent
fi

################################################################################

einfo "Creating guest..."

eexec VBoxManage createvm \
    --name "$GUEST_NAME" \
    --ostype "$GUEST_OS_TYPE" \
    --register

################################################################################

einfo "Configuring guest..."

eexec VBoxManage modifyvm "$GUEST_NAME" \
    --memory "$GUEST_MEM_SIZE" \
    --cpus "$GUEST_CPUS" \
    --ioapic on \
    --firmware bios \
    --rtcuseutc on \
    --mouse usbtablet \
    --boot1 dvd \
    --boot2 disk \
    --boot3 none \
    --boot4 none \
    --nic1 nat \
    --natpf1 "ssh,tcp,,$HOST_SSH_PORT,,$GUEST_SSH_PORT"

################################################################################

einfo "Adding storage controller to guest..."

eexec VBoxManage storagectl "$GUEST_NAME" \
    --name SATA \
    --add sata \
    --portcount 2

################################################################################

einfo "Attaching DVD drive to guest..."

eexec VBoxManage storageattach "$GUEST_NAME" \
    --storagectl SATA \
    --type dvddrive \
    --medium "$GENTOO_LIVECD_ISO" \
    --port 0

################################################################################

einfo "Creating disk for guest..."

eexec VBoxManage createmedium disk \
    --filename "$GUEST_DISK_FILENAME" \
    --size "$GUEST_DISK_SIZE"

################################################################################

einfo "Attaching disk to guest..."

eexec VBoxManage storageattach "$GUEST_NAME" \
    --storagectl SATA \
    --type hdd \
    --medium "$GUEST_DISK_FILENAME" \
    --port 1

################################################################################

einfo "Running guest..."

eexec VBoxManage startvm "$GUEST_NAME" \
    --type headless

sleep 10

################################################################################

einfo "Booting Gentoo from LiveCD..."

# Commented out since Gentoo LiveCD now uses grub instead of syslinux
#eexec VBoxManage controlvm "$GUEST_NAME" \
#    keyboardputstring $'gentoo nokeymap vga=786\n'

sleep 60

################################################################################

einfo "Configuring SSH..."

GUEST_INIT_FILE="$(mktemp)"

# extra comment lines are needed to workaround VirtualBox v6.x issues
cat > "$GUEST_INIT_FILE" << EOF
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
mkdir -p /root/.ssh
echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
/etc/init.d/sshd start
EOF

eexec VBoxManage controlvm "$GUEST_NAME" \
    keyboardputfile "$GUEST_INIT_FILE"

wait_until_ssh_will_be_up root localhost "$HOST_SSH_PORT"

################################################################################
