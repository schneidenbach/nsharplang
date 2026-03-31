using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using ServerSymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/prepareCallHierarchy requests.
/// Resolves the function at the cursor to a CallHierarchyItem so that
/// incoming/outgoing call queries can follow.
/// </summary>
public class CallHierarchyPrepareHandler : CallHierarchyPrepareHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyPrepareHandler> _logger;

    public CallHierarchyPrepareHandler(DocumentManager documentManager, ILogger<CallHierarchyPrepareHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyItem>?> Handle(
        CallHierarchyPrepareParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<CallHierarchyItem>?>(null);
        }

        try
        {
            var line = request.Position.Line;
            var character = request.Position.Character;

            var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            _logger.LogDebug("Call hierarchy prepare for: {Word}", word);

            // Check if the word is a known function/method symbol
            if (!IsFunctionSymbol(doc, word))
            {
                _logger.LogDebug("Symbol '{Word}' is not a function or method", word);
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            // Find the declaration location for this function
            var declLocation = FindFunctionDeclarationLocation(doc, word);
            if (declLocation == null)
            {
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            var (declUri, declRange, selectionRange) = declLocation.Value;

            var item = new CallHierarchyItem
            {
                Name = word,
                Kind = LspSymbolKind.Function,
                Uri = DocumentUri.From(declUri),
                Range = declRange,
                SelectionRange = selectionRange
            };

            return Task.FromResult<Container<CallHierarchyItem>?>(
                new Container<CallHierarchyItem>(item));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy prepare");
            return Task.FromResult<Container<CallHierarchyItem>?>(null);
        }
    }

    /// <summary>
    /// Checks whether the given word corresponds to a function or method in the document's symbol info.
    /// </summary>
    private static bool IsFunctionSymbol(DocumentState doc, string word)
    {
        if (doc.SymbolsInfo != null && doc.SymbolsInfo.TryGetValue(word, out var symbolInfo))
        {
            return symbolInfo.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method;
        }

        // Also check if there are symbol locations with function/method kind
        if (doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(word, out var locations))
        {
            return locations.Any(loc => loc.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method);
        }

        return false;
    }

    /// <summary>
    /// Finds the declaration location for a function, returning the full range and selection range.
    /// Returns null if the function cannot be located.
    /// </summary>
    private (string Uri, LspRange Range, LspRange SelectionRange)? FindFunctionDeclarationLocation(
        DocumentState doc,
        string functionName)
    {
        // Try symbol locations first (these have precise line/column info)
        if (doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(functionName, out var locations))
        {
            var funcLoc = locations.FirstOrDefault(
                loc => loc.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method);

            if (funcLoc != null)
            {
                // SymbolLocation uses 0-based line/column
                var selectionRange = new LspRange(
                    funcLoc.Line, funcLoc.Column,
                    funcLoc.Line, funcLoc.Column + Math.Max(1, funcLoc.Length));

                // Walk the AST to find the full function range
                var fullRange = FindFunctionRangeInAst(doc, functionName, funcLoc.Line);
                var range = fullRange ?? selectionRange;

                return (funcLoc.Uri, range, selectionRange);
            }
        }

        // Fallback: walk AST declarations directly
        if (doc.CompilationUnit?.Declarations != null)
        {
            var funcDecl = FindFunctionDeclaration(doc.CompilationUnit.Declarations, functionName);
            if (funcDecl != null)
            {
                // AST line/column are 1-based; LSP is 0-based
                var lspLine = Math.Max(0, funcDecl.Line - 1);
                var lspColumn = Math.Max(0, funcDecl.Column - 1);

                var selectionRange = new LspRange(
                    lspLine, lspColumn,
                    lspLine, lspColumn + functionName.Length);

                var bodyEndLine = GetFunctionEndLine(funcDecl);
                // Ensure end character >= start character when on the same line
                var endChar = bodyEndLine == lspLine ? lspColumn + functionName.Length : 0;
                var range = new LspRange(lspLine, lspColumn, bodyEndLine, endChar);

                return (doc.Uri, range, selectionRange);
            }
        }

        return null;
    }

    /// <summary>
    /// Searches AST declarations (including nested type members) for a FunctionDeclaration by name.
    /// </summary>
    private static FunctionDeclaration? FindFunctionDeclaration(List<Declaration> declarations, string name)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func && string.Equals(func.Name, name, StringComparison.Ordinal))
            {
                return func;
            }

            // Search inside type declarations for methods
            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                var nested = FindFunctionDeclaration(members, name);
                if (nested != null) return nested;
            }
        }

        return null;
    }

    /// <summary>
    /// Walks the AST to find the full range of a function declaration at the given 0-based line.
    /// </summary>
    private static LspRange? FindFunctionRangeInAst(DocumentState doc, string name, int line0)
    {
        if (doc.CompilationUnit?.Declarations == null)
            return null;

        var funcDecl = FindFunctionDeclarationAtLine(doc.CompilationUnit.Declarations, name, line0 + 1);
        if (funcDecl == null)
            return null;

        var startLine = Math.Max(0, funcDecl.Line - 1);
        var startCol = Math.Max(0, funcDecl.Column - 1);
        var endLine = GetFunctionEndLine(funcDecl);
        // Ensure end character >= start character when on the same line
        var endCol = endLine == startLine ? startCol + name.Length : 0;

        return new LspRange(startLine, startCol, endLine, endCol);
    }

    /// <summary>
    /// Finds a function declaration at a specific 1-based line number.
    /// </summary>
    private static FunctionDeclaration? FindFunctionDeclarationAtLine(List<Declaration> declarations, string name, int line1)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func
                && string.Equals(func.Name, name, StringComparison.Ordinal)
                && func.Line == line1)
            {
                return func;
            }

            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                var nested = FindFunctionDeclarationAtLine(members, name, line1);
                if (nested != null) return nested;
            }
        }

        return null;
    }

    /// <summary>
    /// Estimates the end line of a function from its body. Returns a 0-based line number.
    /// </summary>
    private static int GetFunctionEndLine(FunctionDeclaration func)
    {
        // AST lines are 1-based
        var startLine = Math.Max(0, func.Line - 1);

        if (func.Body != null && func.Body.Statements.Count > 0)
        {
            var lastStmt = func.Body.Statements[^1];
            return Math.Max(0, lastStmt.Line - 1) + 1; // +1 for closing brace estimate
        }

        if (func.ExpressionBody != null)
        {
            return Math.Max(0, func.ExpressionBody.Line - 1);
        }

        return startLine;
    }

    protected override CallHierarchyRegistrationOptions CreateRegistrationOptions(
        CallHierarchyCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CallHierarchyRegistrationOptions();
    }
}

