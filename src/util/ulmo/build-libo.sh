#!/bin/sh
# build-libo.sh -- compile all library modules from source and archive them
#
# Usage: build-libo.sh BINDIR SRCROOT LIBDIR [OBJARCH [TOFGEN_BINDIR]]
#
# SRCROOT contains the three source layers, each archived separately:
#   SRCROOT/rtl       run time system: modules linked into every program
#                     (SRCROOT/rtl/amd64 holds AMD64-specific versions)
#                     -> LIBDIR/librtl.a
#   SRCROOT/lib       general library                  -> LIBDIR/libo.a
#   SRCROOT/compiler  the compiler and its database    -> LIBDIR/libcompiler.a
# rtl imports only rtl, lib imports rtl and lib, compiler may import all.
#
# OBJARCH is the uppercase arch tag used in .obj filenames (I386 or AMD64).
# Defaults to I386.
#
# TOFGEN_BINDIR: directory containing obtofgen and tof2elf for the target arch.
# Defaults to BINDIR. For AMD64 builds, pass the amd64 bin dir here since
# amd64/bin/obtofgen knows AMD64OberonResults while i386/bin/obtofgen does not.
#
# Compiles every .om file of the three layers using BINDIR/ulmoc, converts
# each mod-OBJARCH.obj to a .o via TOFGEN_BINDIR/obtofgen + TOFGEN_BINDIR/tof2elf,
# and archives the .o files of each layer.
#
# Runs in a temporary directory; all output goes to LIBDIR.
# Module compilation failures are reported but do not abort the build
# (some architecture-specific or optional modules may not compile).

set -e
set -x
BINDIR="$1"
SRCROOT="$2"
LIBDIR="$3"
OBJARCH="${4:-I386}"
TOFGEN_BINDIR="${5:-$BINDIR}"

if [ -z "$BINDIR" ] || [ -z "$SRCROOT" ] || [ -z "$LIBDIR" ]; then
    echo "Usage: $0 BINDIR SRCROOT LIBDIR [OBJARCH [TOFGEN_BINDIR]]" >&2
    exit 1
fi

ULMO_OB="$BINDIR/ulmoc"
OBTOFGEN="$TOFGEN_BINDIR/obtofgen"
TOF2ELF="$TOFGEN_BINDIR/tof2elf"

for tool in "$ULMO_OB" "$OBTOFGEN" "$TOF2ELF"; do
    if [ ! -x "$tool" ]; then
        echo "build-libo: required tool not found: $tool" >&2
        exit 1
    fi
done

LAYERS="rtl lib compiler"
INCS=""
ALLSRC=""
for layer in $LAYERS; do
    [ -d "$SRCROOT/$layer" ] || { echo "build-libo: missing $SRCROOT/$layer" >&2; exit 1; }
    INCS="$INCS -I $SRCROOT/$layer"
    ALLSRC="$ALLSRC $SRCROOT/$layer/*.om"
done

TMPDIR=$(mktemp -d /tmp/ulmo-lib-XXXXXX)
trap "rm -rf $TMPDIR" 0 1 2 15

echo "build-libo: compiling library modules from $SRCROOT ($LAYERS) ..."
echo "build-libo: output: $LIBDIR"
echo "build-libo: build dir: $TMPDIR"

cd "$TMPDIR"

# Compile each .om file.  ulmoc caches .obj files so transitive deps that
# were already compiled by a previous invocation are reused.
ARCHFLAG=""
[ "$OBJARCH" != "I386" ] && ARCHFLAG="-a $(echo $OBJARCH | tr A-Z a-z)"
TOFARCH=""
[ "$OBJARCH" != "I386" ] && TOFARCH="-arch $(echo $OBJARCH | tr A-Z a-z)"

failed=0
total=0

