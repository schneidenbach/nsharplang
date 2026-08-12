namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for WHAT COUNTS AS A PROOF.
//
// These thirteen predicates were 114 lines inside `SystemsAnalyzer.cs` and they name NO NSYS code:
// they are consumed by the two `[hot]` trap rules (`NSYS120`, index and division) and by nothing
// else. That makes them the only systems family whose entire observable behaviour is a boolean, and
// it makes these contracts the primary pinning — a wrong answer here does not add a diagnostic, it
// silently REMOVES one, which no corpus run would notice.
//
// EIGHT THINGS THIS FAMILY IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE TWO READINGS ARE OPPOSITE. `if (b.Length < 4) return;` proves a MINIMUM of 4 for the code
// after it, while `while (i < b.Length)` proves `i` is WITHIN `b` for the code inside it. Reading
// either one the other way inverts a proof.
//
// (2) THE NEGATIVE READING ONLY HAPPENS WHEN THE THEN-BRANCH EXITS. An `if` that does not leave the
// function proves nothing after itself.
//
// (3) EXITING SEES THROUGH THREE WRAPPERS AND INTO BLOCKS, and a block exits if ANY statement does.
//
// (4) THE LITERAL BOUNDS ARE ASYMMETRIC. `Length < N` proves a minimum only for N > 0; `Length == N`
// proves one only for N == 0 (and the minimum it proves is 1, not 0).
//
// (5) THE OPERAND ORDER IS PART OF THE PATTERN. `4 > b.Length` and `b.Length > i` are NOT read. That
// is deliberate narrowness, not an oversight, and widening it would manufacture proofs.
//
// (6) THE RECEIVER IS AN EXPRESSION KEY. `b` and `this.b` are different receivers.
//
// (7) THE TWO INDEX PROOFS DO NOT SUBSTITUTE FOR EACH OTHER. A minimum length proves only a LITERAL
// index, and strictly (`MinLength 4` proves `a[3]`, not `a[4]`); an index-within guard proves only a
// NAMED index.
//
// (8) A FLOAT DIVISOR IS READ INVARIANTLY, WITHOUT ITS TYPE SUFFIX, AND WITHOUT THOUSANDS
// SEPARATORS. The last is exactness: the rule reads under `NumberStyles.Float`, which does not admit
// them, so `1,000` must not be readable as a non-zero literal.

func SgpInt(text: string): IntLiteralExpression {
    return new IntLiteralExpression(text, 1, 1)
}

func SgpFloat(text: string): FloatLiteralExpression {
    return new FloatLiteralExpression(text, 1, 1)
}

func SgpName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 1, 1)
}

func SgpMember(target: Expression, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(target, memberName, false, 1, 1)
}

func SgpLength(receiverName: string): MemberAccessExpression {
    return SgpMember(SgpName(receiverName), "Length")
}

func SgpBinary(left: Expression, op: BinaryOperator, right: Expression): BinaryExpression {
    return new BinaryExpression(left, op, right, 1, 1)
}

func SgpBlock(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 1, 1)
}

func SgpOne(statement: Statement): List<Statement> {
    statements := new List<Statement>()
    statements.Add(statement)
    return statements
}

func SgpReturn(): ReturnStatement {
    return new ReturnStatement(null, 1, 1)
}

func SgpEmpty(): EmptyStatement {
    return new EmptyStatement(1, 1)
}

func SgpIf(condition: Expression, thenStatement: Statement): IfStatement {
    return new IfStatement(condition, thenStatement, null, 1, 1)
}

func SgpIndex(receiver: Expression, index: Expression): IndexAccessExpression {
    return new IndexAccessExpression(receiver, index, false, 1, 1)
}

func SgpGuards(): List<Guard> {
    return new List<Guard>()
}

// Field readers, one per field a contract asserts on: a property read chained onto a call result does
// not emit.
func SgpKind(guards: List<Guard>, index: int): GuardKind {
    guard := guards[index]
    return guard.Kind
}

func SgpTarget(guards: List<Guard>, index: int): string {
    guard := guards[index]
    return guard.Target
}

func SgpValue(guards: List<Guard>, index: int): int {
    guard := guards[index]
    return guard.Value
}

func SgpSecondary(guards: List<Guard>, index: int): string? {
    guard := guards[index]
    return guard.Secondary
}

// `if (<condition>) return;` — the shape the negative reading is derived from.
func SgpExitingIf(condition: Expression): List<Guard> {
    return SystemsGuardPolicy.DeriveGuardsFromExitingIf(SgpIf(condition, SgpReturn()))
}

test "A RETURN, A THROW, A BREAK AND A CONTINUE ALL LEAVE" {
    assert SystemsGuardPolicy.StatementExits(SgpReturn())
    assert SystemsGuardPolicy.StatementExits(new ThrowStatement(SgpName("e"), 1, 1))
    assert SystemsGuardPolicy.StatementExits(new BreakStatement(1, 1))
    assert SystemsGuardPolicy.StatementExits(new ContinueStatement(1, 1))
}

test "A STATEMENT THAT IS NOT ONE OF THE FOUR DOES NOT LEAVE" {
    assert !SystemsGuardPolicy.StatementExits(SgpEmpty())
}

