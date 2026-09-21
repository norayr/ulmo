# ULM Oberon AMD64 Backend — Architecture & AST Reference

Source directory: `src/oberon/AMD64*.om` / `src/oberon/AMD64*.od`

---

## 1. Pipeline Overview

```
.om source
   → OberonParser          (produces AST: Sym.Attribute tree)
   → Oberon64iAnalyzer     (type analysis, size/offset computation)
   → AMD64OberonAnalyzer   (AMD64-specific analysis pass)
   → AMD64ObCodeGen        (code generation → FragmentedStream)
   → AMD64OpCodeGenerator  (instruction encoding → bytes)
   → AMD64OberonTOF        (emit .obj in ULM TOF format)
   → obtofgen              (convert .obj → .tof text IR)
   → tof2elf               (convert .tof → ELF .o)
```

The compiler is a 32-bit i386 Oberon binary that generates AMD64 code.
Sizes are computed by `Oberon64iSymbols` (imported as `Sym32` in
AMD64ObCodeGen), NOT the i386 counterpart `Oberon32iSymbols`.

---

## 2. AST — `OberonSymbols` (`Sym`)

### 2.1 Type Forms (`Sym.Form`)

| Constant         | Value | Description |
|------------------|-------|-------------|
| `integer`        | 0     | LONGINT / INTEGER / SHORTINT |
| `cardinal`       | 1     | Unsigned integer |
| `address`        | 2     | SYS.ADDRESS — pointer-sized unsigned, 8 bytes on AMD64 |
| `real`           | 3     | REAL / LONGREAL |
| `boolean`        | 4     | BOOLEAN |
| `char`           | 5     | CHAR |
| `set`            | 6     | SET |
| `byte`           | 7     | BYTE |
| `coroutine`      | 8     | Coroutines.Coroutine — 8 bytes on AMD64 |
| `array`          | 9     | ARRAY |
| `record`         | 10    | RECORD |
| `pointer`        | 11    | POINTER TO — 8 bytes on AMD64 |
| `proceduretype`  | 12    | PROCEDURE type — 8 bytes on AMD64 |

Useful sets defined in `OberonSymbols`:
- `Sym.numeric = {integer, cardinal, address, real}`
- `Sym.structured = {array, record, pointer, proceduretype}`
- `Sym.specforms = {integer, cardinal, real}` — have arch-specific sizes

Size on AMD64 (from `Oberon64iSymbols.GetSize`):
- integer: 4, cardinal: 4, address: 8, real: 8, boolean: 1, char: 1,
  set: 4, byte: 1, coroutine: 8, pointer: 8, proceduretype: 8
- record/array: sum of fields

### 2.2 Identifier Classes (`Sym.Class`)

| Constant      | Value | Description |
|---------------|-------|-------------|
| `moduleC`     | 0     | Module |
| `constC`      | 1     | Constant |
| `typeC`       | 2     | Type |
| `varC`        | 3     | Variable |
| `procedureC`  | 4     | Procedure |

### 2.3 AST Node Modes (`Sym.AtMode`)

Every expression or statement is a `Sym.Attribute` with a `.mode` field:

