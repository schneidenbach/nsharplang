namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A LOOP'S BACK EDGE TAKES AWAY — the paths a flow fact may not survive a second turn of.
//
// THE ANALYZER WALKS A LOOP BODY ONCE, AND THE PROGRAM RUNS IT MANY TIMES. That gap is the whole
// problem this owner exists for. A fact proved BEFORE the loop is true on the first turn and may be
// false on every later one:
//
//     if doc.Error != null {
//         while more {
//             use(doc.Error.Message)   // turn 2 reads whatever the line below left behind
//             doc.Error = maybeNull
//         }
//     }
//
// A single forward walk sees the read before the write and answers "not null", which is the answer
// for turn ONE only. The join at the loop's head has to include the back edge, and the back edge
// carries everything the body wrote.
//
// SO THE KILL SET IS COMPUTED FROM THE SYNTAX, BEFORE THE BODY IS WALKED. Every stable path the
// body (and, for a `for`, its update clause) can write is invalidated at the loop head; the
// condition is then extracted against the joined state, so `while x != null { … }` still narrows
// `x` inside its own body. This is the lattice answer written the cheap way round: one pass plus a
// kill set, rather than iterating the body to a fixed point and reporting every diagnostic twice.
//
// IT IS DELIBERATELY A SYNTACTIC OVER-APPROXIMATION. A write that can never execute still kills the
// fact, because deciding otherwise is the reachability question and this is not the place to ask it.
// Over-approximating costs a re-proof — the author writes the guard again inside the loop, which is
// what the program means anyway — while under-approximating costs a missed NL905 on a real null
// dereference.
//
// WHAT COUNTS AS A WRITE is exactly what invalidates a fact anywhere else in the analyzer: an
// assignment, an increment or decrement, and a `ref`/`out` argument — each named by the STABLE PATH
// it targets, so `doc.Error = e` kills `doc.Error` and everything under it while leaving `doc`
// alone. A method call on a receiver is NOT a write: C# is deliberately optimistic about a property
// a call could have changed behind the analyzer's back, and N# follows it.
//
// THE WALK DESCENDS INTO LAMBDAS AND LOCAL FUNCTIONS declared in the body, because a closure that
// assigns a captured local is a write the loop performs. It descends into nested loops and `try`
// blocks for the same reason. It does NOT descend into a pattern: a pattern DECLARES names, and a
// declaration introduces a binding rather than writing one that already exists.
class AnalyzerLoopCarriedNullFacts {

    // The stable paths a loop body, plus an optional update clause, can write. `paths` may hold
    // duplicates — the caller invalidates each one, and invalidating twice costs nothing.
    static func CollectWrittenPaths(body: Statement?, iterator: Expression?, paths: List<string>) {
        CollectFromStatement(body, paths)
        CollectFromExpression(iterator, paths)
    }

    static func CollectFromStatement(statement: Statement?, paths: List<string>) {
        if statement == null {
            return
        }

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            CollectFromExpression(expressionStatement.Expression, paths)
            return
        }

        declaration := statement as VariableDeclarationStatement
        if declaration != null {
            CollectFromExpression(declaration.Initializer, paths)
            return
        }

        deconstruction := statement as TupleDeconstructionStatement
        if deconstruction != null {
            CollectFromExpression(deconstruction.Initializer, paths)

            // `(x, y) = pair` writes names that already exist; `(x, y) := pair` introduces them.
            if deconstruction.IsAssignment {
                for name in deconstruction.Names {
                    paths.Add(name)
                }
            }

            return
        }

        block := statement as BlockStatement
        if block != null {
            for nested in block.Statements {
                CollectFromStatement(nested, paths)
            }

            return
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            CollectFromStatement(allocBlock.Body, paths)
            return
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            CollectFromStatement(allowBlock.Body, paths)
            return
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            CollectFromStatement(unsafeBlock.Body, paths)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            CollectFromExpression(ifStatement.Condition, paths)
            CollectFromStatement(ifStatement.ThenStatement, paths)
            CollectFromStatement(ifStatement.ElseStatement, paths)
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            CollectFromStatement(forStatement.Initializer, paths)
            CollectFromExpression(forStatement.Condition, paths)
            CollectFromExpression(forStatement.Iterator, paths)
            CollectFromStatement(forStatement.Body, paths)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            CollectFromExpression(foreachStatement.Collection, paths)
            CollectFromStatement(foreachStatement.Body, paths)
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            CollectFromExpression(awaitForeachStatement.Collection, paths)
            CollectFromStatement(awaitForeachStatement.Body, paths)
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            CollectFromExpression(whileStatement.Condition, paths)
            CollectFromStatement(whileStatement.Body, paths)
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            CollectFromExpression(returnStatement.Value, paths)
            return
        }

