using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles signature help (parameter info when typing method calls).
///
/// Every decision is N#-owned: <c>SignatureHelpArgumentFacts</c> finds the call the caret is inside
/// and <c>CodeIntel.SignatureHelpEngine</c> resolves it against the PROJECT SNAPSHOT — the same
/// program completion asks — so a BCL method, an overload set and a type declared in another file
/// all answer. What is left here is the protocol: OmniSharp's SignatureHelp, SignatureInformation,
/// ParameterInformation and MarkupContent, which N# cannot name.
/// </summary>
public class SignatureHelpHandler : SignatureHelpHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SignatureHelpHandler> _logger;
    private readonly CodeIntel.SignatureHelpEngine _signatureHelpEngine = new();

    public SignatureHelpHandler(
        DocumentManager documentManager,
        ILogger<SignatureHelpHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
        _signatureHelpEngine.UseAnalyzer(documentManager.SharedAnalyzer);
    }

    public override Task<SignatureHelp?> Handle(SignatureHelpParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<SignatureHelp?>(null);
        }

        try
        {
            var callInfo = SignatureHelpArgumentFacts.ActiveCallAtPosition(
                doc.Text,
                request.Position.Line,
                request.Position.Character);
            if (callInfo == null)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            _logger.LogDebug("Signature help for: {Method}", callInfo.MethodName);

            var overloads = ResolveOverloads(uri, doc, callInfo, request.Position.Line, request.Position.Character);
            if (overloads.Count == 0)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            var activeOverload = CodeIntel.SignatureHelpOverloadFacts.SelectActiveOverload(
                overloads,
                SignatureHelpArgumentFacts.ArgumentCount(callInfo.ArgumentText));

            return Task.FromResult<SignatureHelp?>(new SignatureHelp
            {
                Signatures = new Container<SignatureInformation>(BuildSignatures(overloads)),
                ActiveSignature = activeOverload,
                ActiveParameter = CodeIntel.SignatureHelpOverloadFacts.ActiveParameter(
                    overloads,
                    activeOverload,
                    callInfo.ArgumentText)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error providing signature help");
            return Task.FromResult<SignatureHelp?>(null);
        }
    }

    protected override SignatureHelpRegistrationOptions CreateRegistrationOptions(
        SignatureHelpCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SignatureHelpRegistrationOptions
        {
            TriggerCharacters = new Container<string>("(", ",")
        };
    }

    /// <summary>
    /// The project snapshot answers when the buffer is backed by one — the same snapshot, and so
    /// the same answer, that <c>nlc query</c> gives. A loose buffer is served by its own parsed
    /// unit and bound model.
    /// </summary>
    private List<CodeIntel.SignatureHelpOverload> ResolveOverloads(
        string uri,
        Models.DocumentState doc,
        SignatureHelpCallContext callInfo,
        int line,
        int character)
    {
        if (_documentManager.TryGetSynchronizedProjectSnapshot(uri, out _, out var filePath, out var snapshot))
        {
            return _signatureHelpEngine.GetOverloads(snapshot, filePath, callInfo, line + 1, character + 1);
        }

        return _signatureHelpEngine.GetOverloads(doc.CompilationUnit, doc.SemanticModel, doc.Text, callInfo, line + 1, character + 1);
    }

    private static List<SignatureInformation> BuildSignatures(List<CodeIntel.SignatureHelpOverload> overloads)
    {
        var signatures = new List<SignatureInformation>();
        foreach (var overload in overloads)
        {
            var parameters = new List<ParameterInformation>();
            foreach (var parameterLabel in overload.ParameterLabels)
            {
                parameters.Add(new ParameterInformation { Label = parameterLabel });
            }

            signatures.Add(new SignatureInformation
            {
                Label = overload.Label,
                Documentation = CreateDocumentationMarkup(overload.Documentation),
                Parameters = new Container<ParameterInformation>(parameters)
            });
        }

        return signatures;
    }

    private static MarkupContent? CreateDocumentationMarkup(string? documentation)
    {
        return string.IsNullOrWhiteSpace(documentation)
            ? null
            : new MarkupContent
            {
                Kind = MarkupKind.Markdown,
                Value = documentation
            };
    }
}
