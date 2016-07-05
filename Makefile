BASEDIR = $(shell readlink -f .)

EL_NAME = scientific
EL_VER = 6.7
EL_ARCH = x86_64
EL_BASEURL = http://mirror.karneval.cz/pub/linux/scientific/$(EL_VER)/$(EL_ARCH)
EL_REPOURL = $(EL_BASEURL)/os
EL_UPDATES = $(EL_BASEURL)/updates/security
EL_REL_RPM = $(EL_BASEURL)/os/Packages/sl-release-6.7-2.x86_64.rpm
EL_YUM_REPOS = $(shell ls -1 $(BASEDIR)/yum.repos.d/*.repo)
EL_GPG_KEYS = $(shell ls -1 $(BASEDIR)/yum.repos.d/RPM-GPG-KEY-*)
EL_RPMLIST = $(BASEDIR)/rpms.list

INSTALLDIR = $(BASEDIR)/install
DOWNLOADDIR = $(BASEDIR)/download
RELEASEDIR = $(BASEDIR)/release

TMPDIR = $(BASEDIR)/tmp

include Makefile.general

clean:
	$Vrm -Rf $(INSTALLDIR) $(DOWNLOADDIR) $(TMPDIR) $(RELEASEDIR)

check_dirs:
	$V[ ! -d $(INSTALLDIR) ] && mkdir -p $(INSTALLDIR)
	$V[ ! -d $(DOWNLOADDIR) ] && mkdir -p $(DOWNLOADDIR)
	$V[ ! -d $(RELEASEDIR) ] && mkdir -p $(RELEASEDIR)
	$V[ ! -d $(TMPDIR) ] && mkdir -p $(TMPDIR)


C	= >> $(TMPDIR)/yum.conf
yum_conf: check_dirs
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
	$V \
		for repo in $(EL_YUM_REPOS); do \
			cp $$repo $(INSTALLDIR)/etc/yum.repos.d/; \
		done
	$V \
		for key in $(EL_GPG_KEYS); do \
			cp $$key $(INSTALLDIR)/etc/pki/rpm-gpg/; \
		done
	
bootstrap: yum_conf
	$E Install release RPM
	$V$(RPM) --initdb --root $(INSTALLDIR) $(STFU)
	$V$(RPM) --root $(INSTALLDIR) -i $(EL_REL_RPM) $(STFU)
	$E Install `cat $(EL_RPMLIST) | wc -l` RPMs
	$Vmkdir -p $(INSTALLDIR)/var/cache/yum
	$Vmkdir -p $(INSTALLDIR)/var/log
	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) makecache $(STFU)
	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) \
		install `cat $(EL_RPMLIST)` -y $(STFU)
#	$Vyum -c $(TMPDIR)/yum.conf --installroot=$(INSTALLDIR) \

pack-etc: bootstrap
	$E Pack etc
	$Vcd $(INSTALLDIR); \
		tar czf $(RELEASEDIR)/etc.tar.gz etc/; rm -Rf etc; mkdir etc
	du -sh $(RELEASEDIR)/etc.tar.gz

pack-rootfs: pack-etc
	$E Pack rootfs
	$Vcd $(INSTALLDIR); \
		tar czf $(RELEASEDIR)/rootfs.tar.gz .
	du -sh $(RELEASEDIR)/rootfs.tar.gz

