namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic


// THE ONLY OWNER OF "WHICH EXPRESSION IS AT THIS POSITION". Task 021 slice 4 deleted the C#
// forwarder `src/NSharpLang.Compiler/AstNodeFinder.cs` that used to wrap this call, so the LSP's
// CompletionHandler and HoverHandler now reach this type directly, exactly as
// CodeIntelligenceNavigation and CompletionReceiverFacts already did.
//
// THE RETURN TYPE IS `object?` AND EVERY CALLER NARROWS IT WITH `as`. The walk is reflective — it
// dispatches on `GetType().Name` and reads properties by name — so it cannot name the AST types it
// answers with. Every node it can return is declared `Expression` in Expressions.nl/Statements.nl
// today, which makes `as Expression` total; it is spelled at every call site anyway, because `as`
// answers NULL for a node of any other kind where a hard cast would throw, and "found the wrong
// kind of node" must degrade to "found nothing" inside a completion or hover request, never to a
// failed LSP call.
class AstNodeFinderCore {
    static func FindExpressionAtPosition(ast: object, line: int, column: int): object? {
        visitor := new AstPositionVisitor(line, column)
        visitor.VisitCompilationUnit(ast)
        return visitor.FoundExpression
    }

    // THE CALL THE POSITION IS THE CALLEE OF — the second question this walk can already answer.
    //
    // "Which member is this" and "which CALL is this member the callee of" are different questions
    // with the same walk behind them, and until now only the first had a door. Hover needs the
    // second to choose an overload (`b.Append("x")` has twenty-six candidates and the argument
    // decides), and SIGNATURE HELP needs exactly the same node for exactly the same reason, so it
    // is one public entry point rather than two private ones.
    //
    // THE ANSWER IS THE INNERMOST CALL, and it is found by IDENTITY rather than by containment. The
    // walk already computes, per call, the best match inside that call's CALLEE subtree; a call
    // whose callee-side match IS the node the walk finally settled on is the call that node is the
    // callee of. Recording candidates as the recursion unwinds puts the inner ones first, so the
    // first identity hit is the innermost — `a.B(x).C(y)` answers `.C`'s call for `C` and `.B`'s
    // for `B`. A position that landed ON a call node is its own answer.
    static func FindCallExpressionAtPosition(ast: object, line: int, column: int): object? {
        visitor := new AstPositionVisitor(line, column)
        visitor.VisitCompilationUnit(ast)
        return visitor.EnclosingCallExpression()
    }

    // THE CLASS WHOSE BODY THE POSITION IS IN — the INNERMOST one, so a member of a nested class
    // answers the nested class. It is what a bare name is resolved against when no source symbol
    // claims it: `Items` inside `class Bag: Collection<string>` is `this.Items`, inherited from a
    // base the project did not declare. A position the walk found nothing at has no enclosing class.
    static func FindEnclosingClassAtPosition(ast: object, line: int, column: int): object? {
        visitor := new AstPositionVisitor(line, column)
        visitor.VisitCompilationUnit(ast)
        return visitor.EnclosingClassDeclaration
    }
}

class AstPositionVisitor {
    targetLine: int
    targetColumn: int
    foundExpressionValue: object?
    calleeOwnerCalls: List<object>
    calleeOwnerTargets: List<object>
    enclosingClassValue: object?

    FoundExpression: object? => foundExpressionValue
    EnclosingClassDeclaration: object? => enclosingClassValue

    constructor(line: int, column: int) {
        targetLine = line
        targetColumn = column
        calleeOwnerCalls = new List<object>()
        calleeOwnerTargets = new List<object>()
    }

    // THE RECORDED CALL WHOSE CALLEE IS THE FOUND NODE. The lists are parallel and in unwind order,
    // so the first identity match is the innermost call — see the entry point's note.
    func EnclosingCallExpression(): object? {
        found := foundExpressionValue
        if found == null {
            return null
        }

        foundNode: object = found
        if foundNode.GetType().Name == "CallExpression" {
            return foundNode
        }

        index := 0
        while index < calleeOwnerTargets.Count {
            candidate: object = calleeOwnerTargets[index]
            if Object.ReferenceEquals(candidate, foundNode) {
                return calleeOwnerCalls[index]
            }

            index = index + 1
        }

        return null
    }

    // A call is recorded only when its CALLEE side produced a match at all; a call whose callee
    // matched nothing can never be the answer, so the lists stay as short as the chain is deep.
    func NoteCalleeOwner(call: object, calleeMatch: object?) {
        if calleeMatch == null {
            return
        }

        calleeOwnerCalls.Add(call)
        calleeOwnerTargets.Add(calleeMatch)
    }

