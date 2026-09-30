namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles signature help (parameter info when typing method calls).
//
// Every decision is N#-owned: `SignatureHelpArgumentFacts` finds the call the caret is inside and
// `SignatureHelpEngine` resolves it against the PROJECT SNAPSHOT — the same program completion asks
// — so a BCL method, an overload set and a type declared in another file all answer. What is left
// here is the protocol: OmniSharp's SignatureHelp, SignatureInformation, ParameterInformation and
// MarkupContent, which N# cannot name.
class SignatureHelpHandler: SignatureHelpHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<SignatureHelpHandler>
    readonly signatureHelpEngine: SignatureHelpEngine

    constructor(documentManager: DocumentManager, logger: ILogger<SignatureHelpHandler>) {
        this.documentManager = documentManager
        this.logger = logger
        signatureHelpEngine = new SignatureHelpEngine()
        signatureHelpEngine.UseAnalyzer(documentManager.SharedAnalyzer)
    }

    override func Handle(request: SignatureHelpParams, cancellationToken: CancellationToken): Task<SignatureHelp?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<SignatureHelp?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            callInfo := SignatureHelpArgumentFacts.ActiveCallAtPosition(doc.Text, line, character)
            if callInfo == null {
                return Task.FromResult<SignatureHelp?>(null)
            }

            logger.LogDebug("Signature help for: {Method}", callInfo.MethodName)

            overloads := resolveOverloads(uri, doc, callInfo, line, character)
            if overloads.Count == 0 {
                return Task.FromResult<SignatureHelp?>(null)
            }

            activeOverload := SignatureHelpOverloadFacts.SelectActiveOverload(
                overloads,
                SignatureHelpArgumentFacts.ArgumentCount(callInfo.ArgumentText)
            )

            help := new SignatureHelp {
                Signatures: new Container<SignatureInformation>(buildSignatures(overloads)),
                ActiveSignature: activeOverload,
                ActiveParameter: SignatureHelpOverloadFacts.ActiveParameter(overloads, activeOverload, callInfo.ArgumentText)
            }

            return Task.FromResult<SignatureHelp?>(help)
        } catch failure: Exception {
            logger.LogError(failure, "Error providing signature help")
            return Task.FromResult<SignatureHelp?>(null)
        }
    }

    protected override func CreateRegistrationOptions(
        capability: SignatureHelpCapability,
        clientCapabilities: ClientCapabilities
    ): SignatureHelpRegistrationOptions {
        return new SignatureHelpRegistrationOptions {
            TriggerCharacters: new Container<string>("(", ",")
        }
    }

    // The project snapshot answers when the buffer is backed by one — the same snapshot, and so the
    // same answer, that `nlc query` gives. A loose buffer is served by its own parsed unit and bound
    // model.
    func resolveOverloads(
        uri: string,
        doc: DocumentState,
        callInfo: SignatureHelpCallContext,
        line: int,
        character: int
    ): List<SignatureHelpOverload> {
        binding := documentManager.SynchronizedProjectSnapshot(uri)
        if binding != null {
            return signatureHelpEngine.GetOverloads(binding.Snapshot, binding.FilePath, callInfo, line + 1, character + 1)
        }

        return signatureHelpEngine.GetOverloads(doc.CompilationUnit, doc.SemanticModel, doc.Text, callInfo, line + 1, character + 1)
    }

    static func buildSignatures(overloads: List<SignatureHelpOverload>): List<SignatureInformation> {
        signatures := new List<SignatureInformation>()
        for overload in overloads {
            parameters := new List<ParameterInformation>()
            for parameterLabel in overload.ParameterLabels {
                parameters.Add(new ParameterInformation { Label: parameterLabel })
            }

            signatures.Add(new SignatureInformation {
                Label: overload.Label,
                Documentation: createDocumentationMarkup(overload.Documentation),
                Parameters: new Container<ParameterInformation>(parameters)
            })
        }

        return signatures
    }

    static func createDocumentationMarkup(documentation: string?): StringOrMarkupContent? {
        if string.IsNullOrWhiteSpace(documentation) {
            return null
        }

        content := new MarkupContent {
            Kind: MarkupKind.Markdown,
            Value: documentation ?? ""
        }

        return new StringOrMarkupContent(content)
    }
}
