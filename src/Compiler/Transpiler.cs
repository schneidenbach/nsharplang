using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

public class Transpiler
{
    private readonly CompilationUnit _compilationUnit;
    private readonly ProjectConfig? _projectConfig;
    private readonly StringBuilder _output;
    private int _indentLevel;
    private const string IndentString = "    ";
    private string? _currentTypeName; // Track current class/struct/record for constructor names
    private bool _inInterface; // Track if we're currently inside an interface
    private List<InterfaceDeclaration> _duckInterfaces; // Track duck interfaces for automatic implementation

    public Transpiler(CompilationUnit compilationUnit, ProjectConfig? projectConfig = null)
    {
        _compilationUnit = compilationUnit;
        _projectConfig = projectConfig;
        _output = new StringBuilder();
        _indentLevel = 0;
        _duckInterfaces = new List<InterfaceDeclaration>();
    }

    public string Transpile()
    {
        _output.Clear();
        _indentLevel = 0;
        _duckInterfaces.Clear();

        // Collect all duck interfaces for automatic implementation
        _duckInterfaces = _compilationUnit.Declarations
            .OfType<InterfaceDeclaration>()
            .Where(i => i.IsDuckInterface)
            .ToList();

        // Check if we have test declarations to add Xunit using
        var hasTests = _compilationUnit.Declarations.OfType<TestDeclaration>().Any();

        // Always add System namespace (needed for Console, Exception, etc.)
        WriteLine("using System;");

        // Add Xunit using if we have test declarations
        if (hasTests)
        {
            WriteLine("using Xunit;");
        }

        // Usings
        foreach (var usingDirective in _compilationUnit.Usings)
        {
            TranspileUsing(usingDirective);
        }

        // Imports (namespace imports only - file imports are inlined)
        foreach (var import in _compilationUnit.Imports)
        {
            if (import is NamespaceImport nsImport)
            {
                TranspileNamespaceImport(nsImport);
            }
            // FileImports are not emitted - their symbols are inlined
        }

        if (_compilationUnit.Usings.Count > 0 || _compilationUnit.Imports.Count > 0 || hasTests)
            _output.AppendLine();

        // Namespace
        if (_compilationUnit.Namespace != null)
        {
            WriteLine($"namespace {_compilationUnit.Namespace.Name};");
            WriteLine();
        }

        // Separate top-level functions and tests from other declarations
        var topLevelFunctions = _compilationUnit.Declarations.OfType<FunctionDeclaration>().ToList();
        var testDeclarations = _compilationUnit.Declarations.OfType<TestDeclaration>().ToList();
        var otherDeclarations = _compilationUnit.Declarations
            .Where(d => d is not FunctionDeclaration && d is not TestDeclaration)
            .ToList();

        // Transpile non-function/non-test declarations first
        foreach (var declaration in otherDeclarations)
        {
            TranspileDeclaration(declaration);
            WriteLine();
        }

        // Wrap top-level functions in a generated internal static class
        if (topLevelFunctions.Count > 0)
        {
            var className = _compilationUnit.Namespace != null
                ? $"_{_compilationUnit.Namespace.Name.Replace(".", "_")}_TopLevel"
                : "_TopLevel";

            WriteLine($"internal static class {className}");
            WriteLine("{");
            _indentLevel++;

            foreach (var func in topLevelFunctions)
            {
                // Top-level functions are always internal static
                var originalModifiers = func.Modifiers;
                var modifiedFunc = func with { Modifiers = originalModifiers | Modifiers.Internal | Modifiers.Static };
                TranspileFunctionDeclaration(modifiedFunc);
                WriteLine();
            }

            _indentLevel--;
            WriteLine("}");
        }

        // Wrap test declarations in a public test class
        if (testDeclarations.Count > 0)
        {
            var className = _compilationUnit.Namespace != null
                ? $"{_compilationUnit.Namespace.Name.Replace(".", "_")}_Tests"
                : "Tests";

            WriteLine($"public class {className}");
            WriteLine("{");
            _indentLevel++;

            foreach (var test in testDeclarations)
            {
                TranspileTestDeclaration(test);
            }

            _indentLevel--;
            WriteLine("}");
        }

        return _output.ToString();
    }

    private void TranspileUsing(UsingDirective usingDirective)
    {
        if (usingDirective.Alias != null)
        {
            WriteLine($"using {usingDirective.Alias} = {usingDirective.Namespace};");
        }
        else
        {
            WriteLine($"using {usingDirective.Namespace};");
        }
    }

    private void TranspileNamespaceImport(NamespaceImport import)
    {
        // Namespace imports transpile to C# using statements
        if (import.Alias != null)
        {
            WriteLine($"using {import.Alias} = {import.Namespace};");
        }
        else
        {
            WriteLine($"using {import.Namespace};");
        }
    }

