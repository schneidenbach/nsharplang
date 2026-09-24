namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT IS TRUE AFTER A CONDITIONAL — the JOIN of the two paths that reach the statement below it.
//
// A GUARD CLAUSE IS THE EASY HALF AND IT WAS THE ONLY HALF. `if x == null { return }` deletes one of
// the two paths, so the surviving flow simply INHERITS the other branch's facts and no join is
// needed. Every other `if` has two live paths, and until this owner existed the analyzer answered
// the question by forgetting both of them: a branch's facts died with the branch's scope and the
// condition's FALSE facts were never installed anywhere at all. That is why the idiom every
// dictionary in the language server is written with
//
//     list: List<int>? = default
//     if !locations.TryGetValue(name, out list) {
//         list = new List<int>()
//     }
//     list.Add(line)
//
// squiggled on the last line. BOTH paths reach it holding a non-null list — the then-branch because
// it just assigned one, the implicit else because `TryGetValue` returning true is exactly what
// `[MaybeNullWhen(false)]` says leaves the `out` target non-null — and the answer is the MEET of
// those two, not the absence of either.
//
// THE RULE, STATED ONCE. After `if c { S }` the state is `join(exit(S), falseFacts(c))`; after
// `if c { S } else { T }` it is `join(exit(S), exit(T))`; and a branch that ALWAYS LEAVES contributes
// nothing, which is the guard-clause rule and is unchanged. The same shape settles a `while` or
// `for` exit: the condition is false at the bottom of a loop that fell out of it, so the false facts
// hold after it — unless a `break` reached the exit without ever testing the condition again.
//
// A BRANCH'S EXIT STATE IS ITS SCOPE'S OWN FACT TABLE, which is why the `if` walk now OWNS the scope
// its branches run in rather than letting each branch block open one of its own. The facts a branch
// ends with are precisely the entries that scope recorded — the condition's proved facts, installed
// when the branch opened, overwritten by whatever the branch then assigned — and reading them at the
// moment the branch ends is the whole of `exit(S)`. A path the branch never touched has no entry,
// and that is the correct answer too: the enclosing flow still speaks for it and the join must not.
//
// THE JOIN MAY NEVER WEAKEN A FACT THE ENCLOSING FLOW STILL HOLDS. An assignment invalidates the
// path it wrote in EVERY open scope, so a path the enclosing flow can still answer for is a path
// neither branch assigned — and a meet computed from two hypotheses about an unreachable branch must
// not overwrite it. Without that rule the redundant re-check `if x != null { Log() }` written after a
// guard clause would take `x` back from not-null to maybe-null and squiggle the line below it.
class AnalyzerConditionalJoin {

    // THE MEET OF TWO PATHS. Two paths that agree answer what they agree on. A definite answer met
    // with a different one is MAYBE-NULL — that is the whole lattice, and it is why `not-null` on one
    // path and `null` on the other is not an error but an uncertainty. `Unknown` is the absence of an
    // answer rather than an answer, so it swallows the meet; `Oblivious` is external metadata the
    // analyzer was never told the nullability of, and N# is deliberately optimistic about it in
    // exactly the way C# is — it yields to whatever the other path knows.
    static func Meet(left: NullState, right: NullState): NullState {
        if left == right {
            return left
        }

        if left == NullState.Unknown || right == NullState.Unknown {
            return NullState.Unknown
        }

        if left == NullState.Oblivious {
            return right
        }

        if right == NullState.Oblivious {
            return left
        }

        return NullState.MaybeNull
    }

    // WHETHER A JOINED ANSWER IS WEAKER THAN ONE THE ENCLOSING FLOW ALREADY PROVED. Only a DEFINITE
    // established fact can be weakened: `not-null` and `null` are proofs, and anything that is not
    // the same proof takes information away. A `maybe-null`, an `unknown` and an `oblivious` are not
    // proofs, so nothing is weaker than they are.
    static func IsWeakerThan(candidate: NullState, established: NullState): bool {
        if candidate == established {
            return false
        }

        if established == NullState.NotNull {
            return true
        }

        return established == NullState.Null
    }

