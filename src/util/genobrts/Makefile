ARCH ?=			i386
BinDir :=		../../../$(ARCH)/bin
InstallBinDir :=	$(BinDir)
Targets :=		genobrts
InstalledTargets :=	$(patsubst %,$(InstallBinDir)/%,$(Targets))

.PHONY:			install
install:		$(InstalledTargets)
$(InstallBinDir)/genobrts:	genobrts-$(ARCH)
			perl -c $<
			cp $< $@
			chmod 755 $@
