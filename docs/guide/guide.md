# Finding your way around Ulm's Oberon

### A practical introduction for Oberon programmers

If you already program in Oberon, most of the language here will be
familiar. The library takes a little more getting used to. Its names do
not always tell you what to import, or why an apparently simple operation
has several parts.

We will begin with a small program, look at the definitions of the modules
it uses, and write a module of our own. Then we can try some of the library
facilities: streams, disciplines, events and services. There is no need to
learn them all before writing a useful program.

The examples use ulmo 0.11.2, the Linux revival of the compiler and library
developed by Andreas F. Borchert and others at the University of Ulm. This
is an introduction to using that system, not a complete Oberon language
manual. The module table near the end should also be useful when you come
back with a particular job in mind.

- [First program](#1-your-first-native-program)
- [Module definitions, separate compilation and initialization](#2-module-definitions-and-separate-compilation)
- [Command-line arguments](#3-command-line-arguments)
- [Library map](#4-a-map-of-the-library)
- [Streams](#5-streams-one-algorithm-several-sources)
- [Your own discipline](#6-disciplines-extending-an-object-without-changing-its-record)
- [Formatting disciplines](#7-built-in-disciplines-formatting-belongs-to-the-stream)
- [Error sinks and forwarding](#8-related-events-let-the-caller-choose-how-to-report-errors)
- [Structured diagnostics](#9-your-own-structured-diagnostics)
- [Event handlers](#10-events-notifications-without-hard-wiring-their-consumers)
- [Services](#11-services-teaching-a-type-an-optional-capability)
- [Persistence](#12-persistence-storing-values-with-their-type)
- [Which module should I use?](#13-finding-the-right-module-for-your-next-problem)
- [Compiler workflow](#14-working-comfortably-with-the-compiler)
- [Memory and resources](#15-things-worth-knowing-about-memory-and-resources)
- [Reading the reference](#16-a-route-through-the-original-reference-documentation)

## Who this guide is for

You should know the usual Oberon declarations and statements. Record
extension and procedure variables will be useful in the later examples.
You may have used ETH Oberon, Component Pascal, oo2c, ofront or voc; you
need not have used Ulm's library or its original compiler database.

### What runs on your machine

ulmo produces statically linked native Linux executables for AMD64 and
i386. An ordinary generated executable does not require libc, a VM or the
compiler installation to run. The compiler toolchain still uses GNU `as`
and `ld`, and its C object converter uses libelf.

The executable does contain a runtime: garbage collection, runtime checks,
streams and coroutine support are compiled into it. You do not have to
install a separate environment on the machine where it runs.

This is a Unix application environment, not an Oberon desktop you must
boot. Ordinary compilation no longer needs the original `pons`/`cdbd`
services.

## 1. Your first native program

Let us start with a program that prints one line. Save it as `Hello.om`:

```oberon
MODULE Hello;
   IMPORT Out;
BEGIN
   Out.Line("Hello from Ulm's Oberon.");
END Hello.
```

In a directory dedicated to this program:

```text
$ ulmo -m Hello.om
ulmo: Hello.om -> Hello.o
ulmo: linked -> Hello
$ ./Hello
Hello from Ulm's Oberon.
```

The first command compiles the module and links an executable named
`Hello`. The two `ulmo:` lines are messages from the driver, not from our
program. The second command runs the executable. The `$` marks the shell
prompt; do not type it as part of the command.

If you built ulmo without installing it, use the absolute path to
`build/root/bin/ulmo` instead of `ulmo`.

The statements between the final `BEGIN` and `END Hello` are the module
body. They run when the program starts; there is no separate `main`
procedure to declare. We will see what happens to imported module bodies
in the next section.

`Out` is a small output module provided by the current ulmo project. For
example, these statements print an integer after a label:

```oberon
Out.String("items: ");
Out.Int(12, 0);
Out.Ln;
```

The second argument to `Int` is the minimum width. Zero means that no
padding is wanted. `Out` writes to standard output, which the shell can
redirect to a file.

### Out or Write?

You will also find `Write` in the original library and its examples. It
provides text and integer output, indentation, and `Write.Real` for
floating-point output. It also has versions that take a destination stream.
`Print` provides more general format-directed output.

There is a size difference worth knowing about. `Write.om` imports `Print`
to implement real-number output, and `Print` brings further formatting
dependencies. Modules are linked as whole units, so importing `Write` can
bring that code into a program even if you only call `Write.String`.

If you only need text and integers, use `Out`. When you need the same basic
operations on a particular stream, use `BasicWrite`. Use `Write` or `Print`
when you want their additional facilities. This is a choice about what to
include, not a reason to avoid the original library. Another import may
already require the formatter, in which case changing your output module
alone will not remove it. All of these choices still use the native runtime.

Source: [Hello.om](examples/01-hello/Hello.om).

## 2. Module definitions and separate compilation

Our program imports `Out`, but how do we find out what `Out` provides?
The answer is its definition module. In Ulm's Oberon the readable
definition has the suffix `.od`, and the implementation has the suffix
`.om`. There is no need to read the implementation just to discover a
procedure's parameters.

### Looking at an installed definition

On a normal Gentoo installation from `norayr-overlay`, try:

```sh
cat /usr/share/ulmo/src/lib/Out.od
```

You should see:

```oberon
DEFINITION Out;

   (* buffered text and integer output on the standard output stream *)
   PROCEDURE Char(ch: CHAR);
   PROCEDURE String(str: ARRAY OF CHAR);
   PROCEDURE Int(int, width: LONGINT);
   PROCEDURE Line(str: ARRAY OF CHAR);
   PROCEDURE Ln;

END Out.
```

This is the interface used by importers of `Out`. It tells us, for example,
that `Int` takes two `LONGINT` arguments and `Ln` takes none. The procedure
bodies belong to `Out.om`, not to this file.

The location depends on how the compiler was installed:

| Installation | Definition of Out |
|---|---|
| Gentoo overlay, without an EPREFIX | `/usr/share/ulmo/src/lib/Out.od` |
| Default `make install` | `/usr/local/share/ulmo/src/lib/Out.od` |
| `make install PREFIX=$HOME/ulmo` | `$HOME/ulmo/share/ulmo/src/lib/Out.od` |
| A source checkout | `src/lib/Out.od` |

The `lib` in these paths is a source subdirectory. Other definitions are
under `rtl` or `compiler`. Thus `Write.od` is normally at
`/usr/share/ulmo/src/rtl/Write.od`, not beside `Out.od`. For modules with an
architecture-specific version, look under `rtl/amd64` or `rtl/i386` first,
then under `rtl`. The compiler searches the target-specific directory first.

If the installation uses custom `LIBDIR` or `DATADIR` settings, the file
`ulmo.sources` in its library root records the source directory. On Gentoo
AMD64:

```sh
cat /usr/lib64/ulmo/ulmo.sources
```

This normally prints `/usr/share/ulmo/src`. You can use it rather than
guessing the source path:

```sh
sources=$(cat /usr/lib64/ulmo/ulmo.sources)
less "$sources/lib/Out.od"
```

For a default installation, the marker is
`/usr/local/lib/ulmo/ulmo.sources`; for `PREFIX=$HOME/ulmo`, it is
`$HOME/ulmo/lib/ulmo/ulmo.sources`. Gentoo x86 normally uses `/usr/lib`
instead of `/usr/lib64`. A Gentoo EPREFIX prefixes both the library and
source paths. `ULMOSRCDIR`, if you set it, overrides the recorded source
directory for the driver.

ulmo does not currently install a definition-viewing command like voc's
`showdef` or oo2c's `oob`. For now, `cat`, `less` or your editor is enough
to read the installed `.od` files.

### Are there symbol files?

There are compiled interfaces, although they do not have the familiar
`.sym` suffix. On Gentoo AMD64, `Out-def-gen.obj` and
`Out-def-AMD64.obj` are installed under `/usr/lib64/ulmo/amd64/obj/`.
For a default installation they are under
`/usr/local/lib/ulmo/amd64/obj/`; with our home-directory prefix, under
`$HOME/ulmo/lib/ulmo/amd64/obj/`.

The first contains architecture-independent interface information; the
second contains target-specific information such as type sizes and field
offsets. These are binary compiler files, not documents to read with `cat`.
Read `Out.od` to learn the interface. Let the compiler use the `.obj` files
to check and reuse it. The file table in section 14 describes the other
compiled files.

### Writing a module for another programmer to use

Let us make a counter. Its public definition, `Counter.od`, is small:

```oberon
DEFINITION Counter;
   PROCEDURE Next() : LONGINT;
END Counter.
```

The user may ask for the next number, but may not read or assign our
internal count. Here is the implementation, `Counter.om`:

```oberon
MODULE Counter;
   IMPORT Out;
   VAR count: LONGINT;

   PROCEDURE Next() : LONGINT;
   BEGIN
      INC(count);
      RETURN count
   END Next;

BEGIN
   count := 0;
   Out.Line("Counter is initialized.");
END Counter.
```

Both files describe the same module. The compiler checks the implementation
against its definition; it is not necessary to import `Counter` inside
`Counter.om`. Everything declared in the definition is public. The
implementation's `count` variable is private because it is not declared
there. Unlike the usual single-file Oberon notation, these implementations
do not mark exported names with `*`.

We can compile this module without having a main program:

```text
$ ulmo Counter.om
ulmo: Counter.om -> Counter.o
```

This produces compiled interfaces, the compiled implementation and an ELF
object `Counter.o`. It does not produce a `Counter` executable, and it does
not run the module body. Notice that there is no "Counter is initialized"
message. Compilation and initialization are different operations.

This is a useful way to work if you are writing a library or an auxiliary
module for somebody else's program. A main module is not required to
compile your implementation. The compiler reads `Counter.od` automatically;
you do not have to compile the definition in a separate command first.

### Using the module

Now add `UseCounter.om` in the same directory:

```oberon
MODULE UseCounter;
   IMPORT Counter, Out;
BEGIN
   Out.Line("UseCounter is running.");
   Out.Int(Counter.Next(), 0); Out.Ln;
   Out.Int(Counter.Next(), 0); Out.Ln;
END UseCounter.
```

Compile and run it:

```text
$ ulmo -m UseCounter.om
ulmo: UseCounter.om -> UseCounter.o
ulmo: linked -> UseCounter
$ ./UseCounter
Counter is initialized.
UseCounter is running.
1
2
```

`-m` asks the driver to link a program, using `UseCounter` as its main
module. Without `-m`, as in the earlier command, it only compiles.

You can also put the three source files in a fresh directory and run just
`ulmo -m UseCounter.om`. You need not compile `Counter.om` first or name it
on that command line. The import tells the compiler which interface is
needed; when linking, the driver finds and compiles the local implementation
if needed. The ordinary driver messages do not list every dependency, so
the short transcript above is also what you see in that case.

There is no makefile for this example. The compiler checks cached objects
and interface fingerprints, and the driver discovers imported local
implementations. Installed library modules, such as `Out`, are normally
reused from the installation rather than rebuilt for each program.

### When does a module initialize?

Look again at the output. The body of `Counter` runs before the body of
`UseCounter`, because `UseCounter` imports it. This sets `count` to zero
before either call of `Next`.

A module body runs once during initialization, not each time one of its
procedures is called. Our two calls return 1 and 2; they do not each restart
the counter. If another module also imports `Counter`, both use the same
module state. Running the executable again starts a new process and a new
counter.

The printed initialization message is only here to make the order visible.
A real counter module would usually initialize quietly. Module bodies are
also used to register library facilities: later, `Labels` obtains its
discipline identifier there, and our service example registers its adapter
there. That registration happens at run time, not when you compile the file.

Depend on the import relationship for initialization order, rather than on
the order of source files passed to the compiler. If a module needs another
module's initialized state, it should import that module. Unrelated modules
should not rely on being initialized in some particular order.

Keep module names and file basenames consistent, including case. A main
module that exports nothing can omit its `.od`; ulmo creates an empty
definition for it. Write an explicit definition for a module other
programmers will import.

Sources: [Counter.od](examples/02-modules/Counter.od),
[Counter.om](examples/02-modules/Counter.om),
[UseCounter.om](examples/02-modules/UseCounter.om).

## 3. Command-line arguments

Our first programs always do the same thing. Let us give the next one a
name to greet, with an optional greeting chosen on the command line.
The library module for this is `UnixArguments`. Its definition is in
`rtl/UnixArguments.od` under the source directory we found above.

Save the following as `Greet.om` in its own directory:

```oberon
MODULE Greet;
   IMPORT Out, UnixArguments;
   VAR greeting, name: ARRAY 80 OF CHAR; flag: CHAR;
BEGIN
   UnixArguments.Init("[-p greeting] name");
   greeting := "Hello";
   WHILE UnixArguments.GetFlag(flag) DO
      CASE flag OF
      | "p": UnixArguments.FetchString(greeting);
      ELSE UnixArguments.Usage
      END;
   END;
   IF ~UnixArguments.GetArg(name) THEN UnixArguments.Usage END;
   UnixArguments.AllArgs;
   Out.String(greeting); Out.String(", ");
   Out.String(name); Out.Line("!");
END Greet.
```

```text
$ ulmo -m Greet.om
ulmo: Greet.om -> Greet.o
ulmo: linked -> Greet
$ ./Greet Norayr
Hello, Norayr!
$ ./Greet -p 'Good evening' Norayr
Good evening, Norayr!
$ ./Greet
Usage: ./Greet [-p greeting] name
```

`Init` starts argument reading and records the text used in the usage
message. It does not parse that text as an option specification: our code
still has to say which options are allowed and how many arguments it needs.
The executable name is not returned as the first ordinary argument.

`GetFlag` returns an option letter, without its leading `-`. When we see
`p`, `FetchString` reads its value into `greeting`. If no value remains,
`FetchString` calls `Usage`. We reject unknown letters ourselves.

After the options, `GetArg` reads the name and returns false if no argument
remains. `AllArgs` rejects any leftovers, so `./Greet Norayr extra` is a
usage error rather than silently ignoring `extra`. `Usage` writes to
standard error and exits with status 1 in the default configuration.

Put options before the name. Use `--` if a name begins with `-`:

```text
$ ./Greet -- -Norayr
Hello, -Norayr!
```

The quotes around `Good evening` are shell notation; they make those words
one argument. The library receives the words without the quotes. Our arrays
hold at most 79 characters plus the terminating `0X`. The string fetch
routines truncate to fit; if accepting long names matters, use the stream
argument interface or add suitable length handling instead of assuming the
whole argument fitted.

We will use `UnixArguments` again in the file example. For now, we have a
program with an imported module of our own, a visible initialization order,
and a way for its user to supply input without changing the source.

Source: [Greet.om](examples/03-arguments/Greet.om).

## 4. A map of the library

We have used `Out` and `UnixArguments` without knowing much about the rest
of the library. You can usually work this way: choose a module for the job
at hand, read its definition, and learn the surrounding machinery as it
becomes useful.

Here are a few modules to start with:

| Need | Start here |
|---|---|
| Print text and integers | `Out`; `BasicWrite` for an explicit stream |
| Format reals or more elaborate output | `Write`, then `Print` |
| Read text and numbers | `Read` |
| Read or write bytes, seek, flush, close | `Streams` |
| Open a Unix file | `UnixFiles` |
| Manipulate bounded character strings | `Strings` |
| Read command-line options and arguments | `UnixArguments` |
| Collect error explanations | `RelatedEvents` |
| Set an exit status | `Process` |

A few names recur in their definitions. An *object* is generally a pointer
to a record participating in a library protocol; it need not have methods.
An *interface record* usually holds procedure variables implementing that
protocol. The following sections introduce the other terms through examples:

| Name | What it refers to |
|---|---|
| Stream | A source or destination of bytes, with operations and capabilities. |
| Discipline | Additional information attached to an object. |
| Event type | A category of notification with a configured reaction. |
| Event | One notification, possibly with additional typed data. |
| Related event | An event handled according to the policy of a particular object. |
| Service | A named capability installed on objects of registered types. |
| Persistent object | An object stored and reconstructed through registered routines. |

You need not memorize this table. Here is how some of the modules fit
together:

```text
Disciplines: attach information to an object
    ├── StreamDisciplines: attach formatting/parsing preferences
    ├── RelatedEvents: attach diagnostic-routing policy
    └── Services: associate objects with registered types and capabilities

Streams: use a byte-oriented protocol
    ├── UnixFiles: a file descriptor behind that protocol
    ├── Strings: a character array behind that protocol
    └── Texts: a growing in-memory text behind that protocol

PersistentObjects: registered reconstruction and storage operations
    ├── Services: identify and register types
    └── Streams / NetIO: carry the serialized representation
```

This is not a complete import graph. It shows a distinction that will be
useful in the examples. A file implementation supplies bytes; a formatting
discipline chooses line endings; an error policy chooses where diagnostics
go. The module that reads those bytes need not make all three decisions.

For basic output to an explicitly chosen stream, we can now write:

```oberon
BasicWrite.LineS(Streams.stderr, "Something went wrong.");
```

Import `BasicWrite` and `Streams` for this fragment. The `S` suffix commonly
means that a routine takes a stream argument. Unlike `Out.Line`, this call
lets us choose standard error as the destination.

## 5. Streams: one algorithm, several sources

Suppose we want to count newlines. We could write one routine to walk a
character array and another to read a file. With streams, the same routine
can do both. It receives a `Streams.Stream`; the caller decides where that
stream comes from.

The following program tries a short string first, then standard input:

```oberon
MODULE CountLines;
   IMPORT Out, Process, Streams, Strings;
   VAR s: Streams.Stream; sample: ARRAY 80 OF CHAR; lines: LONGINT;

   PROCEDURE Count(s: Streams.Stream; VAR lines: LONGINT) : BOOLEAN;
      VAR ch: CHAR;
   BEGIN
      lines := 0;
      WHILE Streams.ReadByte(s, ch) DO
         IF ch = 0AX THEN INC(lines) END;
      END;
      RETURN s.eof & ~s.error
   END Count;

BEGIN
   sample := "first second ";
   sample[5] := 0AX; sample[12] := 0AX;
   Strings.Open(s, sample);
   IF ~Count(s, lines) THEN Process.Exit(1) END;
   Out.String("string: "); Out.Int(lines, 0); Out.Ln;
   IF ~Streams.Close(s) THEN Process.Exit(1) END;
   IF ~Count(Streams.stdin, lines) THEN Process.Exit(1) END;
   Out.String("stdin: "); Out.Int(lines, 0); Out.Ln;
END CountLines.
```

`0AX` is the newline character. The two assignments replace spaces in the
sample with newlines. The routine counts newline bytes, like `wc -l`; an
unterminated final line is not counted.

Try:

```sh
ulmo -m CountLines.om
printf 'one\ntwo\n' | ./CountLines
```

Output:

```text
string: 2
stdin: 2
```

Nothing in `Count` depends on `Strings`. It could just as well receive a
stream opened by `UnixFiles`. This is particularly useful when testing a
parser: provide its input in memory instead of creating a file or replacing
the parser's I/O code.

### Reading and reaching the end

1. `Strings.Open` opens the existing array; it does not give you an
   independently owned, infinitely growing copy. The array must remain
   alive while the stream is used. Its terminating `0X` is not input data.
2. `Streams.ReadByte` returns whether a byte was read. False can mean end
   of input **or a failure**, so the example checks `eof` and `error`.
3. Standard input is borrowed. The example closes the string stream it
   opened, but does not close the process's standard input.
4. This example checks success without giving detailed diagnostics. Section
   8 shows how to collect the explanations of a failure.

`Streams` supports more than byte-at-a-time access: `ReadPart`, `ReadPacket`,
`WritePart` and other operations handle blocks. The simple version is for
learning the protocol, not a claim that byte-at-a-time copying is optimal.

Source: [CountLines.om](examples/04-streams/CountLines.om).

## 6. Disciplines: extending an object without changing its record

Suppose several modules share a stream. One wants to describe it in a
diagnostic as "the report destination." Another only writes bytes and has
no interest in the name. We could extend the stream record, but then we
would have to arrange for the right extension to be created wherever the
stream is opened.

Ulm offers another way: attach a separate record to the existing object.
That record is called a discipline. Our label would look like this:

```text
existing stream
    ├── library's own attached information
    └── our label discipline: "the report destination"
```

A stream may have several disciplines. To tell our label apart from them,
we obtain an identifier with `Disciplines.Unique`. We do this once, in the
module body, just as `Counter` initialized its count. Every label created
by this module uses the same identifier.

`Labels.od`:

```oberon
DEFINITION Labels;
   IMPORT Disciplines;
   PROCEDURE Set(object: Disciplines.Object; text: ARRAY OF CHAR);
   PROCEDURE Get(object: Disciplines.Object; VAR text: ARRAY OF CHAR) : BOOLEAN;
END Labels.
```

`Labels.om`:

```oberon
MODULE Labels;
   IMPORT Disciplines;
   TYPE
      Label = POINTER TO LabelRec;
      LabelRec = RECORD
         (Disciplines.DisciplineRec)
         text: ARRAY 80 OF CHAR;
      END;
   VAR id: Disciplines.Identifier;

   PROCEDURE Set(object: Disciplines.Object; text: ARRAY OF CHAR);
      VAR label: Label;
   BEGIN
      NEW(label); label.id := id;
      COPY(text, label.text);
      Disciplines.Add(object, label);
   END Set;

   PROCEDURE Get(object: Disciplines.Object; VAR text: ARRAY OF CHAR) : BOOLEAN;
      VAR label: Label;
   BEGIN
      IF Disciplines.Seek(object, id, label) THEN
         COPY(label.text, text); RETURN TRUE
      END;
      text[0] := 0X; RETURN FALSE
   END Get;

BEGIN
   id := Disciplines.Unique();
END Labels.
```

Notice that `Labels.od` says nothing about `Label` or its identifier. A
user of the module only needs to call `Set` and `Get`.

`LabelDemo.om`:

```oberon
MODULE LabelDemo;
   IMPORT Labels, Out, Streams;
   VAR name: ARRAY 80 OF CHAR;
BEGIN
   Labels.Set(Streams.stdout, "the report destination");
   IF Labels.Get(Streams.stdout, name) THEN Out.Line(name) END;
   Labels.Set(Streams.stdout, "the renamed destination");
   IF Labels.Get(Streams.stdout, name) THEN Out.Line(name) END;
   IF ~Labels.Get(Streams.stderr, name) THEN Out.Line("stderr has no label") END;
END LabelDemo.
```

Put all three source files in one example directory:

```sh
ulmo -m LabelDemo.om
./LabelDemo
```

The driver finds and compiles the imported `Labels` implementation. Output:

```text
the report destination
the renamed destination
stderr has no label
```

`Add` replaces an attachment with the same identifier. It does not erase
other kinds of disciplines. `Seek` returns false when the attachment is
absent. Our `Get` promises a non-NIL object and enough destination space for
the label; these are small-example preconditions, not a general-purpose
unbounded string API.

### Why not just add a field?

If the label is an ordinary part of a record you own, adding a field is
usually the simpler answer. Disciplines are useful in different situations:

- you do not own the original record;
- multiple independent modules want optional information on it;
- the same addition should work across several record extensions;
- changing the base record would spread unrelated knowledge into its owner.

The attachment belongs to the object, not a variable name or
filename. Another pointer to the same stream finds the same label. A newly
opened stream, even for the same file, is a different object.

This label does not alter writing. Only code that calls `Labels.Get` notices
it. More elaborate disciplines may contain procedure variables as well as
data, but there is no need to start there.

Sources: [Labels.od](examples/05-labels/Labels.od),
[Labels.om](examples/05-labels/Labels.om),
[LabelDemo.om](examples/05-labels/LabelDemo.om).

## 7. Built-in disciplines: formatting belongs to the stream

We do not have to invent every discipline ourselves. `StreamDisciplines`
provides several for text input and output: line terminators, indentation,
field separators and whitespace.

For example, a report writer may need to produce different line endings
for different destinations. It can look up the preference on its stream
instead of taking another parameter on every call. Let us try that with a
string stream, so we can see the resulting text:

```oberon
MODULE FormatDemo;
   IMPORT BasicWrite, Out, Process, StreamDisciplines, Streams, Strings;
   VAR s: Streams.Stream; text: ARRAY 80 OF CHAR;
      ending: StreamDisciplines.LineTerminator;
BEGIN
   text := ""; Strings.Open(s, text);
   ending := "|";
   StreamDisciplines.SetLineTerm(s, ending);
   StreamDisciplines.SetIndentationWidth(s, 3);
   BasicWrite.IndentS(s); BasicWrite.LineS(s, "first");
   BasicWrite.IndentS(s); BasicWrite.LineS(s, "second");
   IF s.error THEN Process.Exit(1) END;
   Out.Line(text);
   IF ~Streams.Close(s) THEN Process.Exit(1) END;
END FormatDemo.
```

```sh
ulmo -m FormatDemo.om
./FormatDemo
```

Output, with three spaces before each word:

```text
   first|   second|
```

The unusual `|` terminator makes the effect visible. For CRLF output you
would fill a `LineTerminator` with `0DX`, `0AX`, then `0X`.

Notice the explicit calls to `IndentS`: setting indentation does not
automatically indent every output operation. Similarly, `LineS` uses the
terminator, but raw `Streams.WriteByte` writes exactly the byte you give it.

Do not confuse `StreamDisciplines.SetLineTerm` with `Streams.LineTerm`:

- the discipline is a convention used by participating text operations;
- `Streams.LineTerm` selects a flush-trigger character for a line-buffered
  stream.

These are related concerns, but changing one is not the same as changing
the other. The preference belongs to `s`, so the final `Out.Line(text)`
still uses the ordinary terminator of standard output.

On input, `Read` consults stream disciplines too. `SetWhiteSpace` and
`SetFieldSepSet` let a reader adapt its token or field interpretation without
rewriting its stream implementation. `Read.FieldS` is useful for simple
delimited fields; it is not, by itself, a complete quoted CSV parser.

Source: [FormatDemo.om](examples/06-formatting/FormatDemo.om).

## 8. Related events: let the caller choose how to report errors

Opening a file can fail. Sometimes we want to print a message and stop;
sometimes we want to try another directory. The routine that opens the
file cannot know which response its caller wants.

Many Ulm library operations therefore give you two things:

1. a Boolean or status telling you whether the operation succeeded;
2. structured events explaining failures, routed to an object you supply.

To collect the explanations, we create an ordinary `RelatedEvents.Object`
and ask for its events to be queued. This object is often called an error
sink:

```oberon
NEW(errors);
RelatedEvents.QueueEvents(errors);
```

Now library code can report to `errors` without printing anything itself.
The caller checks the result, then chooses what to do with the queue.

Here is a complete file-display program. It accepts one filename and writes
the file's bytes to standard output:

```oberon
MODULE ShowFile;
   IMPORT BasicWrite, Events, Process, RelatedEvents, Streams,
      SysErrors, UnixArguments, UnixFiles;
   VAR s: Streams.Stream; errors: RelatedEvents.Object;
      filename: ARRAY 1024 OF CHAR; ch: CHAR; ok: BOOLEAN;

   PROCEDURE Report(context: ARRAY OF CHAR);
      VAR queue: RelatedEvents.Queue; event: Events.Event;
   BEGIN
      BasicWrite.LineS(Streams.stderr, context);
      RelatedEvents.GetQueue(errors, queue);
      WHILE queue # NIL DO
         event := queue.event;
         BasicWrite.StringS(Streams.stderr, "  ");
         BasicWrite.LineS(Streams.stderr, event.message);
         IF event IS SysErrors.Event THEN
            WITH event: SysErrors.Event DO
               BasicWrite.StringS(Streams.stderr, "  ");
               BasicWrite.LineS(Streams.stderr, event.text);
            END;
         END;
         queue := queue.next;
      END;
   END Report;

BEGIN
   UnixArguments.Init("filename");
   IF ~UnixArguments.GetArg(filename) THEN UnixArguments.Usage END;
   UnixArguments.AllArgs;
   NEW(errors); RelatedEvents.QueueEvents(errors);
   IF ~UnixFiles.Open(s, filename, UnixFiles.read,
                      Streams.onebuf, errors) THEN
      Report("Cannot open the input file:"); Process.Exit(1);
   END;
   RelatedEvents.Forward(s, errors);
   RelatedEvents.Forward(Streams.stdout, errors);
   ok := TRUE;
   WHILE ok & Streams.ReadByte(s, ch) DO
      ok := Streams.WriteByte(Streams.stdout, ch);
   END;
   ok := ok & s.eof & ~s.error;
   IF ~Streams.Close(s) THEN ok := FALSE END;
   IF ~Streams.Flush(Streams.stdout) THEN ok := FALSE END;
   IF ~ok OR RelatedEvents.EventsPending(errors) THEN
      Report("Cannot finish displaying the file:"); Process.Exit(1);
   END;
END ShowFile.
```

Try it in its own directory:

```sh
ulmo -m ShowFile.om
printf 'first\nsecond\n' > input.txt
./ShowFile input.txt
./ShowFile no-such-file.txt
```

The first run displays the file. The second prints an explanation to
standard error and returns status 1. Exact OS diagnostic wording may vary.
No filename, or extra arguments, produces a usage message.

### Where do the errors go?

Opening and later stream operations report in different ways:

```text
UnixFiles.Open(..., errors) ───────────────→ errors queue

read / close on s ── RelatedEvents.Forward(s, errors) ──→ errors queue

write / flush on stdout ── Forward(stdout, errors) ────→ errors queue
```

Supplying `errors` to `Open` is not a substitute for forwarding subsequent
stream events. Setting up both routes makes the intention explicit.

`GetQueue` takes the queued events out of the sink; a second call will
not retrieve the same events again. Queue nodes refer to the original event
objects, including their extended fields. That is why `Report` can inspect
`SysErrors.Event.text`, which may contain a filename or other context.

If your code needs to distinguish OS failures, inspect
`SysErrors.Event.errno` rather than comparing the printed message.

### Why both a return value and events?

The return value controls the program's flow. The events explain what
happened. Keeping them separate makes it possible to attempt several
operations and report their explanations together, or to suppress an
expected failure without suppressing failures everywhere.

Do not expect raising a related event to unwind the stack. An operation
still needs to return failure or otherwise stop using invalid results.

### A note about NIL

NIL does not mean "discard the errors." It selects ordinary event handling.
Some library event types are ignored by default, but a newly defined event
type defaults to aborting. If you deliberately want to discard related
events, pass `RelatedEvents.null`. The operation can still fail, so check
its result.

Likewise, queueing an error does not repair the failure. We still check
the read and write results. We also flush standard output before claiming
success: a buffered write can appear to succeed and fail later when the
buffer is sent to its destination.

Keep forwarding graphs simple. Do not forward an object to itself or create
a cycle. `RelatedEvents.Save`/`Restore` support scoped policy changes, but
require correctly balanced calls; they are not needed in this first utility.
In reusable code, changing the policy of a borrowed stream deserves care.

Source: [ShowFile.om](examples/07-file-errors/ShowFile.om).

## 9. Your own structured diagnostics

We can use the same error-handling arrangement in a module of our own.
Consider a routine that checks a port number. Besides an explanation, we
would like to retain the number it rejected. An extended event record
gives us a place to put it.

This example checks ports intended for connecting to a service, and accepts
1–65535. Port zero is useful in other situations, such as requesting an
automatically assigned bind port, but is not accepted by this routine.

`Ports.od`:

```oberon
DEFINITION Ports;
   IMPORT Events, RelatedEvents;
   TYPE
      Event = POINTER TO EventRec;
      EventRec = RECORD (Events.EventRec) value: LONGINT END;
   VAR invalid: Events.EventType;
   PROCEDURE Check(value: LONGINT; errors: RelatedEvents.Object) : BOOLEAN;
END Ports.
```

`Ports.om`:

```oberon
MODULE Ports;
   IMPORT Events, RelatedEvents;
   TYPE
      Event = POINTER TO EventRec;
      EventRec = RECORD (Events.EventRec) value: LONGINT END;
   VAR invalid: Events.EventType;

   PROCEDURE Check(value: LONGINT; errors: RelatedEvents.Object) : BOOLEAN;
      VAR event: Event;
   BEGIN
      IF (value >= 1) & (value <= 65535) THEN RETURN TRUE END;
      NEW(event); event.type := invalid;
      event.message := "port must be between 1 and 65535";
      event.value := value;
      RelatedEvents.Raise(errors, event);
      RETURN FALSE
   END Check;

BEGIN
   Events.Define(invalid);
END Ports.
```

`PortDemo.om`:

```oberon
MODULE PortDemo;
   IMPORT Events, Out, Ports, RelatedEvents;
   VAR errors: RelatedEvents.Object; queue: RelatedEvents.Queue;
      event: Events.Event;
BEGIN
   NEW(errors); RelatedEvents.QueueEvents(errors);
   IF Ports.Check(8080, errors) THEN Out.Line("8080 is accepted") END;
   IF ~Ports.Check(70000, errors) THEN
      RelatedEvents.GetQueue(errors, queue);
      WHILE queue # NIL DO
         event := queue.event;
         Out.Line(event.message);
         IF event IS Ports.Event THEN
            WITH event: Ports.Event DO
               Out.String("rejected value: "); Out.Int(event.value, 0); Out.Ln;
            END;
         END;
         queue := queue.next;
      END;
   END;
END PortDemo.
```

```sh
ulmo -m PortDemo.om
./PortDemo
```

```text
8080 is accepted
port must be between 1 and 65535
rejected value: 70000
```

The validator knows the rule and the rejected value. The main module
decides how to present them. A test could inspect `value` without printing;
a graphical application could highlight the relevant input field.

There are two types involved here:

- `Ports.Event` describes the payload record and enables the type guard;
- `Ports.invalid` identifies the notification category and its reactions.

All raised events must have a defined, non-NIL `event.type`. `message` is a
bounded character array; put substantial or machine-readable context in
additional fields instead of trying to squeeze everything into that string.

The example's sink is prepared before the invalid check. Calling the same
check with NIL would select ordinary handling for `Ports.invalid`, whose
newly defined default reaction is to abort. Calling it with
`RelatedEvents.null` deliberately discards the diagnostic and still returns
false.

Sources: [Ports.od](examples/08-custom-errors/Ports.od),
[Ports.om](examples/08-custom-errors/Ports.om),
[PortDemo.om](examples/08-custom-errors/PortDemo.om).

## 10. Events: notifications without hard-wiring their consumers

So far we have queued events for later inspection. We can also arrange
for a procedure to be called when an event occurs. For example, an editor
might announce that a document changed without knowing which views want
to be updated.

Here is the small version of that arrangement:

```oberon
MODULE EventDemo;
   IMPORT Events, Out;
   VAR changed: Events.EventType; event: Events.Event;

   PROCEDURE Notify(event: Events.Event);
   BEGIN
      Out.String("observer: "); Out.Line(event.message);
   END Notify;

BEGIN
   Events.Define(changed);
   Events.Handler(changed, Notify);
   NEW(event); event.type := changed; event.message := "document changed";
   Events.Raise(event);
END EventDemo.
```

```sh
ulmo -m EventDemo.om
./EventDemo
```

```text
observer: document changed
```

A useful application split would put the event type and producer in one
module, and install the consumers from other modules. Several consumers
can register handlers without the producer importing them.

An event is not a newly launched thread or an OS process. This example's
handler runs during the raise. Ulm also has event priorities: events that
cannot be delivered at the current priority may be deferred. Therefore do
not build a general protocol on the assumption that every `Raise` always
finishes every handler before returning.

Handlers run in reverse registration order. Make them independent of that
order where possible. There is also a distinction between unhandled events
and optional notifications: `Events.Define` starts with an aborting default.
If an application category is intentionally harmless without observers,
its owner can call `Events.Ignore(type)` after defining it; registering a
handler later enables handler delivery.

`Events.Ignore` clears handlers, so it is not a harmless temporary mute for
an already configured type. Consult `SaveReaction`/`RestoreReaction` for
scoped reaction changes.

For object-specific delivery rather than queueing, look at
`RelatedEvents.GetEventType`. Its handlers receive a `RelatedEvents.Event`
wrapper: `.object` is the associated object and `.event` is the original
event. That differs from retrieving original events with `GetQueue`.

Use an ordinary procedure call when the consumer is fixed and the producer
should know it. Use events when separating the producer from interested
parties is the actual problem.

Source: [EventDemo.om](examples/09-events/EventDemo.om).

## 11. Services: teaching a type an optional capability

Suppose we have several kinds of document, and want to add a way to
summarize each of them. We could put every summary routine in the original
document modules. That becomes inconvenient if the types and the new
facility are maintained by different people.

`Services` lets us register support separately. A type can have an
installer for a particular service, and a user can request that service
without knowing which installer will supply it. A discipline can hold
the information or operations installed on the individual object.

Let us first try this in one module. The service will attach a cached
summary to a note:

```oberon
MODULE ServiceDemo;
   IMPORT Disciplines, Out, Services;
   TYPE
      Note = POINTER TO NoteRec;
      NoteRec = RECORD (Services.ObjectRec) title: ARRAY 80 OF CHAR END;
      Summary = POINTER TO SummaryRec;
      SummaryRec = RECORD
         (Disciplines.DisciplineRec)
         text: ARRAY 80 OF CHAR;
      END;
   VAR noteType: Services.Type; summaryService: Services.Service;
      summaryId: Disciplines.Identifier; note: Note; text: ARRAY 80 OF CHAR;

   PROCEDURE InstallSummary(object: Services.Object; service: Services.Service);
      VAR summary: Summary;
   BEGIN
      WITH object: Note DO
         NEW(summary); summary.id := summaryId;
         COPY(object.title, summary.text);
         Disciplines.Add(object, summary);
      END;
   END InstallSummary;

   PROCEDURE GetSummary(object: Services.Object; VAR text: ARRAY OF CHAR) : BOOLEAN;
      VAR summary: Summary;
   BEGIN
      IF Services.Install(object, summaryService) &
            Disciplines.Seek(object, summaryId, summary) THEN
         COPY(summary.text, text); RETURN TRUE
      END;
      text[0] := 0X; RETURN FALSE
   END GetSummary;

BEGIN
   summaryId := Disciplines.Unique();
   Services.CreateType(noteType, "ServiceDemo.Note", "");
   Services.Create(summaryService, "ServiceDemo.Summary");
   Services.Define(noteType, summaryService, InstallSummary);
   NEW(note); Services.Init(note, noteType);
   note.title := "A small note";
   IF GetSummary(note, text) THEN Out.Line(text) END;
   IF GetSummary(note, text) THEN Out.Line(text) END;
END ServiceDemo.
```

```sh
ulmo -m ServiceDemo.om
./ServiceDemo
```

```text
A small note
A small note
```

There are three separate registration steps:

1. `CreateType` registers the library's description of our object type.
   The empty base name makes this an independent root in that registry.
2. `Create` creates the named summary service.
3. `Define` connects this type/service pair to an installer.

`Services.Init` associates the individual note with its registered type.
Oberon's record extension and type guards do not perform this additional
library registration automatically.

The first `GetSummary` installs the service on the object. The second reuses
the installed service; the installer is not called again for that pair.
Installation could attach data, a table of procedure variables, or both.

The summary is a snapshot. Editing `note.title` later does not
automatically update the summary. A real design could invalidate the cache
on a change event, or attach operations that compute the current summary.
The registry does not solve data freshness for you.

### Splitting this into modules

For one note type, a plain `Summarize(note, text)` procedure would be
simpler. The extra arrangement becomes useful when we want the data and
the summarizing facility to remain separate.

In a larger design, you could split it into:

```text
Notes       — owns the data and registered note type
Summaries   — defines the capability and how clients request it
NoteSummary — knows both and registers the adapter
Application — imports NoteSummary so that registration happens
```

Then `Notes` need not import every capability invented for notes, and
`Summaries` need not know every concrete type. An unsupported object makes
`Install` return false. `Supported` can ask whether support exists without
installing it on that object.

Here "service" is an in-process library capability, not a resident daemon
or a network microservice. Use module-qualified registration names to avoid
collisions. These examples register support through ordinary imports; they
do not require dynamic plugin loading.

Source: [ServiceDemo.om](examples/10-services/ServiceDemo.om).

## 12. Persistence: storing values with their type

An object in memory has a record type. If we write it to a file, how will
the reader know which kind of object to create? We could invent our own
type tags and a large CASE statement. `PersistentObjects` provides a
registration scheme for this job instead.

We register the type together with routines to create, read and write its
objects. Those routines still describe the data to be stored. The library
does not simply dump arbitrary record memory into the file.

The example stores one number. Run it only in its example directory:
**it creates or truncates `number.dat` on every run.**

```oberon
MODULE SavedNumber;
   IMPORT NetIO, Out, PersistentObjects, Process, RelatedEvents,
      Services, Streams, UnixFiles;
   TYPE
      Number = POINTER TO NumberRec;
      NumberRec = RECORD (PersistentObjects.ObjectRec) value: LONGINT END;
   VAR numberType: Services.Type; interface: PersistentObjects.Interface;
      number: Number; restored: PersistentObjects.Object;
      s: Streams.Stream; errors: RelatedEvents.Object;

   PROCEDURE Create(VAR object: PersistentObjects.Object);
      VAR number: Number;
   BEGIN
      NEW(number); PersistentObjects.Init(number, numberType);
      object := number;
   END Create;

   PROCEDURE Read(s: Streams.Stream; object: PersistentObjects.Object) : BOOLEAN;
   BEGIN
      WITH object: Number DO RETURN NetIO.ReadLongInt(s, object.value) END;
   END Read;

   PROCEDURE Write(s: Streams.Stream; object: PersistentObjects.Object) : BOOLEAN;
   BEGIN
      WITH object: Number DO RETURN NetIO.WriteLongInt(s, object.value) END;
   END Write;

   PROCEDURE Require(ok: BOOLEAN);
   BEGIN
      IF ~ok THEN Out.Line("persistence example failed"); Process.Exit(1) END;
   END Require;

BEGIN
   NEW(interface);
   interface.create := Create; interface.read := Read; interface.write := Write;
   interface.createAndRead := NIL;
   PersistentObjects.RegisterType(numberType, "SavedNumber.Number",
                                 "", interface);
   NEW(number); PersistentObjects.Init(number, numberType); number.value := 42;
   NEW(errors); RelatedEvents.QueueEvents(errors);
   Require(UnixFiles.Open(s, "number.dat", UnixFiles.write + UnixFiles.create,
                         Streams.onebuf, errors));
   RelatedEvents.Forward(s, errors);
   Require(PersistentObjects.Write(s, number));
   Require(Streams.Close(s));
   Require(UnixFiles.Open(s, "number.dat", UnixFiles.read, Streams.onebuf, errors));
   RelatedEvents.Forward(s, errors);
   Require(PersistentObjects.Read(s, restored));
   Require(restored IS Number);
   number := restored(Number);
   Out.String("restored: "); Out.Int(number.value, 0); Out.Ln;
   Require(Streams.Close(s));
   Require(~RelatedEvents.EventsPending(errors));
END SavedNumber.
```

```sh
ulmo -m SavedNumber.om
./SavedNumber
```

```text
restored: 42
```

The callback table tells the library:

- how to allocate and initialize a `Number`;
- how to read its payload into an allocated object;
- how to write its payload from an existing object.

`createAndRead` is an alternative combined callback for special cases; this
ordinary example uses separate callbacks and sets it to NIL explicitly.

There is a registration detail worth remembering: a type directly based on
`PersistentObjects.ObjectRec` uses an empty `baseName` in `RegisterType`.
The persistence implementation supplies its own root relationship. Do not
copy the base record's name into that parameter. For an actual registered
persistent extension, the parameter identifies its registered persistent
base type.

`NetIO` supplies scalar encoding operations. Its name does not mean this
example opens a socket. Here it writes and reads the `LONGINT` payload;
`PersistentObjects` handles the surrounding type information. A string
stream is not a suitable replacement for arbitrary binary data because it
uses `0X` as the string terminator; use an appropriate byte stream instead.

The reader receives a generic `PersistentObjects.Object`, so it checks the
record type before accessing `value`. Types needed for reconstruction must
be registered in the reading program, too. This self-contained example
registers the type and then writes and reads it in the same run.

### Changing a saved format

Registration does not settle every question about storage. If you change
the fields written by the callbacks, decide what should happen to files
written by the old version. Transactions and reconstruction of arbitrary
pointer graphs also need their own arrangements. Treat this as an example
for your own data, not as a hardened reader for arbitrary untrusted files.

`Require` deliberately keeps this example short. For an application, use
the queue-reporting technique from section 8, give each failure useful
context, and clean up resources on recoverable failure paths.

Persistence is also used by the compiler: its cached `.obj` files contain
structured compiler data in this format. That does not mean your ordinary
application must use persistence.

Source: [SavedNumber.om](examples/11-persistence/SavedNumber.om).

## 13. Finding the right module for your next problem

The library has more modules than we have room to introduce here. This
table gives you a place to start looking. Some of the less commonly used
parts still contain historical, platform-dependent code; check their
contracts and try a small program before relying on them in an application.

| Problem | Modules to investigate | Decision to make |
|---|---|---|
| Small terminal output | `Out`, `BasicWrite` | Is standard output enough, or should the caller supply a stream? |
| Floating-point / formatted output | `Write`, `Print` | Start with explicit write routines; use formatting templates when helpful. |
| Token, line or numeric input | `Read`, `StreamDisciplines`; `Scan` for format-directed input | What counts as whitespace or a field boundary? How will malformed input be reported? |
| Fixed-capacity strings | `Strings` | What is the maximum size? Does truncation need explicit detection? |
| Growing in-memory text | `Texts` | A stream-backed text is useful when the final size is not known. |
| Shared immutable strings | `ConstStrings` | Useful for identifiers and repeatedly referenced names; not the first tool for every small string. |
| Ordinary files | `UnixFiles`, `Streams` | Choose open mode and buffering, then forward stream errors. |
| Directory enumeration | `UnixDirectories`, `Streams` | This stream supplies `Entry` records, not text lines; inspect its record-reading contract. |
| Filesystem metadata / operations | `SysStat`, `SysFile` | Use these when opening a stream is not the operation you need. |
| Arguments | `UnixArguments` | `Init`, `GetFlag`, option fetches, then `GetArg`; reject leftover arguments where appropriate. |
| Environment variables | `UnixEnvironment` | Retrieve a value as a string or stream. |
| Lists and sets | `Lists`, `Sets` | Read their element/comparison types; use a plain array when it is enough. |
| Attached optional metadata | `Disciplines` | Keep the identifier and representation private to the module owning the attachment. |
| Multiple diagnostics from one operation | `RelatedEvents`, `Events` | Queue original events; examine typed fields instead of parsing messages. |
| OS failure details | `SysErrors` | Inspect `errno` and context; retain a user-facing explanation. |
| Notifications | `Events` | Decide whether absence of handlers is harmless or an error. |
| Optional type-dependent capability | `Services` | Register the type, the service, and the adapter between them. |
| Structured object storage | `PersistentObjects`, `NetIO` | Define the payload and reconstruction routines; plan compatibility separately. |
| Persistent attachments | `PersistentDisciplines` | Ordinary `Disciplines.Add` alone does not make an attachment survive serialization. |
| Stream wrappers / slices | `SubStreams`, `CopyingStreams`, `FragmentedStreams` | Understand bounds, backing-stream lifetime and which object owns closure. |
| Transactional stream storage | `TransStreams` | A specialized storage protocol with begin/commit/abort, not an automatic option on every file. |
| Connections independent of transport | `Networks`, `InetTCP` / `Inet6TCP`, `UnixSockets` | `Networks` supplies the common protocol; the other modules adapt concrete address/transport types. |
| Concrete TCP or socket operations | `IPv4TCPSockets`, `IPv6TCPSockets`, `SysSockets` | Pick the abstraction level you need; a generic framework is not compulsory for each operation. |
| Times and clocks | `Times`, `Clocks`, `UnixClock` | `Clocks` is the protocol; `UnixClock` supplies the system clock. |
| Calendar/timezone conversion | `Timezones`, `UnixTimezones` | The generic API and native timezone provider are separate roles. |
| Timed or readiness-based waiting | `Conditions`, `Timers`, `Tasks` | Learn the cooperative scheduling model before composing waits. |
| Coroutine scheduling | `Coroutines`, `Tasks`, `Schedulers`, `RoundRobin` | These are not interchangeable names for kernel threads. |
| Shared-resource lifecycle | `Resources` | Needed when users and dependencies must coordinate release or termination. |
| Process termination | `Process` | Normal application exit includes library notification/cleanup. |
| Child processes / direct execution | `SysProcess` | Fork, exec and wait explicitly; account for descriptors, failure paths and raw argument vectors. |
| Deliberate shell execution | `UnixShell` | It really invokes a shell. Do not choose it when shell-free execution is the requirement. |
| File descriptors and pipes | `SysIO` | Lower-level control means handling interruption, partial operations and lifetime yourself. |
| Heap status / collection policy | `Storage` | Understand the collector before changing policy; this is not needed for ordinary `NEW`. |

### Understanding the names

Some names reveal a pattern, not an absolute rule:

- **`Sys...`** often means an OS-facing or runtime-facing layer.
- **`Unix...`** often adapts Unix facilities to a library abstraction.
- **A generic name**, such as `Streams`, `Clocks` or `Networks`, often names
  the abstraction used by clients.
- **`Persistent...`** indicates an explicit persistence protocol, not that
  all instances are automatically saved.

Follow that pattern when looking for implementation details. If you want
to count input bytes, use `Streams`; if you want to know how file bytes
arrive, inspect `UnixFiles`, then `SysIO`.

Some mechanisms that look related solve different problems:

| Choose this | When you mean this |
|---|---|
| A plain record field | This information is intrinsic to my record. |
| A discipline | This optional information belongs to an existing object's identity. |
| A procedure variable / interface table | This implementation supplies these operations. |
| A service | Registered types can acquire this optional capability through adapters. |
| An event | Interested consumers should be notified without being hard-wired into the producer. |
| A related-event queue | This operation should accumulate explanations for its caller. |

## 14. Working comfortably with the compiler

### Keep one program's compiled objects together

The driver writes compiled files into the current working directory and
links the locally compiled implementations it finds there. Use a separate
directory per program, not one directory containing unrelated tutorial main
modules.

The companion examples already use that layout:

```text
examples/
    01-hello/          Hello.om
    02-modules/        Counter.od, Counter.om, UseCounter.om
    03-arguments/      Greet.om
    04-streams/        CountLines.om
    05-labels/         Labels.od, Labels.om, LabelDemo.om
    ...
```

For a separate build directory, supply the source path and, where needed,
its source directory:

```sh
ulmo -I ../sources -m ../sources/MyProgram.om
```

The current directory remains the output directory. `-I` adds a source
search path; it is not an output-directory option.

### Useful commands

```sh
ulmo -m Main.om                      # compile and link
ulmo -m Main.om -o my-program        # select executable filename
ulmo -m Main Main.om Helper.om       # explicit main, several sources
ulmo Helper.om                      # compile without linking a program
ulmo -arch i386 -m Main.om           # select target, if its tools are installed
ulmo -v 6 -m Main.om                 # explain cache / dependency decisions
```

For a module of your own that exports procedures, write its `.od`, keep its
`.om` available in the search path, then import it from the main module.
You normally need only name the main source when linking: the driver
discovers required local implementations. Explicitly naming sources is
useful when selecting particular implementations.

### Do not confuse the compiled file formats

For module `M`, you may see:

| File | What it is |
|---|---|
| `M.od` | Source of the public definition |
| `M.om` | Source of the implementation |
| `M-def-gen.obj` | Cached architecture-independent public interface |
| `M-def-AMD64.obj` or `M-def-I386.obj` | Cached target-specific interface information |
| `M-mod-AMD64.obj` or `M-mod-I386.obj` | Compiler representation of code, data, types and relocations |
| `M.o` | ELF object produced for the external linker |
| `M` or your `-o` name | Executable |

The `.obj` files are not ELF objects. They use the library's persistence
format. The driver orchestrates compilation, object conversion and linking;
you ordinarily do not need to invoke `ulmoc`, `obtofgen`, `tof2elf` or
`oblink` yourself. `-S` exposes the intermediate textual `.tof` output when
you want to investigate generated code.

Installed library interfaces are reused when valid. The compiler checks
source/interface fingerprints rather than merely trusting that a filename
exists. `-v 6` is useful when something is unexpectedly recompiled.

### Local library changes are intentional overrides

A local module with the same name as an installed library module can take
precedence. This is useful for experimentation, but can also explain an
unexpected build. Do not name an unrelated helper `Streams`, `Events`, or
another existing library module. Use distinctive names for your own code.

### Interface errors and runtime checks

If the compiler rejects a declaration, compare the actual `.od` signature:

- parameter order and `VAR` matter;
- an open array is not interchangeable with every fixed array assignment;
- repeated type and procedure declarations in `.od` and `.om` must agree;
- `LONGINT` is not a pointer-sized integer on AMD64.

This guide leaves the normal runtime checks enabled. Bounds and NIL checks
are useful development tools, not evidence that your program runs in a VM.
Do not solve an unexplained runtime error by disabling checks.

At this release, `HUGEINT` is the 64-bit integer type on both targets;
`LONGINT` remains 32-bit. For raw addresses, consult `SYSTEM` and `Types`
rather than storing pointers in ordinary integers.

## 15. Things worth knowing about memory and resources

### NEW and garbage collection

Ordinary `NEW` allocations participate in the native collector. You do not
need to import `Storage` just to allocate a record. Its APIs are for
inspection, control and specialized runtime work.

The collector can only reclaim objects that are no longer reachable. If
your program keeps a list of old inputs or diagnostics, that list still
occupies memory even if you no longer intend to use it. Drop references
to large objects when you have finished with them.

The collector can move managed objects. Do not casually convert pointers
to untraced integers and assume those integers remain valid addresses.
Raw OS buffers and foreign interfaces require more care than the examples
in this guide. `Storage.DisableCollection` is a scoped low-level tool, not
a general replacement for understanding address lifetime.

At ulmo 0.11.2, managed address-space support still has a low-address
restriction; AMD64 does not imply an unrestricted 64-bit managed heap.
Check the project's current status before choosing it for very large heaps.

### Closing files is a separate responsibility

Leaving a procedure does not close the files it opened. There is no
scope-exit destructor here. In fact, `UnixFiles` streams stay referenced
by the library's open-stream list until closed; losing your local pointer
does not hand their descriptors over to the collector.

Close a file explicitly when you have finished with it, and check the
result if successful output matters.

- `Streams.Flush(s)` pushes buffered output and returns success/failure.
- `Streams.Close(s)` performs stream closure, including relevant flushing,
  and returns success/failure.
- `Streams.Release(s)` is a convenience closure operation without a Boolean
  result. Prefer `Close` when successful completion matters.

Do not assume that a successful buffered write proves the data reached its
destination. The program in section 8 checks a final flush. A flush is also
not the same promise as durable storage across a power failure.

`Resources` becomes useful when several objects or clients share a resource
and need coordinated lifecycle notifications. You do not need to learn it
before opening and explicitly closing one ordinary file.

### Application exit versus immediate OS exit

Use `Process.Exit` for ordinary application termination with a status. The
library can notify interested modules and perform its termination work.
`SysProcess.Exit` is immediate termination without that event mechanism;
it has legitimate low-level uses, such as child-process exec failure, but
is not the default substitute for `Process.Exit`.

### Coroutines do not make every program concurrent

The runtime uses coroutine and stack machinery, including in memory
management. Your small utility need not create tasks or manage a scheduler.

If you later use `Tasks`, you are entering a cooperative scheduling model.
Avoid assuming that a CPU-bound loop automatically yields, or that a task
is simply a kernel thread under another name. The higher-level Unix I/O
adapters can cooperate with task waits; that is one reason they contain
more machinery than a syscall wrapper.

## 16. A route through the original reference documentation

The original documentation is mostly a reference. Once you know which
module you need, it gives you the details of its operations. It is less
helpful when you are still asking why a module exists or how to begin
using it.

Use this order:

1. Find a likely module in the table in section 13.
2. Read the module's `.od`: start with types and the relevant procedures,
   not its entire revision history.
3. Look for a matching small example in this guide or the current project's
   `src/test` programs.
4. Read the corresponding `.om` only when a contract, default or ownership
   detail needs clarification.
5. Follow one relationship at a time: the stream implementation, the
   error-routing policy, or the registration protocol—not all at once.

For example, to understand `UnixFiles.Open`, ask:

- What open modes are accepted? Are existing contents truncated?
- What does the buffering argument mean?
- Where do opening errors go?
- What object comes back on success?
- How should subsequent errors be routed?
- Who closes it, and how is close failure detected?

Those questions are more useful than starting with every module imported
by `UnixFiles`.

Be cautious about old platform comments: some refer to SPARC, m68k, the
original database environment, or assumptions since changed by the Linux
port. Current signatures, implementations and tests are the authority for
this release. Even historical parameter comments can be misleading: the
direct-root `PersistentObjects.RegisterType` case in section 12 is an
example where understanding the implementation helps.

Find sources under the configured installation's `share/ulmo/src` directory
(normally `/usr/share/ulmo/src` or `/usr/local/share/ulmo/src`), or in the
checkout:

| Directory | Role |
|---|---|
| `src/rtl` | Runtime and foundational library modules; architecture-specific overrides are in subdirectories. |
| `src/lib` | Additional containers, adapters, networking and other general facilities. |
| `src/compiler` | Compiler modules; not required reading to begin using the library. |
| `src/test` | Executable regression examples for the current port. |

The `.a` library division is a build organization, not a requirement to
understand everything in an archive. Linking selects modules according to
dependencies and runtime startup; whole modules remain the units of linking
and initialization.

Useful references:

- [Current ulmo README](https://github.com/norayr/ulmo/blob/v0.11.2/readme.md)
- [Current module sources](https://github.com/norayr/ulmo/tree/v0.11.2/src)
- [Current regression programs](https://github.com/norayr/ulmo/tree/v0.11.2/src/test)
- [Original Ulm Oberon documentation](http://www.mathematik.uni-ulm.de/oberon/)

For the mechanisms demonstrated here, the most relevant definitions are
`Streams.od`, `Strings.od`, `Disciplines.od`, `StreamDisciplines.od`,
`RelatedEvents.od`, `Events.od`, `Services.od` and `PersistentObjects.od`
in `src/rtl`, plus `Out.od` in `src/lib`.

## Exercises and next steps

If you would like to try the ideas before writing a larger program, here
are a few changes to make to the examples:

1. **Streams:** have `CountLines` read an explicitly opened file as well as
   a string and standard input. Keep `Count` unchanged.
2. **Disciplines:** add a public `Labels.Clear` procedure using
   `Disciplines.Remove`. Keep the identifier private to `Labels`.
3. **Formatting:** generate two reports into two string streams, using
   different indentation and line terminators. Change neither report writer.
4. **Diagnostics:** teach `ShowFile.Report` to display `errno`. Do not parse
   the OS's message text.
5. **Validation:** check several bad values before taking the `Ports` queue.
   Verify that you receive several distinct payloads in the order raised.
6. **Events:** register two independent consumers, and decide explicitly
   what should happen if neither is installed.
7. **Services:** split `ServiceDemo` into data, capability and adapter
   modules. Keep the data module independent of the capability module.
8. **Persistence:** add a second payload field and decide how an older
   saved file should be handled. Do not mistake changing the callbacks for
   automatically solving format versioning.

Keep the small programs around as you experiment. A plain record field or
procedure call is often all you need. When an existing object needs an
optional label, a different reporting policy, or a capability supplied by
another module, you now have examples of how the library makes that possible.