    // THE FACTS A BRANCH ENDED WITH, as its own scope recorded them, MINUS the ones that die with it.
    // A name the branch DECLARED is gone at the closing brace and a fact about it must not reach the
    // flow outside — but a name the branch merely NARROWED is also written into the scope's symbol
    // table, so "declared here" alone is not the test. The test is declared here AND nowhere outside:
    // that is exactly a branch-local, and exactly not an outer binding the branch spoke about.
    static func ExitFacts(scopes: AnalyzerScopeStack, branchScope: Scope): Dictionary<string, NullState> {
        facts := new Dictionary<string, NullState>(StringComparer.Ordinal)
        for entry in branchScope.NullStates {
            path := entry.Key
            root := RootName(path)
            if branchScope.Symbols.ContainsKey(root) && !scopes.IsNameBoundOutsideTop(root) {
                continue
            }

            facts[path] = entry.Value
        }

        return facts
    }

    // TWO TABLES LAID ONE OVER THE OTHER, the second winning. A narrowed branch ends with two open
    // scopes — the narrowing scope the condition's facts were installed in, and the block scope inside
    // it — and its exit state is the second laid over the first: a path the branch ASSIGNED has
    // already overwritten what the condition PROVED, and a path it did not keeps the proof.
    static func OverlayFacts(under: Dictionary<string, NullState>, over: Dictionary<string, NullState>?): Dictionary<string, NullState> {
        if over == null {
            return under
        }

        for entry in over {
            under[entry.Key] = entry.Value
        }

        return under
    }

    // THE FACTS A NARROWING LIST CARRIES, as the same table a branch's exit state is read as. The
    // implicit else path of an `if` with no else branch has no scope of its own to read — what it
    // knows is exactly what the condition proved when it was false.
    static func NarrowingFacts(narrowings: List<FlowNarrowing>?): Dictionary<string, NullState> {
        facts := new Dictionary<string, NullState>(StringComparer.Ordinal)
        if narrowings == null {
            return facts
        }

        for narrowing in narrowings {
            facts[narrowing.Path] = narrowing.NullState
        }

        return facts
    }

    // THE JOIN ITSELF, rendered as the narrowing list the flow writer installs. Only a path BOTH
    // paths speak for is joined: one that only one path mentions is one the other path left to the
    // enclosing flow, and the enclosing flow's answer — or, when a branch assignment invalidated it,
    // the declared type's own default — is already the right one. The established fact is consulted
    // last and vetoes a weaker answer, because a path the enclosing flow can still answer for is a
    // path neither branch assigned.
    static func JoinFacts(scopes: AnalyzerScopeStack, left: Dictionary<string, NullState>, right: Dictionary<string, NullState>): List<FlowNarrowing> {
        return InstallableFacts(scopes, MeetFacts(left, right))
    }

    // THE MEET OF TWO FACT TABLES, as a table. Only a path BOTH tables speak for survives: one that
    // only one of them mentions is one the other left to the enclosing flow. More than two paths —
    // a `switch`'s arms — meet by folding this over them, which is the same answer taken pairwise
    // because the meet is associative.
    static func MeetFacts(left: Dictionary<string, NullState>, right: Dictionary<string, NullState>): Dictionary<string, NullState> {
        met := new Dictionary<string, NullState>(StringComparer.Ordinal)
        for entry in left {
            other := NullState.Unknown
            if right.TryGetValue(entry.Key, out other) {
                met[entry.Key] = Meet(entry.Value, other)
            }
        }

        return met
    }

    // THE STATE THE ENCLOSING FLOW STILL HOLDS for each of these paths, as a table one more path can
    // be met with. A `switch` with no `default` arm is reached from one more place than it has arms —
    // the path on which no pattern matched — and what THAT path knows is what the flow outside knew.
    // A path an arm assigned has no surviving fact, so it drops out of the meet, which is the right
    // answer: the unmatched path never ran that assignment.
    static func SurvivingFacts(scopes: AnalyzerScopeStack, paths: Dictionary<string, NullState>): Dictionary<string, NullState> {
        surviving := new Dictionary<string, NullState>(StringComparer.Ordinal)
        for entry in paths {
            if scopes.HasNullState(entry.Key) {
                surviving[entry.Key] = scopes.NullStateOrUnknown(entry.Key)
            }
        }

        return surviving
    }

