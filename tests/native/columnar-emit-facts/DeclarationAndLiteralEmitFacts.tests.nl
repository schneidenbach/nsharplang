namespace NSharpLang.ColumnarEmitFacts.Tests

import Demo


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
