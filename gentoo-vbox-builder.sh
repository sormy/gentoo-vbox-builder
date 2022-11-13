#!/bin/bash

SCRIPT_DIR="$( cd "$(dirname "$0")" ; pwd -P )"

################################################################################

# shellcheck source=lib/opt.sh
source "$SCRIPT_DIR/lib/opt.sh"
# shellcheck source=lib/alib.sh
source "$SCRIPT_DIR/lib/alib.sh"
# shellcheck source=lib/elib.sh
source "$SCRIPT_DIR/lib/elib.sh"
# shellcheck source=lib/distfiles.sh
source "$SCRIPT_DIR/lib/distfiles.sh"

################################################################################

APP_NAME="gentoo-vbox-builder"
APP_DESCRIPTION="Gentoo VirtualBox Image Builder"
APP_VERSION="1.0.8"

# Gentoo mirror.
GENTOO_MIRROR="http://distfiles.gentoo.org"

# Current Gentoo GPG public key IDs: https://www.gentoo.org/downloads/signatures/
GENTOO_GPG_SERVER="${GENTOO_GPG_SERVER:-hkps://keys.gentoo.org}"
GENTOO_GPG_KEYS="$(cat "$SCRIPT_DIR/gentoo-gpg-keys.txt" | grep -v '^#')"

# Gentoo stage3.
GENTOO_STAGE3="amd64"

# Gentoo profile. Blank indicates that stage3 default profile should be used.
GENTOO_PROFILE=""

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
GUEST_MEM_SIZE="4096"

# Guest hard disk filename.
GUEST_DISK_FILENAME=""

# Default guest SSH port.
GUEST_SSH_PORT="22"

# Default host SSH port that will be forwarded to guest SSH port.
HOST_SSH_PORT="2222"

# If you really want to get instance as soon as possible.
USE_LIVECD_KERNEL="off"

# Boot using admincd instead of minimal install livecd (useful if livecd is broken).
USE_ADMINCD="off"

# Target disk to install.
TARGET_DISK="/dev/sda"

# Boot partition size.
PARTITION_BOOT_SIZE="300M"

# Swap partition size.
PARTITION_SWAP_SIZE="128M"

# SSH public key to use.
SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/id_rsa.pub")"

# Set root password.
ROOT_PASSWORD="Gentoo.Built.123"

# Curl default options.
CURL_OPTS="--silent"

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
          -o LogLevel=error
          -o ServerAliveInterval=60
          -o ServerAliveCountMax=3"

# Enable color by default.
COLOR="on"

# Disable Keeping of Downloads by default
KEEP_DOWNLOADS="off"

# Disable Debug by default.
ELOG_DEBUG="off"

################################################################################

show_help() {

GENTOO_STAGE3_LIST="$(
    curl -s http://distfiles.gentoo.org/releases/{x86,amd64}/autobuilds/ \
        | grep -e '"latest-stage3-\S*\.txt"' -o \
        | sed -e 's/"//g' -e 's/^latest-stage3-//' -e 's/\.txt$//' \
        | sort | uniq \
)"

GENTOO_PROFILE_LIST="$(
    curl -s https://raw.githubusercontent.com/gentoo/gentoo/master/profiles/profiles.desc \
        | grep '^\(x86\|amd64\)\s' | cut -f 3 | sort | uniq \
)"

cat << END
$APP_NAME: $APP_DESCRIPTION v$APP_VERSION

Usage:
    $(basename "$0") [options]

Options:
    --gentoo-mirror <url>           (default is "$GENTOO_MIRROR")
        Set to use specific gentoo mirror instead of default one.

    --gentoo-stage3 <name>          (default is "$GENTOO_STAGE3")
        Bootstrap using this stage3:
$(echo "$GENTOO_STAGE3_LIST" | sed 's/^/          * /')

    --gentoo-profile <name>         (default is "$GENTOO_PROFILE")
        Switch to this profile during installation:
