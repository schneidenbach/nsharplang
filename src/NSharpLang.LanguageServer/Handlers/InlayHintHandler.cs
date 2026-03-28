using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/inlayHint requests.
/// Shows inferred types as ghost text after := assignments where the type is not explicit.
/// </summary>
public class InlayHintHandler : InlayHintsHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<InlayHintHandler> _logger;

    public InlayHintHandler(DocumentManager documentManager, ILogger<InlayHintHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<InlayHintContainer?> Handle(InlayHintParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit == null || doc.SemanticModel == null)
        {
            return Task.FromResult<InlayHintContainer?>(new InlayHintContainer());
        }

        var range = request.Range;
        var hints = new List<InlayHint>();

        _logger.LogDebug("InlayHint request for {Uri} range {StartLine}:{StartChar}-{EndLine}:{EndChar}",
            uri, range.Start.Line, range.Start.Character, range.End.Line, range.End.Character);

        CollectHints(doc.CompilationUnit, doc.SemanticModel, range, hints);

        return Task.FromResult<InlayHintContainer?>(new InlayHintContainer(hints));
    }

    public override Task<InlayHint> Handle(InlayHint request, CancellationToken cancellationToken)
    {
        // Resolve is not supported — return the hint as-is
        return Task.FromResult(request);
    }

    protected override InlayHintRegistrationOptions CreateRegistrationOptions(
        InlayHintClientCapabilities capability,
        ClientCapabilities clientCapabilities)
    {
        return new InlayHintRegistrationOptions
        {
            ResolveProvider = false
        };
    }

    /// <summary>
    /// Walk the AST collecting inlay hints for inferred-type declarations in the visible range.
    /// </summary>
    internal void CollectHints(CompilationUnit unit, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        if (unit.Declarations == null) return;

        foreach (var decl in unit.Declarations)
        {
            CollectFromDeclaration(decl, semanticModel, range, hints);
        }
    }

    private void CollectFromDeclaration(Declaration decl, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
                if (func.Body != null)
                {
                    CollectFromStatement(func.Body, semanticModel, range, hints);
                }
                break;

            case ClassDeclaration cls:
                if (cls.Members != null)
                {
                    foreach (var member in cls.Members)
                    {
                        CollectFromDeclaration(member, semanticModel, range, hints);
                    }
                }
                break;

            case StructDeclaration str:
                if (str.Members != null)
                {
                    foreach (var member in str.Members)
                    {
                        CollectFromDeclaration(member, semanticModel, range, hints);
                    }
                }
                break;

            case RecordDeclaration rec:
                if (rec.Members != null)
                {
                    foreach (var member in rec.Members)
                    {
                        CollectFromDeclaration(member, semanticModel, range, hints);
                    }
                }
                break;
        }
    }

    private void CollectFromStatement(Statement stmt, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        switch (stmt)
        {
            case BlockStatement block:
                foreach (var s in block.Statements)
                {
                    CollectFromStatement(s, semanticModel, range, hints);
                }
                break;

            case VariableDeclarationStatement varDecl:
                TryAddVariableHint(varDecl, semanticModel, range, hints);
                break;

            case ForeachStatement foreachStmt:
                TryAddForeachHint(foreachStmt, semanticModel, range, hints);
                CollectFromStatement(foreachStmt.Body, semanticModel, range, hints);
                break;

            case IfStatement ifStmt:
                CollectFromStatement(ifStmt.ThenStatement, semanticModel, range, hints);
                if (ifStmt.ElseStatement != null)
                {
                    CollectFromStatement(ifStmt.ElseStatement, semanticModel, range, hints);
                }
                break;

            case WhileStatement whileStmt:
                CollectFromStatement(whileStmt.Body, semanticModel, range, hints);
                break;

            case ForStatement forStmt:
                if (forStmt.Initializer != null)
                {
                    CollectFromStatement(forStmt.Initializer, semanticModel, range, hints);
                }
                CollectFromStatement(forStmt.Body, semanticModel, range, hints);
                break;

            case TryStatement tryStmt:
                CollectFromStatement(tryStmt.TryBlock, semanticModel, range, hints);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    CollectFromStatement(catchClause.Block, semanticModel, range, hints);
                }
                if (tryStmt.FinallyBlock != null)
                {
                    CollectFromStatement(tryStmt.FinallyBlock, semanticModel, range, hints);
                }
                break;

            case UsingStatement usingStmt:
                if (usingStmt.Declaration != null)
                {
                    TryAddVariableHint(usingStmt.Declaration, semanticModel, range, hints);
                }
                if (usingStmt.Body != null)
                {
                    CollectFromStatement(usingStmt.Body, semanticModel, range, hints);
                }
                break;

            case LockStatement lockStmt:
                CollectFromStatement(lockStmt.Body, semanticModel, range, hints);
                break;

            case SwitchStatement switchStmt:
                foreach (var switchCase in switchStmt.Cases)
                {
                    foreach (var s in switchCase.Statements)
                    {
                        CollectFromStatement(s, semanticModel, range, hints);
                    }
                }
                break;

            case AwaitForEachStatement awaitForeachStmt:
                TryAddAwaitForeachHint(awaitForeachStmt, semanticModel, range, hints);
                CollectFromStatement(awaitForeachStmt.Body, semanticModel, range, hints);
                break;

            case LocalFunctionStatement localFunc:
                if (localFunc.Function.Body != null)
                {
                    CollectFromStatement(localFunc.Function.Body, semanticModel, range, hints);
                }
                break;
        }
    }

    private void TryAddVariableHint(VariableDeclarationStatement varDecl, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        // Only show hints for inferred types (no explicit type annotation)
        if (varDecl.Type != null) return;
        if (varDecl.Initializer == null) return;

        // Convert 1-based parser positions to 0-based LSP positions
        var lspLine = varDecl.Line - 1;
        var lspCol = varDecl.Column - 1;

        if (!IsInRange(lspLine, range)) return;

        var typeInfo = semanticModel.LookupIdentifier(varDecl.Name);
        if (typeInfo == null) return;

        var typeName = FormatTypeForHint(typeInfo);
        if (string.IsNullOrEmpty(typeName)) return;

        // Position the hint right after the variable name
        var hintPosition = new Position(lspLine, lspCol + varDecl.Name.Length);

        hints.Add(new InlayHint
        {
            Position = hintPosition,
            Label = new StringOrInlayHintLabelParts($": {typeName}"),
            Kind = InlayHintKind.Type,
            PaddingLeft = false,
            PaddingRight = true
        });
    }

    private void TryAddForeachHint(ForeachStatement foreachStmt, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        var lspLine = foreachStmt.Line - 1;

        if (!IsInRange(lspLine, range)) return;

        var typeInfo = semanticModel.LookupIdentifier(foreachStmt.VariableName);
        if (typeInfo == null) return;

        var typeName = FormatTypeForHint(typeInfo);
        if (string.IsNullOrEmpty(typeName)) return;

        // The foreach variable name starts after "foreach " (8 chars) from the statement column
        // But the exact position depends on the source text, so we use parser position
        // The parser Column points to "foreach", the variable name follows it.
        // We need to find the variable name position. Since the parser stores the statement position,
        // not the variable position, we calculate: column of "foreach" + len("foreach ") = variable start
        // But this isn't reliable with varying whitespace. Instead, use the semantic model.
        // For foreach, the variable is always on the same line, so we search the source text.
        // Since we don't have access to the source text here, we approximate:
        // "foreach <varname> in <collection>" — the variable appears after "foreach "
        var lspCol = foreachStmt.Column - 1;
        var foreachKeywordLen = "foreach ".Length;
        var varStartCol = lspCol + foreachKeywordLen;
        var hintPosition = new Position(lspLine, varStartCol + foreachStmt.VariableName.Length);

        hints.Add(new InlayHint
        {
            Position = hintPosition,
            Label = new StringOrInlayHintLabelParts($": {typeName}"),
            Kind = InlayHintKind.Type,
            PaddingLeft = false,
            PaddingRight = true
        });
    }

    private void TryAddAwaitForeachHint(AwaitForEachStatement awaitForeachStmt, SemanticModel semanticModel, LspRange range, List<InlayHint> hints)
    {
        var lspLine = awaitForeachStmt.Line - 1;

        if (!IsInRange(lspLine, range)) return;

        var typeInfo = semanticModel.LookupIdentifier(awaitForeachStmt.VariableName);
        if (typeInfo == null) return;

        var typeName = FormatTypeForHint(typeInfo);
        if (string.IsNullOrEmpty(typeName)) return;

        // "await foreach <varname> in <collection>" — variable appears after "await foreach "
        var lspCol = awaitForeachStmt.Column - 1;
        var awaitForeachKeywordLen = "await foreach ".Length;
        var varStartCol = lspCol + awaitForeachKeywordLen;
        var hintPosition = new Position(lspLine, varStartCol + awaitForeachStmt.VariableName.Length);

        hints.Add(new InlayHint
        {
            Position = hintPosition,
            Label = new StringOrInlayHintLabelParts($": {typeName}"),
            Kind = InlayHintKind.Type,
            PaddingLeft = false,
            PaddingRight = true
        });
    }

    private static bool IsInRange(int lspLine, LspRange range)
    {
        return lspLine >= range.Start.Line && lspLine <= range.End.Line;
    }

    /// <summary>
    /// Format a TypeInfo into a concise display name suitable for inlay hints.
    /// Uses N# primitive names (int, string, bool) rather than .NET names.
    /// </summary>
    internal static string FormatTypeForHint(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            SimpleTypeInfo simple => simple.Name,
            GenericTypeInfo generic => generic.ToString(),
            ArrayTypeInfo array => array.ToString(),
            NullableTypeInfo nullable => nullable.ToString(),
            TupleTypeInfo tuple => FormatTupleType(tuple),
            ClassTypeInfo cls => cls.Declaration.Name,
            StructTypeInfo str => str.Declaration.Name,
            RecordTypeInfo rec => rec.Declaration.Name,
            InterfaceTypeInfo iface => iface.Declaration.Name,
            EnumTypeInfo en => en.Declaration.Name,
            UnionTypeInfo union => union.Declaration.Name,
            ReflectionTypeInfo reflection => FormatReflectionType(reflection.Type),
            ExternalTypeInfo ext => ext.Name,
            _ => typeInfo.ToString()
        };
    }

    private static string FormatTupleType(TupleTypeInfo tuple)
    {
        var parts = new List<string>();
        foreach (var (name, type) in tuple.Elements)
        {
            var formatted = FormatTypeForHint(type);
            parts.Add(name != null ? $"{name}: {formatted}" : formatted);
        }
        return $"({string.Join(", ", parts)})";
    }

    private static string FormatReflectionType(System.Type type)
    {
        if (type.IsGenericType)
        {
            var genericArgs = type.GetGenericArguments();
            var typeName = type.Name.Substring(0, type.Name.IndexOf('`'));
            var args = string.Join(", ", System.Linq.Enumerable.Select(genericArgs, FormatReflectionType));
            return $"{typeName}<{args}>";
        }

        return type.Name switch
        {
            "Int32" => "int",
            "Int64" => "long",
            "Single" => "float",
            "Double" => "double",
            "Boolean" => "bool",
            "String" => "string",
            "Void" => "void",
            "Object" => "object",
            _ => type.Name
        };
    }
}
