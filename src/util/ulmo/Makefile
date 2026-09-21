# Makefile for ulmo: DB-free Oberon build tool
#
# Targets:
#   ulmo     -- shell wrapper (always buildable)
#   ulmoc  -- Oberon compiler binary, built by self-hosting via ulmo
#
# ulmoc is built entirely from source using the installed ulmo binary.
# No pons or cdbd is required.  libo.a must be installed (in BinDir/../lib).
#
# Prerequisites (one-time bootstrap):
#   1. make install from the top-level with pons+cdbd running, OR
#   2. copy a pre-built ulmoc binary to BinDir manually.
# After that, ulmoc rebuilds itself without the DB.

ARCH ?=			i386
DestDir :=		$(shell pwd)/../../..
BinDir :=		$(DestDir)/$(ARCH)/bin
LibDir :=		$(DestDir)/$(ARCH)/lib
InstallBinDir :=	$(BinDir)
OberonSrcDir :=		$(shell pwd)/../../oberon

# Parameters substituted into ulmo.sh -> ulmo
Parameters :=		BINDIR=$(BinDir) ARCH=$(ARCH)

.PHONY: install
install: $(InstallBinDir)/ulmo $(InstallBinDir)/ulmoc

# Shell wrapper: always buildable, no Oberon compiler needed
$(InstallBinDir)/ulmo: ulmo.sh
	mkdir -p $(InstallBinDir)
	../../../substparams $(Parameters) <$< >$@
	chmod 755 $@

# Oberon binary: self-hosted build via ulmo.
# Compiles FilesystemDB and Ulmo from source, links with libo.a.
# Uses a temporary directory so .obj/.o cache files don't pollute the tree.
$(InstallBinDir)/ulmoc: Ulmo.om $(OberonSrcDir)/FilesystemDB.od \
                           $(OberonSrcDir)/FilesystemDB.om \
                           $(InstallBinDir)/ulmo \
                           $(LibDir)/libo.a
	$(eval TMPDIR := $(shell mktemp -d /tmp/ulmo-build-XXXXXX))
	cd $(TMPDIR) && \
	   $(InstallBinDir)/ulmo \
	      -I $(OberonSrcDir) \
	      -m Ulmo \
	      -L $(LibDir) \
	      $(OberonSrcDir)/FilesystemDB.om \
	      $(shell pwd)/Ulmo.om && \
	   mv Ulmo $(InstallBinDir)/ulmoc
	rm -rf $(TMPDIR)
	chmod 755 $(InstallBinDir)/ulmoc
