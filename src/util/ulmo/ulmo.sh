#!/bin/sh
# ulmo -- compile and link programs written in Ulm's Oberon
#
# Usage:
#   ulmo [options] sourcefile...
#       compile each .om (or .mod) to a .o
#   ulmo [options] -m MainModule [-o outfile] sourcefile...
#       compile, then link a program whose main module is MainModule
#   ulmo [options] -m MainModule.om [-o outfile] [sourcefile...]
#       infer the main module from the source header and compile that file
#   ulmo [options] -S sourcefile...
#       compile each .om and emit the .tof intermediate text instead of a .o
#
# ulmoc compiles the imported modules as needed; the library modules are
# linked from the libraries of the target architecture, all other imported
# modules are converted to .o files and linked in, too.
#
# Files used (make install replaces the two defaults below):
#   ULMOLIBDIR/tof2elf              TOF to ELF converter
#   ULMOLIBDIR/ARCH/                ulmoc, obtofgen, genobrts, linker script,
#                                   librtl.a, libo.a, libcompiler.a
#   ULMOLIBDIR/ARCH/obj/            compiled interfaces and objects of the
#                                   library modules (used while up to date)
#   ULMOSRCDIR/{rtl,lib,compiler}   sources of the libraries; rtl/ARCH holds
#                                   architecture-specific run time modules

here=`dirname "$0"`
here=`cd "$here" && pwd`
ULMOLIBDIR=${ULMOLIBDIR:-$here/../lib/ulmo}
ULMOSRCDIR=${ULMOSRCDIR:-$here/../share/ulmo/src}
AS=${AS:-as}
LD=${LD:-ld}

cmdname=`basename "$0"`

usage() {
   cat >&2 <<EOF
Usage: $cmdname [options] sourcefile...
Options:
  -arch ARCH      target architecture (installed: `ls "$ULMOLIBDIR" 2>/dev/null | grep -v tof2elf | tr '\n' ' '`)
  -I dir          add dir to the source search path
   -m [MainModule] link a program; infer the name from a module source if omitted
   -m Main.om      select and compile Main.om as the main module
  -o outfile      name of the program (default: name of the main module)
  -L dir          take the libraries from dir instead of ULMOLIBDIR/ARCH
  -S              emit .tof files instead of .o files; do not link
  -v level        let ulmoc log why modules are (re)compiled or reused
                  (6: up-to-date checks)
EOF
   exit 1
}

# default architecture: the host's if installed, else the only one installed
case `uname -m` in
x86_64|amd64)  arch=amd64 ;;
i?86)          arch=i386 ;;
*)             arch=`uname -m` ;;
esac
if [ ! -d "$ULMOLIBDIR/$arch" ]; then
   installed=`ls "$ULMOLIBDIR" 2>/dev/null | grep -v '^tof2elf$'`
   [ `echo $installed | wc -w` -eq 1 ] && arch=$installed
fi

iflags=""
main_module=""
main_source=""
infer_main=0
out_file=""
libdir=""
asm_only=0
vflags=""

while [ $# -gt 0 ]; do
   case "$1" in
   -arch) [ $# -lt 2 ] && usage; arch="$2"; shift 2 ;;
   -I)    [ $# -lt 2 ] && usage; iflags="$iflags -I $2"; shift 2 ;;
   -I*)   iflags="$iflags -I${1#-I}"; shift ;;
    -m)
       infer_main=0; main_module=""; main_source=""
       if [ $# -eq 1 ]; then
          infer_main=1; shift
       else
          case "$2" in
          *.om|*.mod) infer_main=1; main_source="$2"; shift 2 ;;
          -*|*.od)   infer_main=1; shift ;;
          *)         main_module="$2"; shift 2 ;;
          esac
       fi
       ;;
   -o)    [ $# -lt 2 ] && usage; out_file="$2"; shift 2 ;;
   -L)    [ $# -lt 2 ] && usage; libdir="$2"; shift 2 ;;
   -L*)   libdir="${1#-L}"; shift ;;
   -S)    asm_only=1; shift ;;
   -v)    [ $# -lt 2 ] && usage; vflags="-v $2"; shift 2 ;;
   --)    shift; break ;;
   -*)    echo "$cmdname: unknown option: $1" >&2; usage ;;
   *)     break ;;
   esac
