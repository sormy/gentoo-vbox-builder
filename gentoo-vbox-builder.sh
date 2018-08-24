#!/bin/bash

SCRIPT_DIR="$( cd "$(dirname "$0")" ; pwd -P )"

################################################################################

source "$SCRIPT_DIR/lib/opt.sh"
source "$SCRIPT_DIR/lib/alib.sh"
source "$SCRIPT_DIR/lib/elib.sh"
source "$SCRIPT_DIR/lib/gentoo.sh"

################################################################################

APP_NAME="gentoo-vbox-builder"
APP_DESCRIPTION="Gentoo VirtualBox Image Builder"
APP_VERSION="1.0.2"

# Gentoo mirror.
GENTOO_MIRROR="http://distfiles.gentoo.org"

# Current Gentoo GPG public key ID.
# See more here: https://www.gentoo.org/downloads/signatures/
GENTOO_GPG_KEYS="$(cat "$SCRIPT_DIR/gentoo-gpg-keys.txt" | grep -v '^#')"

# Gentoo profile.
GENTOO_PROFILE="amd64"

# Detect Gentoo architecture based on provided profile name.
GENTOO_ARCH=""

# Set to Gentoo LiveCD iso, otherwise it will be downloaded during bootstrap.
GENTOO_LIVECD_ISO=""

# Guest OS name.
GUEST_NAME=""

# Guest OS type..
GUEST_OS_TYPE=""

# Configure virtual disk size for Gentoo.
GUEST_DISK_SIZE="20480"

# Configure number of CPUs delegated to guest.
GUEST_CPUS="2"

# Configure memory size delegated to guest.
GUEST_MEM_SIZE="1024"

# Guest hard disk filename.
GUEST_DISK_FILENAME=""

# Default guest SSH port.
GUEST_SSH_PORT="22"

# Default host SSH port that will be forwarded to guest SSH port.
HOST_SSH_PORT="2222"

# If you really want to get instance as soon as possible.
USE_LIVECD_KERNEL="on"

# Boot using admincd instead of minimal install livecd (useful if livecd is broken).
USE_ADMINCD="off"

# Target disk to install.
TARGET_DISK="/dev/sda"

# Boot partition size.
PARTITION_BOOT_SIZE="100M"

# Swap partition size.
PARTITION_SWAP_SIZE="1G"

# SSH public key to use.
SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/id_rsa.pub")"

# Wget default options.
WGET_OPTS="--quiet"

# Emerge default options.
EMERGE_OPTS="--quiet"

# Genkernel default options.
GENKERNEL_OPTS="--no-color"

# SSH default options.
SSH_OPTS="-o ConnectTimeout=5
          -o KbdInteractiveAuthentication=no
          -o ChallengeResponseAuthentication=no
          -o UserKnownHostsFile=/dev/null
          -o StrictHostKeyChecking=no
          -o LogLevel=error"

# Enable color by default.
COLOR="on"

################################################################################

show_help() {
cat << END
$APP_NAME: $APP_DESCRIPTION v$APP_VERSION
Usage:
    $(basename "$0") [options]
Options:
    --gentoo-mirror <url>           (default is "$GENTOO_MIRROR")
    --gentoo-profile <name>         (default is "$GENTOO_PROFILE")
    --gentoo-livecd-iso <path>      (default is autodetected)
    --guest-name <name>             (default is "Gentoo %ARCH%")
    --guest-disk-size <size/mb>     (default is $GUEST_DISK_SIZE)
    --guest-mem-size <size/mb>      (default is $GUEST_MEM_SIZE)
    --guest-cpus <number>           (default is $GUEST_CPUS)
    --host-ssh-port <number>        (default is $HOST_SSH_PORT)
    --ssh-public-key <key>          (default is from ~/.ssh/id_rsa.pub)
    --use-livecd-kernel <bool>      (default is "$USE_LIVECD_KERNEL")
    --use-admincd <bool>            (default is "$USE_ADMINCD")
    --color <bool>                  (default is "$COLOR")
    --version
    --help
END
}