        yieldStatement := statement as YieldStatement
        if yieldStatement != null {
            CollectFromExpression(yieldStatement.Value, paths)
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            CollectFromExpression(throwStatement.Expression, paths)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            CollectFromStatement(tryStatement.TryBlock, paths)
            for clause in tryStatement.CatchClauses {
                CollectFromStatement(clause.Block, paths)
            }

            CollectFromStatement(tryStatement.FinallyBlock, paths)
            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            CollectFromStatement(usingStatement.Declaration, paths)
            CollectFromExpression(usingStatement.Expression, paths)
            CollectFromStatement(usingStatement.Body, paths)
            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            CollectFromExpression(lockStatement.LockObject, paths)
            CollectFromStatement(lockStatement.Body, paths)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            CollectFromExpression(switchStatement.Value, paths)
            for switchCase in switchStatement.Cases {
                for caseStatement in switchCase.Statements {
                    CollectFromStatement(caseStatement, paths)
                }
            }

            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            CollectFromExpression(printStatement.Value, paths)
            return
        }

        offStatement := statement as OffStatement
        if offStatement != null {
            CollectFromExpression(offStatement.Handle, paths)
            return
        }

        assertStatement := statement as AssertStatement
        if assertStatement != null {
            CollectFromExpression(assertStatement.Condition, paths)
            CollectFromExpression(assertStatement.Message, paths)
            return
        }

