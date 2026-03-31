using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/semanticTokens/full requests.
/// Walks the token stream and uses AST + SemanticModel to classify tokens
/// into semantic categories (type, variable, function, keyword, etc.)
/// for rich syntax highlighting beyond what TextMate grammar can provide.
/// </summary>
public class SemanticTokensHandler : SemanticTokensHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SemanticTokensHandler> _logger;

    // Token types in legend order — index matters!
    internal static readonly string[] TokenTypes =
    {
        "namespace",      // 0
        "type",           // 1
        "class",          // 2
        "struct",         // 3
        "enum",           // 4
        "interface",      // 5
        "typeParameter",  // 6
        "parameter",      // 7
        "variable",       // 8
        "property",       // 9
        "function",       // 10
        "method",         // 11
        "keyword",        // 12
        "comment",        // 13
        "string",         // 14
        "number",         // 15
        "operator",       // 16
        "enumMember",     // 17
    };

    // Token modifiers in legend order — index matters!
    internal static readonly string[] TokenModifiers =
    {
        "declaration",    // 0
        "definition",     // 1
        "readonly",       // 2
        "static",         // 3
        "async",          // 4
    };

    // Sets for quick keyword classification
    private static readonly HashSet<TokenType> KeywordTokenTypes = new()
    {
        TokenType.Func, TokenType.Class, TokenType.Struct, TokenType.Interface,
        TokenType.Duck, TokenType.Union, TokenType.Record, TokenType.Enum,
        TokenType.Namespace, TokenType.Using, TokenType.Import, TokenType.Package,
        TokenType.Let, TokenType.Const, TokenType.Readonly,
        TokenType.If, TokenType.Else, TokenType.For, TokenType.Foreach,
        TokenType.While, TokenType.In, TokenType.Return, TokenType.Yield,
        TokenType.Match, TokenType.Switch, TokenType.Case, TokenType.Default,
        TokenType.Break, TokenType.Continue, TokenType.Throw,
        TokenType.Try, TokenType.Catch, TokenType.Finally,
        TokenType.New, TokenType.This, TokenType.Base,
        TokenType.True, TokenType.False, TokenType.Null,
        TokenType.Is, TokenType.As, TokenType.Typeof, TokenType.Nameof, TokenType.Sizeof,
        TokenType.Print, TokenType.Where, TokenType.When,
        TokenType.AndKeyword, TokenType.OrKeyword, TokenType.NotKeyword,
        TokenType.Virtual, TokenType.Override, TokenType.Abstract, TokenType.Sealed, TokenType.Partial,
        TokenType.Static, TokenType.Internal, TokenType.Protected,
        TokenType.Async, TokenType.Await, TokenType.Immutable, TokenType.With,
        TokenType.Type, TokenType.Test, TokenType.Assert,
        TokenType.Operator, TokenType.Required, TokenType.Init,
        TokenType.Ref, TokenType.Out, TokenType.Lock, TokenType.File, TokenType.Params,
        TokenType.Checked, TokenType.Unchecked, TokenType.Implicit, TokenType.Explicit,
    };

    private static readonly HashSet<TokenType> OperatorTokenTypes = new()
    {
        TokenType.Plus, TokenType.Minus, TokenType.Star, TokenType.Slash, TokenType.Percent,
        TokenType.Assign, TokenType.PlusAssign, TokenType.MinusAssign, TokenType.StarAssign, TokenType.SlashAssign,
        TokenType.Equal, TokenType.NotEqual, TokenType.Less, TokenType.LessEqual,
        TokenType.Greater, TokenType.GreaterEqual,
        TokenType.And, TokenType.Or, TokenType.Not,
        TokenType.BitwiseAnd, TokenType.BitwiseOr, TokenType.BitwiseXor, TokenType.BitwiseNot,
        TokenType.LeftShift, TokenType.RightShift,
        TokenType.Increment, TokenType.Decrement,
        TokenType.Question, TokenType.QuestionQuestion, TokenType.QuestionQuestionAssign,
        TokenType.QuestionDot, TokenType.QuestionBracket,
        TokenType.Arrow, TokenType.ColonAssign,
        TokenType.DotDot, TokenType.DotDotDot,
    };

    private static readonly HashSet<string> PrimitiveTypeNames = new()
    {
        "int", "long", "float", "double", "bool", "string", "void", "object",
        "byte", "short", "char", "decimal", "uint", "ulong", "ushort", "sbyte",
        "nint", "nuint",
    };

    public SemanticTokensHandler(DocumentManager documentManager, ILogger<SemanticTokensHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    protected override SemanticTokensRegistrationOptions CreateRegistrationOptions(
        SemanticTokensCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SemanticTokensRegistrationOptions
        {
            Full = new SemanticTokensCapabilityRequestFull { Delta = false },
            Legend = new SemanticTokensLegend
            {
                TokenTypes = new Container<SemanticTokenType>(
                    TokenTypes.Select(t => new SemanticTokenType(t))),
                TokenModifiers = new Container<SemanticTokenModifier>(
                    TokenModifiers.Select(m => new SemanticTokenModifier(m))),
            },
        };
    }

    protected override Task<SemanticTokensDocument> GetSemanticTokensDocument(
        ITextDocumentIdentifierParams @params, CancellationToken cancellationToken)
    {
        return Task.FromResult(new SemanticTokensDocument(CreateRegistrationOptions(
            new SemanticTokensCapability(), new ClientCapabilities())));
    }

    protected override Task Tokenize(SemanticTokensBuilder builder, ITextDocumentIdentifierParams identifier, CancellationToken cancellationToken)
    {
        var uri = identifier.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Tokens == null || doc.Text == null)
        {
            return Task.CompletedTask;
        }

        _logger.LogDebug("Semantic tokens request for {Uri} with {TokenCount} tokens", uri, doc.Tokens.Count);

        // Build lookup sets from AST and SemanticModel for identifier classification
        var typeNames = BuildTypeNameSet(doc);
        var functionNames = BuildFunctionNameSet(doc);
        var parameterNames = BuildParameterNameSet(doc);
        var propertyNames = BuildPropertyNameSet(doc);
        var enumMemberNames = BuildEnumMemberNameSet(doc);

        foreach (var token in doc.Tokens)
        {
            if (cancellationToken.IsCancellationRequested) break;

            var classification = ClassifyToken(token, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
            if (classification == null) continue;

            var (tokenType, modifiers) = classification.Value;

            // Token positions: LSP uses 0-based, compiler tokens use 1-based
            var line = token.Line - 1;
            var col = token.Column - 1;
            var length = token.Value.Length;

            if (line < 0 || col < 0 || length <= 0) continue;

            // LSP semantic tokens must not span multiple lines.
            // Skip multiline tokens (comments, triple-quoted strings) entirely —
            // TextMate grammar handles their highlighting adequately.
            if (token.Value.Contains('\n')) continue;

            builder.Push(line, col, length, tokenType, modifiers);
        }

        return Task.CompletedTask;
    }

    /// <summary>
    /// Classify a single token into a semantic token type and modifier set.
    /// Returns null if the token should not be emitted (whitespace, delimiters, etc.)
    /// </summary>
    internal (int TokenType, int Modifiers)? ClassifyToken(
        Token token,
        DocumentState doc,
        HashSet<string> typeNames,
        HashSet<string> functionNames,
        HashSet<string> parameterNames,
        HashSet<string> propertyNames,
        HashSet<string> enumMemberNames)
    {
        // Keywords
        if (KeywordTokenTypes.Contains(token.Type))
        {
            return (12, 0); // keyword
        }

        // Comments
        if (token.Type is TokenType.Comment or TokenType.MultiLineComment or TokenType.XmlDocComment)
        {
            return (13, 0); // comment
        }

        // String literals
        if (token.Type is TokenType.StringLiteral or TokenType.TripleQuoteStringLiteral or TokenType.InterpolatedRawStringLiteral)
        {
            return (14, 0); // string
        }

        // Number literals
        if (token.Type is TokenType.IntLiteral or TokenType.FloatLiteral)
        {
            return (15, 0); // number
        }

        // Operators
        if (OperatorTokenTypes.Contains(token.Type))
        {
            return (16, 0); // operator
        }

        // Identifiers — the interesting part: classify using semantic information
        if (token.Type == TokenType.Identifier)
        {
            return ClassifyIdentifier(token, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        }

        // Skip delimiters, whitespace, EOF, etc.
        return null;
    }

    private (int TokenType, int Modifiers)? ClassifyIdentifier(
        Token token,
        DocumentState doc,
        HashSet<string> typeNames,
        HashSet<string> functionNames,
        HashSet<string> parameterNames,
        HashSet<string> propertyNames,
        HashSet<string> enumMemberNames)
    {
        var name = token.Value;

        // Primitive type names (int, string, bool, etc.)
        if (PrimitiveTypeNames.Contains(name))
        {
            return (1, 0); // type
        }

        // Enum member names
        if (enumMemberNames.Contains(name))
        {
            return (17, 0); // enumMember
        }

        // Type names (user-defined classes, structs, etc.)
        if (typeNames.Contains(name))
        {
            // Determine specific type kind
            if (doc.SymbolsInfo != null && doc.SymbolsInfo.TryGetValue(name, out var symbolInfo))
            {
                var typeIndex = symbolInfo.Kind switch
                {
                    Models.SymbolKind.Class => 2,      // class
                    Models.SymbolKind.Struct => 3,      // struct
                    Models.SymbolKind.Enum => 4,        // enum
                    Models.SymbolKind.Interface => 5,    // interface
                    Models.SymbolKind.Record => 2,       // class (records are class-like)
                    Models.SymbolKind.Union => 4,        // enum (unions are enum-like)
                    _ => 1                               // generic type
                };
                return (typeIndex, 0);
            }
            return (1, 0); // type
        }

        // Function names
        if (functionNames.Contains(name))
        {
            return (10, 0); // function
        }

        // Parameter names
        if (parameterNames.Contains(name))
        {
            return (7, 0); // parameter
        }

        // Property names
        if (propertyNames.Contains(name))
        {
            return (9, 0); // property
        }

        // Check semantic model for variables
        if (doc.SemanticModel != null)
        {
            if (doc.SemanticModel.Variables.ContainsKey(name))
            {
                return (8, 0); // variable
            }

            if (doc.SemanticModel.Functions.ContainsKey(name))
            {
                return (10, 0); // function
            }
        }

        // Unclassified identifier — don't emit a token (let TextMate handle it)
        return null;
    }

    internal static HashSet<string> BuildTypeNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.Symbols != null)
        {
            foreach (var name in doc.Symbols.Keys)
            {
                names.Add(name);
            }
        }

        if (doc.SymbolsInfo != null)
        {
            foreach (var (name, info) in doc.SymbolsInfo)
            {
                if (info.Kind is Models.SymbolKind.Class or Models.SymbolKind.Struct
                    or Models.SymbolKind.Record or Models.SymbolKind.Interface
                    or Models.SymbolKind.Enum or Models.SymbolKind.Union)
                {
                    names.Add(name);
                }
            }
        }

        return names;
    }

    internal static HashSet<string> BuildFunctionNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (name, info) in doc.SymbolsInfo)
            {
                if (info.Kind is Models.SymbolKind.Function or Models.SymbolKind.Method)
                {
                    names.Add(name);
                }
            }
        }

        if (doc.SemanticModel != null)
        {
            foreach (var name in doc.SemanticModel.Functions.Keys)
            {
                names.Add(name);
            }
        }

        return names;
    }

    internal static HashSet<string> BuildParameterNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.CompilationUnit != null)
        {
            foreach (var decl in doc.CompilationUnit.Declarations)
            {
                if (decl is FunctionDeclaration func)
                {
                    foreach (var param in func.Parameters)
                    {
                        names.Add(param.Name);
                    }
                }
            }
        }

        return names;
    }

    internal static HashSet<string> BuildPropertyNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (_, info) in doc.SymbolsInfo)
            {
                foreach (var member in info.Members)
                {
                    if (member.Kind is Models.SymbolKind.Property)
                    {
                        names.Add(member.Name);
                    }
                }
            }
        }

        return names;
    }

    internal static HashSet<string> BuildEnumMemberNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (_, info) in doc.SymbolsInfo)
            {
                foreach (var member in info.Members)
                {
                    if (member.Kind is Models.SymbolKind.EnumMember)
                    {
                        names.Add(member.Name);
                    }
                }
            }
        }

        return names;
    }
}