/// <summary>
/// Handles callHierarchy/incomingCalls requests.
/// Finds all functions that call the given function (callers).
/// </summary>
public class CallHierarchyIncomingHandler : CallHierarchyIncomingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyIncomingHandler> _logger;

    public CallHierarchyIncomingHandler(DocumentManager documentManager, ILogger<CallHierarchyIncomingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyIncomingCall>?> Handle(
        CallHierarchyIncomingCallsParams request,
        CancellationToken cancellationToken)
    {
        var item = request.Item;
        var uri = item.Uri.ToString();

        try
        {
            _logger.LogDebug("Call hierarchy incoming calls for: {Name}", item.Name);

            // Use semantic project references to find all call sites for this function
            var references = _documentManager.FindProjectReferences(
                uri,
                item.SelectionRange.Start.Line,
                item.SelectionRange.Start.Character);

            if (references != null && references.Count > 0)
            {
                return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                    BuildIncomingCallsFromProjectReferences(uri, item.Name, references));
            }

            // Fallback: walk all open documents to find call expressions that invoke this function
            var incomingCalls = FindIncomingCallsFromAst(item.Name, cancellationToken);
            if (incomingCalls.Count > 0)
            {
                return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                    new Container<CallHierarchyIncomingCall>(incomingCalls));
            }

            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                new Container<CallHierarchyIncomingCall>());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy incoming calls");
            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                new Container<CallHierarchyIncomingCall>());
        }
    }

    /// <summary>
    /// Builds incoming calls from semantic project reference results.
    /// Groups references by enclosing function to produce one CallHierarchyIncomingCall per caller.
    /// </summary>
    private Container<CallHierarchyIncomingCall> BuildIncomingCallsFromProjectReferences(
        string originUri,
        string targetFunctionName,
        List<Compiler.CodeIntelligence.ReferenceResult> references)
    {
        var projectRoot = _documentManager.GetProjectRootForUri(originUri);

        // Group references by their enclosing function
        var callerGroups = new Dictionary<string, (CallHierarchyItem Item, List<LspRange> Ranges)>();

        foreach (var reference in references)
        {
            if (reference.IsDefinition)
                continue;

            var filePath = _documentManager.ResolveProjectFilePath(projectRoot, reference.File);
            var fileUri = new Uri(filePath).AbsoluteUri;
            var doc = _documentManager.GetDocument(fileUri);

            // Convert 1-based reference coords to 0-based LSP coords
            var refLine0 = reference.Line - 1;
            var refCol0 = reference.Column - 1;

            var callRange = new LspRange(
                refLine0, refCol0,
                refLine0, refCol0 + Math.Max(1, reference.Length));

            // Determine enclosing function for this reference
            var enclosingFunc = doc?.CompilationUnit?.Declarations != null
                ? FindEnclosingFunction(doc.CompilationUnit.Declarations, reference.Line, reference.Column)
                : null;

            var callerName = enclosingFunc?.Name ?? reference.Context ?? "<unknown>";
            var callerKey = $"{fileUri}:{callerName}";

            if (!callerGroups.TryGetValue(callerKey, out var group))
            {
                var callerLine = enclosingFunc != null ? Math.Max(0, enclosingFunc.Line - 1) : refLine0;
                var callerCol = enclosingFunc != null ? Math.Max(0, enclosingFunc.Column - 1) : 0;
                var callerEndLine = enclosingFunc != null
                    ? GetFunctionEndLine(enclosingFunc)
                    : callerLine;

                // Ensure end character >= start character when on the same line
                var callerEndChar = callerEndLine == callerLine
                    ? callerCol + callerName.Length : 0;

                var callerItem = new CallHierarchyItem
                {
                    Name = callerName,
                    Kind = LspSymbolKind.Function,
                    Uri = DocumentUri.From(fileUri),
                    Range = new LspRange(callerLine, callerCol, callerEndLine, callerEndChar),
                    SelectionRange = new LspRange(
                        callerLine, callerCol,
                        callerLine, callerCol + callerName.Length)
                };

                group = (callerItem, new List<LspRange>());
                callerGroups[callerKey] = group;
            }

            group.Ranges.Add(callRange);
        }

        var results = callerGroups.Values.Select(g => new CallHierarchyIncomingCall
        {
            From = g.Item,
            FromRanges = new Container<LspRange>(g.Ranges)
        }).ToList();

        return new Container<CallHierarchyIncomingCall>(results);
    }

    /// <summary>
    /// Walks all open documents' ASTs to find call expressions that reference the target function.
    /// Returns one CallHierarchyIncomingCall per calling function.
    /// </summary>
    private List<CallHierarchyIncomingCall> FindIncomingCallsFromAst(string targetName, CancellationToken cancellationToken)
    {
        var callerGroups = new Dictionary<string, (CallHierarchyItem Item, List<LspRange> Ranges)>();

        foreach (var doc in _documentManager.GetAllDocuments())
        {
            if (cancellationToken.IsCancellationRequested)
                break;

            if (doc.CompilationUnit?.Declarations == null)
                continue;

            // Walk all functions in this document
            foreach (var funcDecl in EnumerateFunctions(doc.CompilationUnit.Declarations))
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                var callSites = FindCallSitesInFunction(funcDecl, targetName);
                if (callSites.Count == 0)
                    continue;

                var callerLine = Math.Max(0, funcDecl.Line - 1);
                var callerCol = Math.Max(0, funcDecl.Column - 1);
                var callerEndLine = GetFunctionEndLine(funcDecl);
                // Ensure end character >= start character when on the same line
                var callerEndChar = callerEndLine == callerLine
                    ? callerCol + funcDecl.Name.Length : 0;

                var callerItem = new CallHierarchyItem
                {
                    Name = funcDecl.Name,
                    Kind = LspSymbolKind.Function,
                    Uri = DocumentUri.From(doc.Uri),
                    Range = new LspRange(callerLine, callerCol, callerEndLine, callerEndChar),
                    SelectionRange = new LspRange(
                        callerLine, callerCol,
                        callerLine, callerCol + funcDecl.Name.Length)
                };

                var ranges = callSites.Select(site => new LspRange(
                    Math.Max(0, site.Line - 1),
                    Math.Max(0, site.Column - 1),
                    Math.Max(0, site.Line - 1),
                    Math.Max(0, site.Column - 1) + targetName.Length)).ToList();

                callerGroups[$"{doc.Uri}:{funcDecl.Name}:{funcDecl.Line}"] =
                    (callerItem, ranges);
            }
        }

        return callerGroups.Values.Select(g => new CallHierarchyIncomingCall
        {
            From = g.Item,
            FromRanges = new Container<LspRange>(g.Ranges)
        }).ToList();
    }

    /// <summary>
    /// Finds the enclosing FunctionDeclaration for a given 1-based line/column position.
    /// </summary>
    private static FunctionDeclaration? FindEnclosingFunction(List<Declaration> declarations, int line1, int column1)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func)
            {
                if (IsPositionInsideFunction(func, line1))
                {
                    return func;
                }
            }

            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                var nested = FindEnclosingFunction(members, line1, column1);
                if (nested != null) return nested;
            }
        }

        return null;
    }

    /// <summary>
    /// Checks whether a 1-based line position falls within a function's body.
    /// </summary>
    private static bool IsPositionInsideFunction(FunctionDeclaration func, int line1)
    {
        var startLine = func.Line;
        var endLine = startLine;

        if (func.Body != null && func.Body.Statements.Count > 0)
        {
            endLine = func.Body.Statements[^1].Line + 1; // +1 for closing brace
        }
        else if (func.ExpressionBody != null)
        {
            endLine = func.ExpressionBody.Line;
        }

        return line1 >= startLine && line1 <= endLine;
    }

    /// <summary>
    /// Estimates the end line of a function from its body. Returns a 0-based line number.
    /// </summary>
    private static int GetFunctionEndLine(FunctionDeclaration func)
    {
        var startLine = Math.Max(0, func.Line - 1);

        if (func.Body != null && func.Body.Statements.Count > 0)
        {
            var lastStmt = func.Body.Statements[^1];
            return Math.Max(0, lastStmt.Line - 1) + 1;
        }

        if (func.ExpressionBody != null)
        {
            return Math.Max(0, func.ExpressionBody.Line - 1);
        }

        return startLine;
    }

    /// <summary>
    /// Finds all call sites within a function body that call the target function.
    /// Returns 1-based line/column positions.
    /// </summary>
    private static List<(int Line, int Column)> FindCallSitesInFunction(FunctionDeclaration func, string targetName)
    {
        var results = new List<(int Line, int Column)>();

        if (func.Body != null)
        {
            CollectCallSitesFromStatements(func.Body.Statements, targetName, results);
        }

        if (func.ExpressionBody != null)
        {
            CollectCallSitesFromExpression(func.ExpressionBody, targetName, results);
        }

        return results;
    }

    /// <summary>
    /// Recursively collects call sites from a list of statements.
    /// </summary>
    private static void CollectCallSitesFromStatements(List<Statement> statements, string targetName, List<(int Line, int Column)> results)
    {
        foreach (var stmt in statements)
        {
            switch (stmt)
            {
                case ExpressionStatement exprStmt:
                    CollectCallSitesFromExpression(exprStmt.Expression, targetName, results);
                    break;

                case VariableDeclarationStatement varDecl:
                    if (varDecl.Initializer != null)
                        CollectCallSitesFromExpression(varDecl.Initializer, targetName, results);
                    break;

                case ReturnStatement ret:
                    if (ret.Value != null)
                        CollectCallSitesFromExpression(ret.Value, targetName, results);
                    break;

                case BlockStatement block:
                    CollectCallSitesFromStatements(block.Statements, targetName, results);
                    break;

                case IfStatement ifStmt:
                    CollectCallSitesFromExpression(ifStmt.Condition, targetName, results);
                    CollectCallSitesFromStatement(ifStmt.ThenStatement, targetName, results);
                    if (ifStmt.ElseStatement != null)
                        CollectCallSitesFromStatement(ifStmt.ElseStatement, targetName, results);
                    break;

                case WhileStatement whileStmt:
                    CollectCallSitesFromExpression(whileStmt.Condition, targetName, results);
                    CollectCallSitesFromStatement(whileStmt.Body, targetName, results);
                    break;

                case ForStatement forStmt:
                    CollectCallSitesFromStatement(forStmt.Body, targetName, results);
                    break;

                case ForeachStatement foreachStmt:
                    CollectCallSitesFromExpression(foreachStmt.Collection, targetName, results);
                    CollectCallSitesFromStatement(foreachStmt.Body, targetName, results);
                    break;
            }
        }
    }

    /// <summary>
    /// Helper to collect call sites from a single statement (dispatches to block or single-statement).
    /// </summary>
    private static void CollectCallSitesFromStatement(Statement stmt, string targetName, List<(int Line, int Column)> results)
    {
        if (stmt is BlockStatement block)
        {
            CollectCallSitesFromStatements(block.Statements, targetName, results);
        }
        else
        {
            CollectCallSitesFromStatements(new List<Statement> { stmt }, targetName, results);
        }
    }

    /// <summary>
    /// Recursively collects call sites from an expression tree.
    /// </summary>
    private static void CollectCallSitesFromExpression(Expression expr, string targetName, List<(int Line, int Column)> results)
    {
        switch (expr)
        {
            case CallExpression call:
                var calleeName = call.Callee switch
                {
                    IdentifierExpression id => id.Name,
                    MemberAccessExpression member => member.MemberName,
                    _ => null
                };

                if (string.Equals(calleeName, targetName, StringComparison.Ordinal))
                {
                    // Use the callee's position for the call site
                    results.Add((call.Callee.Line, call.Callee.Column));
                }

                // Also recurse into arguments (they might contain nested calls)
                foreach (var arg in call.Arguments)
                {
                    CollectCallSitesFromExpression(arg.Value, targetName, results);
                }

                // Recurse into callee itself for chained calls
                CollectCallSitesFromExpression(call.Callee, targetName, results);
                break;

            case MemberAccessExpression memberAccess:
                CollectCallSitesFromExpression(memberAccess.Object, targetName, results);
                break;

            case BinaryExpression binary:
                CollectCallSitesFromExpression(binary.Left, targetName, results);
                CollectCallSitesFromExpression(binary.Right, targetName, results);
                break;

            case UnaryExpression unary:
                CollectCallSitesFromExpression(unary.Operand, targetName, results);
                break;

            case IndexAccessExpression indexAccess:
                CollectCallSitesFromExpression(indexAccess.Object, targetName, results);
                CollectCallSitesFromExpression(indexAccess.Index, targetName, results);
                break;

            case AssignmentExpression assignment:
                CollectCallSitesFromExpression(assignment.Target, targetName, results);
                CollectCallSitesFromExpression(assignment.Value, targetName, results);
                break;

            case LambdaExpression lambda:
                if (lambda.BlockBody != null)
                    CollectCallSitesFromStatement(lambda.BlockBody, targetName, results);
                if (lambda.ExpressionBody != null)
                    CollectCallSitesFromExpression(lambda.ExpressionBody, targetName, results);
                break;
        }
    }

    /// <summary>
    /// Enumerates all function declarations across all declaration levels, including type members.
    /// </summary>
    private static IEnumerable<FunctionDeclaration> EnumerateFunctions(List<Declaration> declarations)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func)
            {
                yield return func;
            }

            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                foreach (var nested in EnumerateFunctions(members))
                {
                    yield return nested;
                }
            }
        }
    }
}

