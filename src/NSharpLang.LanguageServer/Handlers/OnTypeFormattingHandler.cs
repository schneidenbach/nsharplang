using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/onTypeFormatting requests to auto-indent after
/// typing '}' or pressing Enter.
/// </summary>
public class OnTypeFormattingHandler : DocumentOnTypeFormattingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<OnTypeFormattingHandler> _logger;

    public OnTypeFormattingHandler(DocumentManager documentManager, ILogger<OnTypeFormattingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<TextEditContainer?> Handle(
        DocumentOnTypeFormattingParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<TextEditContainer?>(null);
        }

        var lines = doc.Text.Split('\n');
        var trigger = request.Character;
        var line = request.Position.Line;
        var character = request.Position.Character;
        var tabSize = request.Options.TabSize;
        var insertSpaces = request.Options.InsertSpaces;

        var edits = trigger switch
        {
            "}" => HandleCloseBrace(lines, line, tabSize, insertSpaces),
            "\n" => HandleNewline(lines, line, tabSize, insertSpaces),
            _ => null
        };

        if (edits == null || edits.Count == 0)
        {
            return Task.FromResult<TextEditContainer?>(null);
        }

        _logger.LogDebug("Returning {Count} on-type formatting edits for '{Trigger}' at {Line}:{Char} in {Uri}",
            edits.Count, trigger, line, character, uri);

        return Task.FromResult<TextEditContainer?>(new TextEditContainer(edits));
    }

    protected override DocumentOnTypeFormattingRegistrationOptions CreateRegistrationOptions(
        DocumentOnTypeFormattingCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentOnTypeFormattingRegistrationOptions
        {
            FirstTriggerCharacter = "}",
            MoreTriggerCharacter = new Container<string>("\n")
        };
    }

    /// <summary>
    /// When '}' is typed, find the matching '{' and align the closing brace
    /// to match its indentation level.
    /// </summary>
    private static List<TextEdit>? HandleCloseBrace(string[] lines, int currentLine, int tabSize, bool insertSpaces)
    {
        if (currentLine < 0 || currentLine >= lines.Length)
            return null;

        // Scan backwards through the text to find the matching '{'
        var braceDepth = 1; // We already have the '}' on the current line
        var matchLine = -1;

        for (int i = currentLine; i >= 0; i--)
        {
            var lineText = lines[i].TrimEnd('\r');
            // Walk the line from right to left (or left to right, tracking)
            var startIdx = (i == currentLine) ? lineText.LastIndexOf('}') - 1 : lineText.Length - 1;

            for (int j = startIdx; j >= 0; j--)
            {
                if (lineText[j] == '}')
                {
                    braceDepth++;
                }
                else if (lineText[j] == '{')
                {
                    braceDepth--;
                    if (braceDepth == 0)
                    {
                        matchLine = i;
                        goto found;
                    }
                }
            }
        }

        found:
        if (matchLine < 0) return null;

        var matchIndent = GetLineIndentation(lines[matchLine], tabSize);
        var currentLineText = lines[currentLine].TrimEnd('\r');
        var currentIndent = GetLineIndentation(currentLineText, tabSize);

        // If indentation already matches, no edit needed
        if (currentIndent == matchIndent) return null;

        var indentStr = BuildIndentString(matchIndent, tabSize, insertSpaces);
        var trimmedContent = currentLineText.TrimStart();

        return new List<TextEdit>
        {
            new TextEdit
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    currentLine, 0, currentLine, currentLineText.Length),
                NewText = indentStr + trimmedContent
            }
        };
    }

    /// <summary>
    /// When Enter is pressed, look at the previous line. If it ends with '{',
    /// add one indent level. Otherwise maintain the current indentation.
    /// </summary>
    private static List<TextEdit>? HandleNewline(string[] lines, int currentLine, int tabSize, bool insertSpaces)
    {
        if (currentLine < 1 || currentLine >= lines.Length)
            return null;

        var prevLineText = lines[currentLine - 1].TrimEnd('\r');
        var prevIndent = GetLineIndentation(prevLineText, tabSize);

        // Strip trailing whitespace and single-line comments to check for '{'
        var trimmedPrev = StripTrailingComment(prevLineText).TrimEnd();

        int targetIndent;
        if (trimmedPrev.EndsWith("{"))
        {
            targetIndent = prevIndent + tabSize;
        }
        else
        {
            targetIndent = prevIndent;
        }

        var currentLineText = lines[currentLine].TrimEnd('\r');
        var currentIndent = GetLineIndentation(currentLineText, tabSize);

        if (currentIndent == targetIndent) return null;

        var indentStr = BuildIndentString(targetIndent, tabSize, insertSpaces);
        var trimmedContent = currentLineText.TrimStart();

        return new List<TextEdit>
        {
            new TextEdit
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    currentLine, 0, currentLine, currentLineText.Length),
                NewText = indentStr + trimmedContent
            }
        };
    }

    /// <summary>
    /// Returns the number of leading whitespace visual columns in a line.
    /// Tabs count as tabSize visual columns each.
    /// </summary>
    private static int GetLineIndentation(string line, int tabSize = 4)
    {
        int count = 0;
        foreach (var ch in line)
        {
            if (ch == ' ') count++;
            else if (ch == '\t') count += tabSize;
            else break;
        }
        return count;
    }

    /// <summary>
    /// Builds an indentation string of the given width using either spaces or tabs.
    /// </summary>
    private static string BuildIndentString(int width, int tabSize, bool insertSpaces)
    {
        if (insertSpaces)
        {
            return new string(' ', width);
        }

        var tabs = width / tabSize;
        var remaining = width % tabSize;
        return new string('\t', tabs) + new string(' ', remaining);
    }

    /// <summary>
    /// Strips a trailing single-line comment (// ...) from a line, returning
    /// only the code portion. Does not handle strings containing //.
    /// </summary>
    private static string StripTrailingComment(string line)
    {
        var idx = line.IndexOf("//", StringComparison.Ordinal);
        return idx >= 0 ? line[..idx] : line;
    }
}