        assertThrows := statement as AssertThrowsStatement
        if assertThrows != null {
            CollectFromStatement(assertThrows.Body, paths)
            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            CollectFromStatement(localFunction.Function.Body, paths)
            CollectFromExpression(localFunction.Function.ExpressionBody, paths)
        }
    }

    static func CollectFromExpression(expression: Expression?, paths: List<string>) {
        if expression == null {
            return
        }

        // THE THREE WRITE SHAPES COME FIRST, because each of them also has operands to descend into
        // and the write must be recorded whichever way the descent goes.
        assignment := expression as AssignmentExpression
        if assignment != null {
            AddWrittenPath(assignment.Target, paths)
            CollectFromExpression(assignment.Target, paths)
            CollectFromExpression(assignment.Value, paths)
            return
        }

        unary := expression as UnaryExpression
        if unary != null {
            if IsIncrementOrDecrement(unary.Operator) {
                AddWrittenPath(unary.Operand, paths)
            }

            CollectFromExpression(unary.Operand, paths)
            return
        }

        call := expression as CallExpression
        if call != null {
            CollectFromExpression(call.Callee, paths)
            CollectFromArguments(call.Arguments, paths)
            return
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            CollectFromArguments(newExpression.ConstructorArguments, paths)
            CollectFromExpression(newExpression.Initializer, paths)
            CollectFromExpression(newExpression.ArrayLengthExpression, paths)
            return
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            CollectFromExpression(lambda.ExpressionBody, paths)
            CollectFromStatement(lambda.BlockBody, paths)
            return
        }

        binary := expression as BinaryExpression
        if binary != null {
            CollectFromExpression(binary.Left, paths)
            CollectFromExpression(binary.Right, paths)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            CollectFromExpression(memberAccess.Object, paths)
            return
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            CollectFromExpression(indexAccess.Object, paths)
            CollectFromExpression(indexAccess.Index, paths)
            return
        }

        ternary := expression as TernaryExpression
        if ternary != null {
            CollectFromExpression(ternary.Condition, paths)
            CollectFromExpression(ternary.ThenExpression, paths)
            CollectFromExpression(ternary.ElseExpression, paths)
            return
        }

        subscription := expression as OnSubscriptionExpression
        if subscription != null {
            CollectFromExpression(subscription.Target, paths)
            CollectFromExpression(subscription.Handler, paths)
            return
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            for element in arrayLiteral.Elements {
                CollectFromExpression(element, paths)
            }

            return
        }

        tuple := expression as TupleExpression
        if tuple != null {
            for tupleElement in tuple.Elements {
                CollectFromExpression(tupleElement.Value, paths)
            }

            return
        }

        objectInitializer := expression as ObjectInitializerExpression
        if objectInitializer != null {
            CollectFromInitializers(objectInitializer.Properties, paths)
            return
        }

        withExpression := expression as WithExpression
        if withExpression != null {
            CollectFromExpression(withExpression.Target, paths)
            CollectFromInitializers(withExpression.Properties, paths)
            return
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            CollectFromExpression(matchExpression.Value, paths)
            for matchCase in matchExpression.Cases {
                CollectFromExpression(matchCase.Guard, paths)
                CollectFromExpression(matchCase.Expression, paths)
            }

            return
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            for part in interpolated.Parts {
                hole := part as InterpolatedStringHole
                if hole != null {
                    CollectFromExpression(hole.Expression, paths)
                }
            }

            return
        }

        range := expression as RangeExpression
        if range != null {
            CollectFromExpression(range.Start, paths)
            CollectFromExpression(range.End, paths)
            return
        }

        CollectFromSingleOperand(expression, paths)
    }

    // THE ONE-OPERAND WRAPPERS, each of which changes what its operand MEANS and none of which can
    // write on its own. They are gathered here rather than spelled out above so the shape of the walk
    // stays readable: everything up there either writes or has more than one child.
    static func CollectFromSingleOperand(expression: Expression, paths: List<string>) {
        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            CollectFromExpression(parenthesized.Inner, paths)
            return
        }

        cast := expression as CastExpression
        if cast != null {
            CollectFromExpression(cast.Expression, paths)
            return
        }

        isExpression := expression as IsExpression
        if isExpression != null {
            CollectFromExpression(isExpression.Expression, paths)
            return
        }

        unwrap := expression as MustExpression
        if unwrap != null {
            CollectFromExpression(unwrap.Expression, paths)
            return
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            CollectFromExpression(awaitExpression.Expression, paths)
            return
        }

        throwExpression := expression as ThrowExpression
        if throwExpression != null {
            CollectFromExpression(throwExpression.Expression, paths)
            return
        }

        spread := expression as SpreadExpression
        if spread != null {
            CollectFromExpression(spread.Expression, paths)
            return
        }

        allocExpression := expression as AllocExpression
        if allocExpression != null {
            CollectFromExpression(allocExpression.Expression, paths)
            return
        }

        stackAlloc := expression as StackAllocExpression
        if stackAlloc != null {
            CollectFromExpression(stackAlloc.LengthExpression, paths)
            return
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            CollectFromExpression(checkedExpression.Expression, paths)
            return
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            CollectFromExpression(uncheckedExpression.Expression, paths)
            return
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            CollectFromExpression(nameofExpression.Target, paths)
        }
    }

    static func CollectFromArguments(arguments: List<Argument>, paths: List<string>) {
        for argument in arguments {
            // A `ref` or `out` argument hands the callee the STORAGE, so the call is a write to it.
            if argument.Modifier != ArgumentModifier.None {
                AddWrittenPath(argument.Value, paths)
            }

            CollectFromExpression(argument.Value, paths)
        }
    }

    static func CollectFromInitializers(properties: List<PropertyInitializer>, paths: List<string>) {
        for property in properties {
            CollectFromExpression(property.IndexExpression, paths)
            CollectFromExpression(property.Value, paths)
        }
    }

    static func IsIncrementOrDecrement(unaryOperator: UnaryOperator): bool {
        return unaryOperator == UnaryOperator.PreIncrement || unaryOperator == UnaryOperator.PreDecrement || unaryOperator == UnaryOperator.PostIncrement || unaryOperator == UnaryOperator.PostDecrement
    }

    // A WRITE THE FLOW CAN NAME. An unstable target — `rows[i].Error`, `Load().Error` — carries no
    // fact to begin with, so there is nothing to invalidate and nothing is recorded.
    static func AddWrittenPath(target: Expression, paths: List<string>) {
        path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(target)
        if path == null {
            return
        }

        paths.Add(path)
    }
}
