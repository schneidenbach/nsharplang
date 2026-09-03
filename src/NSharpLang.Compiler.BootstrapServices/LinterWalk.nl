namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE LINT WALK ITSELF: THE FUNCTION ARM, THE STATEMENT ARM AND THE EXPRESSION ARM.
//
// These five members were one strongly connected component in `LintVisitor` and could not move one at
// a time. The expression sub-territory alone escapes to `VisitStatement` (a lambda's block body);
// adding `VisitStatement` escapes to `VisitFunction` (a local function); adding `VisitFunction`
// escapes to nothing. The smallest closed cut is therefore all three arms, and the only way in is
// `VisitDeclaration` — which is why the DECLARATION walk is what stays in C#.
//
// WHAT THIS OWNER HOLDS is the expression-recursion guard and nothing else. Every other piece of
// per-file state belongs to `LinterWalkState`, which the previous slice took; an arm reaches it
// through a method on that object rather than by mutating a visitor field.
//
// THE GUARD IS A `HashSet<object>`, AND THAT IS A MEASURED SUBSTITUTION, NOT A CONVENIENCE. The C#
// spelled it `HashSet<Expression>(ReferenceEqualityComparer.Instance)` — a set that asks "is this the
// same NODE", not "is this an equal node", because an AST that shares a subtree must not be treated
// as circular. `HashSet<object>` states the same rule, because no AST node type overrides `Equals` or
// `GetHashCode`: `object`'s reference-identity implementations are what both sets end up calling. Two
// structurally identical nodes are two entries, and re-adding one instance answers false.
//
// THE DEPTH COUNTER AND THE VISITING SET ARE BOTH NEEDED and they answer different questions. The
// counter bounds how DEEP a walk may go; the set catches a node that is its own descendant, which
// would otherwise recurse until the counter tripped and turned a recoverable cycle into a throw.
class LinterWalk {
    state: LinterWalkState
    visitingStack: HashSet<object>
    recursionDepth: int

    constructor(walkState: LinterWalkState) {
        state = walkState
        visitingStack = new HashSet<object>()
        recursionDepth = 0
    }

    // Deliberately low: the point is to catch a malformed tree quickly, not to support deep ones.
    static func MaxRecursionDepth(): int {
        return 100
    }

    // ---- the function arm -------------------------------------------------------------------------

    // One function, its parameters and its body. The frame the state hands back is held in a LOCAL and
    // restored on the straight line, with no `finally`: a throw inside the nested walk abandons it,
    // exactly as the C# locals it replaces did.
    func VisitFunction(declaration: FunctionDeclaration) {
        // NL010: the signature's type references are used names.
        state.TrackTypeReference(declaration.ReturnType)
        for parameter in declaration.Parameters {
            state.TrackTypeReference(parameter.Type)
        }

        frame := state.EnterFunction(IsAsync(declaration))

        body := declaration.Body
        expressionBody := declaration.ExpressionBody
        if body != null {
            state.PushScope()
            DeclareParameters(declaration)
            VisitStatement(body)
            state.CheckUnusedParameters(declaration.Name)
            state.PopScope()
        } else if expressionBody != null {
            state.PushScope()
            DeclareParameters(declaration)
            VisitExpression(expressionBody)
            state.CheckUnusedParameters(declaration.Name)
            state.PopScope()
        }

        // NL004: async without await.
        state.CheckAsyncWithoutAwait(declaration)
        state.ExitFunction(frame)
    }

    // Binds this function's parameters into the scope that was just opened, and records that scope so a
    // read from a nested lambda or local function can be credited to the parameter it resolves to.
    // A parameter is exempt from NL001 — it is reported by NL012 instead — which is what the `false`
    // says: this is a BINDING site, not a read that credits an enclosing parameter.
    func DeclareParameters(declaration: FunctionDeclaration) {
        for parameter in declaration.Parameters {
            parameterLine := declaration.Line
            if parameter.Line > 0 {
                parameterLine = parameter.Line
            }

            parameterColumn := declaration.Column
            if parameter.Column > 0 {
                parameterColumn = parameter.Column
            }

            state.DeclareVariable(parameter.Name, parameterLine, parameterColumn)
            state.MarkVariableUsed(parameter.Name, false)
            state.AddParameter(parameter.Name, parameterLine, parameterColumn)
        }

        state.RecordParameterScope()
    }

