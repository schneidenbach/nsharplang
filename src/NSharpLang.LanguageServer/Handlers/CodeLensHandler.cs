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

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/codeLens requests to show reference counts on
/// top-level declarations (functions, classes, structs, records, interfaces, enums).
/// </summary>
public class CodeLensHandler : CodeLensHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CodeLensHandler> _logger;

    public CodeLensHandler(DocumentManager documentManager, ILogger<CodeLensHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<CodeLensContainer?> Handle(CodeLensParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit == null)
        {
            // Return empty array, not null — null can cause VS Code to cache
            // "no CodeLens support" and never re-request for this document.
            return Task.FromResult<CodeLensContainer?>(new CodeLensContainer());
        }

        var lenses = new List<CodeLens>();

        foreach (var decl in doc.CompilationUnit.Declarations)
        {
            CollectCodeLenses(decl, lenses, uri, isTopLevel: true);
        }

        _logger.LogDebug("Returning {Count} code lenses for {Uri}", lenses.Count, uri);
        return Task.FromResult<CodeLensContainer?>(new CodeLensContainer(lenses));
    }

    public override Task<CodeLens> Handle(CodeLens request, CancellationToken cancellationToken)
    {
        // Resolution is already done in the initial request for simplicity
        return Task.FromResult(request);
    }

    protected override CodeLensRegistrationOptions CreateRegistrationOptions(
        CodeLensCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CodeLensRegistrationOptions
        {
            DocumentSelector = new TextDocumentSelector(
                new TextDocumentFilter { Language = "nsharp" }
            ),
            ResolveProvider = false
        };
    }

    private void CollectCodeLenses(Declaration decl, List<CodeLens> lenses, string uri, bool isTopLevel)
    {
        // Test declarations get a Run lens instead of reference counts. Debug is
        // intentionally hidden until the extension has a real debugger-backed path.
        if (decl is TestDeclaration test)
        {
            var line = decl.Line - 1; // Convert to 0-based
            lenses.Add(new CodeLens
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    line, 0, line, 0),
                Command = new Command
                {
                    Title = "$(play) Run Test",
                    Name = "nsharp.runTest",
                    Arguments = new Newtonsoft.Json.Linq.JArray(test.Description, uri)
                }
            });
            return;
        }

        var name = GetDeclarationName(decl);
        if (name == null) return;

        var line2 = decl.Line - 1; // Convert to 0-based
        var isEntryPoint = IsEntryPointCandidate(decl, isTopLevel, name);
        var nameStartCharacter = isEntryPoint ? null : GetDeclarationNameStartCharacter(uri, decl, name);
        var referenceInfo = nameStartCharacter != null
            ? CountReferencesForCodeLens(name, uri, decl, line2, nameStartCharacter.Value)
            : null;
        var commandTitle = isEntryPoint
            ? "Entry point"
            : referenceInfo != null
                ? FormatReferenceCount(referenceInfo.Value.Count)
                : "References unavailable";

        var command = !isEntryPoint && referenceInfo?.IsClickable == true && nameStartCharacter != null
            ? new Command
            {
                Title = commandTitle,
                Name = "nsharp.showReferences",
                Arguments = new Newtonsoft.Json.Linq.JArray(uri, line2, nameStartCharacter.Value)
            }
            : new Command
            {
                Title = commandTitle,
                Name = "nsharp.noop"
            };

        lenses.Add(new CodeLens
        {
            Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                line2, 0, line2, 0),
            Command = command
        });

        // Recurse into type members
        var members = decl switch
        {
            ClassDeclaration c => c.Members,
            StructDeclaration s => s.Members,
            RecordDeclaration r => r.Members,
            InterfaceDeclaration i => i.Members,
            _ => null
        };

        if (members != null)
        {
            foreach (var member in members)
            {
                CollectCodeLenses(member, lenses, uri, isTopLevel: false);
            }
        }
    }

    private (int Count, bool IsClickable)? CountReferencesForCodeLens(string name, string declarationUri, Declaration declaration, int line0, int character0)
    {
        var semanticCount = CountSemanticReferencesExcludingDeclarations(declarationUri, line0, character0);
        if (semanticCount != null)
        {
            return (semanticCount.Value, IsClickable: true);
        }

        var sameDocumentCount = CountSingleDocumentTextReferencesExcludingDeclaration(name, declarationUri, declaration);
        return sameDocumentCount != null ? (sameDocumentCount.Value, IsClickable: false) : null;
    }

    private int? CountSemanticReferencesExcludingDeclarations(string declarationUri, int line0, int character0)
    {
        var references = _documentManager.FindProjectReferences(declarationUri, line0, character0)
            ?? _documentManager.FindStrictDocumentReferences(declarationUri, line0, character0);

        return references?.Count(reference => !reference.IsDefinition);
    }

    private int? CountSingleDocumentTextReferencesExcludingDeclaration(string name, string declarationUri, Declaration declaration)
    {
        if (_documentManager.CountDocumentDeclarations(declarationUri, name) != 1)
        {
            return null;
        }

        var declarationLine = declaration.Line - 1;
        var declarationOccurrenceRemoved = false;
        var count = 0;
        foreach (var reference in _documentManager.FindAllReferences(declarationUri, name))
        {
            if (!declarationOccurrenceRemoved && reference.Line == declarationLine)
            {
                declarationOccurrenceRemoved = true;
                continue;
            }

            count++;
        }

        return count;
    }

    private int? GetDeclarationNameStartCharacter(string uri, Declaration declaration, string name)
    {
        var doc = _documentManager.GetDocument(uri);
        if (doc?.Text == null)
        {
            return null;
        }

        var lines = doc.Text.Split('\n');
        var line0 = declaration.Line - 1;
        if (line0 < 0 || line0 >= lines.Length)
        {
            return null;
        }

        var lineText = lines[line0].TrimEnd('\r');
        var searchStart = System.Math.Max(0, System.Math.Min(declaration.Column - 1, lineText.Length));
        var nameIndex = lineText.IndexOf(name, searchStart, System.StringComparison.Ordinal);
        if (nameIndex < 0)
        {
            nameIndex = lineText.IndexOf(name, System.StringComparison.Ordinal);
        }

        return nameIndex >= 0 ? nameIndex : null;
    }

    private static bool IsEntryPointCandidate(Declaration decl, bool isTopLevel, string name)
    {
        if (decl is not FunctionDeclaration function
            || !string.Equals(name, "main", System.StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return isTopLevel || function.Modifiers.HasFlag(Modifiers.Static);
    }

    private static string FormatReferenceCount(int refCount) =>
        $"{refCount} reference{(refCount == 1 ? "" : "s")}";

    private static string? GetDeclarationName(Declaration decl) => decl switch
    {
        FunctionDeclaration f => f.Name,
        ClassDeclaration c => c.Name,
        StructDeclaration s => s.Name,
        RecordDeclaration r => r.Name,
        InterfaceDeclaration i => i.Name,
        EnumDeclaration e => e.Name,
        _ => null
    };
}
