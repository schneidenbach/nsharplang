using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Workspace;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;
using ServerSymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles workspace/symbol requests (Ctrl+T — Go to Symbol in Workspace).
/// Returns all symbols across all loaded files, filtered by the query string.
/// </summary>
public class WorkspaceSymbolHandler : WorkspaceSymbolsHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<WorkspaceSymbolHandler> _logger;

    public WorkspaceSymbolHandler(DocumentManager documentManager, ILogger<WorkspaceSymbolHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<WorkspaceSymbol>?> Handle(WorkspaceSymbolParams request, CancellationToken cancellationToken)
    {
        var query = request.Query ?? string.Empty;
        _logger.LogDebug("Workspace symbol request: '{Query}'", query);

        var symbols = new List<WorkspaceSymbol>();

        foreach (var doc in _documentManager.GetAllDocuments())
        {
            if (cancellationToken.IsCancellationRequested) break;

            if (doc.SymbolsInfo == null) continue;

            foreach (var (name, info) in doc.SymbolsInfo)
            {
                if (!MatchesQuery(name, query)) continue;

                var lspKind = ConvertSymbolKind(info.Kind);
                var (line, col) = FindSymbolPosition(doc, name);

                symbols.Add(new WorkspaceSymbol
                {
                    Name = name,
                    Kind = lspKind,
                    Location = new Location
                    {
                        Uri = DocumentUri.From(doc.Uri),
                        Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                            Math.Max(0, line - 1), Math.Max(0, col - 1),
                            Math.Max(0, line - 1), Math.Max(0, col - 1) + name.Length)
                    },
                    ContainerName = GetContainerName(info)
                });

                // Also add members of type declarations
                if (info.Kind is ServerSymbolKind.Class or ServerSymbolKind.Struct
                    or ServerSymbolKind.Record or ServerSymbolKind.Interface
                    or ServerSymbolKind.Enum or ServerSymbolKind.Union)
                {
                    foreach (var member in info.Members)
                    {
                        if (!MatchesQuery(member.Name, query)) continue;

                        var (memberLine, memberCol) = FindMemberPosition(doc, name, member.Name);

                        symbols.Add(new WorkspaceSymbol
                        {
                            Name = member.Name,
                            Kind = ConvertSymbolKind(member.Kind),
                            Location = new Location
                            {
                                Uri = DocumentUri.From(doc.Uri),
                                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                                    Math.Max(0, memberLine - 1), Math.Max(0, memberCol - 1),
                                    Math.Max(0, memberLine - 1), Math.Max(0, memberCol - 1) + member.Name.Length)
                            },
                            ContainerName = name
                        });
                    }
                }
            }
        }

        _logger.LogDebug("Returning {Count} workspace symbols", symbols.Count);
        return Task.FromResult<Container<WorkspaceSymbol>?>(new Container<WorkspaceSymbol>(symbols));
    }

    protected override WorkspaceSymbolRegistrationOptions CreateRegistrationOptions(
        WorkspaceSymbolCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new WorkspaceSymbolRegistrationOptions();
    }

    /// <summary>
    /// Case-insensitive fuzzy match: all characters of the query must appear
    /// in order in the symbol name (standard VS Code workspace symbol behavior).
    /// Empty query matches everything.
    /// </summary>
    internal static bool MatchesQuery(string name, string query)
    {
        if (string.IsNullOrEmpty(query)) return true;

        var nameIndex = 0;
        var nameLower = name.ToLowerInvariant();
        var queryLower = query.ToLowerInvariant();

        foreach (var ch in queryLower)
        {
            var found = nameLower.IndexOf(ch, nameIndex);
            if (found < 0) return false;
            nameIndex = found + 1;
        }

        return true;
    }

    private static LspSymbolKind ConvertSymbolKind(ServerSymbolKind kind)
    {
        return kind switch
        {
            ServerSymbolKind.Class => LspSymbolKind.Class,
            ServerSymbolKind.Struct => LspSymbolKind.Struct,
            ServerSymbolKind.Record => LspSymbolKind.Class,
            ServerSymbolKind.Interface => LspSymbolKind.Interface,
            ServerSymbolKind.Enum => LspSymbolKind.Enum,
            ServerSymbolKind.Union => LspSymbolKind.Enum,
            ServerSymbolKind.Function => LspSymbolKind.Function,
            ServerSymbolKind.Method => LspSymbolKind.Method,
            ServerSymbolKind.Property => LspSymbolKind.Property,
            ServerSymbolKind.Field => LspSymbolKind.Field,
            ServerSymbolKind.Parameter => LspSymbolKind.Variable,
            ServerSymbolKind.LocalVariable => LspSymbolKind.Variable,
            ServerSymbolKind.EnumMember => LspSymbolKind.EnumMember,
            ServerSymbolKind.Constructor => LspSymbolKind.Constructor,
            _ => LspSymbolKind.Variable
        };
    }

    private static string? GetContainerName(Models.SymbolInfo info)
    {
        // Top-level symbols have no container
        return null;
    }

    private static (int Line, int Column) FindSymbolPosition(Models.DocumentState doc, string name)
    {
        if (doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(name, out var locations))
        {
            var first = locations.FirstOrDefault();
            if (first != null) return (first.Line, first.Column);
        }

        // Fallback: search AST
        if (doc.CompilationUnit != null)
        {
            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                if (GetDeclarationName(decl) == name)
                {
                    return (decl.Line, decl.Column);
                }
            }
        }

        return (1, 1);
    }

    private static (int Line, int Column) FindMemberPosition(Models.DocumentState doc, string typeName, string memberName)
    {
        // Check SymbolLocations first (has all symbols including enum members)
        if (doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(memberName, out var locations))
        {
            var match = locations.FirstOrDefault();
            if (match != null) return (match.Line, match.Column);
        }

        if (doc.CompilationUnit != null)
        {
            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                if (GetDeclarationName(decl) != typeName) continue;

                // Check class/struct/record/interface members
                var members = GetDeclarationMembers(decl);
                if (members != null)
                {
                    foreach (var member in members)
                    {
                        if (GetDeclarationName(member) == memberName)
                        {
                            return (member.Line, member.Column);
                        }
                    }
                }

                // Check enum members
                if (decl is EnumDeclaration enumDecl)
                {
                    foreach (var enumMember in enumDecl.Members)
                    {
                        if (enumMember.Name == memberName)
                        {
                            return (enumMember.Line, enumMember.Column);
                        }
                    }
                }
            }
        }

        return (1, 1);
    }

    private static string? GetDeclarationName(Declaration decl)
    {
        return decl switch
        {
            FunctionDeclaration f => f.Name,
            ClassDeclaration c => c.Name,
            StructDeclaration s => s.Name,
            RecordDeclaration r => r.Name,
            InterfaceDeclaration i => i.Name,
            EnumDeclaration e => e.Name,
            UnionDeclaration u => u.Name,
            FieldDeclaration fd => fd.Name,
            PropertyDeclaration pd => pd.Name,
            _ => null
        };
    }

    private static List<Declaration>? GetDeclarationMembers(Declaration decl)
    {
        return decl switch
        {
            ClassDeclaration c => c.Members,
            StructDeclaration s => s.Members,
            RecordDeclaration r => r.Members,
            InterfaceDeclaration i => i.Members,
            _ => null
        };
    }
}
