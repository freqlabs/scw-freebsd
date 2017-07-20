# Serial console setup
comconsole_speed="9600"
comconsole_port="0x2F8"
console="comconsole"

# Don't show the boot menu, don't delay
beastie_disable="YES"
loader_color="NO"
loader_logo="none"
autoboot_delay="-1"

# Use the disk image for the initial root filesystem
initmd_load="YES"
initmd_type="md_image"
initmd_name="/mfsroot"
vfs.root.mountfrom="ufs:/dev/md0"

# Load the ZFS modules in advance
zfs_load="YES"
