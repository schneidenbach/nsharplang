namespace NSharpLang.ColumnarEmitFacts.Tests

import Demo
import System
import System.Reflection.Emit


// THE FOUR REMAINING `ColumnarCompiler.TryEmitProgram` CASES, ON THE SAME ROUTE THE FILE BESIDE
// THIS ONE ESTABLISHED IN 020 SLICE 11.
//
// These replace the four `[Fact]`s that drove the internal emit-only wrapper by reflection:
//   tests/ColumnarDeclarationScanTests.cs  ColumnarCompiler_AcceptsTopLevelTypeAliasBeforeFunction
//   tests/ColumnarDeclarationScanTests.cs  ColumnarCompiler_AcceptsExpressionBodiedFunctionsBeforeFunction
//   tests/ColumnarLiteralFactsTests.cs     ColumnarCompiler_CharLiteralEscape_UsesNSharpDecoder
//   tests/ColumnarLiteralFactsTests.cs     ColumnarCompiler_PackageHeader_AllowsPublicTopLevelFunction
//
// Each of the four built a source STRING, handed it to `ColumnarCompiler.TryEmitProgram`, loaded the
// returned bytes into a collectible context, found one method by reflection and invoked it. Here the
// same source shapes are written DIRECTLY and called, because `nlc test` compiles a `tests/native`
// project through `ColumnarProgramInputBuilder` + `ColumnarIlEmitter` — the same two components the
// 25-line wrapper calls, plus the analyser the wrapper skips. The route's three strengths are stated
// in full in `ColumnarEmitFacts.tests.nl`'s header and are not repeated here.
//
// WHAT THE DELETED FOUR ACTUALLY CLAIMED, AND WHAT IS STRICTLY STRONGER HERE. Every one of them
// asserted a single `Assert.True(TryEmitProgram(...))` plus one invocation of one method. The
// declaration-scan pair existed to prove that a PREAMBLE DECLARATION does not stop the declaration
// scan from reaching what follows it — so each contract below calls the function AFTER the preamble
// AND the preamble's own subject where it has one, and the expression-bodied case exercises the
// branch the deleted file only entered once. The char-literal case crosses every escape the decoder
// admits rather than the one the C# sampled. The package-header case additionally proves the
// function is reachable ACROSS files, which reflection over a single emitted type could not see.

// ---- A top-level type alias, ahead of the function the scan must still find --------------------

type TaskId = int

func AliasedValue(): int {
    return 42
}

// The alias is USED, not merely declared: a scan that dropped it would leave this signature
// unresolvable and the project would not build. It is used in the only position that works —
// see the wall recorded directly below.
func RoundTripTaskId(id: TaskId): TaskId {
    return id
}

// A `type X = Y` ALIAS IS NOT TRANSPARENT TO ARITHMETIC, and this is the wall this contract met.
// `func DoubleTaskId(id: TaskId): int { return id * 2 }` reports
// `NL202: The '*' operator doesn't work with 'NSharpLang.Compiler.AliasTypeInfo' and 'int'` at the
// operator — the alias reaches the binary planner as an `AliasTypeInfo` rather than as its
// underlying `int`. The deleted C# could not have seen this: its alias was declared and never used.
// The alias is therefore exercised in the round-trip position, which is the strongest use the
// current toolset admits.

test "a top level type alias does not stop the declaration scan reaching the functions after it" {
    assert AliasedValue() == 42
    assert RoundTripTaskId(21) == 21
    assert RoundTripTaskId(0) == 0
}

// ---- Expression-bodied functions, ahead of a block-bodied one ----------------------------------

func ExprValue(): int => 42
func ExprLabel(): string => "value"

func ExprMain(): int {
    if ExprLabel() == "value" {
        return ExprValue()
    }

    return 0
}

// The C# invoked `Main` alone, so the `return 0` arm was never emitted-and-run. This one takes both.
func ExprMainWithLabel(label: string): int {
    if label == "value" {
        return ExprValue()
    }

    return 0
}

test "expression bodied functions emit as preambles and both arms of the caller run" {
    assert ExprValue() == 42
    assert ExprLabel() == "value"
    assert ExprMain() == 42
    assert ExprMainWithLabel("value") == 42
    assert ExprMainWithLabel("other") == 0
}

// ---- Char literal escapes on the emit path -----------------------------------------------------

func NewlineChar(): char {
    return '\n'
}

func TabChar(): char {
    return '\t'
}

func ReturnChar(): char {
    return '\r'
}

func NullChar(): char {
    return '\0'
}

func BackslashChar(): char {
    return '\\'
}

func QuoteChar(): char {
    return '\''
}

func DoubleQuoteChar(): char {
    return '"'
}

func AlertChar(): char {
    return '\a'
}

func BackspaceChar(): char {
    return '\b'
}

func FormFeedChar(): char {
    return '\f'
}

func VerticalTabChar(): char {
    return '\v'
}

test "every char literal escape the decoder admits emits its own code point" {
    // The deleted C# sampled exactly one of these eleven.
    assert (int)NullChar() == 0
    assert (int)AlertChar() == 7
    assert (int)BackspaceChar() == 8
    assert (int)TabChar() == 9
    assert (int)NewlineChar() == 10
    assert (int)VerticalTabChar() == 11
    assert (int)FormFeedChar() == 12
    assert (int)ReturnChar() == 13
    assert (int)DoubleQuoteChar() == 34
    assert (int)QuoteChar() == 39
    assert (int)BackslashChar() == 92
}

// ---- A package header with a public top-level function -----------------------------------------

// A PACKAGE NAME IS NOT A CALL QUALIFIER. `Demo.buildExplicit()` reports
// `NL301: I cannot find a 'Demo' variable` — the package is reached by `import Demo` at the top of
// this file and the function is then called unqualified, exactly as an imported namespace member is.
// Recorded here because the qualified form is the shape a reader would reach for first.

test "a package header admits a public top level function and it is callable across files" {
    assert buildExplicit() == "explicit"
    assert buildExplicit().Length == 8
}

// ---- 015-B3: the ordinary-body driver, in the only place it can be proved ------------------------

// STATEMENT KIND 20 GETS ITS FIRST NON-SYNTHESIZED CONSUMER, AND THIS IS WHAT THAT MEANS IN SOURCE.
// Each body below is a BLOCK whose single statement returns a LITERAL whose natural type IS the
// declared return type — one of the shapes `ColumnarMethodBodyPlanner.TryPlanBody` claims. A claimed
// body does not reach the host's kind-20 arm at all: the plan-row IR emits every byte of it through
// `ColumnarCodePlanExecutor`, ending in the `ret` row.
//
// THE ESTATE CANNOT PROVE THIS AND SAYS SO. Its blocks drive the planner directly over a hand-built
// node table, which shows the plan is right but not that the COMPILER routes real syntax into it.
// These are ordinary N# compiled by the real pipeline, so a driver that produced a wrong row, a wrong
// value or a missing `ret` would not merely fail an assertion — the project would not run.

