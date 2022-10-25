#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
  echo "help: $0 <USB location of RPi, e.g. 2-1.1>"
  exit
fi

absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

# include echo helper
. "$SRC_ROOT/tools/echohelper.sh"

USBLOC=$1
RPIBOOT=$(which rpiboot)

echoinfo "Checking for rpiboot ..."

if [ ! -x "$RPIBOOT" ]; then
    echoerr "rpiboot missing on this system, please install"
    exit
fi

# ToDo: check if USB device is available on USBLOC before using it

echoinfo "Starting rpiboot on device $USBLOC"
$RPIBOOT -p "$USBLOC"

# wait with sleep for the RPi mass storage device
sleep 5

usb_disk=$(find /sys/devices -iname "${USBLOC:?}" -exec find {} -iname block -print0 \; 2>/dev/null | xargs -0 ls)

if [ ! -b "/dev/$usb_disk" ]; then
	echoerr "no storage device found for USB device $USBLOC"
	exit
fi

echoinfo "RPi mass storage added as /dev/$usb_disk"
echoinfo "Looking for a running container"

# now get this shit into the container, one per line and only running
IFS=$'\n' read -r -d '' -a containers < <( lxc-ls -1 --running --filter 'lxc\-[a-zA-Z]*\-[0-9]*')

# If there is more than one running container, we don't know which container we
# can or should use (ToDo: check if LAVA can substitute the JOB_ID in a jinja2
# file). We exit for now, if we have more than one running container.
if [ ${#containers[@]} != 1 ]; then
	echoerr "no or too many running LXC containers found, aborting"
	exit
fi

echoinfo "Container found (${containers[0]}), adding blockdevice /dev/$usb_disk to container"
lxc-device -n ${containers[0]} add /dev/"$usb_disk"