show_version() {
    echo "$APP_VERSION"
}

################################################################################

set -e

opt_config "
    --gentoo-mirror \
    --gentoo-profile \
    --gentoo-livecd-iso \
    --guest-name \
    --guest-disk-size \
    --guest-mem-size \
    --guest-cpus \
    --host-ssh-port \
    --ssh-public-key \
    --use-livecd-kernel \
    --use-admincd \
    --color \
"

opt_parse "$@"

if [ "$(opt_cmd)" == "help" ]; then
    show_help
    exit
fi

if [ "$(opt_cmd)" == "version" ]; then
    show_version
    exit
fi

OPT="$(opt_get "--gentoo-mirror")";     [ -z "$OPT" ] || GENTOO_MIRROR="$OPT"
OPT="$(opt_get "--gentoo-profile")";    [ -z "$OPT" ] || GENTOO_PROFILE="$OPT"
OPT="$(opt_get "--gentoo-livecd-iso")"; [ -z "$OPT" ] || GENTOO_LIVECD_ISO="$OPT"
OPT="$(opt_get "--guest-name")";        [ -z "$OPT" ] || GUEST_NAME="$OPT"
OPT="$(opt_get "--guest-disk-size")";   [ -z "$OPT" ] || GUEST_DISK_SIZE="$OPT"
OPT="$(opt_get "--guest-mem-size")";    [ -z "$OPT" ] || GUEST_MEM_SIZE="$OPT"
OPT="$(opt_get "--guest-cpus")";        [ -z "$OPT" ] || GUEST_CPUS="$OPT"
OPT="$(opt_get "--host-ssh-port")";     [ -z "$OPT" ] || HOST_SSH_PORT="$OPT"
OPT="$(opt_get "--ssh-public-key")";    [ -z "$OPT" ] || SSH_PUBLIC_KEY="$OPT"
OPT="$(opt_get "--use-livecd-kernel")"; [ -z "$OPT" ] || USE_LIVECD_KERNEL="$OPT"
OPT="$(opt_get "--use-admincd")";       [ -z "$OPT" ] || USE_ADMINCD="$OPT"
OPT="$(opt_get "--color")";             [ -z "$OPT" ] || COLOR="$OPT"

# Autodetect Gentoo architecture based on profile name.
GENTOO_ARCH="$(echo "$GENTOO_PROFILE" | grep -q '^\(amd64\|x32\)' && echo "amd64" || echo "x86")"

# Autodetect guest name based on Gentoo architecture.
GUEST_NAME="${GUEST_NAME:-Gentoo $GENTOO_ARCH}"

# Autodetect OS type name based on Gentoo architecture.
GUEST_OS_TYPE="$([ "$GENTOO_ARCH" = "x86" ] && echo "Gentoo" || echo "Gentoo_64")"

# Use default VirtualBox naming convention for virtual disk files.
GUEST_DISK_FILENAME="$HOME/VirtualBox VMs/$GUEST_NAME/$GUEST_NAME.vdi"

elog_set_colors "$COLOR"

################################################################################

handle_exit() {
    if [ -n "$GENTOO_LIVECD_TMP" ] && [ -e "$GENTOO_LIVECD_TMP" ]; then
        rm  "$GENTOO_LIVECD_TMP"
    fi

    if [ -n "$GUEST_INIT_FILE" ] && [ -e "$GUEST_INIT_FILE" ]; then
        rm "$GUEST_INIT_FILE"
    fi
}

handle_error() {
    local lineno="$1"
    local message="$2"
    local code="${3:-1}"
    if [ -n "$message" ] ; then
        echo "ERROR: Error on or near line ${lineno}: ${message}; exiting with status ${code}"
    else
        echo "ERROR: Error on or near line ${lineno}; exiting with status ${code}"
    fi
    exit "${code}"
}

trap 'handle_exit' EXIT
trap 'handle_error ${LINENO}' ERR

################################################################################

