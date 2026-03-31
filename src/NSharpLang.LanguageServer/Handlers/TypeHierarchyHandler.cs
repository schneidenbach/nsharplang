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
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/prepareTypeHierarchy requests.
/// Resolves the type at the cursor position and returns a TypeHierarchyItem for it.
/// </summary>
public class TypeHierarchyPrepareHandler : TypeHierarchyPrepareHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchyPrepareHandler> _logger;

    public TypeHierarchyPrepareHandler(DocumentManager documentManager, ILogger<TypeHierarchyPrepareHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchyPrepareParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }

        try
        {
            var line = request.Position.Line;
            var character = request.Position.Character;

            var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            _logger.LogDebug("Type hierarchy prepare for: {Word}", word);

            // Resolve the type from the document's symbol table
            if (doc.Symbols == null || !doc.Symbols.TryGetValue(word, out var typeInfo))
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            // Only type declarations produce hierarchy items
            var (name, kind, declLine, declColumn) = typeInfo switch
            {
                ClassTypeInfo c => (c.Declaration.Name, LspSymbolKind.Class, c.Declaration.Line, c.Declaration.Column),
                InterfaceTypeInfo i => (i.Declaration.Name, LspSymbolKind.Interface, i.Declaration.Line, i.Declaration.Column),
                StructTypeInfo s => (s.Declaration.Name, LspSymbolKind.Struct, s.Declaration.Line, s.Declaration.Column),
                RecordTypeInfo r => (r.Declaration.Name, LspSymbolKind.Class, r.Declaration.Line, r.Declaration.Column),
                EnumTypeInfo e => (e.Declaration.Name, LspSymbolKind.Enum, e.Declaration.Line, e.Declaration.Column),
                _ => (null, default(LspSymbolKind), 0, 0)
            };

            if (name == null)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            var item = CreateTypeHierarchyItem(name, kind, uri, declLine, declColumn);

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(item));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy prepare");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }

    protected override TypeHierarchyRegistrationOptions CreateRegistrationOptions(
        TypeHierarchyCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new TypeHierarchyRegistrationOptions();
    }

    internal static TypeHierarchyItem CreateTypeHierarchyItem(string name, LspSymbolKind kind, string uri, int line, int column)
    {
        // AST line/column are 1-based; LSP is 0-based
        var lspLine = Math.Max(0, line - 1);
        var lspColumn = Math.Max(0, column - 1);

        var range = new LspRange(lspLine, lspColumn, lspLine, lspColumn + Math.Max(1, name.Length));

        return new TypeHierarchyItem
        {
            Name = name,
            Kind = kind,
            Uri = DocumentUri.From(uri),
            Range = range,
            SelectionRange = range
        };
    }
}

/// <summary>
/// Handles typeHierarchy/supertypes requests.
/// Given a TypeHierarchyItem, finds its base class and implemented interfaces.
/// </summary>
public class TypeHierarchySupertypesHandler : TypeHierarchySupertypesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchySupertypesHandler> _logger;

    public TypeHierarchySupertypesHandler(DocumentManager documentManager, ILogger<TypeHierarchySupertypesHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchySupertypesParams request, CancellationToken cancellationToken)
    {
        var targetName = request.Item.Name;
        var targetUri = request.Item.Uri.ToString();

        _logger.LogDebug("Type hierarchy supertypes for: {Name}", targetName);

        try
        {
            // Find the declaration for the target type
            var doc = _documentManager.GetDocument(targetUri);
            if (doc?.CompilationUnit?.Declarations == null)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            // Collect supertype references from the AST
            var supertypeRefs = new List<TypeReference>();
            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                switch (decl)
                {
                    case ClassDeclaration c when c.Name == targetName:
                        if (c.BaseClass != null)
                            supertypeRefs.Add(c.BaseClass);
                        supertypeRefs.AddRange(c.Interfaces);
                        break;

                    case StructDeclaration s when s.Name == targetName:
                        supertypeRefs.AddRange(s.Interfaces);
                        break;

                    case RecordDeclaration r when r.Name == targetName:
                        supertypeRefs.AddRange(r.Interfaces);
                        break;

                    case InterfaceDeclaration i when i.Name == targetName:
                        supertypeRefs.AddRange(i.BaseInterfaces);
                        break;
                }
            }

            if (supertypeRefs.Count == 0)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            // Resolve each supertype reference to a TypeHierarchyItem
            var results = new List<TypeHierarchyItem>();
            foreach (var typeRef in supertypeRefs)
            {
                if (cancellationToken.IsCancellationRequested)
                    break;

                var refName = GetTypeReferenceName(typeRef);
                if (refName == null)
                    continue;

                var item = TryResolveTypeHierarchyItem(refName);
                if (item != null)
                {
                    results.Add(item);
                }
            }

            if (results.Count == 0)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(results));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy supertypes");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }

    /// <summary>
    /// Attempts to find a type declaration across all loaded documents and build a TypeHierarchyItem for it.
    /// </summary>
    private TypeHierarchyItem? TryResolveTypeHierarchyItem(string typeName)
    {
        foreach (var doc in _documentManager.GetAllDocuments())
        {
            if (doc.Symbols != null && doc.Symbols.TryGetValue(typeName, out var typeInfo))
            {
                var (kind, line, column) = typeInfo switch
                {
                    ClassTypeInfo c => (LspSymbolKind.Class, c.Declaration.Line, c.Declaration.Column),
                    InterfaceTypeInfo i => (LspSymbolKind.Interface, i.Declaration.Line, i.Declaration.Column),
                    StructTypeInfo s => (LspSymbolKind.Struct, s.Declaration.Line, s.Declaration.Column),
                    RecordTypeInfo r => (LspSymbolKind.Class, r.Declaration.Line, r.Declaration.Column),
                    EnumTypeInfo e => (LspSymbolKind.Enum, e.Declaration.Line, e.Declaration.Column),
                    _ => (default(LspSymbolKind), 0, 0)
                };

                if (line > 0)
                {
                    return TypeHierarchyPrepareHandler.CreateTypeHierarchyItem(typeName, kind, doc.Uri, line, column);
                }
            }
        }

        return null;
    }

    /// <summary>
    /// Extracts the name from a TypeReference.
    /// </summary>
    private static string? GetTypeReferenceName(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            _ => null
        };
    }
}

