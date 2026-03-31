using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/selectionRange requests for smart selection expansion.
/// For each requested position, builds a parent chain of AST nodes containing
/// that position, from innermost to outermost, allowing the editor to expand
/// or shrink selection through syntactic boundaries.
/// </summary>
public class SelectionRangeHandler : SelectionRangeHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SelectionRangeHandler> _logger;

    public SelectionRangeHandler(DocumentManager documentManager, ILogger<SelectionRangeHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<SelectionRange>?> Handle(
        SelectionRangeParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<SelectionRange>?>(null);
        }

        var sourceLines = doc.Text.Split('\n');
        var results = new List<SelectionRange>();

        foreach (var position in request.Positions)
        {
            var chain = new List<LspRange>();

            // Build the parent chain of AST nodes containing this position
            if (doc.CompilationUnit != null)
            {
                CollectContainingRanges(doc.CompilationUnit, position, sourceLines, chain);
            }

            // Always include the whole-file range as the outermost selection
            var wholeFileRange = new LspRange(
                0, 0,
                Math.Max(0, sourceLines.Length - 1),
                sourceLines.Length > 0 ? sourceLines[^1].TrimEnd('\r').Length : 0);

            // Build nested SelectionRange from innermost to outermost
            // Start with the whole-file range as the root (no parent)
            var selectionRange = new SelectionRange { Range = wholeFileRange };

            // Layer on each range from outermost to innermost
            foreach (var range in chain)
            {
                selectionRange = new SelectionRange { Range = range, Parent = selectionRange };
            }

            results.Add(selectionRange);
        }

        _logger.LogDebug("Returning {Count} selection ranges for {Uri}", results.Count, uri);
        return Task.FromResult<Container<SelectionRange>?>(new Container<SelectionRange>(results));
    }

    protected override SelectionRangeRegistrationOptions CreateRegistrationOptions(
        SelectionRangeCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SelectionRangeRegistrationOptions();
    }

    /// <summary>
    /// Collects containing AST node ranges for the given position, from outermost to innermost.
    /// Walks the AST depth-first, appending ranges as it descends into tighter-fitting nodes.
    /// </summary>
    private void CollectContainingRanges(
        CompilationUnit unit, Position position, string[] sourceLines, List<LspRange> chain)
    {
        // Convert LSP 0-based position to 1-based for AST comparison
        var targetLine = position.Line + 1;
        var targetColumn = position.Character + 1;

        foreach (var decl in unit.Declarations)
        {
            if (TryCollectDeclarationRanges(decl, targetLine, targetColumn, sourceLines, chain))
            {
                return;
            }
        }
    }

    /// <summary>
    /// Tries to collect ranges for a declaration if it contains the target position.
    /// Returns true if the position falls within this declaration.
    /// </summary>
    private bool TryCollectDeclarationRanges(
        Declaration decl, int targetLine, int targetColumn, string[] sourceLines, List<LspRange> chain)
    {
        var startLine = decl.Line;
        var endLine = EstimateEndLine(decl, sourceLines);

        if (!ContainsPosition(startLine, endLine, targetLine))
        {
            return false;
        }

        // This declaration contains the position -- add its range
        chain.Add(MakeLspRange(startLine, endLine, sourceLines));

        // Try to descend into members of type declarations
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
            foreach (var member in members)
            {
                if (TryCollectDeclarationRanges(member, targetLine, targetColumn, sourceLines, chain))
                {
                    return true;
                }
            }
        }

        // Try to descend into enum members
        if (decl is EnumDeclaration enumDecl)
        {
            foreach (var member in enumDecl.Members)
            {
                if (member.Line > 0 && member.Line == targetLine)
                {
                    chain.Add(MakeLspRange(member.Line, member.Line, sourceLines));
                    return true;
                }
            }
        }

        // Try to descend into function body
        if (decl is FunctionDeclaration func && func.Body != null)
        {
            TryCollectStatementRanges(func.Body, targetLine, targetColumn, sourceLines, chain);
        }

        return true;
    }

    /// <summary>
    /// Tries to collect ranges for a statement if it contains the target position.
    /// Returns true if the position falls within this statement.
    /// </summary>
    private bool TryCollectStatementRanges(
        Statement stmt, int targetLine, int targetColumn, string[] sourceLines, List<LspRange> chain)
    {
        switch (stmt)
        {
            case BlockStatement block:
            {
                var blockStart = block.Line;
                var blockEnd = EstimateBlockEndLine(block, sourceLines);

                if (!ContainsPosition(blockStart, blockEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(blockStart, blockEnd, sourceLines));

                // Descend into child statements
                foreach (var child in block.Statements)
                {
                    if (TryCollectStatementRanges(child, targetLine, targetColumn, sourceLines, chain))
                    {
                        return true;
                    }
                }

                return true;
            }

            case IfStatement ifStmt:
            {
                var ifStart = ifStmt.Line;
                var ifEnd = EstimateCompoundStatementEndLine(ifStmt, sourceLines);

                if (!ContainsPosition(ifStart, ifEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(ifStart, ifEnd, sourceLines));

                // Try the then branch
                if (TryCollectStatementRanges(ifStmt.ThenStatement, targetLine, targetColumn, sourceLines, chain))
                {
                    return true;
                }

                // Try the else branch
                if (ifStmt.ElseStatement != null)
                {
                    if (TryCollectStatementRanges(ifStmt.ElseStatement, targetLine, targetColumn, sourceLines, chain))
                    {
                        return true;
                    }
                }

                return true;
            }

            case ForStatement forStmt:
            {
                var forStart = forStmt.Line;
                var forEnd = EstimateStatementEndLine(forStmt.Body, sourceLines, forStmt.Line);

                if (!ContainsPosition(forStart, forEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(forStart, forEnd, sourceLines));
                TryCollectStatementRanges(forStmt.Body, targetLine, targetColumn, sourceLines, chain);
                return true;
            }

            case ForeachStatement foreachStmt:
            {
                var foreachStart = foreachStmt.Line;
                var foreachEnd = EstimateStatementEndLine(foreachStmt.Body, sourceLines, foreachStmt.Line);

                if (!ContainsPosition(foreachStart, foreachEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(foreachStart, foreachEnd, sourceLines));
                TryCollectStatementRanges(foreachStmt.Body, targetLine, targetColumn, sourceLines, chain);
                return true;
            }

            case WhileStatement whileStmt:
            {
                var whileStart = whileStmt.Line;
                var whileEnd = EstimateStatementEndLine(whileStmt.Body, sourceLines, whileStmt.Line);

                if (!ContainsPosition(whileStart, whileEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(whileStart, whileEnd, sourceLines));
                TryCollectStatementRanges(whileStmt.Body, targetLine, targetColumn, sourceLines, chain);
                return true;
            }

            case TryStatement tryStmt:
            {
                var tryStart = tryStmt.Line;
                var tryEnd = EstimateTryStatementEndLine(tryStmt, sourceLines);

                if (!ContainsPosition(tryStart, tryEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(tryStart, tryEnd, sourceLines));

                // Try the try block
                if (TryCollectStatementRanges(tryStmt.TryBlock, targetLine, targetColumn, sourceLines, chain))
                {
                    return true;
                }

                // Try each catch block
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    if (TryCollectStatementRanges(catchClause.Block, targetLine, targetColumn, sourceLines, chain))
                    {
                        return true;
                    }
                }

                // Try the finally block
                if (tryStmt.FinallyBlock != null)
                {
                    if (TryCollectStatementRanges(tryStmt.FinallyBlock, targetLine, targetColumn, sourceLines, chain))
                    {
                        return true;
                    }
                }

                return true;
            }

            case SwitchStatement switchStmt:
            {
                var switchStart = switchStmt.Line;
                var switchEnd = EstimateSwitchEndLine(switchStmt, sourceLines);

                if (!ContainsPosition(switchStart, switchEnd, targetLine))
                {
                    return false;
                }

                chain.Add(MakeLspRange(switchStart, switchEnd, sourceLines));
                return true;
            }

            default:
            {
                // Leaf statements (return, variable declaration, expression, etc.)
                if (stmt.Line == targetLine)
                {
                    chain.Add(MakeLspRange(stmt.Line, stmt.Line, sourceLines));
                    return true;
                }

                return false;
            }
        }
    }

    /// <summary>
    /// Checks whether a target position falls within a 1-based [startLine, endLine] range,
    /// accounting for column positions on boundary lines.
    /// When startColumn/endColumn are provided (> 0), the check also validates
    /// that the position is >= startColumn on the start line and <= endColumn on the end line.
    /// </summary>
    private static bool ContainsPosition(int startLine, int endLine, int targetLine,
        int startColumn = 0, int endColumn = 0, int targetColumn = 0)
    {
        if (targetLine < startLine || targetLine > endLine)
            return false;

        // On the start line, the target column must be at or after the start column
        if (targetLine == startLine && startColumn > 0 && targetColumn > 0 && targetColumn < startColumn)
            return false;

        // On the end line, the target column must be at or before the end column
        if (targetLine == endLine && endColumn > 0 && targetColumn > 0 && targetColumn > endColumn)
            return false;

        return true;
    }

    /// <summary>
    /// Converts 1-based start/end lines to a 0-based LSP Range.
    /// </summary>
    private static LspRange MakeLspRange(int startLine1, int endLine1, string[] sourceLines)
    {
        var startLine0 = Math.Max(0, startLine1 - 1);
        var endLine0 = Math.Max(startLine0, endLine1 - 1);

        int endCol = 0;
        if (endLine0 < sourceLines.Length)
        {
            endCol = sourceLines[endLine0].TrimEnd('\r').Length;
        }

        return new LspRange(startLine0, 0, endLine0, endCol);
    }

    /// <summary>
    /// Estimates the end line of a declaration by scanning for the matching closing brace.
    /// </summary>
    private static int EstimateEndLine(Declaration decl, string[] sourceLines)
    {
        if (decl.Line > 0)
        {
            var startLine = decl.Line - 1; // 0-based index
            int braceDepth = 0;
            bool foundOpen = false;

            for (int i = startLine; i < sourceLines.Length; i++)
            {
                foreach (var ch in sourceLines[i])
                {
                    if (ch == '{')
                    {
                        braceDepth++;
                        foundOpen = true;
                    }
                    else if (ch == '}')
                    {
                        braceDepth--;
                        if (foundOpen && braceDepth == 0)
                        {
                            return i + 1; // 1-based
                        }
                    }
                }
            }
        }

        return decl.Line;
    }

    /// <summary>
    /// Estimates the end line of a block statement by scanning for the matching closing brace.
    /// </summary>
    private static int EstimateBlockEndLine(BlockStatement block, string[] sourceLines)
    {
        if (block.Line > 0)
        {
            var startLine = block.Line - 1;
            int braceDepth = 0;
            bool foundOpen = false;

            for (int i = startLine; i < sourceLines.Length; i++)
            {
                foreach (var ch in sourceLines[i])
                {
                    if (ch == '{')
                    {
                        braceDepth++;
                        foundOpen = true;
                    }
                    else if (ch == '}')
                    {
                        braceDepth--;
                        if (foundOpen && braceDepth == 0)
                        {
                            return i + 1; // 1-based
                        }
                    }
                }
            }
        }

        return block.Line;
    }

    /// <summary>
    /// Estimates the end line for a statement that may be a block (with braces) or a single-line statement.
    /// Falls back to the parent start line if the statement has no useful position.
    /// </summary>
    private static int EstimateStatementEndLine(Statement body, string[] sourceLines, int fallbackLine)
    {
        if (body is BlockStatement block)
        {
            return EstimateBlockEndLine(block, sourceLines);
        }

        // Single-line body: use the statement's own line
        return body.Line > 0 ? body.Line : fallbackLine;
    }

    /// <summary>
    /// Estimates the end line for an if statement, including any else branches.
    /// </summary>
    private static int EstimateCompoundStatementEndLine(IfStatement ifStmt, string[] sourceLines)
    {
        // The end of the if statement is the end of the last branch
        if (ifStmt.ElseStatement != null)
        {
            if (ifStmt.ElseStatement is IfStatement nestedIf)
            {
                return EstimateCompoundStatementEndLine(nestedIf, sourceLines);
            }

            return EstimateStatementEndLine(ifStmt.ElseStatement, sourceLines, ifStmt.Line);
        }

        return EstimateStatementEndLine(ifStmt.ThenStatement, sourceLines, ifStmt.Line);
    }

    /// <summary>
    /// Estimates the end line for a try statement, including catch and finally blocks.
    /// </summary>
    private static int EstimateTryStatementEndLine(TryStatement tryStmt, string[] sourceLines)
    {
        if (tryStmt.FinallyBlock != null)
        {
            return EstimateBlockEndLine(tryStmt.FinallyBlock, sourceLines);
        }

        if (tryStmt.CatchClauses.Count > 0)
        {
            var lastCatch = tryStmt.CatchClauses[^1];
            return EstimateBlockEndLine(lastCatch.Block, sourceLines);
        }

        return EstimateBlockEndLine(tryStmt.TryBlock, sourceLines);
    }

    /// <summary>
    /// Estimates the end line for a switch statement by scanning for the matching closing brace.
    /// </summary>
    private static int EstimateSwitchEndLine(SwitchStatement switchStmt, string[] sourceLines)
    {
        if (switchStmt.Line > 0)
        {
            var startLine = switchStmt.Line - 1;
            int braceDepth = 0;
            bool foundOpen = false;

            for (int i = startLine; i < sourceLines.Length; i++)
            {
                foreach (var ch in sourceLines[i])
                {
                    if (ch == '{')
                    {
                        braceDepth++;
                        foundOpen = true;
                    }
                    else if (ch == '}')
                    {
                        braceDepth--;
                        if (foundOpen && braceDepth == 0)
                        {
                            return i + 1; // 1-based
                        }
                    }
                }
            }
        }

        return switchStmt.Line;
    }
}
