namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHETHER A VALUE EXISTS BY THE TIME SOMETHING READS IT — the analyzer's definite-assignment
// authority, and both of its NL304 diagnostics.
//
// There are TWO questions here and they are not the same question, which is why they are two entry
// points rather than one. The CONSTRUCTOR question asks whether a non-nullable FIELD is assigned by
// the end of a constructor, and it answers by collecting the field names a body definitely assigns
// and subtracting them from the names the class declares. The LOCAL question asks whether a LOCAL
// declared without an initializer is assigned on every path that reaches a READ of it, and it
// answers by threading an assigned-set through the control-flow graph — Roslyn's `DataFlowPass`
// shape — intersecting at merge points and treating anything that may run zero times as
// contributing nothing. The squiggle lands on the CONSTRUCTOR for the first and on the offending
// READ for the second.
//
// THIS WALK RE-ENTERS NOTHING. It reads the AST, it mutates a `DefiniteAssignmentState`, and it
// reports. It never asks what an expression's TYPE is — `AnalyzeDefiniteAssignmentExpression` was
// 171 lines of pure recursion in `Analyzer.cs` and is 171 lines of pure recursion here — so unlike
// the call walk and the pattern walk there is no request protocol, no suspended state and no
// driver. The one type question in the whole owner is the constructor arm's `field.Type`, which the
// already-N# type resolver answers directly.
//
// THE TWO WALKS DISAGREE ABOUT `if`, DELIBERATELY. The constructor collector counts an `if` as
// assigning only what BOTH branches assign and does not recurse into a single-branch `if` at all;
// the local walk runs both branches, snapshots each, and merges by intersection unless a branch
// always exits. They are different analyses of different things and the difference is preserved
// verbatim.
//
// WHAT "ALWAYS EXITS" MEANS HERE is `return`, `throw`, `break` or `continue` — the local walk
// returns TRUE for a statement whose every path leaves the enclosing flow, and a path that always
// exits contributes nothing to a merge. `yield` is NOT an exit: a generator resumes.
class AnalyzerDefiniteAssignment {
    diagnosticsValue: AnalyzerDiagnosticSink
    typeResolverValue: AnalyzerTypeResolver

    constructor(diagnostics: AnalyzerDiagnosticSink, typeResolver: AnalyzerTypeResolver) {
        diagnosticsValue = diagnostics
        typeResolverValue = typeResolver
    }

    // ── Definite assignment for fields (NL304) ─────────────────────────────
    //
    // Every non-nullable field a class declares WITHOUT an initializer must be assigned by every
    // constructor that does not chain to another one. The report names the field and lands on the
    // `constructor` keyword, because that is the thing that failed to do its job.
    func CheckConstructorFields(ctor: ConstructorDeclaration, classDecl: ClassDeclaration) {
        // Collect all non-nullable fields without initializers
        uninitializedFields := new HashSet<string>()
        for member in classDecl.Members {
            field := member as FieldDeclaration
            if field != null {
                // Skip STATIC fields: they are not part of any instance constructor's contract — a
                // static field is .cctor-initialized (or CLR zero/null), so NL304 must never demand
                // a ctor assignment for it.
                if HasStaticModifier(field.Modifiers) {
                    continue
                }

                // Skip fields with type inference (they always have initializers)
                if field.Type != null && field.Initializer == null {
                    resolved := typeResolverValue.ResolveType(field.Type)
                    nullable := resolved as NullableTypeInfo
                    if nullable == null {
                        uninitializedFields.Add(field.Name)
                    }
                }
            }
        }

        // Check if constructor assigns all required fields
        assignedFields := GetAssignedFields(ctor.Body)
        for fieldName in uninitializedFields {
            if !assignedFields.Contains(fieldName) {
                diagnosticsValue.Report(ErrorCode.DefiniteAssignmentError, "Field '" + fieldName + "' is non-nullable but isn't assigned in this constructor " + "— either assign it here or give it a default value in its declaration", ctor.Line, ctor.Column, null, "constructor".Length)
            }
        }
    }

    static func HasStaticModifier(modifiers: Modifiers): bool {
        modifierValue := Convert.ToInt32(modifiers)
        staticFlag := Convert.ToInt32(Modifiers.Static)
        return (modifierValue & staticFlag) == staticFlag
    }