    func VisitCompilationUnit(unit: object) {
        declarations := GetOptionalList(unit, "Declarations")
        if declarations == null {
            return
        }

        for declaration in declarations {
            if declaration != null {
                VisitDeclaration(declaration)
                if foundExpressionValue != null {
                    return
                }
            }
        }
    }

    func VisitDeclaration(declaration: object) {
        typeName := declaration.GetType().Name

        // AN EXPRESSION-BODIED FUNCTION HAS NO `Body` — `func Size(): int => c.Count` carries its one
        // expression in `ExpressionBody` and leaves the block null. Without the second arm every
        // position inside it answered `No symbol found`, or the receiver from a nearby column.
        if typeName == "FunctionDeclaration" {
            body := GetOptionalProperty(declaration, "Body")
            if body != null {
                VisitStatement(body)
                return
            }

            expressionBody := GetOptionalProperty(declaration, "ExpressionBody")
            if expressionBody != null {
                SetFoundExpression(FindExpression(expressionBody))
            }
            return
        }

        if typeName == "ClassDeclaration" {
            members := GetOptionalList(declaration, "Members")
            if members == null {
                return
            }

            for member in members {
                if member != null {
                    VisitDeclaration(member)
                    if foundExpressionValue != null {
                        // The walk unwinds innermost first, so a nested class has already claimed it.
                        if enclosingClassValue == null {
                            enclosingClassValue = declaration
                        }
                        return
                    }
                }
            }
        }
    }

