# DestDir, BinDir etc are the paths that get burnt into the scripts
# InstallDir, InstallBinDir etc are the paths where we copy the files to;
# both sets are by default equal; however in case of package constructions
# we set InstallDir etc to the package construction area and DestDir etc
# to the final destination which is created later on by the package
Root := $(shell pwd)
ARCH ?= i386
DestDir := $(Root)
InstallDir := $(DestDir)
BinDir := $(DestDir)/$(ARCH)/bin
EtcDir := $(DestDir)/etc
IntensityDir := $(EtcDir)/intensity
InstallBinDir := $(InstallDir)/$(ARCH)/bin
DBDir := $(DestDir)/var/cdbd
InstallDBDir := $(InstallDir)/var/cdbd
DBAuth := $(DBDir)/write
VarDir := $(DestDir)/var
PonsDir := $(VarDir)/pons
CDBDDir := $(VarDir)/cdbd
CDBDir := /pub/cdb/oberon
ManDir := $(DestDir)/man
SrcDir := $(DestDir)/src
InitDir := $(DestDir)/etc/init.d
InstallPonsDir := $(InstallDir)/var/pons
InstallManDir := $(InstallDir)/man
InstallSrcDir := $(InstallDir)/src
InstallEtcDir := $(InstallDir)/etc
InstallIntensityDir := $(InstallEtcDir)/intensity
InstallVarDir := $(InstallDir)/var
InstallInitDir := $(InstallDir)/etc/init.d
RcFile := $(InstallDir)/rc
ONSRoot := 127.0.0.1:9880
ONSPort := 127.0.0.1:9881
CDBDPort := 127.0.0.1:9882
ONSRootOfStage1 := 127.0.0.1:9883
ONSPortOfStage1 := 127.0.0.1:9884
CDBDPortOfStage1 := 127.0.0.1:9885
Lib := $(Root)/build/libo.a
ScriptDir := $(Root)/build/scripts
Binaries := cdbd nsh obci obco obdeps obload obtofgen obzap pons onsstat \
	onsshut onsmkdir onswait
InstalledBinaries := $(patsubst %,$(InstallBinDir)/%,$(Binaries))
InitScripts := cdbd pons
InstalledInitScripts := $(patsubst %,$(InstallInitDir)/%,$(InitScripts))
InsertableInitScripts := $(patsubst %,$(InitDir)/%,$(InitScripts))
MakeParams := DestDir=$(DestDir) BinDir=$(BinDir) DBAuth=$(DBAuth) \
	ONSRoot=$(ONSRoot) PonsDir=$(PonsDir) CDBDDir=$(CDBDDir) \
	CDBDir=$(CDBDir) SrcDir=$(SrcDir) IntensityDir=$(IntensityDir) \
	InstallDir=$(InstallDir) InstallBinDir=$(InstallBinDir) \
	InstallDBDir=$(InstallDBDir) InstallPonsDir=$(InstallPonsDir) \
	InstallIntensityDir=$(InstallIntensityDir) ONSPort=$(ONSPort) \
	CDBDPort=$(CDBDPort)
Stage1Dir := $(Root)/stage1
Stage2Dir := $(Root)/stage2

.PHONY:	install
install: ulmoinstall installsrc

.PHONY:	installsuse
installsuse: install installsuseinit

.PHONY:	runsuse
runsuse:	installsuse suserun

.PHONY:	bindir
bindir:
	mkdir -p $(InstallBinDir)

.PHONY:	installbin
installbin:	ulmo-core-tools

