# This is a script that will automatically install gentoo

# Create directories
mkdir -p /mnt/gentoo/

# Begin partitioning
## Ask for the amount of swap the user wants
echo "Enter the amout of swap you want: (The recommended amount is double the amount of ram you have.)"
read swap_amt
swap_amt="${swap_amt}"
sgdisk -Zo /dev/vda
sgdisk -n 1::+1024M -t 1:ef00 /dev/vda
sleep 2
sgdisk -n 2::+${swap_amt}G -t 2:8200 /dev/vda
sleep 2
sgdisk -n 3:: -t 3:8300 /dev/vda
sleep 4

# Making the filesystems
echo "Making the filesystems"
mkfs.vfat -n boot -F 32 /dev/vda1
sleep 2
mkswap -L swap /dev/vda2
sleep 2
mkfs.ext4 -L root /dev/vda3
sleep 2
swapon /dev/vda2
sleep 4

# Mount
## Root
mount /dev/vda3 /mnt/gentoo/

# cd into /mnt/gentoo/
echo "cd into /mnt/gentoo/"
sleep 1
cd /mnt/gentoo/

# Make the boot dir
mkdir -p /mnt/gentoo/boot

# Get the stage3 version (latest as of 2-11-2022; may need to be modified when a newer version is released)
# I am not skilled enough yet to make it so it will always grab the latest stage3
echo "Select the \"desired\" stage3."
links https://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/

# Unpack the stage3 tarball
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Remove pre-generated COMMON_FLAGS from make.conf
cd /mnt/gentoo
sed '/^COMMON_FLAGS/d' < /etc/portage/make.conf > /etc/portage/make.conf

# Append desired options to make.conf
cat < ~/deploygentoo-master/ext4GentooInstall/make_append.txt >> /etc/portage/make.conf

# Configure the repo
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

# Copy dns info
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
echo "nameserver 192.168.1.124" >> /mnt/gentoo/etc/resolv.conf

# Mount filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

# Chroot
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"

# Mount boot partition
mount -o defaults,noatime /dev/vda1 /boot

# Sync Portage
emerge-webrsync

# Choose a profile
eselect profile list
echo "Select a profile:"
sleep 5
read profile_set
profile_set="${profile_set}"
eselect profile set ${profile_set}

# Update @world set
echo "Read a book, because it is time to compile baby!"
sleep 2
emerge -avuDN @world

# Set timezone
echo "Time to choose a timezone (use ctrl+alt+f# to go to another tty if need be)"
ls /usr/share/zoneinfo
sleep 10
echo "Make sure to put double quotes around your selection EX: \"America/Detroit\""
read timezone
timezone="${timezone}"
echo $timezone > /etc/timezone
## Configure timezone-data
emerge --config sys-libs/timezone-data

# Configure locales
echo "For EN locales, use en_US ISO-8859-1 and en_US.UTF-8 UTF-8"
sleep 10
nano -w /etc/locale.gen
## Run locale-gen to gen locales
locale-gen

# ESelect locale
eselect locale list
echo "Select a locale using the number next to the entries"
sleep 20
read locale_selection
locale_selection="${locale_selection}"
eselect locale ${locale_selection}

# Reload the environment
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

# Install firmware/microcode
emerge -a sys-kernel/linux-firmware

# Install kernel sources
emerge -a sys-kernel/gentoo-sources

# Forgo a custom kernel configuration for now for debug purposes. May be changed later. A custom kernel can be created after installing gentoo.
emerge -a sys-kernel/genkernel

# Setup /etc/fstab
cat << EOF > /etc/fstab
# <fs>      <mountpoint>    <type>  <opts>                                              <dump/pass>

#shm         /dev/shm        tmpfs   nodev,nosuid,noexec                                 0 0

/dev/vda3   /               ext4   rw,noatime,defaults,discard                          0 1
/dev/vda2   none            swap   sw                                                   0 0
/dev/vda1   /boot           vfat   defaults,noatime,discard                             0 2

EOF

# Genkernel configuration and build
echo "Remember to enable all virtio devices (at least virtio_pci and virtio_blk) and btrfs support."
sleep 5
genkernel --menuconfig --btrfs --virtio all

# List the names of the kernel and the initrd for when the bootloader config file is edited
ls /boot/vmlinu* /boot/initramfs*

# Configure the modules
## List the modules that need to be loaded
echo "The modules that need to be put into the modules-load.d dir will be listed."
sleep 3
find /lib/modules/*/ -type f -iname '*.o' -or -iname '*.ko' | less
mkdir -p /etc/modules-load.d
nano -w /etc/modules-load.d/modules.conf

# Set the hostname
echo "Enter the desired hostname in nano. EX: hostname=\"tux\""
sleep 5
nano -w /etc/conf.d/hostname

## Set domain name
echo "Enter the desired domain name. EX: dns_domain_lo=\"homenetwork\""
sleep 5
nano -w /etc/conf.d/net

# Install dhcpcd
emerge -a net-misc/dhcpcd
rc-update add dhcpcd default
rc-service dhcpcd start

# Create a STRONG root passwd
echo "Create a STRONG root passwd."
sleep 2
passwd

# Configure OpenRC
echo "Make changes to rc.conf as needed."
sleep 2
nano -w /etc/rc.conf
echo "Configure the keyboard."
sleep 2
nano -w /etc/conf.d/keymaps
echo "Configure the clock. Make sure clock=\"local\""
sleep 4
nano -w /etc/conf.d/hwclock

# Install a system logger
emerge -a app-admin/sysklogd

# Install cronie
emerge -a sys-process/cronie
## Enable cronie (cron)
rc-update add cronie default

# Install mlocate for better indexing
emerge -a sys-apps/mlocate

# Install btrfs-progs
emerge -a sys-fs/btrfs-progs

# Install grub
echo "Emerging grub."
emerge -a sys-boot/grub
## Configure
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

# Reboot
exit
cd
umount -l /mnt/gentoo/dev
umount -l /mnt/gentoo/run
umount -l /mnt/gentoo/proc
umount -l /mnt/gentoo/sys
echo "Rebooting in five seconds."
sleep 5
reboot

# Finalizing
