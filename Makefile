# Makefile -- build and install ulmo, the compiler for Ulm's Oberon
#
#   make [ARCH=amd64|i386]   build the compiler and its libraries
#   make check               stage 3 self-hosting check and a test program
#   make install             install (PREFIX, BINDIR, LIBDIR, DATADIR, DESTDIR)
#   make uninstall
#   make clean
#   make cdb-tools           programs of the (legacy) compiler database
#
# ARCH defaults to the architecture of the host.  The build starts with the
# compiler in bootstrap/$(ARCH) and builds the compiler and its libraries
# twice: stage 1 with the bootstrap compiler, stage 2 with the compiler of
# stage 1.  Stage 2 is installed.  "make check" builds stage 3 with the
# compiler of stage 2; both must be identical.
#
# Sources and libraries (see src/):
#   src/rtl       run time system, linked into every program  -> librtl.a
#   src/rtl/ARCH  architecture-specific versions of rtl modules
#   src/lib       general library                             -> libo.a
#   src/compiler  the compiler                                -> libcompiler.a
#
# Installed files:
#   BINDIR/ulmo                        the only command users need
#   LIBDIR/ulmo/tof2elf                converts TOF text to ELF objects
#   LIBDIR/ulmo/ARCH/                  compiler, tools, linker script and
#                                      libraries for one target architecture
#   LIBDIR/ulmo/ARCH/obj/              compiled interfaces and objects of the
#                                      library modules
#   DATADIR/ulmo/src/                  sources of the libraries
#
# build/root has the same layout as an installation; build/root/bin/ulmo
# can be used without installing.

# === configuration ========================================================

ARCH ?= $(shell uname -m)
override ARCH := $(patsubst i%86,i386,$(patsubst x86,i386,$(patsubst x86_64,amd64,$(ARCH))))

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
DATADIR ?= $(PREFIX)/share
DESTDIR ?=
CFLAGS ?= -O2
INSTALL ?= install

ULMOLIBDIR := $(LIBDIR)/ulmo
ULMOSRCDIR := $(DATADIR)/ulmo/src

ifeq ($(ARCH),i386)
OBJARCH := I386
TOFGEN_MAIN := OberonI386TransportableObjectFormatGenerator
else ifeq ($(ARCH),amd64)
OBJARCH := AMD64
TOFGEN_MAIN := OberonAMD64TransportableObjectFormatGenerator
else
$(error unsupported ARCH=$(ARCH), use ARCH=amd64 or ARCH=i386)
endif

# === sources ==============================================================

