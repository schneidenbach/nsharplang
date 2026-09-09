namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A SEQUENCE OF STATEMENTS MEANS.
//
// The three facts pinned here were written by hand in `Analyzer.cs` — a `foreach` with a `terminated`
// flag, a three-line block arm, and three one-line transparent arms — so nothing named them and their
// behaviour was reachable only through end-to-end diagnostics. This is their first DIRECT pinning,
// and it is written around what is easy to get wrong:
//
// (1) THE UNREACHABLE RULE REPORTS ONCE AND THEN STOPS. Four dead statements produce ONE diagnostic,
// and — the part that is invisible from the diagnostic list — none of the four is ever handed to the
// driver, so a name error inside dead code is silent too. A rule that reported once but kept walking
// would look identical in the error list and be wrong.
//
// (2) A SCOPE THAT OPENS ALWAYS CLOSES, INCLUDING WHEN THE RULE ENDED THE LIST EARLY. The close is
// always the LAST step, in every shape, whether the list ran out, was cut short by dead code, or was
// empty to begin with.
//
// (3) TRANSPARENCY IS NOT THE BLOCK FORM. `alloc`, `allow` and `unsafe` hand their body BACK to the
// dispatch as one statement rather than walking its statements here, so a transparent form emits
// exactly one step and NEVER a scope step — even though every body it is given is a block.
//
// Every replayed step records the kind, what it carried and the error count AS THE STEP WAS HANDED
// OUT, so the window each operation happens in is pinned rather than asserted.
class SequenceHarness {
    Sequence: AnalyzerStatementSequence
    Errors: List<CompilerError>

    constructor(sequence: AnalyzerStatementSequence, errors: List<CompilerError>) {
        Sequence = sequence
        Errors = errors
    }
}

func SequenceDefault(): SequenceHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(Path.GetFullPath("statement-sequence-contract.nl"), null)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    return new SequenceHarness(new AnalyzerStatementSequence(diagnostics, spans), errors)
}

// A `print 1` statement, which the termination judgement answers FALSE for and which carries a
// position of its own.
func SequencePlain(line: int): Statement {
    value: Expression = new IntLiteralExpression("1", line, 7)
    statement: Statement = new PrintStatement(value, line, 1)
    return statement
}

// A bare `return`, which the termination judgement answers TRUE for.
func SequenceLeaving(line: int): Statement {
    statement: Statement = new ReturnStatement(null, line, 1)
    return statement
}

func SequenceEmpty(): List<Statement> {
    return new List<Statement>()
}

func SequenceBlock(statements: List<Statement>, line: int, column: int): BlockStatement {
    return new BlockStatement(statements, line, column)
}

// THE WHOLE PROTOCOL, REPLAYED. One row per step: the kind, the position it carried, the error count
// at the moment the step was handed out, and the line of the statement it carried. A step that moves,
// disappears, arrives, changes its operand or fires on the wrong side of a report is a row diff.
func SequenceReplay(harness: SequenceHarness, state: StatementSequenceState): string {
    transcript := ""
    step := harness.Sequence.NextStep(state)
    while step != null {
        if transcript.Length > 0 {
            transcript = transcript + ";"
        }

        transcript = transcript + "k" + step.Kind.ToString() + "@" + step.Line.ToString() + ":" + step.Column.ToString() + "/e" + harness.Errors.Count.ToString()
        body := step.Body
        if body != null {
            transcript = transcript + "/s" + body.Line.ToString()
        }

        step = harness.Sequence.NextStep(state)
    }

    return transcript
}

func SequenceErrorText(harness: SequenceHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

// ---- the bare list ---------------------------------------------------------------------------

test "A LIST HANDS OUT EVERY STATEMENT IN ORDER AND OPENS NO SCOPE" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(3))
    statements.Add(SequencePlain(4))
    statements.Add(SequencePlain(5))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    assert transcript == "k1@0:0/e0/s3;k1@0:0/e0/s4;k1@0:0/e0/s5"
    assert harness.Errors.Count == 0
}

