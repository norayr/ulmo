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
- **Smaller compulsory runtime.** Basic diagnostics share a small writer,
  process naming does not import argument parsing, and timezone support is
  selected from the linked modules. `Out` provides lightweight text and
  integer output.
- **Native Oberon tools.** The public driver, startup generator and linker
  driver are Oberon executables. Compilation does not invoke shell or Perl
  wrappers.

## Requirements

- Linux on x86-64 or 32-bit x86 (Pentium/i586 or later for the i386 target)
- GNU make, a C compiler and the development files of libelf (elfutils);
  they are only needed to build `tof2elf`, which converts the compiler's
  output into ELF object files
- GNU binutils (`as`, `ld`), also at run time: ulmo uses them to link
  programs. For i386 programs on an x86-64 system, binutils must support
  `elf_i386`, as the standard x86-64 binutils do.

The ELF converter is the existing small C tool linked against libelf.
The compiler, driver and runtime helpers use the Ulm Oberon library. GNU
`as` and `ld` remain the external assembler and linker. The normal build
and installed tools do not require Perl; GNU make uses the usual POSIX
shell for its build recipes.

The build starts from prebuilt compilers, object generators and native
link helpers in `bootstrap/i386` and `bootstrap/amd64` (statically linked
executables). Building for i386 on an
x86-64 system runs the 32-bit bootstrap compiler, which needs a kernel with
32-bit support (`CONFIG_IA32_EMULATION`, enabled on common distributions).
Building for amd64 does not need any 32-bit support.

## Building

```sh
make                # for the architecture of the host
make ARCH=i386      # or for a given one: i386 or amd64
make check          # optional: self-hosting check and a test program
make check-runtime  # optional: runtime interface regression programs
make check-cli      # optional: main-module selection and wrapper checks
```

The build takes a few minutes (on a current PC about 7 minutes for amd64
and 3 for i386; `make check` adds about half of that). It proceeds in
stages, each compiling the whole compiler and library:

- stage 1 is built by the bootstrap compiler,
- stage 2 by the compiler of stage 1; this is the one installed,
- stage 3 (only for `make check`) by the compiler of stage 2 and must be
  identical to stage 2, including the native driver and runtime helpers.

`make check-runtime` tests TCP and UDP sockets, file-backed memory mapping,
resource limits, basic I/O, process creation and descriptor duplication,
native C structure conversions, IPv6 addresses and directory enumeration.
It also checks argument naming, integer and floating-point output, timezone
files and automatic timezone-provider selection. It can be run with `ARCH=i386`.

Everything goes to `build/`; `make clean` removes it. The directory
`build/root` has the same layout as an installation, so the freshly built
compiler can be used in place:

```sh
build/root/bin/ulmo -m Hello.om
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
| `BINDIR/ulmo` | symlink to the native driver for an installed architecture |
| `LIBDIR/ulmo/tof2elf` | TOF to ELF converter |
| `LIBDIR/ulmo/ARCH/` | compiler, tools and libraries for one target architecture |
| `LIBDIR/ulmo/ARCH/obj/` | compiled interfaces of the library modules |
| `DATADIR/ulmo/src/` | the sources of the library and the compiler |

`LIBDIR/ulmo/ulmo.sources` records the installed source directory. The
driver locates its private tools through its executable path and selects
the target architecture's tools from the same library root.

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

   IMPORT Out;

BEGIN
   Out.Line("Hello, world!");
END Hello.
```

