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
// declared return type — the exact shape `ColumnarMethodBodyPlanner.TryPlanLiteralReturnBody` claims.
// A claimed body does not reach the host's kind-20 arm at all: the plan-row IR emits every byte of it
// through `ColumnarCodePlanExecutor`, ending in the `ret` row.
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
// A `bool` literal is kind 4 and belongs to a different owner; an unsuffixed integer on a
// non-`int` function goes through the host's target-typed ADOPTION pre-pass, which emits different
// rows than the literal owner would, which is exactly why the claim rule is type EQUALITY.

func DriverBool(): bool {
    return true
}

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
    assert DriverBool()
    assert DriverAdoptedShort() == 42
    assert DriverAdoptedLong() == 42L
    assert DriverTwoStatements() == 42
}