test "AN EMPTY LIST ASKS FOR NOTHING AT ALL" {
    harness := SequenceDefault()

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(SequenceEmpty()))

    assert transcript == ""
    assert harness.Errors.Count == 0
}

test "A STATEMENT THAT ALWAYS LEAVES STILL RUNS; IT IS THE ONE AFTER IT THAT DIES" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(3))
    statements.Add(SequenceLeaving(4))
    statements.Add(SequencePlain(5))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    // The `return` on line 4 IS handed out. Line 5 never is, and the report is raised as the walk
    // ends rather than while a step is outstanding.
    assert transcript == "k1@0:0/e0/s3;k1@0:0/e0/s4"
    assert harness.Errors.Count == 1
}

test "THE UNREACHABLE REPORT IS NL312 WITH THE DEAD STATEMENT'S OWN SPAN" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequenceLeaving(4))
    statements.Add(SequencePlain(9))

    SequenceReplay(harness, harness.Sequence.BeginList(statements))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UnreachableStatement
    assert SequenceErrorText(harness, 0) == "This code will never run — there's a 'return' or 'throw' above it|9:1+1"
}

test "FOUR DEAD STATEMENTS PRODUCE ONE REPORT, AND NONE OF THE FOUR IS EVER WALKED" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequenceLeaving(4))
    statements.Add(SequencePlain(5))
    statements.Add(SequencePlain(6))
    statements.Add(SequencePlain(7))
    statements.Add(SequencePlain(8))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    assert transcript == "k1@0:0/e0/s4"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 5
}

test "A LIST WHOSE LAST STATEMENT LEAVES IS SILENT — THERE IS NOTHING AFTER IT" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(3))
    statements.Add(SequenceLeaving(4))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    assert transcript == "k1@0:0/e0/s3;k1@0:0/e0/s4"
    assert harness.Errors.Count == 0
}

test "A SECOND LEAVING STATEMENT DOES NOT RE-ARM THE RULE — THE FIRST ONE ENDED THE LIST" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequenceLeaving(3))
    statements.Add(SequenceLeaving(4))
    statements.Add(SequenceLeaving(5))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    assert transcript == "k1@0:0/e0/s3"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
}

// ---- the block form --------------------------------------------------------------------------

test "A BLOCK OPENS ITS SCOPE AT ITS OWN POSITION, WALKS ITS STATEMENTS, AND CLOSES" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(8))
    statements.Add(SequencePlain(9))

    transcript := SequenceReplay(harness, harness.Sequence.BeginBlock(SequenceBlock(statements, 7, 22)))

    assert transcript == "k2@7:22/e0;k1@0:0/e0/s8;k1@0:0/e0/s9;k3@0:0/e0"
}

test "AN EMPTY BLOCK STILL OPENS AND CLOSES A SCOPE" {
    harness := SequenceDefault()

    transcript := SequenceReplay(harness, harness.Sequence.BeginBlock(SequenceBlock(SequenceEmpty(), 4, 1)))

    assert transcript == "k2@4:1/e0;k3@0:0/e0"
}

test "A BLOCK CUT SHORT BY DEAD CODE STILL CLOSES ITS SCOPE, AND CLOSES IT AFTER THE REPORT" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequenceLeaving(5))
    statements.Add(SequencePlain(6))

    transcript := SequenceReplay(harness, harness.Sequence.BeginBlock(SequenceBlock(statements, 4, 3)))

    // The close carries error count 1: the report is raised BEFORE the scope closes, which is what
    // keeps the diagnostic inside the region it describes.
    assert transcript == "k2@4:3/e0;k1@0:0/e0/s5;k3@0:0/e1"
    assert harness.Errors.Count == 1
}

// ---- the transparent form --------------------------------------------------------------------

test "A TRANSPARENT WRAPPER EMITS EXACTLY ONE STATEMENT STEP AND NO SCOPE STEP" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(6))
    statements.Add(SequencePlain(7))
    body: Statement = SequenceBlock(statements, 5, 9)

    transcript := SequenceReplay(harness, harness.Sequence.BeginTransparent(body))

    // The BLOCK is handed back whole. Its two statements are the dispatch's business, not this
    // walk's, which is exactly what "the wrapper contributes nothing" means.
    assert transcript == "k1@0:0/e0/s5"
    assert harness.Errors.Count == 0
}

