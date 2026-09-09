namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE THREE STEPS THE STATEMENT-SEQUENCE WALK CANNOT TAKE FOR ITSELF.
//
// This walk owns what a SEQUENCE of statements means — the last policy the statement territory held
// outside an owner. Three facts, and all three used to be written by hand in `Analyzer.cs`:
//
//   1. THE UNREACHABLE-CODE RULE. Statements in a list are walked in order, and the statement after
//      one that ALWAYS LEAVES is reported. The rule has three parts that are each a decision and not
//      bookkeeping: only the FIRST unreachable statement is reported, the walk STOPS there rather
//      than continuing to report its siblings, and everything below it is never analysed at all — so
//      a name error inside dead code is silent. The judgement it asks is
//      `AnalyzerStatementTermination.AlwaysReturns`, which is asked AFTER the statement has been
//      analysed rather than before; the predicate is pure over the AST so the order cannot change the
//      answer, and it is preserved anyway because a reader comparing the two walks should see the
//      same shape.
//   2. WHAT A BLOCK IS. A `{ … }` statement opens a scope of kind BLOCK at the BLOCK'S OWN position —
//      not at the position of whatever introduced it — walks its statements WITH the unreachable
//      rule, and closes the scope. That is the whole semantic content of a block, and it is what
//      makes the unreachable rule apply inside braces but not to a bare loop body.
//   3. WHAT `alloc`, `allow` AND `unsafe` ARE: TRANSPARENT. Each is a systems-facing wrapper that
//      contributes NOTHING semantically — no scope of its own, no rule of its own, no name of its
//      own. Its body is handed back to the statement dispatch as a single statement, and because that
//      body is a `BlockStatement`, the dispatch's block arm is what gives it its scope. Routing the
//      body through the dispatch rather than straight into this walk's own block form is deliberate:
//      the dispatch also advances the analyzer's line cursor, and the wrapper's line and its brace's
//      line are not always the same one.
//
// What it cannot do is analyse a statement — that re-enters the statement dispatch, which is
// `Analyzer.cs`'s — or open and close a scope on the analyzer's scope stack. So it ASKS: one request
// at a time, each naming a kind and carrying every value the step needs. Nothing here is a policy the
// driver may reinterpret.
//
// THIS IS THE ESTATE'S FIRST WALK THAT ASKS NO QUESTIONS, AND SO IT HAS NO `Supply`. Every other walk
// suspends because it needs the ANSWER — a type, an escape flag, a recorded binding — before it can
// choose its next step. Not one of this walk's three operations answers anything: analysing a
// statement, opening a scope and closing one are all orders. So the driver hands nothing back, the
// state carries no pending slot, and `NextStep` advances the phase on its own. A `Supply` that folded
// nothing in would be a round trip that exists only to look like its neighbours.
//
// The kinds:
//   1  analyse ONE statement, which re-enters the statement dispatch and therefore this walk itself
//      whenever that statement is a block. Every `Begin` hands back a fresh state, so a nested block
//      suspends independently of the one that contains it, and the walk needs no stack of its own.
//   2  open a BLOCK scope on the analyzer's scope stack at `Line` / `Column`.
//   3  close the scope kind 2 opened.
class StatementSequenceRequest {
    Kind: int
    Body: Statement?
    Line: int
    Column: int

    constructor(kind: int) {
        Kind = kind
        Body = null
        Line = 0
        Column = 0
    }
}

// THE SEQUENCE'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves all three forms, because ONE driver serves them all. `Form` selects which:
//   0  a bare statement LIST — a test, setup or teardown body, an `assert throws` body, a declared
//      function's body, a `switch` case's body. No scope: whoever asked for the list already owns
//      one, or deliberately wants none.
//   1  a BLOCK statement — form 0 with a scope of its own, opened at `Line` / `Column` before the
//      first statement and closed after the last.
//   2  a TRANSPARENT wrapper's body — exactly one statement, no scope, no unreachable rule.
//
// `Phase` is the walk's program counter. 0 is the entry that chooses the form. 1 is the list's step:
// it either finishes, reports the first unreachable statement and finishes, or hands out the
// statement at `Index`. 2 folds that statement's termination judgement in and advances `Index`. 3 is
// the exit that closes a block's scope. 99 is done for all three forms.
//
// `Terminated` is the unreachable rule's whole memory: it is set by the first statement in the list
// that always leaves, and once it is set the next statement is reported and the walk ends. It is the
// reason the rule reports ONE diagnostic rather than one per dead statement.
class StatementSequenceState {
    formValue: int
    statementsValue: List<Statement>?
    bodyValue: Statement?
    lineValue: int
    columnValue: int

    Form: int => formValue
    Statements: List<Statement>? => statementsValue
    Body: Statement? => bodyValue
    Line: int => lineValue
    Column: int => columnValue

    Phase: int
    Index: int
    Terminated: bool

    constructor(form: int, statements: List<Statement>?, body: Statement?, line: int, column: int) {
        formValue = form
        statementsValue = statements
        bodyValue = body
        lineValue = line
        columnValue = column
        Phase = 0
        Index = 0
        Terminated = false
    }
}

