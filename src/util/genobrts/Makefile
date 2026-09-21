ARCH ?=			i386
BinDir :=		../../../$(ARCH)/bin
InstallBinDir :=	$(BinDir)
Targets :=		genobrts
InstalledTargets :=	$(patsubst %,$(InstallBinDir)/%,$(Targets))

.PHONY:			install
install:		$(InstalledTargets)
$(InstallBinDir)/genobrts:	genobrts.pl
			perl -c genobrts.pl
			cp $< $@
			chmod 755 $@
