using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/documentLink requests to detect clickable URLs
/// in comments and string literals.
/// </summary>
public class DocumentLinkHandler : DocumentLinkHandlerBase
{
    private static readonly Regex UrlRegex = new(
        @"https?://[^\s)>""']+",
        RegexOptions.Compiled);

    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentLinkHandler> _logger;

    public DocumentLinkHandler(DocumentManager documentManager, ILogger<DocumentLinkHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<DocumentLinkContainer?> Handle(DocumentLinkParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Tokens == null)
        {
            return Task.FromResult<DocumentLinkContainer?>(null);
        }

        var links = new List<DocumentLink>();

        // Scan tokens for URLs in string literals and comment tokens
        foreach (var token in doc.Tokens)
        {
            if (token.Type != TokenType.Comment
                && token.Type != TokenType.MultiLineComment
                && token.Type != TokenType.StringLiteral)
            {
                continue;
            }

            var matches = UrlRegex.Matches(token.Value);
            foreach (Match match in matches)
            {
                if (!Uri.TryCreate(match.Value, UriKind.Absolute, out var parsedUri))
                    continue;

                var range = ComputeRange(token, match);
                links.Add(new DocumentLink
                {
                    Range = range,
                    Target = parsedUri.ToString()
                });
            }
        }

        // Also scan comments (CommentTrivia) which may not appear in the token stream
        if (doc.Comments != null)
        {
            foreach (var comment in doc.Comments)
            {
                var matches = UrlRegex.Matches(comment.Text);
                foreach (Match match in matches)
                {
                    if (!Uri.TryCreate(match.Value, UriKind.Absolute, out var parsedUri))
                        continue;

                    var range = ComputeCommentRange(comment, match);
                    links.Add(new DocumentLink
                    {
                        Range = range,
                        Target = parsedUri.ToString()
                    });
                }
            }
        }

        _logger.LogDebug("Returning {Count} document links for {Uri}", links.Count, uri);
        return Task.FromResult<DocumentLinkContainer?>(new DocumentLinkContainer(links));
    }

    public override Task<DocumentLink> Handle(DocumentLink request, CancellationToken cancellationToken)
    {
        // Links are fully resolved in the initial request; return as-is
        return Task.FromResult(request);
    }

    protected override DocumentLinkRegistrationOptions CreateRegistrationOptions(
        DocumentLinkCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentLinkRegistrationOptions();
    }

    /// <summary>
    /// Computes the LSP range (0-based) for a regex match within a CommentTrivia.
    /// CommentTrivia has 1-based Line and Column. The match offset is relative
    /// to the start of comment.Text.
    /// </summary>
    private static OmniSharp.Extensions.LanguageServer.Protocol.Models.Range ComputeCommentRange(
        Compiler.CommentTrivia comment, Match match)
    {
        // Walk through the comment text up to the match start to find the line/column offset
        var commentLine = comment.Line - 1;  // Convert to 0-based
        var commentColumn = comment.Column - 1;  // Convert to 0-based

        var currentLine = commentLine;
        var currentColumn = commentColumn;

        for (int i = 0; i < match.Index; i++)
        {
            if (comment.Text[i] == '\n')
            {
                currentLine++;
                currentColumn = 0;
            }
            else
            {
                currentColumn++;
            }
        }

        var startLine = currentLine;
        var startColumn = currentColumn;

        // URLs don't span lines, so the end is on the same line
        var endLine = startLine;
        var endColumn = startColumn + match.Length;

        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            startLine, startColumn, endLine, endColumn);
    }

    /// <summary>
    /// Computes the LSP range (0-based) for a regex match within a token.
    /// The token's Line and Column are 1-based. The match offset is relative
    /// to the start of token.Value.
    /// </summary>
    private static OmniSharp.Extensions.LanguageServer.Protocol.Models.Range ComputeRange(
        Token token, Match match)
    {
        // Walk through the token value up to the match start to find the line/column offset
        var tokenLine = token.Line - 1;  // Convert to 0-based
        var tokenColumn = token.Column - 1;  // Convert to 0-based

        var currentLine = tokenLine;
        var currentColumn = tokenColumn;

        for (int i = 0; i < match.Index; i++)
        {
            if (token.Value[i] == '\n')
            {
                currentLine++;
                currentColumn = 0;
            }
            else
            {
                currentColumn++;
            }
        }

        var startLine = currentLine;
        var startColumn = currentColumn;

        // URLs don't span lines, so the end is on the same line
        var endLine = startLine;
        var endColumn = startColumn + match.Length;

        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            startLine, startColumn, endLine, endColumn);
    }
}