    // An ordinal-comparer copy of a name set. `new HashSet<string>(source, comparer)` is the shape
    // `Analyzer.cs` used; the columnar backend does not emit that two-argument constructor, and an
    // empty ordinal set unioned with the source is the same set with the same comparer, built by the
    // same enumeration.
    static func CopyNames(source: HashSet<string>): HashSet<string> {
        copy := new HashSet<string>(StringComparer.Ordinal)
        copy.UnionWith(source)
        return copy
    }

    func GetAssignedFields(block: BlockStatement): HashSet<string> {
        assigned := new HashSet<string>()
        CollectAssignedFields(block.Statements, assigned)
        return assigned
    }

    // The CONSTRUCTOR collector, and it is deliberately coarser than the local walk below. A
    // two-branch `if` contributes the INTERSECTION of its branches; a single-branch `if` contributes
    // nothing at all and is not even entered; and `try`, `for`, `foreach`, `while`, `using` and
    // `lock` bodies contribute nothing, because a loop may run zero times and a `try` may throw
    // before it reaches the assignment.
    func CollectAssignedFields(statements: List<Statement>, assigned: HashSet<string>) {
        for stmt in statements {
            expressionStatement := stmt as ExpressionStatement
            if expressionStatement != null {
                assignment := expressionStatement.Expression as AssignmentExpression
                if assignment != null {
                    memberAccess := assignment.Target as MemberAccessExpression
                    identifier := assignment.Target as IdentifierExpression
                    if memberAccess != null {
                        thisReceiver := memberAccess.Object as ThisExpression
                        if thisReceiver != null {
                            assigned.Add(memberAccess.MemberName)
                        }
                    } else if identifier != null {
                        assigned.Add(identifier.Name)
                    }
                }

                continue
            }

            block := stmt as BlockStatement
            if block != null {
                CollectAssignedFields(block.Statements, assigned)
                continue
            }

            ifStatement := stmt as IfStatement
            if ifStatement != null {
                // Only count as assigned if BOTH branches assign (definite assignment)
                elseStatement := ifStatement.ElseStatement
                if elseStatement != null {
                    thenAssigned := new HashSet<string>()
                    elseAssigned := new HashSet<string>()
                    thenStatements := new List<Statement>()
                    thenStatements.Add(ifStatement.ThenStatement)
                    elseStatements := new List<Statement>()
                    elseStatements.Add(elseStatement)
                    CollectAssignedFields(thenStatements, thenAssigned)
                    CollectAssignedFields(elseStatements, elseAssigned)
                    // Fields assigned in both branches are definitely assigned
                    thenAssigned.IntersectWith(elseAssigned)
                    assigned.UnionWith(thenAssigned)
                }

                // Single-branch if: assignments are not definite, but still recurse
                // to catch assignments that happen unconditionally inside
                continue
            }
        }
    }
    // try, for, foreach, while, using, lock bodies are NOT guaranteed
    // to execute (loop may run 0 times, try may throw before assignment),
    // so assignments inside them do NOT count as definite assignment.

    // ── Definite assignment for locals (NL304) ─────────────────────────────
    //
    // A read of a local that was declared without an initializer is an error
    // unless the local is definitely assigned on every path that reaches the
    // read. Modeled after Roslyn's DataFlowPass: we thread an "assigned" set
    // through the control-flow graph, intersecting at merge points (if/else,
    // switch) and treating loop bodies conservatively (they may run zero times).
    // The squiggle lands on the offending READ of the variable.
    func CheckLocals(body: BlockStatement, declaration: FunctionDeclaration?) {
        state := new DefiniteAssignmentState()

        // AN `out` PARAMETER ARRIVES UNASSIGNED AND MUST LEAVE ASSIGNED. It is seeded as a CANDIDATE,
        // so reading it before writing it is the ordinary NL304 report, and as REQUIRED-AT-EXIT, so
        // every `return` is held to it as well. A `ref` parameter is neither: its caller had to assign
        // it before the call, so it arrives with a value.
        anchorLine := body.Line
        anchorColumn := body.Column
        anchorLength := 1
        if declaration != null {
            anchorLine = declaration.Line
            anchorColumn = declaration.Column
            anchorLength = Math.Max(1, declaration.Name.Length)
            for parameter in declaration.Parameters {
                if parameter.Modifier == ParameterModifier.Out {
                    state.Candidates.Add(parameter.Name)
                    state.Assigned.Remove(parameter.Name)
                    state.RequiredAtExit.Add(parameter.Name)
                }
            }
        }

        alwaysExits := AnalyzeBlock(body, state)
        if state.RequiredAtExit.Count == 0 || alwaysExits {
            return
        }

        // FALLING OFF THE END IS AN EXIT LIKE ANY OTHER. A function with an `out` parameter and no
        // `return` at all reaches its caller with the slot still empty, so the last exit is checked
        // too. There is no statement to point at, so the squiggle goes on the PARAMETER that was
        // never filled — the one thing on the line the reader has to change.
        if declaration != null {
            for parameter in declaration.Parameters {
                if parameter.Modifier == ParameterModifier.Out && !state.Assigned.Contains(parameter.Name) && parameter.Line > 0 {
                    anchorLine = parameter.Line
                    anchorColumn = parameter.Column
                    anchorLength = Math.Max(1, parameter.Name.Length)
                    break
                }
            }
        }

        AnalyzerOutParameterExits.ReportUnassigned(diagnosticsValue, state, anchorLine, anchorColumn, anchorLength, true)
    }

