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
# input WGET_OPTS

# output GENTOO_LIVECD_TMP
# output GUEST_INIT_FILE

set -e

################################################################################

if [ -z "$GENTOO_LIVECD_ISO" ]; then
    einfo "Downloading latest Gentoo LiveCD..."

    GENTOO_LIVECD_META_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/latest-iso.txt"
    GENTOO_LIVECD_REL_PATH="$(curl -s "$GENTOO_LIVECD_META_URL" | grep -v "^#" | grep minimal | cut -d" " -f1)"
    GENTOO_LIVECD_URL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/$GENTOO_LIVECD_REL_PATH"
    GENTOO_LIVECD_TMP="/tmp/$(basename "$GENTOO_LIVECD_REL_PATH")"
    GENTOO_LIVECD_ISO="$GENTOO_LIVECD_TMP"

    eexec wget $WGET_OPTS -O "$GENTOO_LIVECD_TMP" "$GENTOO_LIVECD_URL"
fi

################################################################################

if VBoxManage list runningvms | grep -q '^"'"$GUEST_NAME"'"'; then
    einfo "Stopping existing guest..."

    eexec VBoxManage controlvm "$GUEST_NAME" poweroff

    sleep 5
fi

################################################################################

if VBoxManage list vms| grep -q '^"'"$GUEST_NAME"'"'; then
    einfo "Removing existing guest..."

    eexec VBoxManage unregistervm "$GUEST_NAME" --delete
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

einfo "Attaching dvd to guest..."

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

# TODO: Unstable "keyboardputstring" with "--type headless" for some reason
eexec VBoxManage startvm "$GUEST_NAME" \

sleep 10

################################################################################

einfo "Booting Gentoo from LiveCD..."

eexec VBoxManage controlvm "$GUEST_NAME" \
    keyboardputstring $'gentoo nokeymap vga=786\n'

sleep 60

################################################################################

einfo "Configuring SSH..."

GUEST_INIT_FILE="$(mktemp)"

cat > "$GUEST_INIT_FILE" << EOF
mkdir -p /root/.ssh
echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
/etc/init.d/sshd start
EOF

GUEST_INIT_SCRIPT="$(cat "$GUEST_INIT_FILE")"

eexec VBoxManage controlvm "$GUEST_NAME" \
    keyboardputstring "$GUEST_INIT_SCRIPT"$'\n'

wait_until_ssh_will_be_up root localhost "$HOST_SSH_PORT"

################################################################################