func DriverInt(): int {
    return 42
}

func DriverLong(): long {
    return 42L
}

func DriverULong(): ulong {
    return 42UL
}

func DriverDouble(): double {
    return 2.5
}

func DriverFloat(): float {
    return 2.5f
}

func DriverChar(): char {
    return 'Z'
}

func DriverString(): string {
    return "claimed"
}

func DriverDecimal(): decimal {
    return 2.5m
}

// THE DECLINE SIDE, AS SOURCE. These are bodies the driver deliberately does NOT claim, and every one
// of them must still run — a decline that broke the host's path would be worse than no driver at all.
// An unsuffixed integer on a non-`int` function goes through the host's target-typed ADOPTION
// pre-pass, which emits different rows than the literal owner would, which is exactly why the claim
// rule is type EQUALITY. (`015-B3` also listed `return true` here; `015-B4` claims it, so it moved.)

func DriverAdoptedShort(): short {
    return 42
}

func DriverAdoptedLong(): long {
    return 42
}

func DriverTwoStatements(): int {
    n := 40
    return n + 2
}

test "the ordinary body driver claims a literal return in every literal family it owns" {
    assert DriverInt() == 42
    assert DriverLong() == 42L
    assert DriverULong() == 42UL
    assert DriverDouble() == 2.5
    assert DriverFloat() == 2.5f
    assert (int)DriverChar() == 90
    assert DriverString() == "claimed"
    assert DriverDecimal() == 2.5m
}

test "the bodies the ordinary body driver declines still run on the host path" {
    assert DriverAdoptedShort() == 42
    assert DriverAdoptedLong() == 42L
    assert DriverTwoStatements() == 42
}


// ---- 015-B4: the driver's three new claim classes, in real source -------------------------------

// A BOOL literal is kind 4 and belongs to the boolean owner, which is a schema-v1 producer — so
// claiming it needed that owner to learn a method-body append, not merely a widened gate.

func DriverBoolTrue(): bool {
    return true
}

func DriverBoolFalse(): bool {
    return false
}

// A PARAMETER read. THE ORDINAL RANGE IS THE POINT: `015-B3`'s brief warned that ordinals >= 4 might
// diverge because the host's `EmitLoadArgument` narrows to `ldarg.s` while the executor keeps the long
// `ldarg`. It does not, because an ordinary parameter READ never reaches `EmitLoadArgument` — the
// production expression path routes every bare identifier through `ColumnarBoundIdentifierPlanner` and
// the same `ColumnarCodePlanExecutor.EmitArgument`. `DriverParam5` is the shape that would have broken
// if that decode were wrong, so it is compiled and RUN rather than reasoned about.

func DriverParam0(a: int): int {
    return a
}

func DriverParam1(_a: int, b: string): string {
    return b
}

func DriverParam5(_a: int, _b: int, _c: int, _d: int, _e: int, f: string): string {
    return f
}

class DriverInstance {
    Seed: int

    constructor(seed: int) {
        Seed = seed
    }

    // An INSTANCE method: arg 0 is `this`, so this parameter is ordinal 1.
    func Echo(value: int): int {
        return value
    }

    // The VOID arity on an instance member, both shapes.
    func Idle() {
    }

    func IdleBare() {
        return
    }
}

// An EXPLICIT constructor with an EMPTY body: `EmitBody`'s literal `isVoid: true` call site, reached
// after the caller has already emitted the base chain and the field initializers, so a claimed body
// must append its `ret` after them and nothing else.
class DriverEmptyCtor {
    Tag: int = 7

    constructor() {
    }
}

func DriverVoidEmpty() {
}

func DriverVoidBare() {
    return
}

// THE NULLABLE GUARD, AS SOURCE. Equality holds — the parameter and the return type are the same
// `int?` — and the driver still declines, because `IsSupportedNullable` is the one host pre-pass gated
// on the RETURN TYPE and it owns the whole return when it fires.
func DriverNullablePassthrough(v: int?): int? {
    return v
}


// ---- 015-B5: the three identifier classes the expression door adds, in real source --------------
//
// `015-B4` recorded `DriverFielded.Read` here as a DECLINE — "a CurrentField read is a different
// selection kind and stays with the host". `015-B5` CLAIMS it, so the comment is corrected rather
// than deleted: this is the same source, the same bytes, and a different owner writing them.

// A bare instance-FIELD read. This is the shape the buildable corpus actually contains — the
// issue-tracker store's `func GetAll(): List<Issue> { return issues }` is exactly it.
class DriverFielded {
    Count: int

    constructor(count: int) {
        Count = count
    }

    func Read(): int {
        return Count
    }
}

// A bare instance-PROPERTY read. Not the same class as the field: the rows are a receiver plus a
// getter CALL, so it is claimed and proved separately.
class DriverPropertied {
    Count: int

    constructor(count: int) {
        Count = count
    }

    Doubled: int => Count * 2

    func Read(): int {
        return Doubled
    }
}

// A VALUE-TYPE receiver takes the same two classes down the other half of the row decision: the
// argument slot is an address and a property getter is a non-virtual `call`.
struct DriverValueFielded {
    Count: int

    constructor(count: int) {
        Count = count
    }

    Doubled: int => Count * 2

    func ReadField(): int {
        return Count
    }

    func ReadProperty(): int {
        return Doubled
    }
}

// A ref/out parameter READ — `ldarg` plus one typed `ldind`, two rows where a plain parameter has
// one. The write below is the host's; only the bare `return v` body is claimed.
func DriverRefRead(ref v: int): int {
    return v
}

func DriverRefBump(ref v: int) {
    v = v + 1
}

// THE OUT-OF-TABLE BY-REF ELEMENT IS PINNED IN THE ESTATE RATHER THAN HERE, AND THE REASON IS A
// SEPARATE, PRE-EXISTING EMITTER GAP. `func f(ref v: decimal): decimal { return v }` DECLARES fine, but
// any CALL that passes a `ref decimal` argument fails columnar emission outright — measured on the
// `b440f294f` baseline CLI as well as on this tree, so it is not this slice's doing and not this
// slice's to fix. The decline it would have proved (`decimal` has no `ldind` form, so the selection
// never resolves) is asserted directly at the planner in `ColumnarMethodBodyFacts.tests.nl`.

test "the ordinary body driver claims a boolean return in both directions" {
    assert DriverBoolTrue()
    assert !DriverBoolFalse()
}

test "the ordinary body driver claims a parameter return at ordinals inside and outside the narrowed range" {
    assert DriverParam0(19) == 19
    assert DriverParam1(1, "two") == "two"
    assert DriverParam5(1, 2, 3, 4, 5, "six") == "six"
    instance := new DriverInstance(3)
    assert instance.Echo(11) == 11
}

