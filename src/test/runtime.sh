#!/bin/sh
# Run the runtime regression programs with a built compiler.
set -eu
arch=${1:-amd64}
shift || true
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
tests=${*:-RuntimeSockets}
work="$root/build/$arch/runtime-tests"
mkdir -p "$work"
for test in $tests; do
   mkdir -p "$work/$test"
   cd "$work/$test"
   case "$test" in
      RuntimeSockets) module=SysSockets ;;
      *) module= ;;
   esac
   if [ -n "$module" ]; then
      source="$root/src/rtl/$module.om"
      [ ! -f "$root/src/rtl/$arch/$module.om" ] || source="$root/src/rtl/$arch/$module.om"
      "$root/build/root/lib/ulmo/$arch/ulmoc" -a "$arch" \
         -I "$root/src/rtl/$arch" -I "$root/src/rtl" -I "$root/src/lib" \
         -L "$root/build/root/lib/ulmo/$arch/obj" "$source"
   fi
   "$root/build/root/bin/ulmo" -arch "$arch" -m "$test" "$root/src/test/$test.om"
   timeout -k 2 30 "./$test"
done
