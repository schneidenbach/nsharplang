namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for THE TWO NAMES SYSTEMS POLICY GIVES AN EXPRESSION.
//
// These two projections were seven lines each inside `SystemsAnalyzer.cs` and they are the blocking
// out-edge of three separate rule families: the call classification tables key on one, the guard
// proofs and the dictionary-receiver rule key on the other. Nothing they decide carries an NSYS code
// of its own, which is exactly why they need contracts: a change here is silent at the call site and
// loud three families away.
//
// THE THING THESE CONTRACTS EXIST TO PREVENT IS A "DE-DUPLICATION". Two other N# owners compute
// something that LOOKS like each of these, and both DISAGREE. The last section asserts the
// disagreements in both directions, so a future reader who folds them has a failing test rather than
// a silently different systems report. Slice 1 recorded the same trap for `ErasedName` versus
// `GetDisplayName`; this is its second instance and it is now a pattern, not an accident.

func SenIdentifier(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 3, 5)
}

func SenMember(receiver: Expression, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(receiver, memberName, false, 7, 11)
}

func SenArgs(): List<Argument> {
    return new List<Argument>()
}

func SenCall(callee: Expression): CallExpression {
    return new CallExpression(callee, SenArgs(), null, 7, 11)
}

func SenIndex(receiverName: string): IndexAccessExpression {
    return new IndexAccessExpression(SenIdentifier(receiverName), new IntLiteralExpression("0", 13, 17), false, 13, 17)
}

// ------------------------------------------------------------------ the call target

test "A BARE IDENTIFIER CALLEE TARGETS ITSELF" {
    assert SystemsExpressionNames.CallTarget(SenIdentifier("compute")) == "compute"
}

test "A MEMBER CALLEE TARGETS THE WHOLE DOTTED PATH, NOT THE MEMBER" {
    // This is the entire reason this owner exists rather than reusing the synthetic-call fact:
    // every classification table in the systems analyzer keys on receiver AND member together.
    assert SystemsExpressionNames.CallTarget(SenMember(SenIdentifier("File"), "Open")) == "File.Open"
}

test "THE DOTTED PATH IS BUILT ALL THE WAY DOWN, SO A NAMESPACE-QUALIFIED CALL MATCHES ITS OWN ROW" {
    qualified := SenMember(SenMember(SenMember(SenIdentifier("System"), "IO"), "File"), "Open")
    assert SystemsExpressionNames.CallTarget(qualified) == "System.IO.File.Open"
}

test "PARENTHESES ARE TRANSPARENT TO A CALL TARGET" {
    wrapped: Expression = new ParenthesizedExpression(SenIdentifier("handler"), 1, 1)
    assert SystemsExpressionNames.CallTarget(wrapped) == "handler"

    twice: Expression = new ParenthesizedExpression(new ParenthesizedExpression(SenMember(SenIdentifier("Volatile"), "Read"), 1, 1), 1, 1)
    assert SystemsExpressionNames.CallTarget(twice) == "Volatile.Read"
}

test "A CALLEE THAT IS NOT WRITTEN AS A NAME HAS NO TARGET AT ALL" {
    // The analyzer reports these as `<dynamic call>` rather than inventing a name, so the null is
    // load-bearing and not an omission.
    assert SystemsExpressionNames.CallTarget(SenIndex("handlers")) == null
    assert SystemsExpressionNames.CallTarget(SenCall(SenIdentifier("factory"))) == null
    assert SystemsExpressionNames.CallTarget(new ThisExpression(1, 1)) == null
}

test "THE RECEIVER FALLS BACK TO A POSITION KEY RATHER THAN COLLAPSING THE WHOLE TARGET TO NULL" {
    // `buffers[0].Dispose()` still classifies as a `.Dispose` call. If the member arm returned null
    // when its receiver had no name, every indexed receiver would silently lose the resource and
    // pool rules.
    indexed := SystemsExpressionNames.CallTarget(SenMember(SenIndex("buffers"), "Dispose"))
    assert indexed == "@13:17.Dispose"

    // `this.Reset()` reaches the same fallback through the OTHER key arm, and answers "this".
    assert SystemsExpressionNames.CallTarget(SenMember(new ThisExpression(1, 1), "Reset")) == "this.Reset"
}

// ------------------------------------------------------------------ the expression key

test "AN EXPRESSION KEY IS TOTAL: EVERY EXPRESSION HAS ONE" {
    assert SystemsExpressionNames.ExpressionKey(SenIdentifier("map")) == "map"
    assert SystemsExpressionNames.ExpressionKey(SenMember(SenIdentifier("state"), "Table")) == "state.Table"
    assert SystemsExpressionNames.ExpressionKey(new ThisExpression(1, 1)) == "this"
}