test "the ordinary body driver claims both void shapes on free functions members and constructors" {
    DriverVoidEmpty()
    DriverVoidBare()
    instance := new DriverInstance(3)
    instance.Idle()
    instance.IdleBare()
    assert instance.Seed == 3
    empty := new DriverEmptyCtor()
    assert empty.Tag == 7
}

test "the identifier bodies the driver refuses still run on the host path" {
    passthrough := DriverNullablePassthrough(5)
    assert passthrough != null
    unwrapped := must passthrough
    assert unwrapped == 5
}

test "the expression door claims a current field and a current property on both receiver kinds" {
    fielded := new DriverFielded(23)
    assert fielded.Read() == 23
    propertied := new DriverPropertied(23)
    assert propertied.Read() == 46
    valued := new DriverValueFielded(9)
    assert valued.ReadField() == 9
    assert valued.ReadProperty() == 18
}

test "the expression door claims a by-ref parameter read and derefs it" {
    v := 63
    assert DriverRefRead(ref v) == 63
    DriverRefBump(ref v)
    assert DriverRefRead(ref v) == 64
}


// ---- 015-B6: the two composite classes, and the statement loop, in real source -------------------
//
// The nine owner gates that THREW on a method-body plan are open, and these are the bodies that prove
// it in compiled source rather than in a hand-built node table. `~3` is a true COMPOSITE: its owner
// opens a nested operand fragment inside the door's root fragment and recurses into the scalar-literal
// owner. The declaration bodies below are the first ones whose RETURN reads a name the DRIVER created.
//
// ⚠ `func DriverNegative(): int { return -5 }` IS DELIBERATELY ABSENT, AND ITS ABSENCE IS THE FINDING.
// The host's kind-20 arm ADOPTS a unary minus over an unsuffixed integer literal and emits the value
// PRE-NEGATED — `ldc.i4.s -5`, with no `neg` row — on every signed target including `int`. `015-B5`
// recorded those pre-passes as provably unreached under type equality; that holds for the POSITIVE
// adoption arm and fails for the negative one, and a corpus byte diff is what found it. The door
// refuses that one shape in RETURN position and claims it as an INITIALIZER, which is exactly what
// `DriverDeclaredNegative` below is.

func DriverBitNot(): int {
    return ~3
}

func DriverNotTrue(): bool {
    return !true
}

func DriverNegFloat(): double {
    return -2.5
}

func DriverNameOf(count: int): string {
    return nameof(count)
}

func DriverDeclared(): int {
    x := 11
    return x
}

func DriverDeclaredChain(): int {
    a := 13
    b := a
    return b
}

func DriverDeclaredNegative(): int {
    n := -17
    return n
}

func DriverDeclaredFromParameter(p: int): int {
    q := p
    return q
}

// TWO composite statements in one body — two ROOT fragments on one method-body plan, which the
// single-root rule refused outright before this slice.
func DriverTwoComposites(): int {
    n := -19
    return ~21
}

class DriverDeclaringMember {
    Count: int

    constructor(count: int) {
        Count = count
    }

    func ReadDeclared(): int {
        z := Count
        return z
    }
}

test "the expression door claims both composite classes in real source" {
    assert DriverBitNot() == -4
    assert !DriverNotTrue()
    assert DriverNegFloat() == -2.5
    assert DriverNameOf(0) == "count"
}

test "the statement loop claims a declaration and the return that reads it in real source" {
    assert DriverDeclared() == 11
    assert DriverDeclaredChain() == 13
    assert DriverDeclaredNegative() == -17
    assert DriverDeclaredFromParameter(51) == 51
    assert DriverTwoComposites() == -22
    member := new DriverDeclaringMember(29)
    assert member.ReadDeclared() == 29
}


// ---- 015-B7: the direct-call composite in real source ---------------------------------------------
//
// The first claimed kind whose owner consults the three binding facts the driver now routes. Every
// body below reaches `ColumnarDirectCallPlanner.TryAppendRoot` — the SAME root sequence that owner's
// own `Plan` calls, which the emitter reaches for every call root through
// `ColumnarRangeIndexPlanner.TryEmitFromFacts`'s second cascade arm. Two positions, because `015-B6`
// proved the return position is not the value position: a call as a RETURN VALUE and a call as a `:=`
// INITIALIZER are separate claim classes with separate corpus diffs.
//
// `DriverCallee` is a top-level sibling, so `DriverCallReturn` is exactly the shape an EMPTY
// `SiblingCallables` map would have sent down the delegate-invoke arm instead — the routed fact doing
// real work rather than merely existing.

func DriverCallee(value: int): int {
    return value
}

func DriverCallReturn(): int {
    return DriverCallee(7)
}

func DriverCallDeclared(): int {
    n := DriverCallee(9)
    return n
}

func DriverCallDeclaredThenCallReturn(): int {
    n := DriverCallee(3)
    return DriverCallee(n)
}

class DriverCallHolder {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Read(): int {
        return Value
    }

    // A BARE INSTANCE call — the current-instance tier rather than the sibling one.
    func ReadViaCall(): int {
        return Read()
    }
}

test "the expression door claims a direct call in both positions in real source" {
    assert DriverCallReturn() == 7
    assert DriverCallDeclared() == 9
    assert DriverCallDeclaredThenCallReturn() == 3
    holder := new DriverCallHolder(37)
    assert holder.ReadViaCall() == 37
}


// ---- 015-B8: a plan local read INSIDE a claimed call ----------------------------------------------
//
// `015-B7` declined every one of these bodies WHOLE, and it had to: the direct-call owner types each
// argument and receiver by planning it into a fresh scratch plan whose local pool was empty, so
// `ldloc <the body's pool index>` named an index that did not exist and threw straight out of the
// compiler. `015-B8` gives the scratch the body's local VOCABULARY — mirror slots it can name and type
// but never stores or replays — and the whole class becomes claimable.
//
// The bodies below are the two POSITIONS the class splits into, measured rather than assumed: a plan
// local inside an ARGUMENT subtree (four spellings of it) and a plan local as the call's RECEIVER. A
// two-marker liveness mutation moves exactly these and no others.

func DriverMirrorTake(value: int): int {
    return value + 1
}

// ARGUMENT — the exact shape the `015-B7` claim-class corpus crashed the compiler on.
func DriverMirrorArgument(): int {
    n := DriverCallee(3)
    return DriverMirrorTake(n)
}

// ARGUMENT, TWO LOCALS — only the second is read inside the call, so the scratch carries a slot it
// never references. That is the pool's all-used rule meeting a mirror, in real source.
func DriverMirrorSecondOfTwo(): int {
    _first := DriverCallee(1)
    second := DriverCallee(5)
    return DriverMirrorTake(second)
}

