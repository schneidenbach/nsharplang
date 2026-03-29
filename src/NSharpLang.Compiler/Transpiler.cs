using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public class Transpiler
{
    private readonly CompilationUnit _compilationUnit;
    private readonly ProjectConfig? _projectConfig;
    private readonly SemanticModel? _semanticModel;
    private readonly ExpressionTypeResolver? _typeResolver;
    private readonly StringBuilder _output;
    private int _indentLevel;
    private const string IndentString = "    ";
    private string? _currentTypeName; // Track current class/struct/record for constructor names
    private bool _inInterface; // Track if we're currently inside an interface
    private bool _needsExplicitArrayType; // Track if array literals need explicit type (for var declarations)
    private readonly string? _sourceFilePath; // Source .nl file path for #line directives

    public Transpiler(CompilationUnit compilationUnit, ProjectConfig? projectConfig = null, SemanticModel? semanticModel = null, string? sourceFilePath = null)
    {
        _compilationUnit = compilationUnit;
        _projectConfig = projectConfig;
        _semanticModel = semanticModel;
        _typeResolver = semanticModel != null ? new ExpressionTypeResolver(semanticModel) : null;
        _output = new StringBuilder();
        _indentLevel = 0;
        _sourceFilePath = sourceFilePath;
    }

    public string Transpile()
    {
        _output.Clear();
        _indentLevel = 0;

        WriteLine("#nullable enable annotations");
        _output.AppendLine();

        // Check if we have test declarations to add Xunit using
        var hasTests = _compilationUnit.Declarations.OfType<TestDeclaration>().Any();

        // Collect all import directives (deduplicate System if already present)
        var hasSystemImport = _compilationUnit.Imports.Any(i => i.Namespace == "System" && i.Alias == null);

        // Always add System namespace (needed for Console, Exception, etc.) if not already present
        if (!hasSystemImport)
        {
            WriteLine("using System;");
        }

        // Add test framework using if we have test declarations
        if (hasTests)
        {
            if (_projectConfig?.TestFramework == "nunit")
            {
                WriteLine("using NUnit.Framework;");
            }
            else
            {
                WriteLine("using Xunit;");
            }
        }

        // Transpile import directives to C# using statements
        foreach (var importDirective in _compilationUnit.Imports)
        {
            TranspileImportDirective(importDirective);
        }

        // File imports are handled separately (their symbols are inlined)
        // FileImports in _compilationUnit.FileImports are not emitted as using statements

        // Separate top-level functions, tests, and type aliases from other declarations
        var topLevelFunctions = _compilationUnit.Declarations.OfType<FunctionDeclaration>().ToList();
        var testDeclarations = _compilationUnit.Declarations.OfType<TestDeclaration>().ToList();
        var typeAliases = _compilationUnit.Declarations.OfType<TypeAliasDeclaration>().ToList();
        var otherDeclarations = _compilationUnit.Declarations
            .Where(d => d is not FunctionDeclaration && d is not TestDeclaration && d is not TypeAliasDeclaration)
            .ToList();

        // Separate main function from other top-level functions (main goes in Program class)
        var mainFunction = topLevelFunctions.FirstOrDefault(f =>
            f.Name.Equals("main", StringComparison.OrdinalIgnoreCase));
        var nonMainFunctions = topLevelFunctions.Where(f =>
            !f.Name.Equals("main", StringComparison.OrdinalIgnoreCase)).ToList();

        // Add 'using static' for top-level functions class (but only if there are non-main functions)
        // This allows top-level functions to be called from within classes without qualification
        if (nonMainFunctions.Count > 0)
        {
            if (_compilationUnit.Package != null)
            {
                // Package: Functions_PackageName class
                WriteLine($"using static {_compilationUnit.Package.Name}.Functions_{_compilationUnit.Package.Name};");
            }
            else if (_compilationUnit.Namespace != null)
            {
                // Namespace: _Namespace_Name_TopLevel class
                var namespaceClass = $"_{_compilationUnit.Namespace.Name.Replace(".", "_")}_TopLevel";
                WriteLine($"using static {_compilationUnit.Namespace.Name}.{namespaceClass};");
            }
            else
            {
                // No package or namespace: _TopLevel class
                WriteLine($"using static _TopLevel;");
            }
        }

        // Emit type aliases as file-scoped using directives
        foreach (var alias in typeAliases)
        {
            TranspileTypeAlias(alias);
        }

        if (_compilationUnit.Imports.Count > 0 || _compilationUnit.FileImports.Count > 0 || hasTests || topLevelFunctions.Count > 0 || typeAliases.Count > 0)
            _output.AppendLine();

        // Namespace (from either 'namespace' or 'package' keyword)
        if (_compilationUnit.Namespace != null)
        {
            WriteLine($"namespace {_compilationUnit.Namespace.Name};");
            WriteLine();
        }
        else if (_compilationUnit.Package != null)
        {
            WriteLine($"namespace {_compilationUnit.Package.Name};");
            WriteLine();
        }

        // Transpile non-function/non-test declarations first
        foreach (var declaration in otherDeclarations)
        {
            TranspileDeclaration(declaration);
            WriteLine();
        }

        // Generate Program class with Main entry point (for exe projects)
        if (mainFunction != null)
        {
            WriteLine("public partial class Program");
            WriteLine("{");
            _indentLevel++;

            // Transpile main as static Main (capitalize for C#)
            var modifiedMain = mainFunction with
            {
                Name = "Main",  // Capitalize for C# entry point
                Modifiers = mainFunction.Modifiers | Modifiers.Static | Modifiers.Public
            };
            EmitLineDirective(mainFunction.Line);
            TranspileFunctionDeclaration(modifiedMain);
            WriteLine();

            _indentLevel--;
            WriteLine("}");
            WriteLine();
        }

        // Wrap remaining top-level functions in a generated static class
        if (nonMainFunctions.Count > 0)
        {
            string className;
            string visibility;
            string partial = "";

            // Use Functions_ prefix with package name if available, otherwise use _TopLevel
            // The Functions_ prefix avoids conflict with the namespace name (can't use 'using static' on a namespace)
            if (_compilationUnit.Package != null)
            {
                className = $"Functions_{_compilationUnit.Package.Name}";
                visibility = "public";
                partial = "partial "; // Always make package classes partial
            }
            else
            {
                className = _compilationUnit.Namespace != null
                    ? $"_{_compilationUnit.Namespace.Name.Replace(".", "_")}_TopLevel"
                    : "_TopLevel";
                visibility = "internal";
            }

            WriteLine($"{visibility} static {partial}class {className}");
            WriteLine("{");
            _indentLevel++;

            foreach (var func in nonMainFunctions)
            {
                // Package functions are public static, others are internal static
                var originalModifiers = func.Modifiers;
                var staticModifier = Modifiers.Static;
                var visibilityModifier = _compilationUnit.Package != null ? Modifiers.Public : Modifiers.Internal;
                var modifiedFunc = func with { Modifiers = originalModifiers | staticModifier | visibilityModifier };
                EmitLineDirective(func.Line);
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

            if (_projectConfig?.TestFramework == "nunit")
            {
                WriteLine("[TestFixture]");
            }
            WriteLine($"public class {className}");
            WriteLine("{");
            _indentLevel++;

            foreach (var test in testDeclarations)
            {
                EmitLineDirective(test.Line);
                TranspileTestDeclaration(test);
            }

            _indentLevel--;
            WriteLine("}");
        }

        EmitLineDefault();

        return _output.ToString();
    }

    private void TranspileImportDirective(ImportDirective importDirective)
    {
        // N# import directives transpile to C# using statements
        if (importDirective.Alias != null)
        {
            WriteLine($"using {importDirective.Alias} = {importDirective.Namespace};");
        }
        else
        {
            WriteLine($"using {importDirective.Namespace};");
        }
    }

    private void TranspileDeclaration(Declaration declaration)
    {
        EmitLineDirective(declaration.Line);

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

        // Check if test contains await - if so, make it async
        var containsAwait = ContainsAwait(test.Body);

        var isNUnit = _projectConfig?.TestFramework == "nunit";
        WriteLine(isNUnit ? "[Test]" : "[Fact]");
        if (containsAwait)
        {
            WriteLine($"public async Task {methodName}()");
        }
        else
        {
            WriteLine($"public void {methodName}()");
        }
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

            // Operator overloads and conversion operators must be public static
            if (func.IsOperatorOverload || func.IsConversionOperator)
            {
                modifiers = "public static ";
            }
            // If no explicit visibility modifier, apply naming convention
            else if (!func.Modifiers.HasFlag(Modifiers.Public) && !func.Modifiers.HasFlag(Modifiers.Private) &&
                !func.Modifiers.HasFlag(Modifiers.Protected) && !func.Modifiers.HasFlag(Modifiers.Internal))
            {
                modifiers = char.IsUpper(func.Name[0])
                    ? "public " + modifiers
                    : "private " + modifiers;
            }
        }

        var typeParams = func.TypeParameters != null && func.TypeParameters.Count > 0
            ? $"<{string.Join(", ", func.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        var parameters = string.Join(", ", func.Parameters.Select(TranspileParameter));
        var returnType = func.ReturnType != null ? TranspileTypeReference(func.ReturnType) : "void";

        // Handle async implicit wrapping (but NOT for async iterators)
        // Async iterators return IAsyncEnumerable<T>, which should not be wrapped in Task/ValueTask
        if (func.Modifiers.HasFlag(Modifiers.Async) && !func.IsAsyncIterator)
        {
            // Check if this is an entry point (Main function) - C# doesn't support async ValueTask Main()
            var isEntryPoint = func.Name.Equals("Main", StringComparison.Ordinal);
            returnType = WrapAsyncReturnType(returnType, func.ReturnType, isEntryPoint);
        }

        // Determine function name (operator keyword for overloads and conversions)
        if (func.IsConversionOperator)
        {
            // For conversion operators, the "return type" is actually the target type
            // Syntax: public static implicit/explicit operator TargetType(SourceType source)
            var conversionKeyword = func.IsImplicitConversion ? "implicit" : "explicit";
            Write($"{modifiers}{conversionKeyword} operator {returnType}({parameters})");
        }
        else
        {
            var functionName = func.IsOperatorOverload ? $"operator {func.OperatorSymbol}" : func.Name;
            Write($"{modifiers}{returnType} {functionName}{typeParams}({parameters})");
        }

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

        // Infer visibility based on naming convention (PascalCase = public, camelCase = private/internal)
        if (!cls.Modifiers.HasFlag(Modifiers.Public) &&
            !cls.Modifiers.HasFlag(Modifiers.Private) && !cls.Modifiers.HasFlag(Modifiers.Protected) &&
            !cls.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (cls.Modifiers.HasFlag(Modifiers.File))
            {
                // File-local types cannot combine `file` with accessibility modifiers in C#.
            }
            else if (char.IsUpper(cls.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
            else if (_currentTypeName != null)
            {
                // Nested type with camelCase gets private
                modifiers = "private " + modifiers;
            }
            // Top-level camelCase types get internal (default in C#)
        }
        var typeParams = cls.TypeParameters != null && cls.TypeParameters.Count > 0
            ? $"<{string.Join(", ", cls.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}class {cls.Name}{typeParams}");

        // Emit primary constructor parameters (C# 12)
        if (cls.PrimaryConstructorParameters != null && cls.PrimaryConstructorParameters.Count > 0)
        {
            _output.Append("(");
            _output.Append(string.Join(", ", cls.PrimaryConstructorParameters.Select(TranspileParameter)));
            _output.Append(")");
        }

        var bases = new List<string>();
        if (cls.BaseClass != null)
            bases.Add(TranspileTypeReference(cls.BaseClass));
        bases.AddRange(cls.Interfaces.Select(TranspileTypeReference));

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

        // Infer visibility based on naming convention (PascalCase = public, camelCase = private/internal)
        if (!str.Modifiers.HasFlag(Modifiers.Public) &&
            !str.Modifiers.HasFlag(Modifiers.Private) && !str.Modifiers.HasFlag(Modifiers.Protected) &&
            !str.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (str.Modifiers.HasFlag(Modifiers.File))
            {
                // File-local types cannot combine `file` with accessibility modifiers in C#.
            }
            else if (char.IsUpper(str.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
            else if (_currentTypeName != null)
            {
                modifiers = "private " + modifiers;
            }
        }
        var typeParams = str.TypeParameters != null && str.TypeParameters.Count > 0
            ? $"<{string.Join(", ", str.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        Write($"{modifiers}struct {str.Name}{typeParams}");

        // Emit primary constructor parameters (C# 12)
        if (str.PrimaryConstructorParameters != null && str.PrimaryConstructorParameters.Count > 0)
        {
            _output.Append("(");
            _output.Append(string.Join(", ", str.PrimaryConstructorParameters.Select(TranspileParameter)));
            _output.Append(")");
        }

        var bases = new List<string>();
        bases.AddRange(str.Interfaces.Select(TranspileTypeReference));

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

        // Infer visibility based on naming convention (PascalCase = public, camelCase = private/internal)
        if (!rec.Modifiers.HasFlag(Modifiers.Public) &&
            !rec.Modifiers.HasFlag(Modifiers.Private) && !rec.Modifiers.HasFlag(Modifiers.Protected) &&
            !rec.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (rec.Modifiers.HasFlag(Modifiers.File))
            {
                // File-local types cannot combine `file` with accessibility modifiers in C#.
            }
            else if (char.IsUpper(rec.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
            else if (_currentTypeName != null)
            {
                modifiers = "private " + modifiers;
            }
        }
        var typeParams = rec.TypeParameters != null && rec.TypeParameters.Count > 0
            ? $"<{string.Join(", ", rec.TypeParameters.Select(tp => tp.Name))}>"
            : "";

        // C# 10: record struct for value-type records
        var recordKeyword = rec.IsStruct ? "record struct" : "record";
        Write($"{modifiers}{recordKeyword} {rec.Name}{typeParams}");

        // Emit primary constructor parameters (C# 12)
        if (rec.PrimaryConstructorParameters != null && rec.PrimaryConstructorParameters.Count > 0)
        {
            _output.Append("(");
            _output.Append(string.Join(", ", rec.PrimaryConstructorParameters.Select(TranspileParameter)));
            _output.Append(")");
        }

        var bases = new List<string>();
        bases.AddRange(rec.Interfaces.Select(TranspileTypeReference));

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
        // Duck interfaces are type-erased - skip entirely
        if (iface.IsDuckInterface)
            return;

        TranspileAttributes(iface.Attributes);

        var modifiers = GetModifierString(iface.Modifiers);
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

        // Infer visibility based on naming convention (PascalCase = public, camelCase = private/internal)
        if (!enm.Modifiers.HasFlag(Modifiers.Public) &&
            !enm.Modifiers.HasFlag(Modifiers.Private) && !enm.Modifiers.HasFlag(Modifiers.Protected) &&
            !enm.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (enm.Modifiers.HasFlag(Modifiers.File))
            {
                // File-local types cannot combine `file` with accessibility modifiers in C#.
            }
            else if (char.IsUpper(enm.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
            else if (_currentTypeName != null)
            {
                modifiers = "private " + modifiers;
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

        // Infer visibility based on naming convention (PascalCase = public, camelCase = private/internal)
        if (!union.Modifiers.HasFlag(Modifiers.Public) &&
            !union.Modifiers.HasFlag(Modifiers.Private) && !union.Modifiers.HasFlag(Modifiers.Protected) &&
            !union.Modifiers.HasFlag(Modifiers.Internal))
        {
            if (union.Modifiers.HasFlag(Modifiers.File))
            {
                // File-local types cannot combine `file` with accessibility modifiers in C#.
            }
            else if (char.IsUpper(union.Name[0]))
            {
                modifiers = "public " + modifiers;
            }
            else if (_currentTypeName != null)
            {
                modifiers = "private " + modifiers;
            }
        }

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
        // Emit as C# file-scoped using alias with fully qualified type names
        var fqnType = TranspileTypeReferenceForUsing(alias.Type);
        WriteLine($"using {alias.Name} = {fqnType};");
    }

    // Well-known .NET type names mapped to their fully qualified names
    private static readonly Dictionary<string, string> WellKnownTypeFullNames = new()
    {
        // System
        { "Action", "System.Action" },
        { "Func", "System.Func" },
        { "Tuple", "System.Tuple" },
        { "ValueTuple", "System.ValueTuple" },
        { "Exception", "System.Exception" },
        { "Console", "System.Console" },
        { "Math", "System.Math" },
        { "Guid", "System.Guid" },
        { "DateTime", "System.DateTime" },
        { "DateTimeOffset", "System.DateTimeOffset" },
        { "TimeSpan", "System.TimeSpan" },
        { "Uri", "System.Uri" },
        { "Type", "System.Type" },
        { "Nullable", "System.Nullable" },
        { "IDisposable", "System.IDisposable" },
        { "IAsyncDisposable", "System.IAsyncDisposable" },
        { "IComparable", "System.IComparable" },
        { "IEquatable", "System.IEquatable" },
        { "EventHandler", "System.EventHandler" },
        { "Lazy", "System.Lazy" },
        // System.Collections.Generic
        { "List", "System.Collections.Generic.List" },
        { "Dictionary", "System.Collections.Generic.Dictionary" },
        { "HashSet", "System.Collections.Generic.HashSet" },
        { "Queue", "System.Collections.Generic.Queue" },
        { "Stack", "System.Collections.Generic.Stack" },
        { "LinkedList", "System.Collections.Generic.LinkedList" },
        { "SortedDictionary", "System.Collections.Generic.SortedDictionary" },
        { "SortedSet", "System.Collections.Generic.SortedSet" },
        { "SortedList", "System.Collections.Generic.SortedList" },
        { "IEnumerable", "System.Collections.Generic.IEnumerable" },
        { "IList", "System.Collections.Generic.IList" },
        { "IDictionary", "System.Collections.Generic.IDictionary" },
        { "ICollection", "System.Collections.Generic.ICollection" },
        { "IReadOnlyList", "System.Collections.Generic.IReadOnlyList" },
        { "IReadOnlyCollection", "System.Collections.Generic.IReadOnlyCollection" },
        { "IReadOnlyDictionary", "System.Collections.Generic.IReadOnlyDictionary" },
        { "KeyValuePair", "System.Collections.Generic.KeyValuePair" },
        { "ISet", "System.Collections.Generic.ISet" },
        // System.Threading.Tasks
        { "Task", "System.Threading.Tasks.Task" },
        { "ValueTask", "System.Threading.Tasks.ValueTask" },
        // System.IO
        { "Stream", "System.IO.Stream" },
        { "MemoryStream", "System.IO.MemoryStream" },
        { "StreamReader", "System.IO.StreamReader" },
        { "StreamWriter", "System.IO.StreamWriter" },
        { "TextReader", "System.IO.TextReader" },
        { "TextWriter", "System.IO.TextWriter" },
    };

    private static string GetFullyQualifiedName(string name)
    {
        return WellKnownTypeFullNames.TryGetValue(name, out var fqn) ? fqn : name;
    }

    /// <summary>
    /// Like TranspileTypeReference but emits fully qualified names for well-known .NET types.
    /// Used for file-scoped using alias directives.
    /// </summary>
    private string TranspileTypeReferenceForUsing(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => GetFullyQualifiedName(TranspileSimpleTypeReference(simple)),
            GenericTypeReference generic => $"{GetFullyQualifiedName(generic.Name)}<{string.Join(", ", generic.TypeArguments.Select(TranspileTypeReferenceForUsing))}>",
            ArrayTypeReference array => $"{TranspileTypeReferenceForUsing(array.ElementType)}[]",
            NullableTypeReference nullable => $"{TranspileTypeReferenceForUsing(nullable.InnerType)}?",
            TupleTypeReference tuple => TranspileTupleTypeForUsing(tuple),
            FunctionTypeReference func => TranspileFunctionTypeForUsing(func),
            _ => throw new Exception($"Unsupported type reference in using alias: {typeRef.GetType().Name}")
        };
    }

    private string TranspileTupleTypeForUsing(TupleTypeReference tuple)
    {
        var elements = string.Join(", ", tuple.Elements.Select(e =>
        {
            var type = TranspileTypeReferenceForUsing(e.Type);
            return e.Name != null ? $"{type} {e.Name}" : type;
        }));
        return $"({elements})";
    }

    private string TranspileFunctionTypeForUsing(FunctionTypeReference func)
    {
        // Func<void> maps to System.Action
        if (func.ReturnType is SimpleTypeReference simple && simple.Name == "void")
        {
            if (func.ParameterTypes.Count == 0)
                return "System.Action";

            var paramTypes = string.Join(", ", func.ParameterTypes.Select(TranspileTypeReferenceForUsing));
            return $"System.Action<{paramTypes}>";
        }

        // Regular Func<T>
        if (func.ParameterTypes.Count == 0)
        {
            return $"System.Func<{TranspileTypeReferenceForUsing(func.ReturnType)}>";
        }

        var allTypes = string.Join(", ",
            func.ParameterTypes.Select(TranspileTypeReferenceForUsing).Append(TranspileTypeReferenceForUsing(func.ReturnType)));
        return $"System.Func<{allTypes}>";
    }

    private void TranspilePreprocessorDeclaration(PreprocessorDeclaration preprocessor)
    {
        // Pass-through to C# - preprocessor directives are emitted as-is
        WriteLine(preprocessor.Directive);
    }

    private void TranspileFieldDeclaration(FieldDeclaration field)
    {
        TranspileAttributes(field.Attributes);

        var hasReadonly = field.PropertyModifier.HasFlag(PropertyModifier.Readonly);
        var hasInit = field.PropertyModifier.HasFlag(PropertyModifier.Init);
        var hasRequired = field.PropertyModifier.HasFlag(PropertyModifier.Required);

        // Remove readonly and required from modifiers - they'll be handled separately
        var modifiersToEmit = field.Modifiers & ~(Modifiers.Readonly | Modifiers.Required);
        var modifiers = GetModifierString(modifiersToEmit);

        // Handle type inference - if Type is null, infer from initializer
        string type;
        if (field.Type == null)
        {
            if (field.Initializer == null)
            {
                throw new Exception($"Field '{field.Name}' must have either a type or an initializer");
            }
            type = InferTypeFromExpression(field.Initializer);
        }
        else
        {
            type = TranspileTypeReference(field.Type);
        }

        // Determine visibility based on naming convention if no explicit modifier
        if (!field.Modifiers.HasFlag(Modifiers.Public) && !field.Modifiers.HasFlag(Modifiers.Private) &&
            !field.Modifiers.HasFlag(Modifiers.Protected) && !field.Modifiers.HasFlag(Modifiers.Internal))
        {
            modifiers = char.IsUpper(field.Name[0]) ? "public " + modifiers : "private " + modifiers;
        }

        // Add required modifier if present
        if (hasRequired)
        {
            modifiers += "required ";
        }

        // For readonly or init fields, use { get; init; } instead of { get; set; }
        var accessors = (hasReadonly || hasInit) ? "{ get; init; }" : "{ get; set; }";

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

        var modifiers = GetModifierString(prop.Modifiers);
        var hasInit = prop.PropertyModifier.HasFlag(PropertyModifier.Init);
        var hasRequired = prop.PropertyModifier.HasFlag(PropertyModifier.Required);

        // Apply convention-based visibility if no explicit modifier
        if (!prop.Modifiers.HasFlag(Modifiers.Public) && !prop.Modifiers.HasFlag(Modifiers.Private) &&
            !prop.Modifiers.HasFlag(Modifiers.Protected) && !prop.Modifiers.HasFlag(Modifiers.Internal))
        {
            modifiers = char.IsUpper(prop.Name[0]) ? "public " + modifiers : "private " + modifiers;
        }

        // Add required modifier if present
        if (hasRequired)
        {
            modifiers += "required ";
        }

        // Expression-bodied property
        if (prop.ExpressionBody != null)
        {
            var type = TranspileTypeReference(prop.Type!);
            WriteLine($"{modifiers}{type} {prop.Name} => {TranspileExpression(prop.ExpressionBody)};");
        }
        // Auto-property (no custom get/set bodies)
        else if (prop.GetBody == null && prop.SetBody == null)
        {
            var type = TranspileTypeReference(prop.Type!);
            var accessors = hasInit ? "{ get; init; }" : "{ get; set; }";
            WriteLine($"{modifiers}{type} {prop.Name} {accessors}");
        }
        else
        {
            // Regular property with custom get/set blocks
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
                WriteLine(hasInit ? "init" : "set");
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

        // Add parameter attributes inline (e.g., [FromBody] [Required])
        if (param.Attributes is { Count: > 0 })
        {
            foreach (var attr in param.Attributes)
            {
                var args = attr.Arguments.Count > 0
                    ? $"({string.Join(", ", attr.Arguments.Select(a => TranspileExpression(a.Value)))})"
                    : "";
                result += $"[{attr.Name}{args}] ";
            }
        }

        // Add params/ref/out modifier
        if (param.Modifier == ParameterModifier.Params)
            result += "params ";
        else if (param.Modifier == ParameterModifier.Ref)
            result += "ref ";
        else if (param.Modifier == ParameterModifier.Out)
            result += "out ";

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
        // Don't emit #line for block statements — they are structural braces,
        // and the individual statements inside will have their own directives.
        if (statement is not BlockStatement)
            EmitLineDirective(statement.Line);

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
            case AwaitForEachStatement awaitForeachStmt:
                TranspileAwaitForeachStatement(awaitForeachStmt);
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
                if (yieldStmt.Value != null)
                {
                    WriteLine($"yield return {TranspileExpression(yieldStmt.Value)};");
                }
                else
                {
                    WriteLine("yield break;");
                }
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
            case LockStatement lockStmt:
                TranspileLockStatement(lockStmt);
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
            case LocalFunctionStatement localFunc:
                TranspileLocalFunction(localFunc);
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
        var condition = assertStmt.Condition;
        var isNUnit = _projectConfig?.TestFramework == "nunit";

        switch (condition)
        {
            case BinaryExpression binExpr:
                TranspileBinaryAssert(binExpr, isNUnit);
                break;

            case IsExpression isExpr:
                var typeName = TranspileTypeReference(isExpr.Type);
                var expr = TranspileExpression(isExpr.Expression);
                if (isNUnit)
                {
                    // assert x is Type → Assert.That(x, Is.InstanceOf<Type>())
                    WriteLine($"Assert.That({expr}, Is.InstanceOf<{typeName}>());");
                }
                else
                {
                    // assert x is Type → Assert.IsType<Type>(x)
                    WriteLine($"Assert.IsType<{typeName}>({expr});");
                }
                break;

            default:
                // Simple boolean expression: assert x
                if (isNUnit)
                {
                    WriteLine($"Assert.That({TranspileExpression(condition)}, Is.True);");
                }
                else
                {
                    WriteLine($"Assert.True({TranspileExpression(condition)});");
                }
                break;
        }
    }

    private void TranspileBinaryAssert(BinaryExpression binExpr, bool isNUnit)
    {
        var left = TranspileExpression(binExpr.Left);
        var right = TranspileExpression(binExpr.Right);

        if (isNUnit)
        {
            TranspileBinaryAssertNUnit(binExpr, left, right);
        }
        else
        {
            TranspileBinaryAssertXUnit(binExpr, left, right);
        }
    }

    private void TranspileBinaryAssertXUnit(BinaryExpression binExpr, string left, string right)
    {
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

    private void TranspileBinaryAssertNUnit(BinaryExpression binExpr, string left, string right)
    {
        switch (binExpr.Operator)
        {
            case BinaryOperator.Equal:
                // assert x == y → Assert.That(x, Is.EqualTo(y))
                WriteLine($"Assert.That({left}, Is.EqualTo({right}));");
                break;

            case BinaryOperator.NotEqual:
                if (binExpr.Right is NullLiteralExpression)
                {
                    // assert x != null → Assert.That(x, Is.Not.Null)
                    WriteLine($"Assert.That({left}, Is.Not.Null);");
                }
                else if (binExpr.Left is NullLiteralExpression)
                {
                    // assert null != x → Assert.That(x, Is.Not.Null)
                    WriteLine($"Assert.That({right}, Is.Not.Null);");
                }
                else
                {
                    // assert x != y → Assert.That(x, Is.Not.EqualTo(y))
                    WriteLine($"Assert.That({left}, Is.Not.EqualTo({right}));");
                }
                break;

            case BinaryOperator.Greater:
                // assert x > y → Assert.That(x, Is.GreaterThan(y))
                WriteLine($"Assert.That({left}, Is.GreaterThan({right}));");
                break;

            case BinaryOperator.Less:
                // assert x < y → Assert.That(x, Is.LessThan(y))
                WriteLine($"Assert.That({left}, Is.LessThan({right}));");
                break;

            case BinaryOperator.GreaterOrEqual:
                // assert x >= y → Assert.That(x, Is.GreaterThanOrEqualTo(y))
                WriteLine($"Assert.That({left}, Is.GreaterThanOrEqualTo({right}));");
                break;

            case BinaryOperator.LessOrEqual:
                // assert x <= y → Assert.That(x, Is.LessThanOrEqualTo(y))
                WriteLine($"Assert.That({left}, Is.LessThanOrEqualTo({right}));");
                break;

            default:
                // Default to Assert.That(..., Is.True)
                var defaultOp = binExpr.Operator switch
                {
                    BinaryOperator.Add => "+",
                    BinaryOperator.Subtract => "-",
                    BinaryOperator.And => "&&",
                    BinaryOperator.Or => "||",
                    _ => "??"
                };
                WriteLine($"Assert.That({left} {defaultOp} {right}, Is.True);");
                break;
        }
    }

    private void TranspileLocalFunction(LocalFunctionStatement localFunc)
    {
        var func = localFunc.Function;

        // Build modifiers for local function (only 'static' and 'async' are valid for local functions)
        var modifiers = new List<string>();
        if (func.Modifiers.HasFlag(Modifiers.Static))
            modifiers.Add("static");
        if (func.Modifiers.HasFlag(Modifiers.Async))
            modifiers.Add("async");

        var modifierString = modifiers.Count > 0 ? string.Join(" ", modifiers) + " " : "";

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

        Write($"{modifierString}{returnType} {func.Name}{typeParams}({parameters})");

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
            // Expression-bodied local function
            WriteLine($" => {TranspileExpression(func.ExpressionBody)};");
        }
    }

    private void TranspileVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        var type = varDecl.Type != null ? TranspileTypeReference(varDecl.Type) : "var";
        var keyword = varDecl.Kind == VariableKind.Const ? "const " :
                     varDecl.Kind == VariableKind.Readonly ? "readonly " : "";

        if (varDecl.Initializer != null)
        {
            // Set flag to indicate we need explicit array types for var declarations
            // C# collection expressions [1, 2, 3] don't work with var, need new int[] { 1, 2, 3 }
            var previousFlag = _needsExplicitArrayType;
            _needsExplicitArrayType = (varDecl.Type == null); // true if using var

            var initializer = TranspileExpression(varDecl.Initializer);

            _needsExplicitArrayType = previousFlag; // restore

            WriteLine($"{keyword}{type} {varDecl.Name} = {initializer};");
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
                // Try to resolve the actual return type
                string resultType = "object?";
                string resultInitializer = "null";

                if (_typeResolver != null)
                {
                    var returnType = _typeResolver.ResolveExpressionType(tupleDecl.Initializer);
                    if (returnType != null)
                    {
                        resultType = GetCSharpTypeName(returnType);
                        // Use default for value types, null for reference types
                        resultInitializer = returnType.IsValueType ? "default" : "null";
                    }
                }

                WriteLine($"{resultType} {resultVar} = {resultInitializer};");
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

    private void TranspileAwaitForeachStatement(AwaitForEachStatement awaitForeachStmt)
    {
        WriteLine($"await foreach (var {awaitForeachStmt.VariableName} in {TranspileExpression(awaitForeachStmt.Collection)})");
        TranspileStatement(awaitForeachStmt.Body);
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

    private void TranspileLockStatement(LockStatement lockStmt)
    {
        WriteLine($"lock ({TranspileExpression(lockStmt.LockObject)})");
        TranspileStatement(lockStmt.Body);
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
            InterpolatedStringExpression interpolated => TranspileInterpolatedString(interpolated),
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
            CheckedExpression checkedExpr => $"checked({TranspileExpression(checkedExpr.Expression)})",
            UncheckedExpression uncheckedExpr => $"unchecked({TranspileExpression(uncheckedExpr.Expression)})",
            RangeExpression range => TranspileRangeExpression(range),
            SizeOfExpression sizeOf => $"sizeof({TranspileTypeReference(sizeOf.Type)})",
            TupleExpression tuple => TranspileTupleExpression(tuple),
            SpreadExpression spread => $"..{TranspileExpression(spread.Expression)}",
            OutVariableDeclarationExpression outVar => TranspileOutVariableDeclaration(outVar),
            ParenthesizedExpression paren => $"({TranspileExpression(paren.Inner)})",
            _ => throw new Exception($"Unsupported expression type: {expression.GetType().Name}")
        };
    }

    private string TranspileInterpolatedString(InterpolatedStringExpression expr)
    {
        var sb = new System.Text.StringBuilder("$\"");
        foreach (var part in expr.Parts)
        {
            switch (part)
            {
                case InterpolatedStringText text:
                    sb.Append(text.Text);
                    break;
                case InterpolatedStringHole hole:
                    sb.Append('{');
                    sb.Append(TranspileExpression(hole.Expression));
                    if (hole.FormatClause != null)
                    {
                        sb.Append(':');
                        sb.Append(hole.FormatClause);
                    }
                    sb.Append('}');
                    break;
            }
        }
        sb.Append('"');
        return sb.ToString();
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

    private string TranspileOutVariableDeclaration(OutVariableDeclarationExpression outVar)
    {
        // Transpile inline out variable declaration
        // out var x  =>  out var x
        // out int x  =>  out int x
        if (outVar.Type == null)
        {
            return $"var {outVar.VariableName}";
        }
        else
        {
            var type = TranspileTypeReference(outVar.Type);
            return $"{type} {outVar.VariableName}";
        }
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

        // Add generic type arguments if present
        var typeArgs = "";
        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            var typeArgList = string.Join(", ", call.TypeArguments.Select(TranspileTypeReference));
            typeArgs = $"<{typeArgList}>";
        }

        var args = string.Join(", ", call.Arguments.Select(arg =>
        {
            var prefix = "";
            if (arg.Modifier == ArgumentModifier.Ref)
                prefix = "ref ";
            else if (arg.Modifier == ArgumentModifier.Out)
                prefix = "out ";

            // Special handling for spread expressions in function calls
            // In C#, params arrays accept the array directly, not with .. operator
            // So Sum(...items) in N# becomes Sum(items) in C#, not Sum(..items)
            string argValue;
            if (arg.Value is SpreadExpression spread)
            {
                // Unwrap the spread - just transpile the inner expression
                argValue = TranspileExpression(spread.Expression);
            }
            else
            {
                argValue = TranspileExpression(arg.Value);
            }

            var result = prefix + argValue;
            return arg.Name != null ? $"{arg.Name}: {result}" : result;
        }));
        return $"{callee}{typeArgs}({args})";
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

        // If we need explicit array type (e.g., for var declarations), use explicit syntax
        // C# collection expressions [1, 2, 3] require a target type, which doesn't work with var
        if (_needsExplicitArrayType)
        {
            if (array.Elements.Count > 0)
            {
                var elementType = InferArrayElementType(array.Elements[0]);
                return $"new {elementType}[] {{ {elements} }}";
            }
            // Empty array - use object[] as fallback
            return "new object[] { }";
        }

        // Otherwise use C# 12+ collection expression syntax (target-typed)
        // Works with explicit types: List<int> list = [1, 2, 3]
        return $"[{elements}]";
    }

    private string InferArrayElementType(Expression firstElement)
    {
        return firstElement switch
        {
            // Literals - int literals might have L suffix for long
            IntLiteralExpression lit => lit.Value.EndsWith("L") || lit.Value.EndsWith("l") ? "long" : "int",
            FloatLiteralExpression lit => lit.Value.EndsWith("f") || lit.Value.EndsWith("F") ? "float" : "double",
            StringLiteralExpression => "string",
            InterpolatedStringExpression => "string",
            BoolLiteralExpression => "bool",
            NullLiteralExpression => "object",

            // New expressions - extract the type
            NewExpression newExpr when newExpr.Type != null => TranspileTypeReference(newExpr.Type),

            // Array literals (nested) - recursive
            ArrayLiteralExpression nestedArray when nestedArray.Elements.Count > 0 =>
                InferArrayElementType(nestedArray.Elements[0]) + "[]",

            // For complex expressions, fall back to var (let C# infer)
            _ => "var"
        };
    }

    private string TranspileNewExpression(NewExpression newExpr)
    {
        // Target-typed new (C# 9): new() or new { ... }
        string result;
        if (newExpr.Type == null)
        {
            // Target-typed new
            var args = string.Join(", ", newExpr.ConstructorArguments.Select(arg =>
            {
                var prefix = "";
                if (arg.Modifier == ArgumentModifier.Ref)
                    prefix = "ref ";
                else if (arg.Modifier == ArgumentModifier.Out)
                    prefix = "out ";

                var argValue = TranspileExpression(arg.Value);
                var argResult = prefix + argValue;
                return arg.Name != null ? $"{arg.Name}: {argResult}" : argResult;
            }));

            // Anonymous objects (no type, no constructor args, only initializer) should use "new" not "new()"
            if (args.Length == 0 && newExpr.Initializer != null)
            {
                result = "new";
            }
            else
            {
                result = $"new({args})";
            }
        }
        else
        {
            // Traditional new
            var type = TranspileTypeReference(newExpr.Type);
            var args = string.Join(", ", newExpr.ConstructorArguments.Select(arg =>
            {
                var prefix = "";
                if (arg.Modifier == ArgumentModifier.Ref)
                    prefix = "ref ";
                else if (arg.Modifier == ArgumentModifier.Out)
                    prefix = "out ";

                var argValue = TranspileExpression(arg.Value);
                var argResult = prefix + argValue;
                return arg.Name != null ? $"{arg.Name}: {argResult}" : argResult;
            }));

            result = $"new {type}({args})";
        }

        if (newExpr.Initializer != null)
        {
            var props = string.Join(", ", newExpr.Initializer.Properties.Select(p =>
            {
                if (p.IsIndexerInitializer && p.IndexExpression != null)
                {
                    // Indexer initializer: ["key"] = value
                    return $"[{TranspileExpression(p.IndexExpression)}] = {TranspileExpression(p.Value)}";
                }
                else
                {
                    // Property initializer: Name = value
                    return $"{p.Name} = {TranspileExpression(p.Value)}";
                }
            }));
            result += $" {{ {props} }}";
        }

        return result;
    }

    private string TranspileLambdaExpression(LambdaExpression lambda)
    {
        // Always emit with parens in C# for consistency (C# requires parens)
        var parameters = $"({string.Join(", ", lambda.Parameters.Select(p => p.Name))})";

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
            TypePattern type => TranspileTypePattern(type),
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

    private string TranspileTypePattern(TypePattern pattern)
    {
        // C# type pattern: TypeName variableName
        var typeName = TranspileTypeReference(pattern.Type);
        if (pattern.BindingName != null)
        {
            return $"{typeName} {pattern.BindingName}";
        }
        // Type pattern without binding (just type check)
        return typeName;
    }

    private string TranspileTypeReference(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => TranspileSimpleTypeReference(simple),
            GenericTypeReference generic => $"{generic.Name}<{string.Join(", ", generic.TypeArguments.Select(TranspileTypeReference))}>",
            ArrayTypeReference array => $"{TranspileTypeReference(array.ElementType)}[]",
            NullableTypeReference nullable => $"{TranspileTypeReference(nullable.InnerType)}?",
            TupleTypeReference tuple => TranspileTupleType(tuple),
            FunctionTypeReference func => TranspileFunctionType(func),
            _ => throw new Exception($"Unsupported type reference: {typeRef.GetType().Name}")
        };
    }

    private string TranspileSimpleTypeReference(SimpleTypeReference simple)
    {
        // Check if this references a duck interface - if so, type-erase to dynamic
        var duckInterface = _compilationUnit.Declarations
            .OfType<InterfaceDeclaration>()
            .FirstOrDefault(i => i.IsDuckInterface && i.Name == simple.Name);

        if (duckInterface != null)
        {
            // Duck interfaces are type-erased to dynamic in C#
            // This allows method calls to work at runtime with duck typing
            return "dynamic";
        }

        return simple.Name;
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

        if (modifiers.HasFlag(Modifiers.File)) parts.Add("file");
        if (modifiers.HasFlag(Modifiers.Public)) parts.Add("public");
        if (modifiers.HasFlag(Modifiers.Private)) parts.Add("private");
        if (modifiers.HasFlag(Modifiers.Protected)) parts.Add("protected");
        if (modifiers.HasFlag(Modifiers.Internal)) parts.Add("internal");
        if (modifiers.HasFlag(Modifiers.Static)) parts.Add("static");
        if (modifiers.HasFlag(Modifiers.Virtual)) parts.Add("virtual");
        if (modifiers.HasFlag(Modifiers.Override)) parts.Add("override");
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

    /// <summary>
    /// Emits a #line directive mapping the next generated line back to the original .nl source.
    /// Line numbers are 1-based. Only emits if source file path is set and line is valid.
    /// </summary>
    private void EmitLineDirective(int line)
    {
        if (_sourceFilePath == null || line <= 0)
            return;

        // #line directives must not be indented - they are preprocessor directives
        // Sanitize the file path: C# #line directives don't support escape sequences,
        // so strip characters that would break the directive (quotes, newlines)
        var safePath = _sourceFilePath.Replace("\"", "").Replace("\n", "").Replace("\r", "");
        _output.AppendLine($"#line {line} \"{safePath}\"");
    }

    /// <summary>
    /// Emits #line default to restore the default source mapping.
    /// </summary>
    private void EmitLineDefault()
    {
        if (_sourceFilePath == null)
            return;

        _output.AppendLine("#line default");
    }

    /// <summary>
    /// Wraps async function return types with Task/ValueTask based on project configuration.
    /// If the return type is already Task/ValueTask, returns it as-is (explicit mode for nested scenarios).
    /// Otherwise, wraps with the configured async default type.
    /// </summary>
    /// <param name="returnTypeString">The return type string to wrap</param>
    /// <param name="returnType">The original return type reference</param>
    /// <param name="isEntryPoint">If true, forces Task instead of ValueTask (C# entry points don't support ValueTask)</param>
    private string WrapAsyncReturnType(string returnTypeString, TypeReference? returnType, bool isEntryPoint = false)
    {
        // Check if return type is already Task or ValueTask (explicit mode - no wrapping)
        if (returnTypeString.StartsWith("Task") || returnTypeString.StartsWith("ValueTask"))
        {
            // If this is an entry point and user specified ValueTask, convert to Task
            // because C# doesn't support async ValueTask Main() as an entry point
            if (isEntryPoint && returnTypeString.StartsWith("ValueTask"))
            {
                return returnTypeString.Replace("ValueTask", "Task");
            }
            return returnTypeString;
        }

        // Get the configured async default type (defaults to ValueTask)
        // EXCEPTION: Entry points (Main) must use Task, not ValueTask, per C# spec
        var asyncDefaultType = isEntryPoint
            ? "Task"
            : (_projectConfig?.Language?.AsyncDefaultType ?? "ValueTask");

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

    /// <summary>
    /// Infers the C# type from an expression for property type inference.
    /// This is a simple pattern-matching approach based on the expression structure.
    /// </summary>
    private string InferTypeFromExpression(Expression expr)
    {
        return expr switch
        {
            // Specific literal types
            IntLiteralExpression => "int",
            FloatLiteralExpression => "double",
            StringLiteralExpression => "string",
            InterpolatedStringExpression => "string",
            BoolLiteralExpression => "bool",
            NullLiteralExpression => "object", // Null literal - should be caught by analyzer

            // Array literals
            ArrayLiteralExpression array when array.Elements.Count > 0 =>
                InferTypeFromExpression(array.Elements[0]) + "[]",
            ArrayLiteralExpression => "object[]", // Empty array

            // New expressions
            NewExpression newExpr when newExpr.Type != null =>
                TranspileTypeReference(newExpr.Type),

            // Identifiers and member access - use object as fallback
            // (actual type should be resolved by analyzer)
            IdentifierExpression => "object",
            MemberAccessExpression => "object",

            // Function/method calls - fallback to object
            CallExpression => "object",

            // Binary expressions - try to infer from operands
            BinaryExpression binary => InferTypeFromExpression(binary.Left),

            // Default fallback
            _ => "object"
        };
    }

    /// <summary>
    /// Checks if a statement or block contains any await expressions
    /// </summary>
    private bool ContainsAwait(Statement stmt)
    {
        return stmt switch
        {
            BlockStatement block => block.Statements.Any(ContainsAwait),
            ExpressionStatement exprStmt => ContainsAwaitInExpression(exprStmt.Expression),
            VariableDeclarationStatement varDecl => varDecl.Initializer != null && ContainsAwaitInExpression(varDecl.Initializer),
            ReturnStatement retStmt => retStmt.Value != null && ContainsAwaitInExpression(retStmt.Value),
            // For control flow, recursively check bodies
            IfStatement ifStmt => ContainsAwait(ifStmt.ThenStatement) || (ifStmt.ElseStatement != null && ContainsAwait(ifStmt.ElseStatement)),
            WhileStatement whileStmt => ContainsAwait(whileStmt.Body),
            ForeachStatement foreachStmt => ContainsAwait(foreachStmt.Body),
            TryStatement tryStmt => ContainsAwait(tryStmt.TryBlock) || tryStmt.CatchClauses.Any(c => ContainsAwait(c.Block)),
            _ => false
        };
    }

    /// <summary>
    /// Checks if an expression contains any await expressions
    /// </summary>
    private bool ContainsAwaitInExpression(Expression expr)
    {
        return expr switch
        {
            AwaitExpression => true,
            BinaryExpression binary => ContainsAwaitInExpression(binary.Left) || ContainsAwaitInExpression(binary.Right),
            UnaryExpression unary => ContainsAwaitInExpression(unary.Operand),
            CallExpression call => ContainsAwaitInExpression(call.Callee) || call.Arguments.Any(arg => ContainsAwaitInExpression(arg.Value)),
            MemberAccessExpression member => ContainsAwaitInExpression(member.Object),
            AssignmentExpression assign => ContainsAwaitInExpression(assign.Target) || ContainsAwaitInExpression(assign.Value),
            NewExpression newExpr => newExpr.Initializer != null && ContainsAwaitInExpression(newExpr.Initializer),
            _ => false
        };
    }

    private string GetCSharpTypeName(Type type)
    {
        // Handle common C# type aliases
        if (type == typeof(int)) return "int";
        if (type == typeof(long)) return "long";
        if (type == typeof(short)) return "short";
        if (type == typeof(byte)) return "byte";
        if (type == typeof(bool)) return "bool";
        if (type == typeof(float)) return "float";
        if (type == typeof(double)) return "double";
        if (type == typeof(decimal)) return "decimal";
        if (type == typeof(char)) return "char";
        if (type == typeof(string)) return "string";
        if (type == typeof(object)) return "object";
        if (type == typeof(void)) return "void";

        // Handle nullable value types
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(Nullable<>))
        {
            var underlyingType = Nullable.GetUnderlyingType(type);
            return underlyingType != null ? GetCSharpTypeName(underlyingType) + "?" : "object?";
        }

        // Handle generic types
        if (type.IsGenericType)
        {
            var genericType = type.GetGenericTypeDefinition();
            var genericArgs = type.GetGenericArguments();
            var baseName = genericType.Name.Substring(0, genericType.Name.IndexOf('`'));
            var argNames = string.Join(", ", genericArgs.Select(GetCSharpTypeName));
            return $"{baseName}<{argNames}>";
        }

        // Handle arrays
        if (type.IsArray)
        {
            var elementType = type.GetElementType();
            return elementType != null ? GetCSharpTypeName(elementType) + "[]" : "object[]";
        }

        // Default: use the type's full name
        return type.FullName ?? type.Name;
    }
}
