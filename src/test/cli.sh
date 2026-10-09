#!/bin/sh
set -eu
arch=${1:-amd64}
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
export ULMOLIBDIR=${ULMOLIBDIR:-$root/build/root/lib/ulmo}
export ULMOSRCDIR=${ULMOSRCDIR:-$root/src}
wrapper=${ULMO:-$root/build/root/bin/ulmo}
work="$root/build/$arch/cli-test"

driver() {
   case "$wrapper" in
      *.sh) sh "$wrapper" "$@" ;;
      *) "$wrapper" "$@" ;;
   esac
}

check() {
   name=$1
   program=$2
   shift 2
   mkdir -p "$work/$name"
   cd "$work/$name"
   driver -arch "$arch" "$@"
   "./$program" >output.log
}

source="$root/src/test/InferredMain.om"
mkdir -p "$work/compile-only"
cd "$work/compile-only"
driver -arch "$arch" "$source"
[ -f InferredMain.o ] && [ ! -f InferredMain ]
check explicit InferredMain -m InferredMain "$source"
check inferred InferredMain -m "$source"
cmp "$work/explicit/output.log" "$work/inferred/output.log"
check output renamed -m -o renamed "$source"
cmp "$work/explicit/output.log" "$work/output/output.log"
check separated InferredMain -m -- "$source"
cmp "$work/explicit/output.log" "$work/separated/output.log"
check module-file output -m "$source" -o output
cmp "$work/explicit/output.log" "$work/module-file/output.log"
check imports Hello -m "$root/src/test/Hello.om" "$root/src/test/Greeter.om"
cmp output.log "$root/src/test/Hello.expected"
check old-imports Hello -m Hello "$root/src/test/Greeter.om" "$root/src/test/Hello.om"
cmp output.log "$root/src/test/Hello.expected"

mkdir -p "$work/errors"
cd "$work/errors"
if driver -arch "$arch" -m -o ambiguous "$source" "$root/src/test/Hello.om" >error.log 2>&1; then
   echo "ambiguous main module unexpectedly accepted" >&2; exit 1
fi
grep -q 'several module sources' error.log
if driver -arch "$arch" -m missing.om >error.log 2>&1; then
   echo "missing main source unexpectedly accepted" >&2; exit 1
fi
grep -q 'missing.om' error.log
printf '(* unterminated comment MODULE Hidden;\n' >Broken.om
if driver -arch "$arch" -m Broken.om >error.log 2>&1; then
   echo "invalid module header unexpectedly accepted" >&2; exit 1
fi
grep -q 'expected MODULE name;' error.log
[ ! -f Broken.od ]
if driver -arch "$arch" -m "$root/src/test/Greeter.od" >error.log 2>&1; then
   echo "definition file unexpectedly accepted as the main module" >&2; exit 1
fi
echo "command-line main selection: ok ($arch)"
