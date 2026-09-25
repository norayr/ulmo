#!/bin/sh
# ulmo - shell script to compile and link.
#
# compiles Oberon source files (.od/.om/.mod) without pons/cdbd.
# by default, compiles to .o only (-c mode).
# use -m MainModule to also link a resulting binary.
#
# Usage:
#   ulmo [-I srcdir]... sourcefile [sourcefile...]
#       Compile each .om/.mod to a .o  (like gcc -c)
#
#   ulmo [-I srcdir]... -m MainModule [-o outfile] sourcefile [sourcefile...]
#       Compile each .om/.mod to a .o, then link into a binary.
#       ulmoc automatically compiles all transitive dependencies; any that
#       are not already in one of the libraries are also converted to .o and
#       linked in.
#       We only need to list the source files you are directly building;
#       their dependencies are found automatically via -I paths.
#
#   ulmo [-I srcdir]... -S sourcefile [sourcefile...]
#       Compile each .om/.mod and emit a .tof file (text IR, like -S for asm).
#       No .o or binary is produced.
#
# LIBDIR defaults to BINDIR/../lib; override with -L or OBERON_LIBDIR env var.
# It holds librtl.a (run time system), libo.a (general library) and
# libcompiler.a (the compiler).
#
# The sources of these libraries (SRCROOT/rtl, SRCROOT/lib, SRCROOT/compiler)
# are searched after any -I directories.

BINDIR=@BINDIR@
ARCH=@ARCH@
SRCROOT=@SRCROOT@
LIBDIR="${OBERON_LIBDIR:-${BINDIR}/../lib}"
LIBS="libcompiler.a libo.a librtl.a"   # in link order: compiler -> lib -> rtl

case "$ARCH" in
  i386)  OBJARCH=I386;  LDARCH=elf_i386;   ASFLAGS="-32";  LDSCRIPT="$BINDIR/oberon-i386.ld"  ;;
  amd64) OBJARCH=AMD64; LDARCH=elf_x86_64; ASFLAGS="--64"; LDSCRIPT="$BINDIR/oberon-amd64.ld" ;;
  *)     echo "ulmo: unknown arch: $ARCH" >&2; exit 1 ;;
esac

cmdname=`basename $0`

usage() {
   cat >&2 <<EOF
Usage: $cmdname [options] sourcefile [sourcefile...]
Options:
  -I srcdir          Add srcdir to source search path
  -m MainModule      Link .o files into binary named MainModule (or -o name)
  -o outfile         Set output binary name (implies -m if module name omitted)
  -L libdir          Directory containing the libraries (default: BINDIR/../lib)
  -S                 Emit .tof (text IR) instead of .o; do not link
EOF
   exit 1
}

if [ $# -eq 0 ]; then usage; fi

iflags=""
main_module=""
out_file=""
libdir="$LIBDIR"
asm_only=0

while [ $# -gt 0 ]; do
   case "$1" in
   -I)  [ $# -lt 2 ] && usage; iflags="$iflags -I $2"; shift 2 ;;
   -I*) iflags="$iflags -I${1#-I}"; shift ;;
   -m)  [ $# -lt 2 ] && usage; main_module="$2"; shift 2 ;;
   -o)  [ $# -lt 2 ] && usage; out_file="$2"; shift 2 ;;
   -L)  [ $# -lt 2 ] && usage; libdir="$2"; shift 2 ;;
   -L*) libdir="${1#-L}"; shift ;;
   -S)  asm_only=1; shift ;;
   --)  shift; break ;;
   -*)  echo "$cmdname: unknown option: $1" >&2; usage ;;
   *)   break ;;
   esac
done