#### Expression/designator modes
| Constant     | Value | Description |
|--------------|-------|-------------|
| `moduleAt`   | 0     | Module reference |
| `constAt`    | 1     | Named constant |
| `typeAt`     | 2     | Type reference |
| `varAt`      | 3     | Variable reference |
| `procAt`     | 4     | Procedure reference |
| `callAt`     | 5     | Procedure/function call |
| `refAt`      | 6     | Dereference (pointer^) |
| `selectAt`   | 7     | Field selection (rec.field) |
| `indexAt`    | 8     | Array index (arr[i]) |
| `guardAt`    | 9     | Type guard (expr(Type)) |
| `unaryAt`    | 10    | Unary operator (-, ~, ABS, ...) |
| `binaryAt`   | 11    | Binary operator (+, -, *, :=, #, ...) |
| `constvalAt` | 12    | Constant value literal |

#### Statement modes
| Constant      | Value | Description |
|---------------|-------|-------------|
| `ifAt`        | 13    | IF statement |
| `caseAt`      | 14    | CASE statement |
| `singleCaseAt`| 15    | Single CASE branch |
| `whileAt`     | 16    | WHILE loop |
| `repeatAt`    | 17    | REPEAT loop |
| `loopAt`      | 18    | LOOP |
| `exitAt`      | 19    | EXIT |
| `returnAt`    | 20    | RETURN |
| `withAt`      | 21    | WITH (type guard) |

Assignment is `binaryAt` with `opsy = Lex.becomes (53)`.
`Sym.stmtModes = {ifAt..withAt, callAt, binaryAt}`.

### 2.4 Key `opsy` Values (`OberonLex` symbols)

| Symbol    | Value | Op |
|-----------|-------|----|
| `plus`    | 40    | `+` |
| `minus`   | 41    | `-` |
| `times`   | 42    | `*` |
| `slash`   | 43    | `/` |
| `becomes` | 53    | `:=` assignment |
| `arrow`   | 54    | `^` dereference |
| `eql`     | 55    | `=` |
| `neq`     | 56    | `#` |
| `lst`     | 57    | `<` |
| `grt`     | 58    | `>` |
| `leq`     | 59    | `<=` |
| `geq`     | 60    | `>=` |

### 2.5 `Sym.Attribute` Key Fields

```
Attribute:
  mode      : AtMode         — what kind of node
  type      : Type           — result type (NIL for statement nodes)
  next      : Attribute      — next sibling in a list
  opsy      : Lex.Symbol     — for unaryAt/binaryAt: the operator
  leftop    : Attribute      — for binaryAt: left operand
  rightop   : Attribute      — for binaryAt: right operand / RHS of :=
  expression: Attribute      — for ifAt/whileAt/repeatAt: condition
  then      : Attribute      — for ifAt: then-body (linked list via .next)
  else      : Attribute      — for ifAt: else-body
  elsifs    : Attribute      — for ifAt: elsif chain
  body      : Attribute      — for whileAt/loopAt/singleCaseAt: body stmts
  proc      : Attribute      — for callAt: procedure being called
  firstparam: Attribute      — for callAt: first actual parameter
  paramcnt  : INTEGER        — for callAt: number of parameters
  ident     : Ident          — for varAt/procAt/moduleAt: the identifier
  cases     : Attribute      — for caseAt: singleCaseAt chain
  labels    : CaseLabels     — for singleCaseAt: case label list
```

---

## 3. Builtin Procedures

### 3.1 OberonStdProcedures (`OStd`)

| `stdproc` | Name     | Description |
|-----------|----------|-------------|
| 0         | `abs`    | ABS(x) |
| 1         | `adr`    | SYS.ADR(x) — returns address (8 bytes, form=address) |
| 2         | `ash`    | ASH(x,n) |
| 3         | `assert` | ASSERT(cond) |
| 4         | `bit`    | SYS.BIT(adr,n) |
| 7         | `copy`   | COPY(src,dst) |
| 8         | `dec`    | DEC(v) |
| 13        | `inc`    | INC(v) |
| 20        | `move`   | SYS.MOVE(src,dst,len) |
| 21        | `new`    | NEW(ptr) |
| 24        | `put`    | SYS.PUT(adr,val) |
| 11        | `get`    | SYS.GET(adr,var) |
| 27        | `size`   | SIZE(T) |
| 29        | `val`    | SYS.VAL(T, x) — type reinterpretation |

### 3.2 OberonUlmProcedures (`OUlm`)

| `stdproc` | Name       | Description |
|-----------|------------|-------------|
| 0         | `crspawn`  | SYS.CRSPAWN(cr, p, stacksz) — create coroutine |
| 1         | `crswitch` | SYS.CRSWITCH(cr) — switch to coroutine |
| 2         | `halt`     | HALT(code) — exit process |
| 3         | `tas`      | SYS.TAS(x) — test-and-set |

---

## 4. Code Generation Modules

### 4.1 Module Hierarchy

```
AMD64ObCodeGen          — top-level: GenModule, GenBody, GenStmt, GenExpr,
                          GenAssignment, GenDesignator, GenCall, GenBool,
                          GenGuard, GenValue, GenVar, ...
  ↓ imports
AMD64LinuxOberonBuiltIns — GenBuiltIn: platform-specific SYSTEM procedures
                           (SYS.VAL, SYS.ADR, SYS.CRSWITCH, HALT, ...)
  ↓
AMD64Emit               — Instr0/Instr1/Instr2/Instr3, Jump, Call, JumpCC,
                          InstrMode (validates operands), instruction encoding
  ↓
AMD64OpCodeGenerator    — byte-level instruction encoding → FragmentedStream
  ↓
AMD64Instructions       — mnemonic constants (MOV=160, ADD=6, JMP=122, ...)
AMD64Operands           — Operand type, Op.Error, Op.RegOp, Op.MemOp1, ...
```

### 4.2 `PC.Context` — Procedure Compilation State

```
Context:
  s        : FragmentedStream   — output byte stream
  rodata   : Emit.StrTable      — read-only data (strings)
  module   : Sym.Ident          — current module being compiled
  ident    : Sym.Ident          — current procedure identifier
  errors   : RelatedEvents.Object
  stack    : StackAlloc.Stack   — local variable stack frame
  regs     : Regs.RegSet        — register allocator
  fpuregs  : AMD64FPUReg.RegSet — x87 FPU register stack
  level    : INTEGER            — nesting level (module body=2, proc=3+)
```

### 4.3 Operand Types (`AMD64Operands`)

```
Op.Operand:
  loc    — one of: immediate(1), immediateDyn(2), register(3),
                   register2(4), memory(5), fpuRegister(6),
                   condition(7), error(31)
  reg1   — primary register (Regs.Value)
  reg2   — secondary register (memory index, or second reg)
  memsz  — memory access size in bytes (1/2/4/8)
  immsz  — immediate/relocation size in bytes
  disp   — displacement for memory operands
  dispsz — displacement field size (0=no disp, 1/4=byte/dword)
  data   — for immediate: ConstantData (int/real/set/char/bool/nil)
  reloc  — relocation request (for labels/symbols)
  scale  — SIB scale factor for reg2 (1/2/4/8)
```

Key constructors:
- `Op.RegOp(reg, size)` — register operand of `size` bytes
- `Op.MemOp1(reg, memsz, disp, dispsz)` — `[reg + disp]`
- `Op.MemOp2(reg1,reg2, memsz, disp, dispsz, scale)` — `[reg1 + reg2*scale + disp]`
- `Op.ImmInt(i)` — 32-bit integer immediate
- `Op.ImmNil()` — nil pointer immediate (8 bytes on AMD64)
- `Op.Error()` / `Op.IsError(op)` — sentinel for failed expression eval

### 4.4 Register Names (`AMD64OpCodeGenerator`)

| Name    | # | x86-64 reg | Notes |
|---------|---|------------|-------|
| `genax` | 0 | rax/eax/ax/al | return value, dividend |
| `gencx` | 1 | rcx/ecx | shift count |
| `gendx` | 2 | rdx/edx | high word of mul/div |
| `genbx` | 3 | rbx/ebx | callee-saved |
| `gensp` | 4 | rsp | stack pointer (never allocated) |
| `genbp` | 5 | rbp | frame pointer (never allocated) |
| `gensi` | 6 | rsi | string src, args |
| `gendi` | 7 | rdi | string dst, arg0 (Linux syscall) |
| `genr8`–`genr15` | 8–15 | r8–r15 | caller-saved |

`Gen.StdRegs = {ax,bx,cx,dx,si,di,r8..r15}` — all allocatable registers.

### 4.5 Coroutine Record Layout (AMD64)

```c
struct CoroutineRec {
    int32_t interrupts;   // offset  0, 4 bytes
    int32_t started;      // offset  4, 4 bytes  (crstarted=4)
    uint64_t rbp;         // offset  8, 8 bytes  (crbaseoffset=8)
    uint64_t rsp;         // offset 16, 8 bytes  (crtopoffset=16)
    uint64_t rip;         // offset 24, 8 bytes  (creipoffset=24)
};                        // total: 32 bytes     (crrecordlen=32)
```

---

## 5. Key Code Generation Procedures

### `GenExpr(proc, at, byvalue, possible, own) : Op.Operand`

Evaluates expression `at`, returns result operand.
- `byvalue=TRUE` → load into register (not address of variable)
- `possible` → register set hint
- `own` → register ownership for cleanup
- Returns `Op.Error()` on failure; callers must check `Op.IsError()`

Dispatch by `at.mode`:
| Mode | Handler |
|------|---------|
| `varAt(3)` | `GenVar` → load/address of variable |
| `procAt(4)` | procedure address immediate |
| `callAt(5)` | `GenCall` (non-builtin) or `GenBuiltIn` |
| `refAt(6)` | pointer dereference |
| `selectAt(7)` | record field select |
| `indexAt(8)` | array index |
| `guardAt(9)` | `GenGuard` |
| `unaryAt(10)` | unary ops (NEG, NOT, ABS, ...) |
| `binaryAt(11)` | arithmetic/comparison |
| `constvalAt(12)` | `ImmOpConst` → immediate operand |

### `GenAssignment(proc, lop, rightop)`

Assigns `rightop` to `lop` (left-hand side descriptor).
Dispatches on `lop.type.form`:
- `integer/cardinal/address/boolean/char/byte/set` → `MOV r, src`
- `real` → FPU store
- `pointer/proceduretype/coroutine` → 8-byte pointer move (AMD64)
- `record/array` → struct copy via `MOVS` loop

### `GenBuiltIn(proc, at, possible, caller) : Op.Operand`

Handles all `SYSTEM` and built-in procedures.
Dispatches on `at.proc.type.builtinproc` type:
- `UnixOberonProcedures.StdProcedure` → Unix system calls (read, write, mmap, ...)
- `OberonStdProcedures.StdProcedure` → standard builtins (ABS, ADR, VAL, NEW, ...)
- `OberonUlmProcedures.StdProcedure` → ULM extensions (CRSPAWN, CRSWITCH, HALT, TAS)

### `GenStmt(proc, stmt, exitlab)`

Statement dispatch:
- `ifAt(13)` → `GenBool` + body traversal
- `whileAt(16)` → loop with `GenBool` condition
- `callAt(5)` → `GenBuiltIn` or `GenCall` (result must be NIL)
- `binaryAt(11)` with `opsy=becomes(53)` → `GenAssignment`

### `GenBool(proc, at, context)`

Evaluates boolean expressions for branch/set.
`BoolContext` controls where to jump (`truelab`/`falselab`) and
whether to store result to a target operand.

---

## 6. SYS.VAL — Type Reinterpretation

`SYS.VAL(T, x)` reinterprets the bit pattern of `x` as type `T`.

**Handler in AMD64LinuxOberonBuiltIns, `val` case (OStd.29):**

```
typ  = target type T   (size = GetSize(T))
typ2 = source type of x (size2 = GetSize(x))
param = AST node for x
```

Case tree (simplified):
1. `typ.form IN Sym.numeric + {set}` AND `typ2.form IN numeric + {set}`
   AND sizes equal → trivial reinterpret (chown/memsz change)
2. `(typ.form IN {pointer, proceduretype, coroutine})` AND `Op.Loc=register`
   → 8-byte pointer reinterpret — set `op.memsz := 8`, chown, RETURN
3. `typ.form = real` → load to FPU register
4. `ELSE` (source NOT in numeric): `ASSERT(GetSize(typ2) >= size)`;
   then if `typ.form IN numeric`:
   - XOR reg,reg to zero-extend
   - `op.memsz := size` to truncate source if larger
   - `MOV reg_size, op`
   This handles e.g. `SYS.VAL(INTEGER, coroutineVar)` (8→4 byte truncation)

---

## 7. Known AMD64 vs i386 Differences Requiring Fixups

| Issue | i386 | AMD64 | Where fixed |
|-------|------|-------|-------------|
| Pointer size | 4 | 8 | `Oberon64iSymbols.GetSize` |
| Coroutine size | 16 | 32 | `AMD64LinuxOberonBuiltIns` constants |
| Stack frame | ebp-based | rbp-based, 8-byte slots | `AMD64OberonContexts` |
| Return address | 4 bytes above ebp | 8 bytes above rbp | `GenStmt returnAt` offset |
| Tag pointers | `RegOp(reg, 4)` | should be `RegOp(reg, 8)` | `GenGuard` (pending fix) |
| SYS.VAL ptr→ptr | same size (trivial) | 8-byte register reinterpret | AMD64LinuxOberonBuiltIns |
| SYS.VAL int←coroutine | same size=4 | size mismatch 8≠4 | AMD64LinuxOberonBuiltIns (`>= size`) |

---

## 8. Debug Trace Points (temporary, in current source)

Added to diagnose AMD64 backend crashes. Remove when stable.

| Print | File | Meaning |
|-------|------|---------|
| `GE0..GE3` | AMD64ObCodeGen:GenExpr | entry checkpoints |
| `GE-BAT opsy=X type.form=Y` | AMD64ObCodeGen:GenExpr binaryAt | which binary op |
| `GA0 ltype=... rop.mode=...` | AMD64ObCodeGen:GenAssignment | assignment entry |
| `GB0..GB15` | AMD64ObCodeGen:GenBody | body generation steps |
| `GENSTMT mode=X` | AMD64ObCodeGen:GenBody | statement loop (prints before GenStmt call) |
| `CALLAT proc=...` | AMD64ObCodeGen:GenStmt | call statement dispatch |
| `GB0 builtinproc=OStd.N` | AMD64LinuxOberonBuiltIns:GenBuiltIn | which builtin |
| `VAL: typ.form=X size=Y typ2.form=Z` | AMD64LinuxOberonBuiltIns | SYS.VAL entry |
| `InstrMode: error op at i=X mnem=Y` | AMD64Emit:InstrMode | error operand passed to emitter |
| `ANA:` / `PS` / `F64` / `FOLD64` / `BO` / `FPC` | AMD64OberonAnalyzer | analysis phase traces |

Mnemonic numbers: `MOV=160, ADD=6, XOR=283, JMP=122, CALL=40`.
