BASEDIR = $(shell readlink -f .)

BUILDCONF = $(BASEDIR)/buildconf

PXEDIR=/tank/pxe/os/vpsadmin/current

DEBUG = 1

EL_NAME = scientific
EL_VER = 6.7
EL_ARCH = x86_64
EL_BASEURL = http://mirror.karneval.cz/pub/linux/scientific/$(EL_VER)/$(EL_ARCH)
EL_REPOURL = $(EL_BASEURL)/os
EL_UPDATES = $(EL_BASEURL)/updates/security
EL_REL_RPM = $(EL_BASEURL)/os/Packages/sl-release-6.7-2.x86_64.rpm
EL_YUM_REPOS = $(shell ls -1 $(BUILDCONF)/overlay-root/etc/yum.repos.d/*.repo)
EL_GPG_KEYS = $(shell ls -1 $(BUILDCONF)/overlay-root/etc/yum.repos.d/RPM-GPG-KEY-*)
EL_RPMLIST = $(BUILDCONF)/rpms.list

INSTALLDIR = $(BASEDIR)/install
DOWNLOADDIR = $(BASEDIR)/download
RELEASEDIR = /tank/liveos

TMPDIR = $(BASEDIR)/tmp

include Makefile.general

RELEASEVER = "$$(cat $(RELEASEDIR)/current-release)"

increlease:
	$Vif [ -f $(RELEASEDIR)/current-release ]; then \
		echo $$(( $$(cat $(RELEASEDIR)/current-release) + 1 )) > \
						$(RELEASEDIR)/current-release; \
	else \
		echo 1 > $(RELEASEDIR)/current-release; \
	fi;

clean:
	$E Clean
	$Vrm -Rf $(INSTALLDIR) $(DOWNLOADDIR) $(TMPDIR)
	$Vrm -Rf $(RELEASEDIR)/{rootfs.tar.gz,etc.tar.gz,vmlinuz,initrd}

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
	$E cachedir=$(TMPDIR)/var/cache/yum/$(EL_ARCH)/$(EL_VER)	$C
	$E keepcache=0							$C
	$E debuglevel=2							$C
	$E logfile=$(TMPDIR)/var/log/yum.log				$C
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
	$Vcp -r $(BUILDCONF) $(INSTALLDIR)/tmp/
	$Vecho $(RELEASEVER) > $(BUILDCONF)/overlay-initrd/buildver
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
rel_8: rel_7 pxe
.DEFAULT_GOAL := rel_8