.PHONY:	installman
installman:	mandir
ifneq ($(InstallManDir),$(Root)/man)
	cp -a $(Root)/man/* $(InstallManDir)
endif

.PHONY:	mandir
mandir:
	mkdir -p $(InstallManDir)

.PHONY:	installsrc
installsrc:	srcdir
ifneq ($(InstallSrcDir),$(Root)/src)
	cp -a $(Root)/src/* $(InstallSrcDir)
endif

.PHONY:	srcdir
srcdir:
	mkdir -p $(InstallSrcDir)

.PHONY:	installvar
installvar:
	mkdir -p $(PonsDir)
	mkdir -p $(CDBDDir)

.PHONY:	installetc
installetc:	gcintensity

.PHONY:	installutil
installutil:	bindir
	cd src/util && $(MAKE) $(MakeParams) install

.PHONY:	scripts
scripts:
	cd src/util && $(MAKE) $(MakeParams) InstallDir=$(Root) InstallBinDir=$(Root)/build/scripts DestDir=$(Root) BinDir=$(Root)/build/scripts IntensityDir=$(IntensityDir) install

.PHONY: mkoblib
mkoblib: scripts $(Lib)
$(Lib):	installutil build/tofs.tgz
	$(ScriptDir)/mkoblib build

# Note: binary targets are now built via ulmoinstall (ulmo-based, no pons/cdbd).
# The old pons/cdbd-based rules have been replaced.  For the old DB-based build,
# use the scripts/mkoblib/oblink targets manually, or use the pons/cdbd system.

.PHONY:	installrc
installrc:	$(RcFile)
$(RcFile):
	echo OBERON=$(DestDir) >$@
	echo PATH=$(BinDir):\$$PATH >>$@
	echo MANPATH=$(ManDir):\$$MANPATH >>$@
	echo ONS_ROOT=$(ONSRoot) >>$@
	echo ONS_PORT=$(ONSPort) >>$@
	echo CDBD_PORT=$(CDBDPort) >>$@
	echo CDB_BASEDIR=$(CDBDir) >>$@
	echo CDB_AUTH=$(DBAuth) >>$@
	echo export OBERON PATH MANPATH ONS_ROOT ONS_PORT \
	   CDBD_PORT CDB_BASEDIR CDB_AUTH >>$@

.PHONY:	installsuseinit initdir
installsuseinit:	initdir $(InstalledInitScripts)
initdir:
	mkdir -p $(InstallInitDir)
$(InstallInitDir)/cdbd:		scripts
	BASEDIR=$(DestDir) BINDIR=$(BinDir) \
	   $(ScriptDir)/obmk_suse_init_cdbd \
	      -c $(CDBDir) -d $(CDBDDir) -r $(ONSRoot) >$@
	chmod 755 $@
$(InstallInitDir)/pons:		$(ScriptDir)/obmk_suse_init_pons
	ONS_ROOT=$(ONSRoot) ONS_PORT=$(ONSPort) \
	   BASEDIR=$(DestDir) BINDIR=$(BinDir) \
	   $(ScriptDir)/obmk_suse_init_pons \
	      -d $(PonsDir) >$@
	chmod 755 $@

.PHONY:	gcintensity
gcintensity:
	mkdir -p $(InstallIntensityDir)
	$(ScriptDir)/obgcdflts $(InstallIntensityDir)

.PHONY:	suseinsserv
suseinsserv:	$(InsertableInitScripts) 
	insserv $(InitDir)/pons
	insserv $(InitDir)/cdbd
.PHONY:	suserun
suserun:	suseinsserv
	sh $(InitDir)/pons start
	sh $(InitDir)/cdbd start
.PHONY:	stdsuserun
stdsuserun:
	$(MAKE) $(MakeParams) \
	   InitDir=/etc/init.d \
	   InstallInitDir=/etc/init.d \
	   suserun

.PHONY:	stage1 runstage1 stage2 stage12cmp steadystatetest finishstage1
stage1:
	$(SHELL) -c 'time $(BinDir)/mk_obstage \
	   $(Stage1Dir) $(BinDir) $(BinDir) $(ONSRoot) $(CDBDir) $(DBAuth)'
runstage1:
	$(BinDir)/run_obstage $(Stage1Dir) $(BinDir) \
	   $(ONSRootOfStage1) $(ONSPortOfStage1) $(CDBDPortOfStage1)
stage2:
	$(SHELL) -c 'time $(BinDir)/mk_obstage \
	   $(Stage2Dir) $(BinDir) $(Stage1Dir) $(ONSRootOfStage1) \
	   $(CDBDir) $(Stage1Dir)/var/cdbd/write'
finishstage1:
	-ONS_ROOT=$(ONSRootOfStage1) \
	   $(Stage1Dir)/onsshut -a $(Stage1Dir)/var/pons/shutdown /pub/pons
stage12cmp:
	cmp $(Stage1Dir)/cdbd $(Stage2Dir)/cdbd
	cmp $(Stage1Dir)/nsh $(Stage2Dir)/nsh
	cmp $(Stage1Dir)/obci $(Stage2Dir)/obci
	cmp $(Stage1Dir)/obco $(Stage2Dir)/obco
	cmp $(Stage1Dir)/obdeps $(Stage2Dir)/obdeps
	cmp $(Stage1Dir)/obload $(Stage2Dir)/obload
	cmp $(Stage1Dir)/obtofgen $(Stage2Dir)/obtofgen
	cmp $(Stage1Dir)/obzap $(Stage2Dir)/obzap
	cmp $(Stage1Dir)/pons $(Stage2Dir)/pons
	cmp $(Stage1Dir)/onsstat $(Stage2Dir)/onsstat
	cmp $(Stage1Dir)/onsshut $(Stage2Dir)/onsshut
	cmp $(Stage1Dir)/onsmkdir $(Stage2Dir)/onsmkdir
	cmp $(Stage1Dir)/onswait $(Stage2Dir)/onswait
steadystatetest:	stage1 runstage1 stage2 finishstage1 stage12cmp

.PHONY:	download_tof2elf
download_tof2elf:
	wget -O src/util/tof2elf/tof2elf ftp://ftp.mathematik.uni-ulm.de/pub/soft/oberon/ulm/i386/tof2elf
	chmod 755 src/util/tof2elf/tof2elf
	touch src/util/tof2elf/tof2elf

# ============================================================
# ulmoinstall: DB-free build and install — no pons/cdbd needed
#
# Bootstrap binaries (bootstrap/ulmoc, bootstrap/obtofgen) seed the
# build.  Everything is then compiled from source and the bootstrap copies
# are replaced by freshly-built binaries.
#
# Usage:
#   make ulmoinstall [DestDir=/path/to/install]
# ============================================================

LibDir          := $(BinDir)/../lib
BootstrapDir    := $(Root)/bootstrap
SrcRoot         := $(Root)/src
CompilerSrcDir  := $(SrcRoot)/compiler
LibSources      := $(wildcard $(SrcRoot)/rtl/*.om $(SrcRoot)/lib/*.om \
                              $(SrcRoot)/compiler/*.om)
UlmoUtilDir     := $(Root)/src/util/ulmo

# For AMD64: the cross-compiler ulmoc is the i386 build (which has the AMD64 backend).
# Falls back to system ulmoc if i386 install is not present.
ifeq ($(ARCH),amd64)
_I386BIN        := $(DestDir)/i386/bin
_CROSS_ULMOC    := $(or $(wildcard $(_I386BIN)/ulmoc),/home/noch/oberon/bin/ulmoc)
TOFGEN_MODULE   := OberonAMD64TransportableObjectFormatGenerator
TOFGEN_LIBDIR   := $(DestDir)/i386/lib
_BUILD_ULMO     := $(_I386BIN)/ulmo
else
_CROSS_ULMOC    := $(BootstrapDir)/ulmoc
TOFGEN_MODULE   := OberonI386TransportableObjectFormatGenerator
TOFGEN_LIBDIR   := $(LibDir)
_BUILD_ULMO     := $(InstallBinDir)/ulmo
endif

# -- Directories ----------------------------------------------
.PHONY: ulmo-dirs
ulmo-dirs:
	mkdir -p $(InstallBinDir) $(LibDir)

# -- tof2elf: the one C tool in the pipeline ------------------
$(InstallBinDir)/tof2elf: $(Root)/src/util/tof2elf/tof2elf.c | ulmo-dirs
	gcc -O2 -o $@ $< -lelf
	chmod 755 $@

# -- Script/data tools -----------------------------------------
$(InstallBinDir)/genobrts: $(Root)/src/util/genobrts/genobrts.pl | ulmo-dirs
	cp $< $@
	chmod 755 $@

$(InstallBinDir)/oblink: $(Root)/src/util/oblink/oblink.sh | ulmo-dirs
	$(Root)/substparams BINDIR=$(BinDir) ARCH=$(ARCH) <$< >$@
	chmod 755 $@

$(InstallBinDir)/oberon-i386.ld: $(Root)/src/util/oblink/oberon-i386.ld | ulmo-dirs
	cp $< $@

$(InstallBinDir)/oberon-amd64.ld: $(Root)/src/util/oblink/oberon-amd64.ld | ulmo-dirs
	cp $< $@

$(InstallBinDir)/ulmo: $(UlmoUtilDir)/ulmo.sh | ulmo-dirs
	$(Root)/substparams BINDIR=$(BinDir) ARCH=$(ARCH) SRCROOT=$(SrcRoot) <$< >$@
	chmod 755 $@

ifeq ($(ARCH),amd64)
# -- AMD64 libraries (librtl.a, libo.a, libcompiler.a): requires AMD64-capable obtofgen and ulmoc already installed --
# obtofgen and ulmoc are built before libo.a (see ulmo-core-tools ordering).
$(LibDir)/libo.a: $(InstallBinDir)/tof2elf \
                  $(InstallBinDir)/ulmo \
                  $(InstallBinDir)/ulmoc \
                  $(InstallBinDir)/obtofgen \
                  $(LibSources) \
                  | ulmo-dirs
	$(UlmoUtilDir)/build-libo.sh \
	   $(InstallBinDir) $(SrcRoot) $(LibDir) AMD64

# -- AMD64 obtofgen: built before libo.a using i386 ulmo + i386 libo.a --------
$(InstallBinDir)/obtofgen: $(CompilerSrcDir)/$(TOFGEN_MODULE).om | ulmo-dirs
	@if [ ! -f $(TOFGEN_LIBDIR)/libo.a ]; then \
	   echo "ERROR: $(TOFGEN_LIBDIR)/libo.a not found."; \
	   echo "For AMD64 builds, run 'make ARCH=i386 DestDir=$(DestDir) ulmoinstall' first."; \
	   exit 1; \
	fi
	$(eval _TMPD := $(shell mktemp -d /tmp/ulmoctofgen-XXXXXX))
	cd $(_TMPD) && $(_BUILD_ULMO) \
	   -m $(TOFGEN_MODULE) \
	   -L $(TOFGEN_LIBDIR) \
	   $(CompilerSrcDir)/$(TOFGEN_MODULE).om && \
	mv $(TOFGEN_MODULE) $(InstallBinDir)/obtofgen
	rm -rf $(_TMPD)
	chmod 755 $(InstallBinDir)/obtofgen

else
# -- i386 libraries (librtl.a, libo.a, libcompiler.a): bootstrap obtofgen/ulmoc from bootstrap/ if not present -----
$(LibDir)/libo.a: $(InstallBinDir)/tof2elf \
                  $(InstallBinDir)/ulmo \
                  $(LibSources) \
                  | ulmo-dirs
	@if [ ! -f $(InstallBinDir)/ulmoc ]; then \
	   echo "bootstrap: installing ulmoc from $(_CROSS_ULMOC)"; \
	   cp -f $(_CROSS_ULMOC) $(InstallBinDir)/ulmoc; \
	   chmod 755 $(InstallBinDir)/ulmoc; \
	fi
	@if [ ! -f $(InstallBinDir)/obtofgen ]; then \
	   echo "bootstrap: installing obtofgen from $(BootstrapDir)"; \
	   cp -f $(BootstrapDir)/obtofgen $(InstallBinDir)/obtofgen; \
	   chmod 755 $(InstallBinDir)/obtofgen; \
	fi
	$(UlmoUtilDir)/build-libo.sh \
	   $(InstallBinDir) $(SrcRoot) $(LibDir) I386

# -- i386 obtofgen: built after libo.a, replaces bootstrap copy ---------------
$(InstallBinDir)/obtofgen: $(CompilerSrcDir)/$(TOFGEN_MODULE).om \
                            $(LibDir)/libo.a | ulmo-dirs
	$(eval _TMPD := $(shell mktemp -d /tmp/ulmoctofgen-XXXXXX))
	cd $(_TMPD) && $(_BUILD_ULMO) \
	   -m $(TOFGEN_MODULE) \
	   -L $(TOFGEN_LIBDIR) \
	   $(CompilerSrcDir)/$(TOFGEN_MODULE).om && \
	mv $(TOFGEN_MODULE) $(InstallBinDir)/obtofgen
	rm -rf $(_TMPD)
	chmod 755 $(InstallBinDir)/obtofgen

endif

# -- ulmoc: build from source (i386) or copy cross-compiler (amd64) -------
# AMD64 has no native ulmoc yet; amd64/bin/ulmoc is just the i386 cross-compiler.
ifeq ($(ARCH),amd64)
$(InstallBinDir)/ulmoc: $(_CROSS_ULMOC) | ulmo-dirs
	cp -f $(_CROSS_ULMOC) $@
	chmod 755 $@
else
$(InstallBinDir)/ulmoc: $(LibDir)/libo.a \
                           $(InstallBinDir)/obtofgen \
                           $(CompilerSrcDir)/FilesystemDB.om \
                           $(UlmoUtilDir)/Ulmo.om
	$(eval _TMPD := $(shell mktemp -d /tmp/ulmo-self-XXXXXX))
	cd $(_TMPD) && $(InstallBinDir)/ulmo \
	   -m Ulmo \
	   -L $(LibDir) \
	   $(CompilerSrcDir)/FilesystemDB.om \
	   $(UlmoUtilDir)/Ulmo.om && \
	mv Ulmo $(InstallBinDir)/ulmoc
	rm -rf $(_TMPD)
	chmod 755 $(InstallBinDir)/ulmoc
endif

# -- DB tools: optional, built from source with ulmo ----------
# These provide the pons/cdbd infrastructure for users who want it.
# Each is an Oberon main module linked with libo.a; no DB needed to BUILD.
# Built via a phony target (loop) to avoid conflicting with the old pons/cdbd
# rules for the same target file names.
#
# Module name → binary name mapping:
#   OberonI386TransportableObjectFormatGenerator → obtofgen  (already above)
#   OberonLoader        → obload
#   CDBDaemon           → cdbd
#   PersistentNameServer→ pons
#   OberonCheckIn       → obci
#   CDBCheckoutSource   → obco
#   OberonZap           → obzap
#   OberonDependencies  → obdeps
#   NamesShell          → nsh
#   NodeStatus          → onsstat
#   ShutdownNode        → onsshut
#   MakeDirectory       → onsmkdir
#   PathWaiter          → onswait

UlmoDbTools := \
	OberonLoader:obload \
	CDBDaemon:cdbd \
	PersistentNameServer:pons \
	OberonCheckIn:obci \
	CDBCheckoutSource:obco \
	OberonZap:obzap \
	OberonDependencies:obdeps \
	NamesShell:nsh \
	NodeStatus:onsstat \
	ShutdownNode:onsshut \
	MakeDirectory:onsmkdir \
	PathWaiter:onswait

.PHONY: ulmo-db-tools
ulmo-db-tools: ulmo-core-tools
	$(foreach pair,$(UlmoDbTools), \
	  $(eval _MOD  := $(word 1,$(subst :, ,$(pair)))) \
	  $(eval _BIN  := $(word 2,$(subst :, ,$(pair)))) \
	  $(eval _DEST := $(InstallBinDir)/$(_BIN)) \
	  $(eval _TMPD := $(shell mktemp -d /tmp/ulmo-dbtool-XXXXXX)) \
	  $(shell cd $(_TMPD) && \
	      $(InstallBinDir)/ulmo \
	         -m $(_MOD) -L $(LibDir) \
	         $(wildcard $(SrcRoot)/*/$(_MOD).om) && \
	      mv $(_MOD) $(_DEST) && \
	      chmod 755 $(_DEST) && \
	      rm -rf $(_TMPD) && \
	      echo "  built: $(_BIN)") \
	)

# -- Top-level ulmoinstall target ------------------------------
.PHONY: ulmoinstall ulmo-core-tools
ulmo-core-tools: ulmo-dirs \
	$(InstallBinDir)/tof2elf \
	$(InstallBinDir)/genobrts \
	$(InstallBinDir)/oblink \
	$(InstallBinDir)/oberon-$(ARCH).ld \
	$(InstallBinDir)/ulmo \
	$(LibDir)/libo.a \
	$(InstallBinDir)/obtofgen \
	$(InstallBinDir)/ulmoc

ulmoinstall: ulmo-core-tools
	@echo "ulmoinstall complete (ARCH=$(ARCH), DestDir=$(DestDir))."
	@echo "To also build DB tools (cdbd, pons, etc.): make ulmo-db-tools"
