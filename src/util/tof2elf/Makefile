ARCH ?=			i386
BinDir :=		$(shell pwd)/../../../$(ARCH)/bin
InstallBinDir :=	$(BinDir)
Targets :=		tof2elf
InstalledTargets :=	$(patsubst %,$(InstallBinDir)/%,$(Targets))
LDLIBS :=		-lelf
LDFLAGS :=
CFLAGS :=		-I/usr/include/libelf

.PHONY:			all
all:			$(Targets)

.PHONY:			install
install:		$(InstalledTargets)
$(InstalledTargets):	$(InstallBinDir)/%: %
			mkdir -p $(InstallBinDir)
			cp $< $@
			chmod 755 $@
