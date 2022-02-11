# This is a script that will automatically install gentoo

# Ask user to make sure they are connected to the internet
echo "If you are not sure if your device is connected to the internet, hit control+c and use ifconfig to check if your network interface card has an ip address."
sleep 10

# Begin partitioning
## Ask for the amount of swap the user wants
echo "Enter the amout of swap you want:"
read swap_amt
swap_amt="${swap_amt}"
sgdisk -Zo /dev/vda
sgdisk -n 1::+1024M -t:ef02 /dev/vda
sgdisk -n 2::+${swap_amt}G -t 2:8200 /dev/vda
sgdisk -n 3:: -t 3:8300 /dev/vda

# Making the filesystems
mkfs.vfat -n boot -F 32 /dev/vda1
mkswap /dev/vda2
mkfs.btrfs -L btrfsroot /dev/vda3
swapon /dev/vda2

# Create subvols for btrfs
cd /mnt/gentoo
btrfs subvol create root
btrfs subvol create home
btrfs subvol create srv
btrfs subvol create var

## Create dirs for mounts
mkdir srv home root var boot

# Mounts
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=home /dev/vda3 /mnt/gentoo/home
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=srv /dev/vda3 /mnt/gentoo/srv
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=var /dev/vda3 /mnt/gentoo/var


# Mount the root partition
mount -o defaults,noatime,compress=zstd,autodefrag,subvol=root /dev/vda3 /mnt/gentoo/

# Get the stage3 version (latest as of 2-11-2022; may need to be modified when a newer version is released)
# I am not skilled enough yet to make it so it will always grab the latest stage3
curl -LO https://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20220130T170547Z.tar.xz

# Unpack the stage3 tarball
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Remove pre-generated COMMON_FLAGS from make.conf
sed '/^COMMON_FLAGS/d' < /mnt/gentoo/etc/portage/make.conf > /mnt/gentoo/etc/portage/make.conf

# Append desired options to make.conf
cat << EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-march=native -O2 -pipe"
GRUB_PLATFORMS="efi-64"

USE="-systemd -emacs -xemacs -accessibility -altivec -aqua -connman -coreaudio -ibm -infiniband -mule -neon -yahoo vim-syntax X opengl nvidia"

VIDEO_CARDS="intel nvidia"

ACCEPT_LICENSE="*"

#Enable this if you like living on the edge
ACCEPT_KEYWORDS="~amd64"

make_opts="-j$(( $( nproc ) + 0 ))"
MAKEOPTS="${make_opts}"

GENTOO_MIRRORS="http://www.gtlib.gatech.edu/pub/gentoo https://gentoo.osuosl.org/ http://gentoo.osuosl.org/ https://mirrors.rit.edu/gentoo/ http://mirrors.rit.edu/gentoo/ http://gentoo.mirrors.tds.net/gentoo"


EOF

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
mount /dev/vda1 /boot

# Sync Portage
emerge-webrsync

# Choose a profile
eselect profile set default/linux/amd64/17.1/desktop

# Update @world set
echo "Read a book, because it is compile time baby!"
sleep 2
emerge -avuDN @world

# Set timezone
echo "Time to choose a timezone (use ctrl+alt+f# to go to another tty if need be)"
ls /usr/share/zoneinfo
sleep 5
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