/// <summary>
/// Handles callHierarchy/outgoingCalls requests.
/// Finds all functions called from within the given function (callees).
/// </summary>
public class CallHierarchyOutgoingHandler : CallHierarchyOutgoingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyOutgoingHandler> _logger;

    public CallHierarchyOutgoingHandler(DocumentManager documentManager, ILogger<CallHierarchyOutgoingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyOutgoingCall>?> Handle(
        CallHierarchyOutgoingCallsParams request,
        CancellationToken cancellationToken)
    {
        var item = request.Item;
        var uri = item.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit?.Declarations == null)
        {
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>());
        }

        try
        {
            _logger.LogDebug("Call hierarchy outgoing calls for: {Name}", item.Name);

            // Find the function declaration in the AST
            var funcDecl = FindFunctionDeclaration(
                doc.CompilationUnit.Declarations,
                item.Name,
                item.SelectionRange.Start.Line + 1); // Convert 0-based LSP to 1-based AST

            if (funcDecl == null)
            {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                    new Container<CallHierarchyOutgoingCall>());
            }

            // Walk the function body to find all outgoing call expressions
            var callExpressions = new List<(string Name, int Line, int Column)>();
            CollectOutgoingCalls(funcDecl, callExpressions);

            if (callExpressions.Count == 0)
            {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                    new Container<CallHierarchyOutgoingCall>());
            }

            // Group by callee name and resolve each to a CallHierarchyItem
            var outgoingCalls = BuildOutgoingCalls(doc, callExpressions);

            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>(outgoingCalls));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy outgoing calls");
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>());
        }
    }

    /// <summary>
    /// Finds a FunctionDeclaration by name at a specific 1-based AST line.
    /// Falls back to name-only match if no line match is found.
    /// </summary>
    private static FunctionDeclaration? FindFunctionDeclaration(
        List<Declaration> declarations,
        string name,
        int line1)
    {
        // First try exact line match
        var exact = FindFunctionByNameAndLine(declarations, name, line1);
        if (exact != null) return exact;

        // Fall back to first name match
        return FindFunctionByName(declarations, name);
    }

    private static FunctionDeclaration? FindFunctionByNameAndLine(List<Declaration> declarations, string name, int line1)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func
                && string.Equals(func.Name, name, StringComparison.Ordinal)
                && func.Line == line1)
            {
                return func;
            }

            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                var nested = FindFunctionByNameAndLine(members, name, line1);
                if (nested != null) return nested;
            }
        }

        return null;
    }

    private static FunctionDeclaration? FindFunctionByName(List<Declaration> declarations, string name)
    {
        foreach (var decl in declarations)
        {
            if (decl is FunctionDeclaration func && string.Equals(func.Name, name, StringComparison.Ordinal))
            {
                return func;
            }

            var members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                InterfaceDeclaration i => i.Members,
                _ => null
            };

            if (members != null)
            {
                var nested = FindFunctionByName(members, name);
                if (nested != null) return nested;
            }
        }

        return null;
    }

    /// <summary>
    /// Walks a function's body to collect all outgoing call expression targets.
    /// </summary>
    private static void CollectOutgoingCalls(FunctionDeclaration func, List<(string Name, int Line, int Column)> results)
    {
        if (func.Body != null)
        {
            CollectCallsFromStatements(func.Body.Statements, results);
        }

        if (func.ExpressionBody != null)
        {
            CollectCallsFromExpression(func.ExpressionBody, results);
        }
    }

    private static void CollectCallsFromStatements(List<Statement> statements, List<(string Name, int Line, int Column)> results)
    {
        foreach (var stmt in statements)
        {
            switch (stmt)
            {
                case ExpressionStatement exprStmt:
                    CollectCallsFromExpression(exprStmt.Expression, results);
                    break;

                case VariableDeclarationStatement varDecl:
                    if (varDecl.Initializer != null)
                        CollectCallsFromExpression(varDecl.Initializer, results);
                    break;

                case ReturnStatement ret:
                    if (ret.Value != null)
                        CollectCallsFromExpression(ret.Value, results);
                    break;

                case BlockStatement block:
                    CollectCallsFromStatements(block.Statements, results);
                    break;

                case IfStatement ifStmt:
                    CollectCallsFromExpression(ifStmt.Condition, results);
                    CollectCallsFromStatement(ifStmt.ThenStatement, results);
                    if (ifStmt.ElseStatement != null)
                        CollectCallsFromStatement(ifStmt.ElseStatement, results);
                    break;

                case WhileStatement whileStmt:
                    CollectCallsFromExpression(whileStmt.Condition, results);
                    CollectCallsFromStatement(whileStmt.Body, results);
                    break;

                case ForStatement forStmt:
                    CollectCallsFromStatement(forStmt.Body, results);
                    break;

                case ForeachStatement foreachStmt:
                    CollectCallsFromExpression(foreachStmt.Collection, results);
                    CollectCallsFromStatement(foreachStmt.Body, results);
                    break;
            }
        }
    }

    private static void CollectCallsFromStatement(Statement stmt, List<(string Name, int Line, int Column)> results)
    {
        if (stmt is BlockStatement block)
        {
            CollectCallsFromStatements(block.Statements, results);
        }
        else
        {
            CollectCallsFromStatements(new List<Statement> { stmt }, results);
        }
    }

    private static void CollectCallsFromExpression(Expression expr, List<(string Name, int Line, int Column)> results)
    {
        switch (expr)
        {
            case CallExpression call:
                var calleeName = call.Callee switch
                {
                    IdentifierExpression id => id.Name,
                    MemberAccessExpression member => member.MemberName,
                    _ => null
                };

                if (calleeName != null)
                {
                    results.Add((calleeName, call.Callee.Line, call.Callee.Column));
                }

                // Recurse into arguments
                foreach (var arg in call.Arguments)
                {
                    CollectCallsFromExpression(arg.Value, results);
                }

                // Recurse into callee for chained calls
                CollectCallsFromExpression(call.Callee, results);
                break;

            case MemberAccessExpression memberAccess:
                CollectCallsFromExpression(memberAccess.Object, results);
                break;

            case BinaryExpression binary:
                CollectCallsFromExpression(binary.Left, results);
                CollectCallsFromExpression(binary.Right, results);
                break;

            case UnaryExpression unary:
                CollectCallsFromExpression(unary.Operand, results);
                break;

            case IndexAccessExpression indexAccess:
                CollectCallsFromExpression(indexAccess.Object, results);
                CollectCallsFromExpression(indexAccess.Index, results);
                break;

            case AssignmentExpression assignment:
                CollectCallsFromExpression(assignment.Target, results);
                CollectCallsFromExpression(assignment.Value, results);
                break;

            case LambdaExpression lambda:
                if (lambda.BlockBody != null)
                    CollectCallsFromStatement(lambda.BlockBody, results);
                if (lambda.ExpressionBody != null)
                    CollectCallsFromExpression(lambda.ExpressionBody, results);
                break;
        }
    }

    /// <summary>
    /// Builds CallHierarchyOutgoingCall entries by grouping call sites by callee name
    /// and resolving each callee to a CallHierarchyItem using symbol info.
    /// </summary>
    private List<CallHierarchyOutgoingCall> BuildOutgoingCalls(
        DocumentState doc,
        List<(string Name, int Line, int Column)> callExpressions)
    {
        // Group by callee name
        var groups = callExpressions
            .GroupBy(c => c.Name, StringComparer.Ordinal)
            .ToList();

        var results = new List<CallHierarchyOutgoingCall>();

        foreach (var group in groups)
        {
            var calleeName = group.Key;
            var calleeItem = ResolveCalleeItem(doc, calleeName);
            if (calleeItem == null)
                continue;

            var fromRanges = group.Select(site =>
            {
                var line0 = Math.Max(0, site.Line - 1);
                var col0 = Math.Max(0, site.Column - 1);
                return new LspRange(line0, col0, line0, col0 + calleeName.Length);
            }).ToList();

            results.Add(new CallHierarchyOutgoingCall
            {
                To = calleeItem,
                FromRanges = new Container<LspRange>(fromRanges)
            });
        }

        return results;
    }

    /// <summary>
    /// Resolves a callee function name to a CallHierarchyItem by looking up symbol info
    /// and locations across all open documents.
    /// </summary>
    private CallHierarchyItem? ResolveCalleeItem(DocumentState originDoc, string calleeName)
    {
        // Try symbol locations in the origin document first
        if (originDoc.SymbolLocations != null && originDoc.SymbolLocations.TryGetValue(calleeName, out var locations))
        {
            var funcLoc = locations.FirstOrDefault(
                loc => loc.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method);

            if (funcLoc != null)
            {
                return CreateCallHierarchyItemFromLocation(funcLoc);
            }
        }

        // Search all documents for the callee declaration
        var allLocations = _documentManager.FindSymbolLocations(calleeName);
        var bestLoc = allLocations.FirstOrDefault(
            loc => loc.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method);

        if (bestLoc != null)
        {
            return CreateCallHierarchyItemFromLocation(bestLoc);
        }

        // Last resort: create a synthetic item from symbol info if available
        if (originDoc.SymbolsInfo != null && originDoc.SymbolsInfo.TryGetValue(calleeName, out var symbolInfo))
        {
            if (symbolInfo.Kind is ServerSymbolKind.Function or ServerSymbolKind.Method)
            {
                return new CallHierarchyItem
                {
                    Name = calleeName,
                    Kind = LspSymbolKind.Function,
                    Uri = DocumentUri.From(originDoc.Uri),
                    Range = new LspRange(0, 0, 0, 0),
                    SelectionRange = new LspRange(0, 0, 0, 0)
                };
            }
        }

        return null;
    }

    /// <summary>
    /// Creates a CallHierarchyItem from a SymbolLocation.
    /// </summary>
    private static CallHierarchyItem CreateCallHierarchyItemFromLocation(SymbolLocation loc)
    {
        var selectionRange = new LspRange(
            loc.Line, loc.Column,
            loc.Line, loc.Column + Math.Max(1, loc.Length));

        return new CallHierarchyItem
        {
            Name = loc.Name,
            Kind = LspSymbolKind.Function,
            Uri = DocumentUri.From(loc.Uri),
            Range = selectionRange,
            SelectionRange = selectionRange
        };
    }
}
