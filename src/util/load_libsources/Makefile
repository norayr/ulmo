DestDir :=		$(shell pwd)/../../..
BinDir :=		$(DestDir)/bin
CDBDDir :=		$(DestDir)/var/cdbd
SrcDir :=		$(DestDir)/src
DBAuth :=		$(DestDir)/var/cdbd/write
InstallBinDir :=	$(BinDir)
Targets :=		load_libsources
InstalledTargets :=	$(patsubst %,$(InstallBinDir)/%,$(Targets))
Parameters :=		BASEDIR=$(DestDir) BINDIR=$(BinDir) \
			CDBDDIR=$(CDBDDir) ONS_ROOT=$(ONSRoot) \
			CDBDIR=$(CDBDir) SRCROOT=$(SrcDir) \
			DBAUTH=$(DBAuth)

.PHONY:			install
install:		$(InstalledTargets)
$(InstallBinDir)/load_libsources:	load_libsources.sh
			../../../substparams $(Parameters) <$< >$@
			chmod 755 $@