test "ANYTHING WITHOUT A WRITTEN PATH KEYS ON ITS OWN SOURCE POSITION" {
    // Unique per site, which is what stops two different receivers sharing one recorded fact.
    assert SystemsExpressionNames.ExpressionKey(SenIndex("rows")) == "@13:17"
    assert SystemsExpressionNames.ExpressionKey(SenCall(SenIdentifier("f"))) == "@7:11"

    // Two calls at DIFFERENT positions must not key alike.
    other: Expression = new CallExpression(SenIdentifier("f"), SenArgs(), null, 99, 2)
    assert SystemsExpressionNames.ExpressionKey(other) == "@99:2"
    assert SystemsExpressionNames.ExpressionKey(other) != SystemsExpressionNames.ExpressionKey(SenCall(SenIdentifier("f")))
}

test "PARENTHESES ARE NOT TRANSPARENT TO AN EXPRESSION KEY, AND THAT ASYMMETRY IS DELIBERATE" {
    // A call target is a NAME being matched against a table, so a wrapper cannot change which
    // function is meant. A key is a SITE, and `(x)` is written at a different place than `x`.
    wrapped: Expression = new ParenthesizedExpression(SenIdentifier("x"), 21, 4)
    assert SystemsExpressionNames.ExpressionKey(wrapped) == "@21:4"
    assert SystemsExpressionNames.CallTarget(wrapped) == "x"
}

test "THE MEMBER ARM COMPOSES THE FALLBACK RATHER THAN STOPPING AT IT" {
    assert SystemsExpressionNames.ExpressionKey(SenMember(SenIndex("rows"), "Length")) == "@13:17.Length"
}

// ------------------------------------------------------------------ the three disagreements

test "THE CALL TARGET AND THE SYNTHETIC CALL NAME AGREE ON A BARE NAME AND DISAGREE ON EVERY DOTTED ONE" {
    bare := SenCall(SenIdentifier("compute"))
    assert SystemsExpressionNames.CallTarget(bare.Callee) == "compute"
    assert AnalyzerSyntheticCallFacts.GetCallTargetName(bare) == "compute"

    // The one that matters: folding these would turn `File.Open` into `Open`, and the resource
    // factory table — which is NOT simplified — would stop matching anything at all.
    dotted := SenCall(SenMember(SenIdentifier("File"), "Open"))
    assert SystemsExpressionNames.CallTarget(dotted.Callee) == "File.Open"
    assert AnalyzerSyntheticCallFacts.GetCallTargetName(dotted) == "Open"
    assert SystemsExpressionNames.CallTarget(dotted.Callee) != AnalyzerSyntheticCallFacts.GetCallTargetName(dotted)

    // And they disagree on the parenthesised form in the other direction: one sees through it.
    parenthesized := SenCall(new ParenthesizedExpression(SenIdentifier("handler"), 1, 1))
    assert SystemsExpressionNames.CallTarget(parenthesized.Callee) == "handler"
    assert AnalyzerSyntheticCallFacts.GetCallTargetName(parenthesized) == null
}

test "THE EXPRESSION KEY AND THE STABLE NULL PATH DISAGREE IN BOTH DIRECTIONS" {
    // They agree on the shapes both call stable.
    assert SystemsExpressionNames.ExpressionKey(SenIdentifier("map")) == "map"
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(SenIdentifier("map")) == "map"

    // (1) The key is TOTAL where the path is partial: a call has a key and no stable path.
    call: Expression = SenCall(SenIdentifier("f"))
    assert SystemsExpressionNames.ExpressionKey(call) == "@7:11"
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(call) == null

    // (2) The path sees THROUGH parentheses and the key does not.
    wrapped: Expression = new ParenthesizedExpression(SenIdentifier("x"), 21, 4)
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(wrapped) == "x"
    assert SystemsExpressionNames.ExpressionKey(wrapped) == "@21:4"
}

test "A NULL-CONDITIONAL HOP KEYS LIKE ANY OTHER MEMBER ACCESS HERE, AND HAS NO STABLE PATH" {
    // The third disagreement, and the one most likely to be "tidied": the systems tables must key a
    // `?.` receiver the same as a `.` receiver, because it is the same storage.
    conditional: Expression = new MemberAccessExpression(SenIdentifier("owner"), "Buffer", true, 7, 11)
    assert SystemsExpressionNames.ExpressionKey(conditional) == "owner.Buffer"
    assert AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(conditional) == null
}

test "NEITHER PROJECTION IS THE TYPE-NAME SIMPLIFIER" {
    // `SimpleName` takes the LAST segment of a string; the call target BUILDS the dotted string.
    // They are used together — the span width of an unknown-external-call finding is the simple name
    // of the target this owner produced — so a fold in either direction would be visible.
    target := SystemsExpressionNames.CallTarget(SenMember(SenMember(SenIdentifier("System"), "IO"), "File"))
    assert target == "System.IO.File"
    assert SystemsTypeNames.SimpleName(target) == "File"
    assert SystemsTypeNames.SimpleName(target) != target
}