// ARGUMENT, EXTERNAL STATIC callee rather than a sibling.
func DriverMirrorExternalStatic(): int {
    n := DriverCallee(-8)
    return Math.Abs(n)
}

// ARGUMENT, NESTED — the local is read one call deeper than the claimed root.
func DriverMirrorNested(): int {
    n := DriverCallee(3)
    return DriverMirrorTake(DriverMirrorTake(n))
}

// ARGUMENT, a MEMBER ACCESS over the plan local rather than a bare read.
func DriverMirrorMemberOfLocal(): int {
    text := DriverMirrorText()
    return DriverMirrorTake(text.Length)
}

func DriverMirrorText(): string {
    return "abcd"
}

class DriverMirrorHolder {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Take(value: int): int {
        return value + Value
    }
}

func DriverMirrorMakeHolder(): DriverMirrorHolder {
    return new DriverMirrorHolder(2)
}

// RECEIVER — the plan local is the instance the call is made ON, which is a different door position
// from every argument above and gets its own marker in the liveness mutation.
func DriverMirrorReceiver(): int {
    holder := DriverMirrorMakeHolder()
    return holder.Take(4)
}

test "the expression door claims a call whose subtree reads a plan local" {
    assert DriverMirrorArgument() == 4
    assert DriverMirrorSecondOfTwo() == 6
    assert DriverMirrorExternalStatic() == 8
    assert DriverMirrorNested() == 5
    assert DriverMirrorMemberOfLocal() == 5
    assert DriverMirrorReceiver() == 6
}


// ---- 015-B9 — THE BINARY COMPOSITE, AND THE TWO ARGUMENT SHAPES THE CALL OWNER NOW ADMITS ----
//
// Three claims in real source, and they are three DIFFERENT decisions:
//
//   1. the DOOR claims kind 12, entering `ColumnarPrimitiveBinaryPlanner`'s own root sequence — the
//      third owner reached that way, and the first live consumer of the routed overflow flag;
//   2. the CALL owner admits a primitive binary as an ARGUMENT, which every one of its eight argument
//      sites refused with a hard-coded `false` while the construction owner passed `true`;
//   3. the CALL owner's type-discovery scratch stops describing an argument as a plan ROOT, which is
//      what refused an ordinary `arr[0]` at the type step while the append step admitted it.
//
// The last two bodies are `015-B8`'s `P5` and `P9` verbatim — the two shapes that slice measured as
// crashing under its probe and still declining with its fix.

func DriverBinaryAdd(left: int, right: int): int {
    return left + right
}

// The binary's LEFT operand is a plan local, so the statement loop and the composite meet.
func DriverBinaryOverLocal(): int {
    n := DriverCallee(3)
    return n * 2
}

// String concatenation is one of the owner's named families, and its result type is what the door then
// matches against the return type.
func DriverBinaryConcat(text: string): string {
    return text + "!"
}

// ARGUMENT — `015-B8`'s `P8`, the one probe shape that did not even crash under its mutation because
// the call declined before any scratch opened.
func DriverBinaryArgument(): int {
    n := DriverCallee(3)
    return DriverMirrorTake(n + 1)
}

// DECLINED, and correct anyway: mixed-width operands are outside the owner's exact numeric surface, so
// the host emits this body exactly as it always did.
func DriverBinaryMixed(left: int, right: long): long {
    return left + right
}

// ⚠ `015-B12` MOVED THIS BODY'S OWNER, AND THE COMMENT THAT STOOD HERE IS THE REASON IT COULD.
// It read "DECLINED for a different reason: `&&` is the CONDITIONAL owner's root, never this one's",
// and both halves were true — but the conclusion stopped one step short. `&&` IS the conditional
// owner's root, and `015-B12` gave the door an arm that enters that owner, so this body is CLAIMED
// now. Its bytes did not move (the corpus diff says so); only its owner did.
func DriverShortCircuit(left: bool, right: bool): bool {
    return left && right
}

func DriverIndexMakeArray(): int[] {
    return [3, 4, 5]
}

// ARGUMENT — `015-B8`'s `P5`: an ordinary int index over a plan local.
func DriverIndexArgument(): int {
    values := DriverIndexMakeArray()
    return DriverMirrorTake(values[0])
}

// ARGUMENT — `015-B8`'s `P9`: the selector is itself a binary over a member access on a second local.
func DriverIndexSelectorArgument(): int {
    values := DriverIndexMakeArray()
    text := DriverMirrorText()
    return DriverMirrorTake(values[text.Length - 4])
}

test "the expression door claims the binary composite and the arguments a call now admits" {
    assert DriverBinaryAdd(2, 3) == 5
    assert DriverBinaryOverLocal() == 6
    assert DriverBinaryConcat("a") == "a!"
    assert DriverBinaryArgument() == 5
    assert DriverBinaryMixed(2, 3) == 5
    assert !DriverShortCircuit(true, false)
    assert DriverShortCircuit(true, true)
    assert DriverIndexArgument() == 4
    assert DriverIndexSelectorArgument() == 4
}


// ---- THE INDEX/RANGE OWNER'S INHERITED VALUE SURFACE, AND THE CONSTRUCTION SCRATCH'S FRAME (015-B10) ----
//
// `015-B9` widened the direct-call owner's ARGUMENT surface and left the index/range owner's own six
// inner appends on the plain one, so `DriverIndexSelectorArgument` above still declined. All five inner
// appends now inherit the surface of the position the whole expression occupies, and the construction
// owner's ADMISSION scratch declares the frame its APPEND sites already pass.
//
// ⚠ TWO OF THESE BODIES DID NOT COMPILE AT ALL AT `6252626c7` — `DriverIndexFromEndSelector` and
// `DriverRangeEndpointSelector` both failed the whole build with `NL103`, because the LEGACY host cannot
// emit a composite inside `^` or inside a range endpoint either. They are a CAPABILITY GAIN rather than
// a parity move, which is why they are executed here for their values and not merely planned.

func DriverTakeChar(value: char): int {
    return (int)value
}

func DriverTakeText(text: string): int {
    return text.Length
}

func DriverSumArray(items: int[]): int {
    return items.Length
}

// SELECTOR — a binary selector over a parameter receiver, the shape with no plan local in it.
func DriverIndexBinarySelector(values: int[], offset: int): int {
    return DriverMirrorTake(values[offset + 1])
}

// RECEIVER — the INDEXED value is itself a binary (string concatenation), the other half of the
// index-access widening.
func DriverIndexConcatReceiver(text: string): int {
    return DriverTakeChar((text + "x")[0])
}

// CAST OPERAND — the selector is a numeric cast whose operand is a binary.
func DriverIndexCastSelector(values: int[], scale: double): int {
    return DriverMirrorTake(values[(int)(scale + 1.0)])
}

