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

# Architecture-specific versions of run time modules (SRCROOT/rtl/<arch>)
# take precedence over the generic ones: they come first in the search path
# and are compiled first, so that every module sees the same interfaces.
ARCHSRCDIR="$SRCROOT/rtl/$(echo $OBJARCH | tr A-Z a-z)"
if [ -d "$ARCHSRCDIR" ]; then
    INCS="-I $ARCHSRCDIR $INCS"
    ALLSRC="$ARCHSRCDIR/*.om $ALLSRC"
fi

# Compile each module; ulmoc reuses the up-to-date .obj files of modules
# compiled before (their fingerprints are checked).
for om in $ALLSRC; do
    modname=$(basename "$om" .om)
    # a generic module overridden by an architecture-specific one
    [ -f "$ARCHSRCDIR/$modname.om" ] && [ "$om" != "$ARCHSRCDIR/$modname.om" ] && continue
    total=$((total + 1))
    if ! "$ULMO_OB" $ARCHFLAG $INCS "$om" >/dev/null 2>&1; then
        echo "  WARNING: $modname: compile failed (skipping)" >&2
        failed=$((failed + 1))
    fi
done
echo "build-libo: compiled $total modules ($failed failed)"

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
