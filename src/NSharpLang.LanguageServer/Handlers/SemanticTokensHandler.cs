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
        "catchResult",    // 5
    };

    internal const int CatchResultModifierMask = 1 << 5;

    // Neither the keywords, the operators, nor the built-in type spellings are enumerated here.
    // `Lexer.IsReservedKeyword`, `ParserTokenFacts.IsOperator` and
    // `AnalyzerTypeReferenceFacts.IsBuiltInTypeName` are the single owners of those three
    // memberships, and the editor asks them rather than keeping copies that drift.

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
        var catchResultBindings = BuildCatchResultBindingSet(doc);

        foreach (var token in doc.Tokens)
        {
            if (cancellationToken.IsCancellationRequested) break;

            if (IsInterpolatedStringLiteral(token))
            {
                foreach (var embeddedToken in GetInterpolatedStringExpressionTokens(token))
                {
                    var embeddedClassification = ClassifyToken(
                        embeddedToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);
                    if (embeddedClassification == null) continue;

                    var (embeddedTokenType, embeddedModifiers) = embeddedClassification.Value;
                    PushSemanticToken(builder, embeddedToken, embeddedTokenType, embeddedModifiers);
                }

                continue;
            }

            var classification = ClassifyToken(token, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);
            if (classification == null) continue;

            var (tokenType, modifiers) = classification.Value;

            PushSemanticToken(builder, token, tokenType, modifiers);
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
        HashSet<string> enumMemberNames,
        HashSet<SemanticTokenLocation>? catchResultBindings = null)
    {
        // Keywords
        if (Lexer.IsReservedKeyword(token.Type))
        {
            return (12, 0); // keyword
        }

        // Comments
        if (token.Type is TokenType.Comment or TokenType.MultiLineComment or TokenType.XmlDocComment)
        {
            return (13, 0); // comment
        }

        // String literals. Interpolated strings are intentionally left to the
        // TextMate grammar so expression holes keep normal code colors.
        if (IsInterpolatedStringLiteral(token))
        {
            return null;
        }

        if (token.Type is TokenType.StringLiteral or TokenType.TripleQuoteStringLiteral)
        {
            return (14, 0); // string
        }

        // Number literals
        if (token.Type is TokenType.IntLiteral or TokenType.FloatLiteral)
        {
            return (15, 0); // number
        }

        // Operators
        if (ParserTokenFacts.IsOperator(token.Type))
        {
            return (16, 0); // operator
        }

        // Identifiers — the interesting part: classify using semantic information
        if (token.Type == TokenType.Identifier)
        {
            return ClassifyIdentifier(token, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);
        }

        // Skip delimiters, whitespace, EOF, etc.
        return null;
    }

    private static bool IsInterpolatedStringLiteral(Token token)
    {
        return token.Type == TokenType.InterpolatedRawStringLiteral
            || (token.Type == TokenType.StringLiteral
                && token.Value.StartsWith("$\"", StringComparison.Ordinal));
    }

    private static void PushSemanticToken(SemanticTokensBuilder builder, Token token, int tokenType, int modifiers)
    {
        // Token positions: LSP uses 0-based, compiler tokens use 1-based.
        var line = token.Line - 1;
        var col = token.Column - 1;
        var length = token.Value.Length;

        if (line < 0 || col < 0 || length <= 0) return;

        // LSP semantic tokens must not span multiple lines. Skip multiline
        // tokens entirely; TextMate grammar handles their highlighting.
        if (token.Value.Contains('\n')) return;

        builder.Push(line, col, length, tokenType, modifiers);
    }

    // The hole SPANS are `LinterInterpolationScan.HoleSpans`, which is the language's one scanner
    // for "where are the expression holes of this literal". The editor used to walk the literal's
    // characters itself — tracking brace depth, `{{` escapes, nested strings, backslash escapes and
    // the raw-literal brace heuristic — which was a third copy of a walk the parser and the linter
    // already had. All this does now is re-lex each hole's text and shift the resulting tokens into
    // the enclosing file's coordinates.
    internal static IReadOnlyList<Token> GetInterpolatedStringExpressionTokens(Token token)
    {
        if (!IsInterpolatedStringLiteral(token))
        {
            return Array.Empty<Token>();
        }

        var embeddedTokens = new List<Token>();
        foreach (var hole in LinterInterpolationScan.HoleSpans(token.Value, token.Line, token.Column))
        {
            AddEmbeddedExpressionTokens(embeddedTokens, hole, token.FileName);
        }

        return embeddedTokens;
    }

    // A hole's own tokens, in the enclosing file's coordinates. The sub-lexer starts each hole at
    // line 1, column 1, so a FIRST-line token additionally carries the hole's own column; a token on
    // a later line already begins at column 1 in both frames.
    private static void AddEmbeddedExpressionTokens(List<Token> destination, InterpolationHoleSpan hole, string? fileName)
    {
        var lexer = new Lexer(hole.Text, fileName);
        foreach (var token in lexer.Tokenize())
        {
            if (token.Type == TokenType.Eof)
            {
                continue;
            }

            var line = token.Line + hole.Line - 1;
            var column = token.Line == 1
                ? token.Column + hole.Column - 1
                : token.Column;

            destination.Add(new Token(token.Type, token.Value, line, column, fileName, token.IsTerminated));
        }
    }

    private (int TokenType, int Modifiers)? ClassifyIdentifier(
        Token token,
        DocumentState doc,
        HashSet<string> typeNames,
        HashSet<string> functionNames,
        HashSet<string> parameterNames,
        HashSet<string> propertyNames,
        HashSet<string> enumMemberNames,
        HashSet<SemanticTokenLocation>? catchResultBindings)
    {
        var name = token.Value;

        if (catchResultBindings?.Contains(new SemanticTokenLocation(token.Line, token.Column, token.Value)) == true)
        {
            return (8, CatchResultModifierMask); // variable.catchResult
        }

        // Built-in type spellings (int, string, bool, etc.)
        if (AnalyzerTypeReferenceFacts.IsBuiltInTypeName(name))
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

    internal static HashSet<SemanticTokenLocation> BuildCatchResultBindingSet(DocumentState doc)
    {
        var bindings = new HashSet<SemanticTokenLocation>();
        if (doc.CompilationUnit == null || doc.Tokens == null)
        {
            return bindings;
        }

        foreach (var declaration in doc.CompilationUnit.Declarations)
        {
            CollectFromDeclaration(declaration, doc.Tokens, bindings);
        }

        return bindings;
    }

    private static void CollectFromDeclaration(
        Declaration declaration,
        IReadOnlyList<Token> tokens,
        HashSet<SemanticTokenLocation> bindings)
    {
        switch (declaration)
        {
            case FunctionDeclaration functionDeclaration:
                CollectFromStatement(functionDeclaration.Body, tokens, bindings);
                CollectFromExpression(functionDeclaration.ExpressionBody, tokens, bindings);
                break;

            case ClassDeclaration classDeclaration:
                foreach (var member in classDeclaration.Members)
                {
                    CollectFromDeclaration(member, tokens, bindings);
                }
                break;

            case StructDeclaration structDeclaration:
                foreach (var member in structDeclaration.Members)
                {
                    CollectFromDeclaration(member, tokens, bindings);
                }
                break;

            case RecordDeclaration recordDeclaration:
                foreach (var member in recordDeclaration.Members)
                {
                    CollectFromDeclaration(member, tokens, bindings);
                }
                break;

            case InterfaceDeclaration interfaceDeclaration:
                foreach (var member in interfaceDeclaration.Members)
                {
                    CollectFromDeclaration(member, tokens, bindings);
                }
                break;

            case FieldDeclaration fieldDeclaration:
                CollectFromExpression(fieldDeclaration.Initializer, tokens, bindings);
                break;

            case PropertyDeclaration propertyDeclaration:
                CollectFromStatement(propertyDeclaration.GetBody, tokens, bindings);
                CollectFromStatement(propertyDeclaration.SetBody, tokens, bindings);
                CollectFromExpression(propertyDeclaration.ExpressionBody, tokens, bindings);
                break;

            case ConstructorDeclaration constructorDeclaration:
                CollectFromStatement(constructorDeclaration.Body, tokens, bindings);
                CollectFromExpression(constructorDeclaration.Initializer, tokens, bindings);
                break;

            case IndexerDeclaration indexerDeclaration:
                CollectFromStatement(indexerDeclaration.GetBody, tokens, bindings);
                CollectFromStatement(indexerDeclaration.SetBody, tokens, bindings);
                break;

            case EnumDeclaration enumDeclaration:
                foreach (var member in enumDeclaration.Members)
                {
                    CollectFromExpression(member.Value, tokens, bindings);
                }
                break;
        }
    }

    private static void CollectFromStatement(
        Statement? statement,
        IReadOnlyList<Token> tokens,
        HashSet<SemanticTokenLocation> bindings)
    {
        switch (statement)
        {
            case null:
                return;

            case BlockStatement block:
                foreach (var child in block.Statements)
                {
                    CollectFromStatement(child, tokens, bindings);
                }
                break;

            case ExpressionStatement expressionStatement:
                CollectFromExpression(expressionStatement.Expression, tokens, bindings);
                break;

            case VariableDeclarationStatement variableDeclaration:
                CollectFromExpression(variableDeclaration.Initializer, tokens, bindings);
                break;

            case TupleDeconstructionStatement tupleDeconstruction:
                AddCatchResultBinding(tupleDeconstruction, tokens, bindings);
                CollectFromExpression(tupleDeconstruction.Initializer, tokens, bindings);
                break;

            case ReturnStatement returnStatement:
                CollectFromExpression(returnStatement.Value, tokens, bindings);
                break;

            case ThrowStatement throwStatement:
                CollectFromExpression(throwStatement.Expression, tokens, bindings);
                break;

            case IfStatement ifStatement:
                CollectFromExpression(ifStatement.Condition, tokens, bindings);
                CollectFromStatement(ifStatement.ThenStatement, tokens, bindings);
                CollectFromStatement(ifStatement.ElseStatement, tokens, bindings);
                break;

            case ForStatement forStatement:
                CollectFromStatement(forStatement.Initializer, tokens, bindings);
                CollectFromExpression(forStatement.Condition, tokens, bindings);
                CollectFromExpression(forStatement.Iterator, tokens, bindings);
                CollectFromStatement(forStatement.Body, tokens, bindings);
                break;

            case ForeachStatement foreachStatement:
                CollectFromExpression(foreachStatement.Collection, tokens, bindings);
                CollectFromStatement(foreachStatement.Body, tokens, bindings);
                break;

            case AwaitForEachStatement awaitForEachStatement:
                CollectFromExpression(awaitForEachStatement.Collection, tokens, bindings);
                CollectFromStatement(awaitForEachStatement.Body, tokens, bindings);
                break;

            case WhileStatement whileStatement:
                CollectFromExpression(whileStatement.Condition, tokens, bindings);
                CollectFromStatement(whileStatement.Body, tokens, bindings);
                break;

            case TryStatement tryStatement:
                CollectFromStatement(tryStatement.TryBlock, tokens, bindings);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectFromStatement(catchClause.Block, tokens, bindings);
                }
                CollectFromStatement(tryStatement.FinallyBlock, tokens, bindings);
                break;

            case UsingStatement usingStatement:
                if (usingStatement.Declaration != null)
                {
                    CollectFromStatement(usingStatement.Declaration, tokens, bindings);
                }
                CollectFromStatement(usingStatement.Body, tokens, bindings);
                break;

            case LockStatement lockStatement:
                CollectFromExpression(lockStatement.LockObject, tokens, bindings);
                CollectFromStatement(lockStatement.Body, tokens, bindings);
                break;

            case SwitchStatement switchStatement:
                CollectFromExpression(switchStatement.Value, tokens, bindings);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var child in switchCase.Statements)
                    {
                        CollectFromStatement(child, tokens, bindings);
                    }
                }
                break;

            case LocalFunctionStatement localFunction:
                CollectFromStatement(localFunction.Function.Body, tokens, bindings);
                break;

            case PrintStatement printStatement:
                CollectFromExpression(printStatement.Value, tokens, bindings);
                break;

            case AssertStatement assertStatement:
                CollectFromExpression(assertStatement.Condition, tokens, bindings);
                CollectFromExpression(assertStatement.Message, tokens, bindings);
                break;

            case AssertThrowsStatement assertThrowsStatement:
                CollectFromStatement(assertThrowsStatement.Body, tokens, bindings);
                break;
        }
    }

    private static void CollectFromExpression(
        Expression? expression,
        IReadOnlyList<Token> tokens,
        HashSet<SemanticTokenLocation> bindings)
    {
        switch (expression)
        {
            case null:
                return;

            case BinaryExpression binary:
                CollectFromExpression(binary.Left, tokens, bindings);
                CollectFromExpression(binary.Right, tokens, bindings);
                break;

            case UnaryExpression unary:
                CollectFromExpression(unary.Operand, tokens, bindings);
                break;

            case MemberAccessExpression memberAccess:
                CollectFromExpression(memberAccess.Object, tokens, bindings);
                break;

            case IndexAccessExpression indexAccess:
                CollectFromExpression(indexAccess.Object, tokens, bindings);
                CollectFromExpression(indexAccess.Index, tokens, bindings);
                break;

            case CallExpression call:
                CollectFromExpression(call.Callee, tokens, bindings);
                foreach (var argument in call.Arguments)
                {
                    CollectFromExpression(argument.Value, tokens, bindings);
                }
                break;

            case AssignmentExpression assignment:
                CollectFromExpression(assignment.Target, tokens, bindings);
                CollectFromExpression(assignment.Value, tokens, bindings);
                break;

            case LambdaExpression lambda:
                CollectFromExpression(lambda.ExpressionBody, tokens, bindings);
                CollectFromStatement(lambda.BlockBody, tokens, bindings);
                break;

            case TernaryExpression ternary:
                CollectFromExpression(ternary.Condition, tokens, bindings);
                CollectFromExpression(ternary.ThenExpression, tokens, bindings);
                CollectFromExpression(ternary.ElseExpression, tokens, bindings);
                break;

            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectFromExpression(element, tokens, bindings);
                }
                break;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectFromExpression(element.Value, tokens, bindings);
                }
                break;

            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    CollectFromExpression(property.IndexExpression, tokens, bindings);
                    CollectFromExpression(property.Value, tokens, bindings);
                }
                break;

            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    CollectFromExpression(argument.Value, tokens, bindings);
                }
                CollectFromExpression(newExpression.Initializer, tokens, bindings);
                break;

            case CastExpression cast:
                CollectFromExpression(cast.Expression, tokens, bindings);
                break;

            case IsExpression isExpression:
                CollectFromExpression(isExpression.Expression, tokens, bindings);
                break;

            case MatchExpression match:
                CollectFromExpression(match.Value, tokens, bindings);
                foreach (var matchCase in match.Cases)
                {
                    CollectFromExpression(matchCase.Guard, tokens, bindings);
                    CollectFromExpression(matchCase.Expression, tokens, bindings);
                }
                break;

            case AwaitExpression awaitExpression:
                CollectFromExpression(awaitExpression.Expression, tokens, bindings);
                break;

            case SpreadExpression spread:
                CollectFromExpression(spread.Expression, tokens, bindings);
                break;

            case ParenthesizedExpression parenthesized:
                CollectFromExpression(parenthesized.Inner, tokens, bindings);
                break;
        }
    }

    private static void AddCatchResultBinding(
        TupleDeconstructionStatement tupleDeconstruction,
        IReadOnlyList<Token> tokens,
        HashSet<SemanticTokenLocation> bindings)
    {
        // `AnalyzerVariableDeclaration.IsErrorCaptureForm` owns which deconstructions are the
        // Go-style error capture. The editor used to test `Names.Count >= 2`, which painted the
        // modifier on three-name deconstructions the analyzer and the emitter both treat as
        // ordinary tuples.
        var names = tupleDeconstruction.Names;
        if (names.Count == 0 || !AnalyzerVariableDeclaration.IsErrorCaptureForm(names.Count, names[^1]))
        {
            return;
        }

        var catchResultIndex = tupleDeconstruction.Names.Count - 1;
        var identifierIndex = 0;

        foreach (var token in tokens)
        {
            if (token.Line < tupleDeconstruction.Line
                || (token.Line == tupleDeconstruction.Line && token.Column < tupleDeconstruction.Column))
            {
                continue;
            }

            if (token.Type is TokenType.ColonAssign or TokenType.Assign)
            {
                return;
            }

            if (token.Type != TokenType.Identifier)
            {
                continue;
            }

            if (identifierIndex == catchResultIndex && token.Value == "err")
            {
                bindings.Add(new SemanticTokenLocation(token.Line, token.Column, token.Value));
                return;
            }

            identifierIndex++;
        }
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

internal readonly record struct SemanticTokenLocation(int Line, int Column, string Name);