// FROM-END OPERAND — `^(offset + 1)`. DID NOT COMPILE BEFORE THIS SLICE.
func DriverIndexFromEndSelector(values: int[], offset: int): int {
    return DriverMirrorTake(values[^(offset + 1)])
}

// RANGE ENDPOINT — `(offset + 1)..`. DID NOT COMPILE BEFORE THIS SLICE.
func DriverRangeEndpointSelector(text: string, offset: int): int {
    return DriverTakeText(text[(offset + 1)..])
}

// CONSTRUCTION — the admission scratch's frame, at all three of its append sites: a constructor
// argument, an array-literal element and an array length.
func DriverConstructionIndexArgument(values: int[]): int {
    return DriverMirrorTake(new DriverMirrorHolder(values[0]).Value)
}

func DriverConstructionIndexElement(values: int[]): int {
    return DriverSumArray([values[0], 2])
}

func DriverConstructionIndexLength(values: int[]): int {
    return DriverSumArray(new int[values[0]])
}

test "the index owner inherits its value surface and the construction scratch declares its frame" {
    values := DriverIndexMakeArray()

    assert DriverIndexBinarySelector(values, 0) == 5
    assert DriverIndexConcatReceiver("zb") == 122
    assert DriverIndexCastSelector(values, 0.0) == 5
    assert DriverIndexFromEndSelector(values, 1) == 5
    assert DriverRangeEndpointSelector("abcdef", 1) == 4

    assert DriverConstructionIndexArgument(values) == 4
    assert DriverConstructionIndexElement(values) == 2
    assert DriverConstructionIndexLength(values) == 3

    // The owner's own numeric surface still bounds the selector, and the `015-B9` shapes still hold.
    assert DriverIndexArgument() == 4
    assert DriverIndexSelectorArgument() == 4
}

// ---- 015-B11 — THE `Module` NAME (STAGE 1), THE ADOPTED NEGATIVE LITERAL, AND THE INSTANCE-MEMBER
// RECEIVER SURFACE ----
//
// ⚠ THE FIRST TWO FUNCTIONS BELOW ARE THE STAGE-1 PROOF, AND THEY ONLY WORK BECAUSE OF WHERE THIS
// FILE LIVES. `src/NSharpLang.Compiler.BootstrapServices` compiles under the PACKAGED SDK from the
// local feed, so its own `.nl` cannot spell a type the tree has only just admitted; a
// `tests/native` project compiles under the CLI the gate has just BUILT, so it can. That split is
// the whole two-stage boundary: the list widens here, the estate keeps compiling unchanged, and the
// reflective `PropertyInfo.GetValue` detour in `ColumnarTypeEquivalenceFacts.SameDeclaredIdentity`
// deletes in `015-B12` after the coordinator republishes.
//
// ⚠ AND THE WIDENING TOOK TWO ROWS RATHER THAN ONE, WHICH A PROBE PROVED BEFORE THIS FILE ASSERTED
// IT. With only `System.Reflection.Module` on `IsSupportedRuntimeTypeName`, `a.get_Module()` still
// declined at `emit.return.expression` while the neighbouring `a.get_Assembly()` compiled — because
// `System.Type`'s bindable members are an EXPLICIT table in `GetInstanceCallPlan` and `get_Assembly`
// had a row there while `get_Module` did not. Declarable and bindable are two admissions.
func B11ModuleName(a: Type): string {
    m := a.get_Module()
    return m.get_Name()
}

// The exact predicate the detour exists for: two DECLARED identities are one type only when the
// module halves are the same reference.
func B11SameModule(a: Type, b: Type): bool {
    am := a.get_Module()
    bm := b.get_Module()
    return Object.ReferenceEquals(am, bm)
}

// A type from ANOTHER module, resolved by assembly-qualified name because `typeof(Uri)` is not on
// the `typeof` owner's admitted surface. `System.Uri` is type-forwarded out of CoreLib into
// `System.Private.Uri`, which is what makes the pair below a genuine cross-module comparison rather
// than a tautology.
func B11ForeignModuleType(): Type {
    resolved := Type.GetType("System.Uri, System.Private.Uri")
    if resolved == null {
        throw new InvalidOperationException("System.Uri must resolve by assembly-qualified name.")
    }

    return resolved
}

// THE ADOPTED NEGATIVE LITERAL. `-2147483648` is the ONE magnitude the host's return-position
// adoption pre-pass declines (`2147483648 > int.MaxValue`) and the unary owner claims, emitting it
// PRE-NEGATED with no `neg`; `-1L` is the suffix half. `-1` on an `int` function is the control that
// the host still adopts and this door still refuses.
func B11MinimumMagnitude(): int {
    return -2147483648
}

func B11SuffixedNegative(): long {
    return -1L
}

func B11AdoptedNegative(): int {
    return -1
}

struct B11Point {
    X: int

    constructor(x: int) {
        X = x
    }
}

func B11Use(v: int): int {
    return v + 1
}

// THE INSTANCE-MEMBER RECEIVER SURFACE — a member access whose index receiver carries a BINARY
// selector, in an argument position the shared dispatcher already claims.
func B11MemberOverBinarySelector(items: B11Point[], i: int): int {
    return B11Use(items[i + 1].X)
}

func B11MemberOverLiteralSelector(items: B11Point[]): int {
    return B11Use(items[1].X)
}

func B11StringElementMember(names: string[], i: int): int {
    return B11Use(names[i + 1].Length)
}

test "the declaring module binds, the adopted negative literal narrows, and the member receiver inherits its surface" {
    // STAGE 1, EXECUTED. Both halves of the identity read run, and they answer correctly for a pair
    // that shares a module and a pair that does not.
    assert B11ModuleName(typeof(int)) == "System.Private.CoreLib.dll"
    assert B11ModuleName(B11ForeignModuleType()) == "System.Private.Uri.dll"
    assert B11SameModule(typeof(int), typeof(string))
    assert !B11SameModule(typeof(int), B11ForeignModuleType())

    // THE ADOPTED NEGATIVE LITERAL, IN VALUES.
    assert B11MinimumMagnitude() == -2147483648
    assert B11SuffixedNegative() == -1L
    assert B11AdoptedNegative() == -1

    // THE INSTANCE-MEMBER RECEIVER SURFACE.
    points := [new B11Point(10), new B11Point(20), new B11Point(30)]
    assert B11MemberOverBinarySelector(points, 0) == 21
    assert B11MemberOverLiteralSelector(points) == 21

    names := new string[](3)
    names[0] = "a"
    names[1] = "bb"
    names[2] = "ccc"
    assert B11StringElementMember(names, 0) == 3
}


// ---- 015-B12: THE CONDITIONAL OWNER'S TWO DOOR ARMS, AS SOURCE THE REAL PIPELINE COMPILES ---------

