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

            // Parse import directives (both namespace and file imports)
            var imports = new List<ImportDirective>();
            var fileImports = new List<Statement>();
            while (Check(TokenType.Import))
            {
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

            // Parse package declaration (optional)
            PackageDeclaration? packageDecl = null;
            if (Check(TokenType.Package))
            {
                packageDecl = ParsePackage();
            }

            // Parse top-level declarations with error recovery
            var declarations = new List<Declaration>();
            while (!IsAtEnd())
            {
                _panicMode = false; // Reset at each declaration boundary
                var startPosition = _position;

                try
                {
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

            return new FileImport(path, alias, line, column);
        }

        // Namespace import: import System.Collections.Generic [as Alias]
        // OR: import Alias = System.Collections.Generic (C# style)

        // Check for C# style alias: import Alias = Namespace
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Assign)
        {
            var alias = ConsumeIdentifier("Expected identifier");
            Consume(TokenType.Assign, "Expected '='");
            var namespaceName = ParseQualifiedName();
            return new NamespaceImport(namespaceName, alias, line, column);
        }

        // Normal namespace import with optional 'as' alias
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
            if (Check(TokenType.Static))
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
        string name;

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

            // Check for async: func async or func async* (async iterator)
            if (Check(TokenType.Async))
            {
                modifiers |= Modifiers.Async;
                Advance();

                // Check for async iterator: func async*
                if (Check(TokenType.Star))
                {
                    modifiers |= Modifiers.Generator;
                    Advance();
                }
            }

            if (Check(TokenType.Operator))
            {
                isOperatorOverload = true;
                Advance(); // consume 'operator'

                // Get the operator symbol
                operatorSymbol = ParseOperatorSymbol();
                name = "operator " + operatorSymbol; // For error reporting
            }
            else
            {
                name = ConsumeIdentifier("Expected function name");
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
            body = ParseBlock();
        }

        return new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParams, constraints, modifiers, attributes, isOperatorOverload, operatorSymbol, isConversionOperator, isImplicitConversion, line, column);
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
        var body = ParseBlock();

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
        var body = ParseBlock();
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
        var body = ParseBlock();
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

                var paramName = ConsumeIdentifier("Expected parameter name");
                Consume(TokenType.Colon, "Expected ':' after parameter name");
                var paramType = ParseTypeReference();

                Expression? defaultValue = null;
                if (Check(TokenType.Assign))
                {
                    Advance();
                    defaultValue = ParseExpression();
                }

                parameters.Add(new Parameter(paramName, paramType, defaultValue, isThis, modifier,
                    attributes.Count > 0 ? attributes : null));
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightParen, "Expected ')'");
        return parameters;
    }

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

            do
            {
                if (Check(TokenType.Class))
                {
                    Advance();
                    specialConstraints |= SpecialConstraintKind.Class;
                }
                else if (Check(TokenType.Struct))
                {
                    Advance();
                    specialConstraints |= SpecialConstraintKind.Struct;
                }
                else if (Check(TokenType.New) && LookAhead(1).Type == TokenType.LeftParen)
                {
                    Advance(); // consume 'new'
                    Advance(); // consume '('
                    Consume(TokenType.RightParen, "Expected ')' after 'new('");
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
                ReportError(
                    ErrorCode.InvalidSyntax,
                    "Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "A type parameter cannot be both a reference type (class) and a value type (struct) at the same time."
                );
            }

            // Validate: struct implies new(), so combining them is redundant and illegal in C#
            if (specialConstraints.HasFlag(SpecialConstraintKind.Struct) &&
                specialConstraints.HasFlag(SpecialConstraintKind.New))
            {
                ReportError(
                    ErrorCode.InvalidSyntax,
                    "Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor",
                    Current.Line,
                    Current.Column,
                    humanExplanation: "The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in C#."
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

        var name = ConsumeIdentifier("Expected class name");
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
        var members = ParseMemberList(line, column);

        return new ClassDeclaration(name, typeParams, baseClass, interfaces, members, primaryCtorParams, modifiers, attributes, line, column);
    }

    private StructDeclaration ParseStructDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Struct, "Expected 'struct'");

        var name = ConsumeIdentifier("Expected struct name");
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
        var members = ParseMemberList(line, column);

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

        var name = ConsumeIdentifier("Expected record name");
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
        var members = ParseMemberList(line, column);

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
        var name = ConsumeIdentifier("Expected interface name");
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
        var members = ParseMemberList(line, column);

        return new InterfaceDeclaration(name, typeParams, baseInterfaces, members, modifiers, isDuck, attributes, line, column);
    }

    private UnionDeclaration ParseUnionDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Union, "Expected 'union'");

        var name = ConsumeIdentifier("Expected union name");

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

        return new UnionDeclaration(name, cases, modifiers, attributes, line, column);
    }

    private EnumDeclaration ParseEnumDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Enum, "Expected 'enum'");

        var name = ConsumeIdentifier("Expected enum name");

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
    /// Assumes the opening '{' has already been consumed. The openLine/openColumn parameters
    /// indicate where the opening brace was for error reporting.
    /// </summary>
    private List<Declaration> ParseMemberList(int openLine = 0, int openColumn = 0)
    {
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            _panicMode = false; // Reset at each member boundary
            var startPosition = _position;
            members.Add(ParseMemberDeclaration());

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
        else if (IsAtEnd() && openLine > 0)
        {
            ReportError(
                ErrorCode.MissingClosingBrace,
                "Missing closing '}'",
                openLine,
                openColumn,
                humanExplanation: $"The type body that started on line {openLine} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this type declaration.",
                length: 1
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

        var body = ParseBlock();

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
                var paramName = ConsumeIdentifier("Expected parameter name");
                Consume(TokenType.Colon, "Expected ':'");
                var paramType = ParseTypeReference();
                parameters.Add(new Parameter(paramName, paramType, null, false));
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
            var accessor = ConsumeIdentifier("Expected 'get' or 'set'");

            if (accessor == "get")
            {
                getBody = ParseBlock();
            }
            else if (accessor == "set")
            {
                setBody = ParseBlock();
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
        Consume(TokenType.Colon, "Expected ':' or ':='");
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
                    var accessor = Current.Value;
                    Advance();

                    if (accessor == "get")
                    {
                        getBody = ParseBlock();
                    }
                    else if (accessor == "set")
                    {
                        setBody = ParseBlock();
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
            Advance();
            initializer = ParseExpression();
        }

        return new FieldDeclaration(name, type, initializer, modifiers, propertyModifier, attributes, line, column);
    }

    private TypeReference ParseTypeReference()
    {
        var baseType = ParseBaseTypeReference();

        // Array type
        // Only treat '[' as array if it's followed by ']' (not an attribute)
        while (Check(TokenType.LeftBracket) && LookAhead(1).Type == TokenType.RightBracket)
        {
            Advance();
            Consume(TokenType.RightBracket, "Expected ']'");
            baseType = new ArrayTypeReference(baseType);
        }

        // Nullable type
        if (Check(TokenType.Question))
        {
            Advance();
            baseType = new NullableTypeReference(baseType);
        }

        return baseType;
    }

    private TypeReference ParseBaseTypeReference()
    {
        // Tuple type
        if (Check(TokenType.LeftParen))
        {
            return ParseTupleTypeReference();
        }

        // Func<> type
        if (Check(TokenType.Identifier) && Current.Value == "Func")
        {
            return ParseFunctionTypeReference();
        }

        // Simple or generic type (possibly qualified with dots like Result.Success)
        var typeNameLine = Current.Line;
        var typeNameColumn = Current.Column;
        var name = ConsumeIdentifier("Expected type name");

        // Support qualified names like Result.Success
        while (Check(TokenType.Dot))
        {
            Advance();
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

            ConsumeGreater("Expected '>'");
            return new GenericTypeReference(name, typeArgs);
        }

        return new SimpleTypeReference(name, typeNameLine, typeNameColumn);
    }

    private TupleTypeReference ParseTupleTypeReference()
    {
        Consume(TokenType.LeftParen, "Expected '('");
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

        Consume(TokenType.RightParen, "Expected ')'");
        return new TupleTypeReference(elements);
    }

    private FunctionTypeReference ParseFunctionTypeReference()
    {
        Consume(TokenType.Identifier, "Expected 'Func'");
        Consume(TokenType.Less, "Expected '<'");

        var paramTypes = new List<TypeReference>();
        var returnType = ParseTypeReference();

        while (Match(TokenType.Comma))
        {
            paramTypes.Add(returnType);
            returnType = ParseTypeReference();
        }

        Consume(TokenType.Greater, "Expected '>'");

        // Last type is return type, rest are parameters
        return new FunctionTypeReference(paramTypes, returnType);
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
    private void ConsumeGreater(string message)
    {
        if (Check(TokenType.Greater))
        {
            Advance();
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
        }
    }

    // Track when we split >> into > >
    private int _splitGreaterDepth = 0;

    private BlockStatement ParseBlock()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftBrace, "Expected '{'");

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
                    line,
                    column,
                    humanExplanation: $"The block that started on line {line} appears to be missing its closing brace. " +
                                     $"I found '{Current.Value}' on line {Current.Line}, which looks like a new declaration.",
                    hint: "Add a '}' before this declaration to close the previous block.",
                    length: 1
                );
                // Don't advance - let the outer loop parse this as a new declaration
                break;
            }

            _panicMode = false; // Reset at each statement boundary
            var startPosition = _position;
            statements.Add(ParseStatement());

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
                line,
                column,
                humanExplanation: $"The block that started on line {line} is missing its closing brace. I reached the end of the file without finding it.",
                hint: "Add a '}' to close this block.",
                length: 1
            );
        }

        return new BlockStatement(statements, line, column);
    }

    private Statement ParseStatement()
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
            return ParseBlock();

        // Local function (C# 7): [static] func Name(...) { }
        if (Check(TokenType.Static) && LookAhead(1).Type == TokenType.Func)
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
        Consume(TokenType.Assert, "Expected 'assert'");

        // Check for assert throws ExceptionType { body }
        if (Current.Type == TokenType.Identifier && Current.Value == "throws")
        {
            Advance(); // consume 'throws'
            var exceptionType = ParseTypeReference();
            var body = ParseBlock();
            return new AssertThrowsStatement(exceptionType, body, line, column);
        }

        var condition = ParseExpression();

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

        // Handle optional 'static' modifier for local functions
        Modifiers modifiers = Modifiers.None;
        if (Check(TokenType.Static))
        {
            modifiers |= Modifiers.Static;
            Advance();
        }

        Consume(TokenType.Func, "Expected 'func'");

        // Check for generator: func*
        if (Check(TokenType.Star))
        {
            modifiers |= Modifiers.Generator;
            Advance();
        }

        // Check for async: func async
        if (Check(TokenType.Async))
        {
            modifiers |= Modifiers.Async;
            Advance();
        }

        var name = ConsumeIdentifier("Expected function name");
        var typeParams = ParseTypeParameters();
        var parameters = ParseParameterList();

        TypeReference? returnType = null;
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
            body = ParseBlock();
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
            Advance();
            initializer = ParseExpression();
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

        if (Check(TokenType.ColonAssign) || Check(TokenType.Assign))
        {
            Advance(); // consume := or =
        }

        var initializer = ParseExpression();

        return new TupleDeconstructionStatement(names, initializer, kind, line, column);
    }

    private IfStatement ParseIfStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.If, "Expected 'if'");

        var condition = ParseExpression();
        var thenStatement = ParseStatement();

        Statement? elseStatement = null;
        if (Check(TokenType.Else))
        {
            Advance();
            elseStatement = ParseStatement();
        }

        return new IfStatement(condition, thenStatement, elseStatement, line, column);
    }

    private ForStatement ParseForStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.For, "Expected 'for'");

        // Check for foreach-style: for item in collection
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.In)
        {
            var varName = Advance().Value;
            Consume(TokenType.In, "Expected 'in'");
            var collection = ParseExpression();
            var body = ParseStatement();
            return new ForStatement(null, null, null,
                new ForeachStatement(varName, collection, body, line, column), line, column);
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
                var initLine = Current.Line;
                var initCol = Current.Column;
                var expr = ParseExpression();

                // Check for := shorthand declaration
                if (expr is IdentifierExpression ident && Check(TokenType.ColonAssign))
                {
                    Advance();
                    var init = ParseExpression();
                    initializer = new VariableDeclarationStatement(ident.Name, null, init, VariableKind.Let, initLine, initCol);
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

        var forBody = ParseStatement();

        return new ForStatement(initializer, condition, iterator, forBody, line, column);
    }

    private ForeachStatement ParseForeachStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Foreach, "Expected 'foreach'");

        // Allow optional parentheses: foreach (x in y) or foreach x in y
        var hasParens = Match(TokenType.LeftParen);

        var varName = ConsumeIdentifier("Expected variable name");
        Consume(TokenType.In, "Expected 'in'");
        var collection = ParseExpression();

        if (hasParens)
        {
            Consume(TokenType.RightParen, "Expected ')' to match opening '('");
        }

        var body = ParseStatement();

        return new ForeachStatement(varName, collection, body, line, column);
    }

    private AwaitForEachStatement ParseAwaitForeachStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Await, "Expected 'await'");
        Consume(TokenType.Foreach, "Expected 'foreach'");

        // Allow optional parentheses: await foreach (x in y) or await foreach x in y
        var hasParens = Match(TokenType.LeftParen);

        var varName = ConsumeIdentifier("Expected variable name");
        Consume(TokenType.In, "Expected 'in'");
        var collection = ParseExpression();

        if (hasParens)
        {
            Consume(TokenType.RightParen, "Expected ')' to match opening '('");
        }

        var body = ParseStatement();

        return new AwaitForEachStatement(varName, collection, body, line, column);
    }

    private WhileStatement ParseWhileStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.While, "Expected 'while'");

        var condition = ParseExpression();
        var body = ParseStatement();

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
            TokenType.StringLiteral or
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
        Consume(TokenType.Yield, "Expected 'yield'");

        // Check for "yield break" (no expression)
        Expression? value = null;
        if (!Check(TokenType.Break))
        {
            value = ParseExpression();
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
        Consume(TokenType.Print, "Expected 'print'");

        var value = ParseExpression();
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
        Consume(TokenType.Throw, "Expected 'throw'");

        var expr = ParseExpression();
        return new ThrowStatement(expr, line, column);
    }

    private TryStatement ParseTryStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Try, "Expected 'try'");

        var tryBlock = ParseBlock();
        var catchClauses = new List<CatchClause>();

        while (Check(TokenType.Catch))
        {
            Advance();

            TypeReference? exceptionType = null;
            string? varName = null;

            if (Check(TokenType.LeftParen))
            {
                Advance();
                if (!Check(TokenType.RightParen))
                {
                    exceptionType = ParseTypeReference();

                    if (Check(TokenType.Identifier))
                    {
                        varName = Advance().Value;
                    }
                }
                Consume(TokenType.RightParen, "Expected ')'");
            }

            var catchBlock = ParseBlock();
            catchClauses.Add(new CatchClause(exceptionType, varName, catchBlock));
        }

        BlockStatement? finallyBlock = null;
        if (Check(TokenType.Finally))
        {
            Advance();
            finallyBlock = ParseBlock();
        }

        return new TryStatement(tryBlock, catchClauses, finallyBlock, line, column);
    }

    private UsingStatement ParseUsingStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Using, "Expected 'using'");

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
                Consume(TokenType.ColonAssign, "Expected ':='");
                var init = ParseExpression();
                decl = new VariableDeclarationStatement(varName, null, init, VariableKind.Let, line, column);
            }

            Statement? body = null;
            if (Check(TokenType.LeftBrace))
            {
                body = ParseBlock();
            }

            return new UsingStatement(decl, null, body, line, column);
        }

        // using (expr) or using expr
        var expr = ParseExpression();
        Statement? usingBody = null;

        if (Check(TokenType.LeftBrace))
        {
            usingBody = ParseBlock();
        }

        return new UsingStatement(null, expr, usingBody, line, column);
    }

    private LockStatement ParseLockStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Lock, "Expected 'lock'");

        // lock obj { ... } or lock (obj) { ... }
        var hasParens = Check(TokenType.LeftParen);
        if (hasParens)
            Consume(TokenType.LeftParen, "Expected '('");

        var lockObject = ParseExpression();

        if (hasParens)
            Consume(TokenType.RightParen, "Expected ')'");

        var bodyStmt = ParseBlock() as BlockStatement;
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
        Consume(TokenType.Switch, "Expected 'switch'");

        var value = ParseExpression();
        Consume(TokenType.LeftBrace, "Expected '{'");

        var cases = new List<SwitchCase>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            Pattern? pattern = null;
            var caseLine = Current.Line;
            var caseColumn = Current.Column;

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
                var block = ParseBlock();
                statements.AddRange(block.Statements);
            }
            else
            {
                statements.Add(ParseStatement());
            }

            cases.Add(new SwitchCase(pattern, statements, caseLine, caseColumn));
        }

        Consume(TokenType.RightBrace, "Expected '}'");

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
        if (Check(TokenType.IntLiteral) || Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) ||
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
                props.Add(new PropertyPattern(propName, pattern, null));
            }
            else
            {
                // Just property name, implicit binding: { value } -> bind property 'value' to variable 'value'
                // BindingName is null, Analyzer will use Name as binding
                props.Add(new PropertyPattern(propName, null, null));
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
                var initializer = ParseExpression();
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

                Advance(); // consume := or =
                var initializer = ParseExpression();
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
            Advance();
            var initializer = ParseExpression();
            return new VariableDeclarationStatement(ident.Name, null, initializer, VariableKind.Let, line, column);
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
            var param = Advance().Value;
            Advance(); // consume =>

            if (Check(TokenType.LeftBrace))
            {
                var body = ParseBlock();
                return new LambdaExpression(
                    new List<Parameter> { new Parameter(param, new SimpleTypeReference("var"), null, false) },
                    null, body, line, column);
            }
            else
            {
                var exprBody = ParseExpression();
                return new LambdaExpression(
                    new List<Parameter> { new Parameter(param, new SimpleTypeReference("var"), null, false) },
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
            var right = ParseLambdaOrAssignmentExpression();
            return new AssignmentExpression(expr, op, right, opToken.Line, opToken.Column);
        }

        return expr;
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
            var right = ParseLogicalOrExpression();
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
            var right = ParseLogicalAndExpression();
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
            var right = ParseBitwiseOrExpression();
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
            var right = ParseBitwiseXorExpression();
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
            var right = ParseBitwiseAndExpression();
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
            var right = ParseEqualityExpression();
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
            var right = ParseRelationalExpression();
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
                var right = ParseShiftExpression();
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
            var right = ParseAdditiveExpression();
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
            var right = ParseMultiplicativeExpression();
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
            var right = ParseRangeExpression();
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

                // If the dot is the last token on the line, the next token may be on a new line
                // (e.g. "x.\n y"), which should be treated as an incomplete member access.
                if (Current.Line != dotToken.Line)
                {
                    ReportError(
                        ErrorCode.ExpectedToken,
                        $"Expected member name. Got '{Current.Value}'",
                        dotToken.Line,
                        dotToken.Column,
                        humanExplanation: "I see a dot (.) operator but no member name after it.",
                        hint: "After a dot, I need to see a property or method name.",
                        suggestions: new List<string> {
                            "Check if you forgot to finish this line",
                            "Common members: Length, Count, ToString(), GetHashCode()",
                            "If this is end of statement, remove the trailing dot"
                        },
                        length: dotToken.Value.Length
                    );
                    memberName = "<error>";
                }
                else
                {
                    memberName = ConsumeIdentifier("Expected member name");
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

                    // Check for inline out variable declaration (C# 7+)
                    // Syntax: out var identifier  OR  out Type identifier
                    var line = Current.Line;
                    var column = Current.Column;

                    if ((Check(TokenType.Identifier) || Check(TokenType.Let)) && Current.Value == "var")
                    {
                        // out var identifier
                        Advance(); // consume 'var'
                        var varName = ConsumeIdentifier("Expected identifier after 'out var'");
                        var outVarDecl = new OutVariableDeclarationExpression(null, varName, line, column);
                        args.Add(new Argument(null, outVarDecl, modifier));
                        continue; // Skip the rest of normal argument parsing
                    }
                    else if (Check(TokenType.Identifier))
                    {
                        // Could be: out Type identifier  OR  out existingVar
                        // We need to check if next token is another identifier
                        if (LookAhead(1).Type == TokenType.Identifier)
                        {
                            // out Type identifier
                            var typeRef = ParseTypeReference();
                            var varName = ConsumeIdentifier("Expected identifier after type");
                            var outVarDecl = new OutVariableDeclarationExpression(typeRef, varName, line, column);
                            args.Add(new Argument(null, outVarDecl, modifier));
                            continue; // Skip the rest of normal argument parsing
                        }
                        // Otherwise fall through to normal expression parsing (out existingVar)
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

    private Expression ParsePrimaryExpression()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Literals
        if (Check(TokenType.IntLiteral))
            return new IntLiteralExpression(Advance().Value, line, column);

        if (Check(TokenType.FloatLiteral))
            return new FloatLiteralExpression(Advance().Value, line, column);

        if (Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral))
        {
            var token = Advance();
            if (token.Type == TokenType.StringLiteral && token.Value.StartsWith("$\""))
                return ParseInterpolatedString(token, line, column);
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

        // Return error placeholder
        return new IdentifierExpression("<error>", line, column);
    }

    private InterpolatedStringExpression ParseInterpolatedString(Token token, int line, int column)
    {
        var parts = new List<InterpolatedStringPart>();
        var value = token.Value;

        // Skip $" prefix (2 chars) and " suffix (1 char)
        int start = 2;
        int end = value.Length - 1;
        // Handle unterminated strings gracefully
        if (end < start || value[end] != '"')
            end = value.Length;

        var textBuf = new System.Text.StringBuilder();
        int textStartCol = column + start;
        int i = start;

        while (i < end)
        {
            if (value[i] == '\\' && i + 1 < end)
            {
                textBuf.Append(value[i]);
                textBuf.Append(value[i + 1]);
                i += 2;
                continue;
            }

            if (value[i] == '{')
            {
                // Emit accumulated text
                if (textBuf.Length > 0)
                {
                    parts.Add(new InterpolatedStringText(textBuf.ToString(), line, textStartCol));
                    textBuf.Clear();
                }

                // Find matching }
                int holeContentStart = i + 1;
                int braceDepth = 1;
                int j = holeContentStart;
                bool inNestedString = false;

                while (j < end && braceDepth > 0)
                {
                    if (inNestedString)
                    {
                        if (value[j] == '\\' && j + 1 < end)
                        {
                            j += 2;
                            continue;
                        }
                        if (value[j] == '"')
                            inNestedString = false;
                    }
                    else
                    {
                        if (value[j] == '"')
                            inNestedString = true;
                        else if (value[j] == '{')
                            braceDepth++;
                        else if (value[j] == '}')
                        {
                            braceDepth--;
                            if (braceDepth == 0)
                                break;
                        }
                    }
                    j++;
                }

                var exprContent = value.Substring(holeContentStart, j - holeContentStart);

                // Check for format specifier (top-level : not inside parens/brackets/strings)
                string? formatClause = null;
                int colonPos = FindFormatSpecifierColon(exprContent);
                if (colonPos >= 0)
                {
                    formatClause = exprContent.Substring(colonPos + 1);
                    exprContent = exprContent.Substring(0, colonPos);
                }

                // Sub-parse the expression
                int exprStartCol = column + holeContentStart;
                Expression expr;
                try
                {
                    var subLexer = new Lexer(exprContent);
                    var subTokens = subLexer.Tokenize();

                    // Adjust token positions to match source location
                    int colOffset = exprStartCol - 1;
                    for (int t = 0; t < subTokens.Count; t++)
                    {
                        var tok = subTokens[t];
                        subTokens[t] = new Token(tok.Type, tok.Value, line, tok.Column + colOffset, tok.FileName);
                    }

                    var subParser = new Parser(subTokens, _fileName);
                    expr = subParser.ParseExpression();

                    // Propagate errors from the sub-parser into this parser's error list
                    _errors.AddRange(subParser._errors);
                }
                catch
                {
                    // Fallback: treat as identifier
                    var trimmed = exprContent.Trim();
                    expr = new IdentifierExpression(
                        string.IsNullOrEmpty(trimmed) ? "<error>" : trimmed,
                        line, exprStartCol);
                }

                parts.Add(new InterpolatedStringHole(expr, formatClause, line, column + i));

                i = j + 1; // Skip past }
                textStartCol = column + i;
            }
            else
            {
                textBuf.Append(value[i]);
                i++;
            }
        }

        // Emit remaining text
        if (textBuf.Length > 0)
            parts.Add(new InterpolatedStringText(textBuf.ToString(), line, textStartCol));

        return new InterpolatedStringExpression(parts, line, column);
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
                    Consume(TokenType.Colon, "Expected ':'");
                    var propValue = ParseExpression();
                    props.Add(new PropertyInitializer(propName, null, propValue));
                }

                if (!Check(TokenType.RightBrace))
                    Match(TokenType.Comma);

                EnsureProgress(startPosition);
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
                var paramName = ConsumeIdentifier("Expected parameter name");
                parameters.Add(new Parameter(paramName, new SimpleTypeReference("var"), null, false));
            } while (Match(TokenType.Comma));
        }

        Consume(TokenType.RightParen, "Expected ')'");
        Consume(TokenType.Arrow, "Expected '=>'");

        if (Check(TokenType.LeftBrace))
        {
            var body = ParseBlock();
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
        var saved = _position;
        try
        {
            Advance(); // consume (

            if (!Check(TokenType.Identifier))
                return false;

            Advance();

            // Handle qualified names like Result.Success
            while (Check(TokenType.Dot))
            {
                Advance(); // consume .
                if (!Check(TokenType.Identifier))
                    return false;
                Advance(); // consume identifier
            }

            // Simple type cast: (TypeName) or (Qualified.TypeName)
            if (Check(TokenType.RightParen))
            {
                // Disambiguate from parenthesized expressions like `(x)`:
                // casts must be followed by an expression start token.
                var next = LookAhead(1).Type;
                return next is
                    TokenType.Identifier or
                    TokenType.IntLiteral or
                    TokenType.FloatLiteral or
                    TokenType.StringLiteral or
                    TokenType.True or
                    TokenType.False or
                    TokenType.Null or
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
                    TokenType.Await or
                    TokenType.Throw;
            }

            // Generic or complex type (not supported in cast check yet)
            return false;
        }
        finally
        {
            _position = saved;
        }
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

    private void Consume(TokenType type, string message)
    {
        if (!Check(type))
        {
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
            return; // Don't advance
        }
        Advance();
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
        int length = 1)
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
                DocsUrl = $"https://docs.nsharp.dev/errors/NL{(int)code:D3}"
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
