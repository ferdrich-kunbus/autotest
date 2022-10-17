#!/usr/bin/env bash

set +x

absdirname () { echo "$(cd "$(dirname "$1")" && pwd)"; }
SRC_ROOT="$(absdirname "${BASH_SOURCE[0]}")"

whoami
ls -l /lava-lxc

# include echo helper
# shellcheck disable=SC1091
. "$SRC_ROOT/tools/echohelper.sh"

PWD=$(pwd)

echo "$LAVA_STATIC_INFO_0_usb_path"
#./rpiboot -p "${LAVA_STATIC_INFO_0_usb_path:?}"

# find image and extract
cd /lava-lxc || exit

ARCHIVE=$(find . -iname "*tar*")
tar xzvf "$ARCHIVE"
rm "$ARCHIVE"

IMAGE=$(find /lava-lxc -iname "*.img")
echo "$IMAGE"
ls -l
echoinfo "please wait, calculating md5sum for image"
md5_img=$(md5sum "$IMAGE" | awk '{ print $1 }' )

usb_disk=$(find /sys/devices -iname "${LAVA_STATIC_INFO_0_usb_path:?}" -exec find {} -iname block -print0 \; 2>/dev/null | xargs -0 ls)
disk=$(lsblk -I 8 -dno NAME,RM | awk '{ if  ($2 == 1) { print $1 } }')

if [ ! "$usb_disk" == "$disk" ]; then
    echoerr "Blockdevice from lsblk and sysfs are differend ($disk - $usb_disk)"
    exit 1
fi

fdisk -l "/dev/$disk"

echoinfo "programming the image on storage device /dev/$disk"
dd if="$IMAGE" of="/dev/$disk" bs=64k status=progress conv=sync
sync

echoinfo "verifying disk vs image"
md5_disk=$(dd if="/dev/$disk" bs=64k count="$(stat -c %s "$IMAGE")" iflag=count_bytes status=progress | md5sum | awk '{ print $1 }' )
echo "$md5_img"
echo "$md5_disk"

if [[ "$md5_img" != "$md5_disk" ]]; then
  echoerr "image on disk seems to have errors"
fi

cd "$PWD" || exit