    // Returns true if the statement (and therefore the path through it) always
    // exits the enclosing flow via return/throw/break/continue.
    func AnalyzeStatement(stmt: Statement, state: DefiniteAssignmentState): bool {
        block := stmt as BlockStatement
        if block != null {
            return AnalyzeBlock(block, state)
        }

        allocBlock := stmt as AllocBlockStatement
        if allocBlock != null {
            return AnalyzeBlock(allocBlock.Body, state)
        }

        allowStatement := stmt as AllowStatement
        if allowStatement != null {
            return AnalyzeBlock(allowStatement.Body, state)
        }

        unsafeBlock := stmt as UnsafeBlockStatement
        if unsafeBlock != null {
            return AnalyzeBlock(unsafeBlock.Body, state)
        }

        varDecl := stmt as VariableDeclarationStatement
        if varDecl != null {
            if varDecl.Initializer != null {
                AnalyzeExpression(varDecl.Initializer, state)
                state.Assigned.Add(varDecl.Name)
            } else {
                // Declared without initializer: must be assigned before use.
                state.Candidates.Add(varDecl.Name)
                state.Assigned.Remove(varDecl.Name)
            }

            return false
        }

        tupleDecl := stmt as TupleDeconstructionStatement
        if tupleDecl != null {
            AnalyzeExpression(tupleDecl.Initializer, state)
            for name in tupleDecl.Names {
                if name != "_" {
                    state.Assigned.Add(name)
                }
            }

            return false
        }

        exprStmt := stmt as ExpressionStatement
        if exprStmt != null {
            AnalyzeExpression(exprStmt.Expression, state)
            return false
        }

        printStmt := stmt as PrintStatement
        if printStmt != null {
            AnalyzeExpression(printStmt.Value, state)
            return false
        }

        returnStmt := stmt as ReturnStatement
        if returnStmt != null {
            if returnStmt.Value != null {
                AnalyzeExpression(returnStmt.Value, state)
            }

            // AN `out` PARAMETER IS CHECKED AT EVERY EXIT, and a `return` is one. The returned
            // EXPRESSION is walked first, so `return value` on an unassigned `out` is told about the
            // read before it is told about the exit.
            if state.RequiredAtExit.Count > 0 {
                AnalyzerOutParameterExits.ReportUnassigned(diagnosticsValue, state, returnStmt.Line, returnStmt.Column, 6, false)
            }

            return true
        }

        yieldStmt := stmt as YieldStatement
        if yieldStmt != null {
            if yieldStmt.Value != null {
                AnalyzeExpression(yieldStmt.Value, state)
            }

            return false
        }

        throwStmt := stmt as ThrowStatement
        if throwStmt != null {
            AnalyzeExpression(throwStmt.Expression, state)
            return true
        }

        breakStmt := stmt as BreakStatement
        continueStmt := stmt as ContinueStatement
        if breakStmt != null || continueStmt != null {
            return true
        }

        ifStmt := stmt as IfStatement
        if ifStmt != null {
            return AnalyzeIf(ifStmt, state)
        }

        whileStmt := stmt as WhileStatement
        if whileStmt != null {
            AnalyzeExpression(whileStmt.Condition, state)
            AnalyzeLoopBody(whileStmt.Body, state, null)
            return false
        }

        forStmt := stmt as ForStatement
        if forStmt != null {
            if forStmt.Initializer != null {
                AnalyzeStatement(forStmt.Initializer, state)
            }

            if forStmt.Condition != null {
                AnalyzeExpression(forStmt.Condition, state)
            }

            AnalyzeLoopBody(forStmt.Body, state, forStmt.Iterator)
            return false
        }

        foreachStmt := stmt as ForeachStatement
        if foreachStmt != null {
            AnalyzeExpression(foreachStmt.Collection, state)
            AnalyzeLoopBody(foreachStmt.Body, state, null)
            return false
        }

        awaitForeach := stmt as AwaitForEachStatement
        if awaitForeach != null {
            AnalyzeExpression(awaitForeach.Collection, state)
            AnalyzeLoopBody(awaitForeach.Body, state, null)
            return false
        }

        switchStmt := stmt as SwitchStatement
        if switchStmt != null {
            return AnalyzeSwitch(switchStmt, state)
        }

        tryStmt := stmt as TryStatement
        if tryStmt != null {
            return AnalyzeTry(tryStmt, state)
        }

        usingStmt := stmt as UsingStatement
        if usingStmt != null {
            usingDeclaration := usingStmt.Declaration
            if usingDeclaration != null {
                AnalyzeStatement(usingDeclaration, state)
            }

            usingExpression := usingStmt.Expression
            if usingExpression != null {
                AnalyzeExpression(usingExpression, state)
            }

            usingBody := usingStmt.Body
            if usingBody != null {
                return AnalyzeStatement(usingBody, state)
            }

            return false
        }

        lockStmt := stmt as LockStatement
        if lockStmt != null {
            AnalyzeExpression(lockStmt.LockObject, state)
            AnalyzeBlock(lockStmt.Body, state)
            return false
        }

        assertStmt := stmt as AssertStatement
        if assertStmt != null {
            AnalyzeExpression(assertStmt.Condition, state)
            if assertStmt.Message != null {
                AnalyzeExpression(assertStmt.Message, state)
            }

            return false
        }

        // Local functions have their own bodies analyzed independently; do not
        // flow the enclosing assignment state into them.
        return false
    }