```sh
$ ulmo -m Hello.om
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
| `-m [Main]` | link a program; `-m Hello.om` reads its main-module name from the source header; `-m Main source.om` selects it explicitly |
| `-o file` | name of the program (default: name of the main module) |
| `-arch ARCH` | target architecture: `amd64` or `i386` (default: the host's, if installed) |
| `-I dir` | search sources in `dir`, too |
| `-S` | write the intermediate code (`.tof`, text) instead of `.o` files |
| `-v 6` | tell why modules are compiled or taken as they are |
| `-L dir` | take the libraries from `dir` |

Without `-m`, ulmo only compiles the given modules to `.o` files.

`ulmo -m Hello.om` selects the module declared in `Hello.om`, compiles it
and links a program with that module name. You can give other sources
after it, or choose an output filename with `-o program`. A bare `-m`
before other options (for example, `ulmo -m -o program Hello.om`) infers
the main module when exactly one implementation source is given. The
explicit form `ulmo -m Hello Hello.om` continues to work.

`Out.Char`, `Out.String`, `Out.Int(value, width)`, `Out.Line` and `Out.Ln`
write to buffered standard output without importing the general formatter.
Use `Write` or `Print` for floating-point or general formatted output;
the existing `Write` interface is preserved.

How compilation works:

- ulmoc compiles your modules and those they import, as far as there are
  no up-to-date compiled files for them (see below). It writes its
  compiled files into the current directory. When linking, ulmo compiles
  the implementations of imported modules of your own, too, so it is
  enough to name the main module's source.
- Library modules are taken precompiled from the installation, as long as
  their sources are unchanged.
- A modified copy of a library module, given on the command line or found
  in the current directory (or in a directory given with `-I`), takes
  precedence and is linked instead of the library's version.
- All modules compiled in the current directory are linked, so use one
  directory per program.

The native driver keeps compiler invocations separate and sequential,
retaining the existing bounded-memory build model. It executes tools via
`SysProcess.Fork`/`Exec`/`WaitFor`, with argument vectors rather than shell
command strings. Startup generation uses the same instruction sequences
as the former Perl tools; comparison tests produced identical assembler
objects on AMD64 and i386, with and without timezone startup.

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

A program is statically linked and contains the run time system, about 69
modules, among them a garbage collector, coroutines and a stream system.
The hello world program of `src/test`:

| | as linked | stripped |
|---|---|---|
| amd64 | 1.45 MB | 0.64 MB |
| i386 | 1.16 MB | 0.47 MB |

More than half of it is the symbol table. Remove it with `strip`, or link
without it:

```sh
strip Hello
LDFLAGS=-s ulmo -m Hello Hello.om
```

Keep the symbols while you debug: they are all there is (see below).

Most of this size is the runtime dependency graph, rather than the program
itself. The following are stripped executables, with sizes in bytes:

| program | amd64 | i386 | added over empty, amd64 / i386 |
|---|---:|---:|---:|
| empty module | 576,504 | 425,916 | 0 / 0 |
| hello world using `Out` | 578,064 | 426,932 | 1,560 / 1,016 |
| hello world using `Write` | 640,080 | 471,888 | 63,576 / 45,972 |

Using `Out` adds only about 1-1.6 KB to the minimal executable. Using
`Write` adds about 46-64 KB because its floating-point output imports the
general formatter, even if the program calls only `Write.Line`.

The empty program links 69 runtime modules, down from 81. Its size has
fallen by about 22% from the former 741 KB / 545 KB baseline. The native
timezone provider is included automatically when `Timezones` is linked;
programs that do not use it do not carry the timezone reader. Adding
`LDFLAGS='-s --gc-sections'` does not reduce that baseline: the compiler
emits code at module granularity, and retained modules keep their unused
procedures. Further reductions need more separation of optional facilities
from the remaining core runtime dependencies.

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
   (a 387-compatible x87 FPU). Independently, the i386 allocation fast path
   uses `CMPXCHG8B`, making Pentium/i586 the minimum CPU for normal programs.
   It does not require MMX or SSE. Integer literals are
  still limited to the range of `LONGINT`; larger constants are built from
  `MIN(HUGEINT)` and `MAX(HUGEINT)`: sums, differences and comparisons of
  such constants are computed by the compiler (`CONST big = MAX(HUGEINT) -
  5`), other operations on them at run time.
- The amd64 backend is new. It compiles the compiler and the whole library,
  and the compiler reproduces itself, but it has seen far less use than the
  i386 backend.
- The amd64 runtime now has native socket calls and tested mappings,
  resource limits and C structure conversions. The `SysIPC` interface
  still needs a native System V IPC port. The allocator remains restricted
  to low addresses; the remaining porting work is listed in `WANTED`.
- The database-based tools of the original system (`pons`, `cdbd`, `obci`,
  ...) can still be built with `make cdb-tools`; `Makefile.cdb` has the
  targets for setting them up. They are not needed for ulmo.

## License

Ulm's Oberon System is copyright by Andreas F. Borchert and others. It may
be used and distributed under the terms of the GNU General Public License
(the library under the GNU Library General Public License); see `COPYING`
and the headers of the source files.
