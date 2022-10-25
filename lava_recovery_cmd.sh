#!/usr/bin/env bash

if [[ $# -ne 2 ]]; then
  echo "help: $0 <Relais-No> <on|onff>"
  exit
fi

absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

# include relaiscard helper functions
. "$SRC_ROOT/tools/relaiscard.sh"
# include echo helper
. "$SRC_ROOT/tools/echohelper.sh"
# include basic configuration
. "$SRC_ROOT/config.sh"

USBPORT=1
RELAISPORT=$1
CMD=$(echo "$2" | awk '{print tolower ($0)}')

RPIBOOT=$(which rpiboot)
UHUBCTL=$(which uhubctl)

echoinfo "check for availability of relais card"
if ! rc_get_status $ipaddr $port; then
  echoerr "relais card not reachable, stopping script"
  exit
fi

recovery_start() {
  echoinfo "Start Recovery"
        
  echo $LAVA_JOB_ID
  rc_set_relais "$ipaddr" "$port" "$RELAISPORT" 0
  "$UHUBCTL" -l "$usbhub_loc" -p "$USBPORT" -a on
  rc_set_relais "$ipaddr" "$port" 2 1
  sleep 0.5

  rc_set_relais "$ipaddr" "$port" "$RELAISPORT" 1
  sleep 0.5

  USBLOC="2-1.1"

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
}

recovery_exit() {
    echo "Stop Recovery"

    rc_set_relais "$ipaddr" "$port" "$RELAISPORT" 0
    "$UHUBCTL" -l "$usbhub_loc" -p "$USBPORT" -a off
    rc_set_relais "$ipaddr" "$port" 2 0
    sleep 0.5

    rc_set_relais "$ipaddr" "$port" "$RELAISPORT" 1
    sleep 0.5
}

case "$CMD" in
    on) recovery_start ;;
    off) recovery_exit ;;
    *) echo "only on and off are supported as parameter for recovery mode" && exit ;;
esac

