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
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/documentSymbol requests to provide the Outline panel in VS Code.
/// Maps N# declarations (types, functions, fields, etc.) to LSP DocumentSymbol hierarchy.
/// </summary>
public class DocumentSymbolHandler : DocumentSymbolHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentSymbolHandler> _logger;

    public DocumentSymbolHandler(DocumentManager documentManager, ILogger<DocumentSymbolHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<SymbolInformationOrDocumentSymbolContainer?> Handle(
        DocumentSymbolParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit == null)
        {
            return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(null);
        }

        _logger.LogDebug("Document symbol request for {Uri}", uri);

        // Split source lines once and reuse for all EstimateEndLine calls
        var sourceLines = doc.Text?.Split('\n');

        var symbols = new List<DocumentSymbol>();

        foreach (var decl in doc.CompilationUnit.Declarations)
        {
            var symbol = DeclarationToDocumentSymbol(decl, sourceLines);
            if (symbol != null)
            {
                symbols.Add(symbol);
            }
        }

        var result = new SymbolInformationOrDocumentSymbolContainer(
            symbols.Select(s => new SymbolInformationOrDocumentSymbol(s)));

        return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(result);
    }

    protected override DocumentSymbolRegistrationOptions CreateRegistrationOptions(
        DocumentSymbolCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentSymbolRegistrationOptions();
    }

    private DocumentSymbol? DeclarationToDocumentSymbol(Declaration decl, string[]? sourceLines)
    {
        return decl switch
        {
            FunctionDeclaration f => MakeSymbol(
                f.Name, LspSymbolKind.Function, f.Line,
                EstimateEndLine(f, sourceLines), sourceLines, FormatReturnType(f.ReturnType)),

            ClassDeclaration c => MakeSymbol(
                c.Name, LspSymbolKind.Class, c.Line,
                EstimateEndLine(c, sourceLines), sourceLines, null,
                ConvertMembers(c.Members, sourceLines)),

            StructDeclaration s => MakeSymbol(
                s.Name, LspSymbolKind.Struct, s.Line,
                EstimateEndLine(s, sourceLines), sourceLines, null,
                ConvertMembers(s.Members, sourceLines)),

            RecordDeclaration r => MakeSymbol(
                r.Name, LspSymbolKind.Class, r.Line,
                EstimateEndLine(r, sourceLines), sourceLines, "record",
                ConvertMembers(r.Members, sourceLines)),

            InterfaceDeclaration i => MakeSymbol(
                i.Name, LspSymbolKind.Interface, i.Line,
                EstimateEndLine(i, sourceLines), sourceLines, null,
                ConvertMembers(i.Members, sourceLines)),

            EnumDeclaration e => MakeSymbol(
                e.Name, LspSymbolKind.Enum, e.Line,
                EstimateEndLine(e, sourceLines), sourceLines, null,
                ConvertEnumMembers(e, sourceLines)),

            UnionDeclaration u => MakeSymbol(
                u.Name, LspSymbolKind.Enum, u.Line,
                EstimateEndLine(u, sourceLines), sourceLines, "union"),

            FieldDeclaration fd => MakeSymbol(
                fd.Name, LspSymbolKind.Field, fd.Line, fd.Line, sourceLines,
                FormatTypeRef(fd.Type)),

            PropertyDeclaration pd => MakeSymbol(
                pd.Name, LspSymbolKind.Property, pd.Line, pd.Line, sourceLines,
                FormatTypeRef(pd.Type)),

            TestDeclaration td => MakeSymbol(
                td.Description, LspSymbolKind.Method, td.Line,
                EstimateEndLine(td, sourceLines), sourceLines, "test"),

            _ => null
        };
    }

    private static DocumentSymbol MakeSymbol(
        string name, LspSymbolKind kind, int startLine, int endLine,
        string[]? sourceLines, string? detail, IEnumerable<DocumentSymbol>? children = null)
    {
        // LSP uses 0-based lines; N# AST uses 1-based lines
        var line0 = Math.Max(0, startLine - 1);
        var endLine0 = Math.Max(line0, endLine - 1);

        // Compute the end column so Range fully contains SelectionRange.
        // For the end line, use the actual line length if available; otherwise use a safe max.
        int endCol = 0;
        if (sourceLines != null && endLine0 < sourceLines.Length)
        {
            endCol = sourceLines[endLine0].TrimEnd('\r').Length;
        }
        else
        {
            endCol = int.MaxValue;
        }

        var childArray = children?.ToArray();

        return new DocumentSymbol
        {
            Name = name,
            Kind = kind,
            Range = new LspRange(line0, 0, endLine0, endCol),
            SelectionRange = new LspRange(line0, 0, line0, name.Length),
            Detail = detail,
            Children = childArray is { Length: > 0 }
                ? new Container<DocumentSymbol>(childArray)
                : null
        };
    }

    private IEnumerable<DocumentSymbol> ConvertMembers(List<Declaration> members, string[]? sourceLines)
    {
        return members
            .Select(m => DeclarationToDocumentSymbol(m, sourceLines))
            .Where(s => s != null)!;
    }

    private static IEnumerable<DocumentSymbol> ConvertEnumMembers(EnumDeclaration e, string[]? sourceLines)
    {
        return e.Members.Select(m => MakeSymbol(
            m.Name, LspSymbolKind.EnumMember, m.Line, m.Line, sourceLines, null));
    }

    private static int EstimateEndLine(Declaration decl, string[]? sourceLines)
    {
        if (sourceLines != null && decl.Line > 0)
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

        // Fallback: return start line
        return decl.Line;
    }

    private static string? FormatReturnType(TypeReference? typeRef)
    {
        return typeRef == null ? null : FormatTypeRef(typeRef);
    }

    private static string? FormatTypeRef(TypeReference? typeRef)
    {
        if (typeRef == null) return null;

        return typeRef switch
        {
            SimpleTypeReference s => s.Name,
            GenericTypeReference g =>
                $"{g.Name}<{string.Join(", ", g.TypeArguments.Select(FormatTypeRef))}>",
            ArrayTypeReference a => $"{FormatTypeRef(a.ElementType)}[]",
            NullableTypeReference n => $"{FormatTypeRef(n.InnerType)}?",
            FunctionTypeReference f =>
                $"({string.Join(", ", f.ParameterTypes.Select(FormatTypeRef))}) -> {FormatTypeRef(f.ReturnType)}",
            _ => typeRef.ToString()
        };
    }
}
