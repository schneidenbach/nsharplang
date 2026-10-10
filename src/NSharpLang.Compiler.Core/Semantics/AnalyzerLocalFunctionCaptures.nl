namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CALLING A LOCAL FUNCTION READS EVERY VARIABLE ITS BODY READS — and definite assignment is asked
// about them AT THE CALL.
//
// A local function's name is in scope throughout its block, so it may be called ABOVE its own
// declaration; what may NOT happen is for that call to run before the variables the body reads have
// values. C# calls this CS0165 at the invocation, and the reason it is the invocation rather than
// the body is that the body is one piece of code with many call sites: the same `readIt()` is legal
// after `total` is assigned and illegal before it, so the body cannot be the thing that is wrong.
//
// THE READ SET IS COMPUTED BY RE-RUNNING THE WALK THAT ALREADY KNOWS WHAT A READ IS. There is no
// second expression recursion here: `AnalyzerDefiniteAssignment` runs its own walk over the local
// function's body with `Collected` set, which turns its report into a RECORD, and this owner then
// reports the names that are still unassigned where the call is written. One definition of "reads a
// variable", two destinations.
//
// THE SUB-WALK IS DRIVEN BY THE OWNER, NOT FROM HERE, because the owner is at the columnar front
// end's per-class member-function ceiling and cannot be handed `this`. So the split is: this owner
// prepares the state, the owner walks, this owner judges what the walk collected.
//
// FOLLOWING CALLS IS WHAT MAKES IT TOTAL. A local function that calls a sibling reads whatever the
// sibling reads, so the walk re-enters through the same call arm; `Active` is the cycle guard, and a
// mutually recursive pair contributes each other's reads exactly once instead of recursing forever.
//
// THE FILTER IS THE CALLER'S, NOT THE CALLEE'S. A name the callee declares for itself is a local of
// the callee and the callee's own definite-assignment walk reports it; only a name the CALLER is
// tracking and has not assigned is reported here.
class AnalyzerLocalFunctionCaptures {

    // THE BLOCK'S LOCAL FUNCTIONS, REACHABLE FROM EVERY CALL IN THE BODY. Recorded when the block is
    // walked, which mirrors where the analyzer's scope stack binds them. A nested block's own are
    // recorded too and outlive it — harmless, because a call to one from outside the block is a name
    // error before this walk is consulted at all.
    static func Collect(statements: List<Statement>, state: DefiniteAssignmentState) {
        for statement in statements {
            localFunction := statement as LocalFunctionStatement
            if localFunction != null {
                state.LocalFunctions[localFunction.Function.Name] = localFunction
            }
        }
    }

    // THE CALLEE'S BODY, or null when this call is not one this rule is about: a callee that is not a
    // local function of this body, one already being read higher up the same cycle, or one with no
    // block body to read.
    static func BodyToRead(calleeName: string, state: DefiniteAssignmentState): BlockStatement? {
        localFunction: LocalFunctionStatement? = null
        if !state.LocalFunctions.TryGetValue(calleeName, out localFunction) {
            return null
        }

        if state.Active.Contains(calleeName) {
            return null
        }

        return localFunction.Function.Body
    }

    // THE SUB-WALK'S STATE. It carries the CALLER's assigned set, so a variable the caller has
    // already assigned is not a read the callee can complain about, and `Collected`, so every
    // remaining read is recorded instead of reported. The candidate set is COPIED: locals the callee
    // declares for itself must not join the caller's tracking. `LocalFunctions` and `Active` are
    // SHARED, because the cycle guard has to span the whole chain of calls.
    static func BeginRead(state: DefiniteAssignmentState): DefiniteAssignmentState {
        inner := new DefiniteAssignmentState()
        inner.Candidates.UnionWith(state.Candidates)
        inner.Assigned.UnionWith(state.Assigned)
        inner.Collected = new HashSet<string>(StringComparer.Ordinal)
        inner.LocalFunctions = state.LocalFunctions
        inner.Active = state.Active
        return inner
    }

    // WHAT THE SUB-WALK FOUND, JUDGED AGAINST THE CALLER. Names are sorted so a body that reads two
    // unassigned variables reports them in a stable order however the source ordered the reads.
    //
    // A CALL REACHED WHILE ALREADY COLLECTING REPORTS NOTHING AND CONTRIBUTES EVERYTHING. `outer`
    // calling `inner` is a read BY `outer` of whatever `inner` reads, so the names travel outwards to
    // whoever called `outer` — the squiggle belongs on that call, not on the one written inside a
    // body that is merely being inspected.
    static func ReportUnassignedReads(diagnostics: AnalyzerDiagnosticSink, inner: DefiniteAssignmentState, calleeName: string, callee: IdentifierExpression, state: DefiniteAssignmentState) {
        collected := inner.Collected
        if collected == null {
            return
        }

        outerCollected := state.Collected
        if outerCollected != null {
            outerCollected.UnionWith(collected)
            return
        }

        unassigned := new List<string>()
        for name in collected {
            if state.Candidates.Contains(name) && !state.Assigned.Contains(name) {
                unassigned.Add(name)
            }
        }

        if unassigned.Count == 0 {
            return
        }

        unassigned.Sort()
        for unassignedItem in unassigned {
            Report(diagnostics, unassignedItem, calleeName, callee, state)
        }
    }

    // NL304, NAMING BOTH HALVES: the variable that has no value yet AND the local function whose body
    // reads it. Naming only the variable would point at a line that never mentions it — the call site
    // is where the program has to change, and the function is why.
    static func Report(diagnostics: AnalyzerDiagnosticSink, name: string, calleeName: string, callee: IdentifierExpression, state: DefiniteAssignmentState) {
        key := new ValueTuple<string, int, int>(name + " via " + calleeName, callee.Line, callee.Column)
        if !state.Reported.Add(key) {
            return
        }

        diagnostics.Report(
            ErrorCode.DefiniteAssignmentError,
            "'" + name + "' is read by local function '" + calleeName + "' and has not been assigned a value on every path that reaches this call",
            callee.Line,
            callee.Column,
            "Assign '" + name + "' before calling '" + calleeName + "' here, or give it an initial value where you declare it.",
            Math.Max(1, calleeName.Length)
        )
    }
}