// WHAT A SEQUENCE OF STATEMENTS MEANS.
//
// The walk holds exactly two collaborators — the span reader, for where an unreachable statement is
// underlined, and the diagnostic sink, for the one report it can raise. Both are constructed once by
// `Analyzer.cs` and never rebuilt with the metadata load context, so holding them is safe in the way
// holding the assignability oracle or the CLR conversion funnel would not be.
//
// The termination judgement is a STATIC call rather than a held collaborator, because
// `AnalyzerStatementTermination` reads no analysis state: the same three rules ask it from three
// places that are far apart in the analysis and none of them may get a different answer.
class AnalyzerStatementSequence {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans) {
        diagnosticsValue = diagnostics
        spansValue = spans
    }

    // A BARE STATEMENT LIST. The caller already owns whatever scope the list runs in — a test body
    // runs in the scope the test declaration opened, an `assert throws` body in the one that walk
    // opened, a declared function's body in its FUNCTION scope — so this form opens none. The
    // unreachable rule still applies: it is a property of a LIST, not of a brace.
    func BeginList(statements: List<Statement>): StatementSequenceState {
        return new StatementSequenceState(0, statements, null, 0, 0)
    }

    // A BLOCK STATEMENT. The scope opens at the BLOCK'S own line and column, which is what puts a
    // nested block's recorded semantic scope at the brace rather than at the statement that led to
    // it, and closes after the last statement — including when the unreachable rule ended the list
    // early, because a scope that opened must close on every path.
    func BeginBlock(block: BlockStatement): StatementSequenceState {
        return new StatementSequenceState(1, block.Statements, null, block.Line, block.Column)
    }

    // A TRANSPARENT WRAPPER'S BODY — `alloc { … }`, `allow(…) { … }` and `unsafe { … }`. The wrapper
    // itself means nothing to the semantic phase; its body is one statement handed back to the
    // dispatch. All three bodies are `BlockStatement`s, so what they get is the block form — reached
    // through the dispatch, not by calling `BeginBlock` here, because the dispatch also advances the
    // analyzer's line cursor for the inner block.
    func BeginTransparent(body: Statement): StatementSequenceState {
        return new StatementSequenceState(2, null, body, 0, 0)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this sequence is finished. Every phase
    // either decides something and advances, or emits exactly one request. There is no `Supply`
    // because no step answers anything, so the phase moves on the next call rather than on a fold.
    func NextStep(state: StatementSequenceState): StatementSequenceRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    func Advance(state: StatementSequenceState): StatementSequenceRequest? {
        if state.Phase == 0 {
            return EnterSequence(state)
        }

        if state.Phase == 1 {
            return NextListStatement(state)
        }

        if state.Phase == 2 {
            return FoldTermination(state)
        }

        return ExitSequence(state)
    }

    // PHASE 0. The transparent form is one statement and nothing else. The block form opens its scope
    // before any statement is walked, which is what puts the block's own locals inside it. The bare
    // list opens nothing and falls straight into the walk.
    func EnterSequence(state: StatementSequenceState): StatementSequenceRequest? {
        if state.Form == 2 {
            state.Phase = 99
            transparentBody := state.Body
            if transparentBody == null {
                return null
            }

            return SingleStatement(transparentBody)
        }

        state.Phase = 1
        if state.Form == 1 {
            return ScopeStep(2, state.Line, state.Column)
        }

        return null
    }

    // PHASE 1. The list's step. A list that has run out finishes. A list whose previous statement
    // ALWAYS LEAVES reports THIS statement as unreachable and finishes — one report, and nothing
    // below it is analysed. Otherwise the statement at `Index` is handed out.
    func NextListStatement(state: StatementSequenceState): StatementSequenceRequest? {
        statements := state.Statements
        if statements == null {
            state.Phase = 3
            return null
        }

        if state.Index >= statements.Count {
            state.Phase = 3
            return null
        }

        current := statements[state.Index]
        if state.Terminated {
            ReportUnreachable(current)
            state.Phase = 3
            return null
        }

        state.Phase = 2
        return SingleStatement(current)
    }

    // PHASE 2. The judgement is asked about the statement that was JUST analysed, exactly where
    // `Analyzer.cs` asked it. Once it answers yes, `Terminated` stays set for the rest of the list.
    func FoldTermination(state: StatementSequenceState): StatementSequenceRequest? {
        statements := state.Statements
        if statements != null {
            if AnalyzerStatementTermination.AlwaysReturns(statements[state.Index]) {
                state.Terminated = true
            }
        }

        state.Index = state.Index + 1
        state.Phase = 1
        return null
    }

    // PHASE 3. A block closes the scope it opened. Nothing else has one to close.
    func ExitSequence(state: StatementSequenceState): StatementSequenceRequest? {
        state.Phase = 99
        if state.Form == 1 {
            return ScopeStep(3, 0, 0)
        }

        return null
    }

    // NL312. The span is the statement's own diagnostic span — the expression inside an expression
    // statement, the NAME inside a local declaration, the keyword otherwise — so the squiggle lands
    // on what the developer wrote rather than on the whole dead region.
    func ReportUnreachable(statement: Statement) {
        span := spansValue.GetStatementDiagnosticSpan(statement)
        diagnosticsValue.Report(ErrorCode.UnreachableStatement, "This code will never run — there's a 'return' or 'throw' above it", span.Line, span.Column, null, span.Length)
    }

    static func SingleStatement(body: Statement): StatementSequenceRequest {
        request := new StatementSequenceRequest(1)
        request.Body = body
        return request
    }

    static func ScopeStep(kind: int, line: int, column: int): StatementSequenceRequest {
        request := new StatementSequenceRequest(kind)
        request.Line = line
        request.Column = column
        return request
    }
}
