# Copyright 2016 Palmer Dabbelt <palmer@dabbelt.com>
# 
# Sets up one of my computers.

# This target updates the computer.
.PHONY: update
update: var/lib/palmer/update.stamp

# Does all the pre-chroot steps for when you're installing a new system.
.PHONY: preinstall
preinstall: var/lib/palmer/preinstall.stamp

# Synchronizes the portage database with upstream.
.PHONY: sync
sync::
	emaint sync -A
	date > var/lib/palmer/sync.stamp
	$(MAKE)

# This Makefile is configured by creating a Makefile.config.  Users need to do
# this in order to specify which machine is being setup.
ifeq ($(wildcard Makefile.config),)
$(error No Makefile.config provided)
endif
include Makefile.config

ifeq ($(CONFIG_HOSTNAME),)
$(error Makefile.config should set CONFIG_HOSTNAME)
endif

include etc/palmer/makefrags/host-$(CONFIG_HOSTNAME).mk

ifeq ($(CONFIG_USE),)
$(error etc/palmer/makefrags/host-$(CONFIG_HOSTNAME).mk needs to set CONFIG_USE)
endif

ifeq ($(CONFIG_PLATFORM),)
$(error etc/palmer/makefrags/host-$(CONFIG_HOSTNAME).mk needs to set CONFIG_PLATFORM)
endif

# It's expected that these variables will change over time as various versions
# of things get bumped.
STAGE3_VERSION = 20161215
KERNEL_VERSION = 4.4.39

###############################################################################
# Pre-Install
###############################################################################

# Ensures the system's clock is correct.
var/lib/palmer/preinstall-ntpdate.stamp:
	ntpdate -b -u pool.ntp.org
	date > $@

# Downloads and extracts a stage3 tarball.
var/lib/palmer/stage3-amd64.tar.bz: /usr/bin/wget var/lib/palmer/preinstall-ntpdate.stamp
	@mkdir -p $(dir $@)
	$< http://cosmos.illinois.edu/pub/gentoo/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-$(STAGE3_VERSION).tar.bz2 -O $@
	touch $@

var/lib/palmer/preinstall-stage3-extract.stamp: var/lib/palmer/stage3-amd64.tar.bz
	tar -xjpf $<
	date > $@

# Copies DNS from the the host machine
etc/resolv.conf: /etc/resolv.conf
	cp -L $< $@

# Mounts the various Gentoo directories
var/lib/palmer/preinstall-mount.stamp: /etc/mtab var/lib/palmer/preinstall-stage3-extract.stamp
	mount -t proc proc proc
	mount --rbind /sys sys
	mount --make-rslave sys
	mount --rbind /dev dev
	mount --make-rslave dev
	date > $@

var/lib/palmer/preinstall.stamp: \
		var/lib/palmer/preinstall-stage3-extract.stamp \
		var/lib/palmer/preinstall-mount.stamp \
		etc/resolv.conf
	date > $@

###############################################################################
# Install
###############################################################################

# Regenerates the localtime variable whenever any timezone stuff changes, and
# allows it to be initialized on new systems.
etc/localtime: \
		etc/timezone \
		$(shell find usr/share/zoneinfo -type f) \
		var/lib/palmer/update-portage.stamp
	emerge --config sys-libs/timezone-data	

etc/timezone:
	@mkdir -p $(dir $@)
	echo "America/Los_Angeles" > $@

# Sets up the profile symlink.  I always just use the default one.
etc/portage/make.profile: var/lib/palmer/sync.stamp
	eselect profile set 1
	touch $@

# Sets up my locales
etc/locale.gen: var/lib/palmer/preinstall-stage3-extract.stamp
	@mkdir -p $(dir $@)
	echo -e "en_US ISO-8859-1\nen_US.UTF-8 UTF-8" > $@

usr/share/i18n/locales/en_US: etc/locale.gen
	@mkdir -p $(dir $@)
	locale-gen
	touch $@

etc/env.d/02locale: var/lib/palmer/preinstall-stage3-extract.stamp
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	echo 'LANG="en_US.UTF-8"' >> $@
	echo 'LC_COLLATE="C"' >> $@

# I generate a fstab, which is currently static because I'm lazy...
etc/fstab: var/lib/palmer/preinstall-stage3-extract.stamp
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	echo "/dev/sda1 /boot vfat ro 0 2" >> $@
	echo "/dev/mapper/crypt-sda2 / btrfs subvol=roots/gentoo,discard 0 1" >> $@
	echo "/dev/mapper/crypt-sda2 /media/internal btrfs discard 0 1" >> $@
	echo "/dev/mapper/crypt-sdb1 /media/array btrfs compress=zlib,discard 0 1" >> $@
	echo "/dev/mapper/crypt-sdb1 /home btrfs subvol=homes,compress=zlib,discard 0 1" >> $@
	echo "/dev/mapper/crypt-sdb1 /global btrfs subvol=global,compress=zlib,discard 0 1" >> $@
	echo "/dev/mapper/crypt-sdb1 /var/lib/transmission btrfs subvol=torrent,compress=zlib,discard 0 1" >> $@