    // A JOINED TABLE RENDERED AS THE NARROWING LIST THE FLOW WRITER INSTALLS, minus every answer that
    // is WEAKER than a proof the enclosing flow still holds. An assignment invalidates the path it
    // wrote in every open scope, so a path the enclosing flow can still answer for is a path no branch
    // assigned — and a meet computed from two hypotheses about an unreachable branch must not take
    // that proof back.
    static func InstallableFacts(scopes: AnalyzerScopeStack, facts: Dictionary<string, NullState>): List<FlowNarrowing> {
        installable := new List<FlowNarrowing>()
        for entry in facts {
            if scopes.HasNullState(entry.Key) && IsWeakerThan(entry.Value, scopes.NullStateOrUnknown(entry.Key)) {
                continue
            }

            installable.Add(new FlowNarrowing(entry.Key, null, entry.Value))
        }

        return installable
    }

    // A FACT TABLE RENDERED AS A NARROWING LIST, for the branch-leaves case: the surviving flow
    // INHERITS the other branch's exit state outright rather than joining anything with it, because
    // there is no second path left to join with.
    static func InheritedFacts(facts: Dictionary<string, NullState>): List<FlowNarrowing> {
        inherited := new List<FlowNarrowing>()
        for entry in facts {
            inherited.Add(new FlowNarrowing(entry.Key, null, entry.Value))
        }

        return inherited
    }

    // THE ROOT NAME OF A STABLE PATH — `doc` for `doc.Error.Message`, and the whole path for a simple
    // name.
    static func RootName(path: string): string {
        index := path.IndexOf(".", StringComparison.Ordinal)
        if index < 0 {
            return path
        }

        return path.Substring(0, index)
    }

    // WHETHER A `break` CAN CARRY CONTROL OUT OF THIS LOOP WITHOUT TESTING ITS CONDITION AGAIN. A
    // loop the flow fell out of the bottom of exited because its condition was FALSE, and that is a
    // fact the code after it may keep — but a `break` leaves with the condition untested and whatever
    // was true at the `break` instead, so a loop that contains one proves nothing on its way out.
    //
    // A `break` written in a NESTED loop belongs to that loop and never reaches this one, so the walk
    // stops at every nested `for`, `foreach`, `await foreach` and `while`. It does NOT stop at a
    // `switch`, and it does not descend into a lambda or a local function: neither can break out of
    // the loop that lexically encloses it.
    // THE SAME QUESTION OF A STATEMENT LIST — a `switch` arm's flattened statements.
    static func ContainsListBreak(statements: List<Statement>): bool {
        for statement in statements {
            if ContainsLoopBreak(statement) {
                return true
            }
        }

        return false
    }

    static func ContainsLoopBreak(statement: Statement?): bool {
        if statement == null {
            return false
        }

        if statement as BreakStatement != null {
            return true
        }

        block := statement as BlockStatement
        if block != null {
            for nested in block.Statements {
                if ContainsLoopBreak(nested) {
                    return true
                }
            }

            return false
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            return ContainsLoopBreak(ifStatement.ThenStatement) || ContainsLoopBreak(ifStatement.ElseStatement)
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            if ContainsLoopBreak(tryStatement.TryBlock) || ContainsLoopBreak(tryStatement.FinallyBlock) {
                return true
            }

            for clause in tryStatement.CatchClauses {
                if ContainsLoopBreak(clause.Block) {
                    return true
                }
            }

            return false
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            for switchCase in switchStatement.Cases {
                for caseStatement in switchCase.Statements {
                    if ContainsLoopBreak(caseStatement) {
                        return true
                    }
                }
            }

            return false
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            return ContainsLoopBreak(usingStatement.Body)
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            return ContainsLoopBreak(lockStatement.Body)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return ContainsLoopBreak(allocBlock.Body)
        }

        allowStatement := statement as AllowStatement
        if allowStatement != null {
            return ContainsLoopBreak(allowStatement.Body)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return ContainsLoopBreak(unsafeBlock.Body)
        }

        return false
    }
}
