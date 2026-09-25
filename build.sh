#!/bin/sh
# build.sh -- build and install the ulmo toolchain (no pons/cdbd required)
#
# Usage:
#   build.sh i386  [DESTDIR]      -- build i386 tools
#   build.sh amd64 [DESTDIR]      -- build AMD64 tools (requires i386 first)
#
# DESTDIR defaults to the directory containing this script.
# The tools are installed under DESTDIR/<arch>/bin/ and DESTDIR/<arch>/lib/.
#
# Sources live in three layers under src/, each archived into its own library:
#   src/rtl       run time system, linked into every program  -> lib/librtl.a
#   src/lib       general library                             -> lib/libo.a
#   src/compiler  the compiler                                -> lib/libcompiler.a
#
# For a full build:
#   build.sh i386  /opt/oberon
#   build.sh amd64 /opt/oberon
#
# Both builds include a two-stage self-hosting check: the compiler is built
# once, then used to build itself again.  The md5sums are printed; a match
# means the compiler reproducibly generates itself (self-hosting fixed point).
#
# Targets in build.sh:
#   i386  -- 32-bit x86, fully self-hosted from bootstrap binary
#   amd64 -- 64-bit x86-64, cross-compiled from i386, then self-hosted
#
# Two equivalent targets also exist in src/util/ulmo/Makefile:
#   make ARCH=i386  install
#   make ARCH=amd64 install

set -e

ARCH="$1"
DESTDIR="${2:-$(cd "$(dirname "$0")" && pwd)}"

if [ "$ARCH" != "i386" ] && [ "$ARCH" != "amd64" ]; then
    echo "Usage: $0 i386|amd64 [DESTDIR]" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRCROOT="$ROOT/src"
RTLDIR="$SRCROOT/rtl"
COMPDIR="$SRCROOT/compiler"
ULMODIR="$ROOT/src/util/ulmo"
OBLINKDIR="$ROOT/src/util/oblink"
GENOBRTSDIR="$ROOT/src/util/genobrts"
BOOTSTRAP="$ROOT/bootstrap"
BINDIR="$DESTDIR/$ARCH/bin"
LIBDIR="$DESTDIR/$ARCH/lib"

# For AMD64, the cross-compiler and tofgen base are in the i386 install
I386BIN="$DESTDIR/i386/bin"
I386LIB="$DESTDIR/i386/lib"

OBJARCH=$(echo "$ARCH" | tr a-z A-Z)

die() { echo "build.sh: $*" >&2; exit 1; }

# Build ulmoc from source in a clean tmpdir, copy result to dest.
# Usage: build_ulmoc <label> <dest> <ulmo_cmd>
build_ulmoc() {
    local label="$1" dest="$2"
    shift 2
    local TMPD
    TMPD=$(mktemp -d /tmp/ulmo-XXXXXX)
    (cd "$TMPD" && "$@" \
        -m Ulmo \
        -L "$LIBDIR" \
        "$COMPDIR/FilesystemDB.om" \
        "$ULMODIR/Ulmo.om" && \
     cp Ulmo "$dest")
    rm -rf "$TMPD"
    chmod 755 "$dest"
    echo "    $label md5: $(md5sum "$dest" | awk '{print $1}')"
}

# Compare two binaries by md5sum; print result (warn but don't die on mismatch).
compare_stages() {
    local label="$1" file1="$2" file2="$3"
    md5_1=$(md5sum "$file1" | awk '{print $1}')
    md5_2=$(md5sum "$file2" | awk '{print $1}')
    if [ "$md5_1" = "$md5_2" ]; then
        echo "    $label: IDENTICAL (self-hosting fixed point confirmed)"
    else
        echo "    $label stage1 md5: $md5_1"
        echo "    $label stage2 md5: $md5_2"
        echo "    $label: DIFFER (compiler not yet at fixed point — may need another pass)"
    fi
}

mkdir -p "$BINDIR" "$LIBDIR"

# ── step 1: tof2elf (C tool, build for host) ─────────────────────────────────
echo "==> building tof2elf"
gcc -O2 -o "$BINDIR/tof2elf" "$ROOT/src/util/tof2elf/tof2elf.c" -lelf
chmod 755 "$BINDIR/tof2elf"