// THE FIRST CLAIMED KIND WHOSE ROWS BRANCH. Every body the door claimed before this slice lowers to a
// straight line; a ternary and a short-circuit lower to a BRANCH-MERGE, so these bodies are the first
// to put `DefineLabel`/`Brfalse`/`Br`/`MarkLabel` rows on a schema-v4 METHOD BODY rather than on a
// standalone schema-v3 expression. The estate proves the rows are right; only a real compiled body
// proves the EXECUTOR marks those labels when it walks a method body, and a wrong branch target here
// would not fail an assertion — it would fail IL verification or run the wrong arm.

func DoorTernaryMax(a: int, b: int): int {
    return a > b ? a : b
}

// A ternary with REFERENCE-typed arms, so the arm-agreement rule is exercised off the int path.
func DoorTernaryLabel(flag: bool): string {
    return flag ? "yes" : "no"
}

func DoorShortCircuitAnd(left: bool, right: bool): bool {
    return left && right
}

func DoorShortCircuitOr(left: bool, right: bool): bool {
    return left || right
}

// The short-circuit through the door's OTHER entry: a `:=` INITIALIZER rather than a return. The two
// entries share one dispatcher, and a widening that reached only one would be a silent asymmetry.
func DoorShortCircuitPersisted(left: bool, right: bool): bool {
    outcome := left && right
    return outcome
}

// A ternary whose CONDITION is itself a short-circuit — one owner entered twice, once as a root and
// once as a nested value.
func DoorTernaryOverShortCircuit(a: bool, b: bool, whenTrue: int, whenFalse: int): int {
    return a && b ? whenTrue : whenFalse
}

// ⚠ THE SEMANTIC THE ROWS EXIST TO PRESERVE: `&&` MUST NOT EVALUATE ITS RIGHT OPERAND WHEN THE LEFT IS
// FALSE. A branch-merge that merely computed the right answer while evaluating both operands would
// pass every value assertion above and still be wrong, so the side effect is counted rather than
// assumed.
class DoorEvaluationProbe {
    Calls: int

    constructor() {
        this.Calls = 0
    }

    func Observe(value: bool): bool {
        this.Calls = this.Calls + 1
        return value
    }
}

func DoorAndRightCalls(left: bool): int {
    probe := new DoorEvaluationProbe()
    outcome := left && probe.Observe(true)
    if outcome {
        return probe.Calls + 100
    }

    return probe.Calls
}

func DoorOrRightCalls(left: bool): int {
    probe := new DoorEvaluationProbe()
    outcome := left || probe.Observe(false)
    if outcome {
        return probe.Calls + 100
    }

    return probe.Calls
}

test "the expression door claims the conditional composite and both of its arms run correctly" {
    assert DoorTernaryMax(7, 3) == 7
    assert DoorTernaryMax(3, 7) == 7
    assert DoorTernaryMax(4, 4) == 4

    assert DoorTernaryLabel(true) == "yes"
    assert DoorTernaryLabel(false) == "no"

    // Both operators over the whole truth table — a branch-merge with a swapped opcode would show here.
    assert DoorShortCircuitAnd(true, true)
    assert !DoorShortCircuitAnd(true, false)
    assert !DoorShortCircuitAnd(false, true)
    assert !DoorShortCircuitAnd(false, false)

    assert DoorShortCircuitOr(true, true)
    assert DoorShortCircuitOr(true, false)
    assert DoorShortCircuitOr(false, true)
    assert !DoorShortCircuitOr(false, false)

    assert DoorShortCircuitPersisted(true, true)
    assert !DoorShortCircuitPersisted(false, true)

    assert DoorTernaryOverShortCircuit(true, true, 11, 22) == 11
    assert DoorTernaryOverShortCircuit(true, false, 11, 22) == 22
    assert DoorTernaryOverShortCircuit(false, true, 11, 22) == 22
}

test "the claimed short circuit still refuses to evaluate its right operand" {
    // `false && f()` never calls f: 0 evaluations, and the result was false so no +100.
    assert DoorAndRightCalls(false) == 0
    // `true && f()` calls it once, and f returned true, so the result was true: 1 + 100.
    assert DoorAndRightCalls(true) == 101

    // `true || f()` never calls f, and the result was true: 0 + 100.
    assert DoorOrRightCalls(true) == 100
    // `false || f()` calls it once, and f returned false: 1 evaluation, no bonus.
    assert DoorOrRightCalls(false) == 1
}


// ---- 015-B13: THE CHECKED CONTEXT (class K) — THE CLAIM WHOSE SEMANTICS ARE A THROW ----
//
// Every earlier door claim could be checked by comparing a VALUE. This one cannot: `checked` and
// `unchecked` produce the same value on every input that does not overflow, and differ only in
// whether the CLR raises `OverflowException` on the one that does. So these bodies are driven past
// the boundary on purpose — a claim that emitted `add` where the host emitted `add.ovf` would return
// a wrapped number here instead of throwing, and no value comparison inside the range would notice.
//
// ⚠ THE UNSIGNED ARM (`add.ovf.un`) IS PROVED IN THE ESTATE AND NOT HERE, FOR A PRE-EXISTING REASON
// THAT WAS MEASURED RATHER THAN ASSUMED. A `uint` literal declines columnar emission at this tip on
// BOTH the pre-slice and post-slice CLI — `func UMax(): uint { return 4294967295U }` alone is enough,
// with no `checked` anywhere — so a `uint` body cannot be spelled in this corpus project at all. The
// estate asserts `AddOvfUn` directly against a plan built from `uint` parameter bindings, which needs
// no source literal.

func DoorCheckedAdd(a: int, b: int): int {
    return checked(a + b)
}

func DoorUncheckedAdd(a: int, b: int): int {
    return unchecked(a + b)
}

func DoorCheckedSubtract(a: int, b: int): int {
    return checked(a - b)
}

func DoorCheckedMultiply(a: int, b: int): int {
    return checked(a * b)
}

func DoorCheckedLongMultiply(a: long, b: long): long {
    return checked(a * b)
}

// The INNER keyword wins, and a door arm that only SET the flag without restoring it would answer
// these two the same way.
func DoorCheckedOverUnchecked(a: int, b: int): int {
    return checked(unchecked(a + b))
}

func DoorUncheckedOverChecked(a: int, b: int): int {
    return unchecked(checked(a + b))
}

// The INITIALIZER door, and the leak test in one body: the declaration is checked and the returned
// binary must not inherit that.
func DoorCheckedDeclarationThenPlainAdd(a: int, b: int): int {
    guarded := checked(a * 1)
    return guarded + b
}

func DoorCheckedThrows(a: int, b: int): bool {
    try {
        wrapped := DoorCheckedAdd(a, b)
        return wrapped == 0 && false
    } catch ex: OverflowException {
        return true
    }
}