    func AnalyzeBlock(block: BlockStatement, state: DefiniteAssignmentState): bool {
        for statement in block.Statements {
            if AnalyzeStatement(statement, state) {
                return true
            }
        }

        return false
    }

    func AnalyzeIf(ifStmt: IfStatement, state: DefiniteAssignmentState): bool {
        AnalyzeExpression(ifStmt.Condition, state)

        beforeBranches := CopyNames(state.Assigned)

        thenAlwaysExits := AnalyzeStatement(ifStmt.ThenStatement, state)
        afterThen := CopyNames(state.Assigned)

        // Reset to pre-branch state for the else path.
        state.Assigned.Clear()
        state.Assigned.UnionWith(beforeBranches)

        elseAlwaysExits := false
        afterElse := beforeBranches
        elseStatement := ifStmt.ElseStatement
        if elseStatement != null {
            elseAlwaysExits = AnalyzeStatement(elseStatement, state)
            afterElse = CopyNames(state.Assigned)
        }

        // Merge: a variable is assigned afterward only if it is assigned on every
        // path that can fall through. A path that always exits contributes nothing.
        state.Assigned.Clear()
        if thenAlwaysExits && elseAlwaysExits {
            // Both paths exit — code after the if is unreachable; keep pre-branch state.
            state.Assigned.UnionWith(beforeBranches)
            return true
        }

        if thenAlwaysExits {
            state.Assigned.UnionWith(afterElse)
        } else if elseAlwaysExits {
            state.Assigned.UnionWith(afterThen)
        } else {
            afterThen.IntersectWith(afterElse)
            state.Assigned.UnionWith(afterThen)
        }

        return false
    }

    func AnalyzeLoopBody(body: Statement, state: DefiniteAssignmentState, iterator: Expression?) {
        // The body may execute zero times, so assignments inside it are not
        // definite afterward. Analyze reads against a snapshot, then restore.
        before := CopyNames(state.Assigned)
        AnalyzeStatement(body, state)
        if iterator != null {
            AnalyzeExpression(iterator, state)
        }

        state.Assigned.Clear()
        state.Assigned.UnionWith(before)
    }