$(echo "$GENTOO_PROFILE_LIST" | sed 's/^/          * /')

    --gentoo-livecd-iso <path>      (default is autodetected)
        Set to use custom livecd file and don't download latest from server.

    --guest-name <name>             (default is "Gentoo %ARCH%")
        Guest name.

    --guest-disk-size <size/mb>     (default is $GUEST_DISK_SIZE)
        Hard disk size to share with guest.

    --guest-mem-size <size/mb>      (default is $GUEST_MEM_SIZE)
        Memory size to share with guest.

    --guest-cpus <number>           (default is $GUEST_CPUS)
        Number of CPUs to share with guest.

    --host-ssh-port <number>        (default is $HOST_SSH_PORT)
        Host port that should be used for guest ssh.

    --ssh-public-key <key>          (default is from ~/.ssh/id_rsa.pub)
        Set to use specific public ssh key for bootstrap.

    --root-password <password>      (default is "$ROOT_PASSWORD")
        Enable password auth.

    --use-livecd-kernel <bool>      (default is "$USE_LIVECD_KERNEL")
        Use precompiled livecd kernel from livecd. This options will save
        time on getting bootable system.

    --use-admincd <bool>            (default is "$USE_ADMINCD")
        Use admincd instead of minimal install cd. Could be helpful if minimal
        install cd is broken for some reason.

    --color <bool>                  (default is "$COLOR")
        Enable or disable colors in output.

    --keep-downloads <bool>         (default is "$KEEP_DOWNLOADS")
        Enable or disable cleaning up files downloaded to /tmp on exit.

    --version
        Show version.

    --help
        Show this screen.
END
}

show_version() {
    echo "$APP_VERSION"
}

################################################################################

set -e

opt_config "
    --gentoo-mirror \
    --gentoo-stage3 \
    --gentoo-profile \
    --gentoo-livecd-iso \
    --guest-name \
    --guest-disk-size \
    --guest-mem-size \
    --guest-cpus \
    --host-ssh-port \
    --ssh-public-key \
    --root-password \
    --use-livecd-kernel \
    --use-admincd \
    --color \
    --keep-downloads \
    --debug \
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

OPT="$(opt_get "--gentoo-mirror")";         [ -z "$OPT" ] || GENTOO_MIRROR="$OPT"
OPT="$(opt_get "--gentoo-stage3")";         [ -z "$OPT" ] || GENTOO_STAGE3="$OPT"
OPT="$(opt_get "--gentoo-profile")";        [ -z "$OPT" ] || GENTOO_PROFILE="$OPT"
OPT="$(opt_get "--gentoo-livecd-iso")";     [ -z "$OPT" ] || GENTOO_LIVECD_ISO="$OPT"
OPT="$(opt_get "--guest-name")";            [ -z "$OPT" ] || GUEST_NAME="$OPT"
OPT="$(opt_get "--guest-disk-size")";       [ -z "$OPT" ] || GUEST_DISK_SIZE="$OPT"
OPT="$(opt_get "--guest-mem-size")";        [ -z "$OPT" ] || GUEST_MEM_SIZE="$OPT"
OPT="$(opt_get "--guest-cpus")";            [ -z "$OPT" ] || GUEST_CPUS="$OPT"
OPT="$(opt_get "--host-ssh-port")";         [ -z "$OPT" ] || HOST_SSH_PORT="$OPT"
OPT="$(opt_get "--ssh-public-key")";        [ -z "$OPT" ] || SSH_PUBLIC_KEY="$OPT"
OPT="$(opt_get "--root-password")";         [ -z "$OPT" ] || ROOT_PASSWORD="$OPT"
OPT="$(opt_get "--use-livecd-kernel")";     [ -z "$OPT" ] || USE_LIVECD_KERNEL="$OPT"
OPT="$(opt_get "--use-admincd")";           [ -z "$OPT" ] || USE_ADMINCD="$OPT"
OPT="$(opt_get "--color")";                 [ -z "$OPT" ] || COLOR="$OPT"
OPT="$(opt_get "--keep-downloads")";        [ -z "$OPT" ] || KEEP_DOWNLOADS="$OPT"
OPT="$(opt_get "--debug")";                 [ -z "$OPT" ] || ELOG_DEBUG="$OPT"


