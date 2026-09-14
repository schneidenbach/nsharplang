namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import System.Globalization
import NSharpLang.Compiler.Ast


// WHAT COUNTS AS A PROOF.
//
// Two of the systems rules refuse an operation unless the program has already PROVED it safe: an
// index access in `[hot]` needs a bounds proof, and a division in `[hot]` needs a non-zero divisor.
// This owner decides what a proof is. It reports nothing and names no NSYS code — `SystemsTrapPolicy`
// at the foot of this file is its reporting twin and holds the sink — which is why this class is the
// only systems owner that takes no constructor argument at all.
//
// A GUARD IS DERIVED FROM CONTROL FLOW, NOT FROM AN ANNOTATION. Three shapes produce one:
// a condition that must HOLD inside a scope (a loop's condition, an `if`'s then-branch), and a
// condition whose failure EXITS (an `if` whose then-branch returns, throws, breaks or continues,
// which proves the negation for everything after it). The first is read positively and the second is
// read negatively, and those are the only two readings — there is no inference across statements,
// no value tracking, and no arithmetic.
//
// EXITING IS STRUCTURAL AND IT LOOKS INSIDE BLOCKS. `if (x.Length < 4) return;` proves a minimum
// length, and so does the same test with a braced body, an `alloc { }`, an `allow(...) { }` or an
// `unsafe { }` around the `return`, because those three wrappers do not change whether control
// leaves. A block exits if ANY of its statements does — deliberately not "the last one" — because
// `{ Log(); return; }` exits just as much as `{ return; }`.
//
// THE PROOFS ARE DELIBERATELY NARROW, AND THE NARROWNESS IS THE POINT. A length comparison is read
// only in the written form `receiver.Length <op> <int literal>`; an index-within proof only in
// `<identifier> < receiver.Length`. Widening either — commuting the operands, admitting a computed
// bound, following an alias — would let the analyzer claim a proof the reader cannot see, and a
// false proof here silently removes a diagnostic rather than adding one.
//
// THE RECEIVER IS AN EXPRESSION KEY, NOT A NAME. `buffer.Length` and `this.buffer.Length` are
// different receivers and must not prove each other, so both the guard and the question that reads
// it go through `SystemsExpressionNames.ExpressionKey`, which is the same projection the rest of the
// systems analyzer keys expressions by.
//
// A NON-ZERO LITERAL DIVISOR IS A PROOF IN EVERY NUMERIC SHAPE. `x / 2` and `x / 2.0f` are both
// provably safe, and reading only integer literals here reported the float form as an unproven trap
// (M2). A float literal is read by its magnitude after its type suffix is removed, so `0.0`, `0f`
// and `0.00m` are all zero and none of them proves anything.
class SystemsGuardPolicy {

    // THE NEGATIVE READING. An `if` whose then-branch leaves the function proves the NEGATION of its
    // condition for every statement after it. An `if` that does not exit proves nothing at all here —
    // its positive reading belongs to the scope of the then-branch, which is what
    // `DerivePositiveGuards` gives the walk to push.
    static func DeriveGuardsFromExitingIf(ifStatement: IfStatement): List<Guard> {
        guards := new List<Guard>()
        if !StatementExits(ifStatement.ThenStatement) {
            return guards
        }

        CollectNegativeGuard(ifStatement.Condition, guards)
        return guards
    }

    // A LOOP'S CONDITION IS ITS BODY'S POSITIVE GUARD, and that is the whole rule: `for (i = 0;
    // i < b.Length; i++)` proves `i` is within `b` for every statement in the body, and nothing after
    // it. Named separately from `DerivePositiveGuards` because the walk asks it of a `for` and a
    // `while` rather than of an `if`, and a future loop rule that is not the plain positive reading
    // must be able to say so here.
    static func DeriveLoopGuards(condition: Expression?): List<Guard> {
        return DerivePositiveGuards(condition)
    }

    // THE POSITIVE READING, over a condition that may be absent: `for (;;)` proves nothing.
    static func DerivePositiveGuards(condition: Expression?): List<Guard> {
        guards := new List<Guard>()
        if condition != null {
            CollectPositiveGuard(condition, guards)
        }

        return guards
    }

    // WHETHER CONTROL LEAVES. `return`, `throw`, `break` and `continue` all leave the statement the
    // guard is being derived for, and the three transparent wrappers are seen through. A block exits
    // if ANY statement in it does; see the header for why that is not "the last one".
    static func StatementExits(statement: Statement): bool {
        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            return true
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            return true
        }