    // The `async` modifier, read as a flag bit. `Modifiers` is a flags enum and the test is the same
    // mask test `HasFlag` performs.
    static func IsAsync(declaration: FunctionDeclaration): bool {
        modifierBits := Convert.ToInt32(declaration.Modifiers)
        asyncBits := Convert.ToInt32(Modifiers.Async)
        return (modifierBits & asyncBits) == asyncBits
    }

    // ---- the statement arm ------------------------------------------------------------------------

    // Every statement shape the walk understands, AND — SINCE THIS SLICE — EVERY SHAPE IT DOES NOT.
    //
    // THIS ARM USED TO BE FAIL-OPEN WHILE THE EXPRESSION ARM WAS FAIL-SAFE, AND THAT ASYMMETRY COST
    // TWO SHIPPED FEATURES. `OffStatement` carries a handle expression and had no arm, so a
    // subscription read only by its `off` was reported NL001. Then `AllocBlockStatement`,
    // `AllowStatement` and `UnsafeBlockStatement` — each carrying a `BlockStatement` body — had no arm
    // either, so THE LINTER WAS BLIND INSIDE EVERY `unsafe`, `alloc` AND `allow(…)` BODY FOR EVERY
    // RULE IT HAS: a local read only in such a body was reported NL001, a local declared and never
    // read inside one was never reported at all, an import used only inside one was reported NL010,
    // and an empty catch block inside one was never NL011. A missing arm does not weaken one rule; it
    // switches the whole linter off for that subtree.
    //
    // SO THE TAIL NOW THROWS, exactly as `AstChildrenCore.Of` throws for an expression node it does
    // not know. A statement shape reaches the end of this walk only by being named in
    // `IsBodylessStatement` as carrying no binding, no expression and no nested body; anything else
    // is a new node kind whose arm has not been written, and the walk says so instead of silently
    // skipping the subtree. That is what stops the next `Statement` subclass from re-opening this
    // hole — the previous two were each found by a user, not by the walk.
    func VisitStatement(statement: Statement) {
        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            VisitVariableDeclaration(variableDeclaration)
            return
        }

        block := statement as BlockStatement
        if block != null {
            VisitBlock(block)
            return
        }

