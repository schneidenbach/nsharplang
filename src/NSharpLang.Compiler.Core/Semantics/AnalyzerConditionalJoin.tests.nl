namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Native contracts for the join that decides what is true after a conditional.
//
// THE FAILURE MODES POINT IN BOTH DIRECTIONS AND BOTH ARE PINNED. Too little and the census idiom
// squiggles a value both paths just proved non-null; too much and a fact one path never established
// is handed to the code below as though it had. So the meet is pinned arm by arm, the veto that
// stops a join from taking back a proof the enclosing flow still holds is pinned on its own, and the
// branch-local filter is pinned in BOTH of its cases — a name the branch declared and nothing else
// binds is dropped, and a name the branch merely narrowed is kept.
func JoinFactText(facts: Dictionary<string, NullState>): string {
    keys := new List<string>()
    for entry in facts {
        keys.Add(entry.Key)
    }

    keys.Sort(StringComparer.Ordinal)
    rendered := ""
    index := 0
    while index < keys.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + keys[index] + "=" + NullStateFacts.GetDiagnosticText(facts[keys[index]])
        index = index + 1
    }

    return rendered
}

func JoinNarrowingText(narrowings: List<FlowNarrowing>): string {
    facts := new Dictionary<string, NullState>(StringComparer.Ordinal)
    for narrowing in narrowings {
        facts[narrowing.Path] = narrowing.NullState
    }

    return JoinFactText(facts)
}

func JoinFactsOf(pairs: string): Dictionary<string, NullState> {
    facts := new Dictionary<string, NullState>(StringComparer.Ordinal)
    if pairs.Length == 0 {
        return facts
    }

    for pair in pairs.Split(",") {
        parts := pair.Split("=")
        facts[parts[0]] = JoinStateOf(parts[1])
    }

    return facts
}

func JoinStateOf(text: string): NullState {
    if text == "null" {
        return NullState.Null
    }

    if text == "maybe-null" {
        return NullState.MaybeNull
    }

    if text == "not-null" {
        return NullState.NotNull
    }

    if text == "oblivious" {
        return NullState.Oblivious
    }

    return NullState.Unknown
}

// A stack with one enclosing scope and, on top of it, a BRANCH scope holding the given facts — the
// exact shape phase 33 of the `if` walk reads.
func JoinStackWithBranch(enclosingFacts: string, branchFacts: string): AnalyzerScopeStack {
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Block), 1, 1)
    for entry in JoinFactsOf(enclosingFacts) {
        scopes.Peek().NullStates[entry.Key] = entry.Value
    }

    scopes.Push(model, new Scope(ScopeKind.Block), 2, 1)
    for entry in JoinFactsOf(branchFacts) {
        scopes.Peek().NullStates[entry.Key] = entry.Value
    }

    return scopes
}

func JoinIfOver(condition: Expression, thenStatement: Statement, elseStatement: Statement?): IfStatement {
    return new IfStatement(condition, thenStatement, elseStatement, 1, 1)
}

func JoinBlockOf(statements: List<Statement>): Statement {
    block: Statement = new BlockStatement(statements, 1, 1)
    return block
}

func JoinOneStatementBlock(statement: Statement): Statement {
    statements := new List<Statement>()
    statements.Add(statement)
    return JoinBlockOf(statements)
}

func JoinBreak(): Statement {
    statement: Statement = new BreakStatement(2, 1)
    return statement
}

func JoinEmptyBlock(): Statement {
    return JoinBlockOf(new List<Statement>())
}

test "TWO PATHS THAT AGREE ANSWER WHAT THEY AGREE ON" {
    assert AnalyzerConditionalJoin.Meet(NullState.NotNull, NullState.NotNull) == NullState.NotNull
    assert AnalyzerConditionalJoin.Meet(NullState.Null, NullState.Null) == NullState.Null
    assert AnalyzerConditionalJoin.Meet(NullState.MaybeNull, NullState.MaybeNull) == NullState.MaybeNull
}

test "TWO DEFINITE ANSWERS THAT DISAGREE ARE AN UNCERTAINTY, NOT AN ERROR" {
    assert AnalyzerConditionalJoin.Meet(NullState.NotNull, NullState.Null) == NullState.MaybeNull
    assert AnalyzerConditionalJoin.Meet(NullState.Null, NullState.NotNull) == NullState.MaybeNull
    assert AnalyzerConditionalJoin.Meet(NullState.NotNull, NullState.MaybeNull) == NullState.MaybeNull
    assert AnalyzerConditionalJoin.Meet(NullState.MaybeNull, NullState.Null) == NullState.MaybeNull
}

