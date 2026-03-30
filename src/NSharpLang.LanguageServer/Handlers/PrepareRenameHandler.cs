using System;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/prepareRename requests.
/// Validates that the symbol at cursor can be renamed before showing the rename dialog.
/// Prevents renaming keywords, .NET built-in types, and non-existent symbols.
/// </summary>
public class PrepareRenameHandler : PrepareRenameHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<PrepareRenameHandler> _logger;

    public PrepareRenameHandler(DocumentManager documentManager, ILogger<PrepareRenameHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<RangeOrPlaceholderRange?> Handle(PrepareRenameParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        var word = GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
        if (string.IsNullOrWhiteSpace(word))
        {
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Reject keywords
        if (IsKeyword(word))
        {
            _logger.LogDebug("Cannot rename keyword: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Reject primitive type names
        if (IsPrimitiveType(word))
        {
            _logger.LogDebug("Cannot rename primitive type: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Verify the symbol exists in our analysis
        var isKnownSymbol = false;
        if (doc.SymbolLocations?.ContainsKey(word) == true)
            isKnownSymbol = true;
        else if (doc.SemanticModel?.LookupIdentifier(word) != null)
            isKnownSymbol = true;
        else if (doc.SemanticModel?.Variables.ContainsKey(word) == true)
            isKnownSymbol = true;
        else if (doc.SemanticModel?.Functions.ContainsKey(word) == true)
            isKnownSymbol = true;

        if (!isKnownSymbol)
        {
            _logger.LogDebug("Cannot rename unknown symbol: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Return the range of the word and a placeholder
        var range = GetWordRange(doc.Text, request.Position.Line, request.Position.Character, word);
        return Task.FromResult<RangeOrPlaceholderRange?>(new RangeOrPlaceholderRange(
            new PlaceholderRange { Range = range, Placeholder = word }));
    }

    protected override RenameRegistrationOptions CreateRegistrationOptions(
        RenameCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new RenameRegistrationOptions
        {
            PrepareProvider = true
        };
    }

    private static string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (lineText.Length == 0) return string.Empty;
        if (character < 0 || character >= lineText.Length) return string.Empty;
        if (!IsIdentifierChar(lineText[character])) return string.Empty;

        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
            start--;

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
            end++;

        return lineText.Substring(start, end - start);
    }

    private static LspRange GetWordRange(string text, int line, int character, string word)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return new LspRange(line, character, line, character);

        var lineText = lines[line];
        var startSearch = Math.Max(0, Math.Min(lineText.Length, character) - word.Length);
        var startChar = lineText.IndexOf(word, startSearch, StringComparison.Ordinal);
        if (startChar < 0) startChar = character;

        return new LspRange(line, startChar, line, startChar + word.Length);
    }

    private static bool IsIdentifierChar(char c) => char.IsLetterOrDigit(c) || c == '_';

    private static bool IsKeyword(string word)
    {
        return word switch
        {
            "func" or "class" or "struct" or "record" or "interface" or "enum" or "union" or
            "namespace" or "using" or "import" or "if" or "else" or "for" or "foreach" or
            "while" or "return" or "break" or "continue" or "match" or "switch" or "case" or
            "when" or "yield" or "await" or "async" or "throw" or "try" or "catch" or "finally" or
            "lock" or "new" or "this" or "base" or "static" or "virtual" or "override" or
            "abstract" or "sealed" or "partial" or "readonly" or "const" or "file" or "duck" or
            "public" or "private" or "internal" or "protected" or "required" or "init" or
            "let" or "var" or "type" or "out" or "ref" or "params" or "true" or "false" or
            "null" or "is" or "as" or "typeof" or "nameof" or "and" or "or" or "not" or
            "with" or "immutable" or "print" or "test" or "assert" or "implicit" or "explicit"
                => true,
            _ => false
        };
    }

    private static bool IsPrimitiveType(string word)
    {
        return word switch
        {
            "int" or "long" or "float" or "double" or "bool" or "string" or "void" or "object" or
            "byte" or "short" or "char" or "decimal" or "uint" or "ulong" or "ushort" or "sbyte"
                => true,
            _ => false
        };
    }
}