if [ "$OBJARCH" != "I386" ]; then
    # For non-i386 architectures (e.g. AMD64): compile ALL modules in a single
    # ulmoc invocation.  This keeps AMD64 TypeDisciplines in process memory so
    # that types with private (non-exported) fields — like Events.EventTypeRec —
    # have their correct AMD64 sizes available when dependent modules (e.g.
    # SysSignals) are compiled later.  With per-module invocations the
    # Disciplines.Add cache is lost between processes, causing size=0 for
    # imported record types whose private fields are stripped from the .def file.
    ARCHSRCDIR="$SRCROOT/rtl/$(echo $OBJARCH | tr A-Z a-z)"
    # Step 1: Pre-compile stub/no-op modules that need to override the batch
    # BEFORE the batch runs, so the batch reuses them.  Only pre-compile modules
    # that do NOT import Sys (to avoid poisoning the tmpdir with wrong Sys values).
    # SysSignalOperations.om is the critical one: its no-op stub avoids the
    # wrong-syscall-number crash (rtsigprocmask=175 vs AMD64 rt_sigprocmask=14).
    # Step 2: Compile all library modules in one shot (batch).
    # Provide AMD64 Sys.od/Sys.om to fix syscall numbers (mmap=9, brk=12 etc.).
    SYSONLY_TMP=$(mktemp -d)
    cp "$ARCHSRCDIR/Sys.od" "$SYSONLY_TMP/" 2>/dev/null || true
    cp "$ARCHSRCDIR/Sys.om" "$SYSONLY_TMP/" 2>/dev/null || true
    total=$(ls $ALLSRC 2>/dev/null | wc -l)
    if ! "$ULMO_OB" $ARCHFLAG -I "$SYSONLY_TMP" $INCS $ALLSRC >/dev/null 2>&1; then
        echo "  WARNING: batch compile had failures (some modules may be missing)" >&2
        failed=1
    fi
    rm -rf "$SYSONLY_TMP"
    # Step 3: Post-batch overrides for modules with AMD64-specific implementations
    # (SysArgs, SysSegments, SysModules etc.).
    if [ -d "$ARCHSRCDIR" ]; then
        for archom in "$ARCHSRCDIR"/*.om; do
            [ -f "$archom" ] || continue
            modname=$(basename "$archom" .om)
            [ "$modname" = "SysSignalOperations" ] && continue
            [ "$modname" = "SysTime" ] && continue  # handled in Step 5 (fresh dir)
            rm -f "${modname}-def-gen.obj" "${modname}-def-${OBJARCH}.obj" \
                  "${modname}-mod-${OBJARCH}.obj"
            "$ULMO_OB" $ARCHFLAG -I "$ARCHSRCDIR" $INCS "$archom" >/dev/null 2>&1 || true
        done
    fi
    # Step 4: Recompile SysStorage.om with AMD64 SysSegments.od so that the
    # segment record access code uses 8-byte (SYS.UNTRACEDADDRESS) reads,
    # matching the runtime layout of the SysSegments.segments global array.
    # The batch above compiled SysStorage with the generic LONGINT-based
    # SysSegments.od; this step replaces that .obj with the correct one.
    #
    # IMPORTANT: run in a FRESH directory containing only the AMD64 SysSegments
    # .obj files.  If we run in the main TMPDIR, ulmoc finds the batch-compiled
    # .obj files (which have GENERIC/LONGINT SysSegments type versions) and
    # hits an internal assertion in CompilerDatabases.LookupHeader because the
    # type versions are inconsistent with the AMD64 SysSegments.od declaration.
    if [ -d "$ARCHSRCDIR" ] && [ -f "$ARCHSRCDIR/SysSegments.od" ]; then
        STEP4_TMP=$(mktemp -d)
        # Seed the clean dir with only the AMD64-typed SysSegments obj files
        # (produced by step 3 above).  No other batch .obj files should be here.
        for f in "SysSegments-def-gen.obj" "SysSegments-def-${OBJARCH}.obj" \
                 "SysSegments-mod-${OBJARCH}.obj"; do
            [ -f "$f" ] && cp "$f" "$STEP4_TMP/"
        done
        ( cd "$STEP4_TMP" && \
          "$ULMO_OB" $ARCHFLAG -I "$ARCHSRCDIR" $INCS \
              "$SRCROOT/rtl/SysStorage.om" >/dev/null 2>&1 )
        if [ -f "$STEP4_TMP/SysStorage-mod-${OBJARCH}.obj" ]; then
            cp "$STEP4_TMP/SysStorage-mod-${OBJARCH}.obj" \
               "SysStorage-mod-${OBJARCH}.obj"
            cp "$STEP4_TMP/SysStorage-def-${OBJARCH}.obj" \
               "SysStorage-def-${OBJARCH}.obj" 2>/dev/null || true
            echo "build-libo: SysStorage recompiled with AMD64 SysSegments types"
        else
            echo "build-libo: WARNING: SysStorage step4 failed — SysStorage.o will be missing" >&2
        fi
        rm -rf "$STEP4_TMP"
    fi
    # Step 5: Compile AMD64-specific SysTime.om in a fresh directory.
    # SysTime must use Timeval64/Tms64/Itimerval64 (lo+hi LONGINT pairs) to avoid
    # overflowing the 8-byte Oberon TimeVal with the 16-byte kernel struct timeval.
    # Cannot compile in TMPDIR because the batch-compiled .obj type versions cause
    # a LookupHeader assertion when a new ulmoc process reads them and then
    # encounters the AMD64-specific SysTime.om types.
    if [ -d "$ARCHSRCDIR" ] && [ -f "$ARCHSRCDIR/SysTime.om" ]; then
        STEP5_TMP=$(mktemp -d)
        ( cd "$STEP5_TMP" && \
          "$ULMO_OB" $ARCHFLAG -I "$ARCHSRCDIR" $INCS \
              "$ARCHSRCDIR/SysTime.om" >/dev/null 2>&1 )
        if [ -f "$STEP5_TMP/SysTime-mod-${OBJARCH}.obj" ]; then
            cp "$STEP5_TMP/SysTime-mod-${OBJARCH}.obj" \
               "SysTime-mod-${OBJARCH}.obj"
            cp "$STEP5_TMP/SysTime-def-${OBJARCH}.obj" \
               "SysTime-def-${OBJARCH}.obj" 2>/dev/null || true
            echo "build-libo: SysTime recompiled with AMD64 timeval implementation"
        else
            echo "build-libo: WARNING: SysTime step5 failed — SysTime.o will use generic version" >&2
        fi
        rm -rf "$STEP5_TMP"
    fi
    echo "build-libo: compiled $total modules ($failed batch failures)"
else
    for om in $ALLSRC; do
        modname=$(basename "$om" .om)
        total=$((total + 1))
        if ! "$ULMO_OB" $ARCHFLAG $INCS "$om" >/dev/null 2>&1; then
            echo "  WARNING: $modname: compile failed (skipping)" >&2
            failed=$((failed + 1))
        fi
    done
    echo "build-libo: compiled $total modules ($failed failed)"
fi

# Convert all mod-OBJARCH.obj files to ELF .o via obtofgen + tof2elf.
obj_count=0
for obj in ./*-mod-${OBJARCH}.obj; do
    [ -f "$obj" ] || continue
    modname=$(basename "$obj" -mod-${OBJARCH}.obj)
    toffile="$modname.tof"
    ofile="$modname.o"
    "$OBTOFGEN" -o "$toffile" "$obj" || { echo "build-libo: obtofgen failed for $modname" >&2; exit 1; }
    "$TOF2ELF" $TOFARCH -o "$ofile" "$toffile" || { rm -f "$toffile"; echo "build-libo: tof2elf failed for $modname" >&2; exit 1; }
    rm -f "$toffile"
    obj_count=$((obj_count + 1))
done
echo "build-libo: converted $obj_count modules to .o"

# Archive each layer separately; every .o must belong to exactly one layer.
mkdir -p "$LIBDIR"
archived=0
for layer in $LAYERS; do
    case $layer in
    rtl) archive="$LIBDIR/librtl.a" ;;
    lib) archive="$LIBDIR/libo.a" ;;
    compiler) archive="$LIBDIR/libcompiler.a" ;;
    esac
    members=""
    for om in "$SRCROOT/$layer"/*.om; do
        modname=$(basename "$om" .om)
        [ -f "$modname.o" ] && members="$members $modname.o"
    done
    rm -f "$archive"
    n=$(echo $members | wc -w)
    ar q "$archive" $members
    archived=$((archived + n))
    echo "build-libo: $archive created ($n modules)"
done
if [ "$archived" -ne "$obj_count" ]; then
    echo "build-libo: $((obj_count - archived)) .o files belong to no layer" >&2
    exit 1
fi
