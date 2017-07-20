# FreeBSD on Scaleway

## Overview

Scaleway servers PXE boot their operating system and attach storage over NBD.
The boot process can be interrupted on the serial console, allowing an iPXE
script to be manually chainloaded.  This script is used to load a custom
FreeBSD disk image into memory and then chainload SYSLINUX [MEMDISK][memdisk].
With the addition of an NBD client, FreeBSD can be used comfortably on the
Scaleway platform.

MEMDISK is a handy shim that hooks some BIOS interrupts in order to boot from a
disk image in RAM as if it was a physical disk attached to the machine.  The
image is a simple [mfsbsd][mfsbsd]-style raw disk, partitioned with a small
freebsd-boot partition for bootloader code and a larger UFS partition.

The UFS partition contains boot configuration files, the kernel, and a
compressed root filesystem image.  This image is decompressed and preloaded by
the bootloader, then attached as an `md(4)` disk and used to mount the root
filesystem from during kernel startup.

Two root filesystems are presented here: an automated installer based on the
mini-memstick image, and an extremely minimal image that acts as an initrd.
Both include tools for attaching NBD volumes, signaling the Scaleway backend
about server state, and interacting with metadata and userdata in the Scaleway
API.

The example installer image sets up the system with a few extras out of the
box, including tmux, bash, sudo, curl, some hardening options, and an alternate
account for administration

The example boot image runs a modified init that remounts the root filesystem
from a ZFS pool after attaching the storage volumes.

[memdisk]: http://www.syslinux.org/wiki/index.php?title=MEMDISK
[mfsbsd]: http://mfsbsd.vx.sk/
[rerooting]: https://www.freebsd.org/cgi/man.cgi?query=reboot#end

## Quick Start

```
server=$(scw create --commercial-type=C2S 50G)
scw attach $(scw start ${server})
```

Now pay attention, and start mashing ctrl-b when you see iPXE start loading.
At the iPXE> prompt:

```
dhcp
chain http://scw.freqlabs.com/install
```

FreeBSD will boot and automatically install to the storage volume.  When the
installation completes and the server reboots, pay attention and break to the
iPXE prompt again, then run the boot script:

```
dhcp
chain http://scw.freqlabs.com/boot
```

Press ctrl-q to exit the serial console, then ssh into the server:

```
server_address=$(scw inspect -f "{{ .PublicAddress.IP }}" ${server})
sshd_port=$(scw _userdata SSHD_PORT ${server})

ssh -p ${sshd_port} serveradmin@${server_address}
```

## Step by Step

### Prerequisites

The [scaleway-cli][scaleway-cli] tool is highly recommended.  The HTML5 console
on the Scaleway control panel periodically types 'n' during the boot process,
making it difficult to enter the iPXE commands to chainload the boot script.
This is not a problem when using the `scw` CLI tool.

If this is your first time setting up `scaleway-cli` on your system, be sure to
log in before continuing with these instructions:

```
scw login
```

Examples and instructions for creating your own custom images and boot scripts
are included in this repository, but for a quick demo you may use the boot
server in this example.  _This server is for demonstration purposes only and
may cease to exist at any time._

[scaleway-cli]: https://github.com/scaleway/scaleway-cli

### Creating a server

Start by creating a small bare metal x86\_64 server with a 50G storage volume:

```
scw create --commercial-type=C2S 50G
```

The UUID of the new server is printed as the output of this command.

### (optional) Choosing the sshd port

The example installer script selects a random high-numbered port for sshd to
listen on.  This can be overriden by specifying a port explicitly in the server
userdata before installation:

```
scw _userdata ${server} SSHD_PORT=22
```

### Installing FreeBSD

Since Scaleway does not provide preinstalled FreeBSD images, the next step is
to install the operating system.  This is accomplished by booting the server
with the `install` iPXE script.

First, start the server and attach to the serial console:

```
scw attach $(scw start ${server})
```

Now patiently wait for the BIOS protection delay, and when the PXE ROM starts
to load, break to the iPXE prompt by pressing `ctrl-b` at precisely the right
moment, or alternatively by repeatedly mashing the combo until the `iPXE>`
prompt appears.

At the prompt, run the commands to get a DHCP lease and chainload the install
script:

```
dhcp
chain http://scw.freqlabs.com/install
```

Pay attention as the installer finishes.  When the server reboots, break to the
iPXE prompt again.

### Booting the Installation

It is necessary to manually chain load the `boot` script for FreeBSD every time
the server boots.  Hopefully Scaleway add customizable bootscripts in the near
future.  Until then, boot FreeBSD by entering at the iPXE prompt:

```
dhcp
chain http://scw.freqlabs.com/boot
```

The serial console can now be exited by pressing `ctrl-q`

## Caveats

- Booting is a manual process until Scaleway support custom bootscripts
- Shutdown/reboot hangs when the NBD clients are killed
- No warranty
