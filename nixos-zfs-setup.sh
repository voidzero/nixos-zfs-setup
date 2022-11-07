#
# Edit the variables below. Then run this by issuing:
# `bash ./nixos-zfs-setup.sh`
#
# WARNING: this script will clear partition tables of existing disks.
# Make sure that you set the DISK variable correctly. Additionally, it
# is a good idea to clean your disk(s) current partitions first. Use the
# command `wipefs` for this.
#
###############################################################################
#    nixos-zfs-setup.sh: a bash script that sets up zfs disks for NixOS.      #
#      Copyright (C) 2022  Mark (voidzero) van Dijk, The Netherlands.         #
#                                                                             #
#    This program is free software: you can redistribute it and/or modify     #
#    it under the terms of the GNU General Public License as published by     #
#    the Free Software Foundation, either version 3 of the License, or        #
#    (at your option) any later version.                                      #
#                                                                             #
#    This program is distributed in the hope that it will be useful,          #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#    GNU General Public License for more details.                             #
#                                                                             #
#    You should have received a copy of the GNU General Public License        #
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.   #
###############################################################################

set -ex

DISK=(/dev/vda)
#DISK=(/dev/vda /dev/vdb)

# How to name the partitions. This will be visible in 'gdisk -l /dev/disk' and
# in /dev/disk/by-partlabel.
PART_MBR="bootcode"
PART_EFI="efiboot"
PART_BOOT="bpool"
PART_SWAP="swap"
PART_ROOT="rpool"

# How much swap per disk?
SWAPSIZE=2G

# The type of virtual device for boot and root. If kept empty, the disks will
# be joined (two 1T disks will give you ~2TB of data). Other valid options are
# mirror, raidz types and draid types. You will have to manually add other
# devices like spares, intent log devices, cache and so on. Here we're just
# setting this up for installation after all.
#ZFS_BOOT_VDEV="mirror"
#ZFS_ROOT_VDEV="mirror"

# How to name the boot pool and root pool.
ZFS_BOOT="bpool"
ZFS_ROOT="rpool"

# How to name the root volume in which nixos will be installed.
# If ZFS_ROOT is set to "rpool" and ZFS_ROOT_VOL is set to "nixos",
# nixos will be installed in rpool/nixos, with a few extra subvolumes
# (datasets).
ZFS_ROOT_VOL="nixos"

# Generate a root password with mkpasswd -m SHA-512
ROOTPW=''

# End of settings.

