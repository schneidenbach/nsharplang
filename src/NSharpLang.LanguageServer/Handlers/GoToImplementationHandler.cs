using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspLocation = OmniSharp.Extensions.LanguageServer.Protocol.Models.Location;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles go-to-implementation requests (Ctrl+F12 in VS Code).
/// Finds all types that implement an interface or extend a base/abstract class.
/// </summary>
public class GoToImplementationHandler : ImplementationHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<GoToImplementationHandler> _logger;

    public GoToImplementationHandler(DocumentManager documentManager, ILogger<GoToImplementationHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationOrLocationLinks?> Handle(ImplementationParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }

        try
        {
            var line = request.Position.Line;
            var character = request.Position.Character;

            var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            _logger.LogDebug("Go to implementation for: {Word}", word);

            // Determine whether the target symbol is an interface or abstract/base class.
            // Only these kinds make sense for "go to implementation."
            if (!TryGetTargetSymbolKind(doc, word, out var targetKind))
            {
                _logger.LogDebug("Symbol '{Word}' is not an interface or class — skipping implementation search", word);
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            // Walk all open documents to find implementors
            var locations = FindImplementors(word, targetKind, cancellationToken);

            if (locations.Count == 0)
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            return Task.FromResult<LocationOrLocationLinks?>(
                new LocationOrLocationLinks(locations.Select(loc => new LocationOrLocationLink(loc))));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling go to implementation");
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
    }

    /// <summary>
    /// Checks whether <paramref name="word"/> is an interface or class in the document's symbol table.
    /// Returns false (and does not set <paramref name="kind"/>) if the symbol is not found or is
    /// neither an interface nor a class.
    /// </summary>
    private static bool TryGetTargetSymbolKind(Models.DocumentState doc, string word, out TargetSymbolKind kind)
    {
        kind = default;

        if (doc.Symbols == null || !doc.Symbols.TryGetValue(word, out var typeInfo))
        {
            return false;
        }

        if (typeInfo is InterfaceTypeInfo)
        {
            kind = TargetSymbolKind.Interface;
            return true;
        }

        if (typeInfo is ClassTypeInfo)
        {
            kind = TargetSymbolKind.Class;
            return true;
        }

        return false;
    }

    /// <summary>
    /// Walks every tracked document's AST declarations to find types that implement or extend the target.
    /// </summary>
    private List<LspLocation> FindImplementors(string targetName, TargetSymbolKind targetKind, CancellationToken cancellationToken)
    {
        var results = new List<LspLocation>();

        foreach (var doc in _documentManager.GetAllDocuments())
        {
            if (cancellationToken.IsCancellationRequested)
                break;

            if (doc.CompilationUnit?.Declarations == null)
                continue;

            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                if (TryMatchImplementor(decl, targetName, targetKind, doc, out var location))
                {
                    results.Add(location!);
                }
            }
        }

        return results;
    }

    /// <summary>
    /// Tests whether a single declaration implements or extends the target type.
    /// Uses semantic comparison when available (matching resolved TypeInfo in the doc's Symbols),
    /// falling back to conservative name matching.
    /// </summary>
    private bool TryMatchImplementor(
        Declaration decl,
        string targetName,
        TargetSymbolKind targetKind,
        Models.DocumentState doc,
        out LspLocation? location)
    {
        location = null;

        switch (decl)
        {
            case ClassDeclaration classDecl:
            {
                bool matches = false;

                // Check base class (only relevant when target is a class)
                if (targetKind == TargetSymbolKind.Class && classDecl.BaseClass != null)
                {
                    matches = TypeReferenceMatchesName(classDecl.BaseClass, targetName);
                }

                // Check interfaces (relevant for both interface and class targets,
                // since a class could appear in an implements list if it is the base)
                if (!matches)
                {
                    matches = classDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName));
                }

                if (matches && VerifySemantic(doc, classDecl.Name, targetName))
                {
                    location = CreateLocation(doc.Uri, classDecl.Name, classDecl.Line, classDecl.Column);
                    return true;
                }

                break;
            }

            case StructDeclaration structDecl:
            {
                if (structDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName)))
                {
                    if (VerifySemantic(doc, structDecl.Name, targetName))
                    {
                        location = CreateLocation(doc.Uri, structDecl.Name, structDecl.Line, structDecl.Column);
                        return true;
                    }
                }

                break;
            }

            case RecordDeclaration recordDecl:
            {
                if (recordDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName)))
                {
                    if (VerifySemantic(doc, recordDecl.Name, targetName))
                    {
                        location = CreateLocation(doc.Uri, recordDecl.Name, recordDecl.Line, recordDecl.Column);
                        return true;
                    }
                }

                break;
            }
        }

        return false;
    }

    /// <summary>
    /// Extracts the name from a TypeReference and compares it to the target.
    /// Handles both <see cref="SimpleTypeReference"/> and <see cref="GenericTypeReference"/>.
    /// </summary>
    private static bool TypeReferenceMatchesName(TypeReference typeRef, string targetName)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => string.Equals(simple.Name, targetName, StringComparison.Ordinal),
            GenericTypeReference generic => string.Equals(generic.Name, targetName, StringComparison.Ordinal),
            _ => false
        };
    }

    /// <summary>
    /// Semantic verification: if the implementing document has a Symbols dictionary, verify that
    /// the implementor type actually resolves to a known type, and that the target name resolves
    /// to a matching kind. This prevents false positives from coincidental name collisions across
    /// unrelated namespaces.
    /// Returns true if semantic info is unavailable (conservative: allow the match through).
    /// </summary>
    private static bool VerifySemantic(Models.DocumentState doc, string implementorName, string targetName)
    {
        // If no symbol table is available, fall through — we already matched by name
        if (doc.Symbols == null)
            return true;

        // The implementor itself should be a known type in this document
        if (!doc.Symbols.TryGetValue(implementorName, out var implementorType))
            return true; // Symbol table incomplete; allow conservative match

        // Verify the implementor is a concrete type (class/struct/record), not an interface itself
        // An interface extending another interface is not an "implementation"
        if (implementorType is InterfaceTypeInfo)
            return false;

        // If the document also has the target in its symbol table, verify the target is
        // the right kind (interface or class). If not present, we trust the AST match.
        if (doc.Symbols.TryGetValue(targetName, out var targetType))
        {
            return targetType is InterfaceTypeInfo or ClassTypeInfo;
        }

        return true;
    }

    /// <summary>
    /// Creates a Location for a declaration. Line/column from the AST are 1-based;
    /// LSP expects 0-based positions.
    /// </summary>
    private static LspLocation CreateLocation(string docUri, string name, int line, int column)
    {
        // AST line/column are 1-based; LSP is 0-based
        var lspLine = Math.Max(0, line - 1);
        var lspColumn = Math.Max(0, column - 1);

        return new LspLocation
        {
            Uri = DocumentUri.From(docUri),
            Range = new LspRange(lspLine, lspColumn, lspLine, lspColumn + Math.Max(1, name.Length))
        };
    }

    protected override ImplementationRegistrationOptions CreateRegistrationOptions(
        ImplementationCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new ImplementationRegistrationOptions();
    }

    private enum TargetSymbolKind
    {
        Interface,
        Class
    }
}
