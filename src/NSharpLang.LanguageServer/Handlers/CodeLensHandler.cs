using System.Collections.Generic;
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
            CollectCodeLenses(decl, lenses, uri);
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

    private void CollectCodeLenses(Declaration decl, List<CodeLens> lenses, string uri)
    {
        // Test declarations get Run/Debug lenses instead of reference counts
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
            lenses.Add(new CodeLens
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    line, 0, line, 0),
                Command = new Command
                {
                    Title = "$(debug-alt) Debug Test",
                    Name = "nsharp.debugTest",
                    Arguments = new Newtonsoft.Json.Linq.JArray(test.Description, uri)
                }
            });
            return;
        }

        var name = GetDeclarationName(decl);
        if (name == null) return;

        var line2 = decl.Line - 1; // Convert to 0-based

        // Count actual references across all open documents using text-based search
        var refCount = 0;
        foreach (var doc in _documentManager.GetAllDocuments())
        {
            var refs = _documentManager.FindAllReferences(doc.Uri, name);
            refCount += refs.Count;
        }

        lenses.Add(new CodeLens
        {
            Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                line2, 0, line2, 0),
            Command = new Command
            {
                Title = $"{refCount} reference{(refCount == 1 ? "" : "s")}",
                Name = "nsharp.showReferences"
            }
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
                CollectCodeLenses(member, lenses, uri);
            }
        }
    }

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