    func VisitStatement(statement: object) {
        typeName := statement.GetType().Name

        if typeName == "BlockStatement" {
            statements := GetRequiredList(statement, "Statements")
            for child in statements {
                if child != null {
                    VisitStatement(child)
                    if foundExpressionValue != null {
                        return
                    }
                }
            }
            return
        }

        if typeName == "ExpressionStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Expression")))
            return
        }

        if typeName == "VariableDeclarationStatement" {
            initializer := GetOptionalProperty(statement, "Initializer")
            if initializer != null {
                SetFoundExpression(FindExpression(initializer))
            }
            return
        }

        if typeName == "ReturnStatement" {
            value := GetOptionalProperty(statement, "Value")
            if value != null {
                SetFoundExpression(FindExpression(value))
            }
            return
        }

        if typeName == "PrintStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Value")))
            return
        }

        // `off <handle>` — the handle is an ORDINARY expression, so hover, definition and rename over
        // it must reach it. Without this arm the statement is a leaf and every position inside it
        // answers `No symbol found`.
        if typeName == "OffStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Handle")))
            return
        }

        if typeName == "IfStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Condition")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "ThenStatement"))
            if foundExpressionValue != null {
                return
            }

            elseStatement := GetOptionalProperty(statement, "ElseStatement")
            if elseStatement != null {
                VisitStatement(elseStatement)
            }
            return
        }

        if typeName == "WhileStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Condition")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
            return
        }

        if typeName == "ForStatement" {
            initializer := GetOptionalProperty(statement, "Initializer")
            if initializer != null {
                VisitStatement(initializer)
                if foundExpressionValue != null {
                    return
                }
            }

            condition := GetOptionalProperty(statement, "Condition")
            if condition != null {
                SetFoundExpression(FindExpression(condition))
                if foundExpressionValue != null {
                    return
                }
            }

            iterator := GetOptionalProperty(statement, "Iterator")
            if iterator != null {
                SetFoundExpression(FindExpression(iterator))
                if foundExpressionValue != null {
                    return
                }
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
            return
        }

        if typeName == "ForeachStatement" {
            SetFoundExpression(FindExpression(GetRequiredProperty(statement, "Collection")))
            if foundExpressionValue != null {
                return
            }

            VisitStatement(GetRequiredProperty(statement, "Body"))
            return
        }

        // A `using` carries an expression in TWO places and only ever one of them at a time: the
        // BOUND form's resource is the initializer of its declaration, the unbound form's is the
        // statement's own `Expression`. Its body is optional — a using DECLARATION has none, because
        // the region it guards is the rest of the enclosing block, and the block walk above is
        // already visiting those statements as siblings.
        if typeName == "UsingStatement" {
            declaration := GetOptionalProperty(statement, "Declaration")
            if declaration != null {
                VisitStatement(declaration)
                if foundExpressionValue != null {
                    return
                }
            }

            resource := GetOptionalProperty(statement, "Expression")
            if resource != null {
                SetFoundExpression(FindExpression(resource))
                if foundExpressionValue != null {
                    return
                }
            }

            body := GetOptionalProperty(statement, "Body")
            if body != null {
                VisitStatement(body)
            }
        }
    }

    func FindExpression(expression: object): object? {
        currentMatch: object? = null
        if IsAtPosition(GetRequiredInt(expression, "Line"), GetRequiredInt(expression, "Column")) {
            currentMatch = expression
        }

        typeName := expression.GetType().Name

        if typeName == "BinaryExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Left")))
            bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(expression, "Right")))
            return bestMatch
        }

        if typeName == "UnaryExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Operand"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        if typeName == "MustExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Expression"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        // A THROW EXPRESSION IS ITS OPERAND'S OWNER, exactly as `must` is. The keyword anchors the
        // node, so a position ON the keyword answers the throw itself (type `never`), while a
        // position inside the exception being raised must reach that expression — otherwise a hover
        // over the exception's type name would be told the throw's own bottom type.
        if typeName == "ThrowExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Expression"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        if typeName == "CallExpression" {
            calleeMatch := FindExpression(GetRequiredProperty(expression, "Callee"))
            NoteCalleeOwner(expression, calleeMatch)
            bestMatch := ChooseBestExpression(currentMatch, calleeMatch)

            arguments := GetRequiredList(expression, "Arguments")
            index := 0
            while index < arguments.Count {
                argument := arguments[index]
                if argument != null {
                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(argument, "Value")))
                }

                index = index + 1
            }

            return bestMatch
        }

        if typeName == "MemberAccessExpression" {
            return ChooseBestExpression(FindExpression(GetRequiredProperty(expression, "Object")), currentMatch)
        }

        if typeName == "IndexAccessExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Object")))
            bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(expression, "Index")))
            return bestMatch
        }

        if typeName == "ArrayLiteralExpression" {
            bestMatch := currentMatch
            elements := GetRequiredList(expression, "Elements")
            index := 0
            while index < elements.Count {
                element := elements[index]
                if element != null {
                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(element))
                }

                index = index + 1
            }

            return bestMatch
        }

        if typeName == "LambdaExpression" {
            expressionBody := GetOptionalProperty(expression, "ExpressionBody")
            if expressionBody != null {
                childMatch := FindExpression(expressionBody)
                return ChooseBestExpression(currentMatch, childMatch)
            }

            blockBody := GetOptionalProperty(expression, "BlockBody")
            if blockBody != null {
                previousFound := foundExpressionValue
                foundExpressionValue = null
                VisitStatement(blockBody)
                childMatch := foundExpressionValue
                foundExpressionValue = previousFound
                return ChooseBestExpression(currentMatch, childMatch)
            }

            return currentMatch
        }

        if typeName == "ParenthesizedExpression" {
            childMatch := FindExpression(GetRequiredProperty(expression, "Inner"))
            return ChooseBestExpression(currentMatch, childMatch)
        }

        // `on <receiver>.<Event> <handler>` — the SAME defect the three arms below were, in the one
        // expression whose children are a whole member chain and a whole lambda. Without this arm the
        // subscription is a LEAF: hovering the receiver, the event name or anything in the handler body
        // answered from the `on` node, so every one of them reported the subscription HANDLE's type
        // instead of its own. The receiver goes first because the handler is the later span, and
        // `ChooseBestExpression` picks by position either way.
        if typeName == "OnSubscriptionExpression" {
            bestMatch := ChooseBestExpression(currentMatch, FindExpression(GetRequiredProperty(expression, "Target")))
            return ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(expression, "Handler")))
        }

        // THE THREE ARMS BELOW WERE THE WHOLE OF IDE DEFECTS D1 AND D2, and they are three arms
        // rather than one because the walk descends by SHAPE. Without them a `new Foo { A: x.Y() }`
        // and a `$"{x.Y}"` are LEAVES: the node on the target line is never asked about its
        // children, so hover and completion answer from the enclosing node — `No symbol found` for
        // the initializer (nothing on that line is a match at all) and `string` for every member in
        // an interpolation hole (the interpolated string itself is the only match, and its type is
        // `string`). Neither was a coordinate bug: `MemberAccessExpression` carries its DOT's
        // position, so once the walk REACHES the hole, `ChooseBestExpression` already picks the
        // right link of the chain.
        if typeName == "NewExpression" {
            bestMatch := currentMatch
            constructorArguments := GetRequiredList(expression, "ConstructorArguments")
            index := 0
            while index < constructorArguments.Count {
                argument := constructorArguments[index]
                if argument != null {
                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(argument, "Value")))
                }

                index = index + 1
            }

            arrayLength := GetOptionalProperty(expression, "ArrayLengthExpression")
            if arrayLength != null {
                bestMatch = ChooseBestExpression(bestMatch, FindExpression(arrayLength))
            }

            // The initializer is itself an `Expression`, so it goes through the arm below rather
            // than being walked here a second time.
            initializer := GetOptionalProperty(expression, "Initializer")
            if initializer != null {
                bestMatch = ChooseBestExpression(bestMatch, FindExpression(initializer))
            }

            return bestMatch
        }

        // A `PropertyInitializer` is NOT an `Expression` — it has no position of its own worth
        // matching — so the walk reads through it to the two expressions it holds. An indexer
        // initializer carries both; a plain one carries only `Value`.
        if typeName == "ObjectInitializerExpression" {
            bestMatch := currentMatch
            properties := GetRequiredList(expression, "Properties")
            index := 0
            while index < properties.Count {
                property := properties[index]
                if property != null {
                    indexExpression := GetOptionalProperty(property, "IndexExpression")
                    if indexExpression != null {
                        bestMatch = ChooseBestExpression(bestMatch, FindExpression(indexExpression))
                    }

                    bestMatch = ChooseBestExpression(bestMatch, FindExpression(GetRequiredProperty(property, "Value")))
                }

                index = index + 1
            }

            return bestMatch
        }

        // A part is a HOLE or it is TEXT, and the reflective read tells them apart for free: only
        // `InterpolatedStringHole` has an `Expression`, so a text segment answers null and is
        // skipped without this owner naming either type.
        if typeName == "InterpolatedStringExpression" {
            bestMatch := currentMatch
            parts := GetRequiredList(expression, "Parts")
            index := 0
            while index < parts.Count {
                part := parts[index]
                if part != null {
                    holeExpression := GetOptionalProperty(part, "Expression")
                    if holeExpression != null {
                        bestMatch = ChooseBestExpression(bestMatch, FindExpression(holeExpression))
                    }
                }

                index = index + 1
            }

            return bestMatch
        }

        return currentMatch
    }

    func SetFoundExpression(expression: object?) {
        if expression != null {
            foundExpressionValue = expression
        }
    }

    func ChooseBestExpression(current: object?, candidate: object?): object? {
        if current == null {
            return candidate
        }

        if candidate == null {
            return current
        }

        currentLine := Math.Max(0, GetRequiredInt(current, "Line") - 1)
        candidateLine := Math.Max(0, GetRequiredInt(candidate, "Line") - 1)
        if currentLine != targetLine {
            return candidate
        }

        if candidateLine != targetLine {
            return current
        }

        currentColumn := Math.Max(0, GetRequiredInt(current, "Column") - 1)
        candidateColumn := Math.Max(0, GetRequiredInt(candidate, "Column") - 1)
        if candidateColumn >= currentColumn && candidateColumn <= targetColumn {
            return candidate
        }

        return current
    }

    func IsAtPosition(line: int, column: int): bool {
        nodeLine := Math.Max(0, line - 1)
        nodeColumn := Math.Max(0, column - 1)
        return nodeLine == targetLine && nodeColumn <= targetColumn
    }

    static func GetRequiredList(owner: object, propertyName: string): IList {
        value := GetRequiredProperty(owner, propertyName)
        list := value as IList
        if list == null {
            throw new InvalidOperationException("AstNodeFinder expected a list.")
        }

        return list
    }

    static func GetRequiredInt(owner: object, propertyName: string): int {
        return Convert.ToInt32(GetRequiredProperty(owner, propertyName))
    }

    static func GetRequiredProperty(owner: object, propertyName: string): object {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            throw new InvalidOperationException("AstNodeFinder expected a property.")
        }

        return value
    }

    static func GetOptionalList(owner: object, propertyName: string): IList? {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            return null
        }

        list := value as IList
        if list == null {
            throw new InvalidOperationException("AstNodeFinder expected a list.")
        }

        return list
    }

    static func GetOptionalProperty(owner: object, propertyName: string): object? {
        property := owner.GetType().GetProperty(propertyName)
        if property != null {
            return property.GetValue(owner)
        }

        field := owner.GetType().GetField(propertyName)
        if field != null {
            return field.GetValue(owner)
        }

        return null
    }
}
