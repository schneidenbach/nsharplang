namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A `stackalloc` MAY RESERVE, AND WHAT IT MAY NOT OUTLIVE.
//
// Every member of this family was `private` in `SystemsAnalyzer.cs`, reached from ONE decision site,
// and pinned only by whatever end-to-end fixture happened to compile a `stackalloc` — of which the
// systems corpus has none that violates the budget. NSYS080 is one of the sixteen codes the live
// corpus never fires, so these contracts and the slice's fixtures are the whole proof. They are
// written around the six things this rule is easy to get wrong.
//
// (1) THE PRODUCT IS COMPUTED IN `long`. `stackalloc int[2000000000]` is 8 GB, and an `int`
// multiplication wraps it to a small negative number that passes any budget. The contract below
// asserts the reported byte count, not merely that it failed.
//
// (2) A NEGATIVE COUNT IS ITS OWN ANSWER. `-1` must report "cannot be negative", not "must be
// statically bounded": the first tells a developer their expression is wrong, the second tells them
// the analyzer could not read it. `-0` is zero and is legal.
//
// (3) THE TRANSPARENT WRAPPERS ARE EXACTLY FOUR, AND THE CAST IS CONDITIONAL. Parentheses,
// `checked`, `unchecked` and an INTEGER-SHAPED cast are seen through; a `(double)` cast is not,
// because it is not the same reservation.
//
// (4) ALIASES ARE FOLLOWED BEFORE THE SIZE TABLE IS CONSULTED, and following them is what stops the
// same program reporting different numbers depending on whether it wrote `int` or an alias for it.
//
// (5) AN ALIAS CYCLE TERMINATES. A self-alias or a two-step ring must resolve, not hang.
//
// (6) THE ESCAPE RULE IS LEXICAL AND NARROW. Only a bare identifier the walk recorded as stackalloc
// backed escapes; a member access, a call, or an identifier that was never recorded does not.
func SapConfig(budget: int): ProjectConfig {
    config := ProjectFileParser.CreateDefault("stackalloc-contract")
    systems := config.Language.Systems
    systems.StackBudgetBytes = budget
    return config
}

func SapPolicy(budget: int): SystemsStackallocPolicy {
    policy := new SystemsStackallocPolicy()
    policy.BeginAnalysis(SapConfig(budget))
    return policy
}

func SapDefault(): SystemsStackallocPolicy {
    return SapPolicy(4096)
}

func SapSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func SapInt(text: string): IntLiteralExpression {
    return new IntLiteralExpression(text, 3, 20)
}

func SapStackAlloc(elementTypeName: string, length: Expression): StackAllocExpression {
    return new StackAllocExpression(SapSimple(elementTypeName), length, 3, 9)
}

func SapCast(targetTypeName: string, inner: Expression): CastExpression {
    return new CastExpression(inner, SapSimple(targetTypeName), CastKind.Hard, 3, 20)
}

func SapMessage(policy: SystemsStackallocPolicy, elementTypeName: string, length: Expression): string {
    violation := policy.BudgetViolation(SapStackAlloc(elementTypeName, length))
    if violation == null {
        return "<within budget>"
    }

    return violation.Code + "/" + violation.Effect + "/" + violation.Message
}

// ── the reservation fits, or it does not ─────────────────────────────────────

test "A RESERVATION INSIDE THE BUDGET IS NOT A VIOLATION, AND THE BOUNDARY IS INCLUSIVE" {
    policy := SapDefault()

    assert SapMessage(policy, "int", SapInt("1024")) == "<within budget>"
    assert SapMessage(policy, "byte", SapInt("4096")) == "<within budget>"
    assert SapMessage(policy, "int", SapInt("0")) == "<within budget>"
}

test "ONE ELEMENT PAST THE BUDGET IS A VIOLATION THAT NAMES BOTH NUMBERS" {
    policy := SapDefault()

    assert SapMessage(policy, "byte", SapInt("4097")) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
}

test "THE BUDGET IS THE PROJECT'S, NOT A CONSTANT — THE SAME SOURCE ANSWERS DIFFERENTLY UNDER IT" {
    assert SapMessage(SapPolicy(64), "int", SapInt("16")) == "<within budget>"
    assert SapMessage(SapPolicy(64), "int", SapInt("17")) == "NSYS080/lifetime/stackalloc reserves 68 bytes, above the configured systems stack budget of 64 bytes"
}

test "THE VIOLATION CARRIES ITS OWN FIX, SO THE WALK RELAYS AND DECIDES NOTHING" {
    violation := SapDefault().BudgetViolation(SapStackAlloc("byte", SapInt("999999")))

    assert violation != null
    assert violation.Suggestion == "Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path."
}