etc/conf.d/hostname: var/lib/palmer/preinstall-stage3-extract.stamp
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	echo "hostname=\"$(CONFIG_HOSTNAME)\"" > $@

etc/conf.d/net: var/lib/palmer/preinstall-stage3-extract.stamp
	echo "# autogenerated do not edit" > $@
	echo "config_enp2s0=\"dhcp\"" >> $@

etc/%: etc/palmer/overlay/etc/%
	@mkdir -p $(dir $@)
	cat $< | sed 's/@@HOSTNAME@@/$(CONFIG_HOSTNAME)/g' > $@

var/lib/palmer/install.stamp: \
		etc/localtime \
		usr/share/i18n/locales/en_US \
		etc/env.d/02locale \
		etc/portage/make.profile \
		etc/fstab \
		etc/conf.d/hostname \
		etc/conf.d/net \
		$(patsubst etc/palmer/overlay/%,%,$(find etc/palmer/overlay -type f))
	date > $@

###############################################################################
# Update
###############################################################################

var/lib/palmer/update.stamp: \
		var/lib/palmer/install.stamp \
		var/lib/palmer/update-portage.stamp \
		var/lib/palmer/update-world.stamp \
		boot/vmlinux-$(KERNEL_VERSION)-gentoo \
		boot/grub/grub.cfg
	date > $@

# Generates a simple but sane make.conf.
etc/portage/make.conf: \
		etc/palmer/make.conf.d/__base__ \
		$(addprefix etc/palmer/make.conf.d/use-,$(CONFIG_SYSTEM_USE)) \
		$(addprefix etc/palmer/make.conf.d/platform-,$(CONFIG_PLATFORM))
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	echo "MAKEOPTS=\"-j`cat /proc/cpuinfo | grep -c ^processor`\"" >> $@
	cat $< >> $@

etc/portage/repos.conf: $(wildcard etc/palmer/repos.conf.d/*)
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

etc/portage/package.keywords: $(wildcard etc/palmer/keywords/*)
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

# Produces a package set
var/lib/portage/world: \
		etc/palmer/sets/__base__ \
		$(addprefix etc/palmer/sets/use-,$(CONFIG_USE)) \
		$(addprefix etc/palmer/sets/platform-,$(CONFIG_PLATFORM))
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

# Synchronizes the portage database with upstream, which will trigger another
# update.
var/lib/palmer/sync.stamp: \
		etc/portage/repos.conf \
		etc/portage/make.conf
	emaint sync -a
	date > $@

# Updates portage, which is supposed to be the first thing that happens
# whenever something is synchronized.  This step is smart enough to do nothing
# if there isn't a real portage update, so it'll just get run every time.
var/lib/palmer/update-portage.stamp: \
		etc/portage/make.profile \
		var/lib/palmer/sync.stamp
	emerge -u1 portage
	date > $@

# Updates the rest of the packages on the system.
var/lib/palmer/update-world.stamp: \
		var/lib/portage/world \
		etc/portage/package.keywords \
		var/lib/palmer/update-portage.stamp \
		etc/portage/make.profile \
		var/lib/palmer/sync.stamp
	emerge -vNDu @world
	emerge @preserved-rebuild
	emerge --depclean
	date > $@

# Linux
usr/src/linux-$(KERNEL_VERSION)-gentoo/.config: \
		var/lib/palmer/update-world.stamp \
		etc/palmer/linux.config
	$(MAKE) -C $(dir $@) defconfig
	cat etc/palmer/linux.config >> $@
	$(MAKE) -C $(dir $@) olddefconfig

usr/src/linux-$(KERNEL_VERSION)-gentoo/vmlinux: \
		usr/src/linux-$(KERNEL_VERSION)-gentoo/.config
	$(MAKE) -C $(dir $@)

boot/vmlinux-$(KERNEL_VERSION)-gentoo: \
		usr/src/linux-$(KERNEL_VERSION)-gentoo/vmlinux
	$(MAKE) -C $(dir $<) modules_install
	$(MAKE) -C $(dir $<) install
	touch $@

# Grub installation and configuration
boot/grub/grub.cfg: boot/vmlinux-$(KERNEL_VERSION)-gentoo
	grub-mkconfig -o $@

boot/EFI/gentoo/grub64.efi:
	grub-install --target=x86_64-efi --efi-directory=/boot