# modules in src/rtl/$(ARCH) replace the generic ones of the same name
RTL_ARCH_SRC := $(wildcard src/rtl/$(ARCH)/*.om)
RTL_SRC := $(RTL_ARCH_SRC) \
	$(filter-out $(addprefix src/rtl/,$(notdir $(RTL_ARCH_SRC))), \
		$(wildcard src/rtl/*.om))
COMPILER_SRC := $(wildcard src/compiler/*.om)
LIB_SRC := $(wildcard src/lib/*.om)
ALL_SRC := $(RTL_SRC) $(COMPILER_SRC) $(LIB_SRC)
ALL_DEF := $(wildcard src/rtl/$(ARCH)/*.od src/rtl/*.od \
	src/compiler/*.od src/lib/*.od)

SRCDIRS := $(wildcard src/rtl/$(ARCH)) src/rtl src/lib src/compiler
INCS := $(foreach dir,$(SRCDIRS),-I $(CURDIR)/$(dir))

modules = $(basename $(notdir $(1)))

# === build tree ===========================================================

B := build/$(ARCH)
ROOT := build/root
ROOTARCH := $(ROOT)/lib/ulmo/$(ARCH)
TOF2ELF := $(ROOT)/lib/ulmo/tof2elf
GENOBRTS := src/util/genobrts/genobrts-$(ARCH)
LDSCRIPT := src/util/oblink/oberon-$(ARCH).ld

# shell command linking the main module $$main into the program $$prog
# with the libraries in the directory $$libs
LINK = echo "  LINK    $$prog" && \
	AS='$(AS)' LD='$(LD)' LDFLAGS='$(LDFLAGS)' \
	GENOBRTS='$(GENOBRTS)' LDSCRIPT='$(LDSCRIPT)' \
	sh src/util/oblink/link-static.sh $(ARCH) $$libs $$prog $$main \
		$$libs/libcompiler.a $$libs/libo.a $$libs/librtl.a

.PHONY: all stage1 stage2 stage3 root check check-runtime check-cli install uninstall clean cdb-tools

all: root
	@if cmp -s $(B)/stage1/ulmoc $(B)/stage2/ulmoc; then \
		echo "ulmo for $(ARCH) built; stages 1 and 2 are identical"; \
	else \
		echo "ulmo for $(ARCH) built; stage 2 differs from stage 1" \
			"(the bootstrap compiler is older), see make check"; \
	fi

stage1: $(TOF2ELF)
	@$(MAKE) --no-print-directory stage STAGE=1 \
		OC=bootstrap/$(ARCH)/ulmoc TOFGEN=bootstrap/$(ARCH)/obtofgen

stage2: stage1
	@$(MAKE) --no-print-directory stage STAGE=2 \
		OC=$(B)/stage1/ulmoc TOFGEN=$(B)/stage1/obtofgen

stage3: stage2
	@$(MAKE) --no-print-directory stage STAGE=3 \
		OC=$(B)/stage2/ulmoc TOFGEN=$(B)/stage2/obtofgen

$(TOF2ELF): src/util/tof2elf/tof2elf.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< -lelf

root: stage2
	@mkdir -p $(ROOT)/bin $(ROOTARCH) $(ROOT)/share/ulmo
	@# remove first: the old programs may still be running
	@rm -f $(ROOTARCH)/ulmoc $(ROOTARCH)/obtofgen $(ROOTARCH)/genobrts \
		$(ROOT)/bin/ulmo
	@cp -p $(B)/stage2/ulmoc $(B)/stage2/obtofgen $(B)/stage2/lib/*.a \
		$(LDSCRIPT) $(ROOTARCH)/
	@rm -rf $(ROOTARCH)/obj
	@mkdir -p $(ROOTARCH)/obj
	@cp -p $(B)/stage2/obj/*.obj $(ROOTARCH)/obj/
	@cp -p $(GENOBRTS) $(ROOTARCH)/genobrts
	@cp -p src/util/oblink/link-static.sh $(ROOTARCH)/oblink
	@cp -p src/util/ulmo/ulmo.sh $(ROOT)/bin/ulmo
	@chmod 755 $(ROOT)/bin/ulmo $(ROOTARCH)/genobrts $(ROOTARCH)/oblink
	@ln -sfn ../../../../src $(ROOT)/share/ulmo/src

# === one stage: compile all modules with $(OC), archive them, link tools ===

ifdef STAGE
S := $(B)/stage$(STAGE)
MOD_OBJ := $(foreach m,$(call modules,$(ALL_SRC)),$(S)/obj/$(m)-mod-$(OBJARCH).obj)
objects = $(addprefix $(S)/obj/,$(addsuffix .o,$(call modules,$(1))))

.PHONY: stage
stage: $(S)/ulmoc $(S)/obtofgen
	@echo "stage $(STAGE) ($(ARCH)): ulmoc $$(md5sum < $(S)/ulmoc | cut -c1-32)"

# objects compiled by another compiler are not reused
$(S)/compiler.id: $(OC) $(TOFGEN)
	@mkdir -p $(S)
	@cat $(OC) $(TOFGEN) | md5sum > $@.new
	@if cmp -s $@.new $@; then rm $@.new; \
	else rm -rf $(S)/obj $(S)/lib; mv $@.new $@; fi

# the run time system and the compiler first, then the rest of the library;
# ulmoc compiles imported modules as needed and keeps up-to-date objects
$(S)/compiled: $(S)/compiler.id $(ALL_SRC) $(ALL_DEF)
	@mkdir -p $(S)/obj
	@for src in $(ALL_SRC); do \
		echo "  OC      $$src"; \
		(cd $(S)/obj && $(abspath $(OC)) -a $(ARCH) $(INCS) \
			$(CURDIR)/$$src) || exit 1; \
	done
	@touch $@

$(MOD_OBJ): $(S)/compiled ;

$(S)/obj/%.o: $(S)/obj/%-mod-$(OBJARCH).obj
	@$(abspath $(TOFGEN)) -o $(@:.o=.tof) $<
	@$(TOF2ELF) -arch $(ARCH) -o $@ $(@:.o=.tof)
	@rm -f $(@:.o=.tof)

$(S)/lib/librtl.a: $(call objects,$(RTL_SRC))
$(S)/lib/libo.a: $(call objects,$(LIB_SRC))
$(S)/lib/libcompiler.a: $(call objects,$(COMPILER_SRC))
$(S)/lib/%.a:
	@echo "  AR      $@"
	@mkdir -p $(@D)
	@rm -f $@
	@$(AR) rcD $@ $^

$(S)/ulmoc: $(S)/lib/libcompiler.a $(S)/lib/libo.a $(S)/lib/librtl.a \
	$(GENOBRTS) $(LDSCRIPT) src/util/oblink/link-static.sh
	@main=Ulmo prog=$@ libs=$(S)/lib; $(LINK)

$(S)/obtofgen: $(S)/lib/libcompiler.a $(S)/lib/libo.a $(S)/lib/librtl.a \
	$(GENOBRTS) $(LDSCRIPT) src/util/oblink/link-static.sh
	@main=$(TOFGEN_MAIN) prog=$@ libs=$(S)/lib; $(LINK)
endif

# === check ================================================================

check: all stage3
	@cmp $(B)/stage2/ulmoc $(B)/stage3/ulmoc
	@cmp $(B)/stage2/obtofgen $(B)/stage3/obtofgen
	@echo "self-hosting: stages 2 and 3 are identical"
	@rm -rf $(B)/test
	@mkdir -p $(B)/test
	@cd $(B)/test && $(CURDIR)/$(ROOT)/bin/ulmo -arch $(ARCH) -m Hello \
		$(CURDIR)/src/test/Greeter.om $(CURDIR)/src/test/Hello.om >build.log
	@$(B)/test/Hello | cmp -s - src/test/Hello.expected
	@echo "test program: ok"

check-runtime: all
	sh src/test/runtime.sh $(ARCH)

check-cli: all
	sh src/test/cli.sh $(ARCH)

# === installation =========================================================

install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(ULMOLIBDIR)/$(ARCH) \
		$(DESTDIR)$(ULMOSRCDIR)
	sed -e 's|^ULMOLIBDIR=.*|ULMOLIBDIR=$${ULMOLIBDIR:-$(ULMOLIBDIR)}|' \
		-e 's|^ULMOSRCDIR=.*|ULMOSRCDIR=$${ULMOSRCDIR:-$(ULMOSRCDIR)}|' \
		src/util/ulmo/ulmo.sh >$(DESTDIR)$(BINDIR)/ulmo
	chmod 755 $(DESTDIR)$(BINDIR)/ulmo
	$(INSTALL) -m 755 $(TOF2ELF) $(DESTDIR)$(ULMOLIBDIR)/tof2elf
	$(INSTALL) -m 755 $(ROOTARCH)/ulmoc $(ROOTARCH)/obtofgen \
		$(ROOTARCH)/genobrts $(ROOTARCH)/oblink $(DESTDIR)$(ULMOLIBDIR)/$(ARCH)/
	$(INSTALL) -m 644 $(ROOTARCH)/oberon-$(ARCH).ld $(ROOTARCH)/librtl.a \
		$(ROOTARCH)/libo.a $(ROOTARCH)/libcompiler.a \
		$(DESTDIR)$(ULMOLIBDIR)/$(ARCH)/
	$(INSTALL) -d $(DESTDIR)$(ULMOLIBDIR)/$(ARCH)/obj
	$(INSTALL) -m 644 $(ROOTARCH)/obj/*.obj $(DESTDIR)$(ULMOLIBDIR)/$(ARCH)/obj/
	cp -R src/rtl src/lib src/compiler $(DESTDIR)$(ULMOSRCDIR)/

# the command, the converter and the sources are shared by all installed
# architectures and removed with the last one
uninstall:
	rm -rf $(DESTDIR)$(ULMOLIBDIR)/$(ARCH)
	@if [ -z "$$(ls $(DESTDIR)$(ULMOLIBDIR) | grep -v '^tof2elf$$')" ]; then \
		echo "rm -rf $(DESTDIR)$(ULMOLIBDIR) $(DESTDIR)$(DATADIR)/ulmo" \
			"$(DESTDIR)$(BINDIR)/ulmo"; \
		rm -rf $(DESTDIR)$(ULMOLIBDIR) $(DESTDIR)$(DATADIR)/ulmo \
			$(DESTDIR)$(BINDIR)/ulmo; \
	fi

clean:
	rm -rf build

# === programs of the compiler database (see Makefile.cdb) =================

CDB_TOOLS := OberonLoader:obload CDBDaemon:cdbd PersistentNameServer:pons \
	OberonCheckIn:obci CDBCheckoutSource:obco OberonZap:obzap \
	OberonDependencies:obdeps NamesShell:nsh NodeStatus:onsstat \
	ShutdownNode:onsshut MakeDirectory:onsmkdir PathWaiter:onswait

cdb-tools: stage2
	@mkdir -p $(B)/cdb
	@for tool in $(CDB_TOOLS); do \
		main=$${tool%%:*} prog=$(B)/cdb/$${tool#*:} libs=$(B)/stage2/lib; \
		$(LINK) || exit 1; \
	done