test "A BLOCK LEAVES IF ANY STATEMENT IN IT DOES, NOT ONLY THE LAST" {
    statements := new List<Statement>()
    statements.Add(SgpReturn())
    statements.Add(SgpEmpty())
    assert SystemsGuardPolicy.StatementExits(SgpBlock(statements))
}

test "AN EMPTY BLOCK DOES NOT LEAVE" {
    assert !SystemsGuardPolicy.StatementExits(SgpBlock(new List<Statement>()))
}

test "THE THREE TRANSPARENT WRAPPERS DO NOT CHANGE WHETHER CONTROL LEAVES" {
    body := SgpBlock(SgpOne(SgpReturn()))
    assert SystemsGuardPolicy.StatementExits(new AllocBlockStatement(body, 1, 1))
    assert SystemsGuardPolicy.StatementExits(new AllowStatement(new List<string>(), null, null, body, 1, 1))
    assert SystemsGuardPolicy.StatementExits(new UnsafeBlockStatement(body, 1, 1))
}

test "A WRAPPER AROUND A BLOCK THAT DOES NOT LEAVE DOES NOT LEAVE EITHER" {
    body := SgpBlock(SgpOne(SgpEmpty()))
    assert !SystemsGuardPolicy.StatementExits(new UnsafeBlockStatement(body, 1, 1))
}

test "AN IF WHOSE THEN-BRANCH DOES NOT EXIT PROVES NOTHING" {
    guards := SystemsGuardPolicy.DeriveGuardsFromExitingIf(SgpIf(SgpBinary(SgpLength("b"), BinaryOperator.Less, SgpInt("4")), SgpEmpty()))
    assert guards.Count == 0
}

test "A LENGTH-LESS-THAN GUARD THAT EXITS PROVES THAT MINIMUM" {
    guards := SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Less, SgpInt("4")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.MinLength
    assert SgpTarget(guards, 0) == "b"
    assert SgpValue(guards, 0) == 4
}

test "A LENGTH-EQUALS-ZERO GUARD THAT EXITS PROVES A MINIMUM OF ONE" {
    guards := SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Equal, SgpInt("0")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.MinLength
    assert SgpValue(guards, 0) == 1
}

test "THE TWO LITERAL BOUNDS ARE ASYMMETRIC AND NEITHER WIDENS" {
    // `Length < 0` is not a minimum anyone would read, and `Length == 3` bounds nothing.
    assert SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Less, SgpInt("0"))).Count == 0
    assert SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Equal, SgpInt("3"))).Count == 0
}

test "THE OPERAND ORDER IS PART OF THE LENGTH PATTERN" {
    assert SgpExitingIf(SgpBinary(SgpInt("4"), BinaryOperator.Less, SgpLength("b"))).Count == 0
}

test "A LENGTH COMPARISON AGAINST A NON-LITERAL IS NOT READ" {
    assert SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Less, SgpName("n"))).Count == 0
}

test "THE RECEIVER IS AN EXPRESSION KEY, SO A QUALIFIED ONE IS A DIFFERENT RECEIVER" {
    guards := SgpExitingIf(SgpBinary(SgpMember(SgpMember(SgpName("this"), "buffer"), "Length"), BinaryOperator.Less, SgpInt("4")))
    assert guards.Count == 1
    assert SgpTarget(guards, 0) == "this.buffer"
}

test "AN EQUALS-ZERO TEST THAT EXITS PROVES THE IDENTIFIER IS NON-ZERO" {
    guards := SgpExitingIf(SgpBinary(SgpName("d"), BinaryOperator.Equal, SgpInt("0")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.NonZero
    assert SgpTarget(guards, 0) == "d"
}

test "THE ZERO MUST BE THE WRITTEN ZERO AND THE SUBJECT MUST BE ON THE LEFT" {
    assert SgpExitingIf(SgpBinary(SgpName("d"), BinaryOperator.Equal, SgpInt("0x0"))).Count == 0
    assert SgpExitingIf(SgpBinary(SgpInt("0"), BinaryOperator.Equal, SgpName("d"))).Count == 0
}

test "ONE CONDITION CAN CONTRIBUTE TWO GUARDS BECAUSE BOTH ARMS RUN" {
    // `b.Length == 0` is read as a minimum AND — were the left side an identifier — as a non-zero
    // test; the arms are consecutive ifs, not an else-chain. Here only the first fires, and the
    // second's independence is what this pins.
    guards := SgpExitingIf(SgpBinary(SgpLength("b"), BinaryOperator.Equal, SgpInt("0")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.MinLength
}

test "A LOOP CONDITION IS ITS BODY'S POSITIVE GUARD" {
    guards := SystemsGuardPolicy.DeriveLoopGuards(SgpBinary(SgpName("i"), BinaryOperator.Less, SgpLength("b")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.IndexWithin
    assert SgpTarget(guards, 0) == "b"
    assert SgpSecondary(guards, 0) == "i"
}

test "AN ABSENT LOOP CONDITION PROVES NOTHING" {
    assert SystemsGuardPolicy.DeriveLoopGuards(null).Count == 0
    assert SystemsGuardPolicy.DerivePositiveGuards(null).Count == 0
}

test "THE INDEX-WITHIN PATTERN IS EXACT IN BOTH OPERANDS AND IN ITS OPERATOR" {
    assert SystemsGuardPolicy.DerivePositiveGuards(SgpBinary(SgpLength("b"), BinaryOperator.Less, SgpName("i"))).Count == 0
    assert SystemsGuardPolicy.DerivePositiveGuards(SgpBinary(SgpName("i"), BinaryOperator.LessOrEqual, SgpLength("b"))).Count == 0
    assert SystemsGuardPolicy.DerivePositiveGuards(SgpBinary(SgpName("i"), BinaryOperator.Less, SgpMember(SgpName("b"), "Count"))).Count == 0
}

test "A NOT-EQUALS-ZERO CONDITION HOLDING PROVES NON-ZERO" {
    guards := SystemsGuardPolicy.DerivePositiveGuards(SgpBinary(SgpName("d"), BinaryOperator.NotEqual, SgpInt("0")))
    assert guards.Count == 1
    assert SgpKind(guards, 0) == GuardKind.NonZero
    assert SgpTarget(guards, 0) == "d"
}

test "AN INDEX-WITHIN GUARD PROVES A NAMED INDEX ON THE SAME RECEIVER" {
    guards := SgpGuards()
    guards.Add(Guard.IndexWithin("b", "i"))
    assert SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpName("i")), guards)
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpName("j")), guards)
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("c"), SgpName("i")), guards)
}