func DoorCheckedMultiplyThrows(a: int, b: int): bool {
    try {
        wrapped := DoorCheckedMultiply(a, b)
        return wrapped == 0 && false
    } catch ex: OverflowException {
        return true
    }
}

test "the expression door claims the checked context and keeps its overflow semantics" {
    // In range, both directions agree — which is exactly why the boundary cases below are the proof.
    assert DoorCheckedAdd(2, 3) == 5
    assert DoorUncheckedAdd(2, 3) == 5
    assert DoorCheckedSubtract(9, 4) == 5
    assert DoorCheckedMultiply(6, 7) == 42
    assert DoorCheckedLongMultiply(3000000000L, 2L) == 6000000000L

    // OUT of range: the checked bodies THROW and the unchecked one WRAPS. A claim that lost the flag
    // would wrap in all four.
    assert DoorCheckedThrows(2147483647, 1)
    assert DoorCheckedMultiplyThrows(100000, 100000)
    assert DoorUncheckedAdd(2147483647, 1) == -2147483648
}

test "the claimed checked context restores the flag rather than merely setting it" {
    // The INNER keyword governs: the outer one is restored around the inner subtree.
    assert DoorCheckedOverUnchecked(2147483647, 1) == -2147483648

    outerUncheckedThrew := false
    try {
        assert DoorUncheckedOverChecked(2147483647, 1) == 0
    } catch ex: OverflowException {
        outerUncheckedThrew = true
    }

    assert outerUncheckedThrew

    // And a checked INITIALIZER does not leak into the statement after it: the return's `+` wraps.
    assert DoorCheckedDeclarationThenPlainAdd(2147483647, 1) == -2147483648
}


// ---- THE MEMBER-ACCESS ROOT AT THE DOOR (015-B14) ----
//
// Kind 8 is the FIRST claimed kind two cascade arms admit: `ColumnarExternalStaticMemberPlanner` and
// `ColumnarInstanceMemberPlanner` share the same unqualified `kind == MemberAccess` root test, and
// `ColumnarRangeIndexPlanner.TryEmitFromFacts` asks the first at arm SEVEN and the second at arm EIGHT.
// The door asks both, in that order, and claims only the second — so an external-static root stays with
// the host and the bodies below are the instance-member owner's own root sequence.
//
// The receiver classes are exercised one apiece rather than sampled, because each takes a different
// route through `ColumnarInstanceMemberPlanner.TryAppend`: a bound identifier (direct storage), a
// value-typed one that must PRESERVE its address, a by-reference parameter, a plan local the statement
// loop created, an SZ-array `Length` (no member handle at all), a composed index receiver, and a
// composed receiver typed through `TryGetComposedReceiverType` — the function `015-B12` and `015-B13`
// both reported as structurally unreached from a claimed body, and which this slice reaches.

struct DoorMemberPoint {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }
}

class DoorMemberBox {
    Value: int
    Label: string

    constructor(value: int, label: string) {
        Value = value
        Label = label
    }
}

func DoorMemberOfClass(box: DoorMemberBox): int {
    return box.Value
}

func DoorMemberStringOfClass(box: DoorMemberBox): string {
    return box.Label
}

// A VALUE-typed receiver in direct storage: the owner preserves the address rather than spilling.
func DoorMemberOfStruct(point: DoorMemberPoint): int {
    return point.X
}

// The BY-REFERENCE receiver class.
func DoorMemberOfByRefStruct(ref point: DoorMemberPoint): int {
    return point.Y
}

func DoorMemberArrayLength(values: int[]): int {
    return values.Length
}

func DoorMemberStringLength(text: string): int {
    return text.Length
}

// The receiver is a PLAN LOCAL the statement loop created — the tier `015-B6` invented.
func DoorMemberOfPlanLocal(box: DoorMemberBox): int {
    local := box
    return local.Value
}

// A COMPOSED INDEX receiver, which spills the element through `AppendTemporaryAddress` — so this body's
// plan declares a local INSIDE an expression, beside the statement loop's own.
func DoorMemberOfElement(points: DoorMemberPoint[]): int {
    return points[1].X
}

// ⚠ THE `015-B8` PLAN-LOCAL MIRROR, LIVE. The index receiver here is a PLAN LOCAL, so the throwaway
// scratch `TryGetComposedReceiverType` types it in has to know `local`'s slot type. `015-B8` armed that
// mirror and recorded it as inert; this body is what makes it load-bearing.
func DoorMemberOfPlanLocalElement(points: DoorMemberPoint[]): int {
    local := points
    return local[1].Y
}

// A SCALAR-LITERAL receiver — a shape that can only type through the composed side.
func DoorMemberOfLiteral(): int {
    return "abcd".Length
}

// The temporary and the statement loop's own local in ONE body, which is where their pool ORDER matters.
func DoorMemberTemporaryThenLocal(points: DoorMemberPoint[]): int {
    first := points[0].X
    return first + points[1].Y
}

// The INITIALIZER door as well as the return door.
func DoorMemberDeclaration(box: DoorMemberBox): int {
    captured := box.Value
    return captured
}

// Under a `checked` context: kind 57 recurses into the SAME dispatcher, so the new arm is reachable
// through it without a second copy of anything.
func DoorMemberChecked(box: DoorMemberBox): int {
    return checked(box.Value)
}

test "the expression door claims the member-access root through every receiver class" {
    box := new DoorMemberBox(7, "label")
    point := new DoorMemberPoint(3, 4)
    points := [new DoorMemberPoint(10, 20), new DoorMemberPoint(30, 40)]

    assert DoorMemberOfClass(box) == 7
    assert DoorMemberStringOfClass(box) == "label"
    assert DoorMemberOfStruct(point) == 3
    assert DoorMemberOfByRefStruct(ref point) == 4
    assert DoorMemberArrayLength([1, 2, 3]) == 3
    assert DoorMemberStringLength("abcde") == 5
    assert DoorMemberOfPlanLocal(box) == 7
    assert DoorMemberOfElement(points) == 30
    assert DoorMemberOfPlanLocalElement(points) == 40
    assert DoorMemberOfLiteral() == 4
    assert DoorMemberTemporaryThenLocal(points) == 50
    assert DoorMemberDeclaration(box) == 7
    assert DoorMemberChecked(box) == 7
}


// ---- AND THE MEMBER-ACCESS ROOTS THE DOOR DOES **NOT** CLAIM STILL COMPILE (015-B14) ----
//
// Every one of these is a NARROWING rather than a divergence: the door declines and the host emits the
// body exactly as it always did. They are executed for their values because "the door declines" is only
// half a claim — the other half is that nothing regressed behind it.