    func AnalyzeSwitch(switchStmt: SwitchStatement, state: DefiniteAssignmentState): bool {
        AnalyzeExpression(switchStmt.Value, state)

        before := CopyNames(state.Assigned)
        merged: HashSet<string>? = null
        hasDefault := false
        allCasesExit := true

        for switchCase in switchStmt.Cases {
            if switchCase.Pattern == null {
                hasDefault = true
            }

            state.Assigned.Clear()
            state.Assigned.UnionWith(before)

            caseExits := false
            for statement in switchCase.Statements {
                if AnalyzeStatement(statement, state) {
                    caseExits = true
                    break
                }
            }

            if !caseExits {
                allCasesExit = false
                afterCase := CopyNames(state.Assigned)
                if merged == null {
                    merged = afterCase
                } else {
                    merged.IntersectWith(afterCase)
                }
            }
        }

        state.Assigned.Clear()
        if hasDefault && allCasesExit {
            return true
        }

        // Without a default case, the value may fall through unmatched, so only
        // the pre-switch assignments are guaranteed.
        mergedResult := merged
        if hasDefault && mergedResult != null {
            state.Assigned.UnionWith(mergedResult)
        } else {
            state.Assigned.UnionWith(before)
        }

        return false
    }

    func AnalyzeTry(tryStmt: TryStatement, state: DefiniteAssignmentState): bool {
        before := CopyNames(state.Assigned)

        // The try block may throw partway through, so its assignments are not
        // guaranteed to reach the catch/finally. Analyze reads, then discard.
        tryExits := AnalyzeBlock(tryStmt.TryBlock, state)
        state.Assigned.Clear()
        state.Assigned.UnionWith(before)

        everyCatchExits := true
        for catchClause in tryStmt.CatchClauses {
            catchState := CopyNames(before)
            state.Assigned.Clear()
            state.Assigned.UnionWith(catchState)
            if !AnalyzeBlock(catchClause.Block, state) {
                everyCatchExits = false
            }
        }

        state.Assigned.Clear()
        state.Assigned.UnionWith(before)
        if tryStmt.FinallyBlock != null {
            AnalyzeBlock(tryStmt.FinallyBlock, state)
        }

        // A `try` WHOSE TRY BLOCK AND EVERY `catch` LEAVE THE FLOW LEAVES THE FLOW. This member
        // returned a flat `false` until the `out` exit rule made the answer observable:
        // `TryParseUnsignedIntegerMagnitude` in `NumericLiteralFacts.nl` returns from its `try` and
        // from all THREE of its `catch` clauses, and was accused of falling off the end with its
        // `out` parameter unassigned — the ONE false positive the 103-project differential found,
        // in the compiler's own source.
        //
        // A HANDLERLESS `try` STILL ANSWERS `false`, AND THAT IS DELIBERATE. With no `catch` the
        // only other authority on termination — `AnalyzerStatementTermination`, which owns `NL305` —
        // holds that a `return` inside a `try` with a `finally` is not a returning path, and a
        // pinned contract here says a try statement never itself always-exits. Narrowing the claim
        // to the handled shape fixes the measured defect without making the two authorities
        // disagree about a shape neither of them can see the same way.
        //
        // THE CHANGE ONLY EVER REMOVES REPORTS. A statement that always exits contributes NOTHING to
        // a merge, so answering `true` can silence an intersection computed against a path that does
        // not exist; it can never create a new accusation.
        return tryExits && everyCatchExits && tryStmt.CatchClauses.Count > 0
    }

