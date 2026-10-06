#!/bin/sh

BINDIR=@BINDIR@
ARCH=@ARCH@

case "$ARCH" in
  i386)  LDSCRIPT="$BINDIR/oberon-i386.ld"; LDARCH=elf_i386; ASFLAGS="-32" ;;
  amd64) LDSCRIPT="$BINDIR/oberon-amd64.ld"; LDARCH=elf_x86_64; ASFLAGS="--64" ;;
  *)     echo "oblink: unknown arch: $ARCH" >&2; exit 1 ;;
esac

cmdname=`basename $0`
usage="Usage: $cmdname output lib {module}"
if [ $# -lt 3 ]
then
   echo >&2 "$usage"; exit 1
fi
outfile="$1"; shift
lib="$1"; shift

start=`mktemp /tmp/obstartXXXXXX`
trap "rm -f $start" 0
trap "rm -f $start; exit 1" 1 2 15

if $BINDIR/genobrts -t "$@" | as $ASFLAGS -o $start
then
   ld -T $LDSCRIPT -m $LDARCH -o $outfile $start $lib || exit 1
else
   exit 1
fi
