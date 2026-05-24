using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
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
        if (KeywordTokenTypes.Contains(token.Type))
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
        if (OperatorTokenTypes.Contains(token.Type))
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

    internal static IReadOnlyList<Token> GetInterpolatedStringExpressionTokens(Token token)
    {
        if (!IsInterpolatedStringLiteral(token))
        {
            return Array.Empty<Token>();
        }

        var value = token.Value;
        var isRaw = token.Type == TokenType.InterpolatedRawStringLiteral;
        var start = isRaw ? 4 : 2; // $"""...""" or $"..."
        var end = isRaw ? value.Length - 3 : value.Length - 1;
        if (end < start || !value.EndsWith(isRaw ? "\"\"\"" : "\"", StringComparison.Ordinal))
        {
            end = value.Length;
        }

        var embeddedTokens = new List<Token>();
        var currentLine = token.Line;
        var currentColumn = token.Column + start;
        var i = start;

        void AdvancePosition(char ch)
        {
            if (ch == '\n')
            {
                currentLine++;
                currentColumn = 1;
            }
            else
            {
                currentColumn++;
            }
        }

        while (i < end)
        {
            var ch = value[i];

            if (!isRaw && ch == '\\' && i + 1 < end)
            {
                AdvancePosition(ch);
                i++;
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '{' && i + 1 < end && value[i + 1] == '{')
            {
                AdvancePosition(value[i]);
                i++;
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '}' && i + 1 < end && value[i + 1] == '}')
            {
                AdvancePosition(value[i]);
                i++;
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '{')
            {
                if (isRaw && IsRawStringLiteralBrace(value, start, end, i))
                {
                    AdvancePosition(ch);
                    i++;
                    continue;
                }

                AdvancePosition(ch);
                i++;

                var expressionLine = currentLine;
                var expressionColumn = currentColumn;
                var expression = new StringBuilder();
                var braceDepth = 1;
                var inNestedString = false;

                while (i < end && braceDepth > 0)
                {
                    ch = value[i];

                    if (inNestedString)
                    {
                        expression.Append(ch);
                        if (ch == '\\' && i + 1 < end)
                        {
                            AdvancePosition(ch);
                            i++;
                            ch = value[i];
                            expression.Append(ch);
                        }
                        else if (ch == '"')
                        {
                            inNestedString = false;
                        }
                    }
                    else
                    {
                        if (ch == '"')
                        {
                            inNestedString = true;
                            expression.Append(ch);
                        }
                        else if (ch == '{')
                        {
                            braceDepth++;
                            expression.Append(ch);
                        }
                        else if (ch == '}')
                        {
                            braceDepth--;
                            if (braceDepth == 0)
                            {
                                break;
                            }

                            expression.Append(ch);
                        }
                        else
                        {
                            expression.Append(ch);
                        }
                    }

                    AdvancePosition(ch);
                    i++;
                }

                AddEmbeddedExpressionTokens(
                    embeddedTokens,
                    expression.ToString(),
                    expressionLine,
                    expressionColumn,
                    token.FileName);

                if (i < end && value[i] == '}')
                {
                    AdvancePosition(value[i]);
                    i++;
                }

                continue;
            }

            AdvancePosition(ch);
            i++;
        }

        return embeddedTokens;
    }

    private static bool IsRawStringLiteralBrace(string value, int start, int end, int braceIndex)
    {
        var previous = braceIndex - 1;
        while (previous >= start && char.IsWhiteSpace(value[previous]))
        {
            previous--;
        }

        var close = value.IndexOf('}', braceIndex + 1);
        return (previous >= start && value[previous] == ':')
            || close < 0
            || close >= end
            || value.Substring(braceIndex + 1, close - braceIndex - 1).IndexOfAny(new[] { '\r', '\n' }) >= 0;
    }

    private static void AddEmbeddedExpressionTokens(
        List<Token> destination,
        string expression,
        int expressionLine,
        int expressionColumn,
        string? fileName)
    {
        if (string.IsNullOrWhiteSpace(expression))
        {
            return;
        }

        var lexer = new Lexer(expression, fileName);
        foreach (var token in lexer.Tokenize())
        {
            if (token.Type == TokenType.Eof)
            {
                continue;
            }

            var line = token.Line + expressionLine - 1;
            var column = token.Line == 1
                ? token.Column + expressionColumn - 1
                : token.Column;

            destination.Add(new Token(token.Type, token.Value, line, column, fileName));
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
        if (!IsCatchResultTupleDeconstruction(tupleDeconstruction))
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

    private static bool IsCatchResultTupleDeconstruction(TupleDeconstructionStatement tupleDeconstruction)
    {
        return tupleDeconstruction.Names.Count >= 2
            && tupleDeconstruction.Names[^1] == "err";
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
