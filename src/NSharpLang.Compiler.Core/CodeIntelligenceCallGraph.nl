namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CALL GRAPH — who calls whom, and the answer `query call-graph` prints.
//
// The whole territory is here: the four-level walk that records caller→callee edges, and the
// selection that turns the accumulated map into a `CallGraphResult`. Owning the selection as well as
// the walk is what keeps the accumulator INSIDE the language — the C# spelled it
// `Dictionary<string, List<(string, string?, int, int)>>`, and a tuple-valued dictionary crossing an
// assembly boundary is a question this owner never has to ask.
//
// The map's ITERATION ORDER is an observable contract: the unfiltered arm returns the first `limit`
// edges in it. The C# inherited that order from `Dictionary`'s internals; here it is carried
// explicitly in `callerOrder`, so the contract is stated rather than assumed.
class CodeIntelligenceCallGraph {
    static func Build(units: List<CompilationUnit>, relativeFiles: List<string>, functionName: string?, limit: int): CallGraphResult {
        callSites := new Dictionary<string, List<CallSiteResult>>(StringComparer.Ordinal)
        callerOrder := new List<string>()

        unitIndex := 0
        while unitIndex < units.Count {
            CollectUnit(units[unitIndex], relativeFiles[unitIndex], callSites, callerOrder)
            unitIndex = unitIndex + 1
        }

        if functionName == null {
            return Unfiltered(callSites, callerOrder, limit)
        }

        return ForFunction(callSites, callerOrder, functionName, limit)
    }

    // ── The two selections ──────────────────────────────────────────────
    // Unfiltered: every edge in map order up to the limit, and NO callers at all. A limit of zero
    // truncates before the first edge rather than after it.
    static func Unfiltered(callSites: Dictionary<string, List<CallSiteResult>>, callerOrder: List<string>, limit: int): CallGraphResult {
        callees := new List<CallSiteResult>()
        callers := new List<CallSiteResult>()
        truncated := false

        orderIndex := 0
        while orderIndex < callerOrder.Count {
            bucket := callSites[callerOrder[orderIndex]]
            edgeIndex := 0
            while edgeIndex < bucket.Count {
                if callees.Count >= limit {
                    truncated = true
                    break
                }

                callees.Add(bucket[edgeIndex])
                edgeIndex = edgeIndex + 1
            }

            if truncated {
                break
            }

            orderIndex = orderIndex + 1
        }

        return new CallGraphResult(null, callers, callees, truncated)
    }

    // Function-specific: the named function's own edges are its CALLEES, and every edge anywhere
    // that names it is a CALLER — reported under the calling function's name at the call site's own
    // position. The truncation test is on the COMBINED count, and it halves both lists.
    static func ForFunction(callSites: Dictionary<string, List<CallSiteResult>>, callerOrder: List<string>, functionName: string, limit: int): CallGraphResult {
        callees := new List<CallSiteResult>()
        direct: List<CallSiteResult>? = null
        if callSites.TryGetValue(functionName, out direct) && direct != null {
            index := 0
            while index < direct.Count {
                callees.Add(direct[index])
                index = index + 1
            }
        }

        callers := new List<CallSiteResult>()
        orderIndex := 0
        while orderIndex < callerOrder.Count {
            callerName := callerOrder[orderIndex]
            bucket := callSites[callerName]
            edgeIndex := 0
            while edgeIndex < bucket.Count {
                edge := bucket[edgeIndex]
                if String.Equals(edge.Name, functionName, StringComparison.Ordinal) {
                    callers.Add(new CallSiteResult(callerName, edge.File, edge.Line, edge.Column))
                }

                edgeIndex = edgeIndex + 1
            }

            orderIndex = orderIndex + 1
        }

        truncated := callees.Count + callers.Count > limit
        if truncated {
            half := limit / 2
            return new CallGraphResult(functionName, Take(callers, half), Take(callees, half), true)
        }

        return new CallGraphResult(functionName, callers, callees, false)
    }

    static func Take(items: List<CallSiteResult>, count: int): List<CallSiteResult> {
        results := new List<CallSiteResult>()
        index := 0
        while index < items.Count && index < count {
            results.Add(items[index])
            index = index + 1
        }

        return results
    }

    // ── The walk ────────────────────────────────────────────────────────
    static func CollectUnit(unit: CompilationUnit, relativeFile: string, callSites: Dictionary<string, List<CallSiteResult>>, callerOrder: List<string>) {
        index := 0
        while index < unit.Declarations.Count {
            CollectDeclaration(unit.Declarations[index], null, relativeFile, callSites, callerOrder)
            index = index + 1
        }
    }

    // Only a function opens a bucket. A type contributes nothing itself; it renames its members'
    // caller with its own name, which is why `Widget.Draw` and a free `Draw` are different keys —
    // and why two files declaring the same qualified name SHARE one bucket, appended in file order.
    static func CollectDeclaration(declaration: Declaration, ownerContext: string?, relativeFile: string, callSites: Dictionary<string, List<CallSiteResult>>, callerOrder: List<string>) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            callerName := functionDeclaration.Name
            if ownerContext != null {
                callerName = ownerContext + "." + functionDeclaration.Name
            }

