#!/bin/sh
# build-libo-amd64.sh -- compile all library modules for AMD64 and archive into libo-amd64.a
#
# Usage: build-libo-amd64.sh BINDIR SRCDIR LIBDIR
#
# Compiles every .om file in SRCDIR using BINDIR/ulmoc -a amd64, converts
# each mod-AMD64.obj to a .o via BINDIR/obtofgen-amd64 + BINDIR/tof2elf -arch amd64,
# and archives all .o files into LIBDIR/libo-amd64.a.

set -e
BINDIR="$1"
SRCDIR="$2"
LIBDIR="$3"

if [ -z "$BINDIR" ] || [ -z "$SRCDIR" ] || [ -z "$LIBDIR" ]; then
    echo "Usage: $0 BINDIR SRCDIR LIBDIR" >&2
    exit 1
fi

ULMOC="$BINDIR/ulmoc"
OBTOFGEN="$BINDIR/obtofgen-amd64"
TOF2ELF="$BINDIR/tof2elf"

for tool in "$ULMOC" "$OBTOFGEN" "$TOF2ELF"; do
    if [ ! -x "$tool" ]; then
        echo "build-libo-amd64: required tool not found: $tool" >&2
        exit 1
    fi
done

TMPDIR=$(mktemp -d /tmp/ulmo-lib-amd64-XXXXXX)
trap "rm -rf $TMPDIR" 0 1 2 15

echo "build-libo-amd64: compiling library modules from $SRCDIR ..."
echo "build-libo-amd64: output: $LIBDIR/libo-amd64.a"
echo "build-libo-amd64: build dir: $TMPDIR"

cd "$TMPDIR"

failed=0
total=0
for om in "$SRCDIR"/*.om; do
    modname=$(basename "$om" .om)
    total=$((total + 1))
    if ! "$ULMOC" -a amd64 -I "$SRCDIR" "$om" >/dev/null 2>&1; then
        echo "  WARNING: $modname: compile failed (skipping)" >&2
        failed=$((failed + 1))
    fi
done
echo "build-libo-amd64: compiled $total modules ($failed failed)"

obj_count=0
for obj in ./*-mod-AMD64.obj; do
    [ -f "$obj" ] || continue
    modname=$(basename "$obj" -mod-AMD64.obj)
    toffile="$modname-amd64.tof"
    ofile="$modname.o"
    "$OBTOFGEN" -o "$toffile" "$obj" || { echo "build-libo-amd64: obtofgen failed for $modname" >&2; exit 1; }
    "$TOF2ELF" -arch amd64 -o "$ofile" "$toffile" || { rm -f "$toffile"; echo "build-libo-amd64: tof2elf failed for $modname" >&2; exit 1; }
    rm -f "$toffile"
    obj_count=$((obj_count + 1))
done
echo "build-libo-amd64: converted $obj_count modules to .o"

mkdir -p "$LIBDIR"
rm -f "$LIBDIR/libo-amd64.a"
ar q "$LIBDIR/libo-amd64.a" ./*.o
echo "build-libo-amd64: $LIBDIR/libo-amd64.a created ($obj_count modules)"