// The ROOT's PLAIN surface refuses a BINARY selector, and this is the body that would STOP COMPILING if
// `TryGetComposedReceiverType` were widened without widening `TryAppend`'s root call in the same move:
// `ClaimsRoot` would answer yes, the append would answer no, and the cascade sets `nsharpOwned` before
// it asks. That combination declines the whole FUNCTION.
func DoorMemberBinarySelector(points: DoorMemberPoint[], offset: int): int {
    return points[offset + 1].X
}

// A composed INSTANCE-member receiver is not one of the five arms the type side answers.
func DoorMemberOfMember(outer: DoorMemberOuter): int {
    return outer.Inner.Value
}

// A CALL receiver is not one of them either.
func DoorMemberOfCallResult(text: string): int {
    return text.Trim().Length
}

// The door dispatches on the OUTER kind, so a parenthesised ROOT is the parenthesis owner's shape.
func DoorMemberParenthesisedRoot(box: DoorMemberBox): int {
    return (box.Value)
}

// The claim rule is type EQUALITY: the same expression on a `long` function is the host's, because the
// host's `conv.i8` is not a row this door promises.
func DoorMemberWidenedReturn(box: DoorMemberBox): long {
    return box.Value
}

class DoorMemberOuter {
    Inner: DoorMemberBox

    constructor(inner: DoorMemberBox) {
        Inner = inner
    }
}

test "the member-access roots the door declines are emitted by the host exactly as before" {
    box := new DoorMemberBox(7, "label")
    points := [new DoorMemberPoint(10, 20), new DoorMemberPoint(30, 40)]

    assert DoorMemberBinarySelector(points, 0) == 30
    assert DoorMemberOfMember(new DoorMemberOuter(box)) == 7
    assert DoorMemberOfCallResult("  ab  ") == 2
    assert DoorMemberParenthesisedRoot(box) == 7
    assert DoorMemberWidenedReturn(box) == 7L
}


// ---- THE EXTERNAL-STATIC ROOT: DOOR KIND 8's OTHER OWNER (class X, 015-B15) ----
//
// `015-B14` gave the door kind 8 and claimed only the cascade's EIGHTH arm; its SEVENTH —
// `ColumnarExternalStaticMemberPlanner` — was the named remainder and the arm REFUSED it. This slice
// gives that owner its own `TryAppendRoot` and the refusal becomes a CLAIM, so door kind 8 is CLOSED:
// both cascade arms are owned and the arm carries no scratch plan and no refusal.
//
// The owner has THREE appends and all three are exercised here: a static PROPERTY (`call`), a static
// readonly FIELD (`ldsfld`), and a LITERAL field, which `TryAppendLiteralField` reconstructs rather
// than loads — an enum member through `Convert.ToInt32(field.GetValue(null))` and a primitive
// `MinValue`/`MaxValue` from the field TYPE alone. Only the first two are reached by the corpus's own
// live bodies; the literal arm is reached here and by the probe set.

// A static PROPERTY over a reference result.
func DoorStaticProperty(): string {
    return Environment.NewLine
}

// A static PROPERTY over a VALUE result.
func DoorStaticValueProperty(): DateTime {
    return DateTime.UtcNow
}

// A static readonly FIELD whose owner is a DOTTED chain rather than a bare name.
func DoorStaticQualifiedField(): OpCode {
    return System.Reflection.Emit.OpCodes.Ldsfld
}

// A static readonly FIELD that is NOT literal, so it loads rather than reconstructing.
func DoorStaticReadonlyField(): DateTime {
    return DateTime.UnixEpoch
}

// The LITERAL arm, enum half.
func DoorStaticEnumLiteral(): StringComparison {
    return StringComparison.Ordinal
}

// The LITERAL arm, RECONSTRUCTION half — the value is rebuilt from the field type and the member name,
// never read off the `FieldInfo`.
func DoorStaticIntMax(): int {
    return Int32.MaxValue
}

func DoorStaticLongMin(): long {
    return Int64.MinValue
}

// The INITIALIZER door as well as the return door.
func DoorStaticDeclaration(): string {
    captured := Environment.NewLine
    return captured
}

// An INSTANCE method rather than a free function — the shape `RangeAndIndex.tests.nl:106` carries.
class DoorStaticReader {
    func ReadNewLine(): string {
        return Environment.NewLine
    }
}

test "the expression door claims the external static-member root through all three appends" {
    assert DoorStaticProperty() == Environment.NewLine
    assert DoorStaticDeclaration() == Environment.NewLine

    utcNow := DoorStaticValueProperty()
    assert utcNow.Year >= 2020

    code := DoorStaticQualifiedField()
    codeText := code.ToString()
    assert codeText == "ldsfld"

    epoch := DoorStaticReadonlyField()
    assert epoch.Year == 1970

    comparison := DoorStaticEnumLiteral()
    assert comparison == StringComparison.Ordinal

    intMax := DoorStaticIntMax()
    assert intMax == 2147483647

    longMin := DoorStaticLongMin()
    assert longMin == Int64.MinValue

    reader := new DoorStaticReader()
    assert reader.ReadNewLine() == Environment.NewLine
}


// ---- AND THE MEMBER-ACCESS ROOTS THE SEVENTH ARM DOES **NOT** CLAIM (015-B15) ----
//
// Named precisely rather than loosely, because a MARKED CLI was run over these three bodies and only
// ONE of them is a door decline at all. The other two are door claims through OTHER arms, and saying
// "the door declines them" would have been false in bytes.

// THE ONE REAL DECLINE OF THE THREE. The door dispatches on the OUTER kind, so a parenthesised ROOT
// stays the parenthesis owner's shape — the same policy `015-B14` pinned for the instance-member root,
// and a marked CLI says this body is on the host path on both sides.
func DoorStaticParenthesisedRoot(): string {
    return (Environment.NewLine)
}

// A COMPOSED root whose RECEIVER is an external static member is the EIGHTH arm's, not the seventh's:
// the seventh finds no row for owner `DateTime.UnixEpoch`, and `TryGetComposedReceiverType`'s
// member-access arm then types the receiver through that same owner. A marked CLI says it is
// door-claimed on BOTH sides — `015-B14` took it, and this slice does not move it.
func DoorStaticComposedReceiver(): int {
    return DateTime.UnixEpoch.Year
}

// A name the body can SEE is a nearer binding, so the external-static owner refuses it and the
// IDENTIFIER owner takes the read instead — a kind-6 claim the door has held since `015-B5`, and a
// marked CLI says it is door-claimed on BOTH sides rather than moved by this slice.
func DoorStaticShadowedOwner(Environment: string): string {
    marker := Environment
    return marker
}

test "the member-access roots outside the external-static arm keep their existing owners" {
    assert DoorStaticParenthesisedRoot() == Environment.NewLine
    assert DoorStaticComposedReceiver() == 1970
    assert DoorStaticShadowedOwner("shadow") == "shadow"
}
