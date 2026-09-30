namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Native contracts for CALLING A LOCAL FUNCTION READS WHAT ITS BODY READS.
//
// A local function is visible throughout its block, so it may be CALLED above its declaration; what
// must not happen is for that call to run before the variables the body reads have values. The
// question is asked at the CALL and not in the body, because the same body is legal after the
// variable is assigned and illegal before it — C# reports CS0165 at the invocation for the same
// reason.
//
// The walk is `AnalyzerDefiniteAssignment`'s own, re-run in COLLECTION mode, so these contracts are
// about the three decisions this owner makes on top of it: which calls the rule is about at all,
// what the collected reads are judged against, and what a call reached while ALREADY collecting
// does.
func CaptureBlock(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 1, 1)
}

func CaptureLocalFunction(name: string, body: BlockStatement, line: int): Statement {
    declaration := new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line, 5)
    statement: Statement = new LocalFunctionStatement(declaration, line, 1)
    return statement
}

func CaptureReadOf(name: string): BlockStatement {
    statements := new List<Statement>()
    read: Statement = new ExpressionStatement(new IdentifierExpression(name, 4, 9), 4, 9)
    statements.Add(read)
    return CaptureBlock(statements)
}

func CaptureState(candidate: string?, assigned: string?): DefiniteAssignmentState {
    state := new DefiniteAssignmentState()
    if candidate != null {
        state.Candidates.Add(candidate)
    }

    if assigned != null {
        state.Assigned.Add(assigned)
    }

    return state
}

func CaptureErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

func CaptureSink(errors: List<CompilerError>): AnalyzerDiagnosticSink {
    return new AnalyzerDiagnosticSink(errors, new AnalyzerProjectSourceProvider())
}

test "A CALL TO A NAME THAT IS NOT A LOCAL FUNCTION IS NOT THIS RULE'S BUSINESS" {
    state := CaptureState("total", null)

    assert AnalyzerLocalFunctionCaptures.BodyToRead("Console", state) == null
}

test "A BLOCK'S LOCAL FUNCTIONS ARE COLLECTED BY NAME AND THEIR BODIES ARE WHAT IS READ" {
    state := new DefiniteAssignmentState()
    statements := new List<Statement>()
    statements.Add(CaptureLocalFunction("readIt", CaptureReadOf("total"), 3))

    AnalyzerLocalFunctionCaptures.Collect(statements, state)

    body := AnalyzerLocalFunctionCaptures.BodyToRead("readIt", state)
    assert body != null
    assert body.Statements.Count == 1
}

test "A CALLEE ALREADY BEING READ HIGHER UP THE SAME CYCLE IS SKIPPED" {
    state := new DefiniteAssignmentState()
    statements := new List<Statement>()
    statements.Add(CaptureLocalFunction("even", CaptureReadOf("total"), 3))
    AnalyzerLocalFunctionCaptures.Collect(statements, state)

    state.Active.Add("even")

    // Without this guard a mutually recursive pair re-enters each other forever. The OUTER call
    // already asked the question for the whole cycle.
    assert AnalyzerLocalFunctionCaptures.BodyToRead("even", state) == null
}

test "THE SUB-WALK CARRIES THE CALLER'S ASSIGNED SET AND A COPY OF ITS CANDIDATES" {
    state := CaptureState("total", "other")

    inner := AnalyzerLocalFunctionCaptures.BeginRead(state)

    assert inner.Candidates.Contains("total")
    assert inner.Assigned.Contains("other")
    assert inner.Collected != null

    // The candidate set is COPIED, so a local the callee declares for itself never joins the
    // caller's tracking; `LocalFunctions` and `Active` are SHARED, because the cycle guard has to
    // span the whole chain of calls.
    inner.Candidates.Add("calleeLocal")
    assert !state.Candidates.Contains("calleeLocal")
    inner.Active.Add("even")
    assert state.Active.Contains("even")
}

test "A COLLECTED READ THE CALLER IS NOT TRACKING SAYS NOTHING" {
    errors := CaptureErrors()
    state := CaptureState("total", null)
    inner := AnalyzerLocalFunctionCaptures.BeginRead(state)
    inner.Collected.Add("somethingElse")

    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), inner, "readIt", new IdentifierExpression("readIt", 9, 10), state)

    // Only a name the CALLER is tracking and has not assigned is reported here — a local of the
    // callee is reported by the callee's own definite-assignment walk.
    assert errors.Count == 0
}

test "A COLLECTED READ THE CALLER HAS ALREADY ASSIGNED SAYS NOTHING" {
    errors := CaptureErrors()
    state := CaptureState("total", "total")
    inner := AnalyzerLocalFunctionCaptures.BeginRead(state)
    inner.Collected.Add("total")

    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), inner, "readIt", new IdentifierExpression("readIt", 9, 10), state)

    assert errors.Count == 0
}

test "AN UNASSIGNED READ IS NL304 AT THE CALL, NAMING THE VARIABLE AND THE FUNCTION" {
    errors := CaptureErrors()
    state := CaptureState("total", null)
    inner := AnalyzerLocalFunctionCaptures.BeginRead(state)
    inner.Collected.Add("total")

    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), inner, "readIt", new IdentifierExpression("readIt", 9, 10), state)

    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.DefiniteAssignmentError
    assert errors[0].Line == 9
    assert errors[0].Column == 10
    assert errors[0].Length == 6
    assert errors[0].Message == "'total' is read by local function 'readIt' and has not been assigned a value on every path that reaches this call"
    assert errors[0].Suggestion == "Assign 'total' before calling 'readIt' here, or give it an initial value where you declare it."
}

test "TWO UNASSIGNED READS ARE REPORTED IN SORTED ORDER, NOT IN READ ORDER" {
    errors := CaptureErrors()
    state := new DefiniteAssignmentState()
    state.Candidates.Add("zeta")
    state.Candidates.Add("alpha")
    inner := AnalyzerLocalFunctionCaptures.BeginRead(state)
    inner.Collected.Add("zeta")
    inner.Collected.Add("alpha")

    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), inner, "readIt", new IdentifierExpression("readIt", 9, 10), state)

    assert errors.Count == 2
    assert errors[0].Message.StartsWith("'alpha'")
    assert errors[1].Message.StartsWith("'zeta'")
}

test "THE SAME CALL REPORTS THE SAME VARIABLE ONCE" {
    errors := CaptureErrors()
    state := CaptureState("total", null)
    callee := new IdentifierExpression("readIt", 9, 10)

    first := AnalyzerLocalFunctionCaptures.BeginRead(state)
    first.Collected.Add("total")
    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), first, "readIt", callee, state)
    second := AnalyzerLocalFunctionCaptures.BeginRead(state)
    second.Collected.Add("total")
    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), second, "readIt", callee, state)

    assert errors.Count == 1
}

test "A CALL REACHED WHILE ALREADY COLLECTING REPORTS NOTHING AND CONTRIBUTES EVERYTHING" {
    errors := CaptureErrors()
    outer := CaptureState("total", null)
    collecting := AnalyzerLocalFunctionCaptures.BeginRead(outer)
    inner := AnalyzerLocalFunctionCaptures.BeginRead(collecting)
    inner.Collected.Add("total")

    AnalyzerLocalFunctionCaptures.ReportUnassignedReads(CaptureSink(errors), inner, "inner", new IdentifierExpression("inner", 5, 16), collecting)

    // `outer` calling `inner` is a read BY `outer`, so the name travels outwards to whoever called
    // `outer` — the squiggle belongs on that call, not on the one written inside a body that is
    // merely being inspected.
    assert errors.Count == 0
    assert collecting.Collected.Contains("total")
}
