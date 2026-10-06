#!/bin/sh
# Run the runtime regression programs with a built compiler.
set -eu
arch=${1:-amd64}
shift || true
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
tests=${*:-RuntimeSockets RuntimeMemory RuntimeResources RuntimeIO RuntimeProcess RuntimeConversions RuntimeDirectory}
work="$root/build/$arch/runtime-tests"
mkdir -p "$work"
for test in $tests; do
   mkdir -p "$work/$test"
   cd "$work/$test"
   case "$test" in
      RuntimeSockets) module=SysSockets ;;
      RuntimeMemory) module=SysMemory ;;
      RuntimeResources) module=SysResources ;;
      RuntimeIO) module="IO Out4" ;;
      RuntimeProcess) module="SysProcess SysIO" ;;
      RuntimeConversions) module="SysConversions IPv6Addresses" ;;
      RuntimeDirectory) module="SysConversions UnixDirectories UnixFiles" ;;
      *) module= ;;
   esac
   for module in $module; do
      source="$root/src/rtl/$module.om"
      [ -f "$source" ] || source="$root/src/lib/$module.om"
      [ ! -f "$root/src/rtl/$arch/$module.om" ] || source="$root/src/rtl/$arch/$module.om"
      "$root/build/root/lib/ulmo/$arch/ulmoc" -a "$arch" \
         -I "$root/src/rtl/$arch" -I "$root/src/rtl" -I "$root/src/lib" \
         -L "$root/build/root/lib/ulmo/$arch/obj" "$source"
   done
   "$root/build/root/bin/ulmo" -arch "$arch" -m "$test" "$root/src/test/$test.om"
   case "$test" in
      RuntimeIO)
         printf a | timeout -k 2 30 "./$test" >io.log 4>out4.log
         printf a | cmp -s - io.log
         printf b | cmp -s - out4.log
         echo "runtime io: ok"
         ;;
      *) timeout -k 2 30 "./$test" ;;
   esac
done