    private void TranspileDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case TestDeclaration test:
                TranspileTestDeclaration(test);
                break;
            case FunctionDeclaration func:
                TranspileFunctionDeclaration(func);
                break;
            case ClassDeclaration cls:
                TranspileClassDeclaration(cls);
                break;
            case StructDeclaration str:
                TranspileStructDeclaration(str);
                break;
            case RecordDeclaration rec:
                TranspileRecordDeclaration(rec);
                break;
            case InterfaceDeclaration iface:
                TranspileInterfaceDeclaration(iface);
                break;
            case EnumDeclaration enm:
                TranspileEnumDeclaration(enm);
                break;
            case UnionDeclaration union:
                TranspileUnionDeclaration(union);
                break;
            case TypeAliasDeclaration alias:
                TranspileTypeAlias(alias);
                break;
            case PreprocessorDeclaration preprocessor:
                TranspilePreprocessorDeclaration(preprocessor);
                break;
            case FieldDeclaration field:
                TranspileFieldDeclaration(field);
                break;
            case PropertyDeclaration prop:
                TranspilePropertyDeclaration(prop);
                break;
            case ConstructorDeclaration ctor:
                TranspileConstructorDeclaration(ctor);
                break;
            case IndexerDeclaration indexer:
                TranspileIndexerDeclaration(indexer);
                break;
            default:
                throw new Exception($"Unsupported declaration type: {declaration.GetType().Name}");
        }
    }

    private void TranspileTestDeclaration(TestDeclaration test)
    {
        // Convert test description to valid C# method name
        var methodName = TestDescriptionToMethodName(test.Description);

        WriteLine("[Fact]");
        WriteLine($"public void {methodName}()");
        WriteLine("{");
        _indentLevel++;

        foreach (var stmt in test.Body.Statements)
        {
            TranspileStatement(stmt);
        }

        _indentLevel--;
        WriteLine("}");
        WriteLine();
    }

    private string TestDescriptionToMethodName(string description)
    {
        // Convert "should add two numbers" to "ShouldAddTwoNumbers"
        var words = description.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries);
        var sb = new StringBuilder();

        foreach (var word in words)
        {
            if (word.Length > 0)
            {
                // Capitalize first letter, lowercase rest (simple version)
                sb.Append(char.ToUpper(word[0]));
                if (word.Length > 1)
                {
                    // Keep rest of word as-is for acronyms like "API"
                    sb.Append(word.Substring(1));
                }
            }
        }

        var result = sb.ToString();

        // Remove any remaining invalid characters
        result = new string(result.Where(c => char.IsLetterOrDigit(c) || c == '_').ToArray());

        // Ensure it starts with a letter or underscore
        if (result.Length == 0 || !char.IsLetter(result[0]))
        {
            result = "Test_" + result;
        }

        return result;
    }

    private void TranspileFunctionDeclaration(FunctionDeclaration func)
    {
        TranspileAttributes(func.Attributes);

        // Get modifiers - interface methods don't need modifiers in C# (they're implicitly public)
        string modifiers;
        if (_inInterface)
        {
            modifiers = "";
        }
        else
        {
            modifiers = GetModifierString(func.Modifiers);

            // Operator overloads must be public static
            if (func.IsOperatorOverload)
            {
                modifiers = "public static ";
            }
            // If no explicit visibility modifier, apply naming convention
            else if (!func.Modifiers.HasFlag(Modifiers.Public) && !func.Modifiers.HasFlag(Modifiers.Private) &&
                !func.Modifiers.HasFlag(Modifiers.Protected) && !func.Modifiers.HasFlag(Modifiers.Internal))
            {
                modifiers = char.IsUpper(func.Name[0]) ? "public " + modifiers : "private " + modifiers;
            }
        }

        var typeParams = func.TypeParameters != null && func.TypeParameters.Count > 0
            ? $"<{string.Join(", ", func.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        var parameters = string.Join(", ", func.Parameters.Select(TranspileParameter));
        var returnType = func.ReturnType != null ? TranspileTypeReference(func.ReturnType) : "void";

        // Handle async implicit wrapping
        if (func.Modifiers.HasFlag(Modifiers.Async))
        {
            returnType = WrapAsyncReturnType(returnType, func.ReturnType);
        }

        // Determine function name (operator keyword for overloads)
        var functionName = func.IsOperatorOverload ? $"operator {func.OperatorSymbol}" : func.Name;

        Write($"{modifiers}{returnType} {functionName}{typeParams}({parameters})");

        if (func.Constraints != null && func.Constraints.Count > 0)
        {
            foreach (var constraint in func.Constraints)
            {
                _output.Append($" where {constraint.TypeParameter} : {string.Join(", ", constraint.Constraints.Select(TranspileTypeReference))}");
            }
        }

        if (func.Body != null)
        {
            WriteLine();
            TranspileBlockStatement(func.Body);
        }
        else if (func.ExpressionBody != null)
        {
            // Expression-bodied method
            WriteLine($" => {TranspileExpression(func.ExpressionBody)};");
        }
        else
        {
            WriteLine(";");
        }
    }

    private void TranspileClassDeclaration(ClassDeclaration cls)
    {
        TranspileAttributes(cls.Attributes);

        var modifiers = GetModifierString(cls.Modifiers);

        // Infer visibility for nested types (PascalCase = public)
        if (_currentTypeName != null && !cls.Modifiers.HasFlag(Modifiers.Public) &&
            !cls.Modifiers.HasFlag(Modifiers.Private) && !cls.Modifiers.HasFlag(Modifiers.Protected) &&
            !cls.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (char.IsUpper(cls.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
        }
        var typeParams = cls.TypeParameters != null && cls.TypeParameters.Count > 0
            ? $"<{string.Join(", ", cls.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}class {cls.Name}{typeParams}");

        var bases = new List<string>();
        if (cls.BaseClass != null)
            bases.Add(TranspileTypeReference(cls.BaseClass));
        bases.AddRange(cls.Interfaces.Select(TranspileTypeReference));

        // Automatically add duck interfaces that this class implements
        foreach (var duckInterface in _duckInterfaces)
        {
            if (ClassImplementsDuckInterface(cls.Members, duckInterface))
            {
                bases.Add(duckInterface.Name);
            }
        }

        if (bases.Count > 0)
        {
            _output.Append($" : {string.Join(", ", bases)}");
        }

        WriteLine();
        WriteLine("{");
        _indentLevel++;

        var previousTypeName = _currentTypeName;
        _currentTypeName = cls.Name;
        foreach (var member in cls.Members)
        {
            TranspileDeclaration(member);
            WriteLine();
        }
        _currentTypeName = previousTypeName;

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileStructDeclaration(StructDeclaration str)
    {
        TranspileAttributes(str.Attributes);

        var modifiers = GetModifierString(str.Modifiers);

        // Infer visibility for nested types (PascalCase = public)
        if (_currentTypeName != null && !str.Modifiers.HasFlag(Modifiers.Public) &&
            !str.Modifiers.HasFlag(Modifiers.Private) && !str.Modifiers.HasFlag(Modifiers.Protected) &&
            !str.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (char.IsUpper(str.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
        }
        var typeParams = str.TypeParameters != null && str.TypeParameters.Count > 0
            ? $"<{string.Join(", ", str.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}struct {str.Name}{typeParams}");

        var bases = new List<string>();
        bases.AddRange(str.Interfaces.Select(TranspileTypeReference));

        // Automatically add duck interfaces that this struct implements
        foreach (var duckInterface in _duckInterfaces)
        {
            if (ClassImplementsDuckInterface(str.Members, duckInterface))
            {
                bases.Add(duckInterface.Name);
            }
        }

        if (bases.Count > 0)
        {
            _output.Append($" : {string.Join(", ", bases)}");
        }

        WriteLine();
        WriteLine("{");
        _indentLevel++;

        var previousTypeName = _currentTypeName;
        _currentTypeName = str.Name;
        foreach (var member in str.Members)
        {
            TranspileDeclaration(member);
            WriteLine();
        }
        _currentTypeName = previousTypeName;

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileRecordDeclaration(RecordDeclaration rec)
    {
        TranspileAttributes(rec.Attributes);

        var modifiers = GetModifierString(rec.Modifiers);

        // Infer visibility for nested types (PascalCase = public)
        if (_currentTypeName != null && !rec.Modifiers.HasFlag(Modifiers.Public) &&
            !rec.Modifiers.HasFlag(Modifiers.Private) && !rec.Modifiers.HasFlag(Modifiers.Protected) &&
            !rec.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (char.IsUpper(rec.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
        }
        var typeParams = rec.TypeParameters != null && rec.TypeParameters.Count > 0
            ? $"<{string.Join(", ", rec.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}record {rec.Name}{typeParams}");

        var bases = new List<string>();
        bases.AddRange(rec.Interfaces.Select(TranspileTypeReference));

        // Automatically add duck interfaces that this record implements
        foreach (var duckInterface in _duckInterfaces)
        {
            if (ClassImplementsDuckInterface(rec.Members, duckInterface))
            {
                bases.Add(duckInterface.Name);
            }
        }

        if (bases.Count > 0)
        {
            _output.Append($" : {string.Join(", ", bases)}");
        }

        WriteLine();
        WriteLine("{");
        _indentLevel++;

        var previousTypeName = _currentTypeName;
        _currentTypeName = rec.Name;
        foreach (var member in rec.Members)
        {
            TranspileDeclaration(member);
            WriteLine();
        }
        _currentTypeName = previousTypeName;

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileInterfaceDeclaration(InterfaceDeclaration iface)
    {
        TranspileAttributes(iface.Attributes);

        // Duck interfaces are emitted as internal interfaces
        var modifiers = iface.IsDuckInterface
            ? "internal "
            : GetModifierString(iface.Modifiers);
        var typeParams = iface.TypeParameters != null && iface.TypeParameters.Count > 0
            ? $"<{string.Join(", ", iface.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}interface {iface.Name}{typeParams}");

        if (iface.BaseInterfaces.Count > 0)
        {
            _output.Append($" : {string.Join(", ", iface.BaseInterfaces.Select(TranspileTypeReference))}");
        }

        WriteLine();
        WriteLine("{");
        _indentLevel++;

        _inInterface = true; // Set flag while transpiling interface members
        foreach (var member in iface.Members)
        {
            TranspileDeclaration(member);
            WriteLine();
        }
        _inInterface = false; // Reset flag

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileEnumDeclaration(EnumDeclaration enm)
    {
        TranspileAttributes(enm.Attributes);

        var modifiers = GetModifierString(enm.Modifiers);

        // Infer visibility for nested types (PascalCase = public)
        if (_currentTypeName != null && !enm.Modifiers.HasFlag(Modifiers.Public) &&
            !enm.Modifiers.HasFlag(Modifiers.Private) && !enm.Modifiers.HasFlag(Modifiers.Protected) &&
            !enm.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (char.IsUpper(enm.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
        }

        // String enums in C# need to be handled differently (using constants or records)
        if (enm.Type == EnumType.String)
        {
            // For string enums, we'll generate a static class with string constants
            WriteLine($"{modifiers}static class {enm.Name}");
            WriteLine("{");
            _indentLevel++;

            foreach (var member in enm.Members)
            {
                var value = member.Value != null ? TranspileExpression(member.Value) : $"\"{member.Name}\"";
                WriteLine($"public const string {member.Name} = {value};");
            }

            _indentLevel--;
            WriteLine("}");
        }
        else
        {
            WriteLine($"{modifiers}enum {enm.Name}");
            WriteLine("{");
            _indentLevel++;

            for (int i = 0; i < enm.Members.Count; i++)
            {
                var member = enm.Members[i];
                if (member.Value != null)
                {
                    Write($"{member.Name} = {TranspileExpression(member.Value)}");
                }
                else
                {
                    Write($"{member.Name}");
                }

                if (i < enm.Members.Count - 1)
                    _output.Append(",");

                WriteLine();
            }

            _indentLevel--;
            WriteLine("}");
        }
    }

    private void TranspileUnionDeclaration(UnionDeclaration union)
    {
        // Union types transpile to an abstract base class with nested case classes
        TranspileAttributes(union.Attributes);

        var modifiers = GetModifierString(union.Modifiers);
        WriteLine($"{modifiers}abstract record {union.Name}");
        WriteLine("{");
        _indentLevel++;

        // Generate case classes
        foreach (var unionCase in union.Cases)
        {
            if (unionCase.Properties != null && unionCase.Properties.Count > 0)
            {
                var props = string.Join(", ", unionCase.Properties.Select(p => $"{TranspileTypeReference(p.Type)} {p.Name}"));
                WriteLine($"public record {unionCase.Name}({props}) : {union.Name};");
            }
            else
            {
                WriteLine($"public record {unionCase.Name} : {union.Name};");
            }
        }

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileTypeAlias(TypeAliasDeclaration alias)
    {
        // C# doesn't have type aliases outside of using directives at file level
        // We'll emit a comment for documentation
        WriteLine($"// type {alias.Name} = {TranspileTypeReference(alias.Type)}");
    }

    private void TranspilePreprocessorDeclaration(PreprocessorDeclaration preprocessor)
    {
        // Pass-through to C# - preprocessor directives are emitted as-is
        WriteLine(preprocessor.Directive);
    }

    private void TranspileFieldDeclaration(FieldDeclaration field)
    {
        TranspileAttributes(field.Attributes);

        // Get modifiers, but exclude readonly and init from the modifier string since we handle them in accessors
        var modifiersWithoutReadonlyAndInit = field.Modifiers & ~Modifiers.Readonly & ~Modifiers.Init;
        var modifiers = GetModifierString(modifiersWithoutReadonlyAndInit);
        var type = TranspileTypeReference(field.Type);
        var isReadonly = field.Modifiers.HasFlag(Modifiers.Readonly);
        var isInit = field.Modifiers.HasFlag(Modifiers.Init);

        // Determine visibility based on naming convention if no explicit modifier
        if (!field.Modifiers.HasFlag(Modifiers.Public) && !field.Modifiers.HasFlag(Modifiers.Private) &&
            !field.Modifiers.HasFlag(Modifiers.Protected) && !field.Modifiers.HasFlag(Modifiers.Internal))
        {
            modifiers = char.IsUpper(field.Name[0]) ? "public " + modifiers : "private " + modifiers;
        }

        // For readonly or init fields, use { get; init; } instead of { get; set; }
        var accessors = (isReadonly || isInit) ? "{ get; init; }" : "{ get; set; }";

        if (field.Initializer != null)
        {
            WriteLine($"{modifiers}{type} {field.Name} {accessors} = {TranspileExpression(field.Initializer)};");
        }
        else
        {
            WriteLine($"{modifiers}{type} {field.Name} {accessors}");
        }
    }

    private void TranspilePropertyDeclaration(PropertyDeclaration prop)
    {
        TranspileAttributes(prop.Attributes);

        // Exclude Init from modifier string - it's handled in accessors
        var modifiersWithoutInit = prop.Modifiers & ~Modifiers.Init;
        var modifiers = GetModifierString(modifiersWithoutInit);
        var isInit = prop.Modifiers.HasFlag(Modifiers.Init);

        // Apply convention-based visibility if no explicit modifier
        if (!prop.Modifiers.HasFlag(Modifiers.Public) && !prop.Modifiers.HasFlag(Modifiers.Private) &&
            !prop.Modifiers.HasFlag(Modifiers.Protected) && !prop.Modifiers.HasFlag(Modifiers.Internal))
        {
            modifiers = char.IsUpper(prop.Name[0]) ? "public " + modifiers : "private " + modifiers;
        }

        // Expression-bodied property
        if (prop.ExpressionBody != null)
        {
            var type = TranspileTypeReference(prop.Type!);
            WriteLine($"{modifiers}{type} {prop.Name} => {TranspileExpression(prop.ExpressionBody)};");
        }
        else
        {
            // Regular property with get/set blocks
            var type = TranspileTypeReference(prop.Type!); // Type is required for non-expression-bodied properties
            WriteLine($"{modifiers}{type} {prop.Name}");
            WriteLine("{");
            _indentLevel++;

            if (prop.GetBody != null)
            {
                WriteLine("get");
                TranspileBlockStatement(prop.GetBody);
            }

            if (prop.SetBody != null)
            {
                // If init modifier is present, use init instead of set
                WriteLine(isInit ? "init" : "set");
                TranspileBlockStatement(prop.SetBody);
            }

            _indentLevel--;
            WriteLine("}");
        }
    }

    private void TranspileConstructorDeclaration(ConstructorDeclaration ctor)
    {
        TranspileAttributes(ctor.Attributes);

        var modifiers = GetModifierString(ctor.Modifiers);
        if (!ctor.Modifiers.HasFlag(Modifiers.Public) && !ctor.Modifiers.HasFlag(Modifiers.Private) &&
            !ctor.Modifiers.HasFlag(Modifiers.Protected) && !ctor.Modifiers.HasFlag(Modifiers.Internal))
        {
            modifiers = "public " + modifiers;
        }

        var parameters = string.Join(", ", ctor.Parameters.Select(TranspileParameter));
        var ctorName = _currentTypeName ?? "UnknownType";

        // Emit constructor with optional initializer
        if (ctor.Initializer != null)
        {
            var initializer = TranspileConstructorInitializer(ctor.Initializer);
            WriteLine($"{modifiers}{ctorName}({parameters}) : {initializer}");
        }
        else
        {
            WriteLine($"{modifiers}{ctorName}({parameters})");
        }

        TranspileBlockStatement(ctor.Body);
    }

    private string TranspileConstructorInitializer(Expression initializer)
    {
        // Initializer is a CallExpression with either ThisExpression or BaseExpression as callee
        if (initializer is CallExpression call)
        {
            var keyword = call.Callee switch
            {
                ThisExpression => "this",
                BaseExpression => "base",
                _ => throw new Exception("Constructor initializer must be 'this()' or 'base()' call")
            };

            var arguments = string.Join(", ", call.Arguments.Select(arg =>
            {
                var prefix = "";
                if (arg.Modifier == ArgumentModifier.Ref)
                    prefix = "ref ";
                else if (arg.Modifier == ArgumentModifier.Out)
                    prefix = "out ";

                var argValue = TranspileExpression(arg.Value);
                var result = prefix + argValue;
                return arg.Name != null ? $"{arg.Name}: {result}" : result;
            }));
            return $"{keyword}({arguments})";
        }

        throw new Exception("Invalid constructor initializer expression");
    }

    private void TranspileIndexerDeclaration(IndexerDeclaration indexer)
    {
        TranspileAttributes(indexer.Attributes);

        var modifiers = GetModifierString(indexer.Modifiers);
        var type = TranspileTypeReference(indexer.Type);
        var parameters = string.Join(", ", indexer.Parameters.Select(TranspileParameter));

        WriteLine($"{modifiers}{type} this[{parameters}]");
        WriteLine("{");
        _indentLevel++;

        if (indexer.GetBody != null)
        {
            WriteLine("get");
            TranspileBlockStatement(indexer.GetBody);
        }

        if (indexer.SetBody != null)
        {
            WriteLine("set");
            TranspileBlockStatement(indexer.SetBody);
        }

        _indentLevel--;
        WriteLine("}");
    }

    private string TranspileParameter(Parameter param)
    {
        var result = "";

        // Add ref/out modifier
        if (param.Modifier == ParameterModifier.Ref)
            result = "ref ";
        else if (param.Modifier == ParameterModifier.Out)
            result = "out ";

        if (param.IsThis)
            result += "this ";

        result += $"{TranspileTypeReference(param.Type)} {param.Name}";

        if (param.DefaultValue != null)
        {
            result += $" = {TranspileExpression(param.DefaultValue)}";
        }

        return result;
    }

    private void TranspileBlockStatement(BlockStatement block)
    {
        WriteLine("{");
        _indentLevel++;

        foreach (var statement in block.Statements)
        {
            TranspileStatement(statement);
        }

        _indentLevel--;
        WriteLine("}");
    }

    private void TranspileStatement(Statement statement)
    {
        switch (statement)
        {
            case ExpressionStatement expr:
                WriteLine($"{TranspileExpression(expr.Expression)};");
                break;
            case VariableDeclarationStatement varDecl:
                TranspileVariableDeclaration(varDecl);
                break;
            case TupleDeconstructionStatement tupleDecl:
                TranspileTupleDeconstruction(tupleDecl);
                break;
            case BlockStatement block:
                TranspileBlockStatement(block);
                break;
            case IfStatement ifStmt:
                TranspileIfStatement(ifStmt);
                break;
            case ForStatement forStmt:
                TranspileForStatement(forStmt);
                break;
            case ForeachStatement foreachStmt:
                TranspileForeachStatement(foreachStmt);
                break;
            case WhileStatement whileStmt:
                WriteLine($"while ({TranspileExpression(whileStmt.Condition)})");
                TranspileStatement(whileStmt.Body);
                break;
            case ReturnStatement returnStmt:
                if (returnStmt.Value != null)
                    WriteLine($"return {TranspileExpression(returnStmt.Value)};");
                else
                    WriteLine("return;");
                break;
            case YieldStatement yieldStmt:
                WriteLine($"yield return {TranspileExpression(yieldStmt.Value)};");
                break;
            case BreakStatement:
                WriteLine("break;");
                break;
            case ContinueStatement:
                WriteLine("continue;");
                break;
            case ThrowStatement throwStmt:
                WriteLine($"throw {TranspileExpression(throwStmt.Expression)};");
                break;
            case TryStatement tryStmt:
                TranspileTryStatement(tryStmt);
                break;
            case UsingStatement usingStmt:
                TranspileUsingStatement(usingStmt);
                break;
            case SwitchStatement switchStmt:
                TranspileSwitchStatement(switchStmt);
                break;
            case PrintStatement printStmt:
                WriteLine($"Console.WriteLine({TranspileExpression(printStmt.Value)});");
                break;
            case AssertStatement assertStmt:
                TranspileAssertStatement(assertStmt);
                break;
            case PreprocessorDirective preprocessor:
                WriteLine(preprocessor.Directive);
                break;
            case EmptyStatement:
                WriteLine(";");
                break;
            default:
                throw new Exception($"Unsupported statement type: {statement.GetType().Name}");
        }
    }

    private void TranspileAssertStatement(AssertStatement assertStmt)
    {
        // Smart assert transpilation - convert different patterns to appropriate XUnit asserts
        var condition = assertStmt.Condition;

        switch (condition)
        {
            case BinaryExpression binExpr:
                TranspileBinaryAssert(binExpr);
                break;

            case IsExpression isExpr:
                // assert x is Type → Assert.IsType<Type>(x)
                var typeName = TranspileTypeReference(isExpr.Type);
                WriteLine($"Assert.IsType<{typeName}>({TranspileExpression(isExpr.Expression)});");
                break;

            default:
                // Simple boolean expression: assert x → Assert.True(x)
                WriteLine($"Assert.True({TranspileExpression(condition)});");
                break;
        }
    }

    private void TranspileBinaryAssert(BinaryExpression binExpr)
    {
        var left = TranspileExpression(binExpr.Left);
        var right = TranspileExpression(binExpr.Right);

        switch (binExpr.Operator)
        {
            case BinaryOperator.Equal:
                // assert x == y → Assert.Equal(y, x) [XUnit expects expected first]
                WriteLine($"Assert.Equal({right}, {left});");
                break;

            case BinaryOperator.NotEqual:
                // Special case: assert x != null → Assert.NotNull(x)
                if (binExpr.Right is NullLiteralExpression)
                {
                    WriteLine($"Assert.NotNull({left});");
                }
                else if (binExpr.Left is NullLiteralExpression)
                {
                    WriteLine($"Assert.NotNull({right});");
                }
                else
                {
                    WriteLine($"Assert.NotEqual({right}, {left});");
                }
                break;

            case BinaryOperator.Greater:
            case BinaryOperator.Less:
            case BinaryOperator.GreaterOrEqual:
            case BinaryOperator.LessOrEqual:
                // Relational operators: assert x > y → Assert.True(x > y)
                var relOp = binExpr.Operator switch
                {
                    BinaryOperator.Greater => ">",
                    BinaryOperator.Less => "<",
                    BinaryOperator.GreaterOrEqual => ">=",
                    BinaryOperator.LessOrEqual => "<=",
                    _ => "??"
                };
                WriteLine($"Assert.True({left} {relOp} {right});");
                break;

            default:
                // Default to Assert.True for any other binary expression
                var defaultOp = binExpr.Operator switch
                {
                    BinaryOperator.Add => "+",
                    BinaryOperator.Subtract => "-",
                    BinaryOperator.And => "&&",
                    BinaryOperator.Or => "||",
                    _ => "??"
                };
                WriteLine($"Assert.True({left} {defaultOp} {right});");
                break;
        }
    }

    private void TranspileVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        var type = varDecl.Type != null ? TranspileTypeReference(varDecl.Type) : "var";
        var keyword = varDecl.Kind == VariableKind.Const ? "const " :
                     varDecl.Kind == VariableKind.Readonly ? "readonly " : "";

        if (varDecl.Initializer != null)
        {
            WriteLine($"{keyword}{type} {varDecl.Name} = {TranspileExpression(varDecl.Initializer)};");
        }
        else
        {
            WriteLine($"{keyword}{type} {varDecl.Name};");
        }
    }

    private void TranspileTupleDeconstruction(TupleDeconstructionStatement tupleDecl)
    {
        // Check if this is error handling pattern: (result, err := Function())
        // The pattern is: exactly 2 names, last one is "err"
        bool isErrorHandling = tupleDecl.Names.Count == 2 && tupleDecl.Names[1] == "err";

        if (isErrorHandling)
        {
            // Generate try-catch wrapper for error handling pattern
            var resultVar = tupleDecl.Names[0];
            var errVar = tupleDecl.Names[1];

            // Declare variables (skip result var if it's discarded)
            if (resultVar != "_")
            {
                WriteLine($"object? {resultVar} = null;");
            }
            WriteLine($"Exception? {errVar} = null;");
            WriteLine("try");
            WriteLine("{");
            _indentLevel++;
            // If result is discarded, just call the function; otherwise assign
            if (resultVar == "_")
            {
                WriteLine($"{TranspileExpression(tupleDecl.Initializer)};");
            }
            else
            {
                WriteLine($"{resultVar} = {TranspileExpression(tupleDecl.Initializer)};");
            }
            _indentLevel--;
            WriteLine("}");
            WriteLine($"catch (Exception ex)");
            WriteLine("{");
            _indentLevel++;
            WriteLine($"{errVar} = ex;");
            _indentLevel--;
            WriteLine("}");
        }
        else
        {
            // Normal tuple deconstruction
            var keyword = tupleDecl.Kind == VariableKind.Const ? "const " :
                         tupleDecl.Kind == VariableKind.Readonly ? "readonly " : "";

            // C# tuple deconstruction syntax: (var x, var y) = expr;
            // or: var (x, y) = expr;
            var names = string.Join(", ", tupleDecl.Names.Select(n => n == "_" ? "_" : n));
            WriteLine($"{keyword}({names}) = {TranspileExpression(tupleDecl.Initializer)};");
        }
    }

    private void TranspileIfStatement(IfStatement ifStmt)
    {
        Write($"if ({TranspileExpression(ifStmt.Condition)})");
        WriteLine();

        if (ifStmt.ThenStatement is BlockStatement)
        {
            TranspileStatement(ifStmt.ThenStatement);
        }
        else
        {
            _indentLevel++;
            TranspileStatement(ifStmt.ThenStatement);
            _indentLevel--;
        }

        if (ifStmt.ElseStatement != null)
        {
            WriteLine("else");

            if (ifStmt.ElseStatement is BlockStatement || ifStmt.ElseStatement is IfStatement)
            {
                TranspileStatement(ifStmt.ElseStatement);
            }
            else
            {
                _indentLevel++;
                TranspileStatement(ifStmt.ElseStatement);
                _indentLevel--;
            }
        }
    }

    private void TranspileForStatement(ForStatement forStmt)
    {
        // Check if this is actually a foreach wrapped in a for
        if (forStmt.Body is ForeachStatement foreachStmt)
        {
            TranspileForeachStatement(foreachStmt);
            return;
        }

        Write("for (");

        if (forStmt.Initializer != null)
        {
            if (forStmt.Initializer is VariableDeclarationStatement varDecl)
            {
                var type = varDecl.Type != null ? TranspileTypeReference(varDecl.Type) : "var";
                _output.Append($"{type} {varDecl.Name} = {TranspileExpression(varDecl.Initializer!)}");
            }
            else if (forStmt.Initializer is ExpressionStatement exprStmt)
            {
                _output.Append(TranspileExpression(exprStmt.Expression));
            }
        }

        _output.Append("; ");

        if (forStmt.Condition != null)
        {
            _output.Append(TranspileExpression(forStmt.Condition));
        }

        _output.Append("; ");

        if (forStmt.Iterator != null)
        {
            _output.Append(TranspileExpression(forStmt.Iterator));
        }

        _output.Append(")");
        WriteLine();
        TranspileStatement(forStmt.Body);
    }

    private void TranspileForeachStatement(ForeachStatement foreachStmt)
    {
        WriteLine($"foreach (var {foreachStmt.VariableName} in {TranspileExpression(foreachStmt.Collection)})");
        TranspileStatement(foreachStmt.Body);
    }

    private void TranspileTryStatement(TryStatement tryStmt)
    {
        WriteLine("try");
        TranspileBlockStatement(tryStmt.TryBlock);

        foreach (var catchClause in tryStmt.CatchClauses)
        {
            if (catchClause.ExceptionType != null)
            {
                if (catchClause.VariableName != null)
                {
                    WriteLine($"catch ({TranspileTypeReference(catchClause.ExceptionType)} {catchClause.VariableName})");
                }
                else
                {
                    WriteLine($"catch ({TranspileTypeReference(catchClause.ExceptionType)})");
                }
            }
            else
            {
                WriteLine("catch");
            }

            TranspileBlockStatement(catchClause.Block);
        }

        if (tryStmt.FinallyBlock != null)
        {
            WriteLine("finally");
            TranspileBlockStatement(tryStmt.FinallyBlock);
        }
    }

    private void TranspileUsingStatement(UsingStatement usingStmt)
    {
        if (usingStmt.Declaration != null)
        {
            var type = usingStmt.Declaration.Type != null ? TranspileTypeReference(usingStmt.Declaration.Type) : "var";
            Write($"using ({type} {usingStmt.Declaration.Name} = {TranspileExpression(usingStmt.Declaration.Initializer!)})");

            if (usingStmt.Body != null)
            {
                WriteLine();
                TranspileStatement(usingStmt.Body);
            }
            else
            {
                WriteLine(";");
            }
        }
        else if (usingStmt.Expression != null)
        {
            Write($"using ({TranspileExpression(usingStmt.Expression)})");

            if (usingStmt.Body != null)
            {
                WriteLine();
                TranspileStatement(usingStmt.Body);
            }
            else
            {
                WriteLine(";");
            }
        }
    }

    private void TranspileSwitchStatement(SwitchStatement switchStmt)
    {
        WriteLine($"switch ({TranspileExpression(switchStmt.Value)})");
        WriteLine("{");
        _indentLevel++;

        foreach (var caseStmt in switchStmt.Cases)
        {
            if (caseStmt.Pattern != null)
            {
                WriteLine($"case {TranspilePattern(caseStmt.Pattern)}:");
            }
            else
            {
                WriteLine("default:");
            }

            _indentLevel++;
            foreach (var statement in caseStmt.Statements)
            {
                TranspileStatement(statement);
            }
            WriteLine("break;");
            _indentLevel--;
        }

        _indentLevel--;
        WriteLine("}");
    }

    private string TranspileExpression(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression intLit => intLit.Value,
            FloatLiteralExpression floatLit => floatLit.Value,
            StringLiteralExpression strLit => strLit.Value, // Value already includes quotes
            BoolLiteralExpression boolLit => boolLit.Value ? "true" : "false",
            NullLiteralExpression => "null",
            IdentifierExpression ident => ident.Name,
            BinaryExpression binary => TranspileBinaryExpression(binary),
            UnaryExpression unary => TranspileUnaryExpression(unary),
            MemberAccessExpression member => TranspileMemberAccess(member),
            IndexAccessExpression index => TranspileIndexAccess(index),
            CallExpression call => TranspileCallExpression(call),
            AssignmentExpression assign => TranspileAssignmentExpression(assign),
            TernaryExpression ternary => $"({TranspileExpression(ternary.Condition)} ? {TranspileExpression(ternary.ThenExpression)} : {TranspileExpression(ternary.ElseExpression)})",
            ArrayLiteralExpression array => TranspileArrayLiteral(array),
            NewExpression newExpr => TranspileNewExpression(newExpr),
            LambdaExpression lambda => TranspileLambdaExpression(lambda),
            CastExpression cast => TranspileCastExpression(cast),
            IsExpression isExpr => TranspileIsExpression(isExpr),
            MatchExpression match => TranspileMatchExpression(match),
            WithExpression with => TranspileWithExpression(with),
            AwaitExpression await => $"await {TranspileExpression(await.Expression)}",
            ThrowExpression throwExpr => $"throw {TranspileExpression(throwExpr.Expression)}",
            ThisExpression => "this",
            BaseExpression => "base",
            TypeOfExpression typeOf => $"typeof({TranspileTypeReference(typeOf.Type)})",
            NameofExpression nameOf => TranspileNameofExpression(nameOf),
            RangeExpression range => TranspileRangeExpression(range),
            SizeOfExpression sizeOf => $"sizeof({TranspileTypeReference(sizeOf.Type)})",
            TupleExpression tuple => TranspileTupleExpression(tuple),
            SpreadExpression spread => $"..{TranspileExpression(spread.Expression)}",
            _ => throw new Exception($"Unsupported expression type: {expression.GetType().Name}")
        };
    }

    private string TranspileBinaryExpression(BinaryExpression binary)
    {
        var left = TranspileExpression(binary.Left);
        var right = TranspileExpression(binary.Right);
        var op = binary.Operator switch
        {
            BinaryOperator.Add => "+",
            BinaryOperator.Subtract => "-",
            BinaryOperator.Multiply => "*",
            BinaryOperator.Divide => "/",
            BinaryOperator.Modulo => "%",
            BinaryOperator.Equal => "==",
            BinaryOperator.NotEqual => "!=",
            BinaryOperator.Less => "<",
            BinaryOperator.LessOrEqual => "<=",
            BinaryOperator.Greater => ">",
            BinaryOperator.GreaterOrEqual => ">=",
            BinaryOperator.And => "&&",
            BinaryOperator.Or => "||",
            BinaryOperator.BitwiseAnd => "&",
            BinaryOperator.BitwiseOr => "|",
            BinaryOperator.BitwiseXor => "^",
            BinaryOperator.LeftShift => "<<",
            BinaryOperator.RightShift => ">>",
            BinaryOperator.NullCoalesce => "??",
            BinaryOperator.Range => "..",
            _ => throw new Exception($"Unsupported binary operator: {binary.Operator}")
        };

        return $"({left} {op} {right})";
    }

    private string TranspileRangeExpression(RangeExpression range)
    {
        // Handle all combinations of open-ended ranges
        // start..end, ..end, start.., ..
        var start = range.Start != null ? TranspileExpression(range.Start) : "";
        var end = range.End != null ? TranspileExpression(range.End) : "";
        return $"{start}..{end}";
    }

    private string TranspileUnaryExpression(UnaryExpression unary)
    {
        var operand = TranspileExpression(unary.Operand);
        return unary.Operator switch
        {
            UnaryOperator.Negate => $"(-{operand})",
            UnaryOperator.Not => $"(!{operand})",
            UnaryOperator.BitwiseNot => $"(~{operand})",
            UnaryOperator.PreIncrement => $"++{operand}",
            UnaryOperator.PreDecrement => $"--{operand}",
            UnaryOperator.PostIncrement => $"{operand}++",
            UnaryOperator.PostDecrement => $"{operand}--",
            UnaryOperator.IndexFromEnd => $"^{operand}",
            _ => throw new Exception($"Unsupported unary operator: {unary.Operator}")
        };
    }

    private string TranspileMemberAccess(MemberAccessExpression member)
    {
        var obj = TranspileExpression(member.Object);
        var accessor = member.IsNullConditional ? "?." : ".";
        return $"{obj}{accessor}{member.MemberName}";
    }

    private string TranspileIndexAccess(IndexAccessExpression index)
    {
        var obj = TranspileExpression(index.Object);
        var indexValue = TranspileExpression(index.Index);
        var accessor = index.IsNullConditional ? "?[" : "[";
        return $"{obj}{accessor}{indexValue}]";
    }

    private string TranspileCallExpression(CallExpression call)
    {
        var callee = TranspileExpression(call.Callee);
        var args = string.Join(", ", call.Arguments.Select(arg =>
        {
            var prefix = "";
            if (arg.Modifier == ArgumentModifier.Ref)
                prefix = "ref ";
            else if (arg.Modifier == ArgumentModifier.Out)
                prefix = "out ";

            var argValue = TranspileExpression(arg.Value);
            var result = prefix + argValue;
            return arg.Name != null ? $"{arg.Name}: {result}" : result;
        }));
        return $"{callee}({args})";
    }

    private string TranspileAssignmentExpression(AssignmentExpression assign)
    {
        var target = TranspileExpression(assign.Target);
        var value = TranspileExpression(assign.Value);
        var op = assign.Operator switch
        {
            AssignmentOperator.Assign => "=",
            AssignmentOperator.AddAssign => "+=",
            AssignmentOperator.SubtractAssign => "-=",
            AssignmentOperator.MultiplyAssign => "*=",
            AssignmentOperator.DivideAssign => "/=",
            AssignmentOperator.NullCoalesceAssign => "??=",
            _ => throw new Exception($"Unsupported assignment operator: {assign.Operator}")
        };
        return $"{target} {op} {value}";
    }

    private string TranspileArrayLiteral(ArrayLiteralExpression array)
    {
        var elements = string.Join(", ", array.Elements.Select(TranspileExpression));

        if (array.IsImmutable)
        {
            // Use collection expression syntax for immutable arrays (C# 12+)
            return $"[{elements}]";
        }

        return $"new[] {{ {elements} }}";
    }

    private string TranspileNewExpression(NewExpression newExpr)
    {
        var type = TranspileTypeReference(newExpr.Type);
        var args = string.Join(", ", newExpr.ConstructorArguments.Select(arg =>
        {
            var prefix = "";
            if (arg.Modifier == ArgumentModifier.Ref)
                prefix = "ref ";
            else if (arg.Modifier == ArgumentModifier.Out)
                prefix = "out ";

            var argValue = TranspileExpression(arg.Value);
            var result = prefix + argValue;
            return arg.Name != null ? $"{arg.Name}: {result}" : result;
        }));

        var result = $"new {type}({args})";

        if (newExpr.Initializer != null)
        {
            var props = string.Join(", ", newExpr.Initializer.Properties.Select(p =>
                $"{p.Name} = {TranspileExpression(p.Value)}"));
            result += $" {{ {props} }}";
        }

        return result;
    }

    private string TranspileLambdaExpression(LambdaExpression lambda)
    {
        var parameters = lambda.Parameters.Count == 1
            ? lambda.Parameters[0].Name
            : $"({string.Join(", ", lambda.Parameters.Select(p => p.Name))})";

        if (lambda.ExpressionBody != null)
        {
            return $"{parameters} => {TranspileExpression(lambda.ExpressionBody)}";
        }
        else if (lambda.BlockBody != null)
        {
            var sb = new StringBuilder();
            sb.Append($"{parameters} => ");

            // Transpile block inline
            var savedIndent = _indentLevel;
            var savedOutput = _output.ToString();
            _output.Clear();
            _indentLevel = 0;

            TranspileBlockStatement(lambda.BlockBody);

            var blockCode = _output.ToString().Trim();
            _output.Clear();
            _output.Append(savedOutput);
            _indentLevel = savedIndent;

            return $"{parameters} => {blockCode}";
        }

        throw new Exception("Lambda must have either expression or block body");
    }

    private string TranspileCastExpression(CastExpression cast)
    {
        var expr = TranspileExpression(cast.Expression);
        var type = TranspileTypeReference(cast.TargetType);

        return cast.Kind == CastKind.Hard
            ? $"(({type}){expr})"
            : $"({expr} as {type})";
    }

    private string TranspileIsExpression(IsExpression isExpr)
    {
        var expr = TranspileExpression(isExpr.Expression);
        var type = TranspileTypeReference(isExpr.Type);

        if (isExpr.VariableName != null)
        {
            return $"{expr} is {type} {isExpr.VariableName}";
        }

        return $"{expr} is {type}";
    }

    private string TranspileNameofExpression(NameofExpression nameofExpr)
    {
        // Extract the final identifier name from the target expression
        // For member access like obj.Property, we want just "Property"
        // For simple identifiers like variable, we want "variable"
        string targetName = ExtractNameofTarget(nameofExpr.Target);
        return $"nameof({targetName})";
    }

    private string ExtractNameofTarget(Expression expr)
    {
        return expr switch
        {
            IdentifierExpression ident => ident.Name,
            MemberAccessExpression member => member.MemberName,
            _ => TranspileExpression(expr) // Fallback to full expression
        };
    }

    private string TranspileMatchExpression(MatchExpression match)
    {
        // Match expressions transpile to switch expressions in C#
        var value = TranspileExpression(match.Value);
        var cases = string.Join(",\n" + GetIndent(), match.Cases.Select(c =>
        {
            var pattern = TranspilePattern(c.Pattern);
            var guard = c.Guard != null ? $" when {TranspileExpression(c.Guard)}" : "";
            var expression = TranspileExpression(c.Expression);
            return $"{pattern}{guard} => {expression}";
        }));

        return $"{value} switch {{\n{GetIndent()}{cases}\n{GetIndent()}}}";
    }

    private string TranspileWithExpression(WithExpression with)
    {
        var target = TranspileExpression(with.Target);
        var props = string.Join(", ", with.Properties.Select(p =>
            $"{p.Name} = {TranspileExpression(p.Value)}"));
        return $"{target} with {{ {props} }}";
    }

    private string TranspileTupleExpression(TupleExpression tuple)
    {
        var elements = string.Join(", ", tuple.Elements.Select(e =>
        {
            var value = TranspileExpression(e.Value);
            return e.Name != null ? $"{e.Name}: {value}" : value;
        }));
        return $"({elements})";
    }

    private string TranspilePattern(Pattern pattern)
    {
        return pattern switch
        {
            LiteralPattern lit => TranspileExpression(lit.Literal),
            IdentifierPattern ident => TranspileIdentifierPattern(ident),
            UnionCasePattern unionCase => TranspileUnionCasePattern(unionCase),
            ObjectPattern obj => TranspileObjectPattern(obj),
            RelationalPattern relational => TranspileRelationalPattern(relational),
            AndPattern and => TranspileAndPattern(and),
            OrPattern or => TranspileOrPattern(or),
            NotPattern not => TranspileNotPattern(not),
            PositionalPattern positional => TranspilePositionalPattern(positional),
            ListPattern list => TranspileListPattern(list),
            SlicePattern slice => TranspileSlicePattern(slice),
            _ => throw new Exception($"Unsupported pattern type: {pattern.GetType().Name}")
        };
    }

    private string TranspileIdentifierPattern(IdentifierPattern pattern)
    {
        // Wildcard pattern
        if (pattern.Name == "_")
            return "_";

        // Qualified name (e.g., Result.Success without properties) - no var prefix
        if (pattern.Name.Contains('.'))
            return pattern.Name;

        // Simple identifier - needs var prefix to capture the variable
        return $"var {pattern.Name}";
    }

    private string TranspileUnionCasePattern(UnionCasePattern pattern)
    {
        if (pattern.Properties == null || pattern.Properties.Count == 0)
        {
            return pattern.CaseName;
        }

        var props = TranspilePropertyPatterns(pattern.Properties);
        return $"{pattern.CaseName} {{ {props} }}";
    }

    private string TranspileObjectPattern(ObjectPattern pattern)
    {
        var props = TranspilePropertyPatterns(pattern.Properties);
        return $"{{ {props} }}";
    }

    private string TranspilePropertyPatterns(List<PropertyPattern> propertyPatterns)
    {
        return string.Join(", ", propertyPatterns.Select(p =>
        {
            // If there's a nested pattern, recursively transpile it
            if (p.Pattern != null)
            {
                var nestedPattern = TranspilePattern(p.Pattern);
                return $"{p.Name}: {nestedPattern}";
            }
            else
            {
                // Simple binding: { Name } or { Name: var name }
                var binding = p.BindingName ?? p.Name;
                return $"{p.Name}: var {binding}";
            }
        }));
    }

    private string TranspileRelationalPattern(RelationalPattern pattern)
    {
        // C# 9+ relational patterns: < value, >= value, etc.
        return $"{pattern.Operator} {TranspileExpression(pattern.Value)}";
    }

    private string TranspileAndPattern(AndPattern pattern)
    {
        // C# 9+ and pattern: pattern1 and pattern2
        return $"{TranspilePattern(pattern.Left)} and {TranspilePattern(pattern.Right)}";
    }

    private string TranspileOrPattern(OrPattern pattern)
    {
        // C# 9+ or pattern: pattern1 or pattern2
        return $"{TranspilePattern(pattern.Left)} or {TranspilePattern(pattern.Right)}";
    }

    private string TranspileNotPattern(NotPattern pattern)
    {
        // C# 9+ not pattern: not pattern
        return $"not {TranspilePattern(pattern.Pattern)}";
    }

    private string TranspilePositionalPattern(PositionalPattern pattern)
    {
        // C# positional pattern: (pattern1, pattern2, ...)
        var patterns = string.Join(", ", pattern.Patterns.Select(TranspilePattern));
        return $"({patterns})";
    }

    private string TranspileListPattern(ListPattern pattern)
    {
        // C# 11 list pattern: [pattern1, pattern2, .., pattern3]
        var patterns = string.Join(", ", pattern.Elements.Select(TranspilePattern));
        return $"[{patterns}]";
    }

    private string TranspileSlicePattern(SlicePattern pattern)
    {
        // C# 11 slice pattern: .. or .. var name
        if (pattern.BindingName != null)
        {
            return $".. var {pattern.BindingName}";
        }
        return "..";
    }

    private string TranspileTypeReference(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => $"{generic.Name}<{string.Join(", ", generic.TypeArguments.Select(TranspileTypeReference))}>",
            ArrayTypeReference array => $"{TranspileTypeReference(array.ElementType)}[]",
            NullableTypeReference nullable => $"{TranspileTypeReference(nullable.InnerType)}?",
            TupleTypeReference tuple => TranspileTupleType(tuple),
            FunctionTypeReference func => TranspileFunctionType(func),
            _ => throw new Exception($"Unsupported type reference: {typeRef.GetType().Name}")
        };
    }

    private string TranspileTupleType(TupleTypeReference tuple)
    {
        var elements = string.Join(", ", tuple.Elements.Select(e =>
        {
            var type = TranspileTypeReference(e.Type);
            return e.Name != null ? $"{type} {e.Name}" : type;
        }));
        return $"({elements})";
    }

    private string TranspileFunctionType(FunctionTypeReference func)
    {
        // Func<void> maps to Action
        if (func.ReturnType is SimpleTypeReference simple && simple.Name == "void")
        {
            if (func.ParameterTypes.Count == 0)
                return "Action";

            var paramTypes = string.Join(", ", func.ParameterTypes.Select(TranspileTypeReference));
            return $"Action<{paramTypes}>";
        }

        // Regular Func<T>
        if (func.ParameterTypes.Count == 0)
        {
            return $"Func<{TranspileTypeReference(func.ReturnType)}>";
        }

        var allTypes = string.Join(", ",
            func.ParameterTypes.Select(TranspileTypeReference).Append(TranspileTypeReference(func.ReturnType)));
        return $"Func<{allTypes}>";
    }

    private void TranspileAttributes(List<AttributeNode> attributes)
    {
        foreach (var attr in attributes)
        {
            var args = attr.Arguments.Count > 0
                ? $"({string.Join(", ", attr.Arguments.Select(a => TranspileExpression(a.Value)))})"
                : "";
            WriteLine($"[{attr.Name}{args}]");
        }
    }

    private string GetModifierString(Modifiers modifiers)
    {
        var parts = new List<string>();

        if (modifiers.HasFlag(Modifiers.Public)) parts.Add("public");
        if (modifiers.HasFlag(Modifiers.Private)) parts.Add("private");
        if (modifiers.HasFlag(Modifiers.Protected)) parts.Add("protected");
        if (modifiers.HasFlag(Modifiers.Internal)) parts.Add("internal");
        if (modifiers.HasFlag(Modifiers.Static)) parts.Add("static");
        if (modifiers.HasFlag(Modifiers.Virtual)) parts.Add("virtual");
        if (modifiers.HasFlag(Modifiers.Abstract)) parts.Add("abstract");
        if (modifiers.HasFlag(Modifiers.Sealed)) parts.Add("sealed");
        if (modifiers.HasFlag(Modifiers.Partial)) parts.Add("partial");
        if (modifiers.HasFlag(Modifiers.Readonly)) parts.Add("readonly");
        if (modifiers.HasFlag(Modifiers.Async)) parts.Add("async");
        if (modifiers.HasFlag(Modifiers.Required)) parts.Add("required");
        // Note: Init is handled separately in property accessors, not as a modifier keyword

        return parts.Count > 0 ? string.Join(" ", parts) + " " : "";
    }

    private void Write(string text)
    {
        _output.Append(GetIndent() + text);
    }

    private void WriteLine(string text = "")
    {
        if (string.IsNullOrEmpty(text))
        {
            _output.AppendLine();
        }
        else
        {
            _output.AppendLine(GetIndent() + text);
        }
    }

    private string GetIndent()
    {
        return string.Concat(Enumerable.Repeat(IndentString, _indentLevel));
    }

    private bool ClassImplementsDuckInterface(List<Declaration> members, InterfaceDeclaration duckInterface)
    {
        // Check if all methods in the duck interface are implemented by the class
        foreach (var interfaceMember in duckInterface.Members)
        {
            if (interfaceMember is not FunctionDeclaration interfaceMethod)
                continue;

            var found = false;
            foreach (var classMember in members)
            {
                if (classMember is not FunctionDeclaration classMethod)
                    continue;

                if (MethodSignaturesMatch(classMethod, interfaceMethod))
                {
                    found = true;
                    break;
                }
            }

            if (!found)
                return false;
        }

        return true;
    }

    private bool MethodSignaturesMatch(FunctionDeclaration method1, FunctionDeclaration method2)
    {
        // Must have same name
        if (method1.Name != method2.Name)
            return false;

        // Must have same number of parameters
        if (method1.Parameters.Count != method2.Parameters.Count)
            return false;

        // Check parameter types match (by string comparison - simple but works for now)
        for (int i = 0; i < method1.Parameters.Count; i++)
        {
            var type1Str = TranspileTypeReference(method1.Parameters[i].Type);
            var type2Str = TranspileTypeReference(method2.Parameters[i].Type);

            if (type1Str != type2Str)
                return false;
        }

        // Check return types match
        var returnType1Str = method1.ReturnType != null ? TranspileTypeReference(method1.ReturnType) : "void";
        var returnType2Str = method2.ReturnType != null ? TranspileTypeReference(method2.ReturnType) : "void";

        if (returnType1Str != returnType2Str)
            return false;

        return true;
    }

    /// <summary>
    /// Wraps async function return types with Task/ValueTask based on project configuration.
    /// If the return type is already Task/ValueTask, returns it as-is (explicit mode for nested scenarios).
    /// Otherwise, wraps with the configured async default type.
    /// </summary>
    private string WrapAsyncReturnType(string returnTypeString, TypeReference? returnType)
    {
        // Check if return type is already Task or ValueTask (explicit mode - no wrapping)
        if (returnTypeString.StartsWith("Task") || returnTypeString.StartsWith("ValueTask"))
        {
            return returnTypeString;
        }

        // Get the configured async default type (defaults to ValueTask)
        var asyncDefaultType = _projectConfig?.Language?.AsyncDefaultType ?? "ValueTask";

        // Wrap the return type
        if (returnTypeString == "void")
        {
            // void -> Task or ValueTask (no generic parameter)
            return asyncDefaultType;
        }
        else
        {
            // Type -> Task<Type> or ValueTask<Type>
            return $"{asyncDefaultType}<{returnTypeString}>";
        }
    }
}