    // THE READ WALK, and it is pure recursion over the tree. It asks no type question, declares no
    // symbol and re-enters no other analysis: every arm either recurses into a child, records an
    // assignment, or reports. The two arms that are NOT recursion are the ones that matter — an
    // `out` argument WRITES its target instead of reading it, and `nameof` does not read its operand
    // at all — and the two that stop are a LAMBDA, whose body runs later and is analysed on its own,
    // and every node kind with no arm.
    func AnalyzeExpression(expr: Expression?, state: DefiniteAssignmentState) {
        if expr == null {
            return
        }

        identifier := expr as IdentifierExpression
        if identifier != null {
            ReportIfReadBeforeAssigned(identifier, state)
            return
        }

        assignment := expr as AssignmentExpression
        if assignment != null {
            // Compound assignment (+=, etc.) reads the target first.
            compoundTarget := assignment.Target as IdentifierExpression
            if assignment.Operator != AssignmentOperator.Assign && compoundTarget != null {
                ReportIfReadBeforeAssigned(compoundTarget, state)
            } else if compoundTarget == null {
                AnalyzeExpression(assignment.Target, state)
            }

            AnalyzeExpression(assignment.Value, state)

            assignTarget := assignment.Target as IdentifierExpression
            if assignTarget != null {
                state.Assigned.Add(assignTarget.Name)
            }

            return
        }

        binary := expr as BinaryExpression
        if binary != null {
            AnalyzeExpression(binary.Left, state)
            AnalyzeExpression(binary.Right, state)
            return
        }

        unary := expr as UnaryExpression
        if unary != null {
            AnalyzeExpression(unary.Operand, state)
            return
        }

        member := expr as MemberAccessExpression
        if member != null {
            AnalyzeExpression(member.Object, state)
            return
        }

        index := expr as IndexAccessExpression
        if index != null {
            AnalyzeExpression(index.Object, state)
            AnalyzeExpression(index.Index, state)
            return
        }

        call := expr as CallExpression
        if call != null {
            AnalyzeExpression(call.Callee, state)
            for argument in call.Arguments {
                // out arguments assign the target rather than reading it.
                outTarget := argument.Value as IdentifierExpression
                if argument.Modifier == ArgumentModifier.Out && outTarget != null {
                    state.Assigned.Add(outTarget.Name)
                } else {
                    AnalyzeExpression(argument.Value, state)
                }
            }

            return
        }

        ternary := expr as TernaryExpression
        if ternary != null {
            AnalyzeExpression(ternary.Condition, state)
            AnalyzeExpression(ternary.ThenExpression, state)
            AnalyzeExpression(ternary.ElseExpression, state)
            return
        }

        parenthesized := expr as ParenthesizedExpression
        if parenthesized != null {
            AnalyzeExpression(parenthesized.Inner, state)
            return
        }

        cast := expr as CastExpression
        if cast != null {
            AnalyzeExpression(cast.Expression, state)
            return
        }

        isExpr := expr as IsExpression
        if isExpr != null {
            AnalyzeExpression(isExpr.Expression, state)
            return
        }

        awaitExpr := expr as AwaitExpression
        if awaitExpr != null {
            AnalyzeExpression(awaitExpr.Expression, state)
            return
        }

        mustExpr := expr as MustExpression
        if mustExpr != null {
            AnalyzeExpression(mustExpr.Expression, state)
            return
        }

        throwExpr := expr as ThrowExpression
        if throwExpr != null {
            AnalyzeExpression(throwExpr.Expression, state)
            return
        }

        checkedExpr := expr as CheckedExpression
        if checkedExpr != null {
            AnalyzeExpression(checkedExpr.Expression, state)
            return
        }

        uncheckedExpr := expr as UncheckedExpression
        if uncheckedExpr != null {
            AnalyzeExpression(uncheckedExpr.Expression, state)
            return
        }

        allocExpr := expr as AllocExpression
        if allocExpr != null {
            AnalyzeExpression(allocExpr.Expression, state)
            return
        }

        stackAlloc := expr as StackAllocExpression
        if stackAlloc != null {
            AnalyzeExpression(stackAlloc.LengthExpression, state)
            return
        }

        range := expr as RangeExpression
        if range != null {
            AnalyzeExpression(range.Start, state)
            AnalyzeExpression(range.End, state)
            return
        }

        array := expr as ArrayLiteralExpression
        if array != null {
            for element in array.Elements {
                AnalyzeExpression(element, state)
            }

            return
        }

        tuple := expr as TupleExpression
        if tuple != null {
            for element in tuple.Elements {
                AnalyzeExpression(element.Value, state)
            }

            return
        }

        interpolated := expr as InterpolatedStringExpression
        if interpolated != null {
            for part in interpolated.Parts {
                hole := part as InterpolatedStringHole
                if hole != null {
                    AnalyzeExpression(hole.Expression, state)
                }
            }

            return
        }

        newExpr := expr as NewExpression
        if newExpr != null {
            for argument in newExpr.ConstructorArguments {
                AnalyzeExpression(argument.Value, state)
            }

            AnalyzeExpression(newExpr.ArrayLengthExpression, state)
            initializer := newExpr.Initializer
            if initializer != null {
                for property in initializer.Properties {
                    AnalyzeExpression(property.IndexExpression, state)
                    AnalyzeExpression(property.Value, state)
                }
            }

            return
        }

        spread := expr as SpreadExpression
        if spread != null {
            AnalyzeExpression(spread.Expression, state)
            return
        }

        withExpr := expr as WithExpression
        if withExpr != null {
            AnalyzeExpression(withExpr.Target, state)
            for property in withExpr.Properties {
                AnalyzeExpression(property.IndexExpression, state)
                AnalyzeExpression(property.Value, state)
            }

            return
        }
    }
    // nameof does not read the value of its operand.
    //
    // Lambdas capture by reference and may run later; their bodies are
    // analyzed independently and must not consume the enclosing flow state.