einfo "$APP_DESCRIPTION $APP_VERSION"

einfo "The following parameters will be used:"

eindent

einfo "Guest Name: $GUEST_NAME"
einfo "Host SSH Port: $HOST_SSH_PORT"
einfo "Gentoo Profile: $GENTOO_PROFILE ($GENTOO_ARCH)"

eoutdent

einfo "Started at $(date)"

APP_START_TS=$(date +%s)

einfo "PHASE 1: Prepare Instance..."

eindent

# all global variables are shared
source "$SCRIPT_DIR/lib/phase1.sh"

eoutdent

einfo "PHASE 2: Prepare Root..."

eindent

cat "$SCRIPT_DIR/lib/elib.sh" \
    "$SCRIPT_DIR/lib/gentoo.sh" \
    "$SCRIPT_DIR/lib/phase2.sh" \
    | ssh $SSH_OPTS "root@localhost" \
        -p "$HOST_SSH_PORT" \
        "ELOG_INDENT=\"$ELOG_INDENT\"" \
        "ELOG_COLOR_OK=\"$ELOG_COLOR_OK\"" \
        "ELOG_COLOR_ERROR=\"$ELOG_COLOR_ERROR\"" \
        "ELOG_COLOR_QUOTE=\"$ELOG_COLOR_QUOTE\"" \
        "ELOG_COLOR_RESET=\"$ELOG_COLOR_RESET\"" \
        "GENTOO_MIRROR=\"$GENTOO_MIRROR\"" \
        "GENTOO_PROFILE=\"$GENTOO_PROFILE\"" \
        "GENTOO_ARCH=\"$GENTOO_ARCH\"" \
        "TARGET_DISK=\"$TARGET_DISK\"" \
        "PARTITION_BOOT_SIZE=\"$PARTITION_BOOT_SIZE\"" \
        "PARTITION_SWAP_SIZE=\"$PARTITION_SWAP_SIZE\"" \
        "USE_LIVECD_KERNEL=\"$USE_LIVECD_KERNEL\"" \
        "WGET_OPTS=\"$WGET_OPTS\"" \
        "GENTOO_GPG_KEYS=\"$GENTOO_GPG_KEYS\"" \
        "bash -s"

eoutdent

einfo "PHASE 3: Build Root..."

eindent

cat "$SCRIPT_DIR/lib/elib.sh" \
    "$SCRIPT_DIR/lib/phase3.sh" \
    | ssh $SSH_OPTS "root@localhost" \
        -p "$HOST_SSH_PORT" \
        "ELOG_INDENT=\"$ELOG_INDENT\"" \
        "ELOG_COLOR_OK=\"$ELOG_COLOR_OK\"" \
        "ELOG_COLOR_ERROR=\"$ELOG_COLOR_ERROR\"" \
        "ELOG_COLOR_QUOTE=\"$ELOG_COLOR_QUOTE\"" \
        "ELOG_COLOR_RESET=\"$ELOG_COLOR_RESET\"" \
        "USE_LIVECD_KERNEL=\"$USE_LIVECD_KERNEL\"" \
        "TARGET_DISK=\"$TARGET_DISK\"" \
        "SSH_PUBLIC_KEY=\"$SSH_PUBLIC_KEY\"" \
        "EMERGE_OPTS=\"$EMERGE_OPTS\"" \
        "GENKERNEL_OPTS=\"$GENKERNEL_OPTS\"" \
        "chroot /mnt/gentoo bash -s"

einfo "Shutting down..."

eexec VBoxManage controlvm "$GUEST_NAME" acpipowerbutton

sleep 60

einfo "Removing LiveCD from dvd..."

eexec VBoxManage storageattach "$GUEST_NAME" \
    --storagectl SATA \
    --type dvddrive \
    --medium emptydrive \
    --port 0

eoutdent

einfo "Done at $(date)"

DURATION_MINS=$(expr \( "$(date +%s)" - "$APP_START_TS" \) / 60)

einfo "Process took $DURATION_MINS minutes"

################################################################################