test "A TRANSPARENT WRAPPER APPLIES NO UNREACHABLE RULE OF ITS OWN" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequenceLeaving(6))
    statements.Add(SequencePlain(7))
    body: Statement = SequenceBlock(statements, 5, 9)

    transcript := SequenceReplay(harness, harness.Sequence.BeginTransparent(body))

    assert transcript == "k1@0:0/e0/s5"
    assert harness.Errors.Count == 0
}

// ---- the invariants --------------------------------------------------------------------------

test "BALANCE: EVERY SHAPE OPENS AS MANY SCOPES AS IT CLOSES, AND THE CLOSE IS ALWAYS LAST" {
    harness := SequenceDefault()
    running := SequenceEmpty()
    running.Add(SequencePlain(3))
    running.Add(SequencePlain(4))
    dead := SequenceEmpty()
    dead.Add(SequenceLeaving(3))
    dead.Add(SequencePlain(4))

    states := new List<StatementSequenceState>()
    states.Add(harness.Sequence.BeginList(SequenceEmpty()))
    states.Add(harness.Sequence.BeginList(running))
    states.Add(harness.Sequence.BeginList(dead))
    states.Add(harness.Sequence.BeginBlock(SequenceBlock(SequenceEmpty(), 2, 1)))
    states.Add(harness.Sequence.BeginBlock(SequenceBlock(running, 2, 1)))
    states.Add(harness.Sequence.BeginBlock(SequenceBlock(dead, 2, 1)))
    states.Add(harness.Sequence.BeginTransparent(SequenceBlock(running, 2, 1)))

    shapeIndex := 0
    while shapeIndex < states.Count {
        opens := 0
        closes := 0
        lastKind := 0
        step := harness.Sequence.NextStep(states[shapeIndex])
        while step != null {
            if step.Kind == 2 {
                opens = opens + 1
            }

            if step.Kind == 3 {
                closes = closes + 1
            }

            lastKind = step.Kind
            step = harness.Sequence.NextStep(states[shapeIndex])
        }

        assert opens == closes
        if opens > 0 {
            assert lastKind == 3
        }

        shapeIndex = shapeIndex + 1
    }
}

test "BALANCE: ONLY THE BLOCK FORM EVER TOUCHES THE SCOPE STACK" {
    harness := SequenceDefault()
    statements := SequenceEmpty()
    statements.Add(SequencePlain(3))

    listSteps := SequenceReplay(harness, harness.Sequence.BeginList(statements))
    transparentSteps := SequenceReplay(harness, harness.Sequence.BeginTransparent(SequencePlain(3)))
    blockSteps := SequenceReplay(harness, harness.Sequence.BeginBlock(SequenceBlock(statements, 2, 1)))

    assert !listSteps.Contains("k2")
    assert !listSteps.Contains("k3")
    assert !transparentSteps.Contains("k2")
    assert !transparentSteps.Contains("k3")
    assert blockSteps.Contains("k2")
    assert blockSteps.Contains("k3")
}

test "TWO SEQUENCES SUSPEND INDEPENDENTLY, WHICH IS WHAT MAKES A NESTED BLOCK WORK" {
    harness := SequenceDefault()
    outerStatements := SequenceEmpty()
    outerStatements.Add(SequencePlain(3))
    outerStatements.Add(SequencePlain(9))
    innerStatements := SequenceEmpty()
    innerStatements.Add(SequencePlain(5))
    innerStatements.Add(SequencePlain(6))

    outer := harness.Sequence.BeginBlock(SequenceBlock(outerStatements, 2, 1))
    inner := harness.Sequence.BeginBlock(SequenceBlock(innerStatements, 4, 5))

    // Interleave the two walks completely: open outer, open inner, drain inner, drain outer.
    outerOpen := harness.Sequence.NextStep(outer)
    innerOpen := harness.Sequence.NextStep(inner)
    innerRest := SequenceReplay(harness, inner)
    outerRest := SequenceReplay(harness, outer)

    assert outerOpen != null
    assert innerOpen != null
    assert outerOpen.Kind == 2
    assert outerOpen.Line == 2
    assert innerOpen.Kind == 2
    assert innerOpen.Line == 4
    assert innerRest == "k1@0:0/e0/s5;k1@0:0/e0/s6;k3@0:0/e0"
    assert outerRest == "k1@0:0/e0/s3;k1@0:0/e0/s9;k3@0:0/e0"
}

