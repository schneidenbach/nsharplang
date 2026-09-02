using System;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles hover information (shows type info when hovering over identifiers).
///
/// Every decision about WHAT a hover says is N#-owned: the project answer comes from
/// <c>CodeIntelligenceQueries.HoverInfo</c> through <c>DocumentManager.FindProjectHover</c> — the
/// same owner <c>nlc query hover</c> asks — and every line of markdown comes from
/// <c>EditorHoverFacts</c>. What is left here is the protocol: OmniSharp's <c>Hover</c>,
/// <c>MarkupContent</c> and <c>Range</c>, which N# cannot name.
/// </summary>
public class HoverHandler : HoverHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<HoverHandler> _logger;

    public HoverHandler(DocumentManager documentManager, TypeResolver typeResolver, ILogger<HoverHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
        _logger = logger;
    }

    public override Task<Hover?> Handle(HoverParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Hover?>(null);
        }

        var line = request.Position.Line;
        var character = request.Position.Character;

        _logger.LogDebug("Hover request at {Line}:{Character}", line, character);

        var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);

        // A keyword and a primitive answer for themselves and cannot be wrong, so they go first.
        var keywordMarkdown = EditorHoverFacts.KeywordOrPrimitiveMarkdown(word);
        if (keywordMarkdown != null)
        {
            return Task.FromResult(CreateHover(keywordMarkdown, doc.Text, line, character, word));
        }

        // The project answer: the same signature, documentation, declaring type and file that
        // `nlc query hover` prints at this position.
        var projectHover = _documentManager.FindProjectHover(uri, line, character);
        if (projectHover != null)
        {
            return Task.FromResult(CreateHover(EditorHoverFacts.ProjectHoverMarkdown(projectHover), doc.Text, line, character, word));
        }

        // Loose buffers have no project, so the open document's own model answers for them.
        Expression? expression = null;
        if (doc.CompilationUnit != null && doc.SemanticModel != null)
        {
            expression = AstNodeFinderCore.FindExpressionAtPosition(doc.CompilationUnit, line, character) as Expression;
            if (expression is IdentifierExpression identifier)
            {
                var identifierMarkdown = ResolveIdentifier(identifier.Name, doc);
                if (identifierMarkdown != null)
                {
                    return Task.FromResult(CreateHover(identifierMarkdown, doc.Text, line, character, word));
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(word)
            && doc.SemanticModel != null
            && (expression == null || expression is IdentifierExpression))
        {
            var wordMarkdown = ResolveIdentifier(word, doc);
            if (wordMarkdown != null)
            {
                return Task.FromResult(CreateHover(wordMarkdown, doc.Text, line, character, word));
            }
        }

        if (!string.IsNullOrWhiteSpace(word) && doc.Symbols != null && doc.Symbols.TryGetValue(word, out var symbolTypeInfo))
        {
            return Task.FromResult(CreateHover(EditorHoverFacts.TypeDeclarationMarkdown(word, symbolTypeInfo), doc.Text, line, character, word));
        }

        return Task.FromResult<Hover?>(null);
    }

    private string? ResolveIdentifier(string name, DocumentState doc)
    {
        var typeInfo = doc.SemanticModel?.LookupIdentifier(name);
        if (typeInfo == null)
        {
            return null;
        }

        var typeName = typeInfo.ToString() ?? string.Empty;
        var systemType = _typeResolver.ResolveType(typeName);
        return EditorHoverFacts.VariableMarkdown(name, typeName, systemType?.Namespace, systemType?.Assembly?.GetName().Name);
    }

    private Hover? CreateHover(string markdown, string text, int line, int character, string word)
    {
        return new Hover
        {
            Contents = new MarkedStringsOrMarkupContent(new MarkupContent
            {
                Kind = MarkupKind.Markdown,
                Value = markdown
            }),
            Range = string.IsNullOrWhiteSpace(word) ? null : GetWordRange(text, line, character, word)
        };
    }

    protected override HoverRegistrationOptions CreateRegistrationOptions(
        HoverCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new HoverRegistrationOptions
        {
            // DocumentSelector will be set automatically
        };
    }

    private LspRange GetWordRange(string text, int line, int character, string word)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return new LspRange(line, character, line, character);

        var startChar = EditorHoverFacts.WordRangeStartColumn(lines[line], character, word);
        return new LspRange(line, startChar, line, startChar + word.Length);
    }
}
