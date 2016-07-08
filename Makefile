BASEDIR = $(shell readlink -f .)

BUILDCONF = $(BASEDIR)/buildconf

DEBUG = 1

include $(BUILDCONF)/Makefile.config-repo
include $(BUILDCONF)/Makefile.config-directories
include Makefile.general

RELEASEVER = "$$(cat $(RELEASEDIR)/current-release)"

itworkbitch:
	$E Install build dependencies
	$Vyum install -y parted qemu-kvm util-linux-ng syslinux syslinux-nonlinu \
		kpartx dosfstools

increlease:
	$Vif [ -f $(RELEASEDIR)/current-release ]; then \
		echo $$(( $$(cat $(RELEASEDIR)/current-release) + 1 )) > \
						$(RELEASEDIR)/current-release; \
	else \
		echo 1337 > $(RELEASEDIR)/current-release; \
	fi;

clean:
	$E Clean
	$Vrm -Rf $(INSTALLDIR) $(DOWNLOADDIR) $(TMPDIR)
	$Vrm -Rf $(RELEASEDIR)/{rootfs.tar.gz,etc.tar.gz,vmlinuz,initrd,usb.img}
	$Vrm -f $(BUILDCONF)/overlay-{root,initrd}/buildver

check_dirs:
	$V[ -d $(BUILDCONF) ]
	$V[ ! -d $(INSTALLDIR) ] && mkdir -p $(INSTALLDIR)
	$V[ ! -d $(DOWNLOADDIR) ] && mkdir -p $(DOWNLOADDIR)
	$V[ ! -d $(RELEASEDIR) ] && mkdir -p $(RELEASEDIR) || true
	$V[ ! -d $(TMPDIR) ] && mkdir -p $(TMPDIR)


C	= >> $(TMPDIR)/yum.conf
yum_conf:
	$E Configure yum
	$E [main]							$C
	$E cachedir=/var/cache/yum/$(EL_ARCH)/$(EL_VER)			$C
	$E keepcache=0							$C
	$E debuglevel=2							$C
	$E logfile=/var/log/yum.log					$C
	$E exactarch=1							$C
	$E obsoletes=1							$C
	$E gpgcheck=1							$C
	$E plugins=1							$C
	$E installonly_limit=3						$C
	$Vmkdir -p $(INSTALLDIR)/etc/yum.repos.d
	$Vmkdir -p $(INSTALLDIR)/etc/pki/rpm-gpg
	$Vrepos=0; \
		for repo in $(EL_YUM_REPOS); do \
			cp $$repo $(INSTALLDIR)/etc/yum.repos.d/; \
			repos=$$(($$repos + 1)); \
		done; \
		echo Got $$repos repositories
	$Vkeys=0; \
		for key in $(EL_GPG_KEYS); do \
			cp $$key $(INSTALLDIR)/etc/pki/rpm-gpg/; \
			keys=$$(($$keys + 1)); \
		done; \
		echo Got $$keys keys
	
bootstrap:
	$E Bootstrap
	$E Install release RPM
	$V$(RPM) --initdb --root $(INSTALLDIR) $(STFU)
	$V$(RPM) --root $(INSTALLDIR) -i $(EL_REL_RPM) $(STFU)
	$E Install `cat $(EL_RPMLIST) | wc -l` RPMs
	$Vmkdir -p $(INSTALLDIR)/var/cache/yum
	$Vmkdir -p $(INSTALLDIR)/var/log
	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) makecache $(STFU)
	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) \
		install `cat $(EL_RPMLIST)` -y $(STFU)
	$Vcount=`chroot $(INSTALLDIR) /bin/rpm -qa | wc -l`; \
	echo Actually installed $$count RPMs
#	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) \

modify-rootfs:
	$E Modify rootfs
	$Vecho $(RELEASEVER) > $(BUILDCONF)/overlay-root/buildver
	$Vcp -rf $(BUILDCONF)/overlay-root/* $(INSTALLDIR)/

pack-etc:
	$E Pack etc
	$Vcd $(INSTALLDIR); \
		tar czf $(RELEASEDIR)/etc.tar.gz etc/; rm -Rf etc; mkdir etc
	$E Packed etc size `du -sh $(RELEASEDIR)/etc.tar.gz | sed 's/\s.*//g'`

pack-rootfs:
	$E Pack rootfs
	$Vcd $(INSTALLDIR); \
		tar czf $(RELEASEDIR)/rootfs.tar.gz .
	$E Packed rootfs size `du -sh $(RELEASEDIR)/rootfs.tar.gz | sed 's/\s.*//g'`

copy-kernel:
	$E Copy kernel
	$Vcp $(INSTALLDIR)/boot/vmlinuz-* $(RELEASEDIR)/vmlinuz