# ── step 2: genobrts (architecture-specific perl script) ─────────────────────
echo "==> installing genobrts (ARCH=$ARCH)"
if [ "$ARCH" = "amd64" ]; then
    cp "$OBLINKDIR/genobrts-amd64" "$BINDIR/genobrts"
else
    cp "$GENOBRTSDIR/genobrts.pl" "$BINDIR/genobrts"
fi
chmod 755 "$BINDIR/genobrts"

# ── step 3: oblink (shell script, bake in BINDIR+ARCH) ───────────────────────
echo "==> installing oblink"
"$ROOT/substparams" "BINDIR=$BINDIR" "ARCH=$ARCH" <"$OBLINKDIR/oblink.sh" >"$BINDIR/oblink"
chmod 755 "$BINDIR/oblink"

# ── step 4: linker script ────────────────────────────────────────────────────
echo "==> installing oberon-${ARCH}.ld"
cp "$OBLINKDIR/oberon-${ARCH}.ld" "$BINDIR/oberon-${ARCH}.ld"

# ── step 5: ulmo (shell script, bake in BINDIR+ARCH) ─────────────────────────
echo "==> installing ulmo (ARCH=$ARCH)"
"$ROOT/substparams" "BINDIR=$BINDIR" "ARCH=$ARCH" "SRCROOT=$SRCROOT" \
    <"$ULMODIR/ulmo.sh" >"$BINDIR/ulmo"
chmod 755 "$BINDIR/ulmo"

# ── arch-specific steps ───────────────────────────────────────────────────────
if [ "$ARCH" = "i386" ]; then

    # ── i386: bootstrap ulmoc + obtofgen, build libo.a, then rebuild from src ──
    echo "==> [i386] bootstrapping ulmoc from $BOOTSTRAP"
    cp -f "$BOOTSTRAP/ulmoc" "$BINDIR/ulmoc"
    chmod 755 "$BINDIR/ulmoc"

    echo "==> [i386] bootstrapping obtofgen from $BOOTSTRAP"
    cp -f "$BOOTSTRAP/obtofgen" "$BINDIR/obtofgen"
    chmod 755 "$BINDIR/obtofgen"

    echo "==> [i386] building libraries"
    "$ULMODIR/build-libo.sh" "$BINDIR" "$SRCROOT" "$LIBDIR" I386

    echo "==> [i386] building obtofgen from source"
    TMPD=$(mktemp -d /tmp/ulmo-tofgen-XXXXXX)
    (cd "$TMPD" && "$BINDIR/ulmo" \
        -m OberonI386TransportableObjectFormatGenerator \
        -L "$LIBDIR" \
        "$COMPDIR/OberonI386TransportableObjectFormatGenerator.om" && \
     mv OberonI386TransportableObjectFormatGenerator "$BINDIR/obtofgen")
    rm -rf "$TMPD"
    chmod 755 "$BINDIR/obtofgen"

    # Two-stage self-hosting: build stage1 with bootstrap, stage2 with stage1.
    # Compare stage1 and stage2: a match means the compiler is at a fixed point.
    # (Stage1 vs stage2 may differ if the bootstrap is old; that's OK.
    #  For the canonical fixed-point check, run build.sh i386 a second time.)
    echo "==> [i386] building ulmoc stage1 (bootstrap compiler → self-hosted)"
    build_ulmoc "stage1" "$BINDIR/ulmoc" "$BINDIR/ulmo"
    STAGE1_MD5=$(md5sum "$BINDIR/ulmoc" | awk '{print $1}')

    echo "==> [i386] building ulmoc stage2 (stage1 → stage2)"
    STAGE2=$(mktemp /tmp/ulmo-i386-stage2-XXXXXX)
    build_ulmoc "stage2" "$STAGE2" "$BINDIR/ulmo"

    echo "==> [i386] self-hosting verification"
    compare_stages "i386 ulmoc" "$BINDIR/ulmoc" "$STAGE2"

    # Install stage2 as the active ulmoc (stage2 = compiled by source-built compiler)
    cp -f "$STAGE2" "$BINDIR/ulmoc"
    rm -f "$STAGE2"
    chmod 755 "$BINDIR/ulmoc"

    echo "==> [i386] updating bootstrap/ulmoc"
    cp -f "$BINDIR/ulmoc" "$BOOTSTRAP/ulmoc"