        breakStatement := statement as BreakStatement
        if breakStatement != null {
            return true
        }

        continueStatement := statement as ContinueStatement
        if continueStatement != null {
            return true
        }

        block := statement as BlockStatement
        if block != null {
            return AnyStatementExits(block)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return StatementExits(allocBlock.Body)
        }

        allowStatement := statement as AllowStatement
        if allowStatement != null {
            return StatementExits(allowStatement.Body)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return StatementExits(unsafeBlock.Body)
        }

        return false
    }

    static func AnyStatementExits(block: BlockStatement): bool {
        index := 0
        while index < block.Statements.Count {
            if StatementExits(block.Statements[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // WHAT THE FAILURE OF A CONDITION PROVES. `receiver.Length < 4` failing proves the length is at
    // least 4; `receiver.Length == 0` failing proves it is at least 1. The literal must be positive
    // for the first form — `Length < 0` failing proves nothing a reader would call a minimum — and
    // exactly zero for the second, because `Length == 3` failing does not bound anything.
    //
    // BOTH ARMS RUN. A condition is read as a length comparison AND as a null-ish zero test, so one
    // `if` can contribute two guards; the C# original wrote them as two consecutive `if`s and not as
    // an else-chain, and that is preserved.
    static func CollectNegativeGuard(expression: Expression, guards: List<Guard>) {
        binary := expression as BinaryExpression
        if binary == null {
            return
        }

        receiver := ""
        literal := 0
        comparison := binary.Operator
        if TryGetLengthComparison(binary, out receiver, out literal, out comparison) {
            if comparison == BinaryOperator.Less && literal > 0 {
                guards.Add(Guard.MinLength(receiver, literal))
            }

            if comparison == BinaryOperator.Equal && literal == 0 {
                guards.Add(Guard.MinLength(receiver, 1))
            }
        }

        if binary.Operator == BinaryOperator.Equal {
            CollectNonZeroFromEqualityWithZero(binary, guards)
        }
    }

    // WHAT A CONDITION HOLDING PROVES. `i < receiver.Length` holding proves `i` indexes `receiver`;
    // `x != 0` holding proves `x` is non-zero. Both arms run, for the same reason the negative
    // reading's do.
    static func CollectPositiveGuard(expression: Expression, guards: List<Guard>) {
        binary := expression as BinaryExpression
        if binary == null {
            return
        }

        receiver := ""
        index := ""
        if TryGetIndexLessThanLength(binary, out receiver, out index) {
            guards.Add(Guard.IndexWithin(receiver, index))
        }

        if binary.Operator == BinaryOperator.NotEqual {
            CollectNonZeroFromEqualityWithZero(binary, guards)
        }
    }

    // The two readings differ only in WHICH operator carries the zero test — `==` for the exiting
    // form, `!=` for the holding form — so the shape they share is written once. The subject must be
    // a bare identifier on the LEFT: `0 != x` is not read, deliberately, because widening the
    // proof-side of a trap rule is how a false proof gets in.
    static func CollectNonZeroFromEqualityWithZero(binary: BinaryExpression, guards: List<Guard>) {
        identifier := binary.Left as IdentifierExpression
        if identifier == null {
            return
        }

        if !IsZero(binary.Right) {
            return
        }

        guards.Add(Guard.NonZero(identifier.Name))
    }

    // WHETHER AN INDEX ACCESS IS PROVED IN BOUNDS, asked of every `a[i]` inside `[hot]`. Two proofs
    // answer it: an `IndexWithin` guard naming the same receiver and the same index NAME, or a
    // `MinLength` guard on the same receiver whose bound is strictly greater than a LITERAL index.
    // `a[i]` is never proved by a minimum length, and `a[2]` is never proved by an index-within
    // guard — the two proofs are about different things and neither substitutes for the other.
    static func IsIndexGuarded(index: IndexAccessExpression, guards: List<Guard>): bool {
        receiver := SystemsExpressionNames.ExpressionKey(index.Object)
        indexName := IndexIdentifierName(index.Index)
        literalIndex := 0
        hasLiteralIndex := TryGetLiteralIndex(index.Index, out literalIndex)

        position := 0
        while position < guards.Count {
            guard := guards[position]
            if GuardProvesIndex(guard, receiver, indexName, hasLiteralIndex, literalIndex) {
                return true
            }

            position = position + 1
        }

        return false
    }

    static func GuardProvesIndex(guard: Guard, receiver: string, indexName: string?, hasLiteralIndex: bool, literalIndex: int): bool {
        if guard.Target != receiver {
            return false
        }

        if guard.Kind == GuardKind.IndexWithin && guard.Secondary == indexName {
            return true
        }

        return guard.Kind == GuardKind.MinLength && hasLiteralIndex && guard.Value > literalIndex
    }

    static func IndexIdentifierName(index: Expression): string? {
        identifier := index as IdentifierExpression
        if identifier == null {
            return null
        }

        return identifier.Name
    }

    static func TryGetLiteralIndex(index: Expression, out literalIndex: int): bool {
        literalIndex = 0
        literal := index as IntLiteralExpression
        if literal == null {
            return false
        }

        return int.TryParse(literal.Value, out literalIndex)
    }

    // WHETHER A DIVISOR IS PROVED NON-ZERO BY CONTROL FLOW, asked of the right operand of every `/`
    // and `%` inside `[hot]`. Only a bare identifier can be proved this way; an expression divisor is
    // either a literal (see below) or unproven.
    static func IsNonZeroGuarded(expression: Expression, guards: List<Guard>): bool {
        identifier := expression as IdentifierExpression
        if identifier == null {
            return false
        }

        position := 0
        while position < guards.Count {
            guard := guards[position]
            if guard.Kind == GuardKind.NonZero && guard.Target == identifier.Name {
                return true
            }

            position = position + 1
        }

        return false
    }

    // WHETHER A DIVISOR IS PROVED NON-ZERO BY BEING WRITTEN DOWN. A literal needs no control flow: it
    // is what it is. Both numeric literal shapes count — see the header on M2 — and an unparseable
    // literal proves nothing rather than being assumed safe.
    static func IsDefinitelyNonZero(expression: Expression): bool {
        literal := expression as IntLiteralExpression
        if literal != null {
            value := 0
            return int.TryParse(literal.Value, out value) && value != 0
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return IsNonZeroFloatLiteral(floatLiteral.Value)
        }

        return false
    }

    // A FLOAT LITERAL'S MAGNITUDE, READ INVARIANTLY AND WITHOUT ITS TYPE SUFFIX. `2f`, `2d` and `2m`
    // are the same divisor, and the suffix is stripped rather than parsed.
    //
    // THE GROUP SEPARATOR IS REJECTED BEFORE PARSING, and that is exactness rather than caution: the
    // rule reads a literal under `NumberStyles.Float`, which does NOT admit thousands separators,
    // while the provider-only `TryParse` overload does. `1,000` must therefore fail to read here, and
    // rejecting the separator explicitly is the only difference between the two style sets.
    static func IsNonZeroFloatLiteral(text: string): bool {
        trimmed := TrimNumericSuffix(text)
        if trimmed.IndexOf(',') >= 0 {
            return false
        }

        value := 0.0
        if !Double.TryParse(trimmed, CultureInfo.InvariantCulture, out value) {
            return false
        }

        return value != 0.0
    }

    static func TrimNumericSuffix(text: string): string {
        last := text.Length
        while last > 0 && IsNumericSuffixCharacter(text[last - 1]) {
            last = last - 1
        }

        return text.Substring(0, last)
    }

    static func IsNumericSuffixCharacter(candidate: char): bool {
        if candidate == 'f' || candidate == 'F' {
            return true
        }

        if candidate == 'd' || candidate == 'D' {
            return true
        }

        return candidate == 'm' || candidate == 'M'
    }

    // `receiver.Length <op> <int literal>`, in exactly that order and no other. The operator travels
    // out with the receiver and the bound because the two negative readings differ only by it.
    static func TryGetLengthComparison(binary: BinaryExpression, out receiver: string, out literal: int, out comparison: BinaryOperator): bool {
        receiver = ""
        literal = 0
        comparison = binary.Operator

        member := binary.Left as MemberAccessExpression
        if member == null || member.MemberName != "Length" {
            return false
        }

        value := binary.Right as IntLiteralExpression
        if value == null {
            return false
        }

        if !int.TryParse(value.Value, out literal) {
            return false
        }

        receiver = SystemsExpressionNames.ExpressionKey(member.Object)
        return true
    }

    // `<identifier> < receiver.Length`, in exactly that order and with exactly that operator.
    static func TryGetIndexLessThanLength(binary: BinaryExpression, out receiver: string, out index: string): bool {
        receiver = ""
        index = ""
        if binary.Operator != BinaryOperator.Less {
            return false
        }

        identifier := binary.Left as IdentifierExpression
        if identifier == null {
            return false
        }

        member := binary.Right as MemberAccessExpression
        if member == null || member.MemberName != "Length" {
            return false
        }

        receiver = SystemsExpressionNames.ExpressionKey(member.Object)
        index = identifier.Name
        return true
    }

    // The written zero, and only the written zero: `0`. `0x0`, `0L` and `0.0` are different tokens
    // and none of them is this one, because the rule reads the source the developer wrote.
    static func IsZero(expression: Expression): bool {
        literal := expression as IntLiteralExpression
        if literal == null {
            return false
        }

        return literal.Value == "0"
    }
}

// AN UNPROVEN TRAP OBLIGATION.
//
// The reporting twin of `SystemsGuardPolicy` above, held apart for exactly the reason
// `SystemsAttributeSet` and `SystemsAttributePolicy` are: that one decides what a proof IS and
// answers questions, this one decides what an UNPROVED operation costs and needs the sink. Three
// operations can trap at runtime with nothing in the source marking them — an index access, a
// division or modulo, and a `checked` arithmetic expression — and inside `[hot]` each must either be
// proved or waived.
//
// ALL THREE ARE `[hot]`-ONLY AND ALL THREE ARE WAIVED BY `allow(trap)`. Outside `[hot]` a systems
// program is allowed to trap: the promise about traps is the hot path's promise, and making it
// everywhere would report every array index in every program ever written.
//
// EACH ARM ANSWERS WHETHER THE WALK MUST RECORD THE OBLIGATION, which is exactly when the finding
// fires — and NOT merely whether the operation could trap. A waived trap is a trap the author took
// responsibility for at this site, so it must not travel to the caller through `ImplicitTrap` and be
// reported a second time as a callee's cost. That is the original's shape and it is the reason these
// three return a value at all.
//
// `checked` HAS NO PROOF SHAPE. There is no guard that proves an addition cannot overflow, so the
// only way past that arm is the waiver — which is why it is the one of the three that takes no guard
// list, and the asymmetry is deliberate rather than an omission.
class SystemsTrapPolicy {
    sinkValue: SystemsFindingSink

    constructor(sink: SystemsFindingSink) {
        sinkValue = sink
    }

    // AN INDEX ACCESS IN `[hot]` NEEDS A BOUNDS PROOF. `IsIndexGuarded` above decides what counts as
    // one; this decides what the absence of one costs.
    func ReportIndexTrap(index: IndexAccessExpression, guards: List<Guard>, allows: SystemsAllowStack, filePath: string, functionName: string, isHot: bool, isBoundary: bool): bool {
        if !isHot || allows.IsAllowed("trap") || SystemsGuardPolicy.IsIndexGuarded(index, guards) {
            return false
        }

        sinkValue.AddWhenHot("NSYS120", "implicitTrap", "index access in [hot] requires a proven bounds guard or allow(trap)", index.Line, index.Column, filePath, functionName, isHot, isBoundary)
        return true
    }

    // A DIVISION OR MODULO IN `[hot]` NEEDS A NON-ZERO DIVISOR — proved by a guard, or by the divisor
    // being a literal that is non-zero in any numeric shape. EVERY OTHER BINARY OPERATOR IS SILENT,
    // which is why the operator test lives here and not at the walk that dispatches: "which operators
    // can trap" is this rule's own first sentence, not the walk's.
    func ReportDivisionTrap(binary: BinaryExpression, guards: List<Guard>, allows: SystemsAllowStack, filePath: string, functionName: string, isHot: bool, isBoundary: bool): bool {
        if !isHot {
            return false
        }

        if binary.Operator != BinaryOperator.Divide && binary.Operator != BinaryOperator.Modulo {
            return false
        }

        if allows.IsAllowed("trap") || SystemsGuardPolicy.IsNonZeroGuarded(binary.Right, guards) || SystemsGuardPolicy.IsDefinitelyNonZero(binary.Right) {
            return false
        }

        sinkValue.AddWhenHot("NSYS120", "implicitTrap", "division in [hot] requires a proven non-zero divisor or allow(trap)", binary.Line, binary.Column, filePath, functionName, isHot, isBoundary)
        return true
    }

    // `checked` ARITHMETIC IN `[hot]`. See the header for why the waiver is the only way past it.
    func ReportCheckedTrap(allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool): bool {
        if !isHot || allows.IsAllowed("trap") {
            return false
        }

        sinkValue.AddWhenHot("NSYS120", "implicitTrap", "checked arithmetic in [hot] requires an overflow proof or allow(trap)", line, column, filePath, functionName, isHot, isBoundary)
        return true
    }
}
