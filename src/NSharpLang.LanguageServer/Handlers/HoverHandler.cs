using System;
using System.Linq;
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
/// Handles hover information (shows type info when hovering over identifiers)
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

        var keywordOrPrimitiveHover = TryCreateKeywordOrPrimitiveHover(doc.Text, line, character, word);
        if (keywordOrPrimitiveHover != null)
        {
            return Task.FromResult<Hover?>(keywordOrPrimitiveHover);
        }

        var projectHover = _documentManager.FindProjectHover(uri, line, character);
        if (projectHover != null)
        {
            return Task.FromResult<Hover?>(CreateProjectHover(projectHover, doc.Text, line, character, word));
        }

        // Try AST-based resolution first (most precise)
        if (doc.CompilationUnit != null && doc.SemanticModel != null)
        {
            var expression = AstNodeFinder.FindExpressionAtPosition(doc.CompilationUnit, line, character);
            if (expression != null)
            {
                var hover = TryResolveExpression(expression, word, doc);
                if (hover != null)
                {
                    // Ensure Range is set for consistent behavior
                    if (hover.Range == null && !string.IsNullOrWhiteSpace(word))
                    {
                        hover = new Hover
                        {
                            Contents = hover.Contents,
                            Range = GetWordRange(doc.Text, line, character, word)
                        };
                    }
                    return Task.FromResult<Hover?>(hover);
                }
            }
        }

        // Check symbols (type declarations)
        if (!string.IsNullOrWhiteSpace(word) && doc.Symbols != null && doc.Symbols.TryGetValue(word, out var symbolTypeInfo))
        {
            var markdown = FormatTypeInfo(word, symbolTypeInfo);
            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                }),
                Range = GetWordRange(doc.Text, line, character, word)
            });
        }

        return Task.FromResult<Hover?>(null);
    }

    private Hover? TryCreateKeywordOrPrimitiveHover(string text, int line, int character, string word)
    {
        if (string.IsNullOrWhiteSpace(word))
            return null;

        var keywords = new[]
        {
            "func", "class", "struct", "record", "interface", "enum", "union",
            "match", "async", "await", "yield", "lock", "using", "import", "let"
        };

        if (keywords.Contains(word))
        {
            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = $"**{word}** *(keyword)*"
                }),
                Range = GetWordRange(text, line, character, word)
            };
        }

        var primitiveTypes = new[]
        {
            "int", "long", "float", "double", "bool", "string", "void", "object"
        };

        if (primitiveTypes.Contains(word))
        {
            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = $"**{word}** *(primitive type)*"
                }),
                Range = GetWordRange(text, line, character, word)
            };
        }

        return null;
    }

    private Hover CreateProjectHover(HoverResult result, string text, int line, int character, string word)
    {
        var markdown = new System.Text.StringBuilder();
        markdown.AppendLine("```nsharp");
        markdown.AppendLine(result.Signature);
        markdown.AppendLine("```");

        if (!string.IsNullOrWhiteSpace(result.Documentation))
        {
            markdown.AppendLine();
            markdown.AppendLine(result.Documentation);
        }

        if (!string.IsNullOrWhiteSpace(result.DefinedIn))
        {
            markdown.AppendLine();
            markdown.AppendLine($"*Defined in:* `{result.DefinedIn}`");
        }

        return new Hover
        {
            Contents = new MarkedStringsOrMarkupContent(new MarkupContent
            {
                Kind = MarkupKind.Markdown,
                Value = markdown.ToString().TrimEnd()
            }),
            Range = !string.IsNullOrWhiteSpace(word)
                ? GetWordRange(text, line, character, word)
                : null
        };
    }

    private Hover? TryResolveExpression(Expression expression, string word, DocumentState doc)
    {
        if (doc?.SemanticModel == null) return null;

        switch (expression)
        {
            case IdentifierExpression id:
                return ResolveIdentifier(id.Name, doc);
        }

        return null;
    }

    private Hover? ResolveIdentifier(string name, DocumentState doc)
    {
        if (doc?.SemanticModel == null) return null;

        var typeInfo = doc.SemanticModel.LookupIdentifier(name);
        if (typeInfo != null)
        {
            var typeName = typeInfo.ToString();
            var systemType = _typeResolver.ResolveType(typeName);
            var markdown = systemType != null
                ? FormatVariableWithSystemType(name, typeName, systemType)
                : FormatVariable(name, typeName);

            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                })
            };
        }

        return null;
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

        var lineText = lines[line];
        var startSearch = Math.Max(0, Math.Min(lineText.Length, character) - word.Length);
        var startChar = lineText.IndexOf(word, startSearch, StringComparison.Ordinal);
        if (startChar < 0) startChar = character;

        return new LspRange(line, startChar, line, startChar + word.Length);
    }

    private string FormatTypeInfo(string name, Compiler.TypeInfo typeInfo)
    {
        var kind = typeInfo switch
        {
            ClassTypeInfo => "class",
            StructTypeInfo => "struct",
            RecordTypeInfo => "record",
            InterfaceTypeInfo => "interface",
            EnumTypeInfo => "enum",
            UnionTypeInfo => "union",
            _ => "type"
        };

        return $"**{name}** *({kind})*\n\n```nsharp\n{kind} {name}\n```";
    }

    private string FormatVariable(string name, string typeName)
    {
        return $"**(variable)** `{name}`\n\n```nsharp\n{name}: {typeName}\n```";
    }

    private string FormatVariableWithSystemType(string name, string typeName, Type systemType)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(variable)** `{name}: {typeName}`");
        sb.AppendLine();
        sb.AppendLine("```nsharp");
        sb.AppendLine($"{name}: {typeName}");
        sb.AppendLine("```");

        // Add namespace info if available
        if (!string.IsNullOrEmpty(systemType.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Namespace:* `{systemType.Namespace}`");
        }

        // Add assembly info
        sb.AppendLine();
        sb.AppendLine($"*Assembly:* `{systemType.Assembly.GetName().Name}`");

        return sb.ToString();
    }
}
