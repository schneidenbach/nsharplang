using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CompilerTypeInfo = NSharpLang.Compiler.TypeInfo;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles signature help (parameter info when typing method calls).
/// </summary>
public class SignatureHelpHandler : SignatureHelpHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SignatureHelpHandler> _logger;

    public SignatureHelpHandler(
        DocumentManager documentManager,
        ILogger<SignatureHelpHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
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

            var argumentText = callInfo.ArgumentText;
            var argumentCount = SignatureHelpArgumentFacts.ArgumentCount(argumentText);

            // Constructor call (new TypeName(...)) — look up constructors for the type
            if (callInfo.IsConstructor)
            {
                var ctorSignatures = BuildNSharpConstructorSignatures(doc, callInfo.MethodName);
                if (ctorSignatures.Count > 0)
                {
                    _logger.LogDebug("Found N# constructor for {Type} with {Count} signature(s)",
                        callInfo.MethodName, ctorSignatures.Count);

                    return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                        ctorSignatures,
                        argumentText,
                        argumentCount));
                }

                return Task.FromResult<SignatureHelp?>(null);
            }

            // Bare function call (no dot) — try N# function lookup first
            if (callInfo.ReceiverName == null)
            {
                var nsharpSignatures = BuildNSharpFunctionSignatures(doc, callInfo.MethodName);
                if (nsharpSignatures.Count > 0)
                {
                    _logger.LogDebug("Found N# function: {Name} with {Count} signature(s)",
                        callInfo.MethodName, nsharpSignatures.Count);

                    return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                        nsharpSignatures,
                        argumentText,
                        argumentCount));
                }

                return Task.FromResult<SignatureHelp?>(null);
            }

            // Dot-qualified call — resolve the receiver as a value first, then as a type.
            var typeName = SignatureHelpArgumentFacts.DeclarationReceiverName(callInfo.ReceiverName);
            var methodName = callInfo.MethodName;

            _logger.LogDebug("Method call: {Type}.{Method}", typeName, methodName);

            var signatures = ResolveMemberSignatures(
                doc,
                typeName,
                methodName,
                request.Position.Line,
                request.Position.Character);
            if (signatures.Count == 0)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                signatures,
                argumentText,
                argumentCount));
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
    /// Build signatures for a user-defined N# function.
    /// </summary>
    private List<SignatureInformation> BuildNSharpFunctionSignatures(DocumentState doc, string functionName)
    {
        var signatures = new List<SignatureInformation>();

        if (signatures.Count == 0 && doc.SymbolsInfo != null)
        {
            if (doc.SymbolsInfo.TryGetValue(functionName, out var symbolInfo) &&
                symbolInfo.Kind == Models.SymbolKind.Function)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(symbolInfo));
            }
        }

        return signatures;
    }

    /// <summary>
    /// Build signatures for constructors of a user-defined N# type.
    /// </summary>
    private List<SignatureInformation> BuildNSharpConstructorSignatures(DocumentState doc, string typeName)
    {
        var signatures = new List<SignatureInformation>();

        if (doc.SymbolsInfo == null)
        {
            return signatures;
        }

        if (!doc.SymbolsInfo.TryGetValue(typeName, out var typeSymbol))
        {
            return signatures;
        }

        if (typeSymbol.Kind is not (Models.SymbolKind.Class or Models.SymbolKind.Struct
            or Models.SymbolKind.Record))
        {
            return signatures;
        }

        foreach (var member in typeSymbol.Members)
        {
            if (member.Kind == Models.SymbolKind.Constructor)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(member));
            }
        }

        return signatures;
    }

    /// <summary>
    /// Build signatures for a method on a user-defined N# type.
    /// </summary>
    private List<SignatureInformation> BuildNSharpMemberSignatures(DocumentState doc, string typeName, string methodName)
    {
        var signatures = new List<SignatureInformation>();

        if (doc.SymbolsInfo == null)
        {
            return signatures;
        }

        if (!doc.SymbolsInfo.TryGetValue(typeName, out var typeSymbol))
        {
            return signatures;
        }

        // Only look at type symbols that have members
        if (typeSymbol.Kind is not (Models.SymbolKind.Class or Models.SymbolKind.Struct
            or Models.SymbolKind.Record or Models.SymbolKind.Interface))
        {
            return signatures;
        }

        foreach (var member in typeSymbol.Members)
        {
            if (member.Name == methodName &&
                member.Kind is Models.SymbolKind.Method or Models.SymbolKind.Function or Models.SymbolKind.Constructor)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(member));
            }
        }

        return signatures;
    }

    private List<SignatureInformation> ResolveMemberSignatures(
        DocumentState doc,
        string receiverName,
        string methodName,
        int lspLine,
        int lspCharacter)
    {
        if (TryLookupReceiverTypeInfo(doc, receiverName, lspLine, lspCharacter, out var receiverTypeInfo))
        {
            var nsharpTypeName = GetNSharpTypeName(doc, receiverTypeInfo);
            if (nsharpTypeName != null)
            {
                var nsharpInstanceSignatures = BuildNSharpMemberSignatures(doc, nsharpTypeName, methodName);
                if (nsharpInstanceSignatures.Count > 0)
                {
                    _logger.LogDebug("Resolved receiver '{Receiver}' as N# type '{Type}'",
                        receiverName, nsharpTypeName);
                    return nsharpInstanceSignatures;
                }
            }

        }

        // Direct N# type access, e.g. Person.Create(
        var nsharpMemberSignatures = BuildNSharpMemberSignatures(doc, receiverName, methodName);
        if (nsharpMemberSignatures.Count > 0)
        {
            return nsharpMemberSignatures;
        }

            _logger.LogDebug("Could not resolve receiver: {Receiver}", receiverName);
            return new List<SignatureInformation>();
    }

    private bool TryLookupReceiverTypeInfo(
        DocumentState doc,
        string receiverName,
        int lspLine,
        int lspCharacter,
        out CompilerTypeInfo receiverTypeInfo)
    {
        receiverTypeInfo = null!;

        if (doc.SemanticModel == null || !IdentifierText.IsValid(receiverName))
        {
            return false;
        }

        // SemanticModel stores source positions as 1-based coordinates.
        var typeInfo = doc.SemanticModel.LookupIdentifierAtPosition(receiverName, lspLine + 1, lspCharacter + 1);

        if (typeInfo == null)
        {
            return false;
        }

        receiverTypeInfo = typeInfo;
        return true;
    }

    private static string? GetNSharpTypeName(DocumentState doc, CompilerTypeInfo typeInfo)
    {
        var typeName = typeInfo switch
        {
            ClassTypeInfo classType => classType.Name,
            StructTypeInfo structType => structType.Name,
            RecordTypeInfo recordType => recordType.Name,
            InterfaceTypeInfo interfaceType => interfaceType.Name,
            _ => typeInfo.ToString()
        };

        if (doc.SymbolsInfo?.TryGetValue(typeName, out var symbolInfo) == true &&
            symbolInfo.Kind is Models.SymbolKind.Class or Models.SymbolKind.Struct
                or Models.SymbolKind.Record or Models.SymbolKind.Interface)
        {
            return typeName;
        }

        return null;
    }

    private SignatureHelp CreateSignatureHelp(
        List<SignatureInformation> signatures,
        string argumentText,
        int argumentCount)
    {
        var activeSignature = SelectActiveSignature(signatures, argumentCount);
        var parameterLabels = signatures[activeSignature].Parameters?
            .Select(parameter => parameter.Label.ToString())
            .ToArray() ?? Array.Empty<string>();
        return new SignatureHelp
        {
            Signatures = new Container<SignatureInformation>(signatures),
            ActiveSignature = activeSignature,
            ActiveParameter = SignatureHelpArgumentFacts.ActiveParameterIndex(argumentText, parameterLabels)
        };
    }

    private static int SelectActiveSignature(List<SignatureInformation> signatures, int argumentCount)
    {
        if (signatures.Count == 0)
        {
            return 0;
        }

        var exactArity = signatures.FindIndex(signature => GetParameterCount(signature) == argumentCount);
        if (exactArity >= 0)
        {
            return exactArity;
        }

        var canStillAcceptArguments = signatures.FindIndex(signature => GetParameterCount(signature) > argumentCount);
        return canStillAcceptArguments >= 0 ? canStillAcceptArguments : 0;
    }

    private static int GetParameterCount(SignatureInformation signature)
    {
        return signature.Parameters?.Count() ?? 0;
    }

    /// <summary>
    /// Build a SignatureInformation from a SymbolInfo (for N# type members).
    /// </summary>
    private SignatureInformation BuildSignatureFromSymbolInfo(Models.SymbolInfo symbolInfo)
    {
        var paramInfos = new List<ParameterInformation>();

        foreach (var param in symbolInfo.Parameters)
        {
            var paramLabel = $"{param.Name}: {param.TypeName}";
            paramInfos.Add(new ParameterInformation
            {
                Label = paramLabel
            });
        }

        var returnType = symbolInfo.TypeName ?? "void";
        var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
        var label = $"{symbolInfo.Name}({paramList}): {returnType}";

        return new SignatureInformation
        {
            Label = label,
            Documentation = CreateDocumentationMarkup(symbolInfo.Documentation),
            Parameters = new Container<ParameterInformation>(paramInfos)
        };
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