test "unknown IS THE ABSENCE OF AN ANSWER AND SWALLOWS THE MEET; oblivious YIELDS TO ONE" {
    assert AnalyzerConditionalJoin.Meet(NullState.Unknown, NullState.NotNull) == NullState.Unknown
    assert AnalyzerConditionalJoin.Meet(NullState.Null, NullState.Unknown) == NullState.Unknown
    assert AnalyzerConditionalJoin.Meet(NullState.Oblivious, NullState.NotNull) == NullState.NotNull
    assert AnalyzerConditionalJoin.Meet(NullState.MaybeNull, NullState.Oblivious) == NullState.MaybeNull
}

test "ONLY A PROOF CAN BE WEAKENED — maybe-null, unknown AND oblivious ARE NOT PROOFS" {
    assert AnalyzerConditionalJoin.IsWeakerThan(NullState.MaybeNull, NullState.NotNull)
    assert AnalyzerConditionalJoin.IsWeakerThan(NullState.MaybeNull, NullState.Null)
    assert AnalyzerConditionalJoin.IsWeakerThan(NullState.NotNull, NullState.Null)
    assert !AnalyzerConditionalJoin.IsWeakerThan(NullState.NotNull, NullState.NotNull)
    assert !AnalyzerConditionalJoin.IsWeakerThan(NullState.Null, NullState.MaybeNull)
    assert !AnalyzerConditionalJoin.IsWeakerThan(NullState.Null, NullState.Unknown)
    assert !AnalyzerConditionalJoin.IsWeakerThan(NullState.MaybeNull, NullState.Oblivious)
}

test "A BRANCH'S EXIT FACTS ARE ITS OWN SCOPE'S TABLE, AND NOT THE ENCLOSING FLOW'S" {
    scopes := JoinStackWithBranch("outer=not-null", "inner=null")

    facts := AnalyzerConditionalJoin.ExitFacts(scopes, scopes.Peek())

    // Only what the BRANCH recorded. A path the branch never touched is one the enclosing flow still
    // speaks for, and the join must not answer for it.
    assert JoinFactText(facts) == "inner=null"
}

test "A NAME THE BRANCH DECLARED AND NOTHING OUTSIDE IT BINDS DIES WITH THE BRANCH" {
    scopes := JoinStackWithBranch("", "local=not-null,shared=not-null")
    scopes.Peek().Symbols["local"] = BuiltInTypes.String
    scopes.Peek().Symbols["shared"] = BuiltInTypes.String
    scopes.GlobalScope().Symbols["shared"] = BuiltInTypes.String

    facts := AnalyzerConditionalJoin.ExitFacts(scopes, scopes.Peek())

    // `local` is a branch-local and is gone at the closing brace. `shared` is written into the branch
    // scope's symbol table too — that is what a TYPE narrowing does — but an enclosing scope binds
    // it, so it is an outer binding the branch spoke about and its fact outlives the branch.
    assert JoinFactText(facts) == "shared=not-null"
}

test "A MEMBER PATH IS JUDGED BY ITS ROOT NAME" {
    assert AnalyzerConditionalJoin.RootName("doc") == "doc"
    assert AnalyzerConditionalJoin.RootName("doc.Error.Message") == "doc"

    scopes := JoinStackWithBranch("", "doc.Error=not-null")
    scopes.Peek().Symbols["doc"] = BuiltInTypes.String

    // The branch declared its OWN `doc`, so a fact about `doc.Error` is a fact about that one.
    assert JoinFactText(AnalyzerConditionalJoin.ExitFacts(scopes, scopes.Peek())) == ""
}

test "THE IMPLICIT ELSE PATH KNOWS EXACTLY WHAT THE CONDITION PROVED WHEN IT WAS FALSE" {
    narrowings := new List<FlowNarrowing>()
    narrowings.Add(new FlowNarrowing("list", null, NullState.NotNull))
    narrowings.Add(new FlowNarrowing("other", null, NullState.Null))

    assert JoinFactText(AnalyzerConditionalJoin.NarrowingFacts(narrowings)) == "list=not-null,other=null"
    assert JoinFactText(AnalyzerConditionalJoin.NarrowingFacts(null)) == ""
}

test "ONLY A PATH BOTH SIDES SPEAK FOR IS JOINED" {
    scopes := JoinStackWithBranch("", "")

    joined := AnalyzerConditionalJoin.JoinFacts(scopes, JoinFactsOf("both=not-null,thenOnly=not-null"), JoinFactsOf("both=not-null,elseOnly=null"))

    // `thenOnly` and `elseOnly` are each left to the enclosing flow — or, when a branch assignment
    // invalidated its fact, to the declared type's own default.
    assert JoinNarrowingText(joined) == "both=not-null"
}

test "THE CENSUS SHAPE: A BRANCH THAT CREATED THE VALUE MEETS A FALSE SET THAT PROVED IT" {
    scopes := JoinStackWithBranch("", "")

    joined := AnalyzerConditionalJoin.JoinFacts(scopes, JoinFactsOf("list=not-null"), JoinFactsOf("list=not-null"))

    assert JoinNarrowingText(joined) == "list=not-null"
}