test "THE JUDGEMENT IS THE SHARED ONE — A LOOP DOES NOT TERMINATE A LIST" {
    harness := SequenceDefault()
    loopBody := SequenceEmpty()
    loopBody.Add(SequenceLeaving(4))
    body: Statement = SequenceBlock(loopBody, 3, 5)
    condition: Expression = new BoolLiteralExpression(true, 3, 11)
    loop: Statement = new WhileStatement(condition, body, 3, 1)
    statements := SequenceEmpty()
    statements.Add(loop)
    statements.Add(SequencePlain(6))

    transcript := SequenceReplay(harness, harness.Sequence.BeginList(statements))

    // `AnalyzerStatementTermination` deliberately answers NO for every loop, so the statement after
    // one is live. This walk must not second-guess it.
    assert transcript == "k1@0:0/e0/s3;k1@0:0/e0/s6"
    assert harness.Errors.Count == 0
}

// ---- the scope stack's two new members -------------------------------------------------------

test "A CLOSING SCOPE ENDS AT THE CURSOR THE WALK LAST NOTED" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    stack.Push(model, new Scope(ScopeKind.Block), 4, 1)

    stack.NoteLine(11)
    stack.Pop(model)

    assert model.Scopes.Count == 1
    assert model.Scopes[0].StartLine == 4
    assert model.Scopes[0].EndLine == 11
}

test "THE CURSOR STARTS AT ZERO AND Clear PUTS IT BACK" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    stack.NoteLine(42)
    stack.Clear()

    stack.Push(model, new Scope(ScopeKind.Block), 2, 1)
    stack.Pop(model)

    assert model.Scopes[0].EndLine == 0
}

test "A VARIABLE GOES AGAINST THE INNERMOST SEMANTIC SCOPE WHEN THERE IS ONE" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    stack.Push(model, new Scope(ScopeKind.Function), 1, 1)
    stack.Push(model, new Scope(ScopeKind.Block), 3, 1)

    stack.RecordVariable(model, "inner", BuiltInTypes.Int)

    // The INNERMOST scope answers, and the outer one does not. The flat table is written TOO —
    // `SemanticModel.RecordScopedVariable` records both, so a position-aware lookup and a bare name
    // lookup agree — which is why the choice this member makes is about the SCOPED table only.
    assert model.Scopes[1].Variables.ContainsKey("inner")
    assert !model.Scopes[0].Variables.ContainsKey("inner")
    assert model.Variables.ContainsKey("inner")
}

test "A VARIABLE GOES INTO THE FLAT TABLE WHEN NO SEMANTIC SCOPE IS OPEN" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()

    stack.RecordVariable(model, "loose", BuiltInTypes.Int)

    assert model.Variables.ContainsKey("loose")
    assert model.Scopes.Count == 0
}

test "A FUNCTION OBEYS THE SAME RULE, AGAINST THE OTHER TABLE" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    stack.Push(model, new Scope(ScopeKind.Function), 1, 1)
    stack.Push(model, new Scope(ScopeKind.Block), 3, 1)

    stack.RecordFunction(model, "helper", BuiltInTypes.Int)

    assert model.Scopes[1].Functions.ContainsKey("helper")
    assert !model.Scopes[0].Functions.ContainsKey("helper")
    assert !model.Scopes[1].Variables.ContainsKey("helper")
}

test "A FUNCTION GOES INTO THE FLAT TABLE WHEN NO SEMANTIC SCOPE IS OPEN" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()

    stack.RecordFunction(model, "loose", BuiltInTypes.Int)

    assert model.Functions.ContainsKey("loose")
    assert model.Scopes.Count == 0
}