# Autodetect Gentoo architecture based on profile name.
GENTOO_ARCH="$(echo "$GENTOO_STAGE3" | grep -q '^\(amd64\|x32\)' && echo "amd64" || echo "x86")"

# Autodetect guest name based on Gentoo architecture.
GUEST_NAME="${GUEST_NAME:-Gentoo $GENTOO_ARCH}"

# Autodetect OS type name based on Gentoo architecture.
GUEST_OS_TYPE="$([ "$GENTOO_ARCH" = "x86" ] && echo "Gentoo" || echo "Gentoo_64")"

# Use default VirtualBox naming convention for virtual disk files.
GUEST_DISK_FILENAME="$HOME/VirtualBox VMs/$GUEST_NAME/$GUEST_NAME.vdi"

# Detect if target profile is systemd
GENTOO_SYSTEMD="$(
    (echo "$GENTOO_PROFILE" | grep -q 'systemd' \
        || echo "$GENTOO_STAGE3" | grep -q 'systemd') \
        && echo yes || echo no
)"

elog_set_colors "$COLOR"

################################################################################

handle_exit() {
    if eoff $KEEP_DOWNLOADS; then
        edebug "--keep-downloads is off, cleaning up files in /tmp"

        download_distfile_cleanup
    else
        edebug "--keep-downloads is enabled, downloads were not removed."
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
# Initialization & Dependency check

einfo "$APP_DESCRIPTION $APP_VERSION"

edebug "Debug Messages are enabled"

if ! command -v VBoxManage &> /dev/null; then
    edie "VBoxManage is not installed, please install/reinstall VirtualBox"
fi

if ! command -v gpg &> /dev/null; then
    edie "GPG is not installed."
fi

# If keep downloads was on last run, but off this run, we should clean up distfiles
if eoff $KEEP_DOWNLOADS; then
    edebug "--keep-downloads is off, cleaning up files in /tmp if they exist"
    download_distfile_cleanup
fi



################################################################################
# PHASE 1: Prepare Instance...

einfo "The following parameters will be used:"

eindent

einfo "Guest Name: $GUEST_NAME"
einfo "Host SSH Port: $HOST_SSH_PORT"
einfo "Gentoo Stage3: $GENTOO_STAGE3 (ARCH: $GENTOO_ARCH)"
if [ -n "$GENTOO_PROFILE" ]; then
    einfo "Gentoo Profile: $GENTOO_PROFILE"
fi

eoutdent

einfo "Started at $(date)"

APP_START_TS=$(date +%s)

einfo "PHASE 1: Prepare Instance..."

eindent

# all global variables are shared
source "$SCRIPT_DIR/lib/phase1-prepare-instance.sh"

eoutdent

################################################################################

einfo "PHASE 2: Prepare Root..."

eindent

cat "$SCRIPT_DIR/lib/elib.sh" \
    "$SCRIPT_DIR/lib/distfiles.sh" \
    "$SCRIPT_DIR/lib/phase2-prepare-root.sh" \
    | ssh $SSH_OPTS "root@localhost" \
        -p "$HOST_SSH_PORT" \
        "ELOG_INDENT=\"$ELOG_INDENT\"" \
        "ELOG_COLOR_OK=\"$ELOG_COLOR_OK\"" \
        "ELOG_COLOR_ERROR=\"$ELOG_COLOR_ERROR\"" \
        "ELOG_COLOR_QUOTE=\"$ELOG_COLOR_QUOTE\"" \
        "ELOG_COLOR_RESET=\"$ELOG_COLOR_RESET\"" \
        "ELOG_DEBUG=\"$ELOG_DEBUG\"" \
        "GENTOO_MIRROR=\"$GENTOO_MIRROR\"" \
        "GENTOO_STAGE3=\"$GENTOO_STAGE3\"" \
        "GENTOO_ARCH=\"$GENTOO_ARCH\"" \
        "TARGET_DISK=\"$TARGET_DISK\"" \
        "PARTITION_BOOT_SIZE=\"$PARTITION_BOOT_SIZE\"" \
        "PARTITION_SWAP_SIZE=\"$PARTITION_SWAP_SIZE\"" \
        "USE_LIVECD_KERNEL=\"$USE_LIVECD_KERNEL\"" \
        "CURL_OPTS=\"$CURL_OPTS\"" \
        "GENTOO_GPG_SERVER=\"$GENTOO_GPG_SERVER\"" \
        "GENTOO_GPG_KEYS=\"$GENTOO_GPG_KEYS\"" \
        "GENTOO_PROFILE=\"$GENTOO_PROFILE\"" \
        "GENTOO_SYSTEMD=\"$GENTOO_SYSTEMD\"" \
        "bash -s"

eoutdent

################################################################################

einfo "PHASE 3: Build Root..."

eindent

cat "$SCRIPT_DIR/lib/elib.sh" \
    "$SCRIPT_DIR/lib/phase3-build-root.sh" \
    | ssh $SSH_OPTS "root@localhost" \
        -p "$HOST_SSH_PORT" \
        "ELOG_INDENT=\"$ELOG_INDENT\"" \
        "ELOG_COLOR_OK=\"$ELOG_COLOR_OK\"" \
        "ELOG_COLOR_ERROR=\"$ELOG_COLOR_ERROR\"" \
        "ELOG_COLOR_QUOTE=\"$ELOG_COLOR_QUOTE\"" \
        "ELOG_COLOR_RESET=\"$ELOG_COLOR_RESET\"" \
        "ELOG_DEBUG=\"$ELOG_DEBUG\"" \
        "USE_LIVECD_KERNEL=\"$USE_LIVECD_KERNEL\"" \
        "TARGET_DISK=\"$TARGET_DISK\"" \
        "SSH_PUBLIC_KEY=\"$SSH_PUBLIC_KEY\"" \
        "ROOT_PASSWORD=\"$ROOT_PASSWORD\"" \
        "EMERGE_OPTS=\"$EMERGE_OPTS\"" \
        "GENKERNEL_OPTS=\"$GENKERNEL_OPTS\"" \
        "GENTOO_ARCH=\"$GENTOO_STAGE3\"" \
        "GENTOO_STAGE3=\"$GENTOO_STAGE3\"" \
        "GENTOO_PROFILE=\"$GENTOO_PROFILE\"" \
        "GENTOO_SYSTEMD=\"$GENTOO_SYSTEMD\"" \
        "chroot /mnt/gentoo bash -s"

################################################################################

einfo "Rebooting..."

ssh $SSH_OPTS "root@localhost" -p "$HOST_SSH_PORT" "reboot"

wait_until_ssh_will_be_up root localhost "$HOST_SSH_PORT"

einfo "Shutting down..."

eexec VBoxManage controlvm "$GUEST_NAME" acpipowerbutton

sleep 60

einfo "Removing LiveCD from DVD drive..."

eexec VBoxManage storageattach "$GUEST_NAME" \
    --storagectl SATA \
    --type dvddrive \
    --medium emptydrive \
    --port 0

eoutdent

einfo "Pruning any old instance's known ssh fingerprints"
ssh-keygen -R [localhost]:$HOST_SSH_PORT


einfo "Done at $(date)"

DURATION_MINS=$(expr \( "$(date +%s)" - "$APP_START_TS" \) / 60)

einfo "Process took $DURATION_MINS minutes"

################################################################################