done
[ $# -eq 0 ] && [ -z "$main_source" ] && usage
sources="$*"
if [ -n "$main_source" ]; then
   sources="$main_source $sources"
fi

if [ "$infer_main" -eq 1 ]; then
   if [ -z "$main_source" ]; then
      for sourcefile in $sources; do
         case "$sourcefile" in
         *.om|*.mod)
            if [ -n "$main_source" ]; then
               echo "$cmdname: several module sources; select one with -m Main or -m Main.om" >&2
               exit 1
            fi
            main_source="$sourcefile"
            ;;
         esac
      done
   fi
   [ -n "$main_source" ] || usage
   # Read only the header: whitespace and nested comments may precede or
   # separate its tokens. The compiler handles the rest of the source.
   main_module=$(perl -e '
      use strict;
      use warnings;
      my ($file, $cmd) = @ARGV;
      open(my $in, "<", $file) or die "$cmd: $file: $!\n";
      my $ch = getc($in);
      sub advance { $ch = getc($in); }
      sub invalid { die "$cmd: $file: expected MODULE name; in the source header\n"; }
      sub skip {
         while (defined $ch) {
            if ($ch =~ /\s/) { advance(); }
            elsif ($ch eq "(") {
               advance(); invalid() unless defined($ch) && $ch eq "*";
               advance(); my $depth = 1;
               while ($depth) {
                  invalid() unless defined $ch;
                  if ($ch eq "(") {
                     advance();
                     if (defined($ch) && $ch eq "*") { ++$depth; advance(); }
                  } elsif ($ch eq "*") {
                     advance();
                     if (defined($ch) && $ch eq ")") { --$depth; advance(); }
                  } else { advance(); }
               }
            } else { last; }
         }
      }
      sub identifier {
         skip(); invalid() unless defined($ch) && $ch =~ /[A-Za-z_]/;
         my $name = "";
         while (defined($ch) && $ch =~ /[A-Za-z0-9_]/) { $name .= $ch; advance(); }
         return $name;
      }
      invalid() unless identifier() eq "MODULE";
      my $name = identifier(); skip();
      invalid() unless defined($ch) && $ch eq ";";
      print "$name\n";
   ' "$main_source" "$cmdname") || exit 1
fi

case "$arch" in
i386)  objarch=I386 ;;
amd64) objarch=AMD64 ;;
*)     echo "$cmdname: unsupported architecture: $arch" >&2; exit 1 ;;
esac
tooldir="$ULMOLIBDIR/$arch"
if [ ! -x "$tooldir/ulmoc" ]; then
   echo "$cmdname: no $arch compiler installed in $ULMOLIBDIR" >&2
   exit 1
fi
[ -z "$libdir" ] && libdir="$tooldir"

# the library sources come after the directories given with -I;
# architecture-specific run time modules take precedence over generic ones
[ -d "$ULMOSRCDIR/rtl/$arch" ] && iflags="$iflags -I $ULMOSRCDIR/rtl/$arch"
iflags="$iflags -I $ULMOSRCDIR/rtl -I $ULMOSRCDIR/lib -I $ULMOSRCDIR/compiler"

# ulmoc needs a definition (.od) for every module, even for a main module
# which exports nothing; create an empty one where none exists
for sourcefile in $sources; do
   if [ ! -f "$sourcefile" ]; then
      echo "$cmdname: $sourcefile: no such file" >&2
      exit 1
   fi
   base=`basename "$sourcefile"`
   modname="${base%.*}"
   srcdir=`dirname "$sourcefile"`
   case "$base" in
   *.om|*.mod)
      if [ ! -f "$srcdir/$modname.od" ] && [ ! -f "$modname.od" ]; then
         printf "DEFINITION %s;\nEND %s.\n" "$modname" "$modname" > "$modname.od"
      fi
      ;;
   esac
done

if [ -n "$out_file" ] && [ -z "$main_module" ]; then
   main_module=`basename "$out_file"`
fi
if [ -n "$main_module" ] && [ -z "$out_file" ]; then
   out_file="$main_module"
fi

