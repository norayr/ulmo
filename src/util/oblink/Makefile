ARCH ?=			i386
BinDir :=		$(shell pwd)/../../../$(ARCH)/bin
InstallBinDir :=	$(BinDir)
Targets :=		oblink oberon-$(ARCH).ld
InstalledTargets :=	$(patsubst %,$(InstallBinDir)/%,$(Targets))
Parameters :=		BINDIR=$(BinDir) ARCH=$(ARCH)

.PHONY:			install
install:		$(InstalledTargets)
$(InstallBinDir)/oblink:	oblink.sh
			../../../substparams $(Parameters) <$< >$@
			chmod 755 $@
$(InstallBinDir)/oberon-$(ARCH).ld:	oberon-$(ARCH).ld
			mkdir -p $(InstallBinDir)
			cp $< $@
