#!/usr/bin/env bash
# This is a recipe; not a script. You should try to run it chunk by chunck.
# The shebang is only for syntax highlighting

# Chroot
## Please, run this right after running script 00
mount -o defaults,noatime,compress=zstd,autodefrag,subvol=root /dev/vda3 /mnt/gentoo

## create dirs for mounts
cd /mnt/gentoo
mkdir srv home root var boot

## mount
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=home /dev/vda4 /mnt/gentoo/home
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=srv /dev/vda4 /mnt/gentoo/srv
mount -o defaults,relatime,compress=zstd,autodefrag,subvol=var /dev/vda4 /mnt/gentoo/var
mount -o defaults,relatime /dev/vda2 /mnt/gentoo/boot

### efi partition
mount -o defaults,noatime /dev/vda1 /mnt/gentoo/boot/efi

## get gentoo stage3
curl -LO https://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc/stage3-amd64-desktop-openrc-20220130T170547Z.tar.xz

## uncompress
tar -xapf stage3-amd64-desktop-openrc-20220130T170547Z.tar.xz
rm -f $_

## mount proc, sys and dev
mount -t proc none proc
mount --rbind /sys sys
mount --rbind /dev dev

## activate swap
swapon /dev/vda3

## get dns
cp -u /etc/resolv.conf /mnt/gentoo/etc/

## chroot
env -i HOME=/root TERM=$TERM chroot . bash -l

## environment
source /etc/profile
export PS1="(chroot) $PS1"

## emerge
emaint -A sync
emerge --oneshot portage

# Setup
cat << 'EOF' > /etc/fstab
# <fs>      <mountpoint>    <type>  <opts>                                              <dump/pass>

shm         /dev/shm        tmpfs   nodev,nosuid,noexec                                 0 0

/dev/vda4   /               btrfs   rw,noatime,compress=zstd:1,autodefrag,subvol=root   0 0
/dev/vda4   /home           btrfs   rw,noatime,compress=zstd:1,autodefrag,subvol=home   0 0
/dev/vda4   /srv            btrfs   rw,noatime,compress=zstd:1,autodefrag,subvol=srv    0 0
/dev/vda4   /var            btrfs   rw,noatime,compress=zstd:1,autodefrag,subvol=var    0 0
/dev/vda3   none            swap    sw                                                  0 0
/dev/vda2   /boot           btrfs   rw,noatime                                          1 2
/dev/vda1   /boot/efi       btrfs   noauto,noatime                                      0 2

EOF


## local time in MX
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

## add cpu flags
emerge app-portage/cpuid2cpuflags
cpu_flags=$( cpuid2cpuflags | cut -d ' ' -f '2-' )

## append to my make.conf
use_remove='-systemd -emacs -xemacs -accessibility -altivec -aqua -connman -coreaudio -ibm -infiniband -mule -neon -yahoo'
use_add='vim-syntax X opengl nvidia'
make_opts="-j$(( $( nproc ) + 0 ))"

cat << EOF > /etc/portage/make.conf
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
CHOST="x86_64-pc-linux-gnu"
CPU_FLAGS_X86="${cpu_flags}"

GRUB_PLATFORMS="efi-64"

VIDEO_CARDS="intel nvidia"

#Enable this if you like living on the edge
ACCEPT_KEYWORDS="~amd64"
MAKEOPTS="${make_opts}"

ADD="${use_add}"
REMOVE="${use_remove}"
USE="\$REMOVE \$ADD"

# Portage Opts
#FEATURES="parallel-fetch parallel-install ebuild-locks"
#EMERGE_DEFAULT_OPTS="--with-bdeps=y"
#AUTOCLEAN="yes"


EOF

## set profiles
sleep 20
eselect profile set default/linux/amd64/17.1/desktop

## update everything and cleanup
emerge -DNju @world
emerge -c

## install commonly used tools
#cat << 'EOF' > /etc/portage/package.use/os-prober
#>=sys-boot/grub-2.06-r1 mount

#EOF

emerge -DNju vim bash-completion btrfs-progs
emerge -DNju app-portage/eix app-portage/gentoolkit sys-process/htop sys-process/lsof

## install vanilla sources and genkernel-next
mkdir -p /etc/portage/package.license

cat << 'EOF' > /etc/portage/package.license/linux-firmware
sys-kernel/linux-firmware linux-fw-redistributable no-source-code

EOF

emerge -DNju genkernel sys-kernel/gentoo-sources sys-kernel/linux-firmware

## Remember to enable:
## 	 * all virtio devices; at least: virtio_pci and virtio_blk
##	 * btrfs support
genkernel --menuconfig --btrfs --virtio all

# Configure real root and stuff
vim /etc/default/grub

## install grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi

# update grub
grub-mkconfig -o /boot/grub/grub.cfg

## DHCP
cat << 'EOF' > /etc/systemd/network/20-default.network
[Match]
Name = enp*

[Network]
DHCP = yes

EOF

# set root password
passwd

# reboot (and pray, think wishfully, cross your fingers or whatever you do to influence reality... not!)
reboot
