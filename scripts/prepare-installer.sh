#! /bin/sh
#
# Prepare install.img for booting FreeBSD on Scaleway C2 servers.
#
# NOTE: This script is currently incomplete! USE AT YOUR OWN RISK!
#
# You will likely have to customize a few parts of this script
# in order for it to be at all useful.

echo "Sorry, this script is not finished yet."
exit 1

set -x

#
# Working paths
#

TMP_DIR=/tmp/scw-freebsd
INSTALL_MNT=/media/install
REPO=$(cd "$(dirname "${0}")/.." && pwd)

#
# Image location for fetch
#

FTP_PROTO=ftp
FTP_HOST=ftp.freebsd.org
FTP_PATH=pub/FreeBSD/releases/amd64/amd64/ISO-IMAGES/11.1
MINI_MEMSTICK_ARCHIVE=FreeBSD-11.1-RC3-amd64-mini-memstick.img.xz
MINI_MEMSTICK_CHECKSUM=CHECKSUM.SHA512-FreeBSD-11.1-RC3-amd64

#
# Check for missing build packages
#
missing=0
hash git || { echo "missing git"; : $((missing += 1)) }
hash gmake || { echo "missing gmake"; : $((missing += 1)) }
if [ ${missing} -gt 0 ]
then
  echo "Please install missing tools"
  exit 1
fi

#
# Move into the temporary work path
#

mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"

#
# Fetch the mini memstick image
#

ftp_prefix=${FTP_PROTO}://${FTP_HOST}/${FTP_PATH}
mini_url=${ftp_prefix}/${MINI_MEMSTICK_ARCHIVE}
checksum_url=${ftp_prefix}/${MINI_MEMSTICK_CHECKSUM}
mini_img=${MINI_MEMSTICK_ARCHIVE%.xz}

[ -e ${mini_img} ] || {
    [ -e ${MINI_MEMSTICK_CHECKSUM} ] ||
        fetch "${checksum_url}" || exit 1
    [ -e ${MINI_MEMSTICK_ARCHIVE} ] ||
        fetch "${mini_url}" || exit 1
    checksum=$(grep ${MINI_MEMSTICK_ARCHIVE} ${MINI_MEMSTICK_CHECKSUM})
    [ "$(sha512 ${MINI_MEMSTICK_ARCHIVE})" = "${checksum}" ] || exit 1
    unxz ${MINI_MEMSTICK_ARCHIVE}
}

#
# Attach the mini memstick image and extract the root filesystem from it
#

mini_md=$(mdconfig -a ${mini_img})

dd if=/dev/${mini_md}p3 of=rootfs bs=1m
mdconfig -du ${mini_md}

#
# Create a raw disk image for booting the installer
#

truncate -s 256M install.img

#
# Attach the disk image and root filesystem image
#

img_mnt="${INSTALL_MNT}/img"
root_mnt="${INSTALL_MNT}/root"

mkdir -p "${img_mnt}" "${root_mnt}"

img_md=$(mdconfig -a install.img)
root_md=$(mdconfig -a rootfs)

#
# Partition the disk image, install bootcode, and create a filesystem
#

gpart create \
  -s gpt \
  ${img_md}

gpart add \
  -t freebsd-boot \
  -l boot \
  -s 512K \
  ${img_md}

gpart bootcode \
  -b "${root_mnt}/boot/pmbr" \
  -p "${root_mnt}/boot/gptboot" \
  -i 1 \
  ${img_md}

gpart add \
  -t freebsd-ufs \
  -l rootfs \
  ${img_md}

img_part=${img_md}p2

newfs -L install ${img_part}

#
# Mount the root filesystem and the disk image
#

mount /dev/${root_md} "${root_mnt}"
mount /dev/${img_part} "${img_mnt}"

#
# Build nbd-init
#

[ -d nbd-init ] ||
    git clone --branch simplify https://github.com/freqlabs/nbd-init.git
cd nbd-init
make
cd ..

#
# Build nbd-client
#

[ -d nbd-client ]||
    git clone --branch loop-state-machine-casper https://github.com/freqlabs/nbd-client.git
cd nbd-client
make LDFLAGS=-static
cd ..

#
# Build scw-update-server-state
#

[ -d initrd ] ||
    git clone https://github.com/freqlabs/initrd.git
cd initrd/scw-boot-tools
gmake TARGET=amd64
cd ../..

#
# Obtain scw-metadata and scw-userdata
#

[ -d image-tools ] ||
    git clone https://github.com/freqlabs/image-tools.git
image_tools_local=image-tools/skeleton-common/usr/local

#
# Create a symlink to the source repo, for scripts and configs
#

ln -sf "${REPO}" repo

#
# Create the scaleway package
#

mkdir -p \
  scaleway/bin \
  scaleway/etc/rc.d \
  scaleway/sbin \
  scaleway/usr/sbin
cp ${image_tools_local}/bin/scw-metadata scaleway/bin/
cp repo/scripts/system/rc.d/scaleway scaleway/etc/rc.d/
cp initrd/scw-boot-tools/amd64-scw-update-server-state scaleway/sbin/scw-update-server-state
cp nbd-client/nbd-client scaleway/sbin/
cp ${image_tools_local}/sbin/scw-userdata scaleway/usr/sbin/
cd scaleway
tar -acf scaleway.txz *
checksum=$(sha256 -q scaleway.txz)
size=$(stat -f "%z" scaleway.txz)
cd ..

#
# Copy the scaleway package to the installer filesystem and make a MANIFEST
#

cp scaleway/scaleway.txz "${root_mnt}/usr/freebsd-dist/"
cd "${root_mnt}/usr/freebsd-dist"
printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
  "scaleway.txz" \
  "${checksum}" \
  "${size}" \
  "scaleway" \
  "Scaleway scripts and utilities (MANDATORY)" \
  "on" \
  > MANIFEST
cd "${TMP_DIR}"

#
# Copy extra scripts and utilities to the installer filesystem
#

cp scaleway/bin/scw-metadata "${root_mnt}/bin/"
cp repo/scripts/install/rc.d/* "${root_mnt}/etc/rc.d/"
cp repo/scripts/install/rc.local "${root_mnt}/etc/"
cp scaleway/sbin/scw-update-server-state "${root_mnt}/sbin/"
cp scaleway/sbin/nbd-client "${root_mnt}/sbin/"
cp scaleway/usr/sbin/scw-userdata "${root_mnt}/usr/sbin"

#
# Patch bsdinstall to add GEOM Gate support
#

patch -u -p2 -d "${root_mnt}" < repo/patches/bsdinstall.patch

#
# Populate the boot image
#

mkdir -p "${img_mnt}/boot/kernel"
#cp -a "${root_mnt}/boot/
# TODO: everything else