[ $# -eq 0 ] && usage
sources="$*"
iflags="$iflags -I $SRCROOT/rtl -I $SRCROOT/lib -I $SRCROOT/compiler"

# For each .om source, ensure a .od definition file exists somewhere ulmoc
# can find it.  ULM Oberon requires a .od (even an empty one) to generate the
# public interface object.  For program modules with no exports, we create a
# minimal stub in the current directory.
for sourcefile in $sources; do
   base=`basename "$sourcefile"`
   suffix="${base##*.}"
   modname="${base%.*}"
   srcdir=`dirname "$sourcefile"`
   if [ "$suffix" = "om" ] || [ "$suffix" = "mod" ]; then
      # Look for .od alongside the source file and in CWD
      if [ ! -f "$srcdir/$modname.od" ] && [ ! -f "$modname.od" ]; then
         printf "DEFINITION %s;\nEND %s.\n" "$modname" "$modname" > "$modname.od"
      fi
   fi
done

# -o without -m: derive module name from output filename
if [ -n "$out_file" ] && [ -z "$main_module" ]; then
   main_module=`basename "$out_file"`
fi
# -m without -o: binary name == module name
if [ -n "$main_module" ] && [ -z "$out_file" ]; then
   out_file="$main_module"
fi

#  Step 1: run the Oberon compiler for all source files
# ulmoc compiles each file and all transitive dependencies, writing .obj
# files to the current directory.  (Cached deps are reused on re-runs.)
# Include CWD so ulmoc finds any .od stubs we created above.
archflag=""
[ "$ARCH" != "i386" ] && archflag="-a $ARCH"
if ! $BINDIR/ulmoc $archflag -I . $iflags "$@"; then
   exit 1
fi

#  Step 2: convert each listed .om/.mod to .o (or .tof if -S)
obj_files=""
for sourcefile in $sources; do
   base=`basename "$sourcefile"`
   suffix="${base##*.}"
   modname="${base%.*}"

   case "$suffix" in
   om|mod)
      objfile="${modname}-mod-${OBJARCH}.obj"
      if [ ! -f "$objfile" ]; then
         echo "$cmdname: expected $objfile not found" >&2
         exit 1
      fi
      if [ "$asm_only" -eq 1 ]; then
         toffile="${modname}.tof"
         $BINDIR/obtofgen -o "$toffile" "$objfile" || exit 1
         echo "$cmdname: $sourcefile -> $toffile"
      else
         toffile="${modname}-mod-${OBJARCH}.tof"
         ofile="${modname}.o"
         $BINDIR/obtofgen -o "$toffile" "$objfile" || exit 1
         $BINDIR/tof2elf -arch $ARCH -o "$ofile" "$toffile" || { rm -f "$toffile"; exit 1; }
         rm -f "$toffile"
         echo "$cmdname: $sourcefile -> $ofile"
         obj_files="$obj_files $ofile"
      fi
      ;;
   od)
      # Definition-only: produces ModName-def-gen.obj.  No code output.
      ;;
   *)
      echo "$cmdname: unknown suffix: $suffix" >&2
      exit 1
      ;;
   esac
done

[ "$asm_only" -eq 1 ] && exit 0

#  Step 3: link (only when -m / -o was given)
[ -z "$main_module" ] && exit 0

libfiles=""
for lib in $LIBS; do
   if [ ! -f "$libdir/$lib" ]; then
      echo "$cmdname: $lib not found in $libdir" >&2
      echo "$cmdname: set OBERON_LIBDIR or use -L to specify its directory" >&2
      exit 1
   fi
   libfiles="$libfiles $libdir/$lib"
done

# Auto-discover dependency .o files.
# ulmoc compiled all transitive dependencies to mod-${OBJARCH}.obj.  Any module
# not already in one of the libraries must be linked explicitly — convert
# those to .o now.
libo_modules=`for f in $libfiles; do ar t "$f"; done 2>/dev/null | sed 's/\.o$//'`
for obj in ./*-mod-${OBJARCH}.obj; do
   [ -f "$obj" ] || continue
   mod=`basename "$obj" -mod-${OBJARCH}.obj`
   # Skip if already in a library
   echo "$libo_modules" | grep -qx "$mod" && continue
   # Skip if we already produced this .o from an explicit source above
   echo "$obj_files" | grep -qw "${mod}.o" && continue
   toffile="${mod}-mod-${OBJARCH}.tof"
   ofile="${mod}.o"
   $BINDIR/obtofgen -o "$toffile" "$obj" || exit 1
   $BINDIR/tof2elf -arch $ARCH -o "$ofile" "$toffile" || { rm -f "$toffile"; exit 1; }
   rm -f "$toffile"
   echo "$cmdname: dep $mod -> $ofile"
   obj_files="$obj_files $ofile"
done

start_s="${out_file}.__start.s"
start_o="${out_file}.__start.o"
trap "rm -f ${start_s} ${start_o}" 0 1 2 15

$BINDIR/genobrts "$main_module" > "$start_s" || exit 1
as $ASFLAGS -o "$start_o" "$start_s" || exit 1
ld -T "$LDSCRIPT" -m $LDARCH \
   -o "$out_file" "$start_o" $obj_files $libfiles || exit 1
echo "$cmdname: linked -> $out_file"
