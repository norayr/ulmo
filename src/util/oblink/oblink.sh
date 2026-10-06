#!/bin/sh
# Link whole Oberon modules, selecting the native timezone provider only
# when Timezones is present in the linked dependency closure.
set -eu
arch=$1
tooldir=$2
output=$3
main=$4
shift 4
AS=${AS:-as}
LD=${LD:-ld}
genobrts=${GENOBRTS:-$tooldir/genobrts}
script=${LDSCRIPT:-$tooldir/oberon-$arch.ld}
case "$arch" in
   amd64) asflags=--64; emulation=elf_x86_64 ;;
   i386) asflags=--32; emulation=elf_i386 ;;
   *) echo "oblink: unsupported architecture: $arch" >&2; exit 1 ;;
esac
norwxwarn=$("$LD" --help 2>/dev/null | grep -o -- --no-warn-rwx-segments | head -1)
start="$output.start"
trap 'rm -f "$start.s" "$start.o" "$start.trace"' 0 1 2 15
perl "$genobrts" "$main" >"$start.s"
"$AS" $asflags -o "$start.o" "$start.s"
if ! "$LD" -T "$script" -m "$emulation" $norwxwarn ${LDFLAGS:-} \
   --trace-symbol=Timezones___startup -o "$output" "$start.o" "$@" 2>"$start.trace"; then
   cat "$start.trace" >&2
   exit 1
fi
# Relay ordinary linker diagnostics, excluding the dependency probe itself.
perl -ne 'print STDERR unless /(?:reference to|definition of) Timezones___startup$/' "$start.trace"
if grep -q ': definition of Timezones___startup$' "$start.trace"; then
   perl "$genobrts" -t "$main" >"$start.s"
   "$AS" $asflags -o "$start.o" "$start.s"
   "$LD" -T "$script" -m "$emulation" $norwxwarn ${LDFLAGS:-} \
      -o "$output" "$start.o" "$@"
fi