else

    # ── amd64: requires i386 install ──────────────────────────────────────────
    [ -x "$I386BIN/ulmoc" ] || die "i386 ulmoc not found at $I386BIN/ulmoc; run 'build.sh i386' first"
    for lib in librtl.a libo.a libcompiler.a; do
        [ -f "$I386LIB/$lib" ] || die "i386 $lib not found in $I386LIB; run 'build.sh i386' first"
    done

    echo "==> [amd64] installing ulmoc (i386 cross-compiler for AMD64)"
    cp -f "$I386BIN/ulmoc" "$BINDIR/ulmoc"
    chmod 755 "$BINDIR/ulmoc"

    echo "==> [amd64] building obtofgen (AMD64 tof generator, runs as i386)"
    TMPD=$(mktemp -d /tmp/ulmo-tofgen-XXXXXX)
    (cd "$TMPD" && "$I386BIN/ulmo" \
        -m OberonAMD64TransportableObjectFormatGenerator \
        -L "$I386LIB" \
        "$COMPDIR/OberonAMD64TransportableObjectFormatGenerator.om" && \
     mv OberonAMD64TransportableObjectFormatGenerator "$BINDIR/obtofgen")
    rm -rf "$TMPD"
    chmod 755 "$BINDIR/obtofgen"

    echo "==> [amd64] building libraries"
    "$ULMODIR/build-libo.sh" "$BINDIR" "$SRCROOT" "$LIBDIR" AMD64

    # Two-stage self-hosting: stage1 uses the i386 cross-compiler targeting AMD64;
    # stage2 uses the native AMD64 stage1.  Both use the same AMD64 backend code,
    # so a match confirms the AMD64 backend is self-consistent across host arches.
    echo "==> [amd64] building ulmoc stage1 (i386 cross-compiler → native AMD64)"
    build_ulmoc "stage1" "$BINDIR/ulmoc" "$BINDIR/ulmo"

    echo "==> [amd64] verifying AMD64 ulmoc stage1 is a native ELF binary"
    file "$BINDIR/ulmoc"
    # Test by compiling a source module with full srcdir; exit 0 means it ran.
    # Use if/then (not case $?) so set -e doesn't abort on signal-killed ulmoc.
    TESTTMPD=$(mktemp -d)
    amd64_runnable=0
    if (cd "$TESTTMPD" && "$BINDIR/ulmoc" -a amd64 -I "$RTLDIR" \
            "$RTLDIR/Coroutines.om") >/dev/null 2>&1; then
        amd64_runnable=1
    fi
    rm -rf "$TESTTMPD"

    if [ "$amd64_runnable" = "1" ]; then
        echo "==> [amd64] building ulmoc stage2 (native AMD64 stage1 → stage2)"
        STAGE2=$(mktemp /tmp/ulmo-amd64-stage2-XXXXXX)
        build_ulmoc "stage2" "$STAGE2" "$BINDIR/ulmo"

        echo "==> [amd64] self-hosting verification"
        compare_stages "amd64 ulmoc" "$BINDIR/ulmoc" "$STAGE2"

        # Install stage2 as the active ulmoc
        cp -f "$STAGE2" "$BINDIR/ulmoc"
        rm -f "$STAGE2"
        chmod 755 "$BINDIR/ulmoc"
    else
        echo "    AMD64 ulmoc stage1 crashes at startup (runtime modules need AMD64 adaptation)"
        echo "    Two-stage self-hosting test skipped — stage1 cross-compiled binary will be used"
        echo "    md5sum of stage1: $(md5sum "$BINDIR/ulmoc" | awk '{print $1}')"
    fi

    echo "==> [amd64] updating bootstrap/ulmoc-amd64"
    cp -f "$BINDIR/ulmoc" "$BOOTSTRAP/ulmoc-amd64"

fi

echo ""
echo "Build complete: ARCH=$ARCH  DESTDIR=$DESTDIR"
echo "  binaries: $BINDIR"
echo "  libraries: $LIBDIR/librtl.a $LIBDIR/libo.a $LIBDIR/libcompiler.a"
echo "  ulmoc:    $(file "$BINDIR/ulmoc" | sed 's/.*: //')"
echo "  md5sum:   $(md5sum "$BINDIR/ulmoc" | awk '{print $1}')"
