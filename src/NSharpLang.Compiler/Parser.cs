using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public class Parser
{
    private readonly List<Token> _tokens;
    private readonly string? _fileName;
    private readonly string? _sourceCode;
    private readonly string[]? _sourceLines;
    private readonly List<CompilerError> _errors = new();
    private int _position;
    private bool _panicMode;
    private int? _currentRecoveryBoundaryColumn;

    private readonly record struct DiagnosticSpan(int Line, int Column, int Length);

    public Parser(List<Token> tokens, string? fileName = null, string? sourceCode = null)
    {
        _tokens = tokens.Where(t => t.Type != TokenType.Newline).ToList();
        _fileName = fileName;
        _sourceCode = sourceCode;
        _sourceLines = sourceCode?.Split('\n');
    }

    public ParseResult ParseCompilationUnit()
    {
        CompilationUnit? unit = null;

        try
        {
            var line = Current.Line;
            var column = Current.Column;

            // Parse namespace (optional, file-scoped)
            NamespaceDeclaration? namespaceDecl = null;
            if (Check(TokenType.Namespace))
            {
                namespaceDecl = ParseNamespace();
            }

            // Parse package/import directives. Canonical N# uses package-first,
            // while older sources may still place imports before package.
            var imports = new List<ImportDirective>();
            var fileImports = new List<Statement>();
            PackageDeclaration? packageDecl = null;
            while (Check(TokenType.Package) || Check(TokenType.Import))
            {
                if (Check(TokenType.Package))
                {
                    if (packageDecl != null)
                    {
                        ReportError(
                            ErrorCode.InvalidSyntax,
                            "Only one package declaration is allowed",
                            Current.Line,
                            Current.Column,
                            humanExplanation: "A source file can belong to a single package.",
                            hint: "Remove the extra package declaration.",
                            length: Math.Max(1, Current.Value.Length));
                    }

                    packageDecl = ParsePackage();
                    continue;
                }

                var import = ParseImport();
                if (import is NamespaceImport nsImport)
                {
                    imports.Add(new ImportDirective(nsImport.Namespace, nsImport.Alias, nsImport.Line, nsImport.Column));
                }
                else if (import is FileImport fileImport)
                {
                    fileImports.Add(fileImport);
                }
            }

            // Parse top-level declarations with error recovery
            var declarations = new List<Declaration>();
            while (!IsAtEnd())
            {
                _panicMode = false; // Reset at each declaration boundary
                var startPosition = _position;
                var previousRecoveryBoundaryColumn = _currentRecoveryBoundaryColumn;

                try
                {
                    _currentRecoveryBoundaryColumn = Current.Column;
                    declarations.Add(ParseDeclaration());
                }
                catch (Exception ex)
                {
                    // ParseDeclaration or its callees threw unexpectedly.
                    // Report the error and synchronize to the next declaration.
                    _panicMode = false; // Ensure we can report this error
                    ReportError(
                        ErrorCode.InvalidSyntax,
                        ex.Message,
                        Current.Line,
                        Current.Column,
                        humanExplanation: "An unexpected error occurred while parsing this declaration."
                    );
                    var exStartPos = _position;
                    SynchronizeToNextDeclaration();
                    // If synchronization didn't advance, force-advance to prevent infinite loop
                    if (_position == exStartPos && !IsAtEnd())
                    {
                        Advance();
                    }
                    continue;
                }
                finally
                {
                    _currentRecoveryBoundaryColumn = previousRecoveryBoundaryColumn;
                }

                // If ParseDeclaration returned but we're in panic mode and
                // didn't make progress, synchronize to avoid infinite loops
                if (_position == startPosition && !IsAtEnd())
                {
                    SynchronizeToNextDeclaration();
                    // If synchronization also didn't advance (e.g., stuck on a keyword
                    // that looks like a declaration start but fails to parse), force-advance
                    if (_position == startPosition && !IsAtEnd())
                    {
                        Advance();
                    }
                }
            }

            unit = new CompilationUnit(namespaceDecl, imports, fileImports, packageDecl, declarations, line, column);
        }
        catch (Exception ex)
        {
            // Shouldn't happen after we replace all throws, but safety net
            ReportError(
                ErrorCode.InvalidSyntax,
                ex.Message,
                Current.Line,
                Current.Column,
                humanExplanation: "An unexpected error occurred while parsing."
            );
        }

        return new ParseResult
        {
            CompilationUnit = unit,
            Errors = _errors
        };
    }

    private NamespaceDeclaration ParseNamespace()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Namespace, "Expected 'namespace'");
        var name = ParseQualifiedName();
        return new NamespaceDeclaration(name, line, column);
    }

    private PackageDeclaration ParsePackage()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Package, "Expected 'package'");
        var name = ParseQualifiedName();
        return new PackageDeclaration(name, line, column);
    }


    private Statement ParseImport()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Import, "Expected 'import'");

        // File-based import: import "path/to/file" [as Alias]
        if (Check(TokenType.StringLiteral))
        {
            var pathToken = Advance();
            var path = pathToken.Value.Trim('"');
            string? alias = null;

            if (Check(TokenType.As))
            {
                Advance();
                alias = ConsumeIdentifier("Expected alias name after 'as'");
            }

            return new FileImport(path, alias, line, column)
            {
                PathColumn = pathToken.Column,
                PathLength = Math.Max(1, pathToken.Value.Length)
            };
        }

        // Namespace import: import System.Collections.Generic [as Alias]
        var ns = ParseQualifiedName();
        string? nsAlias = null;

        if (Check(TokenType.As))
        {
            Advance();
            nsAlias = ConsumeIdentifier("Expected alias name after 'as'");
        }

        return new NamespaceImport(ns, nsAlias, line, column);
    }

    private string ParseQualifiedName()
    {
        var parts = new List<string> { ConsumeIdentifier("Expected identifier") };
        while (Check(TokenType.Dot))
        {
            Advance();
            parts.Add(ConsumeIdentifier("Expected identifier after '.'"));
        }
        return string.Join(".", parts);
    }

    private Declaration ParseDeclaration()
    {
        // Test declarations don't have attributes or modifiers (contextual keyword "test")
        if (IsTestDeclarationStart())
            return ParseTestDeclaration();

        // Setup block declarations (contextual keyword "setup")
        if (IsSetupDeclarationStart())
            return ParseSetupDeclaration();

        // Teardown block declarations (contextual keyword "teardown")
        if (IsTeardownDeclarationStart())
            return ParseTeardownDeclaration();

        // Preprocessor directives can appear at top level
        if (Check(TokenType.PreprocessorDirective))
        {
            var line = Current.Line;
            var column = Current.Column;
            var directive = Current.Value;
            Advance();
            return new PreprocessorDeclaration(directive, line, column);
        }

        var attributes = ParseAttributes();
        var modifiers = ParseModifiers();

        if (Check(TokenType.Func))
            return ParseFunctionDeclaration(attributes, modifiers);
        if (Check(TokenType.Class))
            return ParseClassDeclaration(attributes, modifiers);
        if (Check(TokenType.Struct))
            return ParseStructDeclaration(attributes, modifiers);
        if (Check(TokenType.Record))
            return ParseRecordDeclaration(attributes, modifiers);
        if (Check(TokenType.Interface) || (Check(TokenType.Duck) && LookAhead(1).Type == TokenType.Interface))
            return ParseInterfaceDeclaration(attributes, modifiers);
        if (Check(TokenType.Union))
            return ParseUnionDeclaration(attributes, modifiers);
        if (Check(TokenType.Enum))
            return ParseEnumDeclaration(attributes, modifiers);
        if (Check(TokenType.Type))
            return ParseTypeAliasDeclaration();

        ReportError(
            ErrorCode.UnexpectedToken,
            $"Unexpected token '{Current.Value}'",
            Current.Line,
            Current.Column,
            humanExplanation: $"I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '{Current.Value}' instead.",
            hint: "Top-level declarations must be functions, classes, structs, enums, interfaces, or type aliases.",
            length: Current.Value.Length
        );

        // Skip this token and try to continue
        Advance();

        // Return an error declaration as placeholder
        return new ClassDeclaration(
            "<error>",
            null,  // TypeParameters
            null,  // BaseClass
            new List<TypeReference>(),  // Interfaces
            new List<Declaration>(),  // Members
            null,  // PrimaryConstructorParameters
            Modifiers.None,  // Modifiers
            new List<AttributeNode>(),  // Attributes
            Current.Line,
            Current.Column
        );
    }

    private List<AttributeNode> ParseAttributes()
    {
        var attributes = new List<AttributeNode>();
        while (Check(TokenType.LeftBracket))
        {
            Advance();
            // Support qualified attribute names (e.g., System.Runtime.CompilerServices.InlineArray)
            var name = ConsumeIdentifier("Expected attribute name");
            while (Check(TokenType.Dot))
            {
                Advance(); // consume '.'
                name += "." + ConsumeIdentifier("Expected identifier after '.'");
            }
            var args = new List<Argument>();

            if (Check(TokenType.LeftParen))
            {
                Advance(); // consume '('
                args = ParseArgumentList();
            }

            attributes.Add(new AttributeNode(name, args));
            Consume(TokenType.RightBracket, "Expected ']'");
        }
        return attributes;
    }

    private Modifiers ParseModifiers()
    {
        var modifiers = Modifiers.None;

        while (true)
        {
            if (Check(TokenType.Public))
            {
                modifiers |= Modifiers.Public;
                Advance();
            }
            else if (Check(TokenType.Private))
            {
                modifiers |= Modifiers.Private;
                Advance();
            }
            else if (Check(TokenType.Static))
            {
                modifiers |= Modifiers.Static;
                Advance();
            }
            else if (Check(TokenType.Internal))
            {
                modifiers |= Modifiers.Internal;
                Advance();
            }
            else if (Check(TokenType.Protected))
            {
                modifiers |= Modifiers.Protected;
                Advance();
            }
            else if (Check(TokenType.Virtual))
            {
                modifiers |= Modifiers.Virtual;
                Advance();
            }
            else if (Check(TokenType.Override))
            {
                modifiers |= Modifiers.Override;
                Advance();
            }
            else if (Check(TokenType.Abstract))
            {
                modifiers |= Modifiers.Abstract;
                Advance();
            }
            else if (Check(TokenType.Sealed))
            {
                modifiers |= Modifiers.Sealed;
                Advance();
            }
            else if (Check(TokenType.Partial))
            {
                modifiers |= Modifiers.Partial;
                Advance();
            }
            else if (Check(TokenType.Async))
            {
                modifiers |= Modifiers.Async;
                Advance();
            }
            else if (Check(TokenType.File))
            {
                modifiers |= Modifiers.File;
                Advance();
            }
            else
            {
                break;
            }
        }

        return modifiers;
    }

    private FunctionDeclaration ParseFunctionDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;

        // Check for conversion operators: implicit operator TargetType / explicit operator TargetType
        bool isConversionOperator = false;
        bool isImplicitConversion = false;

        // Check for operator overloading: func operator +
        bool isOperatorOverload = false;
        string? operatorSymbol = null;
        SourceSpan operatorKeywordSpan = SourceSpan.None;
        SourceSpan operatorSymbolSpan = SourceSpan.None;
        string name;
        string returnTypeDiagnosticName = "function";
        int returnTypeDiagnosticLine = line;
        int returnTypeDiagnosticColumn = column;
        int returnTypeDiagnosticLength = Math.Max(1, Current.Value.Length);

        if (Check(TokenType.Implicit) || Check(TokenType.Explicit))
        {
            // Conversion operator - no 'func' keyword
            isConversionOperator = true;
            isImplicitConversion = Check(TokenType.Implicit);
            Advance(); // consume 'implicit' or 'explicit'

            Consume(TokenType.Operator, "Expected 'operator' after 'implicit' or 'explicit'");
            name = isImplicitConversion ? "implicit operator" : "explicit operator";
        }
        else
        {
            // Regular function or operator overload - starts with 'func'
            Consume(TokenType.Func, "Expected 'func'");

            // Check for generator: func*
            if (Check(TokenType.Star))
            {
                modifiers |= Modifiers.Generator;
                Advance();
            }

            // Compatibility: accept legacy postfix async (`func async` / `func async*`).
            // Canonical syntax is parsed via modifiers before `func`: `async func` / `async func*`.
            if (Check(TokenType.Async))
            {
                modifiers |= Modifiers.Async;
                Advance();

                // Compatibility: accept legacy postfix async iterator `func async*`.
                if (Check(TokenType.Star))
                {
                    modifiers |= Modifiers.Generator;
                    Advance();
                }
            }

            if (Check(TokenType.Operator))
            {
                isOperatorOverload = true;
                var operatorKeywordToken = Advance(); // consume 'operator'
                operatorKeywordSpan = SpanFromTokens(operatorKeywordToken, operatorKeywordToken);
                returnTypeDiagnosticName = "operator overload";
                returnTypeDiagnosticLine = operatorKeywordToken.Line;
                returnTypeDiagnosticColumn = operatorKeywordToken.Column;
                returnTypeDiagnosticLength = Math.Max(1, operatorKeywordToken.Value.Length);

                // Get the operator symbol
                var operatorSymbolToken = Current;
                operatorSymbol = ParseOperatorSymbol();
                operatorSymbolSpan = SpanFromTokens(operatorSymbolToken, operatorSymbolToken);
                name = "operator " + operatorSymbol; // For error reporting
            }
            else
            {
                var nameLine = Current.Line;
                var nameColumn = Current.Column;
                name = ConsumeIdentifier("Expected function name");
                if (name != "<error>")
                {
                    returnTypeDiagnosticName = name;
                    returnTypeDiagnosticLine = nameLine;
                    returnTypeDiagnosticColumn = nameColumn;
                    returnTypeDiagnosticLength = Math.Max(1, name.Length);
                }
            }
        }

        var typeParams = ParseTypeParameters();

        TypeReference? returnType = null;

        // For conversion operators, the return type comes BEFORE the parameter list
        // Syntax: implicit operator TargetType(source: SourceType): TargetType
        if (isConversionOperator)
        {
            returnType = ParseTypeReference();
        }

        var parameters = ParseParameterList();

        var parameterListEndToken = Previous;

        // For regular functions, return type comes AFTER parameters (with colon)
        if (!isConversionOperator &&
            (Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater)))
        {
            if (Check(TokenType.Colon))
            {
                Advance();
            }
            else
            {
                // Support `->` return type syntax (common in tests / functional-style code)
                Advance(); // consume '-'
                Consume(TokenType.Greater, "Expected '>' after '-' in return type arrow");
            }
            returnType = ParseTypeReference();
        }
        else if (!isConversionOperator && IsLikelyMissingReturnTypeMarker(parameterListEndToken))
        {
            ReportMissingReturnTypeMarker(
                returnTypeDiagnosticName,
                returnTypeDiagnosticLine,
                returnTypeDiagnosticColumn,
                returnTypeDiagnosticLength);
            returnType = ParseTypeReference();
        }

        var constraints = ParseGenericConstraints();

        BlockStatement? body = null;
        Expression? expressionBody = null;

        if (Check(TokenType.Arrow))  // Expression-bodied method: func Foo() => expr
        {
            Advance();
            expressionBody = ParseExpression();
        }
        else if (Check(TokenType.LeftBrace))
        {
            body = ParseBlock(new DiagnosticSpan(returnTypeDiagnosticLine, returnTypeDiagnosticColumn, returnTypeDiagnosticLength));
        }

        return new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParams, constraints, modifiers, attributes, isOperatorOverload, operatorSymbol, isConversionOperator, isImplicitConversion, line, column)
        {
            OperatorKeywordSpan = operatorKeywordSpan,
            OperatorSymbolSpan = operatorSymbolSpan
        };
    }

    private TestDeclaration ParseTestDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        ConsumeTestKeyword();

        // Test description must be a string literal
        string description;
        if (Current.Type != TokenType.StringLiteral)
        {
            ReportError(
                ErrorCode.ExpectedToken,
                $"Expected string literal for test description. Got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: "Test declarations require a string literal describing what the test does.",
                hint: "A test should start with the 'test' keyword followed by a string in quotes.",
                suggestions: new List<string> {
                    "Example: test \"should calculate sum correctly\" { ... }",
                    "Example: test \"validates user input\" { ... }"
                },
                length: Current.Value.Length
            );
            description = "<error>";
            if (!IsAtEnd()) Advance(); // Skip the invalid token
        }
        else
        {
            description = Current.Value.Trim('"'); // Remove quotes
            Advance();
        }

        // Check for table-driven test syntax: with (params) [cases]
        List<Parameter>? tableParameters = null;
        List<List<Expression>>? tableCases = null;

        if (Check(TokenType.With))
        {
            Advance(); // consume 'with'
            tableParameters = ParseParameterList();

            Consume(TokenType.LeftBracket, "Expected '[' to start test cases");
            tableCases = new List<List<Expression>>();

            while (!Check(TokenType.RightBracket) && !IsAtEnd())
            {
                Consume(TokenType.LeftParen, "Expected '(' to start test case row");
                var row = new List<Expression>();
                while (!Check(TokenType.RightParen) && !IsAtEnd())
                {
                    row.Add(ParseExpression());
                    if (!Check(TokenType.RightParen))
                        Match(TokenType.Comma);
                }
                Consume(TokenType.RightParen, "Expected ')' to end test case row");
                tableCases.Add(row);
                if (!Check(TokenType.RightBracket))
                    Match(TokenType.Comma);
            }

            Consume(TokenType.RightBracket, "Expected ']' to end test cases");
        }

        // Check for skip: test "desc" skip "reason"
        string? skipReason = null;
        if (Current.Type == TokenType.Identifier && Current.Value == "skip")
        {
            Advance(); // consume 'skip'
            if (Current.Type != TokenType.StringLiteral)
            {
                ReportError(
                    ErrorCode.ExpectedToken,
                    $"Expected string literal for skip reason. Got '{Current.Value}'",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "The 'skip' modifier requires a string explaining why the test is skipped.",
                    hint: "Add a reason string after 'skip'.",
                    suggestions: new List<string> {
                        "Example: test \"my test\" skip \"needs network\" { ... }"
                    },
                    length: Current.Value.Length
                );
            }
            else
            {
                skipReason = Current.Value.Trim('"');
                Advance();
            }
        }

        // Parse test body
        var body = ParseBlock(new DiagnosticSpan(line, column, Math.Max(1, "test".Length)));

        return new TestDeclaration(description, body, tableParameters, tableCases, skipReason, line, column);
    }

    private bool IsTestDeclarationStart()
    {
        if (Check(TokenType.Test))
            return true;

        return Check(TokenType.Identifier) && Current.Value == "test";
    }

    private void ConsumeTestKeyword()
    {
        if (Check(TokenType.Test))
        {
            Advance();
            return;
        }

        if (Check(TokenType.Identifier) && Current.Value == "test")
        {
            Advance();
            return;
        }

        Consume(TokenType.Test, "Expected 'test'");
    }

    private bool IsSetupDeclarationStart()
    {
        return Current.Type == TokenType.Identifier && Current.Value == "setup"
            && LookAhead(1).Type == TokenType.LeftBrace;
    }

    private SetupDeclaration ParseSetupDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        Advance(); // consume 'setup'
        var body = ParseBlock(new DiagnosticSpan(line, column, Math.Max(1, "setup".Length)));
        return new SetupDeclaration(body, line, column);
    }

    private bool IsTeardownDeclarationStart()
    {
        return Current.Type == TokenType.Identifier && Current.Value == "teardown"
            && LookAhead(1).Type == TokenType.LeftBrace;
    }

    private TeardownDeclaration ParseTeardownDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        Advance(); // consume 'teardown'
        var body = ParseBlock(new DiagnosticSpan(line, column, Math.Max(1, "teardown".Length)));
        return new TeardownDeclaration(body, line, column);
    }

    private List<TypeParameter>? ParseTypeParameters()
    {
        if (!Check(TokenType.Less))
            return null;

        Advance();
        var typeParams = new List<TypeParameter>();

        do
        {
            var name = ConsumeIdentifier("Expected type parameter name");
            typeParams.Add(new TypeParameter(name));
        } while (Match(TokenType.Comma));

        Consume(TokenType.Greater, "Expected '>'");
        return typeParams;
    }

    private List<Parameter> ParseParameterList()
    {
        Consume(TokenType.LeftParen, "Expected '('");
        var parameters = new List<Parameter>();

        if (!Check(TokenType.RightParen))
        {
            do
            {
                if (IsParameterListRecoveryBoundary(Previous))
                    break;

                var attributes = ParseAttributes();

                var modifier = ParameterModifier.None;
                if (Check(TokenType.Params))
                {
                    modifier = ParameterModifier.Params;
                    Advance();
                }
                else if (Check(TokenType.Ref))
                {
                    modifier = ParameterModifier.Ref;
                    Advance();
                }
                else if (Check(TokenType.Out))
                {
                    modifier = ParameterModifier.Out;
                    Advance();
                }

                var isThis = false;
                if (Check(TokenType.This))
                {
                    isThis = true;
                    Advance();
                }

                var paramLine = Current.Line;
                var paramColumn = Current.Column;
                var paramName = ConsumeIdentifier("Expected parameter name");
                ConsumeParameterColon(paramName, paramLine, paramColumn);
                var paramType = ParseTypeReference();

                Expression? defaultValue = null;
                if (Check(TokenType.Assign))
                {
                    Advance();
                    defaultValue = ParseExpression();
                }

                parameters.Add(new Parameter(paramName, paramType, defaultValue, isThis, modifier,
                    attributes.Count > 0 ? attributes : null, paramLine, paramColumn));
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightParen, "Expected ')'");
        return parameters;
    }

    private bool IsParameterListRecoveryBoundary(Token openingToken)
        => IsAtEnd() ||
           Check(TokenType.LeftBrace) ||
           Check(TokenType.RightBrace) ||
           Check(TokenType.Colon) ||
           Check(TokenType.Arrow) ||
           (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater) ||
           IsContinuationRecoveryBoundary(openingToken);

    private List<GenericConstraint>? ParseGenericConstraints()
    {
        if (!Check(TokenType.Where))
            return null;

        var constraints = new List<GenericConstraint>();

        while (Check(TokenType.Where))
        {
            Advance();
            var typeParam = ConsumeIdentifier("Expected type parameter");
            Consume(TokenType.Colon, "Expected ':'");

            var constraintTypes = new List<TypeReference>();
            var specialConstraints = SpecialConstraintKind.None;
            Token? classConstraintToken = null;
            Token? structConstraintToken = null;
            Token? newConstraintStartToken = null;
            Token? newConstraintEndToken = null;

            do
            {
                if (Check(TokenType.Class))
                {
                    classConstraintToken = Advance();
                    specialConstraints |= SpecialConstraintKind.Class;
                }
                else if (Check(TokenType.Struct))
                {
                    structConstraintToken = Advance();
                    specialConstraints |= SpecialConstraintKind.Struct;
                }
                else if (Check(TokenType.New) && LookAhead(1).Type == TokenType.LeftParen)
                {
                    newConstraintStartToken = Advance(); // consume 'new'
                    Advance(); // consume '('
                    newConstraintEndToken = Consume(TokenType.RightParen, "Expected ')' after 'new('");
                    specialConstraints |= SpecialConstraintKind.New;
                }
                else
                {
                    constraintTypes.Add(ParseTypeReference());
                }
            } while (Match(TokenType.Comma));

            // Validate: class and struct are mutually exclusive
            if (specialConstraints.HasFlag(SpecialConstraintKind.Class) &&
                specialConstraints.HasFlag(SpecialConstraintKind.Struct))
            {
                var diagnosticToken = LaterToken(classConstraintToken, structConstraintToken);
                ReportError(
                    ErrorCode.InvalidSyntax,
                    "Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive",
                    diagnosticToken?.Line ?? Current.Line,
                    diagnosticToken?.Column ?? Current.Column,
                    humanExplanation: "A type parameter cannot be both a reference type (class) and a value type (struct) at the same time.",
                    length: TokenLengthOrFallback(diagnosticToken)
                );
            }

            // Validate: struct implies new(), so combining them is redundant and illegal in C#
            if (specialConstraints.HasFlag(SpecialConstraintKind.Struct) &&
                specialConstraints.HasFlag(SpecialConstraintKind.New))
            {
                ReportError(
                    ErrorCode.InvalidSyntax,
                    "Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor",
                    newConstraintStartToken?.Line ?? Current.Line,
                    newConstraintStartToken?.Column ?? Current.Column,
                    humanExplanation: "The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in C#.",
                    length: TokenSpanLengthOrFallback(newConstraintStartToken, newConstraintEndToken)
                );
            }

            constraints.Add(new GenericConstraint(typeParam, constraintTypes, specialConstraints));
        }

        return constraints;
    }

    private ClassDeclaration ParseClassDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Class, "Expected 'class'");

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected class name");
        var typeBodyDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, "class".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));
        var typeParams = ParseTypeParameters();

        // Parse optional primary constructor parameters (C# 12)
        List<Parameter>? primaryCtorParams = null;
        if (Check(TokenType.LeftParen))
        {
            primaryCtorParams = ParseParameterList();
        }

        TypeReference? baseClass = null;
        var interfaces = new List<TypeReference>();

        if (Check(TokenType.Colon))
        {
            Advance();
            var types = new List<TypeReference> { ParseTypeReference() };

            while (Match(TokenType.Comma))
            {
                types.Add(ParseTypeReference());
            }

            // First non-interface type is base class
            baseClass = types.FirstOrDefault();
            interfaces = types.Skip(1).ToList();
        }

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = ParseMemberList(typeBodyDiagnosticSpan);

        return new ClassDeclaration(name, typeParams, baseClass, interfaces, members, primaryCtorParams, modifiers, attributes, line, column);
    }

    private StructDeclaration ParseStructDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Struct, "Expected 'struct'");

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected struct name");
        var typeBodyDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, "struct".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));
        var typeParams = ParseTypeParameters();

        // Parse optional primary constructor parameters (C# 12)
        List<Parameter>? primaryCtorParams = null;
        if (Check(TokenType.LeftParen))
        {
            primaryCtorParams = ParseParameterList();
        }

        var interfaces = new List<TypeReference>();
        if (Check(TokenType.Colon))
        {
            Advance();
            do
            {
                interfaces.Add(ParseTypeReference());
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = ParseMemberList(typeBodyDiagnosticSpan);

        return new StructDeclaration(name, typeParams, interfaces, members, primaryCtorParams, modifiers, attributes, line, column);
    }

    private RecordDeclaration ParseRecordDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Record, "Expected 'record'");

        // Check for 'struct' keyword after 'record' (C# 10: record struct)
        bool isStruct = false;
        if (Check(TokenType.Struct))
        {
            isStruct = true;
            Advance();
        }

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected record name");
        var typeBodyDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, "record".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));
        var typeParams = ParseTypeParameters();

        // Parse optional primary constructor parameters (C# 12)
        List<Parameter>? primaryCtorParams = null;
        if (Check(TokenType.LeftParen))
        {
            primaryCtorParams = ParseParameterList();
        }

        var interfaces = new List<TypeReference>();
        if (Check(TokenType.Colon))
        {
            Advance();
            do
            {
                interfaces.Add(ParseTypeReference());
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = ParseMemberList(typeBodyDiagnosticSpan);

        return new RecordDeclaration(name, typeParams, interfaces, members, primaryCtorParams, isStruct, modifiers, attributes, line, column);
    }

    private InterfaceDeclaration ParseInterfaceDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        var isDuck = false;

        if (Check(TokenType.Duck))
        {
            isDuck = true;
            Advance();
        }

        Consume(TokenType.Interface, "Expected 'interface'");
        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected interface name");
        var typeBodyDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, isDuck ? "duck".Length : "interface".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));
        var typeParams = ParseTypeParameters();

        var baseInterfaces = new List<TypeReference>();
        if (Check(TokenType.Colon))
        {
            Advance();
            do
            {
                baseInterfaces.Add(ParseTypeReference());
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = ParseMemberList(typeBodyDiagnosticSpan);

        return new InterfaceDeclaration(name, typeParams, baseInterfaces, members, modifiers, isDuck, attributes, line, column);
    }

    private UnionDeclaration ParseUnionDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Union, "Expected 'union'");

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected union name");
        var unionDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, "union".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));

        Consume(TokenType.LeftBrace, "Expected '{'");
        var cases = new List<UnionCase>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            var startPosition = _position;
            var caseLine = Current.Line;
            var caseColumn = Current.Column;
            var caseName = ConsumeIdentifier("Expected union case name");
            List<UnionCaseProperty>? properties = null;

            if (Check(TokenType.LeftBrace))
            {
                Advance();
                properties = new List<UnionCaseProperty>();

                while (!Check(TokenType.RightBrace) && !IsAtEnd())
                {
                    var propertyStartPosition = _position;
                    var propName = ConsumeIdentifier("Expected property name");
                    Consume(TokenType.Colon, "Expected ':'");
                    var propType = ParseTypeReference();
                    properties.Add(new UnionCaseProperty(propName, propType));

                    if (!Check(TokenType.RightBrace))
                        Match(TokenType.Comma);

                    EnsureProgress(propertyStartPosition);
                }

                Consume(TokenType.RightBrace, "Expected '}'");
            }

            cases.Add(new UnionCase(caseName, properties, caseLine, caseColumn));

            if (EnsureProgress(startPosition))
            {
                _panicMode = false; // Reset for next case
                continue;
            }
        }

        if (Check(TokenType.RightBrace))
            Advance();
        else if (IsAtEnd())
        {
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                unionDiagnosticSpan.Line,
                unionDiagnosticSpan.Column,
                humanExplanation: $"The union body that started on line {line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this union declaration.",
                length: unionDiagnosticSpan.Length
            );
        }

        return new UnionDeclaration(name, cases, modifiers, attributes, line, column);
    }

    private EnumDeclaration ParseEnumDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Enum, "Expected 'enum'");

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected enum name");
        var enumDiagnosticSpan = name == "<error>"
            ? new DiagnosticSpan(line, column, Math.Max(1, "enum".Length))
            : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length));

        // Parse optional `: type` annotation (e.g., `enum Status: string { ... }`)
        var enumType = EnumType.Int; // Default to int
        var hasExplicitType = false;
        if (Check(TokenType.Colon))
        {
            Advance();
            var typeTokenLine = Current.Line;
            var typeTokenColumn = Current.Column;
            var typeName = ConsumeIdentifier("Expected enum backing type ('int' or 'string')");
            hasExplicitType = true;
            if (typeName == "string")
            {
                enumType = EnumType.String;
            }
            else if (typeName != "int")
            {
                ReportError(ErrorCode.UnexpectedToken,
                    $"Unsupported enum backing type '{typeName}'. Only 'int' and 'string' are supported.",
                    typeTokenLine, typeTokenColumn);
            }
        }

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = new List<EnumMember>();

        if (!Check(TokenType.RightBrace))
        {
            while (!Check(TokenType.RightBrace) && !IsAtEnd())
            {
                var startPosition = _position;
                var memberLine = Current.Line;
                var memberColumn = Current.Column;
                var memberName = ConsumeIdentifier("Expected enum member name");
                Expression? value = null;

                if (Check(TokenType.Assign))
                {
                    Advance();
                    value = ParseExpression();

                    // Infer enum type from first assigned value (only if no explicit type annotation)
                    if (!hasExplicitType && members.Count == 0 && value is StringLiteralExpression)
                    {
                        enumType = EnumType.String;
                    }
                }

                members.Add(new EnumMember(memberName, value, memberLine, memberColumn));

                if (Check(TokenType.Comma))
                    Advance();
                else
                    break;

                if (EnsureProgress(startPosition))
                {
                    continue;
                }
            }
        }

        if (Check(TokenType.RightBrace))
            Advance();
        else if (IsAtEnd())
        {
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                enumDiagnosticSpan.Line,
                enumDiagnosticSpan.Column,
                humanExplanation: $"The enum body that started on line {line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this enum declaration.",
                length: enumDiagnosticSpan.Length
            );
        }

        return new EnumDeclaration(name, members, enumType, modifiers, attributes, line, column);
    }

    private Declaration ParseTypeAliasDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Type, "Expected 'type'");

        var name = ConsumeIdentifier("Expected type alias name");
        Consume(TokenType.Assign, "Expected '='");

        // Check for newtype keyword: type X = newtype Y
        if (Check(TokenType.Newtype))
        {
            Advance(); // consume 'newtype'
            var underlyingType = ParseTypeReference();
            return new NewtypeDeclaration(name, underlyingType, line, column);
        }

        var type = ParseTypeReference();

        return new TypeAliasDeclaration(name, type, line, column);
    }

    /// <summary>
    /// Parse a list of member declarations inside a type body (class/struct/record/interface).
    /// Handles error recovery by synchronizing to the next member or closing brace.
    /// Assumes the opening '{' has already been consumed. The owner span points to the
    /// declaration name/keyword that should carry a missing-brace diagnostic.
    /// </summary>
    private List<Declaration> ParseMemberList(DiagnosticSpan? ownerSpan = null)
    {
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            _panicMode = false; // Reset at each member boundary
            var startPosition = _position;
            var previousRecoveryBoundaryColumn = _currentRecoveryBoundaryColumn;
            try
            {
                _currentRecoveryBoundaryColumn = Current.Column;
                members.Add(ParseMemberDeclaration());
            }
            finally
            {
                _currentRecoveryBoundaryColumn = previousRecoveryBoundaryColumn;
            }

            // If we didn't make progress, synchronize to avoid infinite loops
            if (_position == startPosition && !IsAtEnd())
            {
                SynchronizeToNextStatement();
                // If synchronization also didn't advance (e.g., stuck on a statement
                // keyword like 'return' inside a member list), force-advance
                if (_position == startPosition && !IsAtEnd())
                {
                    Advance();
                }
            }
        }

        // Only consume '}' if present; otherwise report the missing brace
        if (Check(TokenType.RightBrace))
        {
            Advance();
        }
        else if (IsAtEnd() && ownerSpan is { } diagnosticSpan)
        {
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                diagnosticSpan.Line,
                diagnosticSpan.Column,
                humanExplanation: $"The type body that started on line {diagnosticSpan.Line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this type declaration.",
                length: diagnosticSpan.Length
            );
        }

        return members;
    }

    private Declaration ParseMemberDeclaration()
    {
        // Preprocessor directives can appear in class members
        if (Check(TokenType.PreprocessorDirective))
        {
            var line = Current.Line;
            var column = Current.Column;
            var directive = Current.Value;
            Advance();
            return new PreprocessorDeclaration(directive, line, column);
        }

        var attributes = ParseAttributes();
        var modifiers = ParseModifiers();

        // Nested type declarations
        if (Check(TokenType.Class))
        {
            return ParseClassDeclaration(attributes, modifiers);
        }
        if (Check(TokenType.Struct))
        {
            return ParseStructDeclaration(attributes, modifiers);
        }
        if (Check(TokenType.Record))
        {
            return ParseRecordDeclaration(attributes, modifiers);
        }
        if (Check(TokenType.Enum))
        {
            return ParseEnumDeclaration(attributes, modifiers);
        }
        if (Check(TokenType.Union))
        {
            return ParseUnionDeclaration(attributes, modifiers);
        }
        if (Check(TokenType.Interface))
        {
            return ParseInterfaceDeclaration(attributes, modifiers);
        }

        // Constructor
        if (Check(TokenType.Identifier) && Current.Value == "constructor")
        {
            return ParseConstructorDeclaration(attributes, modifiers);
        }

        // Indexer (must check before Function)
        if (Check(TokenType.Func) && LookAhead(1).Type == TokenType.This)
        {
            return ParseIndexerDeclaration(attributes, modifiers);
        }

        // Function (including conversion operators)
        if (Check(TokenType.Func) || Check(TokenType.Implicit) || Check(TokenType.Explicit))
        {
            return ParseFunctionDeclaration(attributes, modifiers);
        }

        // Field/Property
        return ParseFieldDeclaration(attributes, modifiers);
    }

    private ConstructorDeclaration ParseConstructorDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Identifier, "Expected 'constructor'");

        var parameters = ParseParameterList();

        // Parse optional initializer: `: this(args)` or `: base(args)`
        Expression? initializer = null;
        if (Match(TokenType.Colon))  // Match() advances past colon
        {
            if (Check(TokenType.This))
            {
                var thisLine = Current.Line;
                var thisColumn = Current.Column;
                Advance(); // consume 'this'

                // Parse arguments for this()
                Consume(TokenType.LeftParen, "Expected '(' after 'this'");
                var arguments = ParseArgumentList();  // ParseArgumentList consumes the ')'

                // Create CallExpression with this as callee
                initializer = new CallExpression(
                    new ThisExpression(thisLine, thisColumn),
                    arguments,
                    null,  // No type arguments for constructor calls
                    thisLine,
                    thisColumn);
            }
            else if (Check(TokenType.Base))
            {
                var baseLine = Current.Line;
                var baseColumn = Current.Column;
                Advance(); // consume 'base'

                // Parse arguments for base()
                Consume(TokenType.LeftParen, "Expected '(' after 'base'");
                var arguments = ParseArgumentList();  // ParseArgumentList consumes the ')'

                // Create CallExpression with base as callee
                initializer = new CallExpression(
                    new BaseExpression(baseLine, baseColumn),
                    arguments,
                    null,  // No type arguments for constructor calls
                    baseLine,
                    baseColumn);
            }
            else
            {
                ReportError(
                    ErrorCode.ExpectedToken,
                    $"Expected 'this' or 'base' after ':'. Got '{Current.Value}'",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "In constructor initialization, the colon ':' must be followed by either 'this' (to call another constructor) or 'base' (to call parent constructor).",
                    hint: "Constructor chaining syntax: 'constructor(params) : this(args) { }' or 'constructor(params) : base(args) { }'",
                    suggestions: new List<string> {
                        "Use 'this' to call another constructor in the same class",
                        "Use 'base' to call a parent class constructor"
                    },
                    length: Current.Value.Length
                );
                // Create error placeholder - empty call to this()
                initializer = new CallExpression(
                    new ThisExpression(Current.Line, Current.Column),
                    new List<Argument>(),
                    null,
                    Current.Line,
                    Current.Column
                );
                if (!IsAtEnd()) Advance(); // Skip invalid token
            }
        }

        var body = ParseBlock(new DiagnosticSpan(line, column, Math.Max(1, "constructor".Length)));

        return new ConstructorDeclaration(parameters, body, initializer, modifiers, attributes, line, column);
    }

    private IndexerDeclaration ParseIndexerDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Func, "Expected 'func'");
        Consume(TokenType.This, "Expected 'this'");

        Consume(TokenType.LeftBracket, "Expected '['");
        var parameters = new List<Parameter>();

        if (!Check(TokenType.RightBracket))
        {
            do
            {
                var paramLine = Current.Line;
                var paramColumn = Current.Column;
                var paramName = ConsumeIdentifier("Expected parameter name");
                ConsumeParameterColon(paramName, paramLine, paramColumn);
                var paramType = ParseTypeReference();
                parameters.Add(new Parameter(paramName, paramType, null, false, Line: paramLine, Column: paramColumn));
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightBracket, "Expected ']'");
        Consume(TokenType.Colon, "Expected ':'");
        var returnType = ParseTypeReference();

        Consume(TokenType.LeftBrace, "Expected '{'");

        BlockStatement? getBody = null;
        BlockStatement? setBody = null;

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            var accessorLine = Current.Line;
            var accessorColumn = Current.Column;
            var accessor = ConsumeIdentifier("Expected 'get' or 'set'");
            var accessorSpan = new DiagnosticSpan(accessorLine, accessorColumn, Math.Max(1, accessor.Length));

            if (accessor == "get")
            {
                getBody = ParseBlock(accessorSpan);
            }
            else if (accessor == "set")
            {
                setBody = ParseBlock(accessorSpan);
            }
            else
            {
                ReportError(
                    ErrorCode.ExpectedToken,
                    $"Expected 'get' or 'set' accessor, got '{accessor}'",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "Indexer accessors must be either 'get' (for reading) or 'set' (for writing).",
                    hint: "Use 'get' to define how to retrieve a value, or 'set' to define how to assign a value.",
                    suggestions: new List<string> {
                        "Example: get { return items[i]; }",
                        "Example: set { items[i] = value; }"
                    },
                    length: accessor.Length
                );
                // Skip to next accessor or closing brace
                while (!Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd())
                    Advance();
            }
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new IndexerDeclaration(parameters, returnType, getBody, setBody, modifiers, attributes, line, column);
    }

    private Declaration ParseFieldDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;

        // Parse property modifiers (required, init, readonly) - can be combined
        var propertyModifier = PropertyModifier.None;
        while (Check(TokenType.Required) || Check(TokenType.Init) || Check(TokenType.Readonly))
        {
            if (Check(TokenType.Required))
            {
                propertyModifier |= PropertyModifier.Required;
                modifiers |= Modifiers.Required;  // Also set in Modifiers for backward compat
                Advance();
            }
            else if (Check(TokenType.Init))
            {
                propertyModifier |= PropertyModifier.Init;
                modifiers |= Modifiers.Init;  // Also set in Modifiers for backward compat
                Advance();
            }
            else if (Check(TokenType.Readonly))
            {
                propertyModifier |= PropertyModifier.Readonly;
                modifiers |= Modifiers.Readonly;  // Also set in Modifiers for backward compat
                Advance();
            }
        }

        var name = ConsumeIdentifier("Expected field name");

        // Check for type inference with := syntax
        TypeReference? type = null;
        if (Check(TokenType.ColonAssign))
        {
            // Property with type inference: Name := value
            Advance(); // consume :=
            var initializerExpr = ParseExpression();
            return new FieldDeclaration(name, null, initializerExpr, modifiers, propertyModifier, attributes, line, column);
        }

        // Otherwise, expect explicit type with :
        ConsumeFieldColon(name, line, column);
        type = ParseTypeReference();

        // Check for expression-bodied property: name: type => expr
        if (Check(TokenType.Arrow))
        {
            Advance();
            var expressionBody = ParseExpression();
            return new PropertyDeclaration(name, type, null, null, expressionBody, modifiers, propertyModifier, attributes, line, column);
        }

        // Check if this is a property with get/set
        if (Check(TokenType.LeftBrace))
        {
            Advance(); // consume {

            BlockStatement? getBody = null;
            BlockStatement? setBody = null;

            while (!Check(TokenType.RightBrace) && !IsAtEnd())
            {
                if (Check(TokenType.Identifier))
                {
                    var accessorLine = Current.Line;
                    var accessorColumn = Current.Column;
                    var accessor = Current.Value;
                    Advance();
                    var accessorSpan = new DiagnosticSpan(accessorLine, accessorColumn, Math.Max(1, accessor.Length));

                    if (accessor == "get")
                    {
                        getBody = ParseBlock(accessorSpan);
                    }
                    else if (accessor == "set")
                    {
                        setBody = ParseBlock(accessorSpan);
                    }
                    else
                    {
                        ReportError(
                            ErrorCode.ExpectedToken,
                            $"Expected 'get' or 'set' accessor, got '{accessor}'",
                            Current.Line,
                            Current.Column,
                            humanExplanation: "Property accessors must be either 'get' (for reading) or 'set' (for writing).",
                            hint: "Use 'get' to define how to retrieve the property value, or 'set' to define how to assign a new value.",
                            suggestions: new List<string> {
                                "Example: get { return _value; }",
                                "Example: set { _value = value; }"
                            },
                            length: accessor.Length
                        );
                        // Skip to next accessor or closing brace
                        while (!Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd())
                            Advance();
                    }
                }
                else
                {
                    ReportError(
                        ErrorCode.ExpectedToken,
                        $"Expected 'get' or 'set' accessor. Got '{Current.Value}'",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "Inside property declaration braces, I need to see either 'get' or 'set' accessors.",
                        hint: "Properties define how to get and/or set their values using accessor blocks.",
                        suggestions: new List<string> {
                            "Add a 'get' accessor to make the property readable",
                            "Add a 'set' accessor to make the property writable",
                            "Example: { get { return _value; } set { _value = value; } }"
                        },
                        length: Current.Value.Length
                    );
                    Advance(); // Skip invalid token
                }
            }

            Consume(TokenType.RightBrace, "Expected '}' after property accessors");
            return new PropertyDeclaration(name, type, getBody, setBody, null, modifiers, propertyModifier, attributes, line, column);
        }

        // Otherwise it's a field
        Expression? initializer = null;
        if (Check(TokenType.Assign))
        {
            var initializerToken = Advance();
            initializer = ParseRequiredExpressionAfter(
                initializerToken,
                expectedDescription: "an initializer expression",
                ownerDescription: "This field declaration");
        }

        return new FieldDeclaration(name, type, initializer, modifiers, propertyModifier, attributes, line, column);
    }

    private TypeReference ParseTypeReference()
    {
        return ParseUnionTypeReference();
    }

    private TypeReference ParseUnionTypeReference()
    {
        var first = ParsePostfixTypeReference();
        if (!Check(TokenType.BitwiseOr))
            return first;

        var arms = new List<TypeReference> { first };
        var lastToken = Current;

        while (Check(TokenType.BitwiseOr))
        {
            Advance();
            if (IsTypeTerminator(Current.Type))
            {
                ReportError(
                    ErrorCode.InvalidSyntax,
                    "Expected a type after '|' in anonymous union type",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "Anonymous union types use the form `A | B`, so every `|` must be followed by another type.",
                    hint: "Add the missing type arm, or remove the trailing `|`.",
                    length: Math.Max(1, Current.Value.Length));
                break;
            }

            arms.Add(ParsePostfixTypeReference());
            lastToken = Previous;
        }

        return new UnionTypeReference(arms)
        {
            Span = ExtendSpan(first, lastToken)
        };
    }

    private TypeReference ParsePostfixTypeReference()
    {
        var baseType = ParseBaseTypeReference();

        // Array type
        // Only treat '[' as array if it's followed by ']' (not an attribute)
        while (Check(TokenType.LeftBracket) && LookAhead(1).Type == TokenType.RightBracket)
        {
            Advance();
            var rightBracket = Consume(TokenType.RightBracket, "Expected ']'");
            baseType = new ArrayTypeReference(baseType)
            {
                Span = ExtendSpan(baseType, rightBracket)
            };
        }

        // Nullable type
        if (Check(TokenType.Question))
        {
            var question = Advance();
            baseType = new NullableTypeReference(baseType)
            {
                Span = ExtendSpan(baseType, question)
            };
        }

        return baseType;
    }

    private static bool IsTypeTerminator(TokenType type)
    {
        return type is TokenType.Comma
            or TokenType.RightParen
            or TokenType.RightBracket
            or TokenType.RightBrace
            or TokenType.Newline
            or TokenType.Eof
            or TokenType.Assign
            or TokenType.Semicolon
            or TokenType.Arrow
            or TokenType.Colon;
    }

    private TypeReference ParseBaseTypeReference()
    {
        // Tuple type
        if (Check(TokenType.LeftParen))
        {
            return ParseParenthesizedOrTupleTypeReference();
        }

        // Func<> type
        if (Check(TokenType.Identifier) && Current.Value == "Func")
        {
            return ParseFunctionTypeReference();
        }

        // Simple or generic type (possibly qualified with dots like Result.Success)
        var typeNameToken = Current;
        var typeNameLine = typeNameToken.Line;
        var typeNameColumn = typeNameToken.Column;
        var name = ConsumeIdentifier("Expected type name");
        var lastNameToken = typeNameToken;

        // Support qualified names like Result.Success
        while (Check(TokenType.Dot))
        {
            Advance();
            lastNameToken = Current;
            name += "." + ConsumeIdentifier("Expected identifier after '.'");
        }

        if (Check(TokenType.Less))
        {
            Advance();
            var typeArgs = new List<TypeReference> { ParseTypeReference() };

            while (Match(TokenType.Comma))
            {
                typeArgs.Add(ParseTypeReference());
            }

            var greater = ConsumeGreater("Expected '>'");
            return new GenericTypeReference(name, typeArgs)
            {
                Line = typeNameLine,
                Column = typeNameColumn,
                Span = SpanFromTokens(typeNameToken, greater)
            };
        }

        return new SimpleTypeReference(name, typeNameLine, typeNameColumn)
        {
            Span = SpanFromTokens(typeNameToken, lastNameToken)
        };
    }

    private TypeReference ParseParenthesizedOrTupleTypeReference()
    {
        var leftParen = Consume(TokenType.LeftParen, "Expected '('");
        var elements = new List<TupleTypeElement>();

        do
        {
            string? name = null;

            // Check for named element: (name: type) or (type)
            if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon)
            {
                name = Advance().Value;
                Advance(); // consume colon
            }

            var type = ParseTypeReference();
            elements.Add(new TupleTypeElement(type, name));

        } while (Match(TokenType.Comma));

        var rightParen = Consume(TokenType.RightParen, "Expected ')'");

        if (elements.Count == 1 && elements[0].Name is null)
        {
            return elements[0].Type with
            {
                Span = SpanFromTokens(leftParen, rightParen)
            };
        }

        return new TupleTypeReference(elements)
        {
            Span = SpanFromTokens(leftParen, rightParen)
        };
    }

    private FunctionTypeReference ParseFunctionTypeReference()
    {
        var funcToken = Consume(TokenType.Identifier, "Expected 'Func'");
        Consume(TokenType.Less, "Expected '<'");

        var paramTypes = new List<TypeReference>();
        var returnType = ParseTypeReference();

        while (Match(TokenType.Comma))
        {
            paramTypes.Add(returnType);
            returnType = ParseTypeReference();
        }

        var greater = ConsumeGreater("Expected '>'");

        // Last type is return type, rest are parameters
        return new FunctionTypeReference(paramTypes, returnType)
        {
            Span = SpanFromTokens(funcToken, greater)
        };
    }

    // Check if we're looking at a generic method call (e.g., Method<T>(...))
    // vs a less-than comparison (e.g., x < y)
    private bool IsGenericMethodCall()
    {
        // We're at '<'. Look ahead to see if this could be a type argument list.
        // A generic method call looks like: Method<Type>(...)
        // We need to distinguish from: x < y

        var lookAheadPos = _position + 1;

        // Simple heuristic: if we see an identifier followed by '>' or ',', it's likely a type argument
        // This isn't perfect but should cover most cases
        if (lookAheadPos < _tokens.Count)
        {
            var next = _tokens[lookAheadPos];

            // Must start with identifier (type name)
            if (next.Type != TokenType.Identifier)
                return false;

            lookAheadPos++;

            // Skip potential qualified names, array brackets, and nested generics
            while (lookAheadPos < _tokens.Count)
            {
                var token = _tokens[lookAheadPos];

                if (token.Type == TokenType.Greater)
                {
                    // Found '>' - check if followed by '('
                    lookAheadPos++;
                    return lookAheadPos < _tokens.Count && _tokens[lookAheadPos].Type == TokenType.LeftParen;
                }
                else if (token.Type == TokenType.RightShift)
                {
                    // Found '>>' (nested generics) - check if followed by '('
                    lookAheadPos++;
                    return lookAheadPos < _tokens.Count && _tokens[lookAheadPos].Type == TokenType.LeftParen;
                }
                else if (token.Type == TokenType.Comma)
                {
                    // Multiple type arguments, likely generic
                    return true;
                }
                else if (token.Type == TokenType.Dot || token.Type == TokenType.Less ||
                         token.Type == TokenType.LeftBracket || token.Type == TokenType.Question ||
                         token.Type == TokenType.Identifier || token.Type == TokenType.RightBracket)
                {
                    // Continue scanning (qualified names, nested generics, arrays, nullables)
                    lookAheadPos++;
                }
                else
                {
                    // Something else - not a generic method call
                    return false;
                }
            }
        }

        return false;
    }

    private List<TypeReference> ParseCallTypeArguments()
    {
        Consume(TokenType.Less, "Expected '<'");
        var typeArgs = new List<TypeReference> { ParseTypeReference() };

        while (Match(TokenType.Comma))
        {
            typeArgs.Add(ParseTypeReference());
        }

        ConsumeGreater("Expected '>'");
        return typeArgs;
    }

    // Helper to consume '>' but also handle '>>' (which needs to be split)
    private Token ConsumeGreater(string message)
    {
        if (Check(TokenType.Greater))
        {
            return Advance();
        }
        else if (Check(TokenType.RightShift))
        {
            // Split >> into two > tokens by inserting a virtual > token
            // We consume the >> but pretend we only consumed one >
            var rightShift = Current;
            _position++; // consume the >>

            // Insert a virtual > token at the current position
            // by decrementing position and modifying the current token
            // Actually, we can't modify the token stream, so we'll use a different approach:
            // We'll keep track that we "owe" a > token
            _splitGreaterDepth++;
            return new Token(TokenType.Greater, ">", rightShift.Line, rightShift.Column, rightShift.FileName);
        }
        else
        {
            ReportError(
                ErrorCode.ExpectedToken,
                $"{message}. Got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: "I was parsing generic type parameters and expected to see a closing '>' here.",
                hint: GetHintForMissingToken(TokenType.Greater),
                suggestions: new List<string> {
                    "Check if you have matching '<' and '>' in your generic type declaration",
                    "Example: List<int> or Dictionary<string, int>"
                },
                length: Current.Value.Length
            );
            return Current;
        }
    }

    // Track when we split >> into > >
    private int _splitGreaterDepth = 0;

    private BlockStatement ParseBlock(DiagnosticSpan? ownerSpan = null)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftBrace, "Expected '{'");
        var diagnosticSpan = ownerSpan ?? new DiagnosticSpan(line, column, 1);

        var statements = new List<Statement>();
        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            // Detect a type declaration keyword that can't appear as a statement.
            // This signals a missing closing brace - break out so the caller
            // can return and the next declaration gets parsed.
            if (IsBlockClosingDeclarationStart())
            {
                ReportError(
                    ErrorCode.MissingClosingBrace,
                    "Missing closing '}'",
                    diagnosticSpan.Line,
                    diagnosticSpan.Column,
                    humanExplanation: $"The block that started on line {line} appears to be missing its closing brace. " +
                                     $"I found '{Current.Value}' on line {Current.Line}, which looks like a new declaration.",
                    hint: "Add a '}' before this declaration to close the previous block.",
                    length: diagnosticSpan.Length
                );
                // Don't advance - let the outer loop parse this as a new declaration
                break;
            }

            _panicMode = false; // Reset at each statement boundary
            var startPosition = _position;
            var previousRecoveryBoundaryColumn = _currentRecoveryBoundaryColumn;
            try
            {
                _currentRecoveryBoundaryColumn = Current.Column;
                statements.Add(ParseStatement());
            }
            finally
            {
                _currentRecoveryBoundaryColumn = previousRecoveryBoundaryColumn;
            }

            // If we didn't make progress, synchronize to next statement boundary
            if (_position == startPosition && !IsAtEnd())
            {
                SynchronizeToNextStatement();
                // If synchronization also didn't advance (e.g., stuck on a token that
                // matches a sync point but fails to parse), force-advance
                if (_position == startPosition && !IsAtEnd())
                {
                    Advance();
                }
            }
        }

        // Only consume '}' if present; otherwise report the missing brace
        if (Check(TokenType.RightBrace))
        {
            Advance();
        }
        else if (IsAtEnd())
        {
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                diagnosticSpan.Line,
                diagnosticSpan.Column,
                humanExplanation: $"The block that started on line {line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this block.",
                length: diagnosticSpan.Length
            );
        }

        return new BlockStatement(statements, line, column);
    }

    private Statement ParseStatement(DiagnosticSpan? blockOwnerSpan = null)
    {
        // Optional statement terminator / empty statement
        if (Check(TokenType.Semicolon))
        {
            var line = Current.Line;
            var column = Current.Column;
            Advance(); // consume ';'
            return new EmptyStatement(line, column);
        }

        if (Check(TokenType.Let))
            return ParseVariableDeclaration(VariableKind.Let);
        if (Check(TokenType.Const))
            return ParseVariableDeclaration(VariableKind.Const);
        if (Check(TokenType.Readonly))
            return ParseVariableDeclaration(VariableKind.Readonly);
        if (Check(TokenType.If))
            return ParseIfStatement();
        if (Check(TokenType.For))
            return ParseForStatement();
        if (Check(TokenType.Foreach))
            return ParseForeachStatement();
        // Handle "await foreach" for async iteration (C# 8+)
        if (Check(TokenType.Await) && LookAhead(1).Type == TokenType.Foreach)
            return ParseAwaitForeachStatement();
        if (Check(TokenType.While))
            return ParseWhileStatement();
        if (Check(TokenType.Return))
            return ParseReturnStatement();
        if (Check(TokenType.Yield))
            return ParseYieldStatement();
        if (Check(TokenType.Break))
            return ParseBreakStatement();
        if (Check(TokenType.Continue))
            return ParseContinueStatement();
        if (Check(TokenType.Throw))
            return ParseThrowStatement();
        if (Check(TokenType.Try))
            return ParseTryStatement();
        if (Check(TokenType.Using))
            return ParseUsingStatement();
        if (Check(TokenType.Lock))
            return ParseLockStatement();
        if (Check(TokenType.Switch))
            return ParseSwitchStatement();
        if (Check(TokenType.Print))
            return ParsePrintStatement();
        if (Check(TokenType.Assert))
            return ParseAssertStatement();
        if (Check(TokenType.PreprocessorDirective))
            return ParsePreprocessorDirective();
        if (Check(TokenType.LeftBrace))
            return ParseBlock(blockOwnerSpan);

        // Local function (C# 7): [static] [async] func Name(...) { }
        if ((Check(TokenType.Static) || Check(TokenType.Async)) && LookAhead(1).Type == TokenType.Func)
            return ParseLocalFunction();
        if (Check(TokenType.Static) && LookAhead(1).Type == TokenType.Async && LookAhead(2).Type == TokenType.Func)
            return ParseLocalFunction();
        if (Check(TokenType.Func))
            return ParseLocalFunction();

        // Expression statement (or shorthand declaration with :=)
        return ParseExpressionStatement();
    }

    private Statement ParseAssertStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var assertToken = Consume(TokenType.Assert, "Expected 'assert'");

        // Check for assert throws ExceptionType { body }
        if (Current.Type == TokenType.Identifier && Current.Value == "throws")
        {
            Advance(); // consume 'throws'
            var exceptionType = ParseTypeReference();
            var body = ParseBlock(DiagnosticSpanFromToken(assertToken));
            return new AssertThrowsStatement(exceptionType, body, line, column);
        }

        var condition = ParseRequiredExpressionAfter(
            assertToken,
            expectedDescription: "a condition expression",
            ownerDescription: "This assert statement");

        // Check for optional message: assert condition, "message"
        Expression? message = null;
        if (Check(TokenType.Comma))
        {
            Advance(); // consume ','
            message = ParseExpression();
        }

        return new AssertStatement(condition, message, line, column);
    }

    private LocalFunctionStatement ParseLocalFunction()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Handle optional 'static' and 'async' modifiers for local functions
        Modifiers modifiers = Modifiers.None;
        var scanningModifiers = true;
        while (scanningModifiers)
        {
            if (Check(TokenType.Static))
            {
                modifiers |= Modifiers.Static;
                Advance();
            }
            else if (Check(TokenType.Async))
            {
                modifiers |= Modifiers.Async;
                Advance();
            }
            else
            {
                scanningModifiers = false;
            }
        }

        Consume(TokenType.Func, "Expected 'func'");

        // Check for generator: func*
        if (Check(TokenType.Star))
        {
            modifiers |= Modifiers.Generator;
            Advance();
        }

        // Compatibility: accept legacy postfix async (`func async` / `func async*`) for local functions.
        if (Check(TokenType.Async))
        {
            modifiers |= Modifiers.Async;
            Advance();

            // Compatibility: accept legacy postfix async iterator `func async*`.
            if (Check(TokenType.Star))
            {
                modifiers |= Modifiers.Generator;
                Advance();
            }
        }

        var nameLine = Current.Line;
        var nameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected function name");
        var typeParams = ParseTypeParameters();
        var parameters = ParseParameterList();

        TypeReference? returnType = null;
        var parameterListEndToken = Previous;
        if (Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater))
        {
            if (Check(TokenType.Colon))
            {
                Advance();
            }
            else
            {
                Advance(); // consume '-'
                Consume(TokenType.Greater, "Expected '>' after '-' in return type arrow");
            }
            returnType = ParseTypeReference();
        }
        else if (IsLikelyMissingReturnTypeMarker(parameterListEndToken))
        {
            ReportMissingReturnTypeMarker(
                name == "<error>" ? "local function" : name,
                name == "<error>" ? line : nameLine,
                name == "<error>" ? column : nameColumn,
                name == "<error>" ? Math.Max(1, "func".Length) : Math.Max(1, name.Length));
            returnType = ParseTypeReference();
        }

        var constraints = ParseGenericConstraints();

        BlockStatement? body = null;
        Expression? expressionBody = null;

        if (Check(TokenType.Arrow))  // Expression-bodied local function
        {
            Advance();
            expressionBody = ParseExpression();
        }
        else if (Check(TokenType.LeftBrace))
        {
            body = ParseBlock(name == "<error>"
                ? new DiagnosticSpan(line, column, Math.Max(1, "func".Length))
                : new DiagnosticSpan(nameLine, nameColumn, Math.Max(1, name.Length)));
        }
        else
        {
            ReportError(
                ErrorCode.ExpectedToken,
                $"Expected function body or '=>' for expression-bodied function. Got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: "A function needs a body - either a block with braces { } or an expression after '=>'.",
                hint: "Use '{ ... }' for a block body or '=> expression' for a single expression.",
                suggestions: new List<string> {
                    "Add a block: { return value; }",
                    "Use arrow syntax: => value",
                    "Example: func add(x: int, y: int): int => x + y"
                },
                length: Current.Value.Length
            );
            // Create empty block as placeholder
            body = new BlockStatement(new List<Statement>(), Current.Line, Current.Column);
        }

        var functionDecl = new FunctionDeclaration(name, parameters, returnType, body, expressionBody,
            typeParams, constraints, modifiers, new List<AttributeNode>(), false, null, false, false, line, column);

        return new LocalFunctionStatement(functionDecl, line, column);
    }

    private Statement ParseVariableDeclaration(VariableKind kind)
    {
        Advance(); // consume let/const/readonly

        // Check if this is a tuple deconstruction: (x, y) := ...
        if (Check(TokenType.LeftParen))
        {
            // For tuple deconstruction, use the paren position
            var tupleVarLine = Current.Line;
            var tupleVarColumn = Current.Column;
            return ParseTupleDeconstruction(kind, tupleVarLine, tupleVarColumn);
        }

        // Capture the identifier's position (for diagnostics)
        var line = Current.Line;
        var column = Current.Column;
        var name = ConsumeIdentifier("Expected variable name");

        TypeReference? type = null;
        if (Check(TokenType.Colon))
        {
            Advance();
            type = ParseTypeReference();
        }

        Expression? initializer = null;
        if (Check(TokenType.Assign) || Check(TokenType.ColonAssign))
        {
            var initializerToken = Advance();
            initializer = ParseRequiredExpressionAfter(
                initializerToken,
                expectedDescription: "an initializer expression",
                ownerDescription: "This variable declaration");
        }

        return new VariableDeclarationStatement(name, type, initializer, kind, line, column);
    }

    private TupleDeconstructionStatement ParseTupleDeconstruction(VariableKind kind, int line, int column)
    {
        Consume(TokenType.LeftParen, "Expected '('");

        var names = new List<string>();
        do
        {
            var name = ConsumeIdentifier("Expected identifier or '_'");
            names.Add(name);
        } while (Match(TokenType.Comma));

        Consume(TokenType.RightParen, "Expected ')'");

        // Only support := for tuple deconstruction (not = or :)
        if (!Check(TokenType.ColonAssign) && !Check(TokenType.Assign))
        {
            ReportError(
                ErrorCode.ExpectedToken,
                $"Tuple deconstruction requires ':=' or '='. Got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: "To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list.",
                hint: "Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()",
                suggestions: new List<string> {
                    "Add ':=' for new variables: (x, y) := (1, 2)",
                    "Add '=' for existing variables: (x, y) = tuple",
                    "Example: (name, age) := getPerson()"
                },
                length: Current.Value.Length
            );
            // Try to skip current invalid token
            if (!IsAtEnd())
            {
                Advance();
            }
        }

        Token initializerToken;
        if (Check(TokenType.ColonAssign) || Check(TokenType.Assign))
        {
            initializerToken = Advance(); // consume := or =
        }
        else
        {
            initializerToken = Previous;
        }

        var initializer = ParseRequiredExpressionAfter(
            initializerToken,
            expectedDescription: "an initializer expression",
            ownerDescription: "This tuple deconstruction");

        return new TupleDeconstructionStatement(names, initializer, kind, line, column);
    }

    private IfStatement ParseIfStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var ifToken = Consume(TokenType.If, "Expected 'if'");

        var condition = ParseRequiredExpressionAfter(
            ifToken,
            expectedDescription: "a condition expression",
            ownerDescription: "This if statement");
        var thenStatement = ParseStatement(DiagnosticSpanFromToken(ifToken));

        Statement? elseStatement = null;
        if (Check(TokenType.Else))
        {
            var elseToken = Advance();
            elseStatement = ParseStatement(DiagnosticSpanFromToken(elseToken));
        }

        return new IfStatement(condition, thenStatement, elseStatement, line, column);
    }

    private ForStatement ParseForStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var forToken = Consume(TokenType.For, "Expected 'for'");

        // Check for foreach-style: for item in collection
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.In)
        {
            var varName = Advance().Value;
            var inToken = Consume(TokenType.In, "Expected 'in'");
            var collection = ParseRequiredExpressionAfter(
                inToken,
                expectedDescription: "a collection expression",
                ownerDescription: "This for-in statement");
            var body = ParseStatement(DiagnosticSpanFromToken(forToken));
            return new ForStatement(null, null, null,
                new ForeachStatement(varName, collection, body, line, column), line, column);
        }

        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier)
        {
            var variableToken = Advance();
            var inToken = ReportMissingInKeywordAndRecover(forToken, variableToken, "This for-in statement");
            var collection = ParseRequiredExpressionAfter(
                inToken,
                expectedDescription: "a collection expression",
                ownerDescription: "This for-in statement");
            var body = ParseStatement(DiagnosticSpanFromToken(forToken));
            return new ForStatement(null, null, null,
                new ForeachStatement(variableToken.Value, collection, body, line, column), line, column);
        }

        // C-style for loop
        var hasParens = false;
        if (Check(TokenType.LeftParen))
        {
            hasParens = true;
            Advance(); // consume '('
        }

        Statement? initializer = null;
        if (!Check(TokenType.Semicolon))
        {
            if (Check(TokenType.Let))
            {
                initializer = ParseVariableDeclaration(VariableKind.Let);
            }
            else
            {
                // This will handle both regular expressions and := shorthand declarations
                var expr = ParseExpression();

                // Check for := shorthand declaration
                if (expr is IdentifierExpression ident && Check(TokenType.ColonAssign))
                {
                    var initializerToken = Advance();
                    var init = ParseRequiredExpressionAfter(
                        initializerToken,
                        expectedDescription: "an initializer expression",
                        ownerDescription: "This for-loop initializer");
                    initializer = new VariableDeclarationStatement(ident.Name, null, init, VariableKind.Let, ident.Line, ident.Column);
                }
                else
                {
                    initializer = new ExpressionStatement(expr, expr.Line, expr.Column);
                }
            }
        }

        Consume(TokenType.Semicolon, "Expected ';'");

        Expression? condition = null;
        if (!Check(TokenType.Semicolon))
        {
            condition = ParseExpression();
        }

        Consume(TokenType.Semicolon, "Expected ';'");

        Expression? iterator = null;
        if (hasParens ? !Check(TokenType.RightParen) : !Check(TokenType.LeftBrace))
        {
            iterator = ParseExpression();
        }

        if (hasParens)
        {
            Consume(TokenType.RightParen, "Expected ')'");
        }

        var forBody = ParseStatement(DiagnosticSpanFromToken(forToken));

        return new ForStatement(initializer, condition, iterator, forBody, line, column);
    }

    private ForeachStatement ParseForeachStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var foreachToken = Consume(TokenType.Foreach, "Expected 'foreach'");

        // Allow optional parentheses: foreach (x in y) or foreach x in y
        var hasParens = Match(TokenType.LeftParen);

        var variableToken = Current;
        var varName = ConsumeIdentifier("Expected variable name");
        var inToken = Check(TokenType.In)
            ? Consume(TokenType.In, "Expected 'in'")
            : ReportMissingInKeywordAndRecover(foreachToken, variableToken, "This foreach statement");
        var collection = ParseRequiredExpressionAfter(
            inToken,
            expectedDescription: "a collection expression",
            ownerDescription: "This foreach statement");

        if (hasParens)
        {
            Consume(TokenType.RightParen, "Expected ')' to match opening '('");
        }

        var body = ParseStatement(DiagnosticSpanFromToken(foreachToken));

        return new ForeachStatement(varName, collection, body, line, column);
    }

    private AwaitForEachStatement ParseAwaitForeachStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Await, "Expected 'await'");
        var foreachToken = Consume(TokenType.Foreach, "Expected 'foreach'");

        // Allow optional parentheses: await foreach (x in y) or await foreach x in y
        var hasParens = Match(TokenType.LeftParen);

        var variableToken = Current;
        var varName = ConsumeIdentifier("Expected variable name");
        var inToken = Check(TokenType.In)
            ? Consume(TokenType.In, "Expected 'in'")
            : ReportMissingInKeywordAndRecover(foreachToken, variableToken, "This await foreach statement");
        var collection = ParseRequiredExpressionAfter(
            inToken,
            expectedDescription: "a collection expression",
            ownerDescription: "This await foreach statement");

        if (hasParens)
        {
            Consume(TokenType.RightParen, "Expected ')' to match opening '('");
        }

        var body = ParseStatement(DiagnosticSpanFromToken(foreachToken));

        return new AwaitForEachStatement(varName, collection, body, line, column);
    }

    private WhileStatement ParseWhileStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var whileToken = Consume(TokenType.While, "Expected 'while'");

        var condition = ParseRequiredExpressionAfter(
            whileToken,
            expectedDescription: "a condition expression",
            ownerDescription: "This while statement");
        var body = ParseStatement(DiagnosticSpanFromToken(whileToken));

        return new WhileStatement(condition, body, line, column);
    }

    private ReturnStatement ParseReturnStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Return, "Expected 'return'");

        Expression? value = null;
        if (!Check(TokenType.RightBrace) && !IsAtEnd() && CanStartExpression(Current.Type))
        {
            value = ParseExpression();
        }

        return new ReturnStatement(value, line, column);
    }

    private static bool CanStartExpression(TokenType type) =>
        type is
            TokenType.Identifier or
            TokenType.IntLiteral or
            TokenType.FloatLiteral or
            TokenType.CharLiteral or
            TokenType.StringLiteral or
            TokenType.InterpolatedRawStringLiteral or
            TokenType.True or
            TokenType.False or
            TokenType.Null or
            TokenType.New or
            TokenType.Match or
            TokenType.This or
            TokenType.Base or
            TokenType.LeftParen or
            TokenType.LeftBracket or
            TokenType.Immutable or
            TokenType.DotDotDot or
            // Unary operators / keywords that start expressions
            TokenType.Plus or
            TokenType.Minus or
            TokenType.Not or
            TokenType.BitwiseNot or
            TokenType.Increment or
            TokenType.Decrement or
            TokenType.Must or
            TokenType.Await or
            TokenType.Throw or
            // Keywords that are also expressions
            TokenType.Checked or
            TokenType.Unchecked or
            TokenType.Typeof or
            TokenType.Nameof or
            TokenType.Sizeof or
            TokenType.Default;

    private YieldStatement ParseYieldStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var yieldToken = Consume(TokenType.Yield, "Expected 'yield'");

        // Check for "yield break" (no expression)
        Expression? value = null;
        if (!Check(TokenType.Break))
        {
            value = ParseRequiredExpressionAfter(
                yieldToken,
                expectedDescription: "a value to yield",
                ownerDescription: "This yield statement");
        }
        else
        {
            Advance(); // consume 'break'
        }

        return new YieldStatement(value, line, column);
    }

    private PrintStatement ParsePrintStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var printToken = Consume(TokenType.Print, "Expected 'print'");

        var value = ParseRequiredExpressionAfter(
            printToken,
            expectedDescription: "an expression to print",
            ownerDescription: "This print statement");
        return new PrintStatement(value, line, column);
    }

    private PreprocessorDirective ParsePreprocessorDirective()
    {
        var line = Current.Line;
        var column = Current.Column;
        var directive = Current.Value;
        Consume(TokenType.PreprocessorDirective, "Expected preprocessor directive");

        return new PreprocessorDirective(directive, line, column);
    }

    private BreakStatement ParseBreakStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Break, "Expected 'break'");
        return new BreakStatement(line, column);
    }

    private ContinueStatement ParseContinueStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Continue, "Expected 'continue'");
        return new ContinueStatement(line, column);
    }

    private ThrowStatement ParseThrowStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var throwToken = Consume(TokenType.Throw, "Expected 'throw'");

        var expr = ParseRequiredExpressionAfter(
            throwToken,
            expectedDescription: "an exception expression",
            ownerDescription: "This throw statement");
        return new ThrowStatement(expr, line, column);
    }

    private TryStatement ParseTryStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var tryToken = Consume(TokenType.Try, "Expected 'try'");

        var tryBlock = ParseBlock(DiagnosticSpanFromToken(tryToken));
        var catchClauses = new List<CatchClause>();

        while (Check(TokenType.Catch))
        {
            var catchToken = Advance();

            TypeReference? exceptionType = null;
            string? varName = null;

            if (Check(TokenType.LeftParen))
            {
                Advance();
                if (!Check(TokenType.RightParen))
                {
                    if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon)
                    {
                        varName = Advance().Value;
                        Advance(); // consume ':'
                        exceptionType = ParseTypeReference();
                    }
                    else
                    {
                        exceptionType = ParseTypeReference();

                        if (Check(TokenType.Identifier))
                        {
                            varName = Advance().Value;
                        }
                    }
                }
                Consume(TokenType.RightParen, "Expected ')'");
            }
            else if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon)
            {
                varName = Advance().Value;
                Advance(); // consume ':'
                exceptionType = ParseTypeReference();
            }

            var catchBlock = ParseBlock(DiagnosticSpanFromToken(catchToken));
            catchClauses.Add(new CatchClause(exceptionType, varName, catchBlock));
        }

        BlockStatement? finallyBlock = null;
        if (Check(TokenType.Finally))
        {
            var finallyToken = Advance();
            finallyBlock = ParseBlock(DiagnosticSpanFromToken(finallyToken));
        }

        return new TryStatement(tryBlock, catchClauses, finallyBlock, line, column);
    }

    private UsingStatement ParseUsingStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var usingToken = Consume(TokenType.Using, "Expected 'using'");

        // using varName := expr { ... } or using varName := expr (no block)
        if (Check(TokenType.Identifier) || Check(TokenType.Let))
        {
            VariableDeclarationStatement? decl = null;

            if (Check(TokenType.Let))
            {
                var stmt = ParseVariableDeclaration(VariableKind.Let);
                decl = stmt as VariableDeclarationStatement;
                if (decl == null)
                {
                    ReportError(
                        ErrorCode.InvalidSyntax,
                        "Using statement requires a variable declaration, not tuple deconstruction",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "The 'using' statement can only work with single variable declarations, not tuple deconstruction.",
                        hint: "Use a single variable: using let resource := getResource() { ... }",
                        suggestions: new List<string> {
                            "Change from tuple deconstruction to single variable",
                            "Example: using let file := File.Open(path) { ... }",
                            "Note: The variable will be automatically disposed when the block ends"
                        },
                        length: 1
                    );
                    // Create placeholder declaration
                    decl = new VariableDeclarationStatement("<error>", null, null, VariableKind.Let, line, column);
                }
            }
            else
            {
                var varName = ConsumeIdentifier("Expected variable name");
                var initializerToken = Consume(TokenType.ColonAssign, "Expected ':='");
                var init = ParseRequiredExpressionAfter(
                    initializerToken,
                    expectedDescription: "an initializer expression",
                    ownerDescription: "This using declaration");
                decl = new VariableDeclarationStatement(varName, null, init, VariableKind.Let, line, column);
            }

            Statement? body = null;
            if (Check(TokenType.LeftBrace))
            {
                body = ParseBlock(DiagnosticSpanFromToken(usingToken));
            }

            return new UsingStatement(decl, null, body, line, column);
        }

        // using (expr) or using expr
        var expr = ParseRequiredExpressionAfter(
            usingToken,
            expectedDescription: "a resource expression",
            ownerDescription: "This using statement");
        Statement? usingBody = null;

        if (Check(TokenType.LeftBrace))
        {
            usingBody = ParseBlock(DiagnosticSpanFromToken(usingToken));
        }

        return new UsingStatement(null, expr, usingBody, line, column);
    }

    private LockStatement ParseLockStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var lockToken = Consume(TokenType.Lock, "Expected 'lock'");

        // lock obj { ... } or lock (obj) { ... }
        var hasParens = Check(TokenType.LeftParen);
        var expressionAnchor = lockToken;
        if (hasParens)
            expressionAnchor = Consume(TokenType.LeftParen, "Expected '('");

        var lockObject = ParseRequiredExpressionAfter(
            expressionAnchor,
            expectedDescription: "an object expression",
            ownerDescription: "This lock statement");

        if (hasParens)
            Consume(TokenType.RightParen, "Expected ')'");

        var bodyStmt = ParseBlock(DiagnosticSpanFromToken(lockToken)) as BlockStatement;
        if (bodyStmt == null)
        {
            ReportError(
                ErrorCode.InvalidSyntax,
                "Expected block statement after lock",
                Current.Line,
                Current.Column,
                humanExplanation: "A 'lock' statement must be followed by a block of code in braces { }.",
                hint: "The lock body contains the code that runs with exclusive access to the lock object.",
                suggestions: new List<string> {
                    "Add a block: lock (myObject) { /* code */ }",
                    "The code inside will execute with a lock on the specified object"
                },
                length: 1
            );
            bodyStmt = new BlockStatement(new List<Statement>(), Current.Line, Current.Column);
        }

        return new LockStatement(lockObject, bodyStmt, line, column);
    }

    private SwitchStatement ParseSwitchStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        var switchToken = Consume(TokenType.Switch, "Expected 'switch'");

        var value = ParseRequiredExpressionAfter(
            switchToken,
            expectedDescription: "a value expression",
            ownerDescription: "This switch statement");
        Consume(TokenType.LeftBrace, "Expected '{'");

        var cases = new List<SwitchCase>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            Pattern? pattern = null;
            var caseLine = Current.Line;
            var caseColumn = Current.Column;
            var caseDiagnosticSpan = new DiagnosticSpan(caseLine, caseColumn, Math.Max(1, Current.Value.Length));

            if (Check(TokenType.Case))
            {
                Advance();
                pattern = ParsePattern();
            }
            else if (Check(TokenType.Default))
            {
                Advance();
                pattern = null;
            }
            else
            {
                ReportError(
                    ErrorCode.ExpectedToken,
                    $"Expected 'case' or 'default'. Got '{Current.Value}'",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "Switch statements must contain 'case' patterns or a 'default' case.",
                    hint: "Each branch in a switch must start with 'case pattern =>' or 'default =>'",
                    suggestions: new List<string> {
                        "Add a case: case 1 => { ... }",
                        "Add a default: default => { ... }",
                        "Example: case > 0 => Console.WriteLine(\"positive\")"
                    },
                    length: Current.Value.Length
                );
                // Skip to next reasonable token
                while (!Check(TokenType.RightBrace) && !Check(TokenType.Case) && !Check(TokenType.Default) && !IsAtEnd())
                    Advance();
                // Create a placeholder case to continue parsing
                if (Check(TokenType.RightBrace))
                    break;
                continue;
            }

            Consume(TokenType.Arrow, "Expected '=>'");

            var statements = new List<Statement>();
            if (Check(TokenType.LeftBrace))
            {
                var block = ParseBlock(caseDiagnosticSpan);
                statements.AddRange(block.Statements);
            }
            else
            {
                statements.Add(ParseStatement());
            }

            cases.Add(new SwitchCase(pattern, statements, caseLine, caseColumn));
        }

        if (Check(TokenType.RightBrace))
        {
            Advance();
        }
        else
        {
            var switchSpan = DiagnosticSpanFromToken(switchToken);
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                switchSpan.Line,
                switchSpan.Column,
                humanExplanation: $"The switch body that started on line {line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this switch statement.",
                length: switchSpan.Length
            );
        }

        return new SwitchStatement(value, cases, line, column);
    }

    private Pattern ParsePattern()
    {
        // Parse with operator precedence: or > and > not > relational > primary
        return ParseOrPattern();
    }

    private Pattern ParseOrPattern()
    {
        var left = ParseAndPattern();

        while (Check(TokenType.OrKeyword))
        {
            var line = Current.Line;
            var column = Current.Column;
            Advance(); // consume 'or'
            var right = ParseAndPattern();
            left = new OrPattern(left, right, line, column);
        }

        return left;
    }

    private Pattern ParseAndPattern()
    {
        var left = ParseNotPattern();

        while (Check(TokenType.AndKeyword))
        {
            var line = Current.Line;
            var column = Current.Column;
            Advance(); // consume 'and'
            var right = ParseNotPattern();
            left = new AndPattern(left, right, line, column);
        }

        return left;
    }

    private Pattern ParseNotPattern()
    {
        if (Check(TokenType.NotKeyword))
        {
            var line = Current.Line;
            var column = Current.Column;
            Advance(); // consume 'not'
            var pattern = ParseNotPattern(); // recursive for multiple nots
            return new NotPattern(pattern, line, column);
        }

        return ParseRelationalPattern();
    }

    private Pattern ParseRelationalPattern()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Check for relational operators (<, >, <=, >=, ==, !=)
        if (Check(TokenType.Less) || Check(TokenType.Greater) ||
            Check(TokenType.LessEqual) || Check(TokenType.GreaterEqual) ||
            Check(TokenType.Equal) || Check(TokenType.NotEqual))
        {
            var op = Advance().Value;
            // Parse only primary expressions (literals, identifiers, parenthesized expressions)
            // NOT relational expressions, to avoid consuming the next pattern's operators
            var value = ParsePrimaryExpression();
            return new RelationalPattern(op, value, line, column);
        }

        return ParsePrimaryPattern();
    }

    private Pattern ParsePrimaryPattern()
    {
        var line = Current.Line;
        var column = Current.Column;

        // List pattern: [pattern1, pattern2, .., pattern3]
        if (Check(TokenType.LeftBracket))
        {
            Advance(); // consume '['
            var patterns = new List<Pattern>();

            if (!Check(TokenType.RightBracket))
            {
                do
                {
                    // Check for slice pattern: .. or .. var name
                    if (Check(TokenType.DotDot))
                    {
                        Advance(); // consume '..'
                        string? bindingName = null;

                        // Check for variable binding: .. var name or .. name
                        if (Check(TokenType.Identifier))
                        {
                            bindingName = Advance().Value;
                        }

                        patterns.Add(new SlicePattern(bindingName, line, column));
                    }
                    else
                    {
                        patterns.Add(ParsePattern());
                    }
                } while (Match(TokenType.Comma));
            }

            Consume(TokenType.RightBracket, "Expected ']' after list pattern");
            return new ListPattern(patterns, line, column);
        }

        // Positional pattern (tuple pattern): (pattern1, pattern2, ...)
        if (Check(TokenType.LeftParen))
        {
            Advance(); // consume '('
            var patterns = new List<Pattern>();

            if (!Check(TokenType.RightParen))
            {
                do
                {
                    patterns.Add(ParsePattern());
                } while (Match(TokenType.Comma));
            }

            Consume(TokenType.RightParen, "Expected ')' after positional pattern");
            return new PositionalPattern(patterns, line, column);
        }

        // Literal pattern
        if (Check(TokenType.IntLiteral) || Check(TokenType.CharLiteral) || Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) ||
            Check(TokenType.True) || Check(TokenType.False) || Check(TokenType.Null))
        {
            var literal = ParsePrimaryExpression();
            return new LiteralPattern(literal, line, column);
        }

        // Object pattern without type name: { Prop: pattern, ... }
        if (Check(TokenType.LeftBrace))
        {
            var props = ParsePropertyPatterns();
            return new ObjectPattern(props, line, column);
        }

        // Union case, type pattern, or identifier pattern
        if (Check(TokenType.Identifier))
        {
            var name = Advance().Value;

            // Handle qualified names (e.g., Result.Success, System.String)
            while (Check(TokenType.Dot))
            {
                Advance();
                name += "." + ConsumeIdentifier("Expected identifier after '.'");
            }

            // Union case pattern with properties
            if (Check(TokenType.LeftBrace))
            {
                var props = ParsePropertyPatterns();
                return new UnionCasePattern(name, props, line, column);
            }

            // Type pattern: TypeName variableName
            // If followed by identifier, this is a type pattern
            if (Check(TokenType.Identifier))
            {
                var bindingName = Advance().Value;
                var typeRef = new SimpleTypeReference(name);
                return new TypePattern(typeRef, bindingName, line, column);
            }

            // Simple identifier pattern (just a variable binding)
            return new IdentifierPattern(name, line, column);
        }

        ReportError(
            ErrorCode.InvalidSyntax,
            $"Invalid pattern. Got '{Current.Value}'",
            line,
            column,
            humanExplanation: "I couldn't recognize this as a valid pattern for matching.",
            hint: "Patterns can be literals, identifiers, types, or destructuring patterns.",
            suggestions: new List<string> {
                "Literal pattern: case 5 => ...",
                "Identifier pattern: case x => ...",
                "Type pattern: case int x => ...",
                "Object pattern: case { Name: \"John\" } => ..."
            },
            length: Current.Value.Length
        );
        // Return error placeholder pattern
        return new IdentifierPattern("<error>", line, column);
    }

    private List<PropertyPattern> ParsePropertyPatterns()
    {
        Consume(TokenType.LeftBrace, "Expected '{'");
        var props = new List<PropertyPattern>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            var startPosition = _position;
            var propToken = Current;
            var propName = ConsumeIdentifier("Expected property name");

            // Check for colon to distinguish pattern vs simple binding
            // { Name: "John" } -> pattern is literal
            // { Name: name } -> pattern is identifier (explicit binding)
            // { Name: { City: "NYC" } } -> pattern is nested object
            // { Name } -> simple binding (BindingName = null, uses Name)
            if (Check(TokenType.Colon))
            {
                Advance(); // consume ':'
                var pattern = ParsePattern();
                props.Add(new PropertyPattern(propName, pattern, null, propToken.Line, propToken.Column));
            }
            else
            {
                // Just property name, implicit binding: { value } -> bind property 'value' to variable 'value'
                // BindingName is null, Analyzer will use Name as binding
                props.Add(new PropertyPattern(propName, null, null, propToken.Line, propToken.Column));
            }

            if (!Check(TokenType.RightBrace))
                Match(TokenType.Comma);

            EnsureProgress(startPosition);
        }

        Consume(TokenType.RightBrace, "Expected '}'");
        return props;
    }

    private Statement ParseExpressionStatement()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Typed variable declaration without `let` (common in tests):
        //   name: string = "John"
        //   numbers: int[] = [1, 2, 3]
        //   optional: string? = null
        if (Check(TokenType.Identifier) &&
            LookAhead(1).Type == TokenType.Colon &&
            LookAhead(2).Type == TokenType.Identifier)
        {
            var saved = _position;
            var name = Advance().Value;
            Advance(); // consume ':'
            var typeRef = ParseTypeReference();

            if (Check(TokenType.Assign))
            {
                Advance(); // consume '='
                var initializer = ParseRequiredExpressionAfter(
                    Previous,
                    expectedDescription: "an initializer expression",
                    ownerDescription: "This typed variable declaration");
                return new VariableDeclarationStatement(name, typeRef, initializer, VariableKind.Let, line, column);
            }

            // Not a declaration; rewind and parse as a normal expression statement.
            _position = saved;
        }

        // Check for tuple deconstruction without parens: x, y := expr
        // This handles cases like: result, err := MightFail()
        if (Check(TokenType.Identifier) && _position + 1 < _tokens.Count &&
            _tokens[_position + 1].Type == TokenType.Comma)
        {
            // Look ahead to find := or =
            int pos = 1;
            bool isTupleDeconstruction = false;

            while (_position + pos < _tokens.Count)
            {
                var token = _tokens[_position + pos];
                if (token.Type == TokenType.ColonAssign || token.Type == TokenType.Assign)
                {
                    isTupleDeconstruction = true;
                    break;
                }
                // Continue only if we see identifier or comma
                if (token.Type != TokenType.Identifier && token.Type != TokenType.Comma)
                {
                    break;
                }
                pos++;
            }

            if (isTupleDeconstruction)
            {
                // Parse the tuple deconstruction without parens
                var names = new List<string>();
                do
                {
                    var name = ConsumeIdentifier("Expected identifier or '_'");
                    names.Add(name);
                } while (Match(TokenType.Comma));

                var initializerToken = Advance(); // consume := or =
                var initializer = ParseRequiredExpressionAfter(
                    initializerToken,
                    expectedDescription: "an initializer expression",
                    ownerDescription: "This tuple deconstruction");
                return new TupleDeconstructionStatement(names, initializer, VariableKind.Let, line, column);
            }
        }

        // Check for tuple deconstruction shorthand: (x, y) := expr
        // Simple heuristic: (identifier, ... matches tuple deconstruction pattern
        if (Check(TokenType.LeftParen) && _position + 1 < _tokens.Count &&
            _tokens[_position + 1].Type == TokenType.Identifier &&
            _position + 2 < _tokens.Count && _tokens[_position + 2].Type == TokenType.Comma)
        {
            // Look ahead to find the matching ) and check for :=
            int parenDepth = 1;
            int pos = 1;
            bool isTupleDeconstruction = false;

            while (_position + pos < _tokens.Count)
            {
                var token = _tokens[_position + pos];
                if (token.Type == TokenType.LeftParen)
                    parenDepth++;
                else if (token.Type == TokenType.RightParen)
                {
                    parenDepth--;
                    if (parenDepth == 0)
                    {
                        // Check if next token is := or =
                        if (_position + pos + 1 < _tokens.Count)
                        {
                            var next = _tokens[_position + pos + 1];
                            if (next.Type == TokenType.ColonAssign || next.Type == TokenType.Assign)
                            {
                                isTupleDeconstruction = true;
                            }
                        }
                        break;
                    }
                }
                pos++;
            }

            if (isTupleDeconstruction)
            {
                return ParseTupleDeconstruction(VariableKind.Let, line, column);
            }
        }

        var expr = ParseExpression();

        // Check for := shorthand declaration
        if (expr is IdentifierExpression ident && Check(TokenType.ColonAssign))
        {
            var initializerToken = Advance();
            var initializer = ParseRequiredExpressionAfter(
                initializerToken,
                expectedDescription: "an initializer expression",
                ownerDescription: "This shorthand variable declaration");
            return new VariableDeclarationStatement(ident.Name, null, initializer, VariableKind.Let, ident.Line, ident.Column);
        }

        return new ExpressionStatement(expr, line, column);
    }

    // Expression parsing with precedence climbing
    private Expression ParseExpression()
    {
        return ParseLambdaOrAssignmentExpression();
    }

    private Expression ParseLambdaOrAssignmentExpression()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Single parameter lambda: x => expr
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Arrow)
        {
            var paramLine = Current.Line;
            var paramColumn = Current.Column;
            var param = Advance().Value;
            Advance(); // consume =>

            if (Check(TokenType.LeftBrace))
            {
                var body = ParseBlock(new DiagnosticSpan(paramLine, paramColumn, Math.Max(1, param.Length)));
                return new LambdaExpression(
                    new List<Parameter> { new Parameter(param, new SimpleTypeReference("var"), null, false, Line: paramLine, Column: paramColumn) },
                    null, body, line, column);
            }
            else
            {
                var exprBody = ParseExpression();
                return new LambdaExpression(
                    new List<Parameter> { new Parameter(param, new SimpleTypeReference("var"), null, false, Line: paramLine, Column: paramColumn) },
                    exprBody, null, line, column);
            }
        }

        // Multi-parameter lambda: (x, y) => expr
        if (Check(TokenType.LeftParen) && IsLambdaExpression())
        {
            return ParseMultiParameterLambda();
        }

        return ParseAssignmentExpression();
    }

    private Expression ParseAssignmentExpression()
    {
        var expr = ParseTernaryExpression();

        if (Check(TokenType.Assign) || Check(TokenType.PlusAssign) || Check(TokenType.MinusAssign) ||
            Check(TokenType.StarAssign) || Check(TokenType.SlashAssign) || Check(TokenType.QuestionQuestionAssign))
        {
            AssignmentOperator op;
            switch (Current.Type)
            {
                case TokenType.Assign:
                    op = AssignmentOperator.Assign;
                    break;
                case TokenType.PlusAssign:
                    op = AssignmentOperator.AddAssign;
                    break;
                case TokenType.MinusAssign:
                    op = AssignmentOperator.SubtractAssign;
                    break;
                case TokenType.StarAssign:
                    op = AssignmentOperator.MultiplyAssign;
                    break;
                case TokenType.SlashAssign:
                    op = AssignmentOperator.DivideAssign;
                    break;
                case TokenType.QuestionQuestionAssign:
                    op = AssignmentOperator.NullCoalesceAssign;
                    break;
                default:
                    ReportError(
                        ErrorCode.InvalidSyntax,
                        $"Invalid assignment operator '{Current.Value}'",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "This isn't a recognized assignment operator.",
                        hint: "Valid assignment operators: =, +=, -=, *=, /=, ??=",
                        suggestions: new List<string> {
                            "Use '=' for simple assignment",
                            "Use '+=' to add and assign: x += 5",
                            "Use '??=' for null-coalescing assignment"
                        },
                        length: Current.Value.Length
                    );
                    op = AssignmentOperator.Assign; // Default fallback
                    break;
            }

            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseLambdaOrAssignmentExpression);
            return new AssignmentExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseRightOperandOrMissing(Token operatorToken, Func<Expression> parseOperand)
    {
        if (!IsMissingOperandBoundary(operatorToken))
            return parseOperand();

        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected expression after '{operatorToken.Value}'",
            operatorToken.Line,
            operatorToken.Column,
            humanExplanation: $"The '{operatorToken.Value}' operator needs an expression on its right side.",
            hint: "Finish the expression after the operator, or remove the operator if the expression is already complete.",
            suggestions: new List<string>
            {
                $"Add an expression after '{operatorToken.Value}'",
                $"Remove the trailing '{operatorToken.Value}'"
            },
            length: Math.Max(1, operatorToken.Value.Length)
        );

        var column = operatorToken.Column + Math.Max(1, operatorToken.Value.Length);
        return new IdentifierExpression("<error>", operatorToken.Line, column);
    }

    private Expression ParseRequiredExpressionAfter(
        Token anchorToken,
        string expectedDescription,
        string ownerDescription)
    {
        if (!IsMissingRequiredExpressionBoundary(anchorToken))
            return ParseExpression();

        var markerColumn = anchorToken.Column + Math.Max(1, anchorToken.Value.Length);
        var underlineAnchor = ShouldUnderlineAnchorForMissingRequiredExpression(anchorToken);
        var diagnosticColumn = underlineAnchor ? anchorToken.Column : markerColumn;
        var diagnosticLength = underlineAnchor ? Math.Max(1, anchorToken.Value.Length) : 1;
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected {expectedDescription} after '{anchorToken.Value}'",
            anchorToken.Line,
            diagnosticColumn,
            humanExplanation: $"{ownerDescription} needs {expectedDescription} after '{anchorToken.Value}'.",
            hint: "Finish the expression before starting the next statement.",
            suggestions: new List<string>
            {
                $"Add {expectedDescription} after '{anchorToken.Value}'",
                $"Remove '{anchorToken.Value}' until the expression is ready"
            },
            length: diagnosticLength);

        return new IdentifierExpression("<error>", anchorToken.Line, markerColumn);
    }

    private static bool ShouldUnderlineAnchorForMissingRequiredExpression(Token anchorToken)
    {
        return anchorToken.Type switch
        {
            TokenType.If or
            TokenType.While or
            TokenType.Foreach or
            TokenType.Switch or
            TokenType.Print or
            TokenType.Throw or
            TokenType.Yield or
            TokenType.Assert or
            TokenType.Using or
            TokenType.Lock or
            TokenType.In or
            TokenType.Assign or
            TokenType.ColonAssign => true,
            _ => false
        };
    }

    private Token ReportMissingInKeywordAndRecover(Token loopKeywordToken, Token variableToken, string ownerDescription)
    {
        var expected = TokenTypeToString(TokenType.In);
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected '{expected}' between the loop variable and collection",
            loopKeywordToken.Line,
            loopKeywordToken.Column,
            humanExplanation: $"{ownerDescription} needs the '{expected}' keyword between the loop variable and the collection.",
            hint: $"Write `{loopKeywordToken.Value} {variableToken.Value} {expected} ...`.",
            suggestions: new List<string>
            {
                $"Add '{expected}' after '{variableToken.Value}'"
            },
            length: Math.Max(1, loopKeywordToken.Value.Length));

        var recoveredColumn = variableToken.Column + Math.Max(1, variableToken.Value.Length) + 1;
        return new Token(TokenType.In, expected, variableToken.Line, recoveredColumn, variableToken.FileName);
    }

    private bool IsMissingRequiredExpressionBoundary(Token anchorToken)
    {
        if (IsMissingOperandBoundary(anchorToken))
            return true;

        if (Current.Line > anchorToken.Line && LooksLikeStatementStartAfterRequiredExpression())
            return true;

        return Current.Line == anchorToken.Line &&
               (Check(TokenType.LeftBrace) ||
                Check(TokenType.RightBrace) ||
                Check(TokenType.RightParen) ||
                Check(TokenType.RightBracket) ||
                Check(TokenType.Comma) ||
                Check(TokenType.Semicolon));
    }

    private bool LooksLikeStatementStartAfterRequiredExpression()
    {
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.ColonAssign)
            return true;

        if (Check(TokenType.Identifier) &&
            LookAhead(1).Type == TokenType.Colon &&
            LookAhead(2).Type == TokenType.Identifier)
        {
            return true;
        }

        return StartsTupleDeconstructionAtCurrentPosition();
    }

    private bool StartsTupleDeconstructionAtCurrentPosition()
    {
        if (!Check(TokenType.Identifier) || LookAhead(1).Type != TokenType.Comma)
            return false;

        var pos = 1;
        while (_position + pos < _tokens.Count)
        {
            var token = _tokens[_position + pos];
            if (token.Line != Current.Line)
                return false;

            if (token.Type == TokenType.ColonAssign || token.Type == TokenType.Assign)
                return true;

            if (token.Type != TokenType.Identifier && token.Type != TokenType.Comma)
                return false;

            pos++;
        }

        return false;
    }

    private Expression ParseTernaryExpression()
    {
        var expr = ParseNullCoalescingExpression();

        if (Check(TokenType.Question))
        {
            var questionToken = Advance();
            var thenExpr = ParseExpression();
            Consume(TokenType.Colon, "Expected ':' in ternary expression");
            var elseExpr = ParseExpression();
            return new TernaryExpression(expr, thenExpr, elseExpr, questionToken.Line, questionToken.Column);
        }

        return expr;
    }

    private Expression ParseNullCoalescingExpression()
    {
        var expr = ParseLogicalOrExpression();

        while (Check(TokenType.QuestionQuestion))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseLogicalOrExpression);
            expr = new BinaryExpression(expr, BinaryOperator.NullCoalesce, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseLogicalOrExpression()
    {
        var expr = ParseLogicalAndExpression();

        while (Check(TokenType.Or))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseLogicalAndExpression);
            expr = new BinaryExpression(expr, BinaryOperator.Or, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseLogicalAndExpression()
    {
        var expr = ParseBitwiseOrExpression();

        while (Check(TokenType.And))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseBitwiseOrExpression);
            expr = new BinaryExpression(expr, BinaryOperator.And, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseBitwiseOrExpression()
    {
        var expr = ParseBitwiseXorExpression();

        while (Check(TokenType.BitwiseOr))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseBitwiseXorExpression);
            expr = new BinaryExpression(expr, BinaryOperator.BitwiseOr, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseBitwiseXorExpression()
    {
        var expr = ParseBitwiseAndExpression();

        while (Check(TokenType.BitwiseXor))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseBitwiseAndExpression);
            expr = new BinaryExpression(expr, BinaryOperator.BitwiseXor, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseBitwiseAndExpression()
    {
        var expr = ParseEqualityExpression();

        while (Check(TokenType.BitwiseAnd))
        {
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseEqualityExpression);
            expr = new BinaryExpression(expr, BinaryOperator.BitwiseAnd, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseEqualityExpression()
    {
        var expr = ParseRelationalExpression();

        while (Check(TokenType.Equal) || Check(TokenType.NotEqual))
        {
            var op = Current.Type == TokenType.Equal ? BinaryOperator.Equal : BinaryOperator.NotEqual;
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseRelationalExpression);
            expr = new BinaryExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseRelationalExpression()
    {
        var expr = ParseShiftExpression();

        while (Check(TokenType.Less) || Check(TokenType.LessEqual) ||
               Check(TokenType.Greater) || Check(TokenType.GreaterEqual) ||
               Check(TokenType.Is) || Check(TokenType.As))
        {
            if (Check(TokenType.Is))
            {
                var isToken = Advance();
                var type = ParseTypeReference();
                string? varName = null;

                if (Check(TokenType.Identifier))
                {
                    varName = Advance().Value;
                }

                expr = new IsExpression(expr, type, varName, isToken.Line, isToken.Column);
            }
            else if (Check(TokenType.As))
            {
                var asToken = Advance();
                var type = ParseTypeReference();
                expr = new CastExpression(expr, type, CastKind.Safe, asToken.Line, asToken.Column);
            }
            else
            {
                BinaryOperator op;
                switch (Current.Type)
                {
                    case TokenType.Less:
                        op = BinaryOperator.Less;
                        break;
                    case TokenType.LessEqual:
                        op = BinaryOperator.LessOrEqual;
                        break;
                    case TokenType.Greater:
                        op = BinaryOperator.Greater;
                        break;
                    case TokenType.GreaterEqual:
                        op = BinaryOperator.GreaterOrEqual;
                        break;
                    default:
                        ReportError(
                            ErrorCode.InvalidSyntax,
                            $"Invalid relational operator '{Current.Value}'",
                            Current.Line,
                            Current.Column,
                            humanExplanation: "This isn't a recognized comparison operator.",
                            hint: "Valid comparison operators: <, <=, >, >=",
                            suggestions: new List<string> {
                                "Use '<' for less than",
                                "Use '<=' for less than or equal",
                                "Use '>' for greater than",
                                "Use '>=' for greater than or equal"
                            },
                            length: Current.Value.Length
                        );
                        op = BinaryOperator.Less; // Default fallback
                        break;
                }

                var opToken = Advance();
                var right = ParseRightOperandOrMissing(opToken, ParseShiftExpression);
                expr = new BinaryExpression(expr, op, right, opToken.Line, opToken.Column);
            }
        }

        return expr;
    }

    private Expression ParseShiftExpression()
    {
        var expr = ParseAdditiveExpression();

        while (Check(TokenType.LeftShift) || Check(TokenType.RightShift))
        {
            var op = Current.Type == TokenType.LeftShift ? BinaryOperator.LeftShift : BinaryOperator.RightShift;
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseAdditiveExpression);
            expr = new BinaryExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseAdditiveExpression()
    {
        var expr = ParseMultiplicativeExpression();

        while (Check(TokenType.Plus) || Check(TokenType.Minus))
        {
            var op = Current.Type == TokenType.Plus ? BinaryOperator.Add : BinaryOperator.Subtract;
            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseMultiplicativeExpression);
            expr = new BinaryExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseMultiplicativeExpression()
    {
        var expr = ParseRangeExpression();

        while (Check(TokenType.Star) || Check(TokenType.Slash) || Check(TokenType.Percent))
        {
            BinaryOperator op;
            switch (Current.Type)
            {
                case TokenType.Star:
                    op = BinaryOperator.Multiply;
                    break;
                case TokenType.Slash:
                    op = BinaryOperator.Divide;
                    break;
                case TokenType.Percent:
                    op = BinaryOperator.Modulo;
                    break;
                default:
                    ReportError(
                        ErrorCode.InvalidSyntax,
                        $"Invalid multiplicative operator '{Current.Value}'",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "This isn't a recognized arithmetic operator.",
                        hint: "Valid multiplicative operators: *, /, %",
                        suggestions: new List<string> {
                            "Use '*' for multiplication",
                            "Use '/' for division",
                            "Use '%' for modulo (remainder)"
                        },
                        length: Current.Value.Length
                    );
                    op = BinaryOperator.Multiply; // Default fallback
                    break;
            }

            var opToken = Advance();
            var right = ParseRightOperandOrMissing(opToken, ParseRangeExpression);
            expr = new BinaryExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseRangeExpression()
    {
        // Check for open-ended start: ..end or ..
        if (Check(TokenType.DotDot))
        {
            var opToken = Advance();
            // Check if there's an end expression (..end) or fully open (..)
            // We need to peek ahead to see if this is followed by something that could be an expression
            Expression? end = null;
            if (!IsAtEnd() && !Check(TokenType.RightBracket) && !Check(TokenType.Comma) &&
                !Check(TokenType.RightParen) && !Check(TokenType.Semicolon))
            {
                end = ParseUnaryExpression();
            }
            return new RangeExpression(null, end, opToken.Line, opToken.Column);
        }

        var expr = ParseUnaryExpression();

        // Check for range with start: start..end or start..
        if (Check(TokenType.DotDot))
        {
            var opToken = Advance();
            // Check if there's an end expression
            Expression? end = null;
            if (!IsAtEnd() && !Check(TokenType.RightBracket) && !Check(TokenType.Comma) &&
                !Check(TokenType.RightParen) && !Check(TokenType.Semicolon))
            {
                end = ParseUnaryExpression();
            }
            return new RangeExpression(expr, end, opToken.Line, opToken.Column);
        }

        return expr;
    }

    private Expression ParseUnaryExpression()
    {
        if (Check(TokenType.Not) || Check(TokenType.Minus) || Check(TokenType.BitwiseNot) ||
            Check(TokenType.Increment) || Check(TokenType.Decrement) || Check(TokenType.BitwiseXor))
        {
            UnaryOperator op;
            switch (Current.Type)
            {
                case TokenType.Not:
                    op = UnaryOperator.Not;
                    break;
                case TokenType.Minus:
                    op = UnaryOperator.Negate;
                    break;
                case TokenType.BitwiseNot:
                    op = UnaryOperator.BitwiseNot;
                    break;
                case TokenType.Increment:
                    op = UnaryOperator.PreIncrement;
                    break;
                case TokenType.Decrement:
                    op = UnaryOperator.PreDecrement;
                    break;
                case TokenType.BitwiseXor:
                    op = UnaryOperator.IndexFromEnd;  // ^ as prefix for index from end
                    break;
                default:
                    ReportError(
                        ErrorCode.InvalidSyntax,
                        $"Invalid unary operator '{Current.Value}'",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "This isn't a recognized unary (prefix) operator.",
                        hint: "Valid unary operators: !, -, ~, ++, --, ^",
                        suggestions: new List<string> {
                            "Use '!' for logical not",
                            "Use '-' for negation",
                            "Use '++' for increment",
                            "Use '^' for index from end"
                        },
                        length: Current.Value.Length
                    );
                    op = UnaryOperator.Not; // Default fallback
                    break;
            }

            var opToken = Advance();
            var operand = ParseUnaryExpression();
            return new UnaryExpression(op, operand, opToken.Line, opToken.Column);
        }

        if (Check(TokenType.Await))
        {
            var awaitToken = Advance();
            var expr = ParseUnaryExpression();
            return new AwaitExpression(expr, awaitToken.Line, awaitToken.Column);
        }

        if (Check(TokenType.Must))
        {
            var mustToken = Advance();
            var expr = ParseUnaryExpression();
            return new MustExpression(expr, mustToken.Line, mustToken.Column);
        }

        if (Check(TokenType.Throw))
        {
            var throwToken = Advance();
            var expr = ParseUnaryExpression();
            return new ThrowExpression(expr, throwToken.Line, throwToken.Column);
        }

        return ParsePostfixExpression();
    }

    private Expression ParsePostfixExpression()
    {
        var expr = ParsePrimaryExpression();

        while (true)
        {
            if (Check(TokenType.Dot) || Check(TokenType.QuestionDot))
            {
                var isNullConditional = Check(TokenType.QuestionDot);
                var dotToken = Advance();
                string memberName;

                if (Current.Line == dotToken.Line && Check(TokenType.Identifier))
                {
                    memberName = Advance().Value;
                }
                else
                {
                    ReportMissingMemberNameAfterDot(dotToken);
                    memberName = "<error>";
                }
                expr = new MemberAccessExpression(expr, memberName, isNullConditional, dotToken.Line, dotToken.Column);
            }
            else if (Check(TokenType.LeftBracket) || Check(TokenType.QuestionBracket))
            {
                var isNullConditional = Check(TokenType.QuestionBracket);
                var bracketToken = Advance();
                var index = ParseExpression();
                Consume(TokenType.RightBracket, "Expected ']'");
                expr = new IndexAccessExpression(expr, index, isNullConditional, bracketToken.Line, bracketToken.Column);
            }
            else if (Check(TokenType.Less) && IsGenericMethodCall())
            {
                // Parse generic type arguments for method call
                var typeArgs = ParseCallTypeArguments();

                // Now parse the arguments
                if (!Check(TokenType.LeftParen))
                {
                    ReportError(
                        ErrorCode.ExpectedToken,
                        $"Expected '(' after generic type arguments. Got '{Current.Value}'",
                        Current.Line,
                        Current.Column,
                        humanExplanation: "Generic method calls need parentheses for the arguments, even if there are no arguments.",
                        hint: "After the generic type parameters, you need to provide the method arguments in parentheses.",
                        suggestions: new List<string> {
                            "Add parentheses: Method<int>()",
                            "With arguments: Method<int>(arg1, arg2)",
                            "Example: List.Create<string>(\"hello\")"
                        },
                        length: Current.Value.Length
                    );
                    // Create empty argument list as fallback
                    expr = new CallExpression(expr, new List<Argument>(), typeArgs, Current.Line, Current.Column);
                }
                else
                {
                    var parenToken = Advance();
                    var args = ParseArgumentList();
                    expr = new CallExpression(expr, args, typeArgs, parenToken.Line, parenToken.Column);
                }
            }
            else if (Check(TokenType.LeftParen))
            {
                var parenToken = Advance();
                var args = ParseArgumentList();
                expr = new CallExpression(expr, args, null, parenToken.Line, parenToken.Column);
            }
            else if (Check(TokenType.Increment))
            {
                var opToken = Advance();
                expr = new UnaryExpression(UnaryOperator.PostIncrement, expr, opToken.Line, opToken.Column);
            }
            else if (Check(TokenType.Decrement))
            {
                var opToken = Advance();
                expr = new UnaryExpression(UnaryOperator.PostDecrement, expr, opToken.Line, opToken.Column);
            }
            else if (Check(TokenType.With))
            {
                var withToken = Advance();
                Consume(TokenType.LeftBrace, "Expected '{'");
                var props = new List<PropertyInitializer>();

                while (!Check(TokenType.RightBrace) && !IsAtEnd())
                {
                    var startPosition = _position;
                    var propName = ConsumeIdentifier("Expected property name");
                    Consume(TokenType.Colon, "Expected ':'");
                    var propValue = ParseExpression();
                    props.Add(new PropertyInitializer(propName, null, propValue));

                    if (!Check(TokenType.RightBrace))
                        Match(TokenType.Comma);

                    EnsureProgress(startPosition);
                }

                Consume(TokenType.RightBrace, "Expected '}'");
                expr = new WithExpression(expr, props, withToken.Line, withToken.Column);
            }
            else
            {
                break;
            }
        }

        return expr;
    }

    private List<Argument> ParseArgumentList()
    {
        var args = new List<Argument>();

        if (!Check(TokenType.RightParen))
        {
            do
            {
                if (IsArgumentListRecoveryBoundary(Previous))
                    break;

                var modifier = ArgumentModifier.None;

                // Check for ref/out modifier
                if (Check(TokenType.Ref))
                {
                    modifier = ArgumentModifier.Ref;
                    Advance();
                }
                else if (Check(TokenType.Out))
                {
                    modifier = ArgumentModifier.Out;
                    Advance();

                    if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier)
                    {
                        var first = Current;
                        var second = LookAhead(1);
                        ReportError(
                            ErrorCode.InvalidSyntax,
                            "Inline out declarations are not supported",
                            first.Line,
                            first.Column,
                            humanExplanation: "N# out arguments must refer to a variable that already exists.",
                            hint: $"Declare '{second.Value}' before the call, then pass 'out {second.Value}'.",
                            length: Math.Max(1, second.Column + second.Value.Length - first.Column));
                        Advance();
                        Advance();
                        args.Add(new Argument(null, new IdentifierExpression(second.Value, second.Line, second.Column), modifier));
                        continue;
                    }
                }

                string? argName = null;

                // Check for named argument
                if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon)
                {
                    argName = Advance().Value;
                    Advance(); // consume colon
                }

                // Check for spread operator in function calls
                Expression argValue;
                if (Check(TokenType.DotDotDot))
                {
                    var spreadLine = Current.Line;
                    var spreadColumn = Current.Column;
                    Advance(); // consume '...'
                    var spreadExpr = ParseExpression();
                    argValue = new SpreadExpression(spreadExpr, spreadLine, spreadColumn);
                }
                else
                {
                    argValue = ParseExpression();
                }

                args.Add(new Argument(argName, argValue, modifier));

            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightParen, "Expected ')'");
        return args;
    }

    private bool IsArgumentListRecoveryBoundary()
        => IsAtEnd() ||
           Check(TokenType.LeftBrace) ||
           Check(TokenType.RightBrace) ||
           Check(TokenType.RightBracket) ||
           Check(TokenType.Semicolon);

    private bool IsArgumentListRecoveryBoundary(Token openingToken)
        => IsArgumentListRecoveryBoundary() ||
           IsContinuationRecoveryBoundary(openingToken);

    private Expression ParsePrimaryExpression()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Literals
        if (Check(TokenType.IntLiteral))
            return new IntLiteralExpression(Advance().Value, line, column);

        if (Check(TokenType.FloatLiteral))
            return new FloatLiteralExpression(Advance().Value, line, column);

        if (Check(TokenType.CharLiteral))
        {
            var token = Advance();
            ReportMalformedCharLiteralIfNeeded(token);
            return new CharLiteralExpression(token.Value, line, column);
        }

        if (Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral))
        {
            var token = Advance();
            ReportMalformedStringLiteralIfNeeded(token);
            if (token.Type == TokenType.StringLiteral && token.Value.StartsWith("$\""))
                return ParseInterpolatedString(token, line, column);
            if (token.Type == TokenType.InterpolatedRawStringLiteral)
                return ParseInterpolatedString(token, line, column, isRaw: true);
            return new StringLiteralExpression(token.Value, line, column);
        }

        if (Check(TokenType.True))
        {
            Advance();
            return new BoolLiteralExpression(true, line, column);
        }

        if (Check(TokenType.False))
        {
            Advance();
            return new BoolLiteralExpression(false, line, column);
        }

        if (Check(TokenType.Null))
        {
            Advance();
            return new NullLiteralExpression(line, column);
        }

        // Default expression (target-typed)
        if (Check(TokenType.Default))
        {
            var token = Advance();
            return new DefaultExpression(token.Line, token.Column);
        }

        // This and Base
        if (Check(TokenType.This))
        {
            Advance();
            return new ThisExpression(line, column);
        }

        if (Check(TokenType.Base))
        {
            Advance();
            return new BaseExpression(line, column);
        }

        // Typeof, Nameof and Sizeof
        if (Check(TokenType.Typeof))
        {
            Advance();
            Consume(TokenType.LeftParen, "Expected '('");
            var type = ParseTypeReference();
            Consume(TokenType.RightParen, "Expected ')'");
            return new TypeOfExpression(type, line, column);
        }

        if (Check(TokenType.Nameof))
        {
            Advance();
            Consume(TokenType.LeftParen, "Expected '('");
            var target = ParseExpression();
            Consume(TokenType.RightParen, "Expected ')'");
            return new NameofExpression(target, line, column);
        }

        if (Check(TokenType.Sizeof))
        {
            Advance();
            Consume(TokenType.LeftParen, "Expected '('");
            var type = ParseTypeReference();
            Consume(TokenType.RightParen, "Expected ')'");
            return new SizeOfExpression(type, line, column);
        }

        // Checked expression
        if (Check(TokenType.Checked))
        {
            Advance();
            Consume(TokenType.LeftParen, "Expected '('");
            var expr = ParseExpression();
            Consume(TokenType.RightParen, "Expected ')'");
            return new CheckedExpression(expr, line, column);
        }

        // Unchecked expression
        if (Check(TokenType.Unchecked))
        {
            Advance();
            Consume(TokenType.LeftParen, "Expected '('");
            var expr = ParseExpression();
            Consume(TokenType.RightParen, "Expected ')'");
            return new UncheckedExpression(expr, line, column);
        }

        // New expression
        if (Check(TokenType.New))
        {
            return ParseNewExpression();
        }

        // Match expression
        if (Check(TokenType.Match))
        {
            return ParseMatchExpression();
        }

        // Immutable array literal
        if (Check(TokenType.Immutable) && LookAhead(1).Type == TokenType.LeftBracket)
        {
            Advance(); // consume 'immutable'
            return ParseArrayLiteral(isImmutable: true);
        }

        // Array literal
        if (Check(TokenType.LeftBracket))
        {
            return ParseArrayLiteral();
        }

        // Cast expression (check before tuple/paren to handle (Type)expr)
        if (Check(TokenType.LeftParen) && IsCastExpression())
        {
            Advance();
            var castType = ParseTypeReference();
            Consume(TokenType.RightParen, "Expected ')'");
            var castExpr = ParseUnaryExpression();
            return new CastExpression(castExpr, castType, CastKind.Hard, line, column);
        }

        // Tuple or parenthesized expression (lambdas are now handled at higher precedence)
        if (Check(TokenType.LeftParen))
        {
            return ParseTupleOrParenthesizedExpression();
        }

        // Spread operator
        if (Check(TokenType.DotDotDot))
        {
            Advance();
            var spreadExpr = ParseExpression();
            return new SpreadExpression(spreadExpr, line, column);
        }

        // Identifier
        if (Check(TokenType.Identifier))
        {
            var name = Advance().Value;
            return new IdentifierExpression(name, line, column);
        }

        ReportError(
            ErrorCode.UnexpectedToken,
            $"Unexpected token '{Current.Value}' in expression",
            line,
            column,
            humanExplanation: $"I was parsing an expression and found '{Current.Value}', which I don't know how to handle here.",
            hint: "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.",
            length: Current.Value.Length
        );

        if (ShouldSkipUnexpectedExpressionToken())
            Advance();

        // Return error placeholder
        return new IdentifierExpression("<error>", line, column);
    }

    private void ReportMalformedStringLiteralIfNeeded(Token token)
    {
        if (token.Type == TokenType.TripleQuoteStringLiteral)
        {
            ReportMalformedRawStringLiteralIfNeeded(
                token,
                "Unterminated triple-quoted string literal",
                "This triple-quoted string starts with `\"\"\"` but reaches the end of the file before the closing triple quote.",
                "Add the closing triple quote `\"\"\"` before the end of the file.",
                markerLength: 3);
            return;
        }

        if (token.Type == TokenType.InterpolatedRawStringLiteral)
        {
            ReportMalformedRawStringLiteralIfNeeded(
                token,
                "Unterminated interpolated raw string literal",
                "This interpolated raw string starts with `$\"\"\"` but reaches the end of the file before the closing triple quote.",
                "Add the closing triple quote `\"\"\"` before the end of the file.",
                markerLength: 4);
            return;
        }

        if (token.Type != TokenType.StringLiteral || (token.IsTerminated && IsCompleteStringLiteral(token.Value)))
            return;

        var isInterpolated = token.Value.StartsWith("$\"", StringComparison.Ordinal);
        ReportError(
            ErrorCode.InvalidLiteral,
            isInterpolated ? "Unterminated interpolated string literal" : "Unterminated string literal",
            token.Line,
            token.Column,
            humanExplanation: isInterpolated
                ? "This interpolated string starts with `$\"` but reaches the end of the line before a closing quote."
                : "This string starts with a quote but reaches the end of the line before a closing quote.",
            hint: "Add the closing quote on this line, or use a triple-quoted string for multi-line text.",
            suggestions: new List<string>
            {
                "Add a closing quote",
                "Use triple quotes for multi-line strings"
            },
            length: Math.Max(1, token.Value.Length)
        );
    }

    private void ReportMalformedRawStringLiteralIfNeeded(
        Token token,
        string message,
        string humanExplanation,
        string hint,
        int markerLength)
    {
        if (token.IsTerminated)
            return;

        ReportError(
            ErrorCode.InvalidLiteral,
            message,
            token.Line,
            token.Column,
            humanExplanation: humanExplanation,
            hint: hint,
            suggestions: new List<string>
            {
                "Add the closing triple quote",
                "Check where the raw string should end"
            },
            length: markerLength
        );
    }

    private static bool IsCompleteStringLiteral(string value)
    {
        if (value.StartsWith("$\"", StringComparison.Ordinal))
            return HasUnescapedClosingQuote(value, openingQuoteIndex: 1);

        if (value.StartsWith('"'))
            return HasUnescapedClosingQuote(value, openingQuoteIndex: 0);

        return true;
    }

    private static bool HasUnescapedClosingQuote(string value, int openingQuoteIndex)
    {
        if (value.Length <= openingQuoteIndex + 1 || value[^1] != '"')
            return false;

        var backslashCount = 0;
        for (var i = value.Length - 2; i > openingQuoteIndex && value[i] == '\\'; i--)
            backslashCount++;

        return backslashCount % 2 == 0;
    }

    private void ReportMalformedCharLiteralIfNeeded(Token token)
    {
        if (IsCompleteCharLiteral(token.Value))
            return;

        var isEmpty = token.Value == "''";
        ReportError(
            ErrorCode.InvalidLiteral,
            isEmpty ? "Empty character literal" : "Unterminated character literal",
            token.Line,
            token.Column,
            humanExplanation: isEmpty
                ? "A character literal needs exactly one character between the quotes."
                : "This character literal starts with a quote but does not have a closing quote.",
            hint: "Write a single character like `'a'`, or use a string literal like \"a\" when you need text.",
            suggestions: new List<string>
            {
                "Add the closing quote",
                "Use double quotes for a string"
            },
            length: Math.Max(1, token.Value.Length)
        );
    }

    private static bool IsCompleteCharLiteral(string value)
    {
        if (value.Length < 3 || value[0] != '\'' || value[^1] != '\'')
            return false;

        var bodyLength = value.Length - 2;
        if (bodyLength == 1)
            return true;

        return bodyLength == 2 && value[1] == '\\';
    }

    private InterpolatedStringExpression ParseInterpolatedString(Token token, int line, int column, bool isRaw = false)
    {
        var parts = new List<InterpolatedStringPart>();
        var value = token.Value;

        int start = isRaw ? 4 : 2; // $"..." or $"""..."""
        int end = isRaw ? value.Length - 3 : value.Length - 1;
        if (end < start || !value.EndsWith(isRaw ? "\"\"\"" : "\"", StringComparison.Ordinal))
            end = value.Length;

        var textBuf = new System.Text.StringBuilder();
        int textStartLine = line;
        int textStartCol = column + start;
        int currentLine = line;
        int currentCol = column + start;
        int i = start;

        void AdvancePosition(char ch)
        {
            if (ch == '\n')
            {
                currentLine++;
                currentCol = 1;
            }
            else
            {
                currentCol++;
            }
        }

        void AppendText(char ch)
        {
            if (textBuf.Length == 0)
            {
                textStartLine = currentLine;
                textStartCol = currentCol;
            }
            textBuf.Append(ch);
        }

        void EmitText()
        {
            if (textBuf.Length == 0)
                return;

            parts.Add(new InterpolatedStringText(textBuf.ToString(), textStartLine, textStartCol));
            textBuf.Clear();
        }

        while (i < end)
        {
            char ch = value[i];

            if (!isRaw && ch == '\\' && i + 1 < end)
            {
                AppendText(ch);
                AdvancePosition(ch);
                i++;

                AppendText(value[i]);
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '{' && i + 1 < end && value[i + 1] == '{')
            {
                AppendText('{');
                AdvancePosition(value[i]);
                i++;
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '}' && i + 1 < end && value[i + 1] == '}')
            {
                AppendText('}');
                AdvancePosition(value[i]);
                i++;
                AdvancePosition(value[i]);
                i++;
                continue;
            }

            if (ch == '{')
            {
                if (isRaw)
                {
                    var previous = i - 1;
                    while (previous >= start && char.IsWhiteSpace(value[previous]))
                        previous--;

                    var nextClose = value.IndexOf('}', i + 1);
                    if ((previous >= start && value[previous] == ':')
                        || nextClose < 0
                        || value.Substring(i + 1, nextClose - i - 1).IndexOfAny(new[] { '\r', '\n' }) >= 0)
                    {
                        AppendText(ch);
                        AdvancePosition(ch);
                        i++;
                        continue;
                    }
                }

                EmitText();

                int holeLine = currentLine;
                int holeCol = currentCol;

                AdvancePosition(ch);
                i++;
                int exprStartLine = currentLine;
                int exprStartCol = currentCol;

                var exprBuilder = new System.Text.StringBuilder();
                int braceDepth = 1;
                bool inNestedString = false;

                while (i < end && braceDepth > 0)
                {
                    ch = value[i];

                    if (inNestedString)
                    {
                        exprBuilder.Append(ch);
                        if (ch == '\\' && i + 1 < end)
                        {
                            AdvancePosition(ch);
                            i++;
                            ch = value[i];
                            exprBuilder.Append(ch);
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
                            exprBuilder.Append(ch);
                        }
                        else if (ch == '{')
                        {
                            braceDepth++;
                            exprBuilder.Append(ch);
                        }
                        else if (ch == '}')
                        {
                            braceDepth--;
                            if (braceDepth == 0)
                                break;
                            exprBuilder.Append(ch);
                        }
                        else
                        {
                            exprBuilder.Append(ch);
                        }
                    }

                    AdvancePosition(ch);
                    i++;
                }

                var exprContent = exprBuilder.ToString();

                if (isRaw && exprContent.IndexOfAny(new[] { '\r', '\n' }) >= 0)
                {
                    var literalText = "{" + exprContent;
                    if (i < end && value[i] == '}')
                    {
                        literalText += "}";
                        AdvancePosition(value[i]);
                        i++;
                    }

                    parts.Add(new InterpolatedStringText(literalText, holeLine, holeCol));
                    textStartLine = currentLine;
                    textStartCol = currentCol;
                    continue;
                }

                string? formatClause = null;
                int colonPos = FindFormatSpecifierColon(exprContent);
                if (colonPos >= 0)
                {
                    formatClause = exprContent.Substring(colonPos + 1);
                    exprContent = exprContent.Substring(0, colonPos);
                }

                Expression expr;
                try
                {
                    var subLexer = new Lexer(exprContent);
                    var subTokens = subLexer.Tokenize();

                    for (int t = 0; t < subTokens.Count; t++)
                    {
                        var tok = subTokens[t];
                        int adjustedLine = tok.Line + exprStartLine - 1;
                        int adjustedColumn = tok.Line == 1 ? tok.Column + exprStartCol - 1 : tok.Column;
                        subTokens[t] = new Token(tok.Type, tok.Value, adjustedLine, adjustedColumn, tok.FileName, tok.IsTerminated);
                    }

                    var subParser = new Parser(subTokens, _fileName);
                    expr = subParser.ParseExpression();
                    if (!subParser.IsAtEnd())
                    {
                        subParser.ReportError(
                            ErrorCode.UnexpectedToken,
                            $"Unexpected token '{subParser.Current.Value}' after interpolated string expression",
                            subParser.Current.Line,
                            subParser.Current.Column,
                            humanExplanation: "I parsed a valid expression at the start of this interpolation hole, but there was extra syntax after it.",
                            hint: "Keep exactly one expression inside each interpolation hole, or split additional text outside the braces.",
                            length: Math.Max(1, subParser.Current.Value.Length));
                    }
                    _errors.AddRange(subParser._errors);
                }
                catch
                {
                    var trimmed = exprContent.Trim();
                    expr = new IdentifierExpression(
                        string.IsNullOrEmpty(trimmed) ? "<error>" : trimmed,
                        exprStartLine, exprStartCol);
                }

                parts.Add(new InterpolatedStringHole(expr, formatClause, holeLine, holeCol));

                if (i < end && value[i] == '}')
                {
                    AdvancePosition(value[i]);
                    i++;
                }

                textStartLine = currentLine;
                textStartCol = currentCol;
                continue;
            }

            AppendText(ch);
            AdvancePosition(ch);
            i++;
        }

        EmitText();

        return new InterpolatedStringExpression(parts, line, column, isRaw);
    }

    /// <summary>
    /// Finds the position of a format specifier colon in an interpolation expression.
    /// Returns -1 if no format specifier found.
    /// A format colon is one at the top level (not inside parens, brackets, braces, or strings).
    /// </summary>
    private static int FindFormatSpecifierColon(string expr)
    {
        int parenDepth = 0;
        int bracketDepth = 0;
        int braceDepth = 0;
        int ternaryDepth = 0;
        bool inString = false;

        for (int i = 0; i < expr.Length; i++)
        {
            if (inString)
            {
                if (expr[i] == '\\' && i + 1 < expr.Length)
                {
                    i++;
                    continue;
                }
                if (expr[i] == '"')
                    inString = false;
                continue;
            }

            switch (expr[i])
            {
                case '"':
                    inString = true;
                    break;
                case '(':
                    parenDepth++;
                    break;
                case ')':
                    parenDepth--;
                    break;
                case '[':
                    bracketDepth++;
                    break;
                case ']':
                    bracketDepth--;
                    break;
                case '{':
                    braceDepth++;
                    break;
                case '}':
                    braceDepth--;
                    break;
                case '?':
                    if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0)
                    {
                        var next = i + 1 < expr.Length ? expr[i + 1] : '\0';
                        if (next == '?')
                        {
                            i++;
                        }
                        else if (next != '.' && next != '[')
                        {
                            ternaryDepth++;
                        }
                    }
                    break;
                case ':' when parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && ternaryDepth > 0:
                    ternaryDepth--;
                    break;
                case ':' when parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                    return i;
            }
        }

        return -1;
    }

    private Expression ParseNewExpression()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.New, "Expected 'new'");

        // Target-typed new (C# 9): new() or new { ... }
        // Check if next token is '(' or '{' without a type
        TypeReference? type = null;
        var args = new List<Argument>();

        if (Check(TokenType.LeftParen))
        {
            // Target-typed new: new()
            Advance();
            args = ParseArgumentList();
        }
        else if (Check(TokenType.LeftBrace))
        {
            // Target-typed new with initializer only: new { ... }
            // Leave type as null, will parse initializer below
        }
        else
        {
            // Traditional new: new TypeName() or new TypeName { ... }
            type = ParseTypeReference();

            if (Check(TokenType.LeftParen))
            {
                Advance();
                args = ParseArgumentList();
            }
        }

        ObjectInitializerExpression? initializer = null;
        if (Check(TokenType.LeftBrace))
        {
            // For array types (e.g., new string[] { "a", "b" }), parse as collection initializer
            bool isCollectionInit = type is ArrayTypeReference;

            Advance();
            var props = new List<PropertyInitializer>();

            while (!Check(TokenType.RightBrace) && !IsAtEnd())
            {
                var startPosition = _position;

                if (isCollectionInit)
                {
                    // Collection initializer: bare values
                    var value = ParseExpression();
                    props.Add(new PropertyInitializer(null, null, value));
                }
                // Check if this is an indexer initializer (starts with '[')
                else if (Check(TokenType.LeftBracket))
                {
                    Advance(); // consume '['
                    var indexExpr = ParseExpression();
                    Consume(TokenType.RightBracket, "Expected ']'");
                    Consume(TokenType.Assign, "Expected '='");
                    var indexValue = ParseExpression();
                    props.Add(new PropertyInitializer(null, indexExpr, indexValue));
                }
                else
                {
                    // Regular property initializer
                    var propName = ConsumeIdentifier("Expected property name");
                    if (Check(TokenType.Assign))
                    {
                        ReportError(
                            ErrorCode.InvalidSyntax,
                            $"Object initializer member '{propName}' uses '='; N# uses ':'",
                            Current.Line,
                            Current.Column,
                            humanExplanation: "Object initializer members in N# use a colon between the member name and value. The equals sign is C# initializer syntax.",
                            hint: $"Write '{propName}: value' instead of '{propName} = value'.",
                            suggestions: new List<string>
                            {
                                $"Change '{propName} = ...' to '{propName}: ...'"
                            },
                            length: Current.Value.Length
                        );
                        Advance();
                    }
                    else
                    {
                        Consume(TokenType.Colon, "Expected ':'");
                    }
                    var propValue = ParseExpression();
                    props.Add(new PropertyInitializer(propName, null, propValue));
                }

                if (!Check(TokenType.RightBrace))
                    Match(TokenType.Comma);

                if (!EnsureProgress(startPosition))
                    _panicMode = false;
            }

            Consume(TokenType.RightBrace, "Expected '}'");
            initializer = new ObjectInitializerExpression(props, line, column);
        }

        return new NewExpression(type, args, initializer, line, column);
    }

    private Expression ParseMatchExpression()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Match, "Expected 'match'");

        var value = ParseExpression();
        Consume(TokenType.LeftBrace, "Expected '{'");

        var cases = new List<MatchCase>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            var startPosition = _position;
            var pattern = ParsePattern();

            // Check for guard clause (when expression)
            Expression? guard = null;
            if (Match(TokenType.When))
            {
                guard = ParseExpression();
            }

            Consume(TokenType.Arrow, "Expected '=>'");
            var caseExpr = ParseExpression();
            cases.Add(new MatchCase(pattern, guard, caseExpr));

            // Require comma between cases (except before closing brace)
            if (!Check(TokenType.RightBrace))
                Consume(TokenType.Comma, "Expected ',' between match cases");

            EnsureProgress(startPosition);
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new MatchExpression(value, cases, line, column);
    }

    private Expression ParseArrayLiteral(bool isImmutable = false)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftBracket, "Expected '['");

        var elements = new List<Expression>();

        if (!Check(TokenType.RightBracket))
        {
            do
            {
                elements.Add(ParseExpression());
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightBracket, "Expected ']'");

        return new ArrayLiteralExpression(elements, isImmutable, line, column);
    }

    private Expression ParseTupleOrParenthesizedExpression()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftParen, "Expected '('");

        // Empty tuple
        if (Check(TokenType.RightParen))
        {
            Advance();
            return new TupleExpression(new List<TupleElement>(), line, column);
        }

        if (IsArgumentListRecoveryBoundary(Previous))
        {
            var recoveredToken = Consume(TokenType.RightParen, "Expected ')'");
            return new ParenthesizedExpression(
                new IdentifierExpression("<error>", recoveredToken.Line, recoveredToken.Column),
                line,
                column);
        }

        // Single element or tuple
        var firstExpr = ParseExpression();

        // Check for named tuple element
        if (Check(TokenType.Colon) && firstExpr is IdentifierExpression firstIdent)
        {
            Advance();
            var firstValue = ParseExpression();
            var elements = new List<TupleElement>
            {
                new TupleElement(firstIdent.Name, firstValue)
            };

            while (Match(TokenType.Comma))
            {
                var elemName = ConsumeIdentifier("Expected identifier");
                Consume(TokenType.Colon, "Expected ':'");
                var elemValue = ParseExpression();
                elements.Add(new TupleElement(elemName, elemValue));
            }

            Consume(TokenType.RightParen, "Expected ')'");
            return new TupleExpression(elements, line, column);
        }

        // Tuple with unnamed elements
        if (Check(TokenType.Comma))
        {
            var elements = new List<TupleElement> { new TupleElement(null, firstExpr) };

            while (Match(TokenType.Comma))
            {
                elements.Add(new TupleElement(null, ParseExpression()));
            }

            Consume(TokenType.RightParen, "Expected ')'");
            return new TupleExpression(elements, line, column);
        }

        // Parenthesized expression
        Consume(TokenType.RightParen, "Expected ')'");
        return new ParenthesizedExpression(firstExpr, line, column);
    }

    private Expression ParseMultiParameterLambda()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftParen, "Expected '('");

        var parameters = new List<Parameter>();

        if (!Check(TokenType.RightParen))
        {
            do
            {
                var paramLine = Current.Line;
                var paramColumn = Current.Column;
                var paramName = ConsumeIdentifier("Expected parameter name");
                parameters.Add(new Parameter(paramName, new SimpleTypeReference("var"), null, false, Line: paramLine, Column: paramColumn));
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightParen, "Expected ')'");
        Consume(TokenType.Arrow, "Expected '=>'");

        if (Check(TokenType.LeftBrace))
        {
            var lambdaSpan = parameters.Count > 0 && parameters[0].Name != "<error>"
                ? new DiagnosticSpan(parameters[0].Line, parameters[0].Column, Math.Max(1, parameters[0].Name.Length))
                : new DiagnosticSpan(line, column, 1);
            var body = ParseBlock(lambdaSpan);
            return new LambdaExpression(parameters, null, body, line, column);
        }
        else
        {
            var exprBody = ParseExpression();
            return new LambdaExpression(parameters, exprBody, null, line, column);
        }
    }

    private bool IsLambdaExpression()
    {
        var saved = _position;
        try
        {
            Advance(); // consume (

            // Empty lambda
            if (Check(TokenType.RightParen) && LookAhead(1).Type == TokenType.Arrow)
                return true;

            // Check for lambda parameters
            while (!IsAtEnd())
            {
                if (!Check(TokenType.Identifier))
                    return false;

                Advance();

                if (Check(TokenType.RightParen))
                {
                    return LookAhead(1).Type == TokenType.Arrow;
                }

                if (!Check(TokenType.Comma))
                    return false;

                Advance();
            }

            return false;
        }
        finally
        {
            _position = saved;
        }
    }

    private bool IsCastExpression()
    {
        var position = _position + 1; // Skip '(' without mutating parser state.
        var splitGreaterDepth = 0;

        TokenType CurrentType()
        {
            if (splitGreaterDepth > 0)
                return TokenType.Greater;

            return position < _tokens.Count ? _tokens[position].Type : TokenType.Eof;
        }

        void AdvanceScan()
        {
            if (splitGreaterDepth > 0)
            {
                splitGreaterDepth--;
                return;
            }

            if (position < _tokens.Count)
                position++;
        }

        bool ConsumeScan(TokenType type)
        {
            if (CurrentType() != type)
                return false;

            AdvanceScan();
            return true;
        }

        bool ConsumeGreaterScan()
        {
            if (CurrentType() == TokenType.Greater)
            {
                AdvanceScan();
                return true;
            }

            if (splitGreaterDepth == 0
                && position < _tokens.Count
                && _tokens[position].Type == TokenType.RightShift)
            {
                position++;
                splitGreaterDepth++;
                return true;
            }

            return false;
        }

        bool ScanTypeReference()
        {
            if (!ScanPostfixTypeReference())
                return false;

            while (CurrentType() == TokenType.BitwiseOr)
            {
                AdvanceScan();
                if (!ScanPostfixTypeReference())
                    return false;
            }

            return true;
        }

        bool ScanPostfixTypeReference()
        {
            if (!ScanBaseTypeReference())
                return false;

            while (CurrentType() == TokenType.LeftBracket
                   && position + 1 < _tokens.Count
                   && _tokens[position + 1].Type == TokenType.RightBracket)
            {
                AdvanceScan();
                AdvanceScan();
            }

            while (CurrentType() == TokenType.Question)
            {
                AdvanceScan();
            }

            return true;
        }

        bool ScanBaseTypeReference()
        {
            if (CurrentType() == TokenType.LeftParen)
            {
                AdvanceScan();

                if (CurrentType() == TokenType.RightParen)
                    return false;

                do
                {
                    if (CurrentType() == TokenType.Identifier
                        && position + 1 < _tokens.Count
                        && _tokens[position + 1].Type == TokenType.Colon)
                    {
                        AdvanceScan();
                        AdvanceScan();
                    }

                    if (!ScanTypeReference())
                        return false;
                } while (ConsumeScan(TokenType.Comma));

                return ConsumeScan(TokenType.RightParen);
            }

            if (CurrentType() != TokenType.Identifier)
                return false;

            AdvanceScan();

            while (ConsumeScan(TokenType.Dot))
            {
                if (CurrentType() != TokenType.Identifier)
                    return false;
                AdvanceScan();
            }

            if (ConsumeScan(TokenType.Less))
            {
                if (!ScanTypeReference())
                    return false;

                while (ConsumeScan(TokenType.Comma))
                {
                    if (!ScanTypeReference())
                        return false;
                }

                if (!ConsumeGreaterScan())
                    return false;
            }

            return true;
        }

        return ScanTypeReference()
               && CurrentType() == TokenType.RightParen
               && IsExpressionStart(position + 1 < _tokens.Count ? _tokens[position + 1].Type : TokenType.Eof);
    }

    private static bool IsExpressionStart(TokenType type)
    {
        return type is
            TokenType.Identifier or
            TokenType.IntLiteral or
            TokenType.FloatLiteral or
            TokenType.CharLiteral or
            TokenType.StringLiteral or
            TokenType.TripleQuoteStringLiteral or
            TokenType.InterpolatedRawStringLiteral or
            TokenType.True or
            TokenType.False or
            TokenType.Null or
            TokenType.Default or
            TokenType.New or
            TokenType.This or
            TokenType.Base or
            TokenType.LeftParen or
            TokenType.LeftBracket or
            TokenType.Immutable or
            TokenType.Plus or
            TokenType.Minus or
            TokenType.Not or
            TokenType.BitwiseNot or
            TokenType.Increment or
            TokenType.Decrement or
            TokenType.Must or
            TokenType.Await or
            TokenType.Throw or
            TokenType.Match or
            TokenType.Typeof or
            TokenType.Nameof or
            TokenType.Sizeof or
            TokenType.Checked or
            TokenType.Unchecked;
    }

    private string ParseOperatorSymbol()
    {
        // Parse operator symbol for operator overloading
        // Supported: +, -, *, /, %, ==, !=, <, >, <=, >=, !, ~, ++, --, true, false
        var token = Current;
        string symbol;
        switch (token.Type)
        {
            case TokenType.Plus:
                symbol = "+";
                break;
            case TokenType.Minus:
                symbol = "-";
                break;
            case TokenType.Star:
                symbol = "*";
                break;
            case TokenType.Slash:
                symbol = "/";
                break;
            case TokenType.Percent:
                symbol = "%";
                break;
            case TokenType.Equal:
                symbol = "==";
                break;
            case TokenType.NotEqual:
                symbol = "!=";
                break;
            case TokenType.Less:
                symbol = "<";
                break;
            case TokenType.LessEqual:
                symbol = "<=";
                break;
            case TokenType.Greater:
                symbol = ">";
                break;
            case TokenType.GreaterEqual:
                symbol = ">=";
                break;
            case TokenType.Not:
                symbol = "!";
                break;
            case TokenType.BitwiseNot:
                symbol = "~";
                break;
            case TokenType.BitwiseAnd:
                symbol = "&";
                break;
            case TokenType.BitwiseOr:
                symbol = "|";
                break;
            case TokenType.BitwiseXor:
                symbol = "^";
                break;
            case TokenType.LeftShift:
                symbol = "<<";
                break;
            case TokenType.RightShift:
                symbol = ">>";
                break;
            case TokenType.Increment:
                symbol = "++";
                break;
            case TokenType.Decrement:
                symbol = "--";
                break;
            case TokenType.True:
                symbol = "true";
                break;
            case TokenType.False:
                symbol = "false";
                break;
            default:
                ReportError(
                    ErrorCode.InvalidSyntax,
                    $"Invalid operator symbol '{token.Value}' for operator overloading",
                    token.Line,
                    token.Column,
                    humanExplanation: "This operator cannot be overloaded, or is not a valid operator symbol.",
                    hint: "Only certain operators can be overloaded in operator declarations.",
                    suggestions: new List<string> {
                        "Arithmetic: +, -, *, /, %",
                        "Comparison: ==, !=, <, >, <=, >=",
                        "Unary: !, ~, ++, --",
                        "Conversion: true, false"
                    },
                    length: token.Value.Length
                );
                symbol = "+"; // Default fallback
                break;
        }

        Advance();
        return symbol;
    }

    // Helper methods
    private Token Current => _position < _tokens.Count ? _tokens[_position] : _tokens[^1];

    private Token Previous => _position > 0 ? _tokens[_position - 1] : _tokens[0];

    private bool IsAtEnd() => Current.Type == TokenType.Eof;

    private Token Advance()
    {
        // Handle split >> token
        if (_splitGreaterDepth > 0)
        {
            _splitGreaterDepth--;
            // Return a virtual > token
            var prev = _tokens[_position - 1];
            return new Token(TokenType.Greater, ">", prev.Line, prev.Column + 1, prev.FileName);
        }

        if (!IsAtEnd())
            _position++;
        return _tokens[_position - 1];
    }

    private static SourceSpan SpanFromTokens(Token start, Token end)
    {
        if (start.Line <= 0 || start.Column <= 0)
            return SourceSpan.None;

        return new SourceSpan(
            start.Line,
            start.Column,
            end.Line,
            end.Column + Math.Max(1, end.Value.Length));
    }

    private static SourceSpan ExtendSpan(TypeReference start, Token end)
    {
        if (!start.Span.IsValid)
            return SourceSpan.None;

        return new SourceSpan(
            start.Span.StartLine,
            start.Span.StartColumn,
            end.Line,
            end.Column + Math.Max(1, end.Value.Length));
    }

    private static int TokenLengthOrFallback(Token? token)
        => token is null ? 1 : Math.Max(1, token.Value.Length);

    private static int TokenSpanLengthOrFallback(Token? start, Token? end)
    {
        if (start is null)
            return 1;

        if (end is null || end.Line != start.Line)
            return TokenLengthOrFallback(start);

        return Math.Max(1, end.Column + TokenLengthOrFallback(end) - start.Column);
    }

    private static DiagnosticSpan DiagnosticSpanFromToken(Token token)
        => new(token.Line, token.Column, TokenLengthOrFallback(token));

    private static Token? LaterToken(Token? left, Token? right)
    {
        if (left is null)
            return right;
        if (right is null)
            return left;

        return right.Line > left.Line || (right.Line == left.Line && right.Column >= left.Column)
            ? right
            : left;
    }

    private bool Check(TokenType type)
    {
        // Handle split >> token
        if (_splitGreaterDepth > 0 && type == TokenType.Greater)
        {
            return true; // We owe a > from a previous >>
        }
        return Current.Type == type;
    }

    private bool Match(TokenType type)
    {
        if (Check(type))
        {
            Advance();
            return true;
        }
        return false;
    }

    private Token LookAhead(int offset)
    {
        var pos = _position + offset;
        return pos < _tokens.Count ? _tokens[pos] : _tokens[^1];
    }

    private Token Consume(TokenType type, string message)
    {
        if (!Check(type))
        {
            if (TryReportMissingClosingDelimiter(type, out var recoveredToken))
                return recoveredToken;

            var expected = TokenTypeToString(type);
            ReportError(
                ErrorCode.ExpectedToken,
                $"{message}. Expected '{expected}', got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: $"I was expecting {expected} here, but I found '{Current.Value}' instead.",
                hint: GetHintForMissingToken(type),
                length: Current.Value.Length
            );
            return Current; // Don't advance
        }
        return Advance();
    }

    private bool TryReportMissingClosingDelimiter(TokenType type, out Token recoveredToken)
    {
        recoveredToken = Current;

        var (code, expected, opening, hint) = type switch
        {
            TokenType.RightParen => (
                ErrorCode.MissingClosingParen,
                ")",
                "(",
                "Every opening parenthesis '(' needs a matching closing parenthesis ')'."),
            TokenType.RightBracket => (
                ErrorCode.MissingClosingBracket,
                "]",
                "[",
                "Every opening bracket '[' needs a matching closing bracket ']'."),
            _ => default
        };

        if (code == default)
            return false;

        var previous = Previous;
        if (previous.Type == TokenType.Eof)
            return false;

        var sameLineBoundary = Current.Type != TokenType.Eof &&
                               Current.Line == previous.Line &&
                               IsSameLineMissingClosingDelimiterBoundary(type);

        if (Current.Type != TokenType.Eof && Current.Line <= previous.Line && !sameLineBoundary)
            return false;

        var previousLength = Math.Max(1, previous.Value.Length);
        var insertionLine = sameLineBoundary ? Current.Line : previous.Line;
        var insertionColumn = sameLineBoundary ? Current.Column : previous.Column + previousLength;
        var (diagnosticLine, diagnosticColumn, diagnosticLength) =
            GetMissingClosingDelimiterDiagnosticSpan(type, previous, sameLineBoundary);
        var found = sameLineBoundary ? Current.Value : null;

        ReportError(
            code,
            $"Missing closing '{expected}'",
            diagnosticLine,
            diagnosticColumn,
            humanExplanation: found is null
                ? $"I reached the next line while looking for the closing '{expected}' that matches an earlier '{opening}'."
                : $"I found '{found}' while looking for the closing '{expected}' that matches an earlier '{opening}'.",
            hint: hint,
            suggestions: new List<string>
            {
                found is null ? $"Add '{expected}' before starting the next line" : $"Add '{expected}' before '{found}'",
                $"Check the matching '{opening}' in this expression"
            },
            length: diagnosticLength
        );

        recoveredToken = new Token(type, expected, insertionLine, insertionColumn, previous.FileName);
        return true;
    }

    private (int Line, int Column, int Length) GetMissingClosingDelimiterDiagnosticSpan(
        TokenType expectedClosingType,
        Token previous,
        bool sameLineBoundary)
    {
        if (sameLineBoundary)
            return (Current.Line, Current.Column, Math.Max(1, Current.Value.Length));

        if (expectedClosingType == TokenType.RightParen &&
            TryFindUnmatchedOpeningDelimiter(TokenType.LeftParen, TokenType.RightParen, previous, out var openingToken))
        {
            if (TryGetDelimiterOwnerSpan(openingToken, out var ownerSpan))
                return ownerSpan;

            return (openingToken.Line, openingToken.Column, Math.Max(1, openingToken.Value.Length));
        }

        if (expectedClosingType == TokenType.RightBracket &&
            TryFindUnmatchedOpeningDelimiter(TokenType.LeftBracket, TokenType.RightBracket, previous, out var bracketToken))
        {
            if (TryGetDelimiterOwnerSpan(bracketToken, out var ownerSpan))
                return ownerSpan;

            return (bracketToken.Line, bracketToken.Column, Math.Max(1, bracketToken.Value.Length));
        }

        var fallbackLength = Math.Max(1, previous.Value.Length);
        return (previous.Line, previous.Column + fallbackLength, 1);
    }

    private bool TryFindUnmatchedOpeningDelimiter(
        TokenType openingType,
        TokenType closingType,
        Token previous,
        out Token openingToken)
    {
        var depth = 0;
        var previousEndColumn = previous.Column + Math.Max(1, previous.Value.Length);

        for (var index = Math.Min(_position - 1, _tokens.Count - 1); index >= 0; index--)
        {
            var token = _tokens[index];
            if (token.Type == TokenType.Eof)
                continue;

            if (token.Line > previous.Line ||
                (token.Line == previous.Line && token.Column > previousEndColumn))
            {
                continue;
            }

            if (token.Type == closingType)
            {
                depth++;
                continue;
            }

            if (token.Type != openingType)
                continue;

            if (depth == 0)
            {
                openingToken = token;
                return true;
            }

            depth--;
        }

        openingToken = previous;
        return false;
    }

    private bool TryGetDelimiterOwnerSpan(Token openingToken, out (int Line, int Column, int Length) span)
    {
        var tokenIndex = _tokens.FindIndex(token =>
            token.Line == openingToken.Line &&
            token.Column == openingToken.Column &&
            token.Type == openingToken.Type &&
            token.Value == openingToken.Value);

        if (tokenIndex > 0)
        {
            var owner = _tokens[tokenIndex - 1];
            if (owner.Line == openingToken.Line && IsVisibleDelimiterOwner(owner))
            {
                span = (owner.Line, owner.Column, Math.Max(1, owner.Value.Length));
                return true;
            }

            if (owner.Line == openingToken.Line &&
                IsAssignmentAnchor(owner) &&
                TryGetPreviousTokenOnLine(tokenIndex - 1, owner.Line, out var assignedName) &&
                IsVisibleDelimiterOwner(assignedName))
            {
                span = (assignedName.Line, assignedName.Column, Math.Max(1, assignedName.Value.Length));
                return true;
            }
        }

        span = default;
        return false;
    }

    private static bool IsVisibleDelimiterOwner(Token token)
        => token.Type == TokenType.Identifier ||
           token.Type is TokenType.Print or
               TokenType.If or
               TokenType.Case or
               TokenType.Default or
               TokenType.While or
               TokenType.For or
               TokenType.Foreach or
               TokenType.Switch or
               TokenType.Lock or
               TokenType.Using or
               TokenType.Assert or
               TokenType.Return or
               TokenType.Yield or
               TokenType.Throw or
               TokenType.Func or
               TokenType.Test;

    private static bool IsAssignmentAnchor(Token token)
        => token.Type is TokenType.Assign or TokenType.ColonAssign;

    private bool TryGetPreviousTokenOnLine(int beforeIndex, int line, out Token token)
    {
        for (var index = beforeIndex - 1; index >= 0; index--)
        {
            var candidate = _tokens[index];
            if (candidate.Type == TokenType.Eof)
                continue;

            if (candidate.Line != line)
                break;

            token = candidate;
            return true;
        }

        token = default!;
        return false;
    }

    private bool IsSameLineMissingClosingDelimiterBoundary(TokenType type)
    {
        return type switch
        {
            TokenType.RightParen => Check(TokenType.LeftBrace) ||
                                    Check(TokenType.RightBrace) ||
                                    Check(TokenType.RightBracket) ||
                                    Check(TokenType.Colon) ||
                                    Check(TokenType.Arrow) ||
                                    Check(TokenType.Semicolon),
            TokenType.RightBracket => Check(TokenType.RightBrace) ||
                                      Check(TokenType.RightParen) ||
                                      Check(TokenType.Semicolon),
            _ => false
        };
    }

    private string TokenTypeToString(TokenType type)
    {
        return type switch
        {
            TokenType.LeftParen => "(",
            TokenType.RightParen => ")",
            TokenType.LeftBrace => "{",
            TokenType.RightBrace => "}",
            TokenType.LeftBracket => "[",
            TokenType.RightBracket => "]",
            TokenType.Semicolon => ";",
            TokenType.Colon => ":",
            TokenType.Comma => ",",
            TokenType.Dot => ".",
            TokenType.Equal => "=",
            _ => type.ToString().ToLower()
        };
    }

    private string? GetHintForMissingToken(TokenType type)
    {
        return type switch
        {
            TokenType.RightParen => "Every opening parenthesis '(' needs a matching closing parenthesis ')'.",
            TokenType.RightBrace => "Every opening brace '{' needs a matching closing brace '}'.",
            TokenType.RightBracket => "Every opening bracket '[' needs a matching closing bracket ']'.",
            TokenType.Semicolon => "Statements can end with a semicolon, though it's optional in N#.",
            _ => null
        };
    }

    private void ReportMissingMemberNameAfterDot(Token dotToken)
    {
        var operatorText = dotToken.Value;
        var operatorDescription = operatorText == "."
            ? "dot (.)"
            : $"null-conditional member access ({operatorText})";
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected member name. Got '{Current.Value}'",
            dotToken.Line,
            dotToken.Column,
            humanExplanation: $"I see a {operatorDescription} operator but no member name after it.",
            hint: $"After {operatorDescription}, I need to see a property or method name.",
            suggestions: new List<string> {
                "Check if you forgot to finish this line",
                "Common members: Length, Count, ToString(), GetHashCode()",
                $"If this is end of statement, remove the trailing '{operatorText}'"
            },
            length: Math.Max(1, operatorText.Length));
    }

    private Token ConsumeParameterColon(string parameterName, int parameterLine, int parameterColumn)
    {
        if (Check(TokenType.Colon))
            return Advance();

        if (parameterName == "<error>" || parameterLine <= 0 || parameterColumn <= 0)
            return Consume(TokenType.Colon, "Expected ':' after parameter name");

        var nameLength = Math.Max(1, parameterName.Length);
        var insertionColumn = parameterColumn + nameLength;
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected ':' after parameter name. Got '{Current.Value}'",
            parameterLine,
            parameterColumn,
            humanExplanation: $"Parameter '{parameterName}' needs a ':' before its type.",
            hint: $"Write this parameter as `{parameterName}: Type`.",
            suggestions: new List<string>
            {
                $"Add ':' after '{parameterName}'"
            },
            length: nameLength);

        return new Token(TokenType.Colon, ":", parameterLine, insertionColumn, Current.FileName);
    }

    private Token ConsumeFieldColon(string fieldName, int fieldLine, int fieldColumn)
    {
        if (Check(TokenType.Colon))
            return Advance();

        if (fieldName == "<error>" || fieldLine <= 0 || fieldColumn <= 0)
            return Consume(TokenType.Colon, "Expected ':' or ':='");

        var nameLength = Math.Max(1, fieldName.Length);
        var insertionColumn = fieldColumn + nameLength;
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected ':' or ':=' after field name. Got '{Current.Value}'",
            fieldLine,
            fieldColumn,
            humanExplanation: $"Field '{fieldName}' needs a ':' before its type, or ':=' before an inferred initializer.",
            hint: $"Write this field as `{fieldName}: Type` or `{fieldName} := value`.",
            suggestions: new List<string>
            {
                $"Add ':' after '{fieldName}'",
                $"Use ':=' after '{fieldName}' if the type should be inferred"
            },
            length: nameLength);

        return new Token(TokenType.Colon, ":", fieldLine, insertionColumn, Current.FileName);
    }

    private bool IsLikelyMissingReturnTypeMarker(Token parameterListEndToken)
    {
        return parameterListEndToken.Type == TokenType.RightParen &&
               Current.Line == parameterListEndToken.Line &&
               IsTypeReferenceStart(Current.Type);
    }

    private static bool IsTypeReferenceStart(TokenType type)
    {
        return type is TokenType.Identifier or TokenType.LeftParen;
    }

    private void ReportMissingReturnTypeMarker(
        string declarationName,
        int declarationLine,
        int declarationColumn,
        int declarationLength)
    {
        ReportError(
            ErrorCode.ExpectedToken,
            $"Expected ':' before return type. Got '{Current.Value}'",
            declarationLine,
            declarationColumn,
            humanExplanation: $"Function '{declarationName}' needs a ':' before its return type.",
            hint: "Write the return type as `func name(...): Type { ... }`.",
            suggestions: new List<string>
            {
                $"Add ':' before '{Current.Value}'",
                "Remove the return type if this function does not return a value"
            },
            length: Math.Max(1, declarationLength));
    }

    private bool EnsureProgress(int startPosition)
    {
        if (_position == startPosition && !IsAtEnd())
        {
            Advance();
            return true;
        }

        return false;
    }

    private string ConsumeIdentifier(string message)
    {
        if (!Check(TokenType.Identifier))
        {
            // Check if this is incomplete member access (dot with no member)
            var previous = _position > 0 ? _tokens[_position - 1] : _tokens[0];
            var isDotAccess = previous.Type == TokenType.Dot || previous.Type == TokenType.QuestionDot;

            ReportError(
                ErrorCode.ExpectedToken,
                $"{message}. Got '{Current.Value}'",
                Current.Line,
                Current.Column,
                humanExplanation: isDotAccess
                    ? $"I see a dot (.) operator but no member name after it. I found '{Current.Value}' instead."
                    : $"I was expecting an identifier here, but I found '{Current.Value}' instead.",
                hint: isDotAccess
                    ? "After a dot, I need to see a property or method name."
                    : "An identifier is a name for a variable, function, or type.",
                suggestions: isDotAccess
                    ? new List<string> {
                        "Check if you forgot to finish this line",
                        "Common members: Length, Count, ToString(), GetHashCode()",
                        "If this is end of statement, remove the trailing dot"
                    }
                    : null,
                length: Current.Value.Length
            );

            return "<error>"; // Return placeholder
        }
        return Advance().Value;
    }

    /// <summary>
    /// Report a parse error with rich context
    /// </summary>
    private void ReportError(
        ErrorCode code,
        string message,
        int line,
        int column,
        string? humanExplanation = null,
        string? hint = null,
        List<string>? suggestions = null,
        int length = 0)
    {
        // In panic mode, suppress cascading errors until we synchronize
        if (_panicMode)
            return;

        var snippet = GetSourceSnippet(line);

        var error = CompilerError.WithSnippet(
            code,
            message,
            _fileName ?? "unknown",
            line,
            column,
            snippet ?? "",
            length,
            suggestions?.FirstOrDefault()
        );

        // Add rich context if provided
        if (humanExplanation != null || hint != null || suggestions != null)
        {
            error = error with
            {
                HumanExplanation = humanExplanation,
                ContextualHint = hint,
                Suggestions = suggestions,
                DocsUrl = $"https://docs.n-sharp.dev/errors/NL{(int)code:D3}"
            };
        }

        _errors.Add(error);
        _panicMode = true;
    }

    /// <summary>
    /// Check if a token type is a keyword that starts a top-level declaration.
    /// These tokens cannot appear as statements inside a function body (unlike 'func'
    /// which can start a local function).
    /// </summary>
    private static bool IsTypeDeclarationKeyword(TokenType type)
    {
        return type == TokenType.Class || type == TokenType.Struct ||
               type == TokenType.Record || type == TokenType.Interface ||
               type == TokenType.Union || type == TokenType.Enum ||
               type == TokenType.Type;
    }

    /// <summary>
    /// Check if current token starts a declaration keyword (includes func, modifiers, attributes).
    /// Used for synchronization when recovering from errors.
    /// </summary>
    private static bool IsDeclarationKeyword(TokenType type)
    {
        return type == TokenType.Func || IsTypeDeclarationKeyword(type) ||
               type == TokenType.Test || type == TokenType.Implicit || type == TokenType.Explicit ||
               type == TokenType.Duck;
    }

    /// <summary>
    /// Check if a token type is a modifier keyword that can precede declarations.
    /// </summary>
    private static bool IsModifierKeyword(TokenType type)
    {
        return type == TokenType.Static || type == TokenType.Internal ||
               type == TokenType.Protected || type == TokenType.Virtual ||
               type == TokenType.Override || type == TokenType.Abstract ||
               type == TokenType.Sealed || type == TokenType.Readonly ||
               type == TokenType.Partial || type == TokenType.Async ||
               type == TokenType.File;
    }

    /// <summary>
    /// Check if a token type starts a statement (used for statement-level synchronization).
    /// </summary>
    private static bool IsStatementStartKeyword(TokenType type)
    {
        return type == TokenType.Let || type == TokenType.Const ||
               type == TokenType.Readonly || type == TokenType.If ||
               type == TokenType.For || type == TokenType.Foreach ||
               type == TokenType.While || type == TokenType.Return ||
               type == TokenType.Yield || type == TokenType.Break ||
               type == TokenType.Continue || type == TokenType.Throw ||
               type == TokenType.Try || type == TokenType.Using ||
               type == TokenType.Lock || type == TokenType.Switch ||
               type == TokenType.Print || type == TokenType.Assert ||
               type == TokenType.Func || type == TokenType.Semicolon ||
               type == TokenType.LeftBrace;
    }

    private static bool IsExpressionTerminator(TokenType type)
    {
        return type == TokenType.RightBrace ||
               type == TokenType.RightParen ||
               type == TokenType.RightBracket ||
               type == TokenType.Comma ||
               type == TokenType.Semicolon ||
               type == TokenType.Eof;
    }

    private bool IsMissingOperandBoundary(Token operatorToken)
    {
        if (IsAtEnd() || IsExpressionTerminator(Current.Type))
            return true;

        if (Current.Line <= operatorToken.Line)
            return false;

        if (IsStatementStartKeyword(Current.Type) ||
            IsDeclarationKeyword(Current.Type) ||
            IsModifierKeyword(Current.Type))
        {
            return true;
        }

        return _currentRecoveryBoundaryColumn.HasValue &&
               Current.Column <= _currentRecoveryBoundaryColumn.Value;
    }

    private bool IsContinuationRecoveryBoundary(Token openingToken)
    {
        if (Current.Line <= openingToken.Line)
            return false;

        if (IsStatementStartKeyword(Current.Type) ||
            IsDeclarationKeyword(Current.Type) ||
            IsModifierKeyword(Current.Type))
        {
            return true;
        }

        return _currentRecoveryBoundaryColumn.HasValue &&
               Current.Column <= _currentRecoveryBoundaryColumn.Value;
    }

    private bool ShouldSkipUnexpectedExpressionToken()
    {
        if (IsAtEnd() || IsExpressionTerminator(Current.Type))
            return false;

        if (IsStatementStartKeyword(Current.Type) ||
            IsDeclarationKeyword(Current.Type) ||
            IsModifierKeyword(Current.Type))
        {
            return false;
        }

        return true;
    }

    /// <summary>
    /// Check if the parser is at a position that looks like the start of a top-level
    /// or class-level declaration. This is used inside ParseBlock to detect missing '}'.
    /// Only checks for type declarations (class, struct, etc.) since 'func' could be a
    /// local function inside a block.
    /// </summary>
    private bool IsBlockClosingDeclarationStart()
    {
        // Direct type declaration keywords
        if (IsTypeDeclarationKeyword(Current.Type))
            return true;

        // 'duck interface' declaration
        if (Current.Type == TokenType.Duck && LookAhead(1).Type == TokenType.Interface)
            return true;

        // 'test' keyword (contextual)
        if (Current.Type == TokenType.Test ||
            (Current.Type == TokenType.Identifier && Current.Value == "test" &&
             LookAhead(1).Type == TokenType.StringLiteral))
            return true;

        // Modifier(s) followed by a type declaration keyword
        if (IsModifierKeyword(Current.Type))
        {
            var ahead = 1;
            while (_position + ahead < _tokens.Count &&
                   IsModifierKeyword(_tokens[_position + ahead].Type))
            {
                ahead++;
            }
            if (_position + ahead < _tokens.Count &&
                IsTypeDeclarationKeyword(_tokens[_position + ahead].Type))
                return true;
        }

        // '[' (attribute) followed eventually by a type declaration keyword
        if (Current.Type == TokenType.LeftBracket)
        {
            // Look ahead past the attribute to see if a type keyword follows
            var ahead = 1;
            var depth = 1;
            while (_position + ahead < _tokens.Count && depth > 0)
            {
                if (_tokens[_position + ahead].Type == TokenType.LeftBracket) depth++;
                else if (_tokens[_position + ahead].Type == TokenType.RightBracket) depth--;
                ahead++;
            }
            // Skip modifiers after attribute
            while (_position + ahead < _tokens.Count &&
                   IsModifierKeyword(_tokens[_position + ahead].Type))
            {
                ahead++;
            }
            if (_position + ahead < _tokens.Count &&
                IsTypeDeclarationKeyword(_tokens[_position + ahead].Type))
                return true;
        }

        return false;
    }

    /// <summary>
    /// Synchronize to the next top-level declaration boundary after an error.
    /// Skips tokens until finding a declaration keyword or EOF.
    /// </summary>
    private void SynchronizeToNextDeclaration()
    {
        _panicMode = false;
        _splitGreaterDepth = 0;

        while (!IsAtEnd())
        {
            // Declaration keywords
            if (IsDeclarationKeyword(Current.Type))
                return;

            // Modifier keywords that might precede a declaration
            if (IsModifierKeyword(Current.Type))
            {
                // Look ahead to see if this is really a declaration
                var ahead = 1;
                while (_position + ahead < _tokens.Count &&
                       IsModifierKeyword(_tokens[_position + ahead].Type))
                    ahead++;
                if (_position + ahead < _tokens.Count &&
                    IsDeclarationKeyword(_tokens[_position + ahead].Type))
                    return;
            }

            // Attribute that might precede a declaration
            if (Current.Type == TokenType.LeftBracket)
                return;

            // 'test' contextual keyword
            if (Current.Type == TokenType.Identifier && Current.Value == "test")
                return;

            Advance();
        }
    }

    /// <summary>
    /// Synchronize to the next statement boundary after an error inside a block.
    /// Skips tokens until finding a statement keyword, closing brace, or declaration keyword.
    /// </summary>
    private void SynchronizeToNextStatement()
    {
        _panicMode = false;
        _splitGreaterDepth = 0;

        while (!IsAtEnd())
        {
            // Closing brace ends the block - let caller handle it
            if (Check(TokenType.RightBrace))
                return;

            // Statement-starting keywords
            if (IsStatementStartKeyword(Current.Type))
                return;

            // Type declaration keywords signal missing } (handled by caller)
            if (IsTypeDeclarationKeyword(Current.Type))
                return;

            Advance();
        }
    }

    /// <summary>
    /// Get source code snippet for a given line
    /// </summary>
    private string? GetSourceSnippet(int line)
    {
        if (_sourceLines == null || line < 1 || line > _sourceLines.Length)
            return null;
        return _sourceLines[line - 1];
    }
}