    // THE REPORT. It fires only for a name the walk is TRACKING (a local declared without an
    // initializer), only when that name is not in the assigned set, and only ONCE per
    // name-line-column — the same read is visited again by an enclosing loop's snapshot pass, and
    // the log is what keeps that from doubling the squiggle.
    func ReportIfReadBeforeAssigned(identifier: IdentifierExpression, state: DefiniteAssignmentState) {
        name := identifier.Name
        if !state.Candidates.Contains(name) || state.Assigned.Contains(name) {
            return
        }

        key := new ValueTuple<string, int, int>(name, identifier.Line, identifier.Column)
        if !state.Reported.Add(key) {
            return
        }

        diagnosticsValue.Report(ErrorCode.DefiniteAssignmentError, "'" + name + "' is used here before it has been assigned a value on every path that " + "reaches this point", identifier.Line, identifier.Column, "Give '" + name + "' an initial value where you declare it, or assign it on every branch " + "before this use.", Math.Max(1, name.Length))
    }
}

// THE `out` EXIT RULE'S SENTENCE, ON ITS OWN CLASS BECAUSE `AnalyzerDefiniteAssignment` IS AT THE
// COLUMNAR FRONT END'S PER-CLASS MEMBER-FUNCTION CEILING. Adding ANY member function to that class
// — this one included, measured — declines the whole class at `parse.struct` regardless of its name
// or body. The owner is unchanged: this is one sentence and its formatting, called from the two
// exits the walk knows about, with the sink handed in.
class AnalyzerOutParameterExits {

    // EVERY `out` PARAMETER THIS EXIT LEAVES EMPTY, named in sorted order so the sentence is stable
    // however the declaration ordered them. A path that `throw`s never reaches an exit check at all,
    // which is why a function that assigns on one branch and throws on the other is silent.
    static func ReportUnassigned(diagnostics: AnalyzerDiagnosticSink, state: DefiniteAssignmentState, line: int, column: int, length: int, isEndOfBody: bool) {
        missing := new List<string>()
        for name in state.RequiredAtExit {
            if !state.Assigned.Contains(name) {
                missing.Add(name)
            }
        }

        if missing.Count == 0 {
            return
        }

        missing.Sort()
        names := string.Join(", ", missing)
        key := new ValueTuple<string, int, int>(names, line, column)
        if !state.Reported.Add(key) {
            return
        }

        // `where` IS A RESERVED WORD and cannot name a local: spelling this `where` declined the
        // WHOLE class at `parse.struct`, reported at the class header with nothing said about the
        // identifier — the reserved-word failure mode exactly.
        exitText := "this `return`"
        if isEndOfBody {
            exitText = "the end of the body"
        }

        message := "'" + names + "' is an `out` parameter and is not assigned on every path that reaches " + exitText
        suggestion := "Assign '" + names + "' before returning — every path out of the function must leave it with a value. A path that `throw`s does not have to."
        if missing.Count > 1 {
            message = missing.Count.ToString() + " `out` parameters are not assigned on every path that reaches " + exitText + ": " + names
            suggestion = "Assign all " + missing.Count.ToString() + " before returning — every path out of the function must leave each one with a value. A path that `throw`s does not have to."
        }

        diagnostics.Report(ErrorCode.DefiniteAssignmentError, message, line, column, suggestion, length)
    }
}