test "A BRANCH THAT RE-ASSIGNED A MAYBE-NULL VALUE KEEPS THE JOIN MAYBE-NULL" {
    scopes := JoinStackWithBranch("", "")

    joined := AnalyzerConditionalJoin.JoinFacts(scopes, JoinFactsOf("list=maybe-null"), JoinFactsOf("list=not-null"))

    assert JoinNarrowingText(joined) == "list=maybe-null"
}

test "A JOIN MAY NOT TAKE BACK A PROOF THE ENCLOSING FLOW STILL HOLDS" {
    // The redundant re-check written after a guard clause: `if x == null { return }` left `x`
    // not-null, and `if x != null { … }` below it must not take that back. An assignment would have
    // invalidated the enclosing fact — a path the enclosing flow can still answer for is a path
    // neither branch assigned.
    scopes := JoinStackWithBranch("x=not-null", "")

    joined := AnalyzerConditionalJoin.JoinFacts(scopes, JoinFactsOf("x=not-null"), JoinFactsOf("x=null"))

    assert JoinNarrowingText(joined) == ""
}

test "A BRANCH THAT IS THE ONLY PATH LEFT IS INHERITED WHOLE, NOT JOINED" {
    inherited := AnalyzerConditionalJoin.InheritedFacts(JoinFactsOf("list=not-null,other=null"))

    assert JoinNarrowingText(inherited) == "list=not-null,other=null"
}

test "MORE THAN TWO PATHS MEET BY FOLDING, AND ONLY A PATH ALL OF THEM SPEAK FOR SURVIVES" {
    first := JoinFactsOf("a=not-null,b=not-null,c=not-null")
    second := JoinFactsOf("a=not-null,b=null")
    third := JoinFactsOf("a=not-null,b=null,c=not-null")

    met := AnalyzerConditionalJoin.MeetFacts(AnalyzerConditionalJoin.MeetFacts(first, second), third)

    // `c` drops out because the second path never mentioned it.
    assert JoinFactText(met) == "a=not-null,b=maybe-null"
}

test "THE PATH ON WHICH NO ARM MATCHED KNOWS WHAT THE FLOW OUTSIDE KNEW" {
    scopes := JoinStackWithBranch("kept=not-null", "")

    surviving := AnalyzerConditionalJoin.SurvivingFacts(scopes, JoinFactsOf("kept=null,assigned=not-null"))

    // `assigned` has no surviving fact — an arm's assignment invalidated it — so it drops out of the
    // meet, which is the right answer: the unmatched path never ran that assignment.
    assert JoinFactText(surviving) == "kept=not-null"
}

test "A break ANYWHERE IN A STATEMENT LIST IS A break FOR THE LIST" {
    statements := new List<Statement>()
    assert !AnalyzerConditionalJoin.ContainsListBreak(statements)

    statements.Add(JoinBreak())
    assert AnalyzerConditionalJoin.ContainsListBreak(statements)
}

test "A LOOP THAT CONTAINS A break PROVES NOTHING ON ITS WAY OUT" {
    assert AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(JoinBreak()))
    assert !AnalyzerConditionalJoin.ContainsLoopBreak(JoinEmptyBlock())
    assert !AnalyzerConditionalJoin.ContainsLoopBreak(null)
}

test "A break INSIDE A BRANCH OR A try STILL BELONGS TO THE LOOP" {
    guarded: Statement = JoinIfOver(new BoolLiteralExpression(true, 1, 1), JoinOneStatementBlock(JoinBreak()), null)
    assert AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(guarded))

    elseGuarded: Statement = JoinIfOver(new BoolLiteralExpression(true, 1, 1), JoinEmptyBlock(), JoinOneStatementBlock(JoinBreak()))
    assert AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(elseGuarded))

    tryStatement: Statement = new TryStatement(JoinOneStatementBlock(JoinBreak()) as BlockStatement, new List<CatchClause>(), null, 1, 1)
    assert AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(tryStatement))
}

test "A break IN A NESTED LOOP BELONGS TO THAT LOOP AND NEVER REACHES THIS ONE" {
    nested: Statement = new WhileStatement(new BoolLiteralExpression(true, 1, 1), JoinOneStatementBlock(JoinBreak()), 1, 1)
    assert !AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(nested))

    nestedFor: Statement = new ForStatement(null, null, null, JoinOneStatementBlock(JoinBreak()), 1, 1)
    assert !AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(nestedFor))

    nestedForeach: Statement = new ForeachStatement("item", new IdentifierExpression("items", 1, 1), JoinOneStatementBlock(JoinBreak()), 1, 1)
    assert !AnalyzerConditionalJoin.ContainsLoopBreak(JoinOneStatementBlock(nestedForeach))
}