set +x
if [[ ${#DISK[*]} -eq 1 ]] && [[ -n ${ZFS_BOOT_VDEV} || -n ${ZFS_ROOT_VDEV} ]]
then
	echo "Error: You have only specified one disk. ZFS_BOOT_VDEV and ZFS_ROOT_DEV must be unset or empty." >&2
	false
fi

if [[ -z ${ROOTPW} ]]
then
	echo "Error: Please generate a password hash and put that in this file's ROOTPW variable." >&2
	false
fi

set -x

i=0
for d in ${DISK}
do
	sgdisk --zap-all ${d}
	sgdisk -a1 -n1:0:+100K -t1:EF02 -c 1:${PART_MBR}${i} ${d}
	sgdisk -n2:1M:+1G -t2:EF00 -c 2:${PART_EFI}${i} ${d}
	sgdisk -n3:0:+4G -t3:BE00 -c 3:${PART_BOOT}${i} ${d}
	sgdisk -n4:0:+${SWAPSIZE} -t4:8200 -c 4:${PART_SWAP}${i} ${d}
	sgdisk -n5:0:0 -t5:BF00 -c 5:${PART_ROOT}${i} ${d}

	partprobe ${d}
	(( i++ )) || true
done
unset i d

# Wait for a bit to let udev catch up and generate /dev/disk/by-partlabel.
sleep 3s

# Create the boot pool
zpool create \
	-o compatibility=grub2 \
	-o ashift=12 \
	-o autotrim=on \
	-O acltype=posixacl \
	-O compression=lz4 \
	-O devices=off \
	-O normalization=formD \
	-O relatime=on \
	-O xattr=sa \
	-O mountpoint=none \
	-O checksum=sha256 \
	-R /mnt \
	${ZFS_BOOT} ${ZFS_BOOT_VDEV} /dev/disk/by-partlabel/${PART_BOOT}*

# Create the root pool
zpool create \
	-o ashift=12 \
	-o autotrim=on \
	-O acltype=posixacl \
	-O compression=zstd \
	-O dnodesize=auto -O normalization=formD \
	-O relatime=on \
	-O xattr=sa \
	-O mountpoint=none \
	-O checksum=edonr \
	-R /mnt \
	${ZFS_ROOT} ${ZFS_ROOT_VDEV} /dev/disk/by-partlabel/${PART_ROOT}*

# Create the boot dataset
zfs create ${ZFS_BOOT}/${ZFS_ROOT_VOL}

# Create the root dataset
zfs create -o mountpoint=/     ${ZFS_ROOT}/${ZFS_ROOT_VOL}

# Create datasets (subvolumes) in the root dataset
zfs create ${ZFS_ROOT}/${ZFS_ROOT_VOL}/home
zfs create -o atime=off ${ZFS_ROOT}/${ZFS_ROOT_VOL}/nix
zfs create ${ZFS_ROOT}/${ZFS_ROOT_VOL}/root
zfs create ${ZFS_ROOT}/${ZFS_ROOT_VOL}/usr
zfs create ${ZFS_ROOT}/${ZFS_ROOT_VOL}/var

# Create datasets (subvolumes) in the boot dataset
# This comes last because boot order matters
zfs create -o mountpoint=/boot ${ZFS_BOOT}/${ZFS_ROOT_VOL}/boot

# Create, mount and populate the efi partitions
i=0
for d in ${DISK}
do
	mkfs.vfat -n EFI /dev/disk/by-partlabel/${PART_EFI}${i}
	mkdir -p /mnt/boot/efis/${PART_EFI}${i}
	mount -t vfat /dev/disk/by-partlabel/${PART_EFI}${i} /mnt/boot/efis/${PART_EFI}${i}
	(( i++ )) || true
done
unset i d

# Mount the first drive's efi partition to /mnt/boot/efi
mkdir /mnt/boot/efi
mount -t vfat /dev/disk/by-partlabel/${PART_EFI}0 /mnt/boot/efi

# Make sure we won't trip over zpool.cache later
mkdir -p /mnt/etc/zfs/
rm -f /mnt/etc/zfs/zpool.cache
touch /mnt/etc/zfs/zpool.cache
chmod a-w /mnt/etc/zfs/zpool.cache
chattr +i /mnt/etc/zfs/zpool.cache

# Generate and edit configs
nixos-generate-config --root /mnt

sed -i -e "s|./hardware-configuration.nix|& ./zfs.nix|" /mnt/etc/nixos/configuration.nix

tee -a /mnt/etc/nixos/zfs.nix <<EOF
{ config, pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "$(head -c 8 /etc/machine-id)";
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.zfs.devNodes = "/dev/disk/by-partlabel";
EOF

# Remove boot.loader stuff, it's to be added to zfs.nix
sed -i '/boot.loader/d' /mnt/etc/nixos/configuration.nix

# Disable xserver. Comment them without a space after the pound sign so we can
# recognize them when we edit the config later
sed -i -e 's;^  \(services.xserver\);  #\1;' /mnt/etc/nixos/configuration.nix

tee -a /mnt/etc/nixos/zfs.nix <<-'EOF'
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.generationsDir.copyKernels = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.copyKernels = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.zfsSupport = true;

  boot.loader.grub.extraPrepareConfig = ''
    mkdir -p /boot/efis
    for i in  /boot/efis/*; do mount $i ; done

    mkdir -p /boot/efi
    mount /boot/efi
  '';

  boot.loader.grub.extraInstallCommands = ''
    ESP_MIRROR=$(mktemp -d)
    cp -r /boot/efi/EFI $ESP_MIRROR
    for i in /boot/efis/*; do
      cp -r $ESP_MIRROR/EFI $i
    done
    rm -rf $ESP_MIRROR
  '';

  boot.loader.grub.devices = [
EOF

for d in ${DISK}; do
  printf "    \"${d}\"\n" >>/mnt/etc/nixos/zfs.nix
done

tee -a /mnt/etc/nixos/zfs.nix <<EOF
  ];

EOF

sed -i 's|fsType = "zfs";|fsType = "zfs"; options = [ "zfsutil" "X-mount.mkdir" ];|g' \
/mnt/etc/nixos/hardware-configuration.nix

ADDNR=$(awk '/^  fileSystems."\/" =$/ {print NR+3}' /mnt/etc/nixos/hardware-configuration.nix)
sed -i "${ADDNR}i"' \      neededForBoot = true;' /mnt/etc/nixos/hardware-configuration.nix

ADDNR=$(awk '/^  fileSystems."\/boot" =$/ {print NR+3}' /mnt/etc/nixos/hardware-configuration.nix)
sed -i "${ADDNR}i"' \      neededForBoot = true;' /mnt/etc/nixos/hardware-configuration.nix

tee -a /mnt/etc/nixos/zfs.nix <<EOF
users.users.root.initialHashedPassword = "${ROOTPW}";

}
EOF

set +x

echo "Now do this (preferably in another shell, this will put out a lot of text):"
echo "nixos-install -v --show-trace --no-root-passwd --root /mnt"
echo "umount -Rl /mnt"
echo "zpool export -a"
echo "reboot"
echo "Make note of these instructions because the nixos-install command will output a lot of text."