test "AN INDEX-WITHIN GUARD DOES NOT PROVE A LITERAL INDEX" {
    guards := SgpGuards()
    guards.Add(Guard.IndexWithin("b", "i"))
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpInt("0")), guards)
}

test "A MINIMUM LENGTH PROVES A LITERAL INDEX AND IT IS STRICT" {
    guards := SgpGuards()
    guards.Add(Guard.MinLength("b", 4))
    assert SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpInt("3")), guards)
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpInt("4")), guards)
}

test "A MINIMUM LENGTH DOES NOT PROVE A NAMED INDEX" {
    guards := SgpGuards()
    guards.Add(Guard.MinLength("b", 4))
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpName("i")), guards)
}

test "AN INDEX THAT IS NEITHER A NAME NOR A LITERAL IS NEVER PROVED" {
    guards := SgpGuards()
    guards.Add(Guard.IndexWithin("b", "i"))
    guards.Add(Guard.MinLength("b", 4))
    computed := SgpIndex(SgpName("b"), SgpBinary(SgpName("i"), BinaryOperator.Add, SgpInt("1")))
    assert !SystemsGuardPolicy.IsIndexGuarded(computed, guards)
}

test "AN EMPTY GUARD SET PROVES NOTHING" {
    assert !SystemsGuardPolicy.IsIndexGuarded(SgpIndex(SgpName("b"), SgpName("i")), SgpGuards())
    assert !SystemsGuardPolicy.IsNonZeroGuarded(SgpName("d"), SgpGuards())
}

test "A NON-ZERO GUARD PROVES ONLY A BARE IDENTIFIER OF THE SAME NAME" {
    guards := SgpGuards()
    guards.Add(Guard.NonZero("d"))
    assert SystemsGuardPolicy.IsNonZeroGuarded(SgpName("d"), guards)
    assert !SystemsGuardPolicy.IsNonZeroGuarded(SgpName("e"), guards)
    assert !SystemsGuardPolicy.IsNonZeroGuarded(SgpMember(SgpName("x"), "d"), guards)
}

test "A NON-ZERO INT LITERAL IS A PROOF AND ZERO IS NOT" {
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpInt("2"))
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpInt("0"))
}

test "AN UNREADABLE INT LITERAL PROVES NOTHING RATHER THAN BEING ASSUMED SAFE" {
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpInt("0x10"))
}

test "A NON-ZERO FLOAT LITERAL IS A PROOF IN EVERY SUFFIX (M2)" {
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("2.0"))
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("2.0f"))
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("4.0F"))
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("4.0d"))
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("4.0m"))
    assert SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("1e3"))
}

test "A ZERO FLOAT LITERAL PROVES NOTHING IN ANY SPELLING" {
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("0.0"))
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("0f"))
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("0.00m"))
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpFloat("-0.0"))
}

test "A THOUSANDS SEPARATOR IS NOT READABLE, WHICH IS WHAT NumberStyles.Float MEANS" {
    // The provider-only TryParse overload WOULD read `1,000` as one thousand; the rule reads under
    // NumberStyles.Float, which does not admit the group separator, so this must stay unproven.
    assert !SystemsGuardPolicy.IsNonZeroFloatLiteral("1,000")
    assert SystemsGuardPolicy.IsNonZeroFloatLiteral("1000")
}

test "AN EXPRESSION DIVISOR THAT IS NOT A LITERAL IS NEVER PROVED BY ITSELF" {
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpName("d"))
    assert !SystemsGuardPolicy.IsDefinitelyNonZero(SgpMember(SgpName("x"), "d"))
}