/// <summary>
/// Handles typeHierarchy/subtypes requests.
/// Given a TypeHierarchyItem, finds all types that inherit or implement it.
/// Same logic as GoToImplementationHandler but returns TypeHierarchyItems.
/// </summary>
public class TypeHierarchySubtypesHandler : TypeHierarchySubtypesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchySubtypesHandler> _logger;

    public TypeHierarchySubtypesHandler(DocumentManager documentManager, ILogger<TypeHierarchySubtypesHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchySubtypesParams request, CancellationToken cancellationToken)
    {
        var targetName = request.Item.Name;
        var targetKind = request.Item.Kind;

        _logger.LogDebug("Type hierarchy subtypes for: {Name}", targetName);

        try
        {
            var results = new List<TypeHierarchyItem>();

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

                    if (TryMatchSubtype(decl, targetName, targetKind, doc, out var item))
                    {
                        results.Add(item!);
                    }
                }
            }

            if (results.Count == 0)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(results));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy subtypes");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }

    /// <summary>
    /// Tests whether a declaration is a subtype of the target type (implements or extends it).
    /// </summary>
    private static bool TryMatchSubtype(
        Declaration decl,
        string targetName,
        LspSymbolKind targetKind,
        Models.DocumentState doc,
        out TypeHierarchyItem? item)
    {
        item = null;

        switch (decl)
        {
            case ClassDeclaration classDecl:
            {
                bool matches = false;

                // Check base class
                if (classDecl.BaseClass != null)
                {
                    matches = TypeReferenceMatchesName(classDecl.BaseClass, targetName);
                }

                // Check implemented interfaces
                if (!matches)
                {
                    matches = classDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName));
                }

                if (matches)
                {
                    item = TypeHierarchyPrepareHandler.CreateTypeHierarchyItem(
                        classDecl.Name, LspSymbolKind.Class, doc.Uri, classDecl.Line, classDecl.Column);
                    return true;
                }

                break;
            }

            case StructDeclaration structDecl:
            {
                if (structDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName)))
                {
                    item = TypeHierarchyPrepareHandler.CreateTypeHierarchyItem(
                        structDecl.Name, LspSymbolKind.Struct, doc.Uri, structDecl.Line, structDecl.Column);
                    return true;
                }

                break;
            }

            case RecordDeclaration recordDecl:
            {
                if (recordDecl.Interfaces.Any(iface => TypeReferenceMatchesName(iface, targetName)))
                {
                    item = TypeHierarchyPrepareHandler.CreateTypeHierarchyItem(
                        recordDecl.Name, LspSymbolKind.Class, doc.Uri, recordDecl.Line, recordDecl.Column);
                    return true;
                }

                break;
            }

            case InterfaceDeclaration interfaceDecl:
            {
                // An interface extending the target interface is a subtype
                if (targetKind == LspSymbolKind.Interface &&
                    interfaceDecl.BaseInterfaces.Any(iface => TypeReferenceMatchesName(iface, targetName)))
                {
                    item = TypeHierarchyPrepareHandler.CreateTypeHierarchyItem(
                        interfaceDecl.Name, LspSymbolKind.Interface, doc.Uri, interfaceDecl.Line, interfaceDecl.Column);
                    return true;
                }

                break;
            }
        }

        return false;
    }

    /// <summary>
    /// Extracts the name from a TypeReference and compares it to the target.
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
}