# step 1: compile the sources and the modules they import; the compiled
# library modules are taken from the library unless they are out of date
lflags=""
[ -d "$libdir/obj" ] && lflags="-L $libdir/obj"
"$tooldir/ulmoc" -a $arch $vflags -I . $iflags $lflags $sources || exit 1

# step 1b: a program needs the implementations of the modules it imports,
# ulmoc compiles their interfaces only; compile the implementations of
# the imported modules whose interfaces were compiled here (the modules
# of the library are not, as long as they are up to date)
if [ -n "$main_module" ] && [ $asm_only -eq 0 ]; then
   dirs=`echo ". $iflags" | sed 's/-I *//g'`
   tried=""
   while :; do
      missing=""
      for def in ./*-def-gen.obj; do
         [ -f "$def" ] || continue
         mod=`basename "$def" -def-gen.obj`
         [ -f "$mod-mod-$objarch.obj" ] && continue
         for dir in $dirs; do
            if [ -f "$dir/$mod.om" ]; then
               missing="$missing $dir/$mod.om"
               break
            fi
         done
      done
      [ -z "$missing" ] && break
      if [ "$missing" = "$tried" ]; then
         echo "$cmdname: cannot compile$missing" >&2
         exit 1
      fi
      tried="$missing"
      "$tooldir/ulmoc" -a $arch $vflags -I . $iflags $lflags $missing || exit 1
   done
fi

# step 2: convert each given module to a .o (or a .tof with -S)
tof() { # module objfile toffile
   "$tooldir/obtofgen" -o "$3" "$2" || exit 1
}
elf() { # module objfile ofile
   tof "$1" "$2" "$1-mod-$objarch.tof"
   "$ULMOLIBDIR/tof2elf" -arch $arch -o "$3" "$1-mod-$objarch.tof" ||
      { rm -f "$1-mod-$objarch.tof"; exit 1; }
   rm -f "$1-mod-$objarch.tof"
}
obj_files=""
for sourcefile in $sources; do
   base=`basename "$sourcefile"`
   modname="${base%.*}"
   case "$base" in
   *.om|*.mod) ;;
   *) continue ;;
   esac
   # a source given twice is converted once
   echo "$obj_files" | grep -qw "$modname.o" && continue
   objfile="$modname-mod-$objarch.obj"
   # a library module given as source is not compiled again while the
   # compiled one of the library is up to date
   if [ ! -f "$objfile" ] && [ -f "$libdir/obj/$objfile" ]; then
      objfile="$libdir/obj/$objfile"
   fi
   if [ ! -f "$objfile" ]; then
      echo "$cmdname: expected $objfile not found" >&2
      exit 1
   fi
   if [ $asm_only -eq 1 ]; then
      tof "$modname" "$objfile" "$modname.tof"
      echo "$cmdname: $sourcefile -> $modname.tof"
   else
      elf "$modname" "$objfile" "$modname.o"
      echo "$cmdname: $sourcefile -> $modname.o"
      obj_files="$obj_files $modname.o"
   fi
done
[ $asm_only -eq 1 ] && exit 0
[ -z "$main_module" ] && exit 0

# step 3: link; all other modules compiled here (imported modules which
# are not part of the library, or library modules which had to be
# recompiled, e.g. from a modified copy) are converted to .o files and
# linked before the libraries
libs="$libdir/libcompiler.a $libdir/libo.a $libdir/librtl.a" # link order
for lib in $libs; do
   if [ ! -f "$lib" ]; then
      echo "$cmdname: library $lib not found" >&2
      exit 1
   fi
done
for objfile in ./*-mod-$objarch.obj; do
   [ -f "$objfile" ] || continue
   mod=`basename "$objfile" -mod-$objarch.obj`
   echo "$obj_files" | grep -qw "$mod.o" && continue
   elf "$mod" "$objfile" "$mod.o"
   echo "$cmdname: dependency $mod -> $mod.o"
   obj_files="$obj_files $mod.o"
done

AS="$AS" LD="$LD" sh "${ULMOLINK:-$tooldir/oblink}" "$arch" "$tooldir" \
   "$out_file" "$main_module" $obj_files $libs || exit 1
echo "$cmdname: linked -> $out_file"