            if callSites.ContainsKey(callerName) == false {
                callSites[callerName] = new List<CallSiteResult>()
                callerOrder.Add(callerName)
            }

            if functionDeclaration.Body != null {
                CollectStatement(functionDeclaration.Body, callerName, relativeFile, callSites)
            }

            if functionDeclaration.ExpressionBody != null {
                CollectExpression(functionDeclaration.ExpressionBody, callerName, relativeFile, callSites)
            }

            return
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            CollectMembers(classDeclaration.Members, classDeclaration.Name, relativeFile, callSites, callerOrder)
            return
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            CollectMembers(structDeclaration.Members, structDeclaration.Name, relativeFile, callSites, callerOrder)
            return
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            CollectMembers(recordDeclaration.Members, recordDeclaration.Name, relativeFile, callSites, callerOrder)
            return
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            CollectMembers(interfaceDeclaration.Members, interfaceDeclaration.Name, relativeFile, callSites, callerOrder)
        }
    }

    static func CollectMembers(members: List<Declaration>, ownerName: string, relativeFile: string, callSites: Dictionary<string, List<CallSiteResult>>, callerOrder: List<string>) {
        index := 0
        while index < members.Count {
            CollectDeclaration(members[index], ownerName, relativeFile, callSites, callerOrder)
            index = index + 1
        }
    }

    // Seven statement shapes carry expressions. Everything else — `for`, `match`, `try`, `yield`,
    // a bare `alloc` block — contributes no edges, and that gap is inherited deliberately: it is the
    // C#'s behaviour and a differential would catch any change to it.
    static func CollectStatement(statement: Statement, callerName: string, relativeFile: string, callSites: Dictionary<string, List<CallSiteResult>>) {
        block := statement as BlockStatement
        if block != null {
            index := 0
            while index < block.Statements.Count {
                CollectStatement(block.Statements[index], callerName, relativeFile, callSites)
                index = index + 1
            }

            return
        }

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            CollectExpression(expressionStatement.Expression, callerName, relativeFile, callSites)
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            if returnStatement.Value != null {
                CollectExpression(returnStatement.Value, callerName, relativeFile, callSites)
            }

            return
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            if variableDeclaration.Initializer != null {
                CollectExpression(variableDeclaration.Initializer, callerName, relativeFile, callSites)
            }

            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            CollectExpression(ifStatement.Condition, callerName, relativeFile, callSites)
            CollectStatement(ifStatement.ThenStatement, callerName, relativeFile, callSites)
            if ifStatement.ElseStatement != null {
                CollectStatement(ifStatement.ElseStatement, callerName, relativeFile, callSites)
            }

            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            CollectExpression(whileStatement.Condition, callerName, relativeFile, callSites)
            CollectStatement(whileStatement.Body, callerName, relativeFile, callSites)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            CollectExpression(foreachStatement.Collection, callerName, relativeFile, callSites)
            CollectStatement(foreachStatement.Body, callerName, relativeFile, callSites)
        }
    }

    // A call records its edge FIRST, then descends into its arguments and finally into its own
    // callee — so `a().b()` reports the outer call before the inner one.
    static func CollectExpression(expression: Expression, callerName: string, relativeFile: string, callSites: Dictionary<string, List<CallSiteResult>>) {
        call := expression as CallExpression
        if call != null {
            calleeName := CodeIntelligenceDisplayText.ExtractCalleeName(call.Callee)
            if calleeName != null {
                callSites[callerName].Add(new CallSiteResult(calleeName, relativeFile, call.Line, call.Column))
            }

            argumentIndex := 0
            while argumentIndex < call.Arguments.Count {
                CollectExpression(call.Arguments[argumentIndex].Value, callerName, relativeFile, callSites)
                argumentIndex = argumentIndex + 1
            }

            CollectExpression(call.Callee, callerName, relativeFile, callSites)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            CollectExpression(memberAccess.Object, callerName, relativeFile, callSites)
            return
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            // Only the assigned VALUE is walked; a call in the assignment TARGET is not an edge.
            CollectExpression(assignment.Value, callerName, relativeFile, callSites)
            return
        }

        binary := expression as BinaryExpression
        if binary != null {
            CollectExpression(binary.Left, callerName, relativeFile, callSites)
            CollectExpression(binary.Right, callerName, relativeFile, callSites)
            return
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            partIndex := 0
            while partIndex < interpolated.Parts.Count {
                hole := interpolated.Parts[partIndex] as InterpolatedStringHole
                if hole != null {
                    CollectExpression(hole.Expression, callerName, relativeFile, callSites)
                }

                partIndex = partIndex + 1
            }
        }
    }
}