mkinitrd:
	$E Make initrd
	$Vcp -r $(BASEDIR)/mkinitramfs $(INSTALLDIR)/tmp/
	$Vecho $(RELEASEVER) > $(BUILDCONF)/overlay-initrd/buildver
	$Vcp -r $(BUILDCONF) $(INSTALLDIR)/tmp/
	$Vkernel=`ls -1 $(INSTALLDIR)/boot/vmlinuz-* | sed 's/.*vmlinuz\-//g'`; \
	chroot $(INSTALLDIR)\
		bash -c "cd /tmp/mkinitramfs; ./mkinitramfs $$kernel" $(STFU)
	$Vcp $(INSTALLDIR)/tmp/mkinitramfs/initrd.img $(RELEASEDIR)/initrd
	$(IFNDEBUG) rm -Rf $(INSTALLDIR)/tmp/{mkinitramfs,buildconf}

releasecopy:
	$Vecho -en "Copying Release $(RELEASEVER): "; \
	reldir="release-`printf "%04d\n" $(RELEASEVER)`"; \
	mkdir -p $(RELEASEDIR)/$$reldir; \
	rm -f $(RELEASEDIR)/current; \
	cd $(RELEASEDIR); \
	ln -s $$reldir $(RELEASEDIR)/current
	$Vfor file in rootfs.tar.gz etc.tar.gz vmlinuz initrd; do \
		echo -en "$$file "; \
		cp $(RELEASEDIR)/$$file $(RELEASEDIR)/current/; \
	done; echo;
	$(IFDEBUG) echo Copy buildconf for current release && \
	cp -r $(BUILDCONF) $(RELEASEDIR)/current/buildconf

pxe: 
	$E Update PXE
	$Vrm -f $(PXEDIR)/current/{vmlinuz,initrd}
	$Vcp -f $(RELEASEDIR)/current/{vmlinuz,initrd} $(PXEDIR)/

usb:
	$E Create bootable USB drive
	$Vkpartx -d /dev/loop0 $(STFU) || true
	$Vlosetup -d /dev/loop0 $(STFU) || true
	$Vdd if=/dev/zero of=$(RELEASEDIR)/current/usb.img bs=1M count=1024 $(STFU)
	$Vlosetup /dev/loop0 $(RELEASEDIR)/current/usb.img
	$Vparted /dev/loop0 --script mklabel msdos
	$Vparted /dev/loop0 --script mkpart primary fat32 0% 100%
	$Vparted /dev/loop0 --script set 1 boot on
	$Vkpartx -a /dev/loop0 && sleep 2
	$Vmkfs.vfat /dev/mapper/loop0p1
	$Vsyslinux -i /dev/mapper/loop0p1
	$Vmount /dev/mapper/loop0p1 /mnt
	$Vcp $(RELEASEDIR)/current/{initrd,vmlinuz,rootfs.tar.gz,etc.tar.gz} /mnt/
	$Vcp /usr/share/syslinux/menu.c32 /mnt/
	$Vcp $(BUILDCONF)/syslinux.cfg /mnt/
	$Vumount /mnt
	$Vdd conv=notrunc bs=440 if=/usr/share/syslinux/mbr.bin of=/dev/loop0 $(STFU)
	$Vkpartx -d /dev/loop0
	$Vlosetup -d /dev/loop0

qemu-usb:
	$E Launch QEMU with USB drive
	$V/usr/libexec/qemu-kvm -nographic -m 4096 -machine accel=kvm \
		-drive file=$(RELEASEDIR)/current/usb.img,if=virtio,boot=on

help:
	$EvpsAdmin LiveOS Build root
	$E 
	$E invoke full build:    make [VERBOSE=1] [VARIABLEOVERRIDE=value...]
	$E invoke any subtarget: make <command> [VERBOSE=1][VARIABLEOVERRIDE=value...]  
	$E 
	$E available targets in launch order to make a full build:
	$E 	increlease	increment a release version
	$E 	yum_conf	configure yum in INSTALLDIR
	$E 	bootstrap	install rootfs
	$E 	modify-rootfs	copy buildconf overlay to rootfs and clean up
	$E 	pack-etc	pack etc.tar.gz
	$E	copy-kernel	extract kernel from rootfs
	$E	mkinitrd	create
	$E	pack-rootfs	pack rootfs.tar.gz
	$E	releasecopy	make a new release copy
	$E	pxe		update PXE (tftp is retarded and never heard of symlink)
	$E	usb		create USB flashdrive image
	$E	qemu-usb	launch USB flashdrive image in QEMU

rel_0: clean increlease
	$(IFDEBUG) echo DEBUG BUILD $(RELEASEVER)
	$(IFNDEBUG) echo PRODUCTION BUILD $(RELEASEVER)
rel_1: rel_0 check_dirs
rel_2: rel_1 yum_conf
rel_3: rel_2 bootstrap
rel_4: rel_3 modify-rootfs
rel_5: rel_4 pack-etc copy-kernel mkinitrd
rel_6: rel_5 pack-rootfs
rel_7: rel_6 releasecopy
rel_8: rel_7 pxe usb
all:   rel_8

.DEFAULT_GOAL := all
