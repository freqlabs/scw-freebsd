#!/bin/sh -x
#
# Copyright (c) 2016 Ryan Moeller <ryan@freqlabs.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

# This script is a helper for working with the boot and install images for
# FreeBSD on Scaleway.  It gets to be a pain tweaking things manually.
#
# Be warned, this script is naive and will not handle unexpected
# situations well!
#
# Usage:
#
#   -  /media should exist and be writable by root
#
#   -  install.img or boot.img must exist in your working directory
#
#   -  this script must be run as root
#
#   -  mount the img and rootfs at /media/install/{img,root}:
#      ./image.sh attach install
#
#   -  modify the image in some way (be conscious of how much space you use)
#
#   -  unmount the img and rootfs and upload it to the web server:
#      ./image.sh detach install
#
# The instructions are the same for the boot image:
#
#   ./image.sh attach boot
#   # make modifications
#   ./image.sh detach boot
#

# Modify this function to fit your needs
upload()
{
	scp "${1}" "${UPLOAD_DESTINATION}"
}

mount_media()
{
	mount /dev/${1} ${mediadir}/${2}
}

umount_media()
{
	umount ${mediadir}/${1}
}

image_common()
{
	name=${1}
	root=${2}

	mediadir=/media/${name}
}

attach_common()
{
	mkdir -p ${mediadir}/img ${mediadir}/root

	img_md=$(mdconfig -a ${name}.img)
	mount_media ${img_md}p2 img

	gunzip ${root}.gz
	root_md=$(mdconfig -a ${root})
	mount_media ${root_md} root
}

install_attach()
{
	image_common install rootfs
	attach_common
}

boot_attach()
{
	image_common boot mfsroot
	attach_common
}

md_for_path()
{
	mdconfig -lv | awk -v path=${1} '$4 ~ path { print $1 }'
}

detach_common()
{
	root_md=$(md_for_path ${root})
	img_md=$(md_for_path ${name})

	umount_media root
	mdconfig -du ${root_md}	
	gzip -9 ${root}
	cp ${root}.gz ${mediadir}/img

	umount_media img
	mdconfig -du ${img_md}
	upload ${name}.img
}

install_detach()
{
	image_common install rootfs
	detach_common
}

boot_detach()
{
	image_common boot mfsroot
	detach_common
}

if [ "$(uname)" != "FreeBSD" ]
then
        echo "This script only works on FreeBSD"
        exit 1
fi

if [ "$(whoami)" != "root" ]
then
        echo "This script must be run as root"
        exit 1
fi

case "${1} ${2}" in

	"attach install") install_attach ;;
	"attach boot") boot_attach ;;
	"detach install") install_detach ;;
	"detach boot") boot_detach ;;
	*) echo "usage: ${0} attach|detach install|boot" ;;
esac