// ── the arithmetic is done in long, and that is behaviour ────────────────────

test "THE PRODUCT IS COMPUTED IN LONG: TWO BILLION INTS IS EIGHT BILLION BYTES, NOT A WRAPPED NEGATIVE" {
    policy := SapDefault()

    assert SapMessage(policy, "int", SapInt("2000000000")) == "NSYS080/lifetime/stackalloc reserves 8000000000 bytes, above the configured systems stack budget of 4096 bytes"
}

test "A COUNT ABOVE long.MaxValue IS NOT READABLE AS A COUNT AT ALL" {
    policy := SapDefault()

    assert SapMessage(policy, "byte", SapInt("9223372036854775808")) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

// ── a negative count is its own answer ───────────────────────────────────────

test "A NEGATIVE COUNT REPORTS ITS SIGN, NOT ITS UNREADABILITY" {
    policy := SapDefault()
    negativeOne := new UnaryExpression(UnaryOperator.Negate, SapInt("1"), 3, 20)

    assert SapMessage(policy, "int", negativeOne) == "NSYS080/lifetime/stackalloc length cannot be negative"
}

test "NEGATIVE ZERO IS ZERO, AND ZERO FITS EVERY BUDGET" {
    policy := SapDefault()
    negativeZero := new UnaryExpression(UnaryOperator.Negate, SapInt("0"), 3, 20)

    assert SapMessage(policy, "int", negativeZero) == "<within budget>"
}

test "A NEGATION OF SOMETHING UNREADABLE IS UNREADABLE, NOT NEGATIVE" {
    policy := SapDefault()
    negatedName := new UnaryExpression(UnaryOperator.Negate, new IdentifierExpression("n", 3, 20), 3, 20)

    assert SapMessage(policy, "int", negatedName) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

test "A NON-NEGATE UNARY IS NOT A SIGN, SO IT IS UNREADABLE" {
    policy := SapDefault()
    bitwiseNot := new UnaryExpression(UnaryOperator.BitwiseNot, SapInt("1"), 3, 20)

    assert SapMessage(policy, "int", bitwiseNot) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

// ── anything the compiler cannot read is refused, never assumed small ────────

test "A COMPUTED LENGTH IS REFUSED RATHER THAN GUESSED" {
    policy := SapDefault()
    parameterLength := new IdentifierExpression("count", 3, 20)
    sumLength := new BinaryExpression(SapInt("1"), BinaryOperator.Add, SapInt("2"), 3, 20)

    assert SapMessage(policy, "int", parameterLength) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
    assert SapMessage(policy, "int", sumLength) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

test "A MALFORMED LITERAL IS UNREADABLE, NOT ZERO" {
    policy := SapDefault()

    assert SapMessage(policy, "int", SapInt("0x")) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

test "HEX, BINARY AND UNDERSCORED LITERALS ARE READ, AND SO ARE THEIR SUFFIXES" {
    policy := SapDefault()

    assert SapMessage(policy, "byte", SapInt("0x10")) == "<within budget>"
    assert SapMessage(policy, "byte", SapInt("0b1000")) == "<within budget>"
    assert SapMessage(policy, "byte", SapInt("1_024")) == "<within budget>"
    assert SapMessage(policy, "byte", SapInt("16UL")) == "<within budget>"
    assert SapMessage(policy, "byte", SapInt("0x2000")) == "NSYS080/lifetime/stackalloc reserves 8192 bytes, above the configured systems stack budget of 4096 bytes"
}

// ── the four transparent wrappers, and the one conditional ───────────────────

test "PARENTHESES, checked AND unchecked ARE TRANSPARENT AND NEST" {
    policy := SapDefault()
    wrapped := new ParenthesizedExpression(
        new CheckedExpression(new UncheckedExpression(new ParenthesizedExpression(SapInt("4097"), 3, 20), 3, 20), 3, 20),
        3,
        20
    )

    assert SapMessage(policy, "byte", wrapped) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
}

test "AN INTEGER-SHAPED CAST IS TRANSPARENT — ALL SIX OF THEM" {
    policy := SapDefault()

    assert SapMessage(policy, "byte", SapCast("int", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("short", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("sbyte", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("byte", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("ushort", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("char", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
}

test "A NON-INTEGER CAST IS OPAQUE, AND SO IS A CAST TO long" {
    policy := SapDefault()

    assert SapMessage(policy, "byte", SapCast("double", SapInt("4097"))) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
    assert SapMessage(policy, "byte", SapCast("long", SapInt("4097"))) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

test "THE WRAPPERS ARE SEEN THROUGH ON THE WAY TO A SIGN AS WELL" {
    policy := SapDefault()
    negatedWrapped := new UnaryExpression(
        UnaryOperator.Negate,
        new ParenthesizedExpression(SapCast("int", SapInt("4")), 3, 20),
        3,
        20
    )

    assert SapMessage(policy, "int", negatedWrapped) == "NSYS080/lifetime/stackalloc length cannot be negative"
}

// ── the element-size table ───────────────────────────────────────────────────

test "EVERY NAMED ELEMENT WIDTH IS THE SOURCE-LEVEL ONE" {
    policy := SapPolicy(1)

    assert SapMessage(policy, "bool", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 2 bytes, above the configured systems stack budget of 1 bytes"
    assert SapMessage(policy, "short", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 4 bytes, above the configured systems stack budget of 1 bytes"
    assert SapMessage(policy, "float", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 8 bytes, above the configured systems stack budget of 1 bytes"
    assert SapMessage(policy, "double", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 16 bytes, above the configured systems stack budget of 1 bytes"
}

test "AN UNRECOGNISED ELEMENT TYPE IS CHARGED THE WIDEST WIDTH, NOT ASSUMED CHEAP" {
    policy := SapPolicy(1)

    assert SapMessage(policy, "SomeUserStruct", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 32 bytes, above the configured systems stack budget of 1 bytes"
    assert SapMessage(policy, "decimal", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 32 bytes, above the configured systems stack budget of 1 bytes"
}

// The element type IS simplified before it is sized — but the size table is keyed by the LANGUAGE
// KEYWORD, so the CLR spelling lands on the unknown width rather than on 4. That asymmetry is the
// C# original's behaviour reproduced exactly, and it is pinned here rather than quietly improved:
// widening the table is a semantic change to every systems project's reported byte count, and it
// belongs to a slice that owns the whole size family, not to this one.
test "SIMPLIFICATION HAPPENS FIRST, BUT THE SIZE TABLE IS KEYED BY THE KEYWORD, NOT THE CLR NAME" {
    policy := SapPolicy(1)

    assert policy.ResolveTypeAliasName("System.Int32") == "Int32"
    assert SapMessage(policy, "System.Int32", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 32 bytes, above the configured systems stack budget of 1 bytes"
}

// ── aliases are part of the size rule ────────────────────────────────────────

test "AN ALIASED ELEMENT TYPE IS SIZED AS WHAT IT ALIASES" {
    policy := SapPolicy(1)
    policy.RegisterTypeAlias("Sample", SapSimple("int"))

    assert SapMessage(policy, "Sample", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 8 bytes, above the configured systems stack budget of 1 bytes"
}

test "ALIAS CHAINS ARE FOLLOWED TO THE END" {
    policy := SapPolicy(1)
    policy.RegisterTypeAlias("Sample", SapSimple("Frame"))
    policy.RegisterTypeAlias("Frame", SapSimple("byte"))

    assert policy.ResolveTypeAliasName("Sample") == "byte"
    assert SapMessage(policy, "Sample", SapInt("2")) == "NSYS080/lifetime/stackalloc reserves 2 bytes, above the configured systems stack budget of 1 bytes"
}

test "AN ALIAS TO A GENERIC ALIASES ITS CONSTRUCTOR, WHICH IS WHY REGISTRATION ERASES" {
    policy := SapDefault()
    arguments := new List<TypeReference>()
    arguments.Add(SapSimple("int"))
    policy.RegisterTypeAlias("Bag", new GenericTypeReference("List", arguments, 1, 1))

    assert policy.ResolveTypeAliasName("Bag") == "List"
}

test "A SELF-ALIAS TERMINATES INSTEAD OF LOOPING" {
    policy := SapDefault()
    policy.RegisterTypeAlias("Loop", SapSimple("Loop"))

    assert policy.ResolveTypeAliasName("Loop") == "Loop"
}

test "A TWO-STEP ALIAS RING TERMINATES AT ITS FIRST REPEAT" {
    policy := SapDefault()
    policy.RegisterTypeAlias("A", SapSimple("B"))
    policy.RegisterTypeAlias("B", SapSimple("A"))

    assert policy.ResolveTypeAliasName("A") == "A"
    assert policy.ResolveTypeAliasName("B") == "B"
}

test "AN UNREGISTERED NAME RESOLVES TO ITS OWN SIMPLE NAME" {
    policy := SapDefault()

    assert policy.ResolveTypeAliasName("Unknown") == "Unknown"
    assert policy.ResolveTypeAliasName("System.Text.StringBuilder") == "StringBuilder"
}

test "AN ALIASED CAST TARGET IS TRANSPARENT ONLY WHEN THE ALIAS LANDS ON AN INTEGER SHAPE" {
    policy := SapDefault()
    policy.RegisterTypeAlias("Count", SapSimple("int"))
    policy.RegisterTypeAlias("Ratio", SapSimple("double"))

    assert SapMessage(policy, "byte", SapCast("Count", SapInt("4097"))) == "NSYS080/lifetime/stackalloc reserves 4097 bytes, above the configured systems stack budget of 4096 bytes"
    assert SapMessage(policy, "byte", SapCast("Ratio", SapInt("4097"))) == "NSYS080/lifetime/stackalloc length must be statically bounded in Systems N# v1"
}

test "BeginAnalysis CLEARS THE ALIAS TABLE, SO ONE PROJECT'S ALIASES CANNOT SIZE ANOTHER'S" {
    policy := SapPolicy(1)
    policy.RegisterTypeAlias("Sample", SapSimple("int"))
    assert policy.ResolveTypeAliasName("Sample") == "int"

    policy.BeginAnalysis(SapConfig(1))

    assert policy.ResolveTypeAliasName("Sample") == "Sample"
}

// ── the escape rule ──────────────────────────────────────────────────────────

func SapLocals(name: string): HashSet<string> {
    locals := new HashSet<string>(StringComparer.Ordinal)
    locals.Add(name)
    return locals
}

test "A LOCAL IS STACKALLOC BACKED ONLY WHEN ITS INITIALIZER IS THE RESERVATION ITSELF" {
    policy := SapDefault()
    reservation := SapStackAlloc("int", SapInt("4"))

    assert policy.IsStackallocBackedInitializer(reservation)
    assert !policy.IsStackallocBackedInitializer(new IdentifierExpression("other", 3, 20))
    assert !policy.IsStackallocBackedInitializer(SapInt("4"))
}

// The LENGTH rule sees through parentheses and casts; the BINDING rule must not, because a wrapper
// changes what the local owns even when it does not change the constant inside it.
test "THE BINDING RULE DOES NOT UNWRAP, EVEN THOUGH THE LENGTH RULE DOES" {
    policy := SapDefault()
    reservation := SapStackAlloc("int", SapInt("4"))

    assert !policy.IsStackallocBackedInitializer(new ParenthesizedExpression(reservation, 3, 20))
    assert !policy.IsStackallocBackedInitializer(new IndexAccessExpression(reservation, SapInt("0"), false, 3, 20))
}

test "RETURNING A STACKALLOC-BACKED LOCAL BY NAME IS THE ESCAPE, AND IT CARRIES ITS OWN FIX" {
    violation := SapDefault().EscapeViolation(new IdentifierExpression("scratch", 5, 12), SapLocals("scratch"))

    assert violation != null
    assert violation.Code == "NSYS080"
    assert violation.Effect == "lifetime"
    assert violation.Message == "stackalloc span cannot escape through a return value"
    assert violation.Suggestion == "Copy into caller-provided storage or return a heap/parameter-backed span with an explicit lifetime."
}

test "AN IDENTIFIER THE WALK NEVER RECORDED IS NOT AN ESCAPE" {
    assert SapDefault().EscapeViolation(new IdentifierExpression("other", 5, 12), SapLocals("scratch")) == null
}

test "THE ESCAPE IS EXACTLY THE BARE IDENTIFIER — NOT A MEMBER ACCESS, NOT A CALL, NOT A PARENTHESIS" {
    policy := SapDefault()
    locals := SapLocals("scratch")
    scratch := new IdentifierExpression("scratch", 5, 12)

    assert policy.EscapeViolation(new MemberAccessExpression(scratch, "Length", false, 5, 12), locals) == null
    assert policy.EscapeViolation(new CallExpression(scratch, new List<Argument>(), null, 5, 12), locals) == null
    assert policy.EscapeViolation(new ParenthesizedExpression(scratch, 5, 12), locals) == null
}

test "AN EMPTY RECORDED SET NEVER ESCAPES" {
    empty := new HashSet<string>(StringComparer.Ordinal)

    assert SapDefault().EscapeViolation(new IdentifierExpression("scratch", 5, 12), empty) == null
}

test "THE ESCAPE MATCH IS ORDINAL — A CASE DIFFERENCE IS A DIFFERENT LOCAL" {
    assert SapDefault().EscapeViolation(new IdentifierExpression("Scratch", 5, 12), SapLocals("scratch")) == null
}
