using System;
using System.Collections.Generic;
using System.Linq;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

public class Parser
{
    private readonly List<Token> _tokens;
    private readonly string? _fileName;
    private int _position;

    public Parser(List<Token> tokens, string? fileName = null)
    {
        _tokens = tokens.Where(t => t.Type != TokenType.Newline).ToList();
        _fileName = fileName;
    }

    public CompilationUnit ParseCompilationUnit()
    {
        var line = Current.Line;
        var column = Current.Column;

        // Parse namespace (optional, file-scoped)
        NamespaceDeclaration? namespaceDecl = null;
        if (Check(TokenType.Namespace))
        {
            namespaceDecl = ParseNamespace();
        }

        // Parse using directives
        var usings = new List<UsingDirective>();
        while (Check(TokenType.Using))
        {
            usings.Add(ParseUsing());
        }

        // Parse import statements
        var imports = new List<Statement>();
        while (Check(TokenType.Import))
        {
            imports.Add(ParseImport());
        }

        // Parse top-level declarations
        var declarations = new List<Declaration>();
        while (!IsAtEnd())
        {
            declarations.Add(ParseDeclaration());
        }

        return new CompilationUnit(namespaceDecl, usings, imports, declarations, line, column);
    }

    private NamespaceDeclaration ParseNamespace()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Namespace, "Expected 'namespace'");
        var name = ParseQualifiedName();
        return new NamespaceDeclaration(name, line, column);
    }

    private UsingDirective ParseUsing()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Using, "Expected 'using'");

        // Check for alias
        if (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Assign)
        {
            var alias = Advance().Value;
            Consume(TokenType.Assign, "Expected '='");
            var ns = ParseQualifiedName();
            return new UsingDirective(ns, alias, line, column);
        }

        var namespaceName = ParseQualifiedName();
        return new UsingDirective(namespaceName, null, line, column);
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
        var namespaceName = ParseQualifiedName();
        string? nsAlias = null;

        if (Check(TokenType.As))
        {
            Advance();
            nsAlias = ConsumeIdentifier("Expected alias name after 'as'");
        }

        return new NamespaceImport(namespaceName, nsAlias, line, column);
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
        // Test declarations don't have attributes or modifiers
        if (Check(TokenType.Test))
            return ParseTestDeclaration();

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

        throw new Exception($"Unexpected token '{Current.Value}' at {Current.Line}:{Current.Column}");
    }

    private List<AttributeNode> ParseAttributes()
    {
        var attributes = new List<AttributeNode>();
        while (Check(TokenType.LeftBracket))
        {
            Advance();
            var name = ConsumeIdentifier("Expected attribute name");
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
            else if (Check(TokenType.Readonly))
            {
                modifiers |= Modifiers.Readonly;
                Advance();
            }
            else if (Check(TokenType.Async))
            {
                modifiers |= Modifiers.Async;
                Advance();
            }
            else if (Check(TokenType.Required))
            {
                modifiers |= Modifiers.Required;
                Advance();
            }
            else if (Check(TokenType.Init))
            {
                modifiers |= Modifiers.Init;
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
        Consume(TokenType.Func, "Expected 'func'");

        if (Check(TokenType.Star))
        {
            modifiers |= Modifiers.Generator;
            Advance();
        }

        // Check for operator overloading: func operator +
        bool isOperatorOverload = false;
        string? operatorSymbol = null;
        string name;

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

        var typeParams = ParseTypeParameters();
        var parameters = ParseParameterList();

        TypeReference? returnType = null;
        if (Check(TokenType.Colon))
        {
            Advance();
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

        return new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParams, constraints, modifiers, attributes, isOperatorOverload, operatorSymbol, line, column);
    }

    private TestDeclaration ParseTestDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Test, "Expected 'test'");

        // Test description must be a string literal
        if (Current.Type != TokenType.StringLiteral)
            throw new Exception($"Expected string literal for test description at {Current.Line}:{Current.Column}");

        var description = Current.Value.Trim('"'); // Remove quotes
        Advance();

        // Parse test body
        var body = ParseBlock();

        return new TestDeclaration(description, body, line, column);
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

                parameters.Add(new Parameter(paramName, paramType, defaultValue, isThis, modifier));
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

            var constraintTypes = new List<TypeReference> { ParseTypeReference() };
            while (Match(TokenType.Comma))
            {
                constraintTypes.Add(ParseTypeReference());
            }

            constraints.Add(new GenericConstraint(typeParam, constraintTypes));
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
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            members.Add(ParseMemberDeclaration());
        }

        Consume(TokenType.RightBrace, "Expected '}'");

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
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            members.Add(ParseMemberDeclaration());
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new StructDeclaration(name, typeParams, interfaces, members, primaryCtorParams, modifiers, attributes, line, column);
    }

    private RecordDeclaration ParseRecordDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Record, "Expected 'record'");

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
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            members.Add(ParseMemberDeclaration());
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new RecordDeclaration(name, typeParams, interfaces, members, primaryCtorParams, modifiers, attributes, line, column);
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
        var members = new List<Declaration>();

        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            members.Add(ParseMemberDeclaration());
        }

        Consume(TokenType.RightBrace, "Expected '}'");

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
            var caseName = ConsumeIdentifier("Expected union case name");
            List<UnionCaseProperty>? properties = null;

            if (Check(TokenType.LeftBrace))
            {
                Advance();
                properties = new List<UnionCaseProperty>();

                while (!Check(TokenType.RightBrace))
                {
                    var propName = ConsumeIdentifier("Expected property name");
                    Consume(TokenType.Colon, "Expected ':'");
                    var propType = ParseTypeReference();
                    properties.Add(new UnionCaseProperty(propName, propType));

                    if (!Check(TokenType.RightBrace))
                        Match(TokenType.Comma);
                }

                Consume(TokenType.RightBrace, "Expected '}'");
            }

            cases.Add(new UnionCase(caseName, properties));
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new UnionDeclaration(name, cases, modifiers, attributes, line, column);
    }

    private EnumDeclaration ParseEnumDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Enum, "Expected 'enum'");

        var name = ConsumeIdentifier("Expected enum name");

        Consume(TokenType.LeftBrace, "Expected '{'");
        var members = new List<EnumMember>();
        var enumType = EnumType.Int; // Default to int, will infer from first value

        if (!Check(TokenType.RightBrace))
        {
            do
            {
                var memberName = ConsumeIdentifier("Expected enum member name");
                Expression? value = null;

                if (Check(TokenType.Assign))
                {
                    Advance();
                    value = ParseExpression();

                    // Infer enum type from first assigned value
                    if (members.Count == 0 && value is StringLiteralExpression)
                    {
                        enumType = EnumType.String;
                    }
                }

                members.Add(new EnumMember(memberName, value));

                if (Check(TokenType.Comma))
                    Advance();
                else
                    break;
            } while (!Check(TokenType.RightBrace) && !IsAtEnd());
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new EnumDeclaration(name, members, enumType, modifiers, attributes, line, column);
    }

    private TypeAliasDeclaration ParseTypeAliasDeclaration()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Type, "Expected 'type'");

        var name = ConsumeIdentifier("Expected type alias name");
        Consume(TokenType.Assign, "Expected '='");
        var type = ParseTypeReference();

        return new TypeAliasDeclaration(name, type, line, column);
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

        // Function
        if (Check(TokenType.Func))
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
                    baseLine,
                    baseColumn);
            }
            else
            {
                throw new Exception($"Expected 'this' or 'base' after ':' at line {Current.Line}, column {Current.Column}");
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

        while (!Check(TokenType.RightBrace))
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
                throw new Exception($"Expected 'get' or 'set', got '{accessor}'");
            }
        }

        Consume(TokenType.RightBrace, "Expected '}'");

        return new IndexerDeclaration(parameters, returnType, getBody, setBody, modifiers, attributes, line, column);
    }

    private Declaration ParseFieldDeclaration(List<AttributeNode> attributes, Modifiers modifiers)
    {
        var line = Current.Line;
        var column = Current.Column;
        var name = ConsumeIdentifier("Expected field name");

        Consume(TokenType.Colon, "Expected ':'");
        var type = ParseTypeReference();

        // Check for expression-bodied property: name: type => expr
        if (Check(TokenType.Arrow))
        {
            Advance();
            var expressionBody = ParseExpression();
            return new PropertyDeclaration(name, type, null, null, expressionBody, modifiers, attributes, line, column);
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
                        throw new Exception($"Expected 'get' or 'set', got '{accessor}' at line {Current.Line}");
                    }
                }
                else
                {
                    throw new Exception($"Expected accessor (get/set) at line {Current.Line}");
                }
            }

            Consume(TokenType.RightBrace, "Expected '}' after property accessors");
            return new PropertyDeclaration(name, type, getBody, setBody, null, modifiers, attributes, line, column);
        }

        // Otherwise it's a field
        Expression? initializer = null;
        if (Check(TokenType.Assign))
        {
            Advance();
            initializer = ParseExpression();
        }

        return new FieldDeclaration(name, type, initializer, modifiers, attributes, line, column);
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

            Consume(TokenType.Greater, "Expected '>'");
            return new GenericTypeReference(name, typeArgs);
        }

        return new SimpleTypeReference(name);
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

    private BlockStatement ParseBlock()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.LeftBrace, "Expected '{'");

        var statements = new List<Statement>();
        while (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            statements.Add(ParseStatement());
        }

        Consume(TokenType.RightBrace, "Expected '}'");
        return new BlockStatement(statements, line, column);
    }

    private Statement ParseStatement()
    {
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

        // Expression statement (or shorthand declaration with :=)
        return ParseExpressionStatement();
    }

    private AssertStatement ParseAssertStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Assert, "Expected 'assert'");

        var condition = ParseExpression();

        return new AssertStatement(condition, line, column);
    }

    private Statement ParseVariableDeclaration(VariableKind kind)
    {
        var line = Current.Line;
        var column = Current.Column;
        Advance(); // consume let/const/readonly

        // Check if this is a tuple deconstruction: (x, y) := ...
        if (Check(TokenType.LeftParen))
        {
            return ParseTupleDeconstruction(kind, line, column);
        }

        var name = ConsumeIdentifier("Expected variable name");

        TypeReference? type = null;
        if (Check(TokenType.Colon))
        {
            Advance();
            type = ParseTypeReference();
        }

        Expression? initializer = null;
        if (Check(TokenType.Assign))
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
            throw new Exception($"Tuple deconstruction requires ':=' or '=' at line {Current.Line}");
        }

        Advance(); // consume := or =

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
        if (!Check(TokenType.LeftBrace))
        {
            iterator = ParseExpression();
        }

        var forBody = ParseStatement();

        return new ForStatement(initializer, condition, iterator, forBody, line, column);
    }

    private ForeachStatement ParseForeachStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Foreach, "Expected 'foreach'");

        var varName = ConsumeIdentifier("Expected variable name");
        Consume(TokenType.In, "Expected 'in'");
        var collection = ParseExpression();
        var body = ParseStatement();

        return new ForeachStatement(varName, collection, body, line, column);
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
        if (!Check(TokenType.RightBrace) && !IsAtEnd())
        {
            value = ParseExpression();
        }

        return new ReturnStatement(value, line, column);
    }

    private YieldStatement ParseYieldStatement()
    {
        var line = Current.Line;
        var column = Current.Column;
        Consume(TokenType.Yield, "Expected 'yield'");

        var value = ParseExpression();
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
                decl = stmt as VariableDeclarationStatement ?? throw new Exception("Expected variable declaration, not tuple deconstruction");
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

        var body = ParseBlock() as BlockStatement
            ?? throw new Exception("Expected block statement after lock");

        return new LockStatement(lockObject, body, line, column);
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
                throw new Exception($"Expected 'case' or 'default' at {Current.Line}:{Current.Column}");
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

            cases.Add(new SwitchCase(pattern, statements));
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

        throw new Exception($"Invalid pattern at {line}:{column}");
    }

    private List<PropertyPattern> ParsePropertyPatterns()
    {
        Consume(TokenType.LeftBrace, "Expected '{'");
        var props = new List<PropertyPattern>();

        while (!Check(TokenType.RightBrace))
        {
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
        }

        Consume(TokenType.RightBrace, "Expected '}'");
        return props;
    }

    private Statement ParseExpressionStatement()
    {
        var line = Current.Line;
        var column = Current.Column;

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
            var op = Current.Type switch
            {
                TokenType.Assign => AssignmentOperator.Assign,
                TokenType.PlusAssign => AssignmentOperator.AddAssign,
                TokenType.MinusAssign => AssignmentOperator.SubtractAssign,
                TokenType.StarAssign => AssignmentOperator.MultiplyAssign,
                TokenType.SlashAssign => AssignmentOperator.DivideAssign,
                TokenType.QuestionQuestionAssign => AssignmentOperator.NullCoalesceAssign,
                _ => throw new Exception("Invalid assignment operator")
            };

            var opToken = Advance();
            var right = ParseAssignmentExpression();
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
                var op = Current.Type switch
                {
                    TokenType.Less => BinaryOperator.Less,
                    TokenType.LessEqual => BinaryOperator.LessOrEqual,
                    TokenType.Greater => BinaryOperator.Greater,
                    TokenType.GreaterEqual => BinaryOperator.GreaterOrEqual,
                    _ => throw new Exception("Invalid relational operator")
                };

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
            var op = Current.Type switch
            {
                TokenType.Star => BinaryOperator.Multiply,
                TokenType.Slash => BinaryOperator.Divide,
                TokenType.Percent => BinaryOperator.Modulo,
                _ => throw new Exception("Invalid multiplicative operator")
            };

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
            var op = Current.Type switch
            {
                TokenType.Not => UnaryOperator.Not,
                TokenType.Minus => UnaryOperator.Negate,
                TokenType.BitwiseNot => UnaryOperator.BitwiseNot,
                TokenType.Increment => UnaryOperator.PreIncrement,
                TokenType.Decrement => UnaryOperator.PreDecrement,
                TokenType.BitwiseXor => UnaryOperator.IndexFromEnd,  // ^ as prefix for index from end
                _ => throw new Exception("Invalid unary operator")
            };

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
                var memberName = ConsumeIdentifier("Expected member name");
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
            else if (Check(TokenType.LeftParen))
            {
                var parenToken = Advance();
                var args = ParseArgumentList();
                expr = new CallExpression(expr, args, parenToken.Line, parenToken.Column);
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

                while (!Check(TokenType.RightBrace))
                {
                    var propName = ConsumeIdentifier("Expected property name");
                    Consume(TokenType.Colon, "Expected ':'");
                    var propValue = ParseExpression();
                    props.Add(new PropertyInitializer(propName, propValue));

                    if (!Check(TokenType.RightBrace))
                        Match(TokenType.Comma);
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

                    if (Check(TokenType.Identifier) && Current.Value == "var")
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

                var argValue = ParseExpression();
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
            return new StringLiteralExpression(Advance().Value, line, column);

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

        throw new Exception($"Unexpected token '{Current.Value}' at {line}:{column}");
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
            Advance();
            var props = new List<PropertyInitializer>();

            while (!Check(TokenType.RightBrace))
            {
                var propName = ConsumeIdentifier("Expected property name");
                Consume(TokenType.Colon, "Expected ':'");
                var propValue = ParseExpression();
                props.Add(new PropertyInitializer(propName, propValue));

                if (!Check(TokenType.RightBrace))
                    Match(TokenType.Comma);
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
        if (Check(TokenType.Colon))
        {
            Advance();
            var firstValue = ParseExpression();
            var elements = new List<TupleElement>
            {
                new TupleElement(((IdentifierExpression)firstExpr).Name, firstValue)
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
        return firstExpr;
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
                return true;

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
        var symbol = token.Type switch
        {
            TokenType.Plus => "+",
            TokenType.Minus => "-",
            TokenType.Star => "*",
            TokenType.Slash => "/",
            TokenType.Percent => "%",
            TokenType.Equal => "==",
            TokenType.NotEqual => "!=",
            TokenType.Less => "<",
            TokenType.LessEqual => "<=",
            TokenType.Greater => ">",
            TokenType.GreaterEqual => ">=",
            TokenType.Not => "!",
            TokenType.BitwiseNot => "~",
            TokenType.BitwiseAnd => "&",
            TokenType.BitwiseOr => "|",
            TokenType.BitwiseXor => "^",
            TokenType.LeftShift => "<<",
            TokenType.RightShift => ">>",
            TokenType.Increment => "++",
            TokenType.Decrement => "--",
            TokenType.True => "true",
            TokenType.False => "false",
            _ => throw new Exception($"Invalid operator symbol '{token.Value}' at {token.Line}:{token.Column}")
        };

        Advance();
        return symbol;
    }

    // Helper methods
    private Token Current => _position < _tokens.Count ? _tokens[_position] : _tokens[^1];

    private bool IsAtEnd() => Current.Type == TokenType.Eof;

    private Token Advance()
    {
        if (!IsAtEnd())
            _position++;
        return _tokens[_position - 1];
    }

    private bool Check(TokenType type) => Current.Type == type;

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
            throw new Exception($"{message}. Got '{Current.Value}' at {Current.Line}:{Current.Column}");
        Advance();
    }

    private string ConsumeIdentifier(string message)
    {
        if (!Check(TokenType.Identifier))
            throw new Exception($"{message}. Got '{Current.Value}' at {Current.Line}:{Current.Column}");
        return Advance().Value;
    }
}
