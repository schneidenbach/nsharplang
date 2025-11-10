using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
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
    private readonly ILogger<HoverHandler> _logger;

    public HoverHandler(DocumentManager documentManager, ILogger<HoverHandler> logger)
    {
        _documentManager = documentManager;
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

        // Get the word at the cursor position
        var word = GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);

        if (string.IsNullOrWhiteSpace(word))
        {
            return Task.FromResult<Hover?>(null);
        }

        _logger.LogDebug("Hover request for word '{Word}' at {Line}:{Character}",
            word, request.Position.Line, request.Position.Character);

        // Look up the word in symbols
        if (doc.Symbols != null && doc.Symbols.TryGetValue(word, out var typeInfo))
        {
            var markdown = FormatTypeInfo(word, typeInfo);

            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                }),
                Range = GetWordRange(doc.Text, request.Position.Line, request.Position.Character, word)
            });
        }

        // Check if it's a keyword
        var keywords = new[]
        {
            "func", "class", "struct", "record", "interface", "enum", "union",
            "match", "async", "await", "yield", "lock", "using", "import"
        };

        if (keywords.Contains(word))
        {
            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = $"**{word}** *(keyword)*"
                })
            });
        }

        // Check if it's a primitive type
        var primitiveTypes = new[]
        {
            "int", "long", "float", "double", "bool", "string", "void", "object"
        };

        if (primitiveTypes.Contains(word))
        {
            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = $"**{word}** *(primitive type)*"
                })
            });
        }

        return Task.FromResult<Hover?>(null);
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

    private string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (character >= lineText.Length) return string.Empty;

        // Find word boundaries
        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
        {
            start--;
        }

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
        {
            end++;
        }

        return lineText.Substring(start, end - start);
    }

    private LspRange GetWordRange(string text, int line, int character, string word)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return new LspRange(line, character, line, character);

        var lineText = lines[line];
        var startChar = lineText.IndexOf(word, character - word.Length);
        if (startChar < 0) startChar = character;

        return new LspRange(line, startChar, line, startChar + word.Length);
    }

    private bool IsIdentifierChar(char c)
    {
        return char.IsLetterOrDigit(c) || c == '_';
    }

    private string FormatTypeInfo(string name, TypeInfo typeInfo)
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
}
