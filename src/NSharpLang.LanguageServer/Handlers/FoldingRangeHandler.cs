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

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/foldingRange requests for AST-aware code folding.
/// Provides folding ranges for type declarations, functions, block statements,
/// import groups, and multi-line comments.
/// </summary>
public class FoldingRangeHandler : FoldingRangeHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<FoldingRangeHandler> _logger;

    public FoldingRangeHandler(DocumentManager documentManager, ILogger<FoldingRangeHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<FoldingRange>?> Handle(FoldingRangeRequestParam request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<FoldingRange>?>(null);
        }

        var ranges = new List<FoldingRange>();
        var sourceLines = doc.Text.Split('\n');

        // AST-based folding ranges
        if (doc.CompilationUnit != null)
        {
            // Fold import block (group of consecutive imports)
            AddImportFoldingRange(doc.CompilationUnit, ranges);

            // Fold declarations
            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                CollectFoldingRanges(decl, sourceLines, ranges);
            }
        }

        // Comment-based folding ranges (multi-line comments)
        AddCommentFoldingRanges(doc, ranges);

        _logger.LogDebug("Returning {Count} folding ranges for {Uri}", ranges.Count, uri);
        return Task.FromResult<Container<FoldingRange>?>(new Container<FoldingRange>(ranges));
    }

    protected override FoldingRangeRegistrationOptions CreateRegistrationOptions(
        FoldingRangeCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new FoldingRangeRegistrationOptions();
    }

    private void CollectFoldingRanges(Declaration decl, string[] sourceLines, List<FoldingRange> ranges)
    {
        var startLine = decl.Line - 1; // Convert to 0-based
        var endLine = EstimateEndLine(decl, sourceLines) - 1; // Convert to 0-based

        // Only add folding range if it spans more than one line
        if (endLine > startLine)
        {
            var kind = decl switch
            {
                FunctionDeclaration => (FoldingRangeKind?)null,
                _ => (FoldingRangeKind?)null  // "region" kind is for #region only
            };

            ranges.Add(new FoldingRange
            {
                StartLine = startLine,
                StartCharacter = 0,
                EndLine = endLine,
                EndCharacter = sourceLines.Length > endLine ? sourceLines[endLine].TrimEnd('\r').Length : 0,
                Kind = kind
            });
        }

        // Recurse into members for type declarations
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
                CollectFoldingRanges(member, sourceLines, ranges);
            }
        }

        // Recurse into function bodies for block statements
        if (decl is FunctionDeclaration func && func.Body != null)
        {
            CollectStatementFoldingRanges(func.Body, sourceLines, ranges);
        }
    }

    private void CollectStatementFoldingRanges(Statement stmt, string[] sourceLines, List<FoldingRange> ranges)
    {
        switch (stmt)
        {
            case BlockStatement block:
                foreach (var s in block.Statements)
                {
                    CollectStatementFoldingRanges(s, sourceLines, ranges);
                }
                break;

            case IfStatement ifStmt:
                AddStatementFoldingRange(ifStmt.ThenStatement, sourceLines, ranges);
                if (ifStmt.ElseStatement != null)
                {
                    AddStatementFoldingRange(ifStmt.ElseStatement, sourceLines, ranges);
                }
                break;

            case WhileStatement whileStmt:
                AddStatementFoldingRange(whileStmt.Body, sourceLines, ranges);
                break;

            case ForStatement forStmt:
                AddStatementFoldingRange(forStmt.Body, sourceLines, ranges);
                break;

            case ForeachStatement foreachStmt:
                AddStatementFoldingRange(foreachStmt.Body, sourceLines, ranges);
                break;

            case TryStatement tryStmt:
                AddStatementFoldingRange(tryStmt.TryBlock, sourceLines, ranges);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    AddStatementFoldingRange(catchClause.Block, sourceLines, ranges);
                }
                if (tryStmt.FinallyBlock != null)
                {
                    AddStatementFoldingRange(tryStmt.FinallyBlock, sourceLines, ranges);
                }
                break;

            case SwitchStatement:
                // The switch itself is foldable via its containing declaration
                break;
        }
    }

    private void AddStatementFoldingRange(Statement stmt, string[] sourceLines, List<FoldingRange> ranges)
    {
        if (stmt is BlockStatement block && block.Statements.Count > 0)
        {
            var startLine = block.Line - 1;
            var endLine = EstimateBlockEndLine(block, sourceLines) - 1;

            if (endLine > startLine)
            {
                ranges.Add(new FoldingRange
                {
                    StartLine = startLine,
                    EndLine = endLine,
                    EndCharacter = sourceLines.Length > endLine ? sourceLines[endLine].TrimEnd('\r').Length : 0,
                });
            }

            foreach (var s in block.Statements)
            {
                CollectStatementFoldingRanges(s, sourceLines, ranges);
            }
        }
    }

    private static void AddImportFoldingRange(CompilationUnit unit, List<FoldingRange> ranges)
    {
        if (unit.Imports.Count < 2) return;

        var firstImport = unit.Imports.First();
        var lastImport = unit.Imports.Last();

        if (lastImport.Line > firstImport.Line)
        {
            ranges.Add(new FoldingRange
            {
                StartLine = firstImport.Line - 1,
                EndLine = lastImport.Line - 1,
                Kind = FoldingRangeKind.Imports
            });
        }
    }

    private void AddCommentFoldingRanges(Models.DocumentState doc, List<FoldingRange> ranges)
    {
        if (doc.Tokens == null) return;

        foreach (var token in doc.Tokens)
        {
            if (token.Type == NSharpLang.Compiler.TokenType.MultiLineComment)
            {
                var startLine = token.Line - 1;
                var lineCount = token.Value.Split('\n').Length;
                var endLine = startLine + lineCount - 1;

                if (endLine > startLine)
                {
                    ranges.Add(new FoldingRange
                    {
                        StartLine = startLine,
                        EndLine = endLine,
                        Kind = FoldingRangeKind.Comment
                    });
                }
            }
        }
    }

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
}