        // THE THREE BODY-CARRYING WRAPPERS. `unsafe { … }`, `alloc { … }` and
        // `allow(effect, reason: …) { … }` each wrap an ordinary `BlockStatement`, and the code inside
        // one is ordinary code: its reads are reads, its declarations are declarations, and its own
        // scope is the block's. Handing the body to `VisitStatement` reaches `VisitBlock`, which
        // pushes and pops the scope — so a local declared inside the wrapper is reported at the
        // wrapper's closing brace and does not leak past it.
        //
        // `AllowStatement`'s `Effects`, `Reason` and `Owner` are strings the parser already decoded,
        // not expressions, so there is nothing in the header to walk.
        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            VisitStatement(unsafeBlock.Body)
            return
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            VisitStatement(allocBlock.Body)
            return
        }

        allowStatement := statement as AllowStatement
        if allowStatement != null {
            VisitStatement(allowStatement.Body)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            VisitExpression(ifStatement.Condition)
            // NL003 and NL016 both read the condition and neither walks it.
            state.CheckUnnecessaryNullCheck(ifStatement.Condition)
            state.CheckRedundantNullCheck(ifStatement.Condition)
            VisitStatement(ifStatement.ThenStatement)
            elseStatement := ifStatement.ElseStatement
            if elseStatement != null {
                VisitStatement(elseStatement)
            }

            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            VisitFor(forStatement)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            // The collection is read in the OUTER scope, before the loop variable exists.
            VisitExpression(foreachStatement.Collection)
            state.PushScope()
            state.DeclareVariable(foreachStatement.VariableName, foreachStatement.Line, foreachStatement.Column)
            state.MarkVariableUsed(foreachStatement.VariableName, false)
            VisitStatement(foreachStatement.Body)
            state.PopScope()
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            VisitExpression(whileStatement.Condition)
            state.CheckUnnecessaryNullCheck(whileStatement.Condition)
            state.CheckRedundantNullCheck(whileStatement.Condition)
            VisitStatement(whileStatement.Body)
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            returnValue := returnStatement.Value
            if returnValue != null {
                VisitExpression(returnValue)
            }

            return
        }

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            VisitExpression(expressionStatement.Expression)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            VisitTry(tryStatement)
            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            VisitUsing(usingStatement)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            VisitSwitch(switchStatement)
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            VisitExpression(throwStatement.Expression)
            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            VisitFunction(localFunction.Function)
            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            VisitExpression(printStatement.Value)
            return
        }

        // `off <handle>` detaches an event subscription. Its handle is an expression in statement
        // position exactly as a `throw` operand and a `print` value are, so it is a READ — and it had
        // no arm here at all, which made the canonical shape the feature documents
        // (`sub := on obj.Event handler` … `off sub`) report a false NL001 against `sub`.
        offStatement := statement as OffStatement
        if offStatement != null {
            VisitExpression(offStatement.Handle)
            return
        }

        assertStatement := statement as AssertStatement
        if assertStatement != null {
            VisitExpression(assertStatement.Condition)
            assertMessage := assertStatement.Message
            if assertMessage != null {
                VisitExpression(assertMessage)
            }

            return
        }

        assertThrows := statement as AssertThrowsStatement
        if assertThrows != null {
            state.TrackTypeReference(assertThrows.ExceptionType)
            VisitStatement(assertThrows.Body)
            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            VisitExpression(lockStatement.LockObject)
            VisitStatement(lockStatement.Body)
            return
        }

        yieldStatement := statement as YieldStatement
        if yieldStatement != null {
            yieldValue := yieldStatement.Value
            if yieldValue != null {
                VisitExpression(yieldValue)
            }

            return
        }

        tupleDeconstruction := statement as TupleDeconstructionStatement
        if tupleDeconstruction != null {
            VisitTupleDeconstruction(tupleDeconstruction)
            return
        }

        awaitForEach := statement as AwaitForEachStatement
        if awaitForEach != null {
            // `await foreach` is a genuine await usage — record it so NL004 does not misfire on async
            // functions that only consume async streams.
            state.NoteAwait()
            VisitExpression(awaitForEach.Collection)
            state.PushScope()
            state.DeclareVariable(awaitForEach.VariableName, awaitForEach.Line, awaitForEach.Column)
            state.MarkVariableUsed(awaitForEach.VariableName, false)
            VisitStatement(awaitForEach.Body)
            state.PopScope()
            return
        }

        if IsBodylessStatement(statement) {
            return
        }

        // The receiver must be object-typed for `GetType()` to emit.
        node: object = statement
        throw new InvalidOperationException("The lint walk has no arm for statement kind '" + node.GetType().Name + "' at line " + statement.Line.ToString() + ", column " + statement.Column.ToString() + ". Add an arm that walks its bindings and expressions, or name it in IsBodylessStatement if it carries none.")
    }

    // THE SHAPES THAT ARE WALKED NO FURTHER BECAUSE THERE IS NOTHING IN THEM TO WALK. Each carries no
    // binding, no expression and no nested body, so reaching one is not a gap. This list is what makes
    // the throw above safe to write: a shape is silent because it was NAMED silent, not because nobody
    // wrote its arm.
    //
    // The three import/directive kinds are `Statement` subclasses that the parser keeps at file level;
    // they are named here so that a file-level walk which ever reaches one does not trip the tail.
    static func IsBodylessStatement(statement: Statement): bool {
        if (statement as BreakStatement) != null {
            return true
        }

        if (statement as ContinueStatement) != null {
            return true
        }

        if (statement as EmptyStatement) != null {
            return true
        }

        if (statement as PreprocessorDirective) != null {
            return true
        }

        if (statement as FileImport) != null {
            return true
        }

        return (statement as NamespaceImport) != null
    }

    // A declaration binds its name and then walks its initializer — unless the initializer carries a
    // parser-error placeholder, in which case NEITHER happens: a name the parser could not read must
    // not be reported as unused, and a broken subtree must not cascade further diagnostics.
    func VisitVariableDeclaration(declaration: VariableDeclarationStatement) {
        state.TrackTypeReference(declaration.Type)

        initializer := declaration.Initializer
        initializerHasParserError := false
        if initializer != null {
            initializerHasParserError = AnalyzerParserErrorPlaceholders.ContainsInExpression(initializer)
        }

        if !initializerHasParserError {
            // The statement's own column is the IDENTIFIER's location, including for a shorthand
            // declaration like `name := value`.
            state.DeclareVariable(declaration.Name, declaration.Line, declaration.Column)
        }

        if initializer != null && !initializerHasParserError {
            VisitExpression(initializer)
        }
    }

    // A block opens a scope and closes it. NL006 is reported ONCE per block, at the first statement the
    // walk cannot reach, and the statements after it are not walked at all: an unreachable statement
    // must not cascade NL001-class findings of its own.
    func VisitBlock(block: BlockStatement) {
        state.PushScope()
        unreachableReported := false
        restIsUnreachable := false

        for statement in block.Statements {
            if restIsUnreachable {
                if !unreachableReported {
                    state.ReportUnreachableCode(statement.Line, statement.Column)
                    unreachableReported = true
                }

                continue
            }

            VisitStatement(statement)

            if IsFlowTerminator(statement) {
                restIsUnreachable = true
            }
        }

        state.PopScope()
    }

    // What makes the rest of a block unreachable. Only an unconditional exit counts.
    static func IsFlowTerminator(statement: Statement): bool {
        if (statement as ReturnStatement) != null {
            return true
        }

        return (statement as ThrowStatement) != null
    }

    // A `for` owns a scope so its initializer's bindings do not leak past the loop.
    func VisitFor(statement: ForStatement) {
        state.PushScope()
        initializer := statement.Initializer
        if initializer != null {
            VisitStatement(initializer)
        }

        condition := statement.Condition
        if condition != null {
            VisitExpression(condition)
        }

        iterator := statement.Iterator
        if iterator != null {
            VisitExpression(iterator)
        }

        VisitStatement(statement.Body)
        state.PopScope()
    }

    // Each catch clause owns a scope holding its exception variable, which is exempt from NL001. An
    // EMPTY catch block is NL011 and is not walked — there is nothing in it to walk.
    func VisitTry(statement: TryStatement) {
        VisitStatement(statement.TryBlock)
        for catchClause in statement.CatchClauses {
            catchBlockIsEmpty := catchClause.Block.Statements.Count == 0

            if catchBlockIsEmpty {
                state.ReportEmptyCatchBlock(catchClause.Block.Line, catchClause.Block.Column)
            }

            state.PushScope()
            variableName := catchClause.VariableName
            if variableName != null {
                state.DeclareVariable(variableName, catchClause.Block.Line, catchClause.Block.Column)
                state.MarkVariableUsed(variableName, false)
            }

            if !catchBlockIsEmpty {
                VisitStatement(catchClause.Block)
            }

            state.PopScope()
        }

        finallyBlock := statement.FinallyBlock
        if finallyBlock != null {
            VisitStatement(finallyBlock)
        }
    }

    // A `using` owns a scope so the resource it declares is not visible after it.
    func VisitUsing(statement: UsingStatement) {
        state.PushScope()
        declaration := statement.Declaration
        if declaration != null {
            VisitStatement(declaration)
        }

        resource := statement.Expression
        if resource != null {
            VisitExpression(resource)
        }

        body := statement.Body
        if body != null {
            VisitStatement(body)
        }

        state.PopScope()
    }

    // Every case owns its own scope: two cases may bind the same name without shadowing each other.
    // The case's PATTERN is walked inside that scope, because a pattern's own bindings belong to the
    // case rather than to the switch; `default` carries a null pattern and walks nothing.
    func VisitSwitch(statement: SwitchStatement) {
        VisitExpression(statement.Value)
        for switchCase in statement.Cases {
            state.PushScope()
            VisitPattern(switchCase.Pattern)
            for caseStatement in switchCase.Statements {
                VisitStatement(caseStatement)
            }

            state.PopScope()
        }
    }

    // ---- the pattern arm --------------------------------------------------------------------------

    // A PATTERN'S EMBEDDED EXPRESSIONS ARE READS, AND THAT IS THE SAME RULE THE `off` ARM ABOVE STATES:
    // every expression an operand slot carries is a read. A `Pattern` is not an `Expression`, so it
    // never reaches the expression arm — `VisitSwitch` walked a case's STATEMENTS and
    // `AstChildrenCore.Of` hands a match case its `Guard` and its arm `Expression` — and the two
    // expression slots a pattern owns were therefore invisible to every rule. A relational pattern's
    // compared value is a PRIMARY expression, so `case > limit =>` is a read of `limit`, and a
    // variable read only there was reported NL001 by both the statement form and the expression form.
    //
    // WHAT A PATTERN *BINDS* IS DELIBERATELY NOT WALKED. `case bound =>`, a type pattern's binding, a
    // property pattern's binding and a slice pattern's binding all INTRODUCE a name; crediting one as
    // a read would silence a genuine NL001 against a different variable of that name, because
    // `LinterWalkState`'s used-name set is file-wide and deliberately coarser than the scope.
    //
    // WHAT A PATTERN *NAMES* IS A DIFFERENT QUESTION, AND THIS BANNER USED TO CONFLATE THE TWO. A type
    // pattern writes a TYPE beside its binding, and that type is a written type reference exactly as a
    // parameter's or a `typeof`'s is — but a `TypeReference` is not an `Expression`, so neither this
    // walk nor `AstChildrenCore.Of` ever reached it. `match x { Foo f => … }`, `switch x { case Foo f
    // => … }`, `x is Foo` and `x as Foo` therefore all reported a FALSE NL010 against the import that
    // supplies `Foo` — an ERROR — and asked NL002 nothing. Every such slot now goes through
    // `TrackTypeReference`, the one site that answers both rules.
    //
    // The tail throws for the same reason the statement arm's does: a pattern kind is silent only by
    // being NAMED silent below, never by falling through.
    func VisitPattern(pattern: Pattern?) {
        if pattern == null {
            return
        }

        literalPattern := pattern as LiteralPattern
        if literalPattern != null {
            VisitExpression(literalPattern.Literal)
            return
        }

        relationalPattern := pattern as RelationalPattern
        if relationalPattern != null {
            VisitExpression(relationalPattern.Value)
            return
        }

        andPattern := pattern as AndPattern
        if andPattern != null {
            VisitPattern(andPattern.Left)
            VisitPattern(andPattern.Right)
            return
        }

        orPattern := pattern as OrPattern
        if orPattern != null {
            VisitPattern(orPattern.Left)
            VisitPattern(orPattern.Right)
            return
        }

        notPattern := pattern as NotPattern
        if notPattern != null {
            VisitPattern(notPattern.Pattern)
            return
        }

        positionalPattern := pattern as PositionalPattern
        if positionalPattern != null {
            for element in positionalPattern.Patterns {
                VisitPattern(element)
            }

            return
        }

        listPattern := pattern as ListPattern
        if listPattern != null {
            for element in listPattern.Elements {
                VisitPattern(element)
            }

            return
        }

        objectPattern := pattern as ObjectPattern
        if objectPattern != null {
            VisitPropertyPatterns(objectPattern.Properties)
            return
        }

        unionCasePattern := pattern as UnionCasePattern
        if unionCasePattern != null {
            VisitPropertyPatterns(unionCasePattern.Properties)
            return
        }

        // THE TYPE A PATTERN WRITES IS A TYPE REFERENCE, AND ITS BINDING STILL IS NOT. `Foo f` mentions
        // `Foo` — an import usage and a possible missing import — and introduces `f`, which stays
        // uncredited for the reason the banner gives.
        typePattern := pattern as TypePattern
        if typePattern != null {
            state.TrackTypeReference(typePattern.Type)
            return
        }

        if IsBindingOnlyPattern(pattern) {
            return
        }

        // The receiver must be object-typed for `GetType()` to emit.
        node: object = pattern
        throw new InvalidOperationException("The lint walk has no arm for pattern kind '" + node.GetType().Name + "' at line " + pattern.Line.ToString() + ", column " + pattern.Column.ToString() + ". Add an arm that walks its type, its sub-patterns and its expressions, or name it in IsBindingOnlyPattern if it only introduces a name.")
    }

    // THE PATTERN KINDS THAT CARRY A BINDING AND NOTHING ELSE. `case bound =>` and a list pattern's
    // `..rest` each introduce exactly one name and hold no type, no sub-pattern and no expression, so
    // there is nothing here for any rule to see. Naming them is what lets the tail above throw.
    static func IsBindingOnlyPattern(pattern: Pattern): bool {
        if (pattern as IdentifierPattern) != null {
            return true
        }

        return (pattern as SlicePattern) != null
    }

    // A property pattern's own sub-pattern. Its `Name` is the PROPERTY being matched and its
    // `BindingName` is a binding, so neither is a read; only the nested pattern is walked. The list is
    // optional on a union-case pattern, which is what the null check is for.
    func VisitPropertyPatterns(properties: List<PropertyPattern>?) {
        if properties == null {
            return
        }

        for propertyPattern in properties {
            VisitPattern(propertyPattern.Pattern)
        }
    }

    // A deconstruction binds every name but the discard. A parser-error placeholder in the initializer
    // suppresses the whole statement, bindings included, for the same reason a broken declaration is
    // suppressed.
    func VisitTupleDeconstruction(statement: TupleDeconstructionStatement) {
        if AnalyzerParserErrorPlaceholders.ContainsInExpression(statement.Initializer) {
            return
        }

        for name in statement.Names {
            if name != "_" {
                state.DeclareVariable(name, statement.Line, statement.Column)
            }
        }

        VisitExpression(statement.Initializer)
    }

    // ---- the expression arm -----------------------------------------------------------------------

    // THE GUARDED ENTRY POINT. Two different failures are guarded against, and they are not the same
    // failure: the DEPTH counter bounds an unbounded descent, and the VISITING SET catches a node that
    // is currently on the stack — a node that is its own descendant.
    //
    // A node already being visited is NOT walked again, but an identifier still counts as a READ.
    // That is deliberate and it is why the arm exists at all: a circular AST would otherwise lose the
    // usage and report a false NL001 against a variable the code plainly reads.
    func VisitExpression(expression: Expression) {
        recursionDepth = recursionDepth + 1
        if recursionDepth > MaxRecursionDepth() {
            // The receiver must be object-typed for `GetType()` to emit.
            node: object = expression
            throw new InvalidOperationException("Maximum recursion depth exceeded while visiting expression at line " + expression.Line.ToString() + ", column " + expression.Column.ToString() + ". Expression type: " + node.GetType().Name)
        }

        if !visitingStack.Add(expression) {
            identifier := expression as IdentifierExpression
            if identifier != null {
                state.MarkVariableUsed(identifier.Name, true)
            }

            recursionDepth = recursionDepth - 1
            return
        }

        try {
            VisitExpressionInternal(expression)
        } finally {
            recursionDepth = recursionDepth - 1
            visitingStack.Remove(expression)
        }
    }

    // The shapes that mean something to a rule. Everything else is purely structural and is handled by
    // the child walk below.
    func VisitExpressionInternal(expression: Expression) {
        identifier := expression as IdentifierExpression
        if identifier != null {
            state.MarkVariableUsed(identifier.Name, true)
            // NL010: every identifier the code mentions is a use of whatever import supplies it.
            state.NoteCodeIdentifier(identifier.Name)
            // NL002: a bare name that looks like a type may need an import.
            state.CheckMissingImport(identifier)
            return
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            // The RAW literal text, `$"…"` and all: the scan needs the interpolation syntax itself.
            state.HandleStringInterpolation(stringLiteral.Value)
            return
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            constructedType := newExpression.Type
            if constructedType != null {
                state.CheckMissingImportForType(constructedType, newExpression.Line, newExpression.Column)
                // NL010: the constructed type's base name is a used identifier.
                newTypeName := LinterTypeReferenceName.Base(constructedType)
                if newTypeName != null {
                    state.NoteCodeIdentifier(newTypeName)
                }
            }

            VisitChildExpressions(newExpression)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            // NL010: a member name may be an extension method supplied by an import.
            state.NoteMemberAccessName(memberAccess.MemberName)
            VisitChildExpressions(memberAccess)
            return
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            state.NoteAwait()
            VisitChildExpressions(awaitExpression)
            return
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            // NL010: `typeof`'s operand is a TypeReference, not an expression child, so the structural
            // walk never reaches it — track it explicitly.
            state.TrackTypeReference(typeOfExpression.Type)
            return
        }

        // THE OTHER FIVE TYPE-REFERENCE SLOTS, FOR EXACTLY THE REASON THE `typeof` ARM GIVES ABOVE.
        // `AstChildrenCore.Of` enumerates `Expression` children and a `TypeReference` is not one, so a
        // written type in any of these positions was invisible to every rule until it was tracked here.
        // Each arm still walks its children afterwards: the type is IN ADDITION to the operand, never
        // instead of it — `(Foo)bar`, `bar is Foo` and `f<Foo>(bar)` all read `bar` as well.
        //
        // `x is Foo f` and `x as Foo` were measured reporting a false NL010 from ordinary source.
        // `sizeof(T)`, `stackalloc T[n]` and an explicit call type argument are tracked on the same
        // rule but could not be reached from source at the time of writing — the first two make the
        // columnar parser decline the enclosing function, which suppresses the lint pass for the whole
        // file, and an explicit call type argument parses as a comparison. They are contracted through
        // the walk directly so that fixing either front end cannot silently reopen the hole.
        castExpression := expression as CastExpression
        if castExpression != null {
            state.TrackTypeReference(castExpression.TargetType)
            VisitChildExpressions(castExpression)
            return
        }

        isExpression := expression as IsExpression
        if isExpression != null {
            state.TrackTypeReference(isExpression.Type)
            VisitChildExpressions(isExpression)
            return
        }

        sizeOfExpression := expression as SizeOfExpression
        if sizeOfExpression != null {
            state.TrackTypeReference(sizeOfExpression.Type)
            return
        }

        stackAllocExpression := expression as StackAllocExpression
        if stackAllocExpression != null {
            state.TrackTypeReference(stackAllocExpression.ElementType)
            VisitChildExpressions(stackAllocExpression)
            return
        }

        callExpression := expression as CallExpression
        if callExpression != null {
            typeArguments := callExpression.TypeArguments
            if typeArguments != null {
                for typeArgument in typeArguments {
                    state.TrackTypeReference(typeArgument)
                }
            }

            VisitChildExpressions(callExpression)
            return
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            // The patterns are the ONLY part `AstChildrenCore.Of` cannot hand over — it enumerates the
            // scrutinee, each guard and each arm expression, and a `Pattern` is not an `Expression`.
            // The structural walk still runs, so this arm ADDS the pattern reads rather than replacing
            // anything.
            for matchCase in matchExpression.Cases {
                VisitPattern(matchCase.Pattern)
            }

            VisitChildExpressions(matchExpression)
            return
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            state.PushScope()
            for parameter in lambda.Parameters {
                state.DeclareVariable(parameter.Name, lambda.Line, lambda.Column)
                state.MarkVariableUsed(parameter.Name, false)
            }

            blockBody := lambda.BlockBody
            if blockBody != null {
                VisitStatement(blockBody)
            }

            lambdaBody := lambda.ExpressionBody
            if lambdaBody != null {
                VisitExpression(lambdaBody)
            }

            state.PopScope()
            return
        }

        VisitChildExpressions(expression)
    }

    // Routing through `AstChildrenCore` instead of a per-node child list keeps this FAIL-SAFE: a node
    // kind or a child slot missing from the walk cannot silently skip a subtree and produce false
    // NL001/NL010-class diagnostics — `AstChildrenCore.Of` throws for a node it does not know.
    func VisitChildExpressions(expression: Expression) {
        for child in AstChildrenCore.Of(expression) {
            childExpression := child as Expression
            if childExpression == null {
                throw new InvalidCastException("Unable to cast object of type '" + child.GetType().Name + "' to type 'NSharpLang.Compiler.Ast.Expression'.")
            }

            VisitExpression(childExpression)
        }
    }
}
