# ulmo — Ulm's Oberon compiler for Linux on x86 and x86-64

ulmo is a revival of **Ulm's Oberon System**, the Oberon compiler and
library developed by Andreas F. Borchert and others at the University of
Ulm. The original compiler had versions for i386, SPARC and m68k, and the
i386 version depended on a database server setup (`pons` and `cdbd`) to
compile anything.

This version:

- compiles and links without any server, like a C compiler;
- generates native code for **i386** (32-bit x86) and **amd64** (x86-64);
- is self-hosting on both architectures: it compiles itself, and the
  compiler it produces compiles itself again to an identical binary;
- builds with `make` and installs into a prefix or the usual Unix places,
  so it can be packaged for distributions.

The original documentation is at <http://www.mathematik.uni-ulm.de/oberon/>.
The former README and installation instructions are kept in
`README_legacy` and `INSTALL_legacy`.

### Changes compared to the original system

- **No database.** The compiled interfaces and modules are kept in files
  instead of the compiler database (`cdbd`). Like the database before, the
  compiler reuses them as long as their fingerprints show that they are up
  to date, and compiles from source only what has changed (see
  [Compiled files](#compiled-files)).
- **amd64 backend** (new), next to the i386 one.
- **HUGEINT**, a 64-bit integer type on both architectures (see
  [Status and limitations](#status-and-limitations)).
- **Build and installation** with `make`, `make check` and
  `make install`; the precompiled interfaces of the library are installed,
  so programs do not compile library modules again.
- **Library split** into the run time system, the general library and the
  compiler (`src/rtl`, `src/lib`, `src/compiler`).
- **Run time error messages** name the correct source line, report index
  errors with the valid range, and report dereferences of NIL.

## Requirements

- Linux on x86-64 or 32-bit x86
- GNU make, a C compiler and the development files of libelf (elfutils);
  they are only needed to build `tof2elf`, which converts the compiler's
  output into ELF object files
- GNU binutils (`as`, `ld`), also at run time: ulmo uses them to link
  programs. For i386 programs on an x86-64 system, binutils must support
  `elf_i386`, as the standard x86-64 binutils do.
- perl (generates the start-up code of programs)

The build starts from prebuilt compilers in `bootstrap/i386` and
`bootstrap/amd64` (statically linked executables). Building for i386 on an
x86-64 system runs the 32-bit bootstrap compiler, which needs a kernel with
32-bit support (`CONFIG_IA32_EMULATION`, enabled on common distributions).
Building for amd64 does not need any 32-bit support.

## Building

```sh
make                # for the architecture of the host
make ARCH=i386      # or for a given one: i386 or amd64
make check          # optional: self-hosting check and a test program
```

The build takes a few minutes (on a current PC about 7 minutes for amd64
and 3 for i386; `make check` adds about half of that). It proceeds in
stages, each compiling the whole compiler and library:

- stage 1 is built by the bootstrap compiler,
- stage 2 by the compiler of stage 1; this is the one installed,
- stage 3 (only for `make check`) by the compiler of stage 2 and must be
  identical to stage 2.

Everything goes to `build/`; `make clean` removes it. The directory
`build/root` has the same layout as an installation, so the freshly built
compiler can be used in place:

```sh
build/root/bin/ulmo -m Hello Hello.om
```

## Installing

```sh
make install                                  # into /usr/local
make install PREFIX=$HOME/ulmo                # into a directory of your own
make install PREFIX=/usr LIBDIR=/usr/lib64    # the traditional places
make ARCH=i386 install                        # add another architecture
make uninstall                                # per architecture, too
```

`make install` accepts `PREFIX`, `BINDIR`, `LIBDIR`, `DATADIR` and
`DESTDIR`, and installs

| path | contents |
|---|---|
| `BINDIR/ulmo` | the only command you need |
| `LIBDIR/ulmo/tof2elf` | TOF to ELF converter |
| `LIBDIR/ulmo/ARCH/` | compiler, tools and libraries for one target architecture |
| `LIBDIR/ulmo/ARCH/obj/` | compiled interfaces of the library modules |
| `DATADIR/ulmo/src/` | the sources of the library and the compiler |

The Oberon libraries are not system libraries: they belong to the compiler,
and each target architecture has its own directory under `LIBDIR/ulmo`. So
it does not matter whether a distribution uses `lib` or `lib64`; set
`LIBDIR` to what the distribution uses. Several architectures can be
installed side by side; they share `ulmo`, `tof2elf` and the sources.

The installed `ulmo` knows where its files are. `ULMOLIBDIR` and
`ULMOSRCDIR` override these locations, which helps to test an installation
staged with `DESTDIR`.

### Packaging

- Build with `make` and install with
  `make install PREFIX=/usr LIBDIR=/usr/lib64 DESTDIR=$pkgdir`, with the
  `LIBDIR` of the distribution (in a Gentoo ebuild: `/usr/$(get_libdir)`).
- `ARCH` defaults to the host architecture. It also accepts `x86_64`, `x86`
  and `i686`, so an `ARCH` from the environment (as set by portage) does
  not get in the way.
- The build compiles everything from source, but it starts from the
  bootstrap compilers in `bootstrap/`, as the compilers of Go or Free Pascal
  do.

## Using ulmo

A module in Ulm's Oberon consists of a **definition** (`.od`), its public
interface, and a **module** (`.om`), the implementation. A main module that
exports nothing needs no definition; ulmo creates an empty one.

`Hello.om`:

```oberon
MODULE Hello;

   IMPORT Write;

BEGIN
   Write.Line("Hello, world!");
END Hello.
```

```sh
$ ulmo -m Hello Hello.om
ulmo: Hello.om -> Hello.o
ulmo: linked -> Hello
$ ./Hello
Hello, world!
```

A program with modules of its own, as in `src/test`:

```sh
ulmo -m Hello src/test/Greeter.om src/test/Hello.om
```

Options:

| option | |
|---|---|
| `-m Main` | link a program with the main module `Main` |
| `-o file` | name of the program (default: name of the main module) |
| `-arch ARCH` | target architecture: `amd64` or `i386` (default: the host's, if installed) |
| `-I dir` | search sources in `dir`, too |
| `-S` | write the intermediate code (`.tof`, text) instead of `.o` files |
| `-v 6` | tell why modules are compiled or taken as they are |
| `-L dir` | take the libraries from `dir` |

Without `-m`, ulmo only compiles the given modules to `.o` files.

How compilation works:

- ulmoc compiles your modules and those they import, as far as there are
  no up-to-date compiled files for them (see below). It writes its
  compiled files into the current directory. When linking, ulmo compiles
  the implementations of imported modules of your own, too, so it is
  enough to name the main module's source.
- Library modules are taken precompiled from the installation, as long as
  their sources are unchanged.
- A modified copy of a library module in the current directory (or in a
  directory given with `-I`) takes precedence and is linked instead of the
  library's version.
- All modules compiled in the current directory are linked, so use one
  directory per program.

### Compiled files

For a module `M`, ulmoc writes three files. They are not ELF files but
objects of the library's persistence format (`PersistentObjects`):

| file | contents |
|---|---|
| `M-def-gen.obj` | the public interface, independent of the architecture: the declarations of `M.od` (constants, types, variables, procedure signatures) as compiled symbol table |
| `M-def-I386.obj`, `M-def-AMD64.obj` | the public interface for one architecture: sizes and alignments of the types, offsets of record fields and the values of constants in the target representation; it takes the private record fields of `M.om` into account, so importers know the true size of a record |
| `M-mod-I386.obj`, `M-mod-AMD64.obj` | the compiled module: code, data, type descriptors and relocations for one architecture |

ulmo converts `M-mod-ARCH.obj` into the ELF object `M.o` (with `obtofgen`
and `tof2elf`, `-S` shows the intermediate text) and links the `.o` files
with the libraries.

Each file has a header with fingerprints: the MD5 sums of `M.od` and
`M.om`, a key of the compiled interface and the keys of all interfaces it
was compiled against. Before the compiler uses a compiled file, it checks
these against the current sources and against the other interfaces in use:

- an unchanged module is taken as it is, whether it was compiled in the
  current directory or comes with the installation;
- a module whose source changed is compiled again, and so are the modules
  that depend on a changed interface;
- `ulmo -v 6` shows these decisions.

In the original system these objects were stored in the compiler database
instead of files; the checks are the same.

The library is organized in three parts:

| sources | library | |
|---|---|---|
| `src/rtl` | `librtl.a` | run time system: memory management, coroutines, events, streams, I/O. It is linked into every program. `src/rtl/amd64` has the amd64 versions of some of its modules. |
| `src/lib` | `libo.a` | general library: containers, text processing, networking, persistence, ... |
| `src/compiler` | `libcompiler.a` | the compiler itself |

Programs contain only the modules they use, directly or indirectly, plus
the run time system.

## Program size

A program is statically linked and contains the run time system, about 80
modules, among them a garbage collector, coroutines and a stream system.
The hello world program of `src/test`:

| | as linked | stripped |
|---|---|---|
| amd64 | 1.6 MB | 0.7 MB |
| i386 | 1.3 MB | 0.54 MB |

More than half of it is the symbol table. Remove it with `strip`, or link
without it:

```sh
strip Hello
LDFLAGS=-s ulmo -m Hello Hello.om
```

Keep the symbols while you debug: they are all there is (see below).

## Errors at run time and debugging

Run time errors (failed assertions, index range errors, failed type guards,
CASE without matching label, functions without RETURN, failed conversions,
dereferences of NIL) raise an event. By default nothing prints it; the
program just aborts (SIGABRT, exit status 134). Import `Conclusions` in
your main module to get a message:

```oberon
MODULE Fail;
   IMPORT Conclusions;
   ...
```

```
Fail: bug: Failure in Fail.Check at line 5:
      assertion failed
```

The line is that of the failing statement; for a CASE without matching
label it is the line of its END, for a missing RETURN that of the
procedure heading. A dereference of NIL is reported as
`segmentation violation`, without a location.

There is no source-level debugging: the compiler does not generate debug
information (no DWARF). gdb works on the machine level:

- Procedures appear as `Module_Procedure` (e.g. `Greeter_SayHello`), so
  `break Greeter_SayHello`, `disassemble`, `info symbol ADDRESS` and
  `nm program` work.
- Backtraces are unreliable: without unwind information gdb shows internal
  labels (e.g. `Greeter___BLOCK_START__1`) and soon reaches frames it
  cannot interpret.
- The run time system extends coroutine stacks on demand by catching
  SIGSEGV. Tell gdb to pass it on: `handle SIGSEGV nostop noprint pass`.
- gdb disables address space randomization. If a problem only shows up
  outside gdb, try `set disable-randomization off`.

## Status and limitations

- Linux only; programs are static executables with a single segment that is
  readable, writable and executable (the linker warning about it is
  suppressed where binutils support that).
- On amd64 `INTEGER` and `LONGINT` are 32 bits wide, as on i386; addresses
  are 64 bits. Code and static data live in the lowest 2 GB (small code
  model).
- `HUGEINT` is a 64-bit integer type on both architectures:
  `LONGINT` values are included in it, `LONG` of a `LONGINT` is a
  `HUGEINT`, and `SHORT` of a `HUGEINT` is a `LONGINT` (checked at run
  time). On i386 its values are kept in register pairs, and `DIV` and
  `MOD` use the x87 floating point unit, so a CPU with FPU is needed
  (486DX or later; any CPU of the last decades). Integer literals are
  still limited to the range of `LONGINT`; larger constants have to be
  computed, and expressions with `MIN(HUGEINT)` or `MAX(HUGEINT)` are
  evaluated at run time.
- The amd64 backend is new. It compiles the compiler and the whole library,
  and the compiler reproduces itself, but it has seen far less use than the
  i386 backend.
- The database-based tools of the original system (`pons`, `cdbd`, `obci`,
  ...) can still be built with `make cdb-tools`; `Makefile.cdb` has the
  targets for setting them up. They are not needed for ulmo.

## License

Ulm's Oberon System is copyright by Andreas F. Borchert and others. It may
be used and distributed under the terms of the GNU General Public License
(the library under the GNU Library General Public License); see `COPYING`
and the headers of the source files.
