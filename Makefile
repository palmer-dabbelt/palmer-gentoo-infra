# Copyright 2016-2017 Palmer Dabbelt <palmer@dabbelt.com>
# 
# Sets up one of my computers.

# This target updates the computer.
.PHONY: update
update: var/lib/palmer/update.stamp

# Synchronizes the portage database with upstream.
.PHONY: sync
sync: var/lib/palmer/sync.stamp
	$(MAKE) $<
	$(MAKE)

.PHONY: install
install: var/lib/palmer/install.stamp

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
	eselect profile set default/linux/amd64/17.1
	touch $@

# Sets up my locales
etc/locale.gen:
	@mkdir -p $(dir $@)
	echo -e "en_US ISO-8859-1\nen_US.UTF-8 UTF-8" > $@

usr/share/i18n/locales/en_US: etc/locale.gen
	@mkdir -p $(dir $@)
	locale-gen
	touch $@

etc/env.d/02locale:
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	echo 'LANG="en_US.UTF-8"' >> $@
	echo 'LC_COLLATE="C"' >> $@

# I generate a fstab, which is currently static because I'm lazy...
etc/fstab: \
		etc/palmer/fstab.d/__base__ \
		$(addprefix etc/palmer/fstab.d/use-,$(CONFIG_USE)) \
		$(addprefix etc/palmer/fstab.d/platform-,$(CONFIG_PLATFORM))
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	cat $(filter-out %.stamp, $^) >> $@

etc/conf.d/hostname:
	@mkdir -p $(dir $@)
	echo "# autogenerated do not edit" > $@
	echo "hostname=\"$(CONFIG_HOSTNAME)\"" > $@

etc/conf.d/net:
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
		$(wildcard boot/vmlinux-*) \
		boot/grub/grub.cfg
	date > $@

# Generates a simple but sane make.conf.
etc/portage/make.conf: \
		etc/palmer/make.conf.d/__base__ \
		$(addprefix etc/palmer/make.conf.d/use-,$(CONFIG_USE)) \
		$(addprefix etc/palmer/make.conf.d/platform-,$(CONFIG_PLATFORM))
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	echo "MAKEOPTS=\"-j`cat /proc/cpuinfo | grep -c ^processor`\"" >> $@
	echo "EMERGE_DEFAULT_OPTS=\"--load-average `cat /proc/cpuinfo | grep -c ^processor` --jobs `cat /proc/cpuinfo | grep -c ^processor`\"" >> $@
	cat $^ >> $@

etc/portage/repos.conf/%: etc/palmer/repos.conf.d/%
	@mkdir -p $(dir $@)
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

etc/portage/package.accept_keywords/palmer: $(wildcard etc/palmer/keywords/*)
	@mkdir -p $(dir $@)
	@rm -rf $@
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

etc/portage/package.use/palmer: $(wildcard etc/palmer/use/*)
	@mkdir -p $(dir $@)
	@rm -rf $@
	echo "# autogenerated, do not edit `date`" > $@
	cat $^ >> $@

etc/portage/package.license/palmer: $(wildcard etc/palmer/license/*)
	@mkdir -p $(dir $@)
	@rm -rf $@
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
		$(subst etc/palmer/repos.conf.d/,etc/portage/repos.conf/,$(wildcard etc/palmer/repos.conf.d/*)) \
		etc/portage/make.conf
	mkdir -p $(dir $@)
	env emaint sync -a
	date > $@

# Updates portage, which is supposed to be the first thing that happens
# whenever something is synchronized.  This step is smart enough to do nothing
# if there isn't a real portage update, so it'll just get run every time.
var/lib/palmer/update-portage.stamp: \
		etc/portage/make.profile \
		var/lib/palmer/sync.stamp
	env - PATH="$(PATH)" emerge -u1 portage
	date > $@

# Updates the rest of the packages on the system.
var/lib/palmer/update-world.stamp: \
		var/lib/portage/world \
		etc/portage/package.accept_keywords/palmer \
		etc/portage/package.use/palmer \
		etc/portage/package.license/palmer \
		var/lib/palmer/update-portage.stamp \
		etc/portage/make.profile \
		var/lib/palmer/sync.stamp
	env - PATH="$(PATH)" emerge -vNDu @world
	env - PATH="$(PATH)" emerge @preserved-rebuild
	env - PATH="$(PATH)" emerge --depclean
	date > $@

# Grub installation and configuration
boot/grub/grub.cfg: \
		$(wildcard boot/vmlinux-*) \
		boot/EFI/gentoo/grubx64.efi
	grub-mkconfig -o $@

boot/EFI/gentoo/grubx64.efi:
	grub-install --target=x86_64-efi --efi-directory=/boot
