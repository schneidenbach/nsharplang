using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// Compiles N# AST directly to IL using System.Reflection.Emit
/// </summary>
public partial class ILCompiler
{
    private readonly struct BranchTarget(Label label, bool useLeave)
    {
        public Label Label { get; } = label;
        public bool UseLeave { get; } = useLeave;
    }

    private readonly CompilationUnit _compilationUnit;
    private readonly string _assemblyName;
    private readonly string _outputPath;
    private readonly ProjectConfig? _projectConfig;

    // Context for current method being compiled
    private ILGenerator? _currentIL;
    private Dictionary<string, LocalBuilder>? _locals;
    private Dictionary<string, int>? _parameters;
    private Dictionary<string, Type>? _parameterTypes;
    private HashSet<string>? _byRefParameters;
    private GenericTypeParameterBuilder[]? _currentGenericParameters;
    private Type? _currentReturnType;
    private Type? _expectedExpressionType;
    private Type? _currentAsyncReturnType;
    private Type? _currentAsyncResultType;
    private bool _currentAsyncReturnsValueTask;
    private Type? _currentGeneratorReturnType;
    private Type? _currentYieldElementType;
    private LocalBuilder? _currentYieldListLocal;
    private Label? _currentYieldBreakLabel;
    private bool _overflowCheckingEnabled;

    // Global context
    private TypeBuilder? _programType;
    private TypeBuilder? _testType;
    private ModuleBuilder? _moduleBuilder;
    private Dictionary<string, MethodBuilder> _methods = new();
    private Dictionary<string, ConstructorBuilder> _constructors = new();
    private Dictionary<string, TypeBuilder> _types = new();
    private readonly Dictionary<string, Type> _enumTypes = new();
    private readonly Dictionary<string, TypeBuilder> _stringEnumContainers = new();
    private Dictionary<string, FieldBuilder> _fields = new();
    private readonly Dictionary<string, object?> _fieldConstants = new();
    private readonly Dictionary<string, FieldBuilder> _primaryConstructorFields = new();
    private readonly Dictionary<string, PropertyBuilder> _indexers = new();
    private readonly Dictionary<string, IReadOnlyList<Parameter>> _declaredMethodParameters = new();
    private readonly Dictionary<FunctionDeclaration, MethodBuilder> _methodBuildersByDeclaration = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<ConstructorDeclaration, ConstructorBuilder> _constructorBuildersByDeclaration = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<string, List<DeclaredMethodOverload>> _declaredMethodOverloads = new();
    private readonly Dictionary<string, List<DeclaredConstructorOverload>> _declaredConstructorOverloads = new();
    private readonly Dictionary<Type, string> _typeKeys = new();
    private readonly Dictionary<string, TypeReference> _typeAliases = new();
    private readonly Dictionary<string, GenericTypeParameterBuilder[]> _typeGenericParameters = new();
    private readonly Dictionary<Type, AsyncSequenceAdapterInfo> _asyncSequenceAdapters = new();
    private readonly List<TypeBuilder> _generatedHelperTypes = new();
    private readonly Dictionary<DelegateSignatureKey, Type> _customDelegateTypes = new();
    private readonly Dictionary<Type, ConstructorInfo> _delegateConstructors = new();
    private readonly Dictionary<Type, MethodInfo> _delegateInvokeMethods = new();
    private readonly HashSet<string> _typesBeingDeclared = new(StringComparer.Ordinal);
    private TypeBuilder? _currentTypeBuilder;
    private int _asyncSequenceAdapterCounter = 0;
    private int _customDelegateCounter = 0;
    private bool _currentHasThis;

    // Lambda and closure support
    private int _lambdaCounter = 0;
    private int _closureCounter = 0;
    private Dictionary<string, FieldBuilder>? _closureFields;
    private readonly List<TypeBuilder> _closureTypes = new();
    private bool _liftLocalsIntoBoxes;
    private HashSet<string>? _liftedIdentifiers;
    private HashSet<string>? _liftedClosureFields;
    private FunctionDeclaration? _pendingLocalFunctionDefinition;
    private Dictionary<string, FunctionDeclaration>? _localFunctionDeclarations;

    // Control-flow targets for nested loops and switches
    private readonly Stack<BranchTarget> _breakLabels = new();
    private readonly Stack<BranchTarget> _continueLabels = new();
    private readonly List<(TestDeclaration Declaration, MethodBuilder Method)> _testMethods = new();

    private sealed record AsyncSequenceAdapterInfo(
        TypeBuilder EnumerableType,
        ConstructorBuilder EnumerableConstructor,
        TypeBuilder EnumeratorType,
        ConstructorBuilder EnumeratorConstructor);

    private sealed record DeclaredMethodOverload(FunctionDeclaration Declaration, MethodBuilder Builder);
    private sealed record DeclaredConstructorOverload(ConstructorDeclaration Declaration, ConstructorBuilder Builder);
    private sealed class DelegateSignatureKey(Type[] parameterTypes, Type returnType) : IEquatable<DelegateSignatureKey>
    {
        private readonly Type[] _parameterTypes = parameterTypes.ToArray();

        public IReadOnlyList<Type> ParameterTypes => _parameterTypes;
        public Type ReturnType { get; } = returnType;

        public bool Equals(DelegateSignatureKey? other)
        {
            return other != null
                && ReturnType == other.ReturnType
                && _parameterTypes.SequenceEqual(other._parameterTypes);
        }

        public override bool Equals(object? obj)
        {
            return ReferenceEquals(this, obj) || obj is DelegateSignatureKey other && Equals(other);
        }

        public override int GetHashCode()
        {
            var hash = new HashCode();
            hash.Add(ReturnType);
            foreach (var parameterType in _parameterTypes)
            {
                hash.Add(parameterType);
            }

            return hash.ToHashCode();
        }
    }

    private abstract record BoundCallArgument(Type ParameterType);
    private sealed record SuppliedBoundCallArgument(Argument Argument, Type ParameterType) : BoundCallArgument(ParameterType);
    private sealed record ExpressionBoundCallArgument(Expression Expression, Type ParameterType) : BoundCallArgument(ParameterType);
    private sealed record ParamsCollectionBoundCallArgument(Type ParameterType, Type ElementType, IReadOnlyList<Argument> Arguments) : BoundCallArgument(ParameterType);
    private sealed record CapturedGenericLocalBoundCallArgument(GenericLocalFunctionCapture Capture)
        : BoundCallArgument(Capture.CaptureParameterType);
    private sealed record BoundDeclaredMethodCall(
        FunctionDeclaration Declaration,
        MethodInfo Method,
        IReadOnlyList<BoundCallArgument> Arguments,
        bool IsExtensionMethod,
        IReadOnlyList<Type>? TypeArguments);
    private sealed record BoundDeclaredConstructorCall(
        ConstructorDeclaration Declaration,
        ConstructorInfo Constructor,
        IReadOnlyList<BoundCallArgument> Arguments);

    public ILCompiler(CompilationUnit compilationUnit, string assemblyName, string outputPath, ProjectConfig? projectConfig = null)
    {
        _compilationUnit = compilationUnit;
        _assemblyName = assemblyName;
        _outputPath = outputPath;
        _projectConfig = projectConfig;

        foreach (var alias in compilationUnit.Declarations.OfType<TypeAliasDeclaration>())
        {
            _typeAliases[alias.Name] = alias.Type;
        }
    }

    private bool UsesNUnitTestFramework =>
        string.Equals(_projectConfig?.TestFramework, "nunit", StringComparison.OrdinalIgnoreCase);

    private void DeclareTestMembers()
    {
        if (_testType == null)
        {
            throw new InvalidOperationException("Test type has not been declared");
        }

        _testMethods.Clear();

        var setupDeclaration = _compilationUnit.Declarations.OfType<SetupDeclaration>().FirstOrDefault();
        var teardownDeclaration = _compilationUnit.Declarations.OfType<TeardownDeclaration>().FirstOrDefault();
        var asyncTestLifetime = !UsesNUnitTestFramework && UsesAsyncTestLifetime(setupDeclaration, teardownDeclaration)
            ? ResolveTestFrameworkType("Xunit.IAsyncLifetime", "xunit.core", "xunit.v3.core")
            : null;

        ApplyTestTypeAttributes(_testType);

        if (setupDeclaration != null)
        {
            foreach (var variableDeclaration in setupDeclaration.Body.Statements.OfType<VariableDeclarationStatement>())
            {
                var fieldType = GetSetupFieldType(variableDeclaration);
                var fieldBuilder = _testType.DefineField(
                    variableDeclaration.Name,
                    fieldType,
                    FieldAttributes.Private);
                _fields[GetFieldKey(_testType, variableDeclaration.Name)] = fieldBuilder;
            }
        }

        if (UsesNUnitTestFramework)
        {
            _testType.DefineDefaultConstructor(MethodAttributes.Public);

            if (setupDeclaration != null)
            {
                DefineNUnitTestLifecycleMethod(
                    "Setup",
                    ResolveTestFrameworkType("NUnit.Framework.SetUpAttribute", "nunit.framework"),
                    ContainsAwait(setupDeclaration.Body) ? typeof(Task) : typeof(void));
            }

            if (teardownDeclaration != null)
            {
                DefineNUnitTestLifecycleMethod(
                    "Teardown",
                    ResolveTestFrameworkType("NUnit.Framework.TearDownAttribute", "nunit.framework"),
                    ContainsAwait(teardownDeclaration.Body) ? typeof(Task) : typeof(void));
            }
        }
        else if (setupDeclaration != null && asyncTestLifetime == null)
        {
            var constructorBuilder = _testType.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);
            _constructors[GetConstructorKey(_testType)] = constructorBuilder;
        }
        else
        {
            _testType.DefineDefaultConstructor(MethodAttributes.Public);
        }

        if (asyncTestLifetime != null)
        {
            DefineAsyncTestLifecycleMethod(asyncTestLifetime, "InitializeAsync");
            DefineAsyncTestLifecycleMethod(asyncTestLifetime, "DisposeAsync");
        }
        else if (!UsesNUnitTestFramework && teardownDeclaration != null)
        {
            var disposeMethod = _testType.DefineMethod(
                nameof(IDisposable.Dispose),
                MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig | MethodAttributes.Final | MethodAttributes.NewSlot,
                typeof(void),
                Type.EmptyTypes);

            var disposeInterfaceMethod = typeof(IDisposable).GetMethod(nameof(IDisposable.Dispose));
            if (disposeInterfaceMethod != null)
            {
                _testType.DefineMethodOverride(disposeMethod, disposeInterfaceMethod);
            }

            _methods[GetMethodKey(_testType, nameof(IDisposable.Dispose))] = disposeMethod;
        }

        foreach (var testDeclaration in _compilationUnit.Declarations.OfType<TestDeclaration>())
        {
            var parameterTypes = (testDeclaration.TableParameters ?? [])
                .Select(parameter => ResolveType(parameter.Type))
                .ToArray();

            var methodBuilder = _testType.DefineMethod(
                TestDescriptionToMethodName(testDeclaration.Description),
                MethodAttributes.Public | MethodAttributes.HideBySig,
                typeof(void),
                parameterTypes);

            if (testDeclaration.TableParameters != null)
            {
                for (int i = 0; i < testDeclaration.TableParameters.Count; i++)
                {
                    var parameter = testDeclaration.TableParameters[i];
                    methodBuilder.DefineParameter(i + 1, GetParameterAttributes(parameter), parameter.Name);
                }
            }

            ApplyTestMethodAttributes(methodBuilder, testDeclaration);
            _testMethods.Add((testDeclaration, methodBuilder));
        }
    }

    private void EmitTestBodies()
    {
        if (_testType == null)
        {
            throw new InvalidOperationException("Test type has not been declared");
        }

        _currentTypeBuilder = _testType;

        var setupDeclaration = _compilationUnit.Declarations.OfType<SetupDeclaration>().FirstOrDefault();
        var teardownDeclaration = _compilationUnit.Declarations.OfType<TeardownDeclaration>().FirstOrDefault();
        var usesAsyncLifetime = !UsesNUnitTestFramework && UsesAsyncTestLifetime(setupDeclaration, teardownDeclaration);

        if (UsesNUnitTestFramework)
        {
            if (setupDeclaration != null)
            {
                if (!_methods.TryGetValue(GetMethodKey(_testType, "Setup"), out var setupMethod))
                {
                    throw new InvalidOperationException("Test Setup method was not declared");
                }

                EmitTestLifecycleMethodBody(
                    setupMethod,
                    setupDeclaration.Body,
                    setupDeclaration.Body.Statements.OfType<VariableDeclarationStatement>().ToArray());
            }

            if (teardownDeclaration != null)
            {
                if (!_methods.TryGetValue(GetMethodKey(_testType, "Teardown"), out var teardownMethod))
                {
                    throw new InvalidOperationException("Test Teardown method was not declared");
                }

                EmitTestLifecycleMethodBody(teardownMethod, teardownDeclaration.Body);
            }
        }
        else if (setupDeclaration != null && !usesAsyncLifetime)
        {
            if (!_constructors.TryGetValue(GetConstructorKey(_testType), out var constructorBuilder))
            {
                throw new InvalidOperationException("Test constructor was not declared");
            }

            _currentIL = constructorBuilder.GetILGenerator();
            InitializeBodyContext(null, ContainsNestedFunction(setupDeclaration.Body));
            _currentHasThis = true;

            _currentIL.Emit(OpCodes.Ldarg_0);
            var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
            if (objectCtor == null)
            {
                throw new InvalidOperationException("Could not resolve object constructor");
            }

            _currentIL.Emit(OpCodes.Call, objectCtor);

            foreach (var variableDeclaration in setupDeclaration.Body.Statements.OfType<VariableDeclarationStatement>())
            {
                EmitSetupFieldInitialization(variableDeclaration);
            }

            foreach (var statement in setupDeclaration.Body.Statements.Where(statement => statement is not VariableDeclarationStatement))
            {
                EmitStatement(statement);
            }

            _currentIL.Emit(OpCodes.Ret);
            ClearMethodContext();
        }

        if (usesAsyncLifetime)
        {
            if (!_methods.TryGetValue(GetMethodKey(_testType, "InitializeAsync"), out var initializeAsyncMethod))
            {
                throw new InvalidOperationException("Test InitializeAsync method was not declared");
            }

            EmitTestLifecycleMethodBody(
                initializeAsyncMethod,
                setupDeclaration?.Body,
                setupDeclaration?.Body.Statements.OfType<VariableDeclarationStatement>().ToArray());

            if (!_methods.TryGetValue(GetMethodKey(_testType, "DisposeAsync"), out var disposeAsyncMethod))
            {
                throw new InvalidOperationException("Test DisposeAsync method was not declared");
            }

            EmitTestLifecycleMethodBody(disposeAsyncMethod, teardownDeclaration?.Body);
        }
        else if (!UsesNUnitTestFramework && teardownDeclaration != null)
        {
            if (!_methods.TryGetValue(GetMethodKey(_testType, nameof(IDisposable.Dispose)), out var disposeMethod))
            {
                throw new InvalidOperationException("Test Dispose method was not declared");
            }

            _currentIL = disposeMethod.GetILGenerator();
            InitializeBodyContext(null, ContainsNestedFunction(teardownDeclaration.Body));
            _currentHasThis = true;

            EmitStatement(teardownDeclaration.Body);
            _currentIL.Emit(OpCodes.Ret);
            ClearMethodContext();
        }

        foreach (var (declaration, methodBuilder) in _testMethods)
        {
            _currentIL = methodBuilder.GetILGenerator();
            InitializeBodyContext(typeof(void), ContainsNestedFunction(declaration.Body));
            _currentHasThis = true;

            if (declaration.TableParameters != null)
            {
                RegisterParameterContext(declaration.TableParameters, 1);
            }

            EmitStatement(declaration.Body);
            _currentIL.Emit(OpCodes.Ret);
            ClearMethodContext();
        }

        _currentTypeBuilder = null;
    }

    private static bool UsesAsyncTestLifetime(SetupDeclaration? setupDeclaration, TeardownDeclaration? teardownDeclaration)
    {
        return (setupDeclaration != null && ContainsAwait(setupDeclaration.Body))
            || (teardownDeclaration != null && ContainsAwait(teardownDeclaration.Body));
    }

    private void ApplyTestTypeAttributes(TypeBuilder testType)
    {
        if (!UsesNUnitTestFramework)
        {
            return;
        }

        var testFixtureAttribute = ResolveTestFrameworkType("NUnit.Framework.TestFixtureAttribute", "nunit.framework");
        ApplyMarkerAttribute(testType.SetCustomAttribute, testFixtureAttribute);
    }

    private void DefineAsyncTestLifecycleMethod(Type asyncLifetimeType, string methodName)
    {
        if (_testType == null)
        {
            throw new InvalidOperationException("Test type has not been declared");
        }

        var interfaceMethod = asyncLifetimeType.GetMethod(methodName)
            ?? throw new InvalidOperationException($"Could not resolve {asyncLifetimeType.FullName}.{methodName}()");
        var methodBuilder = _testType.DefineMethod(
            methodName,
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig | MethodAttributes.Final | MethodAttributes.NewSlot,
            interfaceMethod.ReturnType,
            Type.EmptyTypes);

        _testType.DefineMethodOverride(methodBuilder, interfaceMethod);
        _methods[GetMethodKey(_testType, methodName)] = methodBuilder;
    }

    private void DefineNUnitTestLifecycleMethod(string methodName, Type attributeType, Type returnType)
    {
        if (_testType == null)
        {
            throw new InvalidOperationException("Test type has not been declared");
        }

        var methodBuilder = _testType.DefineMethod(
            methodName,
            MethodAttributes.Public | MethodAttributes.HideBySig,
            returnType,
            Type.EmptyTypes);
        ApplyMarkerAttribute(methodBuilder.SetCustomAttribute, attributeType);
        _methods[GetMethodKey(_testType, methodName)] = methodBuilder;
    }

    private void EmitTestLifecycleMethodBody(
        MethodBuilder methodBuilder,
        BlockStatement? body,
        IReadOnlyList<VariableDeclarationStatement>? setupVariables = null)
    {
        if (_currentTypeBuilder == null)
        {
            throw new InvalidOperationException("No current test type context");
        }

        _currentIL = methodBuilder.GetILGenerator();

        var returnType = methodBuilder.ReturnType;
        var bodyReturnType = returnType;
        if (TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
        {
            _currentAsyncReturnType = returnType;
            _currentAsyncResultType = asyncResultType;
            _currentAsyncReturnsValueTask = returnsValueTask;
            bodyReturnType = asyncResultType ?? typeof(void);
        }

        InitializeBodyContext(bodyReturnType == typeof(void) ? null : bodyReturnType, body != null && ContainsNestedFunction(body));
        _currentHasThis = true;

        if (setupVariables != null)
        {
            foreach (var variableDeclaration in setupVariables)
            {
                EmitSetupFieldInitialization(variableDeclaration);
            }
        }

        if (body != null)
        {
            foreach (var statement in body.Statements.Where(statement => statement is not VariableDeclarationStatement))
            {
                EmitStatement(statement);
            }
        }

        if (_currentAsyncReturnType != null)
        {
            EmitWrapCurrentAsyncReturn();
            _currentIL.Emit(OpCodes.Ret);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ret);
        }

        ClearMethodContext();
    }

    private void EmitSetupFieldInitialization(VariableDeclarationStatement variableDeclaration)
    {
        if (_testType == null || _currentIL == null)
        {
            throw new InvalidOperationException("No test constructor context");
        }

        if (!_fields.TryGetValue(GetFieldKey(_testType, variableDeclaration.Name), out var fieldBuilder))
        {
            throw new InvalidOperationException($"Setup field {variableDeclaration.Name} was not declared");
        }

        if (variableDeclaration.Initializer == null)
        {
            return;
        }

        _currentIL.Emit(OpCodes.Ldarg_0);
        EmitExpressionWithExpectedType(variableDeclaration.Initializer, fieldBuilder.FieldType);
        _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
    }

    private void ApplyTestMethodAttributes(MethodBuilder methodBuilder, TestDeclaration testDeclaration)
    {
        if (UsesNUnitTestFramework)
        {
            ApplyNUnitTestMethodAttributes(methodBuilder, testDeclaration);
            return;
        }

        var factAttributeType = ResolveTestFrameworkType("Xunit.FactAttribute", "xunit.core", "xunit.v3.core");
        var theoryAttributeType = ResolveTestFrameworkType("Xunit.TheoryAttribute", "xunit.core", "xunit.v3.core");
        var inlineDataAttributeType = ResolveTestFrameworkType("Xunit.InlineDataAttribute", "xunit.core", "xunit.v3.core");
        var traitAttributeType = ResolveTestFrameworkType("Xunit.TraitAttribute", "xunit.core", "xunit.v3.core");

        var traitConstructor = traitAttributeType.GetConstructor(new[] { typeof(string), typeof(string) });
        if (traitConstructor == null)
        {
            throw new InvalidOperationException("Could not resolve Xunit.TraitAttribute(string, string)");
        }

        methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(
            traitConstructor,
            new object[] { "NSharpDescription", testDeclaration.Description }));

        var attributeType = testDeclaration.TableParameters != null && testDeclaration.TableCases != null
            ? theoryAttributeType
            : factAttributeType;
        ApplySkippableTestAttribute(methodBuilder, attributeType, testDeclaration.SkipReason);

        if (testDeclaration.TableCases != null)
        {
            var inlineDataConstructor = inlineDataAttributeType
                .GetConstructors()
                .FirstOrDefault(ctor =>
                {
                    var parameters = ctor.GetParameters();
                    return parameters.Length == 1 && parameters[0].ParameterType == typeof(object[]);
                });

            if (inlineDataConstructor == null)
            {
                throw new InvalidOperationException("Could not resolve Xunit.InlineDataAttribute(object[])");
            }

            foreach (var row in testDeclaration.TableCases)
            {
                var values = row.Select(GetInlineDataValue).ToArray();
                methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(
                    inlineDataConstructor,
                    new object[] { values }));
            }
        }
    }

    private void ApplyNUnitTestMethodAttributes(MethodBuilder methodBuilder, TestDeclaration testDeclaration)
    {
        var testAttributeType = ResolveTestFrameworkType("NUnit.Framework.TestAttribute", "nunit.framework");
        var testCaseAttributeType = ResolveTestFrameworkType("NUnit.Framework.TestCaseAttribute", "nunit.framework");

        if (testDeclaration.TableCases != null)
        {
            var testCaseConstructor = testCaseAttributeType
                .GetConstructors()
                .FirstOrDefault(ctor =>
                {
                    var parameters = ctor.GetParameters();
                    return parameters.Length == 1 && parameters[0].ParameterType == typeof(object[]);
                });

            if (testCaseConstructor == null)
            {
                throw new InvalidOperationException("Could not resolve NUnit.Framework.TestCaseAttribute(object[])");
            }

            foreach (var row in testDeclaration.TableCases)
            {
                var values = row.Select(GetInlineDataValue).ToArray();
                methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(
                    testCaseConstructor,
                    new object[] { values }));
            }
        }
        else
        {
            ApplyMarkerAttribute(methodBuilder.SetCustomAttribute, testAttributeType);
        }

        if (testDeclaration.SkipReason != null)
        {
            ApplyIgnoreAttribute(methodBuilder.SetCustomAttribute, testDeclaration.SkipReason);
        }
    }

    private static void ApplyMarkerAttribute(Action<CustomAttributeBuilder> applyAttribute, Type attributeType)
    {
        var constructor = attributeType.GetConstructor(Type.EmptyTypes);
        if (constructor == null)
        {
            throw new InvalidOperationException($"Could not resolve {attributeType.FullName}()");
        }

        applyAttribute(new CustomAttributeBuilder(constructor, Array.Empty<object>()));
    }

    private static void ApplyIgnoreAttribute(Action<CustomAttributeBuilder> applyAttribute, string reason)
    {
        var ignoreAttributeType = ResolveTestFrameworkType("NUnit.Framework.IgnoreAttribute", "nunit.framework");
        var constructor = ignoreAttributeType.GetConstructor(new[] { typeof(string) });
        if (constructor == null)
        {
            throw new InvalidOperationException("Could not resolve NUnit.Framework.IgnoreAttribute(string)");
        }

        applyAttribute(new CustomAttributeBuilder(constructor, new object[] { reason }));
    }

    private static void ApplySkippableTestAttribute(MethodBuilder methodBuilder, Type attributeType, string? skipReason)
    {
        var constructor = attributeType.GetConstructor(Type.EmptyTypes);
        if (constructor == null)
        {
            throw new InvalidOperationException($"Could not resolve {attributeType.FullName}()");
        }

        if (skipReason == null)
        {
            methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(constructor, Array.Empty<object>()));
            return;
        }

        var skipProperty = attributeType.GetProperty("Skip");
        if (skipProperty == null)
        {
            throw new InvalidOperationException($"Could not resolve {attributeType.FullName}.Skip");
        }

        methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(
            constructor,
            Array.Empty<object>(),
            new[] { skipProperty },
            new object[] { skipReason }));
    }

    private static Type ResolveTestFrameworkType(string fullTypeName, params string[] assemblyNames)
    {
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            var loadedType = assembly.GetType(fullTypeName, throwOnError: false);
            if (loadedType != null)
            {
                return loadedType;
            }
        }

        foreach (var assemblyName in assemblyNames)
        {
            try
            {
                var assembly = Assembly.Load(new AssemblyName(assemblyName));
                var loadedType = assembly.GetType(fullTypeName, throwOnError: false);
                if (loadedType != null)
                {
                    return loadedType;
                }
            }
            catch
            {
                // Try the next known test-framework assembly name.
            }
        }

        throw new InvalidOperationException($"Could not resolve required test framework type {fullTypeName}");
    }

    private Type GetSetupFieldType(VariableDeclarationStatement variableDeclaration)
    {
        if (variableDeclaration.Type != null)
        {
            return ResolveType(variableDeclaration.Type);
        }

        if (variableDeclaration.Initializer != null)
        {
            return GetExpressionType(variableDeclaration.Initializer);
        }

        return typeof(object);
    }

    private static object? GetInlineDataValue(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression intLiteral => ParseIntLiteralValue(intLiteral.Value),
            FloatLiteralExpression floatLiteral => ParseFloatLiteralValue(floatLiteral.Value),
            StringLiteralExpression stringLiteral => stringLiteral.Value.Trim('"'),
            BoolLiteralExpression boolLiteral => boolLiteral.Value,
            NullLiteralExpression => null,
            _ => throw new NotSupportedException($"InlineData does not support {expression.GetType().Name} in IL compiler")
        };
    }

    private static string TestDescriptionToMethodName(string description)
    {
        var words = description.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries);
        var result = string.Concat(words.Select(word =>
            word.Length == 0
                ? string.Empty
                : char.ToUpper(word[0]) + word.Substring(1)));

        result = new string(result.Where(c => char.IsLetterOrDigit(c) || c == '_').ToArray());

        if (result.Length == 0 || !char.IsLetter(result[0]))
        {
            result = "Test_" + result;
        }

        return result;
    }

    private void ClearMethodContext()
    {
        _currentIL = null;
        _locals = null;
        _parameters = null;
        _parameterTypes = null;
        _byRefParameters = null;
        _currentReturnType = null;
        _liftLocalsIntoBoxes = false;
        _liftedIdentifiers = null;
        _liftedClosureFields = null;
        _currentAsyncReturnType = null;
        _currentAsyncResultType = null;
        _currentAsyncReturnsValueTask = false;
        _currentGeneratorReturnType = null;
        _currentYieldElementType = null;
        _currentYieldListLocal = null;
        _currentYieldBreakLabel = null;
        _localFunctionDeclarations = null;
        _currentHasThis = false;
    }

    private void InitializeBodyContext(Type? returnType, bool liftLocalsIntoBoxes)
    {
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();
        _parameterTypes = new Dictionary<string, Type>();
        _byRefParameters = new HashSet<string>();
        _currentReturnType = returnType;
        _liftLocalsIntoBoxes = liftLocalsIntoBoxes;
        _liftedIdentifiers = liftLocalsIntoBoxes ? new HashSet<string>() : null;
        _liftedClosureFields = null;
        _currentHasThis = false;
    }

    private static Type CreateStrongBoxType(Type valueType)
    {
        return typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(valueType);
    }

    private static bool RequiresTypeBuilderMemberResolution(Type type)
    {
        if (type is TypeBuilder or GenericTypeParameterBuilder)
        {
            return true;
        }

        if (type.HasElementType && type.GetElementType() is { } elementType)
        {
            return RequiresTypeBuilderMemberResolution(elementType);
        }

        return type.IsGenericType && type.GetGenericArguments().Any(RequiresTypeBuilderMemberResolution);
    }

    private static IEnumerable<Type> GetRuntimeInterfaces(Type type)
    {
        try
        {
            return type.GetInterfaces();
        }
        catch (NotSupportedException)
        {
            return Array.Empty<Type>();
        }
    }

    private sealed record ResolvedRuntimeProperty(Type PropertyType, MethodInfo? Getter);

    private static bool TryGetDeclaredRuntimeProperty(Type type, string memberName, BindingFlags bindingFlags, out PropertyInfo? property)
    {
        try
        {
            property = type.GetProperty(memberName, bindingFlags);
            return property != null;
        }
        catch (NotSupportedException)
        {
            property = null;
            return false;
        }
    }

    private static FieldInfo? TryGetDeclaredRuntimeField(Type type, string memberName, BindingFlags bindingFlags)
    {
        try
        {
            return type.GetField(memberName, bindingFlags);
        }
        catch (NotSupportedException)
        {
            if (type.IsGenericType && !type.IsGenericTypeDefinition && RequiresTypeBuilderMemberResolution(type))
            {
                var genericDefinition = type.GetGenericTypeDefinition();
                var openField = TryGetDeclaredRuntimeField(genericDefinition, memberName, bindingFlags);
                return openField != null ? TypeBuilder.GetField(type, openField) : null;
            }

            return null;
        }
    }

    private static ResolvedRuntimeProperty? ResolveRuntimeProperty(Type type, string memberName, BindingFlags bindingFlags)
    {
        return ResolveRuntimeProperty(type, memberName, bindingFlags, new HashSet<Type>());
    }

    private static ResolvedRuntimeProperty? ResolveRuntimeProperty(Type type, string memberName, BindingFlags bindingFlags, HashSet<Type> visited)
    {
        if (!visited.Add(type))
        {
            return null;
        }

        if (TryGetDeclaredRuntimeProperty(type, memberName, bindingFlags, out var property))
        {
            return new ResolvedRuntimeProperty(property!.GetMethod?.ReturnType ?? property.PropertyType, property.GetMethod);
        }

        if (type.IsGenericType && !type.IsGenericTypeDefinition && RequiresTypeBuilderMemberResolution(type))
        {
            var genericDefinition = type.GetGenericTypeDefinition();
            if (TryGetDeclaredRuntimeProperty(genericDefinition, memberName, bindingFlags, out var openProperty)
                && openProperty?.GetMethod != null)
            {
                var getter = TypeBuilder.GetMethod(type, openProperty.GetMethod);
                return new ResolvedRuntimeProperty(getter.ReturnType, getter);
            }
        }

        foreach (var interfaceType in GetRuntimeInterfaces(type))
        {
            var propertyFromInterface = ResolveRuntimeProperty(interfaceType, memberName, bindingFlags, visited);
            if (propertyFromInterface != null)
            {
                return propertyFromInterface;
            }
        }

        return type.BaseType != null
            ? ResolveRuntimeProperty(type.BaseType, memberName, bindingFlags, visited)
            : null;
    }

    private static FieldInfo? ResolveRuntimeField(Type type, string memberName, BindingFlags bindingFlags)
    {
        return ResolveRuntimeField(type, memberName, bindingFlags, new HashSet<Type>());
    }

    private static FieldInfo? ResolveRuntimeField(Type type, string memberName, BindingFlags bindingFlags, HashSet<Type> visited)
    {
        if (!visited.Add(type))
        {
            return null;
        }

        var field = TryGetDeclaredRuntimeField(type, memberName, bindingFlags);
        if (field != null)
        {
            return field;
        }

        foreach (var interfaceType in GetRuntimeInterfaces(type))
        {
            field = ResolveRuntimeField(interfaceType, memberName, bindingFlags, visited);
            if (field != null)
            {
                return field;
            }
        }

        return type.BaseType != null
            ? ResolveRuntimeField(type.BaseType, memberName, bindingFlags, visited)
            : null;
    }

    private static ConstructorInfo GetStrongBoxConstructor(Type valueType)
    {
        var strongBoxType = CreateStrongBoxType(valueType);
        var openConstructor = typeof(System.Runtime.CompilerServices.StrongBox<>)
            .GetConstructor(new[] { typeof(System.Runtime.CompilerServices.StrongBox<>).GetGenericArguments()[0] })
            ?? throw new InvalidOperationException("Could not resolve StrongBox<T>(T)");

        if (RequiresTypeBuilderMemberResolution(valueType))
        {
            return TypeBuilder.GetConstructor(strongBoxType, openConstructor);
        }

        return strongBoxType.GetConstructor(new[] { valueType })
            ?? throw new InvalidOperationException($"Could not resolve StrongBox constructor for {valueType}");
    }

    private static FieldInfo GetStrongBoxValueField(Type strongBoxType)
    {
        var openField = typeof(System.Runtime.CompilerServices.StrongBox<>).GetField("Value")
            ?? throw new InvalidOperationException("Could not resolve StrongBox<T>.Value");

        if (strongBoxType.IsGenericType
            && strongBoxType.GetGenericArguments().Any(RequiresTypeBuilderMemberResolution))
        {
            return TypeBuilder.GetField(strongBoxType, openField);
        }

        return strongBoxType.GetField("Value")
            ?? throw new InvalidOperationException($"Could not resolve StrongBox.Value for {strongBoxType}");
    }

    private static Type GetStrongBoxValueType(Type strongBoxType)
    {
        return strongBoxType.IsGenericType && strongBoxType.GetGenericTypeDefinition() == typeof(System.Runtime.CompilerServices.StrongBox<>)
            ? strongBoxType.GetGenericArguments()[0]
            : strongBoxType;
    }

    private bool IsLiftedIdentifier(string name)
    {
        return _liftedIdentifiers?.Contains(name) == true;
    }

    private bool IsLiftedClosureField(string name)
    {
        return _liftedClosureFields?.Contains(name) == true;
    }

    private LocalBuilder DeclareNamedLocal(string name, Type valueType)
    {
        if (_currentIL == null || _locals == null)
            throw new InvalidOperationException("No IL generator context");

        var storageType = _liftLocalsIntoBoxes ? CreateStrongBoxType(valueType) : valueType;
        var local = _currentIL.DeclareLocal(storageType);
        _locals[name] = local;

        if (_liftLocalsIntoBoxes)
        {
            _liftedIdentifiers?.Add(name);
        }

        return local;
    }

    private void EmitInitializeNamedLocal(LocalBuilder local, Type valueType, bool emitDefaultValue, Expression? initializer, bool valueAlreadyOnStack = false)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        if (valueAlreadyOnStack)
        {
        }
        else if (emitDefaultValue)
        {
            EmitDefaultValue(valueType);
        }
        else if (initializer is DefaultExpression)
        {
            EmitDefaultValue(valueType);
        }
        else if (initializer != null)
        {
            EmitExpressionWithExpectedType(initializer, valueType);
        }
        else
        {
            throw new InvalidOperationException("Initializer was required but not provided");
        }

        if (local.LocalType != valueType)
        {
            _currentIL.Emit(OpCodes.Newobj, GetStrongBoxConstructor(valueType));
        }

        _currentIL.Emit(OpCodes.Stloc, local);
    }

    private void EmitLoadLiftedLocalValue(LocalBuilder local)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloc, local);
        _currentIL.Emit(OpCodes.Ldfld, GetStrongBoxValueField(local.LocalType));
    }

    private void EmitLoadLiftedLocalAddress(LocalBuilder local)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloc, local);
        _currentIL.Emit(OpCodes.Ldflda, GetStrongBoxValueField(local.LocalType));
    }

    private void EmitStoreLiftedLocalValue(LocalBuilder local, Type valueType, bool leaveValueOnStack)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        var tempLocal = _currentIL.DeclareLocal(valueType);
        _currentIL.Emit(OpCodes.Stloc, tempLocal);

        var initializedLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Ldloc, local);
        _currentIL.Emit(OpCodes.Brtrue_S, initializedLabel);
        EmitDefaultValue(valueType);
        _currentIL.Emit(OpCodes.Newobj, GetStrongBoxConstructor(valueType));
        _currentIL.Emit(OpCodes.Stloc, local);

        _currentIL.MarkLabel(initializedLabel);
        _currentIL.Emit(OpCodes.Ldloc, local);
        _currentIL.Emit(OpCodes.Ldloc, tempLocal);
        _currentIL.Emit(OpCodes.Stfld, GetStrongBoxValueField(local.LocalType));

        if (leaveValueOnStack)
        {
            _currentIL.Emit(OpCodes.Ldloc, tempLocal);
        }
    }

    private void EmitLoadLiftedClosureFieldValue(FieldInfo closureField)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldarg_0);
        _currentIL.Emit(OpCodes.Ldfld, closureField);
        _currentIL.Emit(OpCodes.Ldfld, GetStrongBoxValueField(closureField.FieldType));
    }

    private void EmitLoadLiftedClosureFieldAddress(FieldInfo closureField)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldarg_0);
        _currentIL.Emit(OpCodes.Ldfld, closureField);
        _currentIL.Emit(OpCodes.Ldflda, GetStrongBoxValueField(closureField.FieldType));
    }

    private void EmitStoreLiftedClosureFieldValue(FieldInfo closureField, Type valueType, bool leaveValueOnStack)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        var tempLocal = _currentIL.DeclareLocal(valueType);
        _currentIL.Emit(OpCodes.Stloc, tempLocal);
        _currentIL.Emit(OpCodes.Ldarg_0);
        _currentIL.Emit(OpCodes.Ldfld, closureField);
        _currentIL.Emit(OpCodes.Ldloc, tempLocal);
        _currentIL.Emit(OpCodes.Stfld, GetStrongBoxValueField(closureField.FieldType));

        if (leaveValueOnStack)
        {
            _currentIL.Emit(OpCodes.Ldloc, tempLocal);
        }
    }

    private static bool ContainsNestedFunction(BlockStatement? block)
    {
        return block != null && ContainsNestedFunction((Statement)block);
    }

    private static bool ContainsNestedFunction(Statement statement)
    {
        return statement switch
        {
            LocalFunctionStatement => true,
            BlockStatement block => block.Statements.Any(ContainsNestedFunction),
            ExpressionStatement expressionStatement => ContainsNestedFunction(expressionStatement.Expression),
            VariableDeclarationStatement variableDeclaration => variableDeclaration.Initializer != null && ContainsNestedFunction(variableDeclaration.Initializer),
            TupleDeconstructionStatement tupleDeconstruction => ContainsNestedFunction(tupleDeconstruction.Initializer),
            IfStatement ifStatement => ContainsNestedFunction(ifStatement.Condition)
                || ContainsNestedFunction(ifStatement.ThenStatement)
                || (ifStatement.ElseStatement != null && ContainsNestedFunction(ifStatement.ElseStatement)),
            ForStatement forStatement => (forStatement.Initializer != null && ContainsNestedFunction(forStatement.Initializer))
                || (forStatement.Condition != null && ContainsNestedFunction(forStatement.Condition))
                || (forStatement.Iterator != null && ContainsNestedFunction(forStatement.Iterator))
                || ContainsNestedFunction(forStatement.Body),
            ForeachStatement foreachStatement => ContainsNestedFunction(foreachStatement.Collection) || ContainsNestedFunction(foreachStatement.Body),
            AwaitForEachStatement awaitForEachStatement => ContainsNestedFunction(awaitForEachStatement.Collection) || ContainsNestedFunction(awaitForEachStatement.Body),
            WhileStatement whileStatement => ContainsNestedFunction(whileStatement.Condition) || ContainsNestedFunction(whileStatement.Body),
            ReturnStatement returnStatement => returnStatement.Value != null && ContainsNestedFunction(returnStatement.Value),
            YieldStatement yieldStatement => yieldStatement.Value != null && ContainsNestedFunction(yieldStatement.Value),
            ThrowStatement throwStatement => ContainsNestedFunction(throwStatement.Expression),
            TryStatement tryStatement => ContainsNestedFunction(tryStatement.TryBlock)
                || tryStatement.CatchClauses.Any(catchClause => ContainsNestedFunction(catchClause.Block))
                || (tryStatement.FinallyBlock != null && ContainsNestedFunction(tryStatement.FinallyBlock)),
            UsingStatement usingStatement => (usingStatement.Declaration?.Initializer != null && ContainsNestedFunction(usingStatement.Declaration.Initializer))
                || (usingStatement.Expression != null && ContainsNestedFunction(usingStatement.Expression))
                || (usingStatement.Body != null && ContainsNestedFunction(usingStatement.Body)),
            LockStatement lockStatement => ContainsNestedFunction(lockStatement.LockObject) || ContainsNestedFunction(lockStatement.Body),
            SwitchStatement switchStatement => ContainsNestedFunction(switchStatement.Value)
                || switchStatement.Cases.Any(switchCase => switchCase.Statements.Any(ContainsNestedFunction)),
            PrintStatement printStatement => ContainsNestedFunction(printStatement.Value),
            AssertStatement assertStatement => ContainsNestedFunction(assertStatement.Condition)
                || (assertStatement.Message != null && ContainsNestedFunction(assertStatement.Message)),
            AssertThrowsStatement assertThrowsStatement => ContainsNestedFunction(assertThrowsStatement.Body),
            _ => false
        };
    }

    private static bool ContainsNestedFunction(Expression expression)
    {
        return expression switch
        {
            LambdaExpression => true,
            InterpolatedStringExpression interpolatedString => interpolatedString.Parts
                .OfType<InterpolatedStringHole>()
                .Any(hole => ContainsNestedFunction(hole.Expression)),
            RangeExpression range => (range.Start != null && ContainsNestedFunction(range.Start))
                || (range.End != null && ContainsNestedFunction(range.End)),
            BinaryExpression binary => ContainsNestedFunction(binary.Left) || ContainsNestedFunction(binary.Right),
            UnaryExpression unary => ContainsNestedFunction(unary.Operand),
            MemberAccessExpression memberAccess => ContainsNestedFunction(memberAccess.Object),
            IndexAccessExpression indexAccess => ContainsNestedFunction(indexAccess.Object) || ContainsNestedFunction(indexAccess.Index),
            CallExpression call => ContainsNestedFunction(call.Callee) || call.Arguments.Any(argument => ContainsNestedFunction(argument.Value)),
            AssignmentExpression assignment => ContainsNestedFunction(assignment.Target) || ContainsNestedFunction(assignment.Value),
            TernaryExpression ternary => ContainsNestedFunction(ternary.Condition)
                || ContainsNestedFunction(ternary.ThenExpression)
                || ContainsNestedFunction(ternary.ElseExpression),
            ArrayLiteralExpression arrayLiteral => arrayLiteral.Elements.Any(ContainsNestedFunction),
            TupleExpression tupleExpression => tupleExpression.Elements.Any(element => ContainsNestedFunction(element.Value)),
            ObjectInitializerExpression initializer => initializer.Properties.Any(property =>
                (property.IndexExpression != null && ContainsNestedFunction(property.IndexExpression)) || ContainsNestedFunction(property.Value)),
            NewExpression newExpression => newExpression.ConstructorArguments.Any(argument => ContainsNestedFunction(argument.Value))
                || (newExpression.Initializer != null && ContainsNestedFunction(newExpression.Initializer)),
            CastExpression castExpression => ContainsNestedFunction(castExpression.Expression),
            IsExpression isExpression => ContainsNestedFunction(isExpression.Expression),
            MatchExpression matchExpression => ContainsNestedFunction(matchExpression.Value)
                || matchExpression.Cases.Any(matchCase =>
                    ContainsNestedFunction(matchCase.Pattern)
                    || (matchCase.Guard != null && ContainsNestedFunction(matchCase.Guard))
                    || ContainsNestedFunction(matchCase.Expression)),
            SpreadExpression spreadExpression => ContainsNestedFunction(spreadExpression.Expression),
            WithExpression withExpression => ContainsNestedFunction(withExpression.Target)
                || withExpression.Properties.Any(property =>
                    (property.IndexExpression != null && ContainsNestedFunction(property.IndexExpression)) || ContainsNestedFunction(property.Value)),
            AwaitExpression awaitExpression => ContainsNestedFunction(awaitExpression.Expression),
            ThrowExpression throwExpression => ContainsNestedFunction(throwExpression.Expression),
            NameofExpression nameofExpression => ContainsNestedFunction(nameofExpression.Target),
            CheckedExpression checkedExpression => ContainsNestedFunction(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => ContainsNestedFunction(uncheckedExpression.Expression),
            ParenthesizedExpression parenthesizedExpression => ContainsNestedFunction(parenthesizedExpression.Inner),
            _ => false
        };
    }

    private static bool ContainsNestedFunction(Pattern pattern)
    {
        return pattern switch
        {
            LiteralPattern literalPattern => ContainsNestedFunction(literalPattern.Literal),
            UnionCasePattern unionCasePattern => unionCasePattern.Properties != null
                && unionCasePattern.Properties.Any(property => property.Pattern != null && ContainsNestedFunction(property.Pattern)),
            RelationalPattern relationalPattern => ContainsNestedFunction(relationalPattern.Value),
            AndPattern andPattern => ContainsNestedFunction(andPattern.Left) || ContainsNestedFunction(andPattern.Right),
            OrPattern orPattern => ContainsNestedFunction(orPattern.Left) || ContainsNestedFunction(orPattern.Right),
            NotPattern notPattern => ContainsNestedFunction(notPattern.Pattern),
            PositionalPattern positionalPattern => positionalPattern.Patterns.Any(ContainsNestedFunction),
            ObjectPattern objectPattern => objectPattern.Properties.Any(property => property.Pattern != null && ContainsNestedFunction(property.Pattern)),
            ListPattern listPattern => listPattern.Elements.Any(ContainsNestedFunction),
            _ => false
        };
    }

    private static bool ContainsAwait(Statement statement)
    {
        return statement switch
        {
            BlockStatement block => block.Statements.Any(ContainsAwait),
            ExpressionStatement expressionStatement => ContainsAwait(expressionStatement.Expression),
            VariableDeclarationStatement variableDeclaration => variableDeclaration.Initializer != null && ContainsAwait(variableDeclaration.Initializer),
            TupleDeconstructionStatement tupleDeconstruction => ContainsAwait(tupleDeconstruction.Initializer),
            ReturnStatement returnStatement => returnStatement.Value != null && ContainsAwait(returnStatement.Value),
            IfStatement ifStatement => ContainsAwait(ifStatement.ThenStatement)
                || (ifStatement.ElseStatement != null && ContainsAwait(ifStatement.ElseStatement)),
            WhileStatement whileStatement => ContainsAwait(whileStatement.Condition) || ContainsAwait(whileStatement.Body),
            ForStatement forStatement => (forStatement.Initializer != null && ContainsAwait(forStatement.Initializer))
                || (forStatement.Condition != null && ContainsAwait(forStatement.Condition))
                || (forStatement.Iterator != null && ContainsAwait(forStatement.Iterator))
                || ContainsAwait(forStatement.Body),
            ForeachStatement foreachStatement => ContainsAwait(foreachStatement.Collection) || ContainsAwait(foreachStatement.Body),
            AwaitForEachStatement awaitForEachStatement => true,
            TryStatement tryStatement => ContainsAwait(tryStatement.TryBlock)
                || tryStatement.CatchClauses.Any(catchClause => ContainsAwait(catchClause.Block))
                || (tryStatement.FinallyBlock != null && ContainsAwait(tryStatement.FinallyBlock)),
            SwitchStatement switchStatement => ContainsAwait(switchStatement.Value)
                || switchStatement.Cases.Any(@case => @case.Statements.Any(ContainsAwait)),
            LockStatement lockStatement => ContainsAwait(lockStatement.LockObject) || ContainsAwait(lockStatement.Body),
            ThrowStatement throwStatement => ContainsAwait(throwStatement.Expression),
            AssertStatement assertStatement => ContainsAwait(assertStatement.Condition),
            AssertThrowsStatement assertThrowsStatement => ContainsAwait(assertThrowsStatement.Body),
            LocalFunctionStatement localFunctionStatement => (localFunctionStatement.Function.Body != null && ContainsAwait(localFunctionStatement.Function.Body))
                || (localFunctionStatement.Function.ExpressionBody != null && ContainsAwait(localFunctionStatement.Function.ExpressionBody)),
            _ => false
        };
    }

    private static bool ContainsAwait(Expression expression)
    {
        return expression switch
        {
            AwaitExpression => true,
            RangeExpression rangeExpression => (rangeExpression.Start != null && ContainsAwait(rangeExpression.Start))
                || (rangeExpression.End != null && ContainsAwait(rangeExpression.End)),
            BinaryExpression binaryExpression => ContainsAwait(binaryExpression.Left) || ContainsAwait(binaryExpression.Right),
            UnaryExpression unaryExpression => ContainsAwait(unaryExpression.Operand),
            MemberAccessExpression memberAccessExpression => ContainsAwait(memberAccessExpression.Object),
            IndexAccessExpression indexAccessExpression => ContainsAwait(indexAccessExpression.Object) || ContainsAwait(indexAccessExpression.Index),
            CallExpression callExpression => ContainsAwait(callExpression.Callee)
                || callExpression.Arguments.Any(argument => ContainsAwait(argument.Value)),
            AssignmentExpression assignmentExpression => ContainsAwait(assignmentExpression.Target) || ContainsAwait(assignmentExpression.Value),
            TernaryExpression ternaryExpression => ContainsAwait(ternaryExpression.Condition)
                || ContainsAwait(ternaryExpression.ThenExpression)
                || ContainsAwait(ternaryExpression.ElseExpression),
            ArrayLiteralExpression arrayLiteralExpression => arrayLiteralExpression.Elements.Any(ContainsAwait),
            TupleExpression tupleExpression => tupleExpression.Elements.Any(element => ContainsAwait(element.Value)),
            ObjectInitializerExpression objectInitializerExpression => objectInitializerExpression.Properties.Any(property =>
                (property.IndexExpression != null && ContainsAwait(property.IndexExpression))
                || ContainsAwait(property.Value)),
            NewExpression newExpression => newExpression.ConstructorArguments.Any(argument => ContainsAwait(argument.Value))
                || (newExpression.Initializer != null && ContainsAwait(newExpression.Initializer)),
            CastExpression castExpression => ContainsAwait(castExpression.Expression),
            IsExpression isExpression => ContainsAwait(isExpression.Expression),
            MatchExpression matchExpression => ContainsAwait(matchExpression.Value)
                || matchExpression.Cases.Any(matchCase =>
                    (matchCase.Guard != null && ContainsAwait(matchCase.Guard))
                    || ContainsAwait(matchCase.Expression)),
            SpreadExpression spreadExpression => ContainsAwait(spreadExpression.Expression),
            WithExpression withExpression => ContainsAwait(withExpression.Target)
                || withExpression.Properties.Any(property =>
                    (property.IndexExpression != null && ContainsAwait(property.IndexExpression))
                    || ContainsAwait(property.Value)),
            ThrowExpression throwExpression => ContainsAwait(throwExpression.Expression),
            CheckedExpression checkedExpression => ContainsAwait(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => ContainsAwait(uncheckedExpression.Expression),
            ParenthesizedExpression parenthesizedExpression => ContainsAwait(parenthesizedExpression.Inner),
            LambdaExpression lambdaExpression => (lambdaExpression.BlockBody != null && ContainsAwait(lambdaExpression.BlockBody))
                || (lambdaExpression.ExpressionBody != null && ContainsAwait(lambdaExpression.ExpressionBody)),
            _ => false
        };
    }

    private void RegisterType(string key, TypeBuilder typeBuilder)
    {
        _types[key] = typeBuilder;
        _typeKeys[typeBuilder] = key;
    }

    private void RegisterStringEnumContainer(string key, TypeBuilder typeBuilder)
    {
        _stringEnumContainers[key] = typeBuilder;
        _typeKeys[typeBuilder] = key;
    }

    private void ApplyCustomAttributes(Action<CustomAttributeBuilder> applyAttribute, IReadOnlyList<AttributeNode>? attributes)
    {
        if (attributes == null)
        {
            return;
        }

        foreach (var attribute in attributes)
        {
            applyAttribute(BuildCustomAttribute(attribute));
        }
    }

    private void ApplyParameterAttributes(ParameterBuilder parameterBuilder, Parameter parameter)
    {
        if (parameter.Attributes == null || parameter.Attributes.Count == 0)
        {
            return;
        }

        ApplyCustomAttributes(parameterBuilder.SetCustomAttribute, parameter.Attributes);
    }

    private CustomAttributeBuilder BuildCustomAttribute(AttributeNode attribute)
    {
        var attributeType = ResolveAttributeType(attribute.Name);
        var positionalValues = new List<object?>();
        var positionalTypes = new List<Type>();
        var namedProperties = new List<PropertyInfo>();
        var propertyValues = new List<object?>();
        var namedFields = new List<FieldInfo>();
        var fieldValues = new List<object?>();

        foreach (var argument in attribute.Arguments)
        {
            var argumentName = argument.Name;
            var valueExpression = argument.Value;
            if (argumentName == null &&
                argument.Value is AssignmentExpression assignmentExpression &&
                assignmentExpression.Target is IdentifierExpression identifierExpression)
            {
                argumentName = identifierExpression.Name;
                valueExpression = assignmentExpression.Value;
            }

            var (value, valueType) = EvaluateAttributeArgument(valueExpression);
            if (argumentName == null)
            {
                positionalValues.Add(value);
                positionalTypes.Add(valueType);
                continue;
            }

            var property = attributeType.GetProperty(argumentName, BindingFlags.Public | BindingFlags.Instance);
            if (property != null)
            {
                namedProperties.Add(property);
                propertyValues.Add(value);
                continue;
            }

            var field = attributeType.GetField(argumentName, BindingFlags.Public | BindingFlags.Instance);
            if (field != null)
            {
                namedFields.Add(field);
                fieldValues.Add(value);
                continue;
            }

            throw new InvalidOperationException($"Named attribute argument '{argumentName}' was not found on {attributeType.FullName}");
        }

        var constructor = ResolveAttributeConstructor(attributeType, positionalTypes.ToArray(), positionalValues.ToArray());
        return new CustomAttributeBuilder(
            constructor,
            positionalValues.ToArray(),
            namedProperties.ToArray(),
            propertyValues.ToArray(),
            namedFields.ToArray(),
            fieldValues.ToArray());
    }

    private Type ResolveAttributeType(string attributeName)
    {
        foreach (var candidate in GetAttributeNameCandidates(attributeName))
        {
            var resolvedType = ResolveExternalType(candidate);
            if (resolvedType != null && typeof(Attribute).IsAssignableFrom(resolvedType))
            {
                return resolvedType;
            }
        }

        throw new InvalidOperationException($"Attribute type '{attributeName}' could not be resolved");
    }

    private static IEnumerable<string> GetAttributeNameCandidates(string attributeName)
    {
        yield return attributeName;
        if (!attributeName.EndsWith("Attribute", StringComparison.Ordinal))
        {
            yield return attributeName + "Attribute";
        }
    }

    private static ConstructorInfo ResolveAttributeConstructor(Type attributeType, Type[] argumentTypes, object?[] argumentValues)
    {
        foreach (var constructor in attributeType.GetConstructors(BindingFlags.Public | BindingFlags.Instance))
        {
            var parameters = constructor.GetParameters();
            if (parameters.Length != argumentTypes.Length)
            {
                continue;
            }

            var isMatch = true;
            for (int i = 0; i < parameters.Length; i++)
            {
                if (!IsAttributeArgumentCompatible(parameters[i].ParameterType, argumentTypes[i], argumentValues[i]))
                {
                    isMatch = false;
                    break;
                }
            }

            if (isMatch)
            {
                return constructor;
            }
        }

        throw new InvalidOperationException($"No matching constructor found for attribute {attributeType.FullName}");
    }

    private static bool IsAttributeArgumentCompatible(Type parameterType, Type argumentType, object? argumentValue)
    {
        if (argumentValue == null)
        {
            return !parameterType.IsValueType || Nullable.GetUnderlyingType(parameterType) != null;
        }

        if (parameterType == argumentType || parameterType.IsAssignableFrom(argumentType))
        {
            return true;
        }

        if (parameterType.IsEnum && Enum.GetUnderlyingType(parameterType) == argumentType)
        {
            return true;
        }

        if (parameterType.IsArray && argumentType.IsArray)
        {
            var parameterElementType = parameterType.GetElementType()!;
            var argumentElementType = argumentType.GetElementType()!;
            return parameterElementType == argumentElementType
                || parameterElementType.IsAssignableFrom(argumentElementType)
                || (parameterElementType.IsEnum && Enum.GetUnderlyingType(parameterElementType) == argumentElementType);
        }

        return false;
    }

    private (object? Value, Type Type) EvaluateAttributeArgument(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression intLiteral => (ParseIntLiteralValue(intLiteral.Value), typeof(int)),
            FloatLiteralExpression floatLiteral => (ParseFloatLiteralValue(floatLiteral.Value), typeof(double)),
            StringLiteralExpression stringLiteral => (stringLiteral.Value.Trim('"'), typeof(string)),
            BoolLiteralExpression boolLiteral => (boolLiteral.Value, typeof(bool)),
            UnaryExpression unary => EvaluateAttributeUnaryArgument(unary),
            BinaryExpression binary => EvaluateAttributeBinaryArgument(binary),
            NullLiteralExpression => (null, typeof(object)),
            TypeOfExpression typeOfExpression => (ResolveType(typeOfExpression.Type, _currentGenericParameters), typeof(Type)),
            NameofExpression nameofExpression => (nameofExpression.Target switch
            {
                IdentifierExpression ident => ident.Name,
                MemberAccessExpression memberAccess => memberAccess.MemberName,
                _ => throw new InvalidOperationException($"nameof does not support target {nameofExpression.Target.GetType().Name}")
            }, typeof(string)),
            MemberAccessExpression memberAccess => EvaluateAttributeMemberAccess(memberAccess),
            ArrayLiteralExpression arrayLiteral => EvaluateAttributeArray(arrayLiteral),
            _ => throw new NotImplementedException($"Attribute argument expression {expression.GetType().Name} is not supported")
        };
    }

    private (object? Value, Type Type) EvaluateAttributeUnaryArgument(UnaryExpression unary)
    {
        var (operandValue, operandType) = EvaluateAttributeArgument(unary.Operand);
        return unary.Operator switch
        {
            UnaryOperator.Negate when operandType == typeof(int) => (-(int)operandValue!, typeof(int)),
            UnaryOperator.Negate when operandType == typeof(long) => (-(long)operandValue!, typeof(long)),
            UnaryOperator.Negate when operandType == typeof(float) => (-(float)operandValue!, typeof(float)),
            UnaryOperator.Negate when operandType == typeof(double) => (-(double)operandValue!, typeof(double)),
            UnaryOperator.Not when operandType == typeof(bool) => (!(bool)operandValue!, typeof(bool)),
            UnaryOperator.BitwiseNot when operandType == typeof(int) => (~(int)operandValue!, typeof(int)),
            UnaryOperator.BitwiseNot when operandType == typeof(long) => (~(long)operandValue!, typeof(long)),
            _ => throw new NotImplementedException($"Attribute unary expression {unary.Operator} on {operandType} is not supported")
        };
    }

    private (object? Value, Type Type) EvaluateAttributeBinaryArgument(BinaryExpression binary)
    {
        var (leftValue, leftType) = EvaluateAttributeArgument(binary.Left);
        var (rightValue, rightType) = EvaluateAttributeArgument(binary.Right);

        if (leftType.IsEnum && rightType == leftType)
        {
            var underlyingType = Enum.GetUnderlyingType(leftType);
            var leftIntegral = Convert.ToInt64(Convert.ChangeType(leftValue, underlyingType));
            var rightIntegral = Convert.ToInt64(Convert.ChangeType(rightValue, underlyingType));
            var result = binary.Operator switch
            {
                BinaryOperator.BitwiseOr => leftIntegral | rightIntegral,
                BinaryOperator.BitwiseAnd => leftIntegral & rightIntegral,
                BinaryOperator.BitwiseXor => leftIntegral ^ rightIntegral,
                _ => throw new NotImplementedException($"Attribute binary expression {binary.Operator} on enum {leftType} is not supported")
            };

            return (Enum.ToObject(leftType, result), leftType);
        }

        return (leftType, rightType) switch
        {
            (var type, _) when type == typeof(int) && rightType == typeof(int) => binary.Operator switch
            {
                BinaryOperator.BitwiseOr => ((int)leftValue! | (int)rightValue!, typeof(int)),
                BinaryOperator.BitwiseAnd => ((int)leftValue! & (int)rightValue!, typeof(int)),
                BinaryOperator.BitwiseXor => ((int)leftValue! ^ (int)rightValue!, typeof(int)),
                _ => throw new NotImplementedException($"Attribute binary expression {binary.Operator} on int is not supported")
            },
            (var type, _) when type == typeof(long) && rightType == typeof(long) => binary.Operator switch
            {
                BinaryOperator.BitwiseOr => ((long)leftValue! | (long)rightValue!, typeof(long)),
                BinaryOperator.BitwiseAnd => ((long)leftValue! & (long)rightValue!, typeof(long)),
                BinaryOperator.BitwiseXor => ((long)leftValue! ^ (long)rightValue!, typeof(long)),
                _ => throw new NotImplementedException($"Attribute binary expression {binary.Operator} on long is not supported")
            },
            _ => throw new NotImplementedException($"Attribute binary expression {binary.Operator} on {leftType} and {rightType} is not supported")
        };
    }

    private (object? Value, Type Type) EvaluateAttributeMemberAccess(MemberAccessExpression memberAccess)
    {
        if (!TryResolveStaticContainer(memberAccess.Object, out var staticType))
        {
            throw new InvalidOperationException($"Attribute member access {memberAccess} does not resolve to a static type");
        }

        if (staticType.IsEnum)
        {
            return (Enum.Parse(staticType, memberAccess.MemberName), staticType);
        }

        if (staticType is TypeBuilder staticTypeBuilder)
        {
            var fieldKey = GetFieldKey(staticTypeBuilder, memberAccess.MemberName);
            if (_fieldConstants.TryGetValue(fieldKey, out var constantValue)
                && _fields.TryGetValue(fieldKey, out var fieldBuilder))
            {
                return (constantValue, fieldBuilder.FieldType);
            }
        }

        var field = staticType.GetField(memberAccess.MemberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (field != null)
        {
            var value = field.IsLiteral ? field.GetRawConstantValue() : field.GetValue(null);
            return (value, field.FieldType);
        }

        var property = staticType.GetProperty(memberAccess.MemberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (property?.GetMethod != null)
        {
            return (property.GetValue(null), property.PropertyType);
        }

        throw new InvalidOperationException($"Attribute member {memberAccess.MemberName} was not found on {GetTypeKey(staticType)}");
    }

    private (object? Value, Type Type) EvaluateAttributeArray(ArrayLiteralExpression arrayLiteral)
    {
        if (arrayLiteral.Elements.Count == 0)
        {
            var emptyArray = Array.CreateInstance(typeof(object), 0);
            return (emptyArray, emptyArray.GetType());
        }

        var evaluatedElements = arrayLiteral.Elements
            .Select(EvaluateAttributeArgument)
            .ToArray();
        var elementType = evaluatedElements[0].Type;
        var array = Array.CreateInstance(elementType, evaluatedElements.Length);
        for (int i = 0; i < evaluatedElements.Length; i++)
        {
            array.SetValue(evaluatedElements[i].Value, i);
        }

        return (array, array.GetType());
    }

    private GenericTypeParameterBuilder[]? DeclareTypeGenericParameters(TypeBuilder typeBuilder, List<TypeParameter>? typeParameters)
    {
        if (typeParameters == null || typeParameters.Count == 0)
        {
            return null;
        }

        var genericParameters = typeBuilder.DefineGenericParameters(typeParameters.Select(parameter => parameter.Name).ToArray());
        _typeGenericParameters[GetTypeKey(typeBuilder)] = genericParameters;
        return genericParameters;
    }

    private GenericTypeParameterBuilder[]? GetTypeGenericParameters(TypeBuilder typeBuilder)
    {
        return _typeGenericParameters.TryGetValue(GetTypeKey(typeBuilder), out var genericParameters)
            ? genericParameters
            : null;
    }

    private static GenericTypeParameterBuilder[]? CombineGenericParameters(params GenericTypeParameterBuilder[]?[] genericParameterSets)
    {
        var combined = genericParameterSets
            .Where(set => set != null && set.Length > 0)
            .SelectMany(set => set!)
            .ToArray();

        return combined.Length > 0 ? combined : null;
    }

    private static bool SignaturesMatch(MethodInfo candidate, Type returnType, Type[] parameterTypes)
    {
        if (candidate.ReturnType != returnType && !candidate.ReturnType.IsGenericParameter)
        {
            return false;
        }

        var candidateParameters = candidate.GetParameters();
        if (candidateParameters.Length != parameterTypes.Length)
        {
            return false;
        }

        for (int i = 0; i < candidateParameters.Length; i++)
        {
            var candidateParameterType = candidateParameters[i].ParameterType;
            if (candidateParameterType != parameterTypes[i] && !candidateParameterType.IsGenericParameter)
            {
                return false;
            }
        }

        return true;
    }

    private string GetTypeKey(Type type)
    {
        if (_typeKeys.TryGetValue(type, out var key))
        {
            return key;
        }

        return type.FullName?.Replace('+', '.') ?? type.Name;
    }

    private string GetMethodKey(Type type, string methodName)
    {
        return $"{GetTypeKey(type)}.{methodName}";
    }

    private string GetConstructorKey(Type type)
    {
        return $"{GetTypeKey(type)}..ctor";
    }

    private string GetFieldKey(Type type, string fieldName)
    {
        return $"{GetTypeKey(type)}.{fieldName}";
    }

    private string GetPrimaryConstructorFieldKey(Type type, string parameterName)
    {
        return $"{GetTypeKey(type)}.<>primary.{parameterName}";
    }

    private string GetIndexerKey(Type type)
    {
        return $"{GetTypeKey(type)}.Item";
    }

    private void RegisterDeclaredMethodOverload(string key, FunctionDeclaration declaration, MethodBuilder builder)
    {
        _methodBuildersByDeclaration[declaration] = builder;

        if (!_declaredMethodOverloads.TryGetValue(key, out var overloads))
        {
            overloads = new List<DeclaredMethodOverload>();
            _declaredMethodOverloads[key] = overloads;
        }

        overloads.Add(new DeclaredMethodOverload(declaration, builder));
    }

    private void RegisterDeclaredConstructorOverload(string key, ConstructorDeclaration declaration, ConstructorBuilder builder)
    {
        _constructorBuildersByDeclaration[declaration] = builder;

        if (!_declaredConstructorOverloads.TryGetValue(key, out var overloads))
        {
            overloads = new List<DeclaredConstructorOverload>();
            _declaredConstructorOverloads[key] = overloads;
        }

        overloads.Add(new DeclaredConstructorOverload(declaration, builder));
    }

    private bool TryGetUserTypeDefinition(Type type, out TypeBuilder typeBuilder)
    {
        if (type is TypeBuilder directTypeBuilder && _typeKeys.ContainsKey(directTypeBuilder))
        {
            typeBuilder = directTypeBuilder;
            return true;
        }

        try
        {
            if (type.IsGenericType)
            {
                var genericDefinition = type.GetGenericTypeDefinition();
                if (genericDefinition is TypeBuilder genericTypeBuilder && _typeKeys.ContainsKey(genericTypeBuilder))
                {
                    typeBuilder = genericTypeBuilder;
                    return true;
                }
            }
        }
        catch (NotSupportedException)
        {
        }

        var typeKey = type.FullName?.Replace('+', '.') ?? type.Name;
        foreach (var entry in _typeKeys)
        {
            if (entry.Value == typeKey && entry.Key is TypeBuilder candidateBuilder)
            {
                typeBuilder = candidateBuilder;
                return true;
            }
        }

        typeBuilder = null!;
        return false;
    }

    private ConstructorInfo? ResolveUserDefinedConstructor(Type type)
    {
        if (!TryGetUserTypeDefinition(type, out var typeBuilder))
        {
            return null;
        }

        if (!_constructors.TryGetValue(GetConstructorKey(typeBuilder), out var constructorBuilder))
        {
            return null;
        }

        return type == typeBuilder
            ? constructorBuilder
            : TypeBuilder.GetConstructor(type, constructorBuilder);
    }

    private MethodInfo? ResolveUserDefinedMethod(Type type, string methodName)
    {
        if (!TryGetUserTypeDefinition(type, out var typeBuilder))
        {
            return null;
        }

        if (!_methods.TryGetValue(GetMethodKey(typeBuilder, methodName), out var methodBuilder))
        {
            return null;
        }

        return type == typeBuilder
            ? methodBuilder
            : TypeBuilder.GetMethod(type, methodBuilder);
    }

    private static bool IsImplicitNumericConversion(Type sourceType, Type targetType)
    {
        if (sourceType == targetType)
        {
            return true;
        }

        var source = Nullable.GetUnderlyingType(sourceType) ?? sourceType;
        var target = Nullable.GetUnderlyingType(targetType) ?? targetType;
        return (Type.GetTypeCode(source), Type.GetTypeCode(target)) switch
        {
            (TypeCode.Byte, TypeCode.Int16 or TypeCode.UInt16 or TypeCode.Int32 or TypeCode.UInt32 or TypeCode.Int64 or TypeCode.UInt64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.SByte, TypeCode.Int16 or TypeCode.Int32 or TypeCode.Int64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.Int16, TypeCode.Int32 or TypeCode.Int64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.UInt16, TypeCode.Int32 or TypeCode.UInt32 or TypeCode.Int64 or TypeCode.UInt64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.Int32, TypeCode.Int64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.UInt32, TypeCode.Int64 or TypeCode.UInt64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.Int64, TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.UInt64, TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.Char, TypeCode.UInt16 or TypeCode.Int32 or TypeCode.UInt32 or TypeCode.Int64 or TypeCode.UInt64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal) => true,
            (TypeCode.Single, TypeCode.Double) => true,
            _ => false
        };
    }

    private static bool AreTypeIdentitiesEquivalent(Type left, Type right)
    {
        if (left == right)
        {
            return true;
        }

        left = GetByRefElementType(left);
        right = GetByRefElementType(right);

        if (left.IsArray && right.IsArray)
        {
            return left.GetArrayRank() == right.GetArrayRank()
                && AreTypeIdentitiesEquivalent(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsGenericType && right.IsGenericType)
        {
            try
            {
                if (left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition())
                {
                    return false;
                }
            }
            catch (NotSupportedException)
            {
                return string.Equals(left.ToString(), right.ToString(), StringComparison.Ordinal);
            }

            var leftArguments = left.GetGenericArguments();
            var rightArguments = right.GetGenericArguments();
            if (leftArguments.Length != rightArguments.Length)
            {
                return false;
            }

            for (int i = 0; i < leftArguments.Length; i++)
            {
                if (!AreTypeIdentitiesEquivalent(leftArguments[i], rightArguments[i]))
                {
                    return false;
                }
            }

            return true;
        }

        return string.Equals(left.FullName ?? left.ToString(), right.FullName ?? right.ToString(), StringComparison.Ordinal);
    }

    private static bool IsEnumType(Type type)
    {
        try
        {
            return type.IsEnum;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static Type? TryGetEnumUnderlyingType(Type type)
    {
        if (!IsEnumType(type))
        {
            return null;
        }

        try
        {
            return Enum.GetUnderlyingType(type);
        }
        catch (ArgumentException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    private static bool IsParameterTypeCompatible(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
        {
            return true;
        }

        if (parameterType.IsGenericParameter)
        {
            return true;
        }

        if (parameterType.ContainsGenericParameters)
        {
            if (parameterType.IsArray && argumentType.IsArray)
            {
                return IsParameterTypeCompatible(parameterType.GetElementType()!, argumentType.GetElementType()!);
            }

            if (parameterType.IsGenericType)
            {
                return FindConstructedGenericMatch(parameterType, argumentType) != null;
            }
        }

        if (AreTypeIdentitiesEquivalent(parameterType, argumentType))
        {
            return true;
        }

        try
        {
            if (parameterType.IsAssignableFrom(argumentType))
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
        }

        var parameterEnumUnderlyingType = TryGetEnumUnderlyingType(parameterType);
        var argumentEnumUnderlyingType = TryGetEnumUnderlyingType(argumentType);
        return IsImplicitNumericConversion(argumentType, parameterType)
            || parameterEnumUnderlyingType == argumentType
            || argumentEnumUnderlyingType == parameterType;
    }

    private static int GetParameterMatchScore(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
        {
            return 8;
        }

        if (parameterType.IsGenericParameter)
        {
            return 4;
        }

        if (AreTypeIdentitiesEquivalent(parameterType, argumentType))
        {
            return 8;
        }

        if (parameterType.ContainsGenericParameters)
        {
            return FindConstructedGenericMatch(parameterType, argumentType) != null ? 4 : 0;
        }

        if (IsImplicitNumericConversion(argumentType, parameterType))
        {
            return 6;
        }

        try
        {
            if (parameterType.IsAssignableFrom(argumentType)
                || TryGetEnumUnderlyingType(parameterType) == argumentType
                || TryGetEnumUnderlyingType(argumentType) == parameterType)
            {
                return 4;
            }
        }
        catch (NotSupportedException)
        {
        }

        if ((parameterType.IsEnum && Enum.GetUnderlyingType(parameterType) == argumentType)
            || (argumentType.IsEnum && Enum.GetUnderlyingType(argumentType) == parameterType))
        {
            return 4;
        }

        return 0;
    }

    private static bool TryGetParamsElementType(Type parameterType, out Type elementType)
    {
        if (parameterType.IsArray)
        {
            elementType = parameterType.GetElementType()!;
            return true;
        }

        if (parameterType.IsGenericType && parameterType.GetGenericArguments().Length == 1)
        {
            elementType = parameterType.GetGenericArguments()[0];
            return true;
        }

        elementType = typeof(object);
        return false;
    }

    private bool ShouldPassParamsArgumentDirectly(Argument argument, Type parameterType)
    {
        if (argument.Value is DefaultExpression)
        {
            return true;
        }

        var argumentType = GetExpressionType(argument.Value);
        return IsParameterTypeCompatible(parameterType, argumentType);
    }

    private static Type? FindConstructedGenericMatch(Type genericParameterType, Type argumentType)
    {
        if (!genericParameterType.IsGenericType)
        {
            return null;
        }

        var genericDefinition = genericParameterType.GetGenericTypeDefinition();
        if (argumentType.IsGenericType && argumentType.GetGenericTypeDefinition() == genericDefinition)
        {
            return argumentType;
        }

        foreach (var interfaceType in argumentType.GetInterfaces())
        {
            if (interfaceType.IsGenericType && interfaceType.GetGenericTypeDefinition() == genericDefinition)
            {
                return interfaceType;
            }
        }

        var baseType = argumentType.BaseType;
        while (baseType != null)
        {
            if (baseType.IsGenericType && baseType.GetGenericTypeDefinition() == genericDefinition)
            {
                return baseType;
            }

            baseType = baseType.BaseType;
        }

        return null;
    }

    private bool TryCollectGenericBindings(Type parameterType, Type argumentType, Dictionary<string, Type> bindings)
    {
        parameterType = GetByRefElementType(parameterType);
        argumentType = GetByRefElementType(argumentType);

        if (parameterType.IsGenericParameter)
        {
            if (!bindings.TryGetValue(parameterType.Name, out var existing))
            {
                bindings[parameterType.Name] = argumentType;
                return true;
            }

            if (existing == argumentType)
            {
                return true;
            }

            if (AreTypeIdentitiesEquivalent(existing, argumentType))
            {
                return true;
            }

            try
            {
                if (existing.IsAssignableFrom(argumentType))
                {
                    bindings[parameterType.Name] = argumentType;
                    return true;
                }
            }
            catch (NotSupportedException)
            {
            }

            try
            {
                if (argumentType.IsAssignableFrom(existing))
                {
                    return true;
                }
            }
            catch (NotSupportedException)
            {
            }

            return false;
        }

        if (parameterType.IsArray)
        {
            return argumentType.IsArray
                && TryCollectGenericBindings(parameterType.GetElementType()!, argumentType.GetElementType()!, bindings);
        }

        if (parameterType.IsGenericType)
        {
            var constructedArgumentType = FindConstructedGenericMatch(parameterType, argumentType);
            if (constructedArgumentType == null)
            {
                return false;
            }

            var parameterTypeArguments = parameterType.GetGenericArguments();
            var argumentTypeArguments = constructedArgumentType.GetGenericArguments();
            for (int i = 0; i < parameterTypeArguments.Length; i++)
            {
                if (!TryCollectGenericBindings(parameterTypeArguments[i], argumentTypeArguments[i], bindings))
                {
                    return false;
                }
            }

            return true;
        }

        return IsParameterTypeCompatible(parameterType, argumentType);
    }

    private Type[]? TryInferDeclaredMethodTypeArguments(FunctionDeclaration declaration, MethodBuilder builder, CallExpression call, Expression? implicitReceiver)
    {
        return TryInferDeclaredMethodTypeArguments(declaration, builder.GetParameters(), call, implicitReceiver);
    }

    private Type[]? TryInferDeclaredMethodTypeArguments(FunctionDeclaration declaration, ParameterInfo[] runtimeParameters, CallExpression call, Expression? implicitReceiver)
    {
        if (declaration.TypeParameters is not { Count: > 0 })
        {
            return null;
        }

        if (call.Arguments.Any(argument => argument.Name != null))
        {
            return null;
        }

        var bindings = new Dictionary<string, Type>();
        var parameterIndex = 0;
        if (implicitReceiver != null)
        {
            if (runtimeParameters.Length == 0 || !TryCollectGenericBindings(runtimeParameters[0].ParameterType, GetExpressionType(implicitReceiver), bindings))
            {
                return null;
            }

            parameterIndex = 1;
        }

        for (int i = 0; i < call.Arguments.Count && parameterIndex + i < runtimeParameters.Length; i++)
        {
            if (!TryCollectGenericBindings(runtimeParameters[parameterIndex + i].ParameterType, GetExpressionType(call.Arguments[i].Value), bindings))
            {
                return null;
            }
        }

        var inferredTypes = new Type[declaration.TypeParameters.Count];
        for (int i = 0; i < declaration.TypeParameters.Count; i++)
        {
            if (!bindings.TryGetValue(declaration.TypeParameters[i].Name, out var inferredType))
            {
                return null;
            }

            inferredTypes[i] = inferredType;
        }

        return inferredTypes;
    }

    private (MethodInfo? Method, Type[]? TypeArguments) CreateDeclaredMethodCandidate(DeclaredMethodOverload overload, CallExpression call, Expression? implicitReceiver)
    {
        if (overload.Declaration.TypeParameters is not { Count: > 0 })
        {
            return call.TypeArguments is { Count: > 0 }
                ? (null, null)
                : (overload.Builder, null);
        }

        Type[]? typeArguments = null;
        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            if (call.TypeArguments.Count != overload.Declaration.TypeParameters.Count)
            {
                return (null, null);
            }

            typeArguments = call.TypeArguments
                .Select(typeArgument => ResolveType(typeArgument, _currentGenericParameters))
                .ToArray();
        }
        else
        {
            typeArguments = TryInferDeclaredMethodTypeArguments(overload.Declaration, overload.Builder, call, implicitReceiver);
        }

        if (typeArguments == null)
        {
            return (null, null);
        }

        return (overload.Builder.MakeGenericMethod(typeArguments), typeArguments);
    }

    private bool TryBindDeclaredParameters(
        IReadOnlyList<Parameter> declaredParameters,
        ParameterInfo[] runtimeParameters,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed,
        Expression? implicitReceiver = null)
    {
        return TryBindDeclaredParameters(
            declaredParameters,
            runtimeParameters.Select(parameter => parameter.ParameterType).ToArray(),
            suppliedArguments,
            out boundArguments,
            out score,
            out usesParams,
            out defaultsUsed,
            implicitReceiver);
    }

    private bool TryBindDeclaredParameters(
        IReadOnlyList<Parameter> declaredParameters,
        IReadOnlyList<Type> runtimeParameterTypes,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed,
        Expression? implicitReceiver = null)
    {
        var bound = new BoundCallArgument[runtimeParameterTypes.Count];
        score = 0;
        defaultsUsed = 0;
        usesParams = declaredParameters.Count > 0 && declaredParameters[^1].Modifier == Ast.ParameterModifier.Params;

        var startIndex = 0;
        if (implicitReceiver != null)
        {
            bound[0] = new ExpressionBoundCallArgument(implicitReceiver, runtimeParameterTypes[0]);
            startIndex = 1;
        }

        var paramsParameterIndex = usesParams ? runtimeParameterTypes.Count - 1 : -1;
        var nextPositionalParameter = startIndex;
        var paramsArguments = new List<Argument>();

        foreach (var argument in suppliedArguments)
        {
            if (argument.Name != null)
            {
                var parameterIndex = Enumerable.Range(startIndex, declaredParameters.Count - startIndex)
                    .FirstOrDefault(index => declaredParameters[index].Name == argument.Name, -1);
                if (parameterIndex < startIndex || parameterIndex >= declaredParameters.Count || bound[parameterIndex] != null)
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                bound[parameterIndex] = new SuppliedBoundCallArgument(argument, runtimeParameterTypes[parameterIndex]);
                continue;
            }

            while (nextPositionalParameter < runtimeParameterTypes.Count
                   && nextPositionalParameter != paramsParameterIndex
                   && bound[nextPositionalParameter] != null)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter < runtimeParameterTypes.Count
                && nextPositionalParameter != paramsParameterIndex)
            {
                bound[nextPositionalParameter] = new SuppliedBoundCallArgument(argument, runtimeParameterTypes[nextPositionalParameter]);
                nextPositionalParameter++;
                continue;
            }

            if (!usesParams)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            paramsArguments.Add(argument);
        }

        var regularParameterCount = usesParams ? paramsParameterIndex : runtimeParameterTypes.Count;
        for (int i = startIndex; i < regularParameterCount; i++)
        {
            if (bound[i] != null)
            {
                continue;
            }

            var defaultValue = declaredParameters[i].DefaultValue;
            if (defaultValue == null)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            bound[i] = new ExpressionBoundCallArgument(defaultValue, runtimeParameterTypes[i]);
            defaultsUsed++;
        }

        if (usesParams)
        {
            if (bound[paramsParameterIndex] != null && paramsArguments.Count > 0)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            if (bound[paramsParameterIndex] == null)
            {
                var paramsParameterType = runtimeParameterTypes[paramsParameterIndex];
                if (!TryGetParamsElementType(paramsParameterType, out var elementType))
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                if (paramsArguments.Count == 1 && ShouldPassParamsArgumentDirectly(paramsArguments[0], paramsParameterType))
                {
                    bound[paramsParameterIndex] = new SuppliedBoundCallArgument(paramsArguments[0], paramsParameterType);
                }
                else
                {
                    bound[paramsParameterIndex] = new ParamsCollectionBoundCallArgument(paramsParameterType, elementType, paramsArguments);
                }
            }
        }

        for (int i = 0; i < runtimeParameterTypes.Count; i++)
        {
            var parameterType = runtimeParameterTypes[i];
            var expectedType = GetByRefElementType(parameterType);

            switch (bound[i])
            {
                case SuppliedBoundCallArgument supplied:
                {
                    var expectsByRef = parameterType.IsByRef;
                    var suppliedByRef = supplied.Argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out;
                    if (expectsByRef != suppliedByRef)
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    if (supplied.Argument.Value is OutVariableDeclarationExpression outVariable)
                    {
                        if (outVariable.Type != null && !IsParameterTypeCompatible(expectedType, ResolveType(outVariable.Type, _currentGenericParameters)))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += 8;
                        break;
                    }

                    if (supplied.Argument.Value is DefaultExpression)
                    {
                        score += 8;
                        break;
                    }

                    var argumentType = GetExpressionType(supplied.Argument.Value);
                    if (!IsParameterTypeCompatible(expectedType, argumentType))
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    score += GetParameterMatchScore(expectedType, argumentType);
                    break;
                }

                case ExpressionBoundCallArgument expressionBound:
                {
                    if (expressionBound.Expression is DefaultExpression)
                    {
                        score += 8;
                        break;
                    }

                    var argumentType = GetExpressionType(expressionBound.Expression);
                    if (!IsParameterTypeCompatible(expectedType, argumentType))
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    score += GetParameterMatchScore(expectedType, argumentType);
                    break;
                }

                case ParamsCollectionBoundCallArgument paramsBound:
                    foreach (var paramsArgument in paramsBound.Arguments)
                    {
                        if (paramsArgument.Value is SpreadExpression)
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        var argumentType = GetExpressionType(paramsArgument.Value);
                        if (!IsParameterTypeCompatible(paramsBound.ElementType, argumentType))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += GetParameterMatchScore(paramsBound.ElementType, argumentType);
                    }
                    break;

                default:
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
            }
        }

        boundArguments = bound;
        return true;
    }

    private BoundDeclaredMethodCall? BindDeclaredMethodCall(
        string key,
        CallExpression call,
        Expression? implicitReceiver = null,
        Type? targetType = null,
        Func<DeclaredMethodOverload, bool>? predicate = null)
    {
        if (!_declaredMethodOverloads.TryGetValue(key, out var overloads))
        {
            return null;
        }

        BoundDeclaredMethodCall? best = null;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;
        var bestIsGeneric = true;

        foreach (var overload in overloads)
        {
            if (predicate != null && !predicate(overload))
            {
                continue;
            }

            var (candidateMethod, candidateTypeArguments) = CreateDeclaredMethodCandidate(overload, call, implicitReceiver);
            if (candidateMethod == null)
            {
                continue;
            }

            if (targetType != null
                && candidateMethod.DeclaringType is TypeBuilder
                && targetType != candidateMethod.DeclaringType)
            {
                candidateMethod = TypeBuilder.GetMethod(targetType, candidateMethod);
            }

            var parameterTypes = overload.Builder.IsStatic
                && targetType == null
                && implicitReceiver == null
                && overload.Declaration.TypeParameters is { Count: > 0 }
                && candidateTypeArguments != null
                ? ResolveDeclaredMethodParameterTypes(overload.Declaration, candidateTypeArguments)
                : candidateMethod.GetParameters().Select(parameter => parameter.ParameterType).ToArray();

            if (!TryBindDeclaredParameters(
                    overload.Declaration.Parameters,
                    parameterTypes,
                    call.Arguments,
                    out var boundArguments,
                    out var score,
                    out var usesParams,
                    out var defaultsUsed,
                    implicitReceiver))
            {
                continue;
            }

            var isGeneric = overload.Declaration.TypeParameters is { Count: > 0 };
            if (best == null
                || score > bestScore
                || (score == bestScore && bestIsGeneric && !isGeneric)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams && !usesParams)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                best = new BoundDeclaredMethodCall(
                    overload.Declaration,
                    candidateMethod,
                    boundArguments,
                    implicitReceiver != null,
                    candidateTypeArguments);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
                bestIsGeneric = isGeneric;
            }
        }

        return best;
    }

    private BoundDeclaredConstructorCall? BindDeclaredConstructorCall(Type type, IReadOnlyList<Argument> arguments)
    {
        if (!TryGetUserTypeDefinition(type, out var typeBuilder)
            || !_declaredConstructorOverloads.TryGetValue(GetConstructorKey(typeBuilder), out var overloads))
        {
            return null;
        }

        BoundDeclaredConstructorCall? best = null;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;

        foreach (var overload in overloads)
        {
            var candidateConstructor = type == typeBuilder
                ? overload.Builder
                : TypeBuilder.GetConstructor(type, overload.Builder);
            if (!TryBindDeclaredParameters(
                    overload.Declaration.Parameters,
                    candidateConstructor.GetParameters(),
                    arguments,
                    out var boundArguments,
                    out var score,
                    out var usesParams,
                    out var defaultsUsed))
            {
                continue;
            }

            if (best == null
                || score > bestScore
                || (score == bestScore && bestUsesParams && !usesParams)
                || (score == bestScore && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                best = new BoundDeclaredConstructorCall(overload.Declaration, candidateConstructor, boundArguments);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
            }
        }

        return best;
    }

    private void EmitBoundCallArguments(IReadOnlyList<BoundCallArgument> arguments)
    {
        foreach (var argument in arguments)
        {
            switch (argument)
            {
                case SuppliedBoundCallArgument supplied:
                    if (supplied.ParameterType.IsByRef)
                    {
                        EmitArgumentAddress(supplied.Argument.Value, GetByRefElementType(supplied.ParameterType));
                    }
                    else
                    {
                        EmitExpressionWithExpectedType(supplied.Argument.Value, supplied.ParameterType);
                    }
                    break;

                case ExpressionBoundCallArgument expressionBound:
                    EmitExpressionWithExpectedType(expressionBound.Expression, expressionBound.ParameterType);
                    break;

                case RuntimeDefaultBoundCallArgument runtimeDefault:
                    if (runtimeDefault.Value == DBNull.Value || runtimeDefault.Value == Missing.Value)
                    {
                        EmitDefaultValue(runtimeDefault.ParameterType);
                    }
                    else
                    {
                        EmitConstantValue(runtimeDefault.Value, runtimeDefault.ParameterType);
                    }
                    break;

                case ParamsCollectionBoundCallArgument paramsBound:
                    EmitParamsCollectionArgument(paramsBound);
                    break;

                case CapturedGenericLocalBoundCallArgument capturedGenericLocal:
                    EmitGenericLocalFunctionCaptureArgument(capturedGenericLocal.Capture);
                    break;
            }
        }
    }

    private void EmitParamsCollectionArgument(ParamsCollectionBoundCallArgument paramsArgument)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var parameterType = paramsArgument.ParameterType;
        var arrayType = paramsArgument.ElementType.MakeArrayType();
        if (parameterType.IsArray)
        {
            _currentIL.Emit(OpCodes.Ldc_I4, paramsArgument.Arguments.Count);
            _currentIL.Emit(OpCodes.Newarr, paramsArgument.ElementType);
            for (int i = 0; i < paramsArgument.Arguments.Count; i++)
            {
                _currentIL.Emit(OpCodes.Dup);
                _currentIL.Emit(OpCodes.Ldc_I4, i);
                EmitExpressionWithExpectedType(paramsArgument.Arguments[i].Value, paramsArgument.ElementType);
                EmitArrayElementStore(paramsArgument.ElementType);
            }

            return;
        }

        if (parameterType.IsAssignableFrom(arrayType))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, paramsArgument.Arguments.Count);
            _currentIL.Emit(OpCodes.Newarr, paramsArgument.ElementType);
            for (int i = 0; i < paramsArgument.Arguments.Count; i++)
            {
                _currentIL.Emit(OpCodes.Dup);
                _currentIL.Emit(OpCodes.Ldc_I4, i);
                EmitExpressionWithExpectedType(paramsArgument.Arguments[i].Value, paramsArgument.ElementType);
                EmitArrayElementStore(paramsArgument.ElementType);
            }

            return;
        }

        if (parameterType.IsGenericType)
        {
            var genericDefinition = parameterType.GetGenericTypeDefinition();
            if ((genericDefinition == typeof(Span<>) || genericDefinition == typeof(ReadOnlySpan<>))
                && parameterType.GetGenericArguments()[0] == paramsArgument.ElementType)
            {
                _currentIL.Emit(OpCodes.Ldc_I4, paramsArgument.Arguments.Count);
                _currentIL.Emit(OpCodes.Newarr, paramsArgument.ElementType);
                for (int i = 0; i < paramsArgument.Arguments.Count; i++)
                {
                    _currentIL.Emit(OpCodes.Dup);
                    _currentIL.Emit(OpCodes.Ldc_I4, i);
                    EmitExpressionWithExpectedType(paramsArgument.Arguments[i].Value, paramsArgument.ElementType);
                    EmitArrayElementStore(paramsArgument.ElementType);
                }

                var spanCtor = parameterType.GetConstructor(new[] { arrayType })
                    ?? throw new InvalidOperationException($"Could not resolve {parameterType}(T[]) constructor");
                _currentIL.Emit(OpCodes.Newobj, spanCtor);
                return;
            }
        }

        var listType = typeof(List<>).MakeGenericType(paramsArgument.ElementType);
        if (!parameterType.IsAssignableFrom(listType) && parameterType != listType)
        {
            throw new InvalidOperationException($"Cannot expand params arguments for parameter type {parameterType}");
        }

        var ctor = listType.GetConstructor(Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
        var addMethod = listType.GetMethod("Add", new[] { paramsArgument.ElementType })
            ?? throw new InvalidOperationException($"Could not resolve Add({paramsArgument.ElementType}) on {listType}");

        _currentIL.Emit(OpCodes.Newobj, ctor);
        foreach (var argument in paramsArgument.Arguments)
        {
            _currentIL.Emit(OpCodes.Dup);
            EmitExpressionWithExpectedType(argument.Value, paramsArgument.ElementType);
            _currentIL.Emit(OpCodes.Callvirt, addMethod);
        }
    }

    private IEnumerable<MethodInfo> GetInterfaceMethodCandidates(Type interfaceType, string methodName)
    {
        if (TryGetUserTypeDefinition(interfaceType, out var interfaceBuilder))
        {
            if (_methods.TryGetValue(GetMethodKey(interfaceBuilder, methodName), out var methodBuilder))
            {
                yield return interfaceType == interfaceBuilder
                    ? methodBuilder
                    : TypeBuilder.GetMethod(interfaceType, methodBuilder);
            }

            yield break;
        }

        foreach (var method in interfaceType.GetMethods().Where(method => method.Name == methodName))
        {
            yield return method;
        }
    }

    private bool TryResolveStaticContainer(string typeName, out Type type)
    {
        type = typeName switch
        {
            "byte" => typeof(byte),
            "sbyte" => typeof(sbyte),
            "short" => typeof(short),
            "ushort" => typeof(ushort),
            "int" => typeof(int),
            "uint" => typeof(uint),
            "long" => typeof(long),
            "ulong" => typeof(ulong),
            "float" => typeof(float),
            "double" => typeof(double),
            "decimal" => typeof(decimal),
            "char" => typeof(char),
            "bool" => typeof(bool),
            "string" => typeof(string),
            "object" => typeof(object),
            _ => typeof(object)
        };

        if (type != typeof(object) || typeName == "object")
        {
            return true;
        }

        if (_stringEnumContainers.TryGetValue(typeName, out var stringEnumContainer))
        {
            type = stringEnumContainer;
            return true;
        }

        if (_types.TryGetValue(typeName, out var typeBuilder))
        {
            type = typeBuilder;
            return true;
        }

        if (_enumTypes.TryGetValue(typeName, out var enumType))
        {
            type = enumType;
            return true;
        }

        var externalType = ResolveExternalType(typeName);
        if (externalType != null)
        {
            type = externalType;
            return true;
        }

        type = typeof(object);
        return false;
    }

    private bool TryResolveStaticContainer(Expression expression, out Type type)
    {
        if (TryGetQualifiedName(expression, out var qualifiedName))
        {
            return TryResolveStaticContainer(qualifiedName, out type);
        }

        type = typeof(object);
        return false;
    }

    private bool TryGetQualifiedName(Expression expression, out string qualifiedName)
    {
        switch (expression)
        {
            case IdentifierExpression ident:
                qualifiedName = ident.Name;
                return true;
            case MemberAccessExpression memberAccess when !memberAccess.IsNullConditional &&
                                                        TryGetQualifiedName(memberAccess.Object, out var parentName):
                qualifiedName = $"{parentName}.{memberAccess.MemberName}";
                return true;
            default:
                qualifiedName = string.Empty;
                return false;
        }
    }

    private static bool IsValueTypeLike(Type type)
    {
        return type.IsValueType || (type is TypeBuilder typeBuilder && typeBuilder.BaseType == typeof(ValueType));
    }

    private static Type GetByRefElementType(Type type)
    {
        return type.IsByRef ? type.GetElementType() ?? typeof(object) : type;
    }

    private static Type GetNullConditionalResultType(Type memberType)
    {
        return memberType.IsValueType && Nullable.GetUnderlyingType(memberType) == null
            ? typeof(Nullable<>).MakeGenericType(memberType)
            : memberType;
    }

    private static bool TryGetEnumerableElementType(Type collectionType, out Type elementType)
    {
        if (collectionType.IsArray)
        {
            elementType = collectionType.GetElementType() ?? typeof(object);
            return true;
        }

        if (collectionType.IsGenericType && collectionType.GetGenericTypeDefinition() == typeof(IEnumerable<>))
        {
            elementType = collectionType.GetGenericArguments()[0];
            return true;
        }

        var enumerableInterface = collectionType
            .GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IEnumerable<>));

        if (enumerableInterface != null)
        {
            elementType = enumerableInterface.GetGenericArguments()[0];
            return true;
        }

        elementType = typeof(object);
        return false;
    }

    private Type GetSpreadElementType(SpreadExpression spreadExpression)
    {
        var collectionType = GetExpressionType(spreadExpression.Expression);
        return TryGetEnumerableElementType(collectionType, out var elementType) ? elementType : typeof(object);
    }

    private void EmitSystemIndex(Expression expression)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var indexCtor = typeof(Index).GetConstructor(new[] { typeof(int), typeof(bool) });
        if (indexCtor == null)
        {
            throw new InvalidOperationException("Could not resolve System.Index constructor");
        }

        if (expression is UnaryExpression { Operator: UnaryOperator.IndexFromEnd } fromEnd)
        {
            EmitExpressionWithExpectedType(fromEnd.Operand, typeof(int));
            _currentIL.Emit(OpCodes.Ldc_I4_1);
            _currentIL.Emit(OpCodes.Newobj, indexCtor);
            return;
        }

        if (GetExpressionType(expression) == typeof(Index))
        {
            EmitExpression(expression);
            return;
        }

        EmitExpressionWithExpectedType(expression, typeof(int));
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Newobj, indexCtor);
    }

    private void EmitRangeEndpoint(Expression? endpoint, bool omittedFromEnd)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (endpoint != null)
        {
            EmitSystemIndex(endpoint);
            return;
        }

        var indexCtor = typeof(Index).GetConstructor(new[] { typeof(int), typeof(bool) });
        if (indexCtor == null)
        {
            throw new InvalidOperationException("Could not resolve System.Index constructor");
        }

        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(omittedFromEnd ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Newobj, indexCtor);
    }

    private void EmitRangeExpression(RangeExpression range)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var rangeCtor = typeof(Range).GetConstructor(new[] { typeof(Index), typeof(Index) });
        if (rangeCtor == null)
        {
            throw new InvalidOperationException("Could not resolve System.Range constructor");
        }

        EmitRangeEndpoint(range.Start, omittedFromEnd: false);
        EmitRangeEndpoint(range.End, omittedFromEnd: true);
        _currentIL.Emit(OpCodes.Newobj, rangeCtor);
    }

    private void EmitIndexOffset(LocalBuilder indexLocal, LocalBuilder lengthLocal)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var getOffset = typeof(Index).GetMethod(nameof(Index.GetOffset), new[] { typeof(int) });
        if (getOffset == null)
        {
            throw new InvalidOperationException("Could not resolve System.Index.GetOffset");
        }

        _currentIL.Emit(OpCodes.Ldloca_S, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
        _currentIL.Emit(OpCodes.Call, getOffset);
    }

    private static ParameterAttributes GetParameterAttributes(Parameter parameter)
    {
        return parameter.Modifier switch
        {
            Ast.ParameterModifier.Out => ParameterAttributes.Out,
            _ => ParameterAttributes.None
        };
    }

    private Type ResolveParameterType(Parameter parameter, GenericTypeParameterBuilder[]? genericParameters = null)
    {
        var parameterType = ResolveType(parameter.Type, genericParameters);
        return parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out
            ? parameterType.MakeByRefType()
            : parameterType;
    }

    private Type ResolveParameterType(Parameter parameter, IReadOnlyDictionary<string, Type> genericTypeArguments)
    {
        var parameterType = ResolveType(parameter.Type, genericTypeArguments);
        return parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out
            ? parameterType.MakeByRefType()
            : parameterType;
    }

    private Type[] ResolveDeclaredMethodParameterTypes(FunctionDeclaration declaration, IReadOnlyList<Type> typeArguments)
    {
        if (declaration.TypeParameters is not { Count: > 0 } || declaration.TypeParameters.Count != typeArguments.Count)
        {
            return declaration.Parameters.Select(parameter => ResolveParameterType(parameter)).ToArray();
        }

        var substitutions = new Dictionary<string, Type>(StringComparer.Ordinal);
        for (int i = 0; i < declaration.TypeParameters.Count; i++)
        {
            substitutions[declaration.TypeParameters[i].Name] = typeArguments[i];
        }

        return declaration.Parameters
            .Select(parameter => ResolveParameterType(parameter, substitutions))
            .ToArray();
    }

    private void RegisterParameterContext(IReadOnlyList<Parameter> parameters, int startIndex, GenericTypeParameterBuilder[]? genericParameters = null)
    {
        if (_currentIL == null || _locals == null || _parameters == null || _parameterTypes == null || _byRefParameters == null)
            throw new InvalidOperationException("No parameter context available");

        for (int i = 0; i < parameters.Count; i++)
        {
            var parameter = parameters[i];
            var parameterType = ResolveType(parameter.Type, genericParameters);
            _parameters[parameter.Name] = startIndex + i;
            _parameterTypes[parameter.Name] = parameterType;

            if (parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out)
            {
                _byRefParameters.Add(parameter.Name);
                continue;
            }

            if (_liftLocalsIntoBoxes)
            {
                var local = DeclareNamedLocal(parameter.Name, parameterType);
                EmitLoadArgument(startIndex + i);
                EmitInitializeNamedLocal(local, parameterType, emitDefaultValue: false, initializer: null, valueAlreadyOnStack: true);
            }
        }
    }

    private void RegisterParameterContext(IReadOnlyList<Parameter> parameters, IReadOnlyList<Type> parameterTypes, int startIndex)
    {
        if (_currentIL == null || _locals == null || _parameters == null || _parameterTypes == null || _byRefParameters == null)
            throw new InvalidOperationException("No parameter context available");

        if (parameters.Count != parameterTypes.Count)
        {
            throw new InvalidOperationException("Resolved parameter type count did not match parameter declarations");
        }

        for (int i = 0; i < parameters.Count; i++)
        {
            var parameter = parameters[i];
            var resolvedParameterType = parameterTypes[i];
            var parameterType = GetByRefElementType(resolvedParameterType);
            _parameters[parameter.Name] = startIndex + i;
            _parameterTypes[parameter.Name] = parameterType;

            if (resolvedParameterType.IsByRef || parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out)
            {
                _byRefParameters.Add(parameter.Name);
                continue;
            }

            if (_liftLocalsIntoBoxes)
            {
                var local = DeclareNamedLocal(parameter.Name, parameterType);
                EmitLoadArgument(startIndex + i);
                EmitInitializeNamedLocal(local, parameterType, emitDefaultValue: false, initializer: null, valueAlreadyOnStack: true);
            }
        }
    }

    private static bool AreParameterTypesCompatible(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
        {
            return true;
        }

        if (parameterType.IsAssignableFrom(argumentType))
        {
            return true;
        }

        if (parameterType.IsEnum && Enum.GetUnderlyingType(parameterType) == argumentType)
        {
            return true;
        }

        if (argumentType.IsEnum && Enum.GetUnderlyingType(argumentType) == parameterType)
        {
            return true;
        }

        return false;
    }

    private bool AreMethodArgumentTypesCompatible(Type parameterType, Type argumentType, Dictionary<string, Type> genericBindings)
    {
        parameterType = GetByRefElementType(parameterType);
        argumentType = GetByRefElementType(argumentType);

        if (parameterType.IsGenericParameter || parameterType.ContainsGenericParameters)
        {
            return TryCollectGenericBindings(parameterType, argumentType, genericBindings);
        }

        return IsParameterTypeCompatible(parameterType, argumentType);
    }

    private static bool IsTaskLikeType(Type type)
    {
        if (type == typeof(System.Threading.Tasks.Task) || type == typeof(System.Threading.Tasks.ValueTask))
        {
            return true;
        }

        if (!type.IsGenericType)
        {
            return false;
        }

        var genericType = type.GetGenericTypeDefinition();
        return genericType == typeof(System.Threading.Tasks.Task<>)
            || genericType == typeof(System.Threading.Tasks.ValueTask<>);
    }

    private static bool TryUnwrapAsyncReturnType(Type returnType, out Type? resultType, out bool returnsValueTask)
    {
        returnsValueTask = false;

        if (returnType == typeof(System.Threading.Tasks.Task))
        {
            resultType = null;
            return true;
        }

        if (returnType == typeof(System.Threading.Tasks.ValueTask))
        {
            resultType = null;
            returnsValueTask = true;
            return true;
        }

        if (returnType.IsGenericType)
        {
            var genericType = returnType.GetGenericTypeDefinition();
            if (genericType == typeof(System.Threading.Tasks.Task<>))
            {
                resultType = returnType.GetGenericArguments()[0];
                return true;
            }

            if (genericType == typeof(System.Threading.Tasks.ValueTask<>))
            {
                resultType = returnType.GetGenericArguments()[0];
                returnsValueTask = true;
                return true;
            }
        }

        resultType = null;
        return false;
    }

    private static Type WrapAsyncReturnType(Type innerReturnType, bool isEntryPoint)
    {
        if (innerReturnType == typeof(void))
        {
            return isEntryPoint
                ? typeof(System.Threading.Tasks.Task)
                : typeof(System.Threading.Tasks.ValueTask);
        }

        return isEntryPoint
            ? typeof(System.Threading.Tasks.Task<>).MakeGenericType(innerReturnType)
            : typeof(System.Threading.Tasks.ValueTask<>).MakeGenericType(innerReturnType);
    }

    private static bool IsEntryPointFunction(string name)
    {
        return string.Equals(name, "main", StringComparison.OrdinalIgnoreCase);
    }

    private Type GetDeclaredFunctionReturnType(FunctionDeclaration function, GenericTypeParameterBuilder[]? genericParameters)
    {
        var explicitReturnType = function.ReturnType != null
            ? ResolveType(function.ReturnType, genericParameters)
            : typeof(void);

        if (!function.Modifiers.HasFlag(Modifiers.Async) || function.Modifiers.HasFlag(Modifiers.Generator) || IsTaskLikeType(explicitReturnType))
        {
            return explicitReturnType;
        }

        return WrapAsyncReturnType(explicitReturnType, IsEntryPointFunction(function.Name));
    }

    private static bool TryGetSequenceElementType(Type returnType, out Type elementType, out bool returnEnumerator)
    {
        returnEnumerator = false;

        if (returnType.IsArray)
        {
            elementType = returnType.GetElementType()!;
            return true;
        }

        if (returnType.IsGenericType)
        {
            var genericType = returnType.GetGenericTypeDefinition();
            if (genericType == typeof(IEnumerable<>) || genericType == typeof(ICollection<>) || genericType == typeof(IList<>))
            {
                elementType = returnType.GetGenericArguments()[0];
                return true;
            }

            if (genericType == typeof(IEnumerator<>))
            {
                elementType = returnType.GetGenericArguments()[0];
                returnEnumerator = true;
                return true;
            }

            if (genericType == typeof(IAsyncEnumerable<>))
            {
                elementType = returnType.GetGenericArguments()[0];
                return true;
            }

            if (genericType == typeof(IAsyncEnumerator<>))
            {
                elementType = returnType.GetGenericArguments()[0];
                returnEnumerator = true;
                return true;
            }
        }

        var enumerableInterface = returnType.GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IEnumerable<>));
        if (enumerableInterface != null)
        {
            elementType = enumerableInterface.GetGenericArguments()[0];
            return true;
        }

        var asyncEnumerableInterface = returnType.GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>));
        if (asyncEnumerableInterface != null)
        {
            elementType = asyncEnumerableInterface.GetGenericArguments()[0];
            return true;
        }

        var asyncEnumeratorInterface = returnType.GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IAsyncEnumerator<>));
        if (asyncEnumeratorInterface != null)
        {
            elementType = asyncEnumeratorInterface.GetGenericArguments()[0];
            returnEnumerator = true;
            return true;
        }

        elementType = typeof(object);
        return false;
    }

    private AsyncSequenceAdapterInfo EnsureAsyncSequenceAdapter(Type elementType)
    {
        if (_moduleBuilder == null)
        {
            throw new InvalidOperationException("No module builder available");
        }

        if (_asyncSequenceAdapters.TryGetValue(elementType, out var existing))
        {
            return existing;
        }

        var sourceType = typeof(IEnumerable<>).MakeGenericType(elementType);
        var enumeratorInterfaceType = typeof(IEnumerator<>).MakeGenericType(elementType);
        var asyncEnumerableType = typeof(IAsyncEnumerable<>).MakeGenericType(elementType);
        var asyncEnumeratorType = typeof(IAsyncEnumerator<>).MakeGenericType(elementType);

        var suffix = _asyncSequenceAdapterCounter++;
        var enumeratorType = _moduleBuilder.DefineType(
            $"<>AsyncEnumerator_{suffix}",
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object));
        enumeratorType.AddInterfaceImplementation(asyncEnumeratorType);
        _generatedHelperTypes.Add(enumeratorType);

        var innerField = enumeratorType.DefineField("_inner", enumeratorInterfaceType, FieldAttributes.Private | FieldAttributes.InitOnly);
        var enumeratorCtor = enumeratorType.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, new[] { sourceType });
        {
            var il = enumeratorCtor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, typeof(object).GetConstructor(Type.EmptyTypes)!);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldarg_1);
            il.Emit(OpCodes.Callvirt, sourceType.GetMethod("GetEnumerator")!);
            il.Emit(OpCodes.Stfld, innerField);
            il.Emit(OpCodes.Ret);
        }

        var currentProperty = enumeratorType.DefineProperty("Current", PropertyAttributes.None, elementType, Type.EmptyTypes);
        var currentGetter = enumeratorType.DefineMethod(
            "get_Current",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
            elementType,
            Type.EmptyTypes);
        {
            var il = currentGetter.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, innerField);
            il.Emit(OpCodes.Callvirt, enumeratorInterfaceType.GetProperty("Current")!.GetMethod!);
            il.Emit(OpCodes.Ret);
        }
        currentProperty.SetGetMethod(currentGetter);
        enumeratorType.DefineMethodOverride(currentGetter, asyncEnumeratorType.GetProperty("Current")!.GetMethod!);

        var moveNextAsync = enumeratorType.DefineMethod(
            "MoveNextAsync",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(ValueTask<bool>),
            Type.EmptyTypes);
        {
            var il = moveNextAsync.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, innerField);
            il.Emit(OpCodes.Callvirt, typeof(System.Collections.IEnumerator).GetMethod(nameof(System.Collections.IEnumerator.MoveNext))!);
            il.Emit(OpCodes.Newobj, typeof(ValueTask<bool>).GetConstructor(new[] { typeof(bool) })!);
            il.Emit(OpCodes.Ret);
        }
        enumeratorType.DefineMethodOverride(moveNextAsync, asyncEnumeratorType.GetMethod(nameof(IAsyncEnumerator<int>.MoveNextAsync))!);

        var disposeAsync = enumeratorType.DefineMethod(
            "DisposeAsync",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(ValueTask),
            Type.EmptyTypes);
        {
            var il = disposeAsync.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, innerField);
            il.Emit(OpCodes.Callvirt, typeof(IDisposable).GetMethod(nameof(IDisposable.Dispose))!);
            var valueTaskLocal = il.DeclareLocal(typeof(ValueTask));
            il.Emit(OpCodes.Ldloca_S, valueTaskLocal);
            il.Emit(OpCodes.Initobj, typeof(ValueTask));
            il.Emit(OpCodes.Ldloc, valueTaskLocal);
            il.Emit(OpCodes.Ret);
        }
        enumeratorType.DefineMethodOverride(disposeAsync, typeof(IAsyncDisposable).GetMethod(nameof(IAsyncDisposable.DisposeAsync))!);

        var enumerableType = _moduleBuilder.DefineType(
            $"<>AsyncEnumerable_{suffix}",
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object));
        enumerableType.AddInterfaceImplementation(asyncEnumerableType);
        _generatedHelperTypes.Add(enumerableType);

        var sourceField = enumerableType.DefineField("_source", sourceType, FieldAttributes.Private | FieldAttributes.InitOnly);
        var enumerableCtor = enumerableType.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, new[] { sourceType });
        {
            var il = enumerableCtor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, typeof(object).GetConstructor(Type.EmptyTypes)!);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldarg_1);
            il.Emit(OpCodes.Stfld, sourceField);
            il.Emit(OpCodes.Ret);
        }

        var getAsyncEnumerator = enumerableType.DefineMethod(
            nameof(IAsyncEnumerable<int>.GetAsyncEnumerator),
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            asyncEnumeratorType,
            new[] { typeof(System.Threading.CancellationToken) });
        {
            var il = getAsyncEnumerator.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, sourceField);
            il.Emit(OpCodes.Newobj, enumeratorCtor);
            il.Emit(OpCodes.Ret);
        }
        enumerableType.DefineMethodOverride(getAsyncEnumerator, asyncEnumerableType.GetMethod(nameof(IAsyncEnumerable<int>.GetAsyncEnumerator))!);

        var adapterInfo = new AsyncSequenceAdapterInfo(enumerableType, enumerableCtor, enumeratorType, enumeratorCtor);
        _asyncSequenceAdapters[elementType] = adapterInfo;
        return adapterInfo;
    }

    private bool IsAsyncEnumerableReturnType(Type returnType)
    {
        return returnType.IsGenericType && returnType.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>);
    }

    private bool IsAsyncEnumeratorReturnType(Type returnType)
    {
        return returnType.IsGenericType && returnType.GetGenericTypeDefinition() == typeof(IAsyncEnumerator<>);
    }

    private void EmitGeneratorReturnValue(Type returnType, LocalBuilder listLocal)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var elementType = listLocal.LocalType.GetGenericArguments()[0];
        if (IsAsyncEnumerableReturnType(returnType))
        {
            var adapter = EnsureAsyncSequenceAdapter(elementType);
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            _currentIL.Emit(OpCodes.Newobj, adapter.EnumerableConstructor);
            return;
        }

        if (IsAsyncEnumeratorReturnType(returnType))
        {
            var adapter = EnsureAsyncSequenceAdapter(elementType);
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            _currentIL.Emit(OpCodes.Newobj, adapter.EnumeratorConstructor);
            return;
        }

        _currentIL.Emit(OpCodes.Ldloc, listLocal);
        if (!TryGetSequenceElementType(returnType, out _, out var returnEnumerator))
        {
            throw new InvalidOperationException($"Generator return type {returnType} is not a sequence type");
        }

        if (returnEnumerator)
        {
            var getEnumerator = listLocal.LocalType.GetMethod("GetEnumerator", Type.EmptyTypes)
                ?? throw new InvalidOperationException($"Could not resolve GetEnumerator for {listLocal.LocalType}");
            _currentIL.Emit(OpCodes.Callvirt, getEnumerator);
        }
    }

    private static TypeAttributes GetTypeVisibilityAttributes(Modifiers modifiers)
    {
        return modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File)
            ? TypeAttributes.NotPublic
            : TypeAttributes.Public;
    }

    private static MethodAttributes GetVisibilityMethodAttributes(Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return MethodAttributes.FamORAssem;
        }

        if (modifiers.HasFlag(Modifiers.Private))
        {
            return MethodAttributes.Private;
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return MethodAttributes.Family;
        }

        if (modifiers.HasFlag(Modifiers.Internal))
        {
            return MethodAttributes.Assembly;
        }

        return MethodAttributes.Public;
    }

    private static FieldAttributes GetVisibilityFieldAttributes(Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return FieldAttributes.FamORAssem;
        }

        if (modifiers.HasFlag(Modifiers.Private))
        {
            return FieldAttributes.Private;
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return FieldAttributes.Family;
        }

        if (modifiers.HasFlag(Modifiers.Internal))
        {
            return FieldAttributes.Assembly;
        }

        return FieldAttributes.Public;
    }

    private static bool HasExplicitVisibility(Modifiers modifiers)
    {
        return modifiers.HasFlag(Modifiers.Public)
            || modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Protected)
            || modifiers.HasFlag(Modifiers.Internal);
    }

    private static FieldAttributes GetConventionFieldVisibilityAttributes(string name, Modifiers modifiers)
    {
        if (HasExplicitVisibility(modifiers))
        {
            return GetVisibilityFieldAttributes(modifiers);
        }

        return !string.IsNullOrEmpty(name) && char.IsUpper(name[0])
            ? FieldAttributes.Public
            : FieldAttributes.Private;
    }

    private static MethodAttributes GetConventionMethodVisibilityAttributes(string name, Modifiers modifiers)
    {
        if (HasExplicitVisibility(modifiers))
        {
            return GetVisibilityMethodAttributes(modifiers);
        }

        return !string.IsNullOrEmpty(name) && char.IsUpper(name[0])
            ? MethodAttributes.Public
            : MethodAttributes.Private;
    }

    private Type ResolveRequiredRuntimeType(string fullName)
    {
        return ResolveExternalType(fullName)
            ?? throw new InvalidOperationException($"Could not resolve required runtime type {fullName}");
    }

    private void ApplyRequiredMemberAttribute(Action<CustomAttributeBuilder> applyAttribute)
    {
        var requiredMemberAttribute = ResolveRequiredRuntimeType("System.Runtime.CompilerServices.RequiredMemberAttribute");
        var ctor = requiredMemberAttribute.GetConstructor(Type.EmptyTypes)
            ?? throw new InvalidOperationException("Could not resolve RequiredMemberAttribute constructor");
        applyAttribute(new CustomAttributeBuilder(ctor, Array.Empty<object>()));
    }

    private Type[] GetInitOnlySetterReturnRequiredCustomModifiers()
    {
        return new[] { ResolveRequiredRuntimeType("System.Runtime.CompilerServices.IsExternalInit") };
    }

    private void EmitExpressionWithExpectedType(Expression expression, Type expectedType)
    {
        var savedExpectedType = _expectedExpressionType;
        _expectedExpressionType = GetByRefElementType(expectedType);
        try
        {
            if (expression is LambdaExpression)
            {
                EmitExpression(expression);
                return;
            }

            if (expression is NullLiteralExpression && Nullable.GetUnderlyingType(_expectedExpressionType) != null)
            {
                EmitDefaultValue(_expectedExpressionType);
                return;
            }

            var actualType = GetExpressionType(expression);
            EmitExpression(expression);
            EmitValueCoercion(actualType, _expectedExpressionType, allowExplicitUserDefinedConversions: false);
        }
        finally
        {
            _expectedExpressionType = savedExpectedType;
        }
    }

    private void EmitBranchIfHasValue(Type valueType, LocalBuilder valueLocal, Label hasValueLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloc, valueLocal);
        if (valueType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Box, valueType);
        }

        _currentIL.Emit(OpCodes.Brtrue, hasValueLabel);
    }

    private void EmitLoadArgument(int parameterIndex)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (parameterIndex)
        {
            case 0:
                _currentIL.Emit(OpCodes.Ldarg_0);
                break;
            case 1:
                _currentIL.Emit(OpCodes.Ldarg_1);
                break;
            case 2:
                _currentIL.Emit(OpCodes.Ldarg_2);
                break;
            case 3:
                _currentIL.Emit(OpCodes.Ldarg_3);
                break;
            default:
                if (parameterIndex <= byte.MaxValue)
                {
                    _currentIL.Emit(OpCodes.Ldarg_S, (byte)parameterIndex);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldarg, parameterIndex);
                }
                break;
        }
    }

    private void EmitStoreArgument(int parameterIndex)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (parameterIndex <= byte.MaxValue)
        {
            _currentIL.Emit(OpCodes.Starg_S, (byte)parameterIndex);
        }
        else
        {
            _currentIL.Emit(OpCodes.Starg, parameterIndex);
        }
    }

    private void EmitLoadIndirect(Type type)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (type.IsEnum || type == typeof(int))
            _currentIL.Emit(OpCodes.Ldind_I4);
        else if (type == typeof(uint))
            _currentIL.Emit(OpCodes.Ldind_U4);
        else if (type == typeof(long))
            _currentIL.Emit(OpCodes.Ldind_I8);
        else if (type == typeof(ulong))
            _currentIL.Emit(OpCodes.Ldind_I8);
        else if (type == typeof(bool) || type == typeof(byte))
            _currentIL.Emit(OpCodes.Ldind_U1);
        else if (type == typeof(sbyte))
            _currentIL.Emit(OpCodes.Ldind_I1);
        else if (type == typeof(short))
            _currentIL.Emit(OpCodes.Ldind_I2);
        else if (type == typeof(ushort) || type == typeof(char))
            _currentIL.Emit(OpCodes.Ldind_U2);
        else if (type == typeof(float))
            _currentIL.Emit(OpCodes.Ldind_R4);
        else if (type == typeof(double))
            _currentIL.Emit(OpCodes.Ldind_R8);
        else if (type.IsValueType)
            _currentIL.Emit(OpCodes.Ldobj, type);
        else
            _currentIL.Emit(OpCodes.Ldind_Ref);
    }

    private void EmitStoreIndirect(Type type)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (type.IsEnum || type == typeof(int) || type == typeof(uint))
            _currentIL.Emit(OpCodes.Stind_I4);
        else if (type == typeof(long) || type == typeof(ulong))
            _currentIL.Emit(OpCodes.Stind_I8);
        else if (type == typeof(bool) || type == typeof(byte) || type == typeof(sbyte))
            _currentIL.Emit(OpCodes.Stind_I1);
        else if (type == typeof(short) || type == typeof(ushort) || type == typeof(char))
            _currentIL.Emit(OpCodes.Stind_I2);
        else if (type == typeof(float))
            _currentIL.Emit(OpCodes.Stind_R4);
        else if (type == typeof(double))
            _currentIL.Emit(OpCodes.Stind_R8);
        else if (type.IsValueType)
            _currentIL.Emit(OpCodes.Stobj, type);
        else
            _currentIL.Emit(OpCodes.Stind_Ref);
    }

    private void EmitConstantValue(object? value, Type targetType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var nullableUnderlyingType = Nullable.GetUnderlyingType(targetType);
        if (nullableUnderlyingType != null)
        {
            if (value == null)
            {
                EmitDefaultValue(targetType);
                return;
            }

            EmitConstantValue(value, nullableUnderlyingType);
            var nullableConstructor = targetType.GetConstructor(new[] { nullableUnderlyingType });
            if (nullableConstructor == null)
            {
                throw new InvalidOperationException($"Could not resolve {targetType.FullName}({nullableUnderlyingType.FullName})");
            }

            _currentIL.Emit(OpCodes.Newobj, nullableConstructor);
            return;
        }

        if (value == null)
        {
            _currentIL.Emit(OpCodes.Ldnull);
            return;
        }

        if (targetType.IsEnum)
        {
            EmitConstantValue(Convert.ChangeType(value, Enum.GetUnderlyingType(targetType)), Enum.GetUnderlyingType(targetType));
            return;
        }

        if (targetType == typeof(string))
        {
            _currentIL.Emit(OpCodes.Ldstr, (string)value);
            return;
        }

        if (targetType == typeof(bool))
        {
            _currentIL.Emit(Convert.ToBoolean(value) ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
            return;
        }

        if (targetType == typeof(char))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, Convert.ToInt32(value));
            return;
        }

        if (targetType == typeof(byte))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, (int)Convert.ToByte(value));
            return;
        }

        if (targetType == typeof(sbyte))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, (int)Convert.ToSByte(value));
            return;
        }

        if (targetType == typeof(short))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, (int)Convert.ToInt16(value));
            return;
        }

        if (targetType == typeof(ushort))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, (int)Convert.ToUInt16(value));
            return;
        }

        if (targetType == typeof(int))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, Convert.ToInt32(value));
            return;
        }

        if (targetType == typeof(uint))
        {
            _currentIL.Emit(OpCodes.Ldc_I4, unchecked((int)Convert.ToUInt32(value)));
            return;
        }

        if (targetType == typeof(long))
        {
            _currentIL.Emit(OpCodes.Ldc_I8, Convert.ToInt64(value));
            return;
        }

        if (targetType == typeof(ulong))
        {
            _currentIL.Emit(OpCodes.Ldc_I8, unchecked((long)Convert.ToUInt64(value)));
            return;
        }

        if (targetType == typeof(float))
        {
            _currentIL.Emit(OpCodes.Ldc_R4, Convert.ToSingle(value));
            return;
        }

        if (targetType == typeof(double))
        {
            _currentIL.Emit(OpCodes.Ldc_R8, Convert.ToDouble(value));
            return;
        }

        if (targetType == typeof(decimal))
        {
            var bits = decimal.GetBits(Convert.ToDecimal(value));
            var decimalConstructor = typeof(decimal).GetConstructor(new[] { typeof(int), typeof(int), typeof(int), typeof(bool), typeof(byte) });
            if (decimalConstructor == null)
            {
                throw new InvalidOperationException("Could not resolve decimal(int, int, int, bool, byte)");
            }

            _currentIL.Emit(OpCodes.Ldc_I4, bits[0]);
            _currentIL.Emit(OpCodes.Ldc_I4, bits[1]);
            _currentIL.Emit(OpCodes.Ldc_I4, bits[2]);
            _currentIL.Emit((bits[3] & unchecked((int)0x80000000)) != 0 ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
            _currentIL.Emit(OpCodes.Ldc_I4_S, (byte)((bits[3] >> 16) & 0x7F));
            _currentIL.Emit(OpCodes.Newobj, decimalConstructor);
            return;
        }

        throw new NotSupportedException($"Literal field constant of type {targetType} is not supported");
    }

    private void EmitAddressableExpression(Expression expression, Type expressionType)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        switch (expression)
        {
            case IdentifierExpression ident when _locals.TryGetValue(ident.Name, out var local):
                if (IsLiftedIdentifier(ident.Name))
                {
                    EmitLoadLiftedLocalAddress(local);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloca_S, local);
                }
                return;
            case IdentifierExpression ident when _parameters.TryGetValue(ident.Name, out var parameterIndex):
                if (_byRefParameters != null && _byRefParameters.Contains(ident.Name))
                {
                    EmitLoadArgument(parameterIndex);
                }
                else if (parameterIndex <= byte.MaxValue)
                {
                    _currentIL.Emit(OpCodes.Ldarga_S, (byte)parameterIndex);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldarga, parameterIndex);
                }
                return;
            case IdentifierExpression ident when _closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField) && IsLiftedClosureField(ident.Name):
                EmitLoadLiftedClosureFieldAddress(closureField);
                return;
            case IdentifierExpression ident when _currentTypeBuilder != null:
                var primaryField = FindPrimaryConstructorField(_currentTypeBuilder, ident.Name);
                if (primaryField != null)
                {
                    _currentIL.Emit(OpCodes.Ldarg_0);
                    _currentIL.Emit(OpCodes.Ldflda, primaryField);
                    return;
                }

                var field = FindField(_currentTypeBuilder, ident.Name);
                if (field != null)
                {
                    _currentIL.Emit(OpCodes.Ldarg_0);
                    _currentIL.Emit(OpCodes.Ldflda, field);
                    return;
                }
                break;
        }

        EmitExpression(expression);
        var tempLocal = _currentIL.DeclareLocal(expressionType);
        _currentIL.Emit(OpCodes.Stloc, tempLocal);
        _currentIL.Emit(OpCodes.Ldloca_S, tempLocal);
    }

    private void EmitArgumentAddress(Expression expression, Type elementType)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        switch (expression)
        {
            case OutVariableDeclarationExpression outVar:
                var localType = outVar.Type != null ? ResolveType(outVar.Type, _currentGenericParameters) : elementType;
                if (!_locals.TryGetValue(outVar.VariableName, out var outLocal))
                {
                    outLocal = DeclareNamedLocal(outVar.VariableName, localType);
                    if (outLocal.LocalType != localType)
                    {
                        EmitInitializeNamedLocal(outLocal, localType, emitDefaultValue: true, initializer: null);
                    }
                }
                if (IsLiftedIdentifier(outVar.VariableName))
                {
                    EmitLoadLiftedLocalAddress(outLocal);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloca_S, outLocal);
                }
                return;

            case IdentifierExpression ident when _locals.TryGetValue(ident.Name, out var local):
                if (IsLiftedIdentifier(ident.Name))
                {
                    EmitLoadLiftedLocalAddress(local);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloca_S, local);
                }
                return;

            case IdentifierExpression ident when _parameters.TryGetValue(ident.Name, out var parameterIndex):
                if (_byRefParameters != null && _byRefParameters.Contains(ident.Name))
                {
                    EmitLoadArgument(parameterIndex);
                }
                else if (parameterIndex <= byte.MaxValue)
                {
                    _currentIL.Emit(OpCodes.Ldarga_S, (byte)parameterIndex);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldarga, parameterIndex);
                }
                return;
            case IdentifierExpression ident when _closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField) && IsLiftedClosureField(ident.Name):
                EmitLoadLiftedClosureFieldAddress(closureField);
                return;
            case MemberAccessExpression memberAccess:
                EmitMemberArgumentAddress(memberAccess);
                return;
            case IndexAccessExpression indexAccess:
                EmitIndexArgumentAddress(indexAccess);
                return;
        }

        throw new NotImplementedException($"ref/out arguments for {expression.GetType().Name} are not yet supported in IL compiler");
    }

    private void EmitMemberArgumentAddress(MemberAccessExpression memberAccess)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
        {
            if (staticType is TypeBuilder staticTypeBuilder)
            {
                if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, memberAccess.MemberName), out var staticFieldBuilder))
                {
                    _currentIL.Emit(OpCodes.Ldsflda, staticFieldBuilder);
                    return;
                }

                throw new InvalidOperationException($"ref/out arguments require a field, but {GetTypeKey(staticTypeBuilder)}.{memberAccess.MemberName} is not a field");
            }

            var staticField = staticType.GetField(
                memberAccess.MemberName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            if (staticField != null)
            {
                _currentIL.Emit(OpCodes.Ldsflda, staticField);
                return;
            }

            throw new InvalidOperationException($"ref/out arguments require a static field, but {GetTypeKey(staticType)}.{memberAccess.MemberName} was not found");
        }

        var objectType = GetExpressionType(memberAccess.Object);
        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberAccess.MemberName), out var fieldBuilder))
            {
                if (fieldBuilder.IsStatic)
                {
                    _currentIL.Emit(OpCodes.Ldsflda, fieldBuilder);
                }
                else
                {
                    if (IsValueTypeLike(objectType) && !objectType.IsGenericParameter)
                    {
                        EmitAddressableExpression(memberAccess.Object, objectType);
                    }
                    else
                    {
                        EmitExpression(memberAccess.Object);
                    }

                    _currentIL.Emit(OpCodes.Ldflda, fieldBuilder);
                }

                return;
            }

            throw new InvalidOperationException($"ref/out arguments require a field, but {GetTypeKey(typeBuilder)}.{memberAccess.MemberName} is not a field");
        }

        var field = objectType.GetField(memberAccess.MemberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (field != null)
        {
            if (field.IsStatic)
            {
                _currentIL.Emit(OpCodes.Ldsflda, field);
            }
            else
            {
                if (IsValueTypeLike(objectType) && !objectType.IsGenericParameter)
                {
                    EmitAddressableExpression(memberAccess.Object, objectType);
                }
                else
                {
                    EmitExpression(memberAccess.Object);
                }

                _currentIL.Emit(OpCodes.Ldflda, field);
            }

            return;
        }

        throw new InvalidOperationException($"ref/out arguments require a field, but {objectType.Name}.{memberAccess.MemberName} is not a field");
    }

    private void EmitIndexArgumentAddress(IndexAccessExpression indexAccess)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var objectType = GetExpressionType(indexAccess.Object);
        if (!objectType.IsArray)
        {
            throw new NotImplementedException($"ref/out arguments for indexed access are only supported on arrays in the IL compiler, not {objectType}");
        }

        var elementType = objectType.GetElementType()
            ?? throw new InvalidOperationException($"Could not resolve array element type for {objectType}");
        var indexType = GetExpressionType(indexAccess.Index);

        if (indexType == typeof(Range))
        {
            throw new InvalidOperationException("ref/out arguments do not support range-based index access");
        }

        EmitExpression(indexAccess.Object);

        if (indexType == typeof(Index))
        {
            var indexLocal = _currentIL.DeclareLocal(typeof(Index));
            var arrayLocal = _currentIL.DeclareLocal(objectType);
            var lengthLocal = _currentIL.DeclareLocal(typeof(int));
            _currentIL.Emit(OpCodes.Stloc, arrayLocal);
            EmitExpression(indexAccess.Index);
            _currentIL.Emit(OpCodes.Stloc, indexLocal);
            _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
            _currentIL.Emit(OpCodes.Ldlen);
            _currentIL.Emit(OpCodes.Conv_I4);
            _currentIL.Emit(OpCodes.Stloc, lengthLocal);
            _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
            EmitIndexOffset(indexLocal, lengthLocal);
            _currentIL.Emit(OpCodes.Ldelema, elementType);
            return;
        }

        EmitExpression(indexAccess.Index);
        _currentIL.Emit(OpCodes.Ldelema, elementType);
    }

    private void EmitCallArguments(IReadOnlyList<Argument> arguments, IReadOnlyList<Type> parameterTypes)
    {
        for (int i = 0; i < arguments.Count; i++)
        {
            var argument = arguments[i];
            var parameterType = parameterTypes[i];
            var parameterElementType = GetByRefElementType(parameterType);

            if (argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out)
            {
                EmitArgumentAddress(argument.Value, parameterElementType);
            }
            else
            {
                EmitExpressionWithExpectedType(argument.Value, parameterElementType);
            }
        }
    }

    /// <summary>
    /// Compile the AST to an assembly file
    /// </summary>
    public void Compile()
    {
        // Create assembly builder using PersistedAssemblyBuilder for .NET 9+
        var assemblyName = new AssemblyName(_assemblyName);
        var assemblyBuilder = new PersistedAssemblyBuilder(
            assemblyName,
            typeof(object).Assembly);

        // Create module builder
        _moduleBuilder = assemblyBuilder.DefineDynamicModule(_assemblyName);

        // Create Program class (entry point container)
        _programType = _moduleBuilder.DefineType(
            "Program",
            TypeAttributes.Public | TypeAttributes.Class);

        if (_compilationUnit.Declarations.Any(d => d is TestDeclaration or SetupDeclaration or TeardownDeclaration))
        {
            var setupDeclaration = _compilationUnit.Declarations.OfType<SetupDeclaration>().FirstOrDefault();
            var teardownDeclaration = _compilationUnit.Declarations.OfType<TeardownDeclaration>().FirstOrDefault();
            Type[]? interfaces;
            if (UsesNUnitTestFramework)
            {
                interfaces = null;
            }
            else if (UsesAsyncTestLifetime(setupDeclaration, teardownDeclaration))
            {
                interfaces = new[] { ResolveTestFrameworkType("Xunit.IAsyncLifetime", "xunit.core", "xunit.v3.core") };
            }
            else if (teardownDeclaration != null)
            {
                interfaces = new[] { typeof(IDisposable) };
            }
            else
            {
                interfaces = null;
            }

            _testType = _moduleBuilder.DefineType(
                "NSharpTests",
                TypeAttributes.Public | TypeAttributes.Class,
                typeof(object),
                interfaces);
        }

        // First pass: declare all types (classes, structs, interfaces, etc.)
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is ClassDeclaration classDecl)
            {
                DeclareClass(_moduleBuilder, classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                DeclareStruct(_moduleBuilder, structDecl);
            }
            else if (declaration is RecordDeclaration recordDecl)
            {
                DeclareRecord(_moduleBuilder, recordDecl);
            }
            else if (declaration is InterfaceDeclaration interfaceDecl)
            {
                DeclareInterface(_moduleBuilder, interfaceDecl);
            }
            else if (declaration is EnumDeclaration enumDecl)
            {
                DeclareEnum(_moduleBuilder, enumDecl);
            }
            else if (declaration is UnionDeclaration unionDecl)
            {
                DeclareUnion(_moduleBuilder, unionDecl);
            }
            else if (declaration is NewtypeDeclaration newtypeDecl)
            {
                DeclareRecord(_moduleBuilder, CreateSyntheticNewtypeRecord(newtypeDecl));
            }
        }

        // Second pass: declare all top-level functions and class/interface members
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                DeclareFunction(_programType, funcDecl);
            }
            else if (declaration is ClassDeclaration classDecl)
            {
                DeclareClassMembers(classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                DeclareStructMembers(structDecl);
            }
            else if (declaration is RecordDeclaration recordDecl)
            {
                DeclareRecordMembers(recordDecl);
            }
            else if (declaration is InterfaceDeclaration interfaceDecl)
            {
                DeclareInterfaceMembers(interfaceDecl);
            }
            else if (declaration is NewtypeDeclaration newtypeDecl)
            {
                DeclareRecordMembers(CreateSyntheticNewtypeRecord(newtypeDecl));
            }
        }

        if (_testType != null)
        {
            DeclareTestMembers();
        }

        // Third pass: emit all function bodies
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                EmitFunctionBody(funcDecl);
            }
            else if (declaration is ClassDeclaration classDecl)
            {
                EmitClassBodies(classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                EmitStructBodies(structDecl);
            }
            else if (declaration is RecordDeclaration recordDecl)
            {
                EmitRecordBodies(recordDecl);
            }
            else if (declaration is UnionDeclaration unionDecl)
            {
                EmitUnionBodies(unionDecl);
            }
            else if (declaration is NewtypeDeclaration newtypeDecl)
            {
                EmitRecordBodies(CreateSyntheticNewtypeRecord(newtypeDecl));
            }
        }

        if (_testType != null)
        {
            EmitTestBodies();
        }

        foreach (var enumType in _enumTypes.Values.OfType<EnumBuilder>())
        {
            enumType.CreateType();
        }

        foreach (var stringEnumContainer in _stringEnumContainers.Values)
        {
            stringEnumContainer.CreateType();
        }

        foreach (var helperType in _generatedHelperTypes)
        {
            helperType.CreateType();
        }

        foreach (var closureType in _closureTypes.AsEnumerable().Reverse())
        {
            closureType.CreateType();
        }

        // Create all types
        foreach (var typeBuilder in _types.Values.OrderByDescending(tb => GetTypeKey(tb).Count(c => c == '.')))
        {
            typeBuilder.CreateType();
        }
        _programType.CreateType();
        _testType?.CreateType();

        // Save the assembly to disk using PersistedAssemblyBuilder (.NET 9+)
        using var stream = new FileStream(_outputPath, FileMode.Create, FileAccess.Write);
        assemblyBuilder.Save(stream);

        Console.Error.WriteLine($"IL Compiler: Assembly '{_assemblyName}' compiled and saved to '{_outputPath}'");
    }

    /// <summary>
    /// Declare a function (method signature only, no body)
    /// </summary>
    private void DeclareFunction(TypeBuilder typeBuilder, FunctionDeclaration function)
    {
        var emittedMethodName = GetEmittedMethodName(function);

        // Create method (without return type and parameter types yet if generic)
        var methodBuilder = typeBuilder.DefineMethod(
            emittedMethodName,
            MethodAttributes.Public
            | MethodAttributes.Static
            | MethodAttributes.HideBySig
            | (function.IsOperatorOverload || function.IsConversionOperator ? MethodAttributes.SpecialName : 0));

        // Define generic parameters if present
        GenericTypeParameterBuilder[]? genericParameters = null;
        if (function.TypeParameters != null && function.TypeParameters.Count > 0)
        {
            var typeParamNames = function.TypeParameters.Select(tp => tp.Name).ToArray();
            genericParameters = methodBuilder.DefineGenericParameters(typeParamNames);

            // Apply constraints if present
            if (function.Constraints != null)
            {
                foreach (var constraint in function.Constraints)
                {
                    var typeParam = genericParameters.FirstOrDefault(gp => gp.Name == constraint.TypeParameter);
                    if (typeParam != null)
                    {
                        ApplyGenericConstraints(typeParam, constraint, genericParameters);
                    }
                }
            }
        }

        // Determine return type (may reference generic parameters)
        var returnType = GetDeclaredFunctionReturnType(function, genericParameters);

        // Determine parameter types (may reference generic parameters)
        var parameterTypes = function.Parameters
            .Select(p => ResolveParameterType(p, genericParameters))
            .ToArray();

        // Set return type and parameter types
        methodBuilder.SetReturnType(returnType);
        methodBuilder.SetParameters(parameterTypes);
        ApplyCustomAttributes(methodBuilder.SetCustomAttribute, function.Attributes);

        // Define parameter names
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(function.Parameters[i]), function.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, function.Parameters[i]);
        }

        // Store method builder for later reference
        _methods[function.Name] = methodBuilder;
        _declaredMethodParameters[function.Name] = function.Parameters;
        RegisterDeclaredMethodOverload(function.Name, function, methodBuilder);
    }

    /// <summary>
    /// Emit the body of a function
    /// </summary>
    private void EmitFunctionBody(FunctionDeclaration function)
    {
        if (!_methodBuildersByDeclaration.TryGetValue(function, out var methodBuilder))
        {
            throw new InvalidOperationException($"Method {function.Name} not declared");
        }

        // Get generic parameters if the method is generic
        _currentGenericParameters = null;
        if (methodBuilder.IsGenericMethodDefinition)
        {
            _currentGenericParameters = methodBuilder.GetGenericArguments()
                .Cast<GenericTypeParameterBuilder>()
                .ToArray();
        }

        // Determine return type
        var returnType = GetDeclaredFunctionReturnType(function, _currentGenericParameters);
        _currentIL = methodBuilder.GetILGenerator();
        var bodyReturnType = returnType;
        if (function.Modifiers.HasFlag(Modifiers.Async) && TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
        {
            _currentAsyncReturnType = returnType;
            _currentAsyncResultType = asyncResultType;
            _currentAsyncReturnsValueTask = returnsValueTask;
            bodyReturnType = asyncResultType ?? typeof(void);
        }

        InitializeBodyContext(bodyReturnType, ContainsNestedFunction(function.Body)
            || (function.ExpressionBody != null && ContainsNestedFunction(function.ExpressionBody)));
        if (function.Modifiers.HasFlag(Modifiers.Generator))
        {
            if (!TryGetSequenceElementType(returnType, out var yieldElementType, out _))
            {
                throw new InvalidOperationException($"Generator function {function.Name} must return an enumerable sequence type, but resolved to {returnType}");
            }

            _currentGeneratorReturnType = returnType;
            _currentYieldElementType = yieldElementType;
            _currentYieldBreakLabel = _currentIL.DefineLabel();
            var listType = typeof(List<>).MakeGenericType(yieldElementType);
            _currentYieldListLocal = _currentIL.DeclareLocal(listType);
            var listCtor = listType.GetConstructor(Type.EmptyTypes)
                ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
            _currentIL.Emit(OpCodes.Newobj, listCtor);
            _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
        }

        RegisterParameterContext(function.Parameters, 0, _currentGenericParameters);

        // Emit function body
        if (function.Body != null)
        {
            EmitStatement(function.Body);
        }
        else if (function.ExpressionBody != null)
        {
            if (_currentAsyncReturnType != null)
            {
                if (_currentAsyncResultType != null)
                {
                    EmitExpressionWithExpectedType(function.ExpressionBody, _currentAsyncResultType);
                }
                else
                {
                    EmitExpression(function.ExpressionBody);
                    if (GetExpressionType(function.ExpressionBody) != typeof(void))
                    {
                        _currentIL.Emit(OpCodes.Pop);
                    }
                }

                EmitWrapCurrentAsyncReturn();
                _currentIL.Emit(OpCodes.Ret);
            }
            else
            {
                EmitExpression(function.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }
        }

        // Ensure function ends with a return
        if (_currentGeneratorReturnType != null)
        {
            _currentIL.MarkLabel(_currentYieldBreakLabel!.Value);
            EmitGeneratorReturnValue(_currentGeneratorReturnType, _currentYieldListLocal!);
            _currentIL.Emit(OpCodes.Ret);
        }
        else if (_currentAsyncReturnType != null && _currentAsyncResultType == null)
        {
            EmitWrapCurrentAsyncReturn();
            _currentIL.Emit(OpCodes.Ret);
        }
        else if (returnType == typeof(void))
        {
            _currentIL.Emit(OpCodes.Ret);
        }

        // Clear context
        ClearMethodContext();
        _currentGenericParameters = null;
    }

    /// <summary>
    /// Emit IL for a statement
    /// </summary>
    private void EmitStatement(Statement statement)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (statement)
        {
            case BlockStatement block:
                EmitBlock(block);
                break;

            case VariableDeclarationStatement varDecl:
                EmitVariableDeclaration(varDecl);
                break;

            case TupleDeconstructionStatement tupleDeconstruction:
                EmitTupleDeconstruction(tupleDeconstruction);
                break;

            case ReturnStatement ret:
                EmitReturn(ret);
                break;

            case ExpressionStatement exprStmt:
                EmitExpression(exprStmt.Expression);
                // Pop the result if it's not used
                if (GetExpressionType(exprStmt.Expression) != typeof(void))
                {
                    _currentIL.Emit(OpCodes.Pop);
                }
                break;

            case IfStatement ifStmt:
                EmitIf(ifStmt);
                break;

            case ForStatement forStmt:
                EmitFor(forStmt);
                break;

            case WhileStatement whileStmt:
                EmitWhile(whileStmt);
                break;

            case PrintStatement printStmt:
                EmitPrint(printStmt);
                break;

            case AssertStatement assertStmt:
                EmitAssert(assertStmt);
                break;

            case AssertThrowsStatement assertThrows:
                EmitAssertThrows(assertThrows);
                break;

            case LocalFunctionStatement:
                break;

            case PreprocessorDirective:
            case FileImport:
            case NamespaceImport:
                break;

            case ForeachStatement foreachStmt:
                EmitForeach(foreachStmt);
                break;

            case AwaitForEachStatement awaitForeachStmt:
                EmitAwaitForeach(awaitForeachStmt);
                break;

            case YieldStatement yieldStmt:
                EmitYield(yieldStmt);
                break;

            case TryStatement tryStmt:
                EmitTry(tryStmt);
                break;

            case UsingStatement usingStmt:
                EmitUsing(usingStmt);
                break;

            case BreakStatement:
                EmitBreak();
                break;

            case ContinueStatement:
                EmitContinue();
                break;

            case ThrowStatement throwStmt:
                EmitThrow(throwStmt);
                break;

            case LockStatement lockStmt:
                EmitLock(lockStmt);
                break;

            case SwitchStatement switchStmt:
                EmitSwitch(switchStmt);
                break;

            case EmptyStatement:
                break;

            default:
                throw new NotImplementedException($"Statement type {statement.GetType().Name} not yet implemented in IL compiler");
        }
    }

    private void EmitBlock(BlockStatement block)
    {
        if (_currentIL == null || _locals == null)
            throw new InvalidOperationException("No IL generator context");

        var localFunctions = block.Statements
            .OfType<LocalFunctionStatement>()
            .ToList();

        foreach (var localFunction in localFunctions)
        {
            _localFunctionDeclarations ??= new Dictionary<string, FunctionDeclaration>();
            _localFunctionDeclarations[localFunction.Function.Name] = localFunction.Function;
        }

        if (_liftLocalsIntoBoxes)
        {
            foreach (var statement in block.Statements)
            {
                switch (statement)
                {
                    case VariableDeclarationStatement variableDeclaration when !_locals.ContainsKey(variableDeclaration.Name):
                        var variableType = variableDeclaration.Type != null
                            ? ResolveType(variableDeclaration.Type, _currentGenericParameters)
                            : variableDeclaration.Initializer != null
                                ? GetExpressionType(variableDeclaration.Initializer)
                                : typeof(object);
                        var variableLocal = DeclareNamedLocal(variableDeclaration.Name, variableType);
                        if (variableLocal.LocalType != variableType)
                        {
                            EmitInitializeNamedLocal(variableLocal, variableType, emitDefaultValue: true, initializer: null);
                        }
                        break;

                    case TupleDeconstructionStatement tupleDeconstruction:
                        var tupleType = GetExpressionType(tupleDeconstruction.Initializer);
                        for (int i = 0; i < tupleDeconstruction.Names.Count; i++)
                        {
                            var name = tupleDeconstruction.Names[i];
                            if (name == "_" || _locals.ContainsKey(name))
                            {
                                continue;
                            }

                            var field = tupleType.GetField($"Item{i + 1}");
                            if (field == null)
                            {
                                continue;
                            }

                            var tupleLocal = DeclareNamedLocal(name, field.FieldType);
                            if (tupleLocal.LocalType != field.FieldType)
                            {
                                EmitInitializeNamedLocal(tupleLocal, field.FieldType, emitDefaultValue: true, initializer: null);
                            }
                        }
                        break;
                }
            }
        }

        foreach (var localFunction in localFunctions)
        {
            if (localFunction.Function.TypeParameters is { Count: > 0 })
            {
                DeclareGenericLocalFunction(localFunction);
                continue;
            }

            var delegateType = GetLocalFunctionDelegateType(localFunction.Function);
            var localBuilder = DeclareNamedLocal(localFunction.Function.Name, delegateType);
            if (localBuilder.LocalType != delegateType)
            {
                EmitInitializeNamedLocal(localBuilder, delegateType, emitDefaultValue: true, initializer: null);
            }
        }

        foreach (var localFunction in localFunctions)
        {
            if (localFunction.Function.TypeParameters is { Count: > 0 })
            {
                EmitGenericLocalFunctionBody(localFunction);
                continue;
            }

            EmitLocalFunctionInitialization(localFunction);
        }

        foreach (var statement in block.Statements)
        {
            if (statement is LocalFunctionStatement localFunction)
            {
                continue;
            }

            EmitStatement(statement);
        }
    }

    private Type GetLocalFunctionDelegateType(FunctionDeclaration function)
    {
        var parameterTypes = function.Parameters
            .Select(parameter => ResolveParameterType(parameter, _currentGenericParameters))
            .ToArray();
        var returnType = GetLocalFunctionReturnType(function);
        return CreateDelegateType(parameterTypes, returnType);
    }

    private Type GetLocalFunctionReturnType(FunctionDeclaration function)
    {
        var innerReturnType = function.ReturnType != null
            ? ResolveType(function.ReturnType, _currentGenericParameters)
            : function.ExpressionBody != null
                ? GetExpressionType(function.ExpressionBody)
                : function.Body != null
                    ? InferLambdaBlockReturnType(function.Body)
                    : typeof(void);

        if (!function.Modifiers.HasFlag(Modifiers.Async)
            || function.Modifiers.HasFlag(Modifiers.Generator)
            || IsTaskLikeType(innerReturnType))
        {
            return innerReturnType;
        }

        return WrapAsyncReturnType(innerReturnType, isEntryPoint: false);
    }

    private void EmitLocalFunctionInitialization(LocalFunctionStatement localFunction)
    {
        if (_currentIL == null || _locals == null)
            throw new InvalidOperationException("No IL generator context");

        if (!_locals.TryGetValue(localFunction.Function.Name, out var localBuilder))
        {
            throw new InvalidOperationException($"Local function {localFunction.Function.Name} was not predeclared");
        }

        var delegateType = GetLocalFunctionDelegateType(localFunction.Function);
        var lambda = new LambdaExpression(
            localFunction.Function.Parameters,
            localFunction.Function.ExpressionBody,
            localFunction.Function.Body,
            localFunction.Line,
            localFunction.Column);
        var savedPendingLocalFunction = _pendingLocalFunctionDefinition;
        _pendingLocalFunctionDefinition = localFunction.Function;
        try
        {
            EmitExpressionWithExpectedType(lambda, delegateType);
        }
        finally
        {
            _pendingLocalFunctionDefinition = savedPendingLocalFunction;
        }
        if (localBuilder.LocalType == delegateType)
        {
            _currentIL.Emit(OpCodes.Stloc, localBuilder);
        }
        else
        {
            EmitStoreLiftedLocalValue(localBuilder, delegateType, leaveValueOnStack: false);
        }
    }

    /// <summary>
    /// Emit IL for a print statement
    /// </summary>
    private void EmitPrint(PrintStatement printStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Emit the value to print
        EmitExpression(printStmt.Value);

        // Box value types if necessary
        var valueType = GetExpressionType(printStmt.Value);
        if (valueType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Box, valueType);
        }

        // Call Console.WriteLine(object)
        var writeLineMethod = typeof(Console).GetMethod("WriteLine", new[] { typeof(object) });
        if (writeLineMethod != null)
        {
            _currentIL.Emit(OpCodes.Call, writeLineMethod);
        }
    }

    private void EmitAssert(AssertStatement assertStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var successLabel = _currentIL.DefineLabel();
        EmitExpression(assertStmt.Condition);
        _currentIL.Emit(OpCodes.Brtrue, successLabel);

        var invalidOperationCtor = typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) });
        if (invalidOperationCtor == null)
        {
            throw new InvalidOperationException("Could not resolve InvalidOperationException(string)");
        }

        if (assertStmt.Message != null)
        {
            EmitExpression(assertStmt.Message);
            var messageType = GetExpressionType(assertStmt.Message);
            if (messageType != typeof(string))
            {
                if (messageType.IsValueType)
                {
                    _currentIL.Emit(OpCodes.Box, messageType);
                }

                var toStringMethod = typeof(object).GetMethod(nameof(ToString), Type.EmptyTypes);
                if (toStringMethod == null)
                {
                    throw new InvalidOperationException("Could not resolve object.ToString()");
                }

                _currentIL.Emit(OpCodes.Callvirt, toStringMethod);
            }
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldstr, "Assertion failed");
        }

        _currentIL.Emit(OpCodes.Newobj, invalidOperationCtor);
        _currentIL.Emit(OpCodes.Throw);
        _currentIL.MarkLabel(successLabel);
    }

    private void EmitAssertThrows(AssertThrowsStatement assertThrows)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var exceptionType = ResolveType(assertThrows.ExceptionType, _currentGenericParameters);
        var invalidOperationCtor = typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) });
        if (invalidOperationCtor == null)
        {
            throw new InvalidOperationException("Could not resolve InvalidOperationException(string)");
        }

        _currentIL.BeginExceptionBlock();
        EmitStatement(assertThrows.Body);
        _currentIL.Emit(OpCodes.Ldstr, $"Expected exception of type {exceptionType.Name} was not thrown");
        _currentIL.Emit(OpCodes.Newobj, invalidOperationCtor);
        _currentIL.Emit(OpCodes.Throw);
        _currentIL.BeginCatchBlock(exceptionType);
        _currentIL.Emit(OpCodes.Pop);
        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for a variable declaration
    /// </summary>
    private void EmitVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Determine type from initializer or explicit type
        Type varType;
        if (varDecl.Type != null)
        {
            varType = ResolveType(varDecl.Type, _currentGenericParameters);
        }
        else if (varDecl.Initializer != null)
        {
            varType = GetExpressionType(varDecl.Initializer);
        }
        else
        {
            throw new InvalidOperationException("Variable must have either a type or an initializer");
        }

        // Declare local
        LocalBuilder local;
        var hadExistingLocal = _locals.TryGetValue(varDecl.Name, out var existingLocal);
        if (hadExistingLocal)
        {
            local = existingLocal;
        }
        else
        {
            local = DeclareNamedLocal(varDecl.Name, varType);
        }

        // Emit initializer if present
        if (varDecl.Initializer != null)
        {
            if (hadExistingLocal && IsLiftedIdentifier(varDecl.Name))
            {
                EmitExpressionWithExpectedType(varDecl.Initializer, varType);
                EmitStoreLiftedLocalValue(local, varType, leaveValueOnStack: false);
            }
            else
            {
                EmitInitializeNamedLocal(local, varType, emitDefaultValue: false, initializer: varDecl.Initializer);
            }
        }
        else if (!hadExistingLocal && local.LocalType != varType)
        {
            EmitInitializeNamedLocal(local, varType, emitDefaultValue: true, initializer: null);
        }
    }

    /// <summary>
    /// Emit IL for tuple deconstruction
    /// </summary>
    private void EmitTupleDeconstruction(TupleDeconstructionStatement tupleDecl)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        EmitExpression(tupleDecl.Initializer);
        var tupleType = GetExpressionType(tupleDecl.Initializer);
        var tupleLocal = _currentIL.DeclareLocal(tupleType);
        _currentIL.Emit(OpCodes.Stloc, tupleLocal);

        for (int i = 0; i < tupleDecl.Names.Count; i++)
        {
            var name = tupleDecl.Names[i];
            if (name == "_")
            {
                continue;
            }

            var field = ResolveRuntimeField(
                tupleType,
                $"Item{i + 1}",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (field == null)
            {
                throw new InvalidOperationException($"Tuple field Item{i + 1} not found on type {tupleType}");
            }

            LocalBuilder local;
            var hadExistingLocal = _locals.TryGetValue(name, out var existingLocal);
            if (hadExistingLocal)
            {
                local = existingLocal;
            }
            else
            {
                local = DeclareNamedLocal(name, field.FieldType);
            }

            if (tupleType.IsValueType)
            {
                _currentIL.Emit(OpCodes.Ldloca_S, tupleLocal);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, tupleLocal);
            }

            _currentIL.Emit(OpCodes.Ldfld, field);
            if (hadExistingLocal && IsLiftedIdentifier(name))
            {
                EmitStoreLiftedLocalValue(local, field.FieldType, leaveValueOnStack: false);
            }
            else if (local.LocalType == field.FieldType)
            {
                _currentIL.Emit(OpCodes.Stloc, local);
            }
            else
            {
                _currentIL.Emit(OpCodes.Newobj, GetStrongBoxConstructor(field.FieldType));
                _currentIL.Emit(OpCodes.Stloc, local);
            }
        }
    }

    /// <summary>
    /// Emit IL for a return statement
    /// </summary>
    private Type GetAwaitResultType(Type awaitableType)
    {
        var getAwaiter = awaitableType.GetMethod("GetAwaiter", Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaitable type {awaitableType} does not expose GetAwaiter()");
        var getResult = getAwaiter.ReturnType.GetMethod("GetResult", Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaiter type {getAwaiter.ReturnType} does not expose GetResult()");
        return getResult.ReturnType;
    }

    private void EmitAwaiterGetResult(Type awaitableType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (awaitableType == typeof(System.Threading.Tasks.ValueTask))
        {
            var asTaskMethod = typeof(System.Threading.Tasks.ValueTask).GetMethod(nameof(System.Threading.Tasks.ValueTask.AsTask), Type.EmptyTypes)
                ?? throw new InvalidOperationException("Could not resolve ValueTask.AsTask()");
            var awaitableLocal = _currentIL.DeclareLocal(awaitableType);
            _currentIL.Emit(OpCodes.Stloc, awaitableLocal);
            _currentIL.Emit(OpCodes.Ldloca_S, awaitableLocal);
            _currentIL.Emit(OpCodes.Call, asTaskMethod);
            EmitAwaiterGetResult(typeof(System.Threading.Tasks.Task));
            return;
        }

        if (awaitableType.IsGenericType && awaitableType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.ValueTask<>))
        {
            var asTaskMethod = awaitableType.GetMethod(nameof(System.Threading.Tasks.ValueTask<int>.AsTask), Type.EmptyTypes)
                ?? throw new InvalidOperationException($"Could not resolve AsTask() for {awaitableType}");
            var awaitableLocal = _currentIL.DeclareLocal(awaitableType);
            _currentIL.Emit(OpCodes.Stloc, awaitableLocal);
            _currentIL.Emit(OpCodes.Ldloca_S, awaitableLocal);
            _currentIL.Emit(OpCodes.Call, asTaskMethod);
            var taskType = typeof(System.Threading.Tasks.Task<>).MakeGenericType(awaitableType.GetGenericArguments()[0]);
            EmitAwaiterGetResult(taskType);
            return;
        }

        var getAwaiter = awaitableType.GetMethod("GetAwaiter", Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaitable type {awaitableType} does not expose GetAwaiter()");
        var awaitableNeedsAddress = awaitableType.IsValueType && !getAwaiter.IsStatic;
        if (awaitableNeedsAddress)
        {
            var awaitableLocal = _currentIL.DeclareLocal(awaitableType);
            _currentIL.Emit(OpCodes.Stloc, awaitableLocal);
            _currentIL.Emit(OpCodes.Ldloca_S, awaitableLocal);
            _currentIL.Emit(OpCodes.Call, getAwaiter);
        }
        else
        {
            _currentIL.Emit(getAwaiter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getAwaiter);
        }

        var getResult = getAwaiter.ReturnType.GetMethod("GetResult", Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaiter type {getAwaiter.ReturnType} does not expose GetResult()");
        var awaiterType = getAwaiter.ReturnType;
        var awaiterNeedsAddress = awaiterType.IsValueType && !getResult.IsStatic;
        if (awaiterNeedsAddress)
        {
            var awaiterLocal = _currentIL.DeclareLocal(awaiterType);
            _currentIL.Emit(OpCodes.Stloc, awaiterLocal);
            _currentIL.Emit(OpCodes.Ldloca_S, awaiterLocal);
            _currentIL.Emit(OpCodes.Call, getResult);
        }
        else
        {
            _currentIL.Emit(getResult.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getResult);
        }
    }

    private void EmitWrapCurrentAsyncReturn()
    {
        if (_currentIL == null || _currentAsyncReturnType == null)
        {
            throw new InvalidOperationException("No async return context");
        }

        if (_currentAsyncResultType == null)
        {
            if (_currentAsyncReturnsValueTask)
            {
                EmitDefaultValue(_currentAsyncReturnType);
            }
            else
            {
                var completedTask = typeof(System.Threading.Tasks.Task).GetProperty(nameof(System.Threading.Tasks.Task.CompletedTask), BindingFlags.Public | BindingFlags.Static)
                    ?.GetMethod;
                if (completedTask == null)
                {
                    throw new InvalidOperationException("Could not resolve Task.CompletedTask");
                }

                _currentIL.Emit(OpCodes.Call, completedTask);
            }

            return;
        }

        if (_currentAsyncReturnsValueTask)
        {
            var ctor = _currentAsyncReturnType.GetConstructor(new[] { _currentAsyncResultType })
                ?? throw new InvalidOperationException($"Could not resolve constructor for {_currentAsyncReturnType}");
            _currentIL.Emit(OpCodes.Newobj, ctor);
            return;
        }

        var fromResult = typeof(System.Threading.Tasks.Task)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(method => method.Name == nameof(System.Threading.Tasks.Task.FromResult) && method.IsGenericMethodDefinition && method.GetParameters().Length == 1)
            ?.MakeGenericMethod(_currentAsyncResultType)
            ?? throw new InvalidOperationException("Could not resolve Task.FromResult<T>");
        _currentIL.Emit(OpCodes.Call, fromResult);
    }

    private void EmitReturn(ReturnStatement ret)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (_currentGeneratorReturnType != null)
        {
            if (ret.Value != null)
            {
                throw new NotImplementedException("Explicit return values are not supported inside generator methods in the IL compiler");
            }

            _currentIL.Emit(OpCodes.Br, _currentYieldBreakLabel!.Value);
            return;
        }

        if (_currentAsyncReturnType != null)
        {
            if (ret.Value != null && _currentAsyncResultType != null)
            {
                if (ret.Value is DefaultExpression)
                {
                    EmitDefaultValue(_currentAsyncResultType);
                }
                else
                {
                    EmitExpressionWithExpectedType(ret.Value, _currentAsyncResultType);
                }
            }
            else if (ret.Value != null)
            {
                EmitExpression(ret.Value);
                if (GetExpressionType(ret.Value) != typeof(void))
                {
                    _currentIL.Emit(OpCodes.Pop);
                }
            }

            EmitWrapCurrentAsyncReturn();
            _currentIL.Emit(OpCodes.Ret);
            return;
        }

        if (ret.Value != null)
        {
            if (ret.Value is DefaultExpression && _currentReturnType != null)
            {
                EmitDefaultValue(_currentReturnType);
            }
            else
            {
                EmitExpressionWithExpectedType(ret.Value, _currentReturnType ?? GetExpressionType(ret.Value));
            }
        }
        _currentIL.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit IL for an if statement
    /// </summary>
    private void EmitIf(IfStatement ifStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var elseLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        // Emit condition
        EmitExpression(ifStmt.Condition);
        _currentIL.Emit(OpCodes.Brfalse, elseLabel);

        // Emit then branch
        EmitStatement(ifStmt.ThenStatement);
        if (ifStmt.ElseStatement != null)
        {
            _currentIL.Emit(OpCodes.Br, endLabel);
        }

        // Emit else branch
        _currentIL.MarkLabel(elseLabel);
        if (ifStmt.ElseStatement != null)
        {
            EmitStatement(ifStmt.ElseStatement);
            _currentIL.MarkLabel(endLabel);
        }
    }

    /// <summary>
    /// Emit IL for a for statement
    /// </summary>
    private void EmitFor(ForStatement forStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (forStmt.Initializer == null && forStmt.Condition == null
            && forStmt.Iterator == null && forStmt.Body is ForeachStatement forInStmt)
        {
            EmitForeach(forInStmt);
            return;
        }

        if (forStmt.Initializer != null)
        {
            EmitStatement(forStmt.Initializer);
        }

        var conditionLabel = _currentIL.DefineLabel();
        var bodyLabel = _currentIL.DefineLabel();
        var continueLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        _currentIL.Emit(OpCodes.Br, conditionLabel);

        _currentIL.MarkLabel(bodyLabel);
        _breakLabels.Push(new BranchTarget(endLabel, useLeave: false));
        _continueLabels.Push(new BranchTarget(continueLabel, useLeave: false));
        try
        {
            EmitStatement(forStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.MarkLabel(continueLabel);
        if (forStmt.Iterator != null)
        {
            EmitExpression(forStmt.Iterator);
            if (GetExpressionType(forStmt.Iterator) != typeof(void))
            {
                _currentIL.Emit(OpCodes.Pop);
            }
        }

        _currentIL.MarkLabel(conditionLabel);
        if (forStmt.Condition != null)
        {
            EmitExpression(forStmt.Condition);
            _currentIL.Emit(OpCodes.Brtrue, bodyLabel);
        }
        else
        {
            _currentIL.Emit(OpCodes.Br, bodyLabel);
        }

        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for a while statement
    /// </summary>
    private void EmitWhile(WhileStatement whileStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var conditionLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        // Mark condition label
        _currentIL.MarkLabel(conditionLabel);

        // Emit condition
        EmitExpression(whileStmt.Condition);
        _currentIL.Emit(OpCodes.Brfalse, endLabel);

        // Emit body
        _breakLabels.Push(new BranchTarget(endLabel, useLeave: false));
        _continueLabels.Push(new BranchTarget(conditionLabel, useLeave: false));
        try
        {
            EmitStatement(whileStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        // Jump back to condition
        _currentIL.Emit(OpCodes.Br, conditionLabel);

        // Mark end label
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for a break statement
    /// </summary>
    private void EmitBreak()
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");
        if (_breakLabels.Count == 0) throw new InvalidOperationException("break used outside of a loop or switch");

        var breakTarget = _breakLabels.Peek();
        _currentIL.Emit(breakTarget.UseLeave ? OpCodes.Leave : OpCodes.Br, breakTarget.Label);
    }

    /// <summary>
    /// Emit IL for a continue statement
    /// </summary>
    private void EmitContinue()
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");
        if (_continueLabels.Count == 0) throw new InvalidOperationException("continue used outside of a loop");

        var continueTarget = _continueLabels.Peek();
        _currentIL.Emit(continueTarget.UseLeave ? OpCodes.Leave : OpCodes.Br, continueTarget.Label);
    }

    /// <summary>
    /// Emit IL for a throw statement
    /// </summary>
    private void EmitThrow(ThrowStatement throwStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        EmitExpression(throwStmt.Expression);
        _currentIL.Emit(OpCodes.Throw);
    }

    /// <summary>
    /// Emit IL for a lock statement
    /// </summary>
    private void EmitLock(LockStatement lockStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var monitorEnter = typeof(System.Threading.Monitor).GetMethod(
            nameof(System.Threading.Monitor.Enter),
            new[] { typeof(object) });
        var monitorExit = typeof(System.Threading.Monitor).GetMethod(
            nameof(System.Threading.Monitor.Exit),
            new[] { typeof(object) });

        if (monitorEnter == null || monitorExit == null)
        {
            throw new InvalidOperationException("Could not resolve Monitor.Enter/Exit");
        }

        EmitExpression(lockStmt.LockObject);
        var lockLocal = _currentIL.DeclareLocal(typeof(object));
        _currentIL.Emit(OpCodes.Stloc, lockLocal);

        _currentIL.Emit(OpCodes.Ldloc, lockLocal);
        _currentIL.Emit(OpCodes.Call, monitorEnter);

        _currentIL.BeginExceptionBlock();
        EmitStatement(lockStmt.Body);
        _currentIL.BeginFinallyBlock();
        _currentIL.Emit(OpCodes.Ldloc, lockLocal);
        _currentIL.Emit(OpCodes.Call, monitorExit);
        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for a switch statement
    /// </summary>
    private void EmitSwitch(SwitchStatement switchStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var endLabel = _currentIL.DefineLabel();
        var nextCaseLabels = new Label[switchStmt.Cases.Count];
        var bodyLabels = new Label[switchStmt.Cases.Count];

        for (int i = 0; i < switchStmt.Cases.Count; i++)
        {
            nextCaseLabels[i] = _currentIL.DefineLabel();
            bodyLabels[i] = _currentIL.DefineLabel();
        }

        var switchValueType = GetExpressionType(switchStmt.Value);
        EmitExpression(switchStmt.Value);
        var switchLocal = _currentIL.DeclareLocal(switchValueType);
        _currentIL.Emit(OpCodes.Stloc, switchLocal);

        _breakLabels.Push(new BranchTarget(endLabel, useLeave: false));
        try
        {
            for (int i = 0; i < switchStmt.Cases.Count; i++)
            {
                var switchCase = switchStmt.Cases[i];
                if (switchCase.Pattern == null)
                {
                    _currentIL.Emit(OpCodes.Br, bodyLabels[i]);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloc, switchLocal);
                    EmitPatternTest(switchCase.Pattern, switchValueType, bodyLabels[i], nextCaseLabels[i]);
                }

                _currentIL.MarkLabel(bodyLabels[i]);
                foreach (var statement in switchCase.Statements)
                {
                    EmitStatement(statement);
                }
                _currentIL.Emit(OpCodes.Br, endLabel);

                _currentIL.MarkLabel(nextCaseLabels[i]);
            }
        }
        finally
        {
            _breakLabels.Pop();
        }

        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for a foreach statement
    /// </summary>
    private void EmitForeach(ForeachStatement foreachStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Get the collection type
        var collectionType = GetExpressionType(foreachStmt.Collection);

        // Determine the element type from the collection
        Type elementType;
        Type? enumerableInterface = null;

        if (collectionType.IsArray)
        {
            // Handle arrays
            elementType = collectionType.GetElementType()!;
        }
        else
        {
            // Try to find IEnumerable<T>
            enumerableInterface = GetRuntimeInterfaces(collectionType)
                .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>));

            if (enumerableInterface == null && collectionType.IsGenericType &&
                collectionType.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>))
            {
                enumerableInterface = collectionType;
            }

            if (enumerableInterface != null)
            {
                elementType = enumerableInterface.GetGenericArguments()[0];
            }
            else
            {
                // Fall back to non-generic IEnumerable (element type is object)
                elementType = typeof(object);
            }
        }

        // Emit the collection expression
        EmitExpression(foreachStmt.Collection);

        // Get the enumerator
        MethodInfo? getEnumeratorMethod;
        Type enumeratorType;

        if (collectionType.IsArray)
        {
            // For arrays, we need to use a different approach
            // Arrays don't have GetEnumerator in a straightforward way for IL
            // We'll implement this as a for loop over array indices instead
            EmitForeachForArray(foreachStmt, collectionType, elementType);
            return;
        }
        else if (enumerableInterface != null)
        {
            // Get IEnumerable<T>.GetEnumerator()
            getEnumeratorMethod = enumerableInterface.GetMethod("GetEnumerator");
            enumeratorType = typeof(System.Collections.Generic.IEnumerator<>).MakeGenericType(elementType);
        }
        else
        {
            // Fall back to non-generic IEnumerable
            getEnumeratorMethod = typeof(System.Collections.IEnumerable).GetMethod("GetEnumerator");
            enumeratorType = typeof(System.Collections.IEnumerator);
        }

        if (getEnumeratorMethod == null)
        {
            throw new InvalidOperationException($"Cannot find GetEnumerator method for type {collectionType}");
        }

        // Store the collection in a local temporarily (already on stack)
        // Call GetEnumerator on the collection
        _currentIL.Emit(OpCodes.Callvirt, getEnumeratorMethod);

        // Store the enumerator in a local variable
        var enumeratorLocal = _currentIL.DeclareLocal(enumeratorType);
        _currentIL.Emit(OpCodes.Stloc, enumeratorLocal);

        var moveNextMethod = enumeratorType.GetMethod("MoveNext") ?? typeof(System.Collections.IEnumerator).GetMethod("MoveNext");
        if (moveNextMethod == null)
        {
            throw new InvalidOperationException("Cannot find MoveNext method");
        }

        var currentProperty = enumeratorType.GetProperty("Current");
        if (currentProperty == null)
        {
            throw new InvalidOperationException("Cannot find Current property");
        }

        var getCurrentMethod = currentProperty.GetGetMethod();
        if (getCurrentMethod == null)
        {
            throw new InvalidOperationException("Cannot find get_Current method");
        }

        var loopStart = _currentIL.DefineLabel();
        var loopBody = _currentIL.DefineLabel();
        var disposeLabel = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        _currentIL.MarkLabel(loopStart);

        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        _currentIL.Emit(OpCodes.Callvirt, moveNextMethod);
        _currentIL.Emit(OpCodes.Brtrue, loopBody);
        _currentIL.Emit(OpCodes.Br, disposeLabel);

        _currentIL.MarkLabel(loopBody);
        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        _currentIL.Emit(OpCodes.Callvirt, getCurrentMethod);

        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingLocal))
        {
            loopVar = existingLocal;
        }
        else
        {
            loopVar = DeclareNamedLocal(foreachStmt.VariableName, elementType);
        }

        if (IsLiftedIdentifier(foreachStmt.VariableName))
        {
            EmitStoreLiftedLocalValue(loopVar, elementType, leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, loopVar);
        }

        _breakLabels.Push(new BranchTarget(disposeLabel, useLeave: false));
        _continueLabels.Push(new BranchTarget(loopStart, useLeave: false));
        try
        {
            EmitStatement(foreachStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.Emit(OpCodes.Br, loopStart);

        _currentIL.MarkLabel(disposeLabel);
        if (typeof(IDisposable).IsAssignableFrom(enumeratorType))
        {
            _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
            var disposeMethod = typeof(IDisposable).GetMethod("Dispose");
            if (disposeMethod != null)
            {
                _currentIL.Emit(OpCodes.Callvirt, disposeMethod);
            }
        }

        _currentIL.MarkLabel(loopEnd);
    }

    private void EmitAwaitForeach(AwaitForEachStatement awaitForeachStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        var collectionType = GetExpressionType(awaitForeachStmt.Collection);
        var asyncEnumerableInterface = collectionType.IsGenericType && collectionType.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>)
            ? collectionType
            : collectionType.GetInterfaces().FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>));
        if (asyncEnumerableInterface == null)
        {
            throw new InvalidOperationException($"Type {collectionType} is not an async enumerable");
        }

        var elementType = asyncEnumerableInterface.GetGenericArguments()[0];
        var getAsyncEnumeratorMethod = asyncEnumerableInterface.GetMethod("GetAsyncEnumerator", new[] { typeof(System.Threading.CancellationToken) })
            ?? asyncEnumerableInterface.GetMethod("GetAsyncEnumerator", Type.EmptyTypes)
            ?? collectionType.GetMethod("GetAsyncEnumerator", new[] { typeof(System.Threading.CancellationToken) })
            ?? collectionType.GetMethod("GetAsyncEnumerator", Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Cannot resolve GetAsyncEnumerator for {collectionType}");

        EmitExpression(awaitForeachStmt.Collection);
        if (getAsyncEnumeratorMethod.GetParameters().Length == 1)
        {
            EmitDefaultValue(typeof(System.Threading.CancellationToken));
        }

        _currentIL.Emit(getAsyncEnumeratorMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getAsyncEnumeratorMethod);

        var enumeratorType = getAsyncEnumeratorMethod.ReturnType;
        var enumeratorLocal = _currentIL.DeclareLocal(enumeratorType);
        _currentIL.Emit(OpCodes.Stloc, enumeratorLocal);

        var loopStart = _currentIL.DefineLabel();
        var loopBody = _currentIL.DefineLabel();
        var disposeLabel = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        var moveNextAsyncMethod = enumeratorType.GetMethod("MoveNextAsync")
            ?? throw new InvalidOperationException($"Cannot resolve MoveNextAsync for {enumeratorType}");
        var currentProperty = enumeratorType.GetProperty("Current")
            ?? throw new InvalidOperationException($"Cannot resolve Current for {enumeratorType}");
        var getCurrentMethod = currentProperty.GetGetMethod()
            ?? throw new InvalidOperationException($"Cannot resolve get_Current for {enumeratorType}");
        var disposeAsyncMethod = enumeratorType.GetMethod("DisposeAsync");

        _currentIL.MarkLabel(loopStart);

        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        _currentIL.Emit(moveNextAsyncMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, moveNextAsyncMethod);
        EmitAwaiterGetResult(moveNextAsyncMethod.ReturnType);
        _currentIL.Emit(OpCodes.Brtrue, loopBody);
        _currentIL.Emit(OpCodes.Br, disposeLabel);

        _currentIL.MarkLabel(loopBody);
        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        _currentIL.Emit(getCurrentMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getCurrentMethod);

        LocalBuilder loopVar;
        if (_locals.TryGetValue(awaitForeachStmt.VariableName, out var existingLocal))
        {
            loopVar = existingLocal;
        }
        else
        {
            loopVar = DeclareNamedLocal(awaitForeachStmt.VariableName, elementType);
        }

        if (IsLiftedIdentifier(awaitForeachStmt.VariableName))
        {
            EmitStoreLiftedLocalValue(loopVar, elementType, leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, loopVar);
        }

        _breakLabels.Push(new BranchTarget(disposeLabel, useLeave: false));
        _continueLabels.Push(new BranchTarget(loopStart, useLeave: false));
        try
        {
            EmitStatement(awaitForeachStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.Emit(OpCodes.Br, loopStart);

        _currentIL.MarkLabel(disposeLabel);
        if (disposeAsyncMethod != null)
        {
            _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
            _currentIL.Emit(disposeAsyncMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, disposeAsyncMethod);
            EmitAwaiterGetResult(disposeAsyncMethod.ReturnType);
        }

        _currentIL.MarkLabel(loopEnd);
    }

    private void EmitYield(YieldStatement yieldStmt)
    {
        if (_currentIL == null || _currentYieldListLocal == null || _currentYieldBreakLabel == null || _currentYieldElementType == null)
        {
            throw new InvalidOperationException("yield used outside of a generator context");
        }

        if (yieldStmt.Value == null)
        {
            _currentIL.Emit(OpCodes.Br, _currentYieldBreakLabel.Value);
            return;
        }

        var listType = _currentYieldListLocal.LocalType;
        var addMethod = listType.GetMethod("Add", new[] { _currentYieldElementType })
            ?? throw new InvalidOperationException($"Could not resolve Add({_currentYieldElementType}) on {listType}");

        _currentIL.Emit(OpCodes.Ldloc, _currentYieldListLocal);
        EmitExpressionWithExpectedType(yieldStmt.Value, _currentYieldElementType);
        _currentIL.Emit(OpCodes.Callvirt, addMethod);
    }

    /// <summary>
    /// Emit IL for foreach over an array (using index-based iteration)
    /// </summary>
    private void EmitForeachForArray(ForeachStatement foreachStmt, Type arrayType, Type elementType)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Store the array in a local
        var arrayLocal = _currentIL.DeclareLocal(arrayType);
        _currentIL.Emit(OpCodes.Stloc, arrayLocal);

        // Create index variable (int)
        var indexLocal = _currentIL.DeclareLocal(typeof(int));

        // Initialize index to 0
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // Define labels
        var loopStart = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        // Mark loop start
        _currentIL.MarkLabel(loopStart);

        // Check if index < array.Length
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldlen);
        _currentIL.Emit(OpCodes.Conv_I4);
        _currentIL.Emit(OpCodes.Bge, loopEnd);  // Branch if index >= length

        // Load array element: array[index]
        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);

        // Use appropriate array element load instruction
        if (elementType == typeof(int))
            _currentIL.Emit(OpCodes.Ldelem_I4);
        else if (elementType == typeof(long))
            _currentIL.Emit(OpCodes.Ldelem_I8);
        else if (elementType == typeof(bool) || elementType == typeof(byte))
            _currentIL.Emit(OpCodes.Ldelem_U1);
        else if (elementType == typeof(double))
            _currentIL.Emit(OpCodes.Ldelem_R8);
        else if (elementType == typeof(float))
            _currentIL.Emit(OpCodes.Ldelem_R4);
        else if (elementType.IsGenericParameter || elementType.ContainsGenericParameters)
            _currentIL.Emit(OpCodes.Ldelem, elementType);
        else if (elementType.IsValueType)
            _currentIL.Emit(OpCodes.Ldelem, elementType);
        else
            _currentIL.Emit(OpCodes.Ldelem_Ref);

        // Declare loop variable and store element
        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingLocal))
        {
            loopVar = existingLocal;
        }
        else
        {
            loopVar = DeclareNamedLocal(foreachStmt.VariableName, elementType);
        }
        if (IsLiftedIdentifier(foreachStmt.VariableName))
        {
            EmitStoreLiftedLocalValue(loopVar, elementType, leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, loopVar);
        }

        // Emit loop body
        EmitStatement(foreachStmt.Body);

        // Increment index
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // Jump back to loop start
        _currentIL.Emit(OpCodes.Br, loopStart);

        // Mark loop end
        _currentIL.MarkLabel(loopEnd);
    }

    /// <summary>
    /// Emit IL for a try/catch/finally statement
    /// </summary>
    private void EmitTry(TryStatement tryStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Begin exception block
        _currentIL.BeginExceptionBlock();

        // Emit the try block
        EmitStatement(tryStmt.TryBlock);

        // Emit catch clauses
        foreach (var catchClause in tryStmt.CatchClauses)
        {
            // Determine exception type
            Type exceptionType = typeof(Exception);
            if (catchClause.ExceptionType != null)
            {
                exceptionType = ResolveType(catchClause.ExceptionType, _currentGenericParameters);
            }

            // Begin catch block
            _currentIL.BeginCatchBlock(exceptionType);

            // If there's a variable name, store the exception in a local
            if (catchClause.VariableName != null)
            {
                LocalBuilder exceptionLocal;
                if (_locals.TryGetValue(catchClause.VariableName, out var existingLocal))
                {
                    exceptionLocal = existingLocal;
                }
                else
                {
                    exceptionLocal = DeclareNamedLocal(catchClause.VariableName, exceptionType);
                }
                if (IsLiftedIdentifier(catchClause.VariableName))
                {
                    EmitStoreLiftedLocalValue(exceptionLocal, exceptionType, leaveValueOnStack: false);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Stloc, exceptionLocal);
                }
            }
            else
            {
                // If no variable name, pop the exception from the stack
                _currentIL.Emit(OpCodes.Pop);
            }

            // Emit the catch block
            EmitStatement(catchClause.Block);
        }

        // Emit finally block if present
        if (tryStmt.FinallyBlock != null)
        {
            _currentIL.BeginFinallyBlock();
            EmitStatement(tryStmt.FinallyBlock);
        }

        // End exception block
        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for a using statement
    /// </summary>
    private void EmitUsing(UsingStatement usingStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        LocalBuilder? resourceLocal = null;

        // Handle using with declaration: using (var x = expr) { ... }
        if (usingStmt.Declaration != null)
        {
            // Emit the variable declaration
            EmitVariableDeclaration(usingStmt.Declaration);
            resourceLocal = _locals[usingStmt.Declaration.Name];
        }
        // Handle using with expression: using (expr) { ... }
        else if (usingStmt.Expression != null)
        {
            // Evaluate the expression and store in a temp local
            EmitExpression(usingStmt.Expression);
            var exprType = GetExpressionType(usingStmt.Expression);
            resourceLocal = _currentIL.DeclareLocal(exprType);
            _currentIL.Emit(OpCodes.Stloc, resourceLocal);
        }

        if (resourceLocal == null)
        {
            throw new InvalidOperationException("Using statement must have either a declaration or an expression");
        }

        var resourceType = resourceLocal.LocalType;
        var resourceIsLifted = usingStmt.Declaration != null && IsLiftedIdentifier(usingStmt.Declaration.Name);
        if (resourceIsLifted)
        {
            resourceType = GetStrongBoxValueType(resourceType);
        }

        // Begin try-finally block
        _currentIL.BeginExceptionBlock();

        // Emit the body
        if (usingStmt.Body != null)
        {
            EmitStatement(usingStmt.Body);
        }

        // Emit finally block to dispose the resource
        _currentIL.BeginFinallyBlock();

        var interfaceDisposeMethod = typeof(IDisposable).GetMethod(nameof(IDisposable.Dispose))
            ?? throw new InvalidOperationException("Could not resolve IDisposable.Dispose()");
        var disposeMethod = ResolveDisposePatternMethod(resourceType);

        if (disposeMethod != null || typeof(IDisposable).IsAssignableFrom(resourceType))
        {
            if (resourceType.IsValueType)
            {
                if (disposeMethod != null)
                {
                    if (resourceIsLifted)
                    {
                        EmitLoadLiftedLocalAddress(resourceLocal);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldloca_S, resourceLocal);
                    }

                    _currentIL.Emit(OpCodes.Call, disposeMethod);
                }
                else
                {
                    if (resourceIsLifted)
                    {
                        EmitLoadLiftedLocalAddress(resourceLocal);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldloca_S, resourceLocal);
                    }

                    _currentIL.Emit(OpCodes.Constrained, resourceType);
                    _currentIL.Emit(OpCodes.Callvirt, interfaceDisposeMethod);
                }
            }
            else
            {
                var endLabel = _currentIL.DefineLabel();
                if (resourceIsLifted)
                {
                    EmitLoadLiftedLocalValue(resourceLocal);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloc, resourceLocal);
                }

                _currentIL.Emit(OpCodes.Brfalse_S, endLabel);

                if (resourceIsLifted)
                {
                    EmitLoadLiftedLocalValue(resourceLocal);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloc, resourceLocal);
                }

                if (disposeMethod != null)
                {
                    _currentIL.Emit(OpCodes.Callvirt, disposeMethod);
                }
                else
                {
                    if (resourceType != typeof(IDisposable))
                    {
                        _currentIL.Emit(OpCodes.Castclass, typeof(IDisposable));
                    }

                    _currentIL.Emit(OpCodes.Callvirt, interfaceDisposeMethod);
                }
                _currentIL.MarkLabel(endLabel);
            }
        }
        else
        {
            throw new InvalidOperationException($"Using target of type {resourceLocal.LocalType} does not have an accessible Dispose method");
        }

        // End exception block
        _currentIL.EndExceptionBlock();
    }

    private MethodInfo? ResolveDisposePatternMethod(Type type)
    {
        if (TryGetUserTypeDefinition(type, out var typeBuilder))
        {
            var disposeMethod = type == typeBuilder
                ? _methods.GetValueOrDefault(GetMethodKey(typeBuilder, nameof(IDisposable.Dispose)))
                : ResolveUserDefinedMethod(type, nameof(IDisposable.Dispose));
            if (disposeMethod != null
                && !disposeMethod.IsStatic
                && disposeMethod.GetParameters().Length == 0)
            {
                return disposeMethod;
            }

            return null;
        }

        try
        {
            return type.GetMethod(
                nameof(IDisposable.Dispose),
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    /// <summary>
    /// Emit IL for an expression
    /// </summary>
    private void EmitExpression(Expression expression)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (expression)
        {
            case IntLiteralExpression intLit:
                EmitIntLiteral(intLit);
                break;

            case FloatLiteralExpression floatLit:
                EmitFloatLiteral(floatLit);
                break;

            case StringLiteralExpression strLit:
                EmitStringLiteral(strLit);
                break;

            case InterpolatedStringExpression interpolated:
                // For IL compilation, emit interpolated strings using string.Format or string.Concat
                // For now, concatenate the parts as a simple approach
                EmitInterpolatedString(interpolated);
                break;

            case BoolLiteralExpression boolLit:
                _currentIL.Emit(boolLit.Value ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
                break;

            case NullLiteralExpression:
                _currentIL.Emit(OpCodes.Ldnull);
                break;

            case IdentifierExpression ident:
                EmitIdentifier(ident);
                break;

            case RangeExpression range:
                EmitRangeExpression(range);
                break;

            case UnaryExpression unary:
                EmitUnaryExpression(unary);
                break;

            case BinaryExpression binary:
                EmitBinaryExpression(binary);
                break;

            case CallExpression call:
                EmitCall(call);
                break;

            case AssignmentExpression assignment:
                EmitAssignment(assignment);
                break;

            case TupleExpression tuple:
                EmitTupleExpression(tuple);
                break;

            case NewExpression newExpr:
                EmitNewObject(newExpr);
                break;

            case WithExpression withExpr:
                EmitWithExpression(withExpr);
                break;

            case AwaitExpression awaitExpr:
                EmitAwaitExpression(awaitExpr);
                break;

            case MemberAccessExpression memberAccess:
                EmitMemberAccess(memberAccess);
                break;

            case IndexAccessExpression indexAccess:
                EmitIndexAccess(indexAccess);
                break;

            case TernaryExpression ternary:
                EmitTernaryExpression(ternary);
                break;

            case ArrayLiteralExpression arrayLiteral:
                EmitArrayLiteral(arrayLiteral);
                break;

            case CastExpression cast:
                EmitCastExpression(cast);
                break;

            case IsExpression isExpr:
                EmitIsExpression(isExpr);
                break;

            case ThisExpression:
                // 'this' is always at argument 0 for instance methods and constructors
                _currentIL.Emit(OpCodes.Ldarg_0);
                break;

            case BaseExpression:
                _currentIL.Emit(OpCodes.Ldarg_0);
                break;

            case ThrowExpression throwExpr:
                EmitExpression(throwExpr.Expression);
                _currentIL.Emit(OpCodes.Throw);
                break;

            case TypeOfExpression typeOfExpr:
                EmitTypeOfExpression(typeOfExpr);
                break;

            case NameofExpression nameofExpr:
                EmitNameofExpression(nameofExpr);
                break;

            case SizeOfExpression sizeofExpr:
                EmitSizeOfExpression(sizeofExpr);
                break;

            case SpreadExpression spread:
                EmitExpression(spread.Expression);
                break;

            case DefaultExpression:
                EmitDefaultValue(_expectedExpressionType ?? typeof(object));
                break;

            case CheckedExpression checkedExpr:
                EmitWithOverflowChecking(enabled: true, () => EmitExpression(checkedExpr.Expression));
                break;

            case UncheckedExpression uncheckedExpr:
                EmitWithOverflowChecking(enabled: false, () => EmitExpression(uncheckedExpr.Expression));
                break;

            case MatchExpression match:
                EmitMatchExpression(match);
                break;

            case LambdaExpression lambda:
                EmitLambda(lambda);
                break;

            case ParenthesizedExpression paren:
                EmitExpression(paren.Inner);
                break;

            default:
                throw new NotImplementedException($"Expression type {expression.GetType().Name} not yet implemented in IL compiler");
        }
    }

    private void EmitAwaitExpression(AwaitExpression awaitExpr)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        EmitExpression(awaitExpr.Expression);
        EmitAwaiterGetResult(GetExpressionType(awaitExpr.Expression));
    }

    /// <summary>
    /// Emit IL for an integer literal
    /// </summary>
    private void EmitIntLiteral(IntLiteralExpression intLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var value = ParseIntLiteralValue(intLit.Value);

        // Use optimized opcodes for small values
        switch (value)
        {
            case -1: _currentIL.Emit(OpCodes.Ldc_I4_M1); break;
            case 0: _currentIL.Emit(OpCodes.Ldc_I4_0); break;
            case 1: _currentIL.Emit(OpCodes.Ldc_I4_1); break;
            case 2: _currentIL.Emit(OpCodes.Ldc_I4_2); break;
            case 3: _currentIL.Emit(OpCodes.Ldc_I4_3); break;
            case 4: _currentIL.Emit(OpCodes.Ldc_I4_4); break;
            case 5: _currentIL.Emit(OpCodes.Ldc_I4_5); break;
            case 6: _currentIL.Emit(OpCodes.Ldc_I4_6); break;
            case 7: _currentIL.Emit(OpCodes.Ldc_I4_7); break;
            case 8: _currentIL.Emit(OpCodes.Ldc_I4_8); break;
            default:
                if (value >= sbyte.MinValue && value <= sbyte.MaxValue)
                {
                    _currentIL.Emit(OpCodes.Ldc_I4_S, (sbyte)value);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldc_I4, value);
                }
                break;
        }
    }

    /// <summary>
    /// Emit IL for a float literal
    /// </summary>
    private void EmitFloatLiteral(FloatLiteralExpression floatLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var value = ParseFloatLiteralValue(floatLit.Value);
        _currentIL.Emit(OpCodes.Ldc_R8, value);
    }

    private static double ParseFloatLiteralValue(string text)
    {
        var span = text.AsSpan().Trim();
        while (span.Length > 0 && (span[^1] is 'f' or 'F' or 'd' or 'D' or 'm' or 'M'))
        {
            span = span[..^1];
        }

        var clean = span.ToString().Replace("_", "");
        return double.Parse(clean, System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// Parse an integer literal value, handling hex (0x), binary (0b), octal (0o),
    /// underscore separators, and integer suffixes (u, l, ul, etc.)
    /// </summary>
    private static int ParseIntLiteralValue(string text)
    {
        // Strip trailing suffixes (u, l, ul, lu, etc.)
        var span = text.AsSpan();
        while (span.Length > 0 && (span[^1] == 'u' || span[^1] == 'U' || span[^1] == 'l' || span[^1] == 'L'))
        {
            span = span[..^1];
        }

        // Remove underscore separators
        var clean = span.ToString().Replace("_", "");

        if (clean.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return int.Parse(clean[2..], System.Globalization.NumberStyles.HexNumber);
        if (clean.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
            return Convert.ToInt32(clean[2..], 2);
        if (clean.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
            return Convert.ToInt32(clean[2..], 8);

        return int.Parse(clean);
    }

    /// <summary>
    /// Emit IL for a string literal
    /// </summary>
    private void EmitStringLiteral(StringLiteralExpression strLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Remove quotes from string value
        var value = strLit.Value.Trim('"');
        _currentIL.Emit(OpCodes.Ldstr, value);
    }

    private void EmitDefaultValue(Type targetType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (!targetType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Ldnull);
            return;
        }

        var local = _currentIL.DeclareLocal(targetType);
        _currentIL.Emit(OpCodes.Ldloca_S, local);
        _currentIL.Emit(OpCodes.Initobj, targetType);
        _currentIL.Emit(OpCodes.Ldloc, local);
    }

    /// <summary>
    /// Emit IL for an interpolated string using string.Concat
    /// </summary>
    private void EmitInterpolatedString(InterpolatedStringExpression interpolated)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Simple approach: convert each part to a string and concatenate
        var parts = new List<InterpolatedStringPart>(interpolated.Parts);
        if (parts.Count == 0)
        {
            _currentIL.Emit(OpCodes.Ldstr, "");
            return;
        }

        // Emit each part
        foreach (var part in parts)
        {
            switch (part)
            {
                case InterpolatedStringText text:
                    _currentIL.Emit(OpCodes.Ldstr, text.Text);
                    break;
                case InterpolatedStringHole hole:
                    EmitExpression(hole.Expression);
                    // Convert to string if not already
                    var exprType = GetExpressionType(hole.Expression);
                    if (exprType != typeof(string))
                    {
                        if (exprType.IsValueType)
                        {
                            _currentIL.Emit(OpCodes.Box, exprType);
                        }
                        var toStringMethod = typeof(object).GetMethod("ToString", Type.EmptyTypes)!;
                        _currentIL.Emit(OpCodes.Callvirt, toStringMethod);
                    }
                    break;
            }
        }

        // Concatenate all parts
        if (parts.Count > 1)
        {
            var concatMethod = typeof(string).GetMethod("Concat", new[] { typeof(string), typeof(string) })!;
            for (int i = 1; i < parts.Count; i++)
            {
                _currentIL.Emit(OpCodes.Call, concatMethod);
            }
        }
    }

    /// <summary>
    /// Emit IL for an identifier (variable or parameter)
    /// </summary>
    private void EmitIdentifier(IdentifierExpression ident)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        // Check if it's a local variable
        if (_locals.TryGetValue(ident.Name, out var local))
        {
            if (IsLiftedIdentifier(ident.Name))
            {
                EmitLoadLiftedLocalValue(local);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, local);
            }
        }
        // Check if it's a parameter
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            EmitLoadArgument(paramIndex);

            if (_byRefParameters != null && _byRefParameters.Contains(ident.Name))
            {
                EmitLoadIndirect(GetIdentifierType(ident));
            }
        }
        // Check if it's a closure field
        else if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField))
        {
            if (IsLiftedClosureField(ident.Name))
            {
                EmitLoadLiftedClosureFieldValue(closureField);
            }
            else
            {
                // Load 'this' (closure instance at arg 0)
                _currentIL.Emit(OpCodes.Ldarg_0);
                // Load the field
                _currentIL.Emit(OpCodes.Ldfld, closureField);
            }
        }
        // Check if it's an instance field (in current class or base classes)
        else if (_currentTypeBuilder != null)
        {
            var primaryConstructorField = FindPrimaryConstructorField(_currentTypeBuilder, ident.Name);
            if (primaryConstructorField != null)
            {
                _currentIL.Emit(OpCodes.Ldarg_0);
                _currentIL.Emit(OpCodes.Ldfld, primaryConstructorField);
                return;
            }

            var fieldInfo = FindField(_currentTypeBuilder, ident.Name);
            if (fieldInfo != null)
            {
                // Load 'this' pointer
                _currentIL.Emit(OpCodes.Ldarg_0);
                // Load the field
                _currentIL.Emit(OpCodes.Ldfld, fieldInfo);
            }
            else
            {
                throw new InvalidOperationException($"Undefined variable, parameter, or field: {ident.Name}");
            }
        }
        else
        {
            throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
        }
    }

    /// <summary>
    /// Find a field in the current type or its base types
    /// </summary>
    private FieldInfo? FindField(TypeBuilder typeBuilder, string fieldName)
    {
        // Check in declared fields of current type
        var fieldKey = GetFieldKey(typeBuilder, fieldName);
        if (_fields.TryGetValue(fieldKey, out var fieldBuilder))
        {
            return fieldBuilder;
        }

        // Check in base type
        var baseType = typeBuilder.BaseType;
        if (baseType != null && baseType != typeof(object))
        {
            // If base type is also a TypeBuilder in our compilation unit, check our fields dictionary
            if (baseType is TypeBuilder baseTypeBuilder)
            {
                var baseFieldKey = GetFieldKey(baseTypeBuilder, fieldName);
                if (_fields.TryGetValue(baseFieldKey, out var baseFieldBuilder))
                {
                    return baseFieldBuilder;
                }
            }
            else
            {
                // External type - use reflection
                var field = baseType.GetField(fieldName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                if (field != null)
                {
                    return field;
                }
            }
        }

        return null;
    }

    private FieldBuilder? FindPrimaryConstructorField(Type type, string parameterName)
    {
        var key = GetPrimaryConstructorFieldKey(type, parameterName);
        return _primaryConstructorFields.TryGetValue(key, out var field) ? field : null;
    }

    /// <summary>
    /// Emit IL for a unary expression
    /// </summary>
    private void EmitUnaryExpression(UnaryExpression unary)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        if (unary.Operator is UnaryOperator.Negate or UnaryOperator.Not or UnaryOperator.BitwiseNot
            && TryEmitUnaryOperator(unary))
        {
            return;
        }

        switch (unary.Operator)
        {
            case UnaryOperator.Negate:
                var operandType = NormalizeOverflowCheckedType(GetExpressionType(unary.Operand));
                if (_overflowCheckingEnabled && operandType == typeof(int))
                {
                    _currentIL.Emit(OpCodes.Ldc_I4_0);
                    EmitExpression(unary.Operand);
                    _currentIL.Emit(OpCodes.Sub_Ovf);
                    return;
                }

                if (_overflowCheckingEnabled && operandType == typeof(long))
                {
                    _currentIL.Emit(OpCodes.Ldc_I8, 0L);
                    EmitExpression(unary.Operand);
                    _currentIL.Emit(OpCodes.Sub_Ovf);
                    return;
                }

                EmitExpression(unary.Operand);
                _currentIL.Emit(OpCodes.Neg);
                return;

            case UnaryOperator.Not:
                EmitExpression(unary.Operand);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                return;

            case UnaryOperator.BitwiseNot:
                EmitExpression(unary.Operand);
                _currentIL.Emit(OpCodes.Not);
                return;

            case UnaryOperator.PreIncrement:
            case UnaryOperator.PreDecrement:
            case UnaryOperator.PostIncrement:
            case UnaryOperator.PostDecrement:
                EmitIncrementOrDecrement(unary);
                return;

            case UnaryOperator.IndexFromEnd:
                EmitSystemIndex(unary);
                return;

            default:
                throw new NotImplementedException($"Unary operator {unary.Operator} not yet implemented in IL compiler");
        }
    }

    private void EmitIncrementOrDecrement(UnaryExpression unary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var delta = unary.Operator is UnaryOperator.PreIncrement or UnaryOperator.PostIncrement ? 1 : -1;
        var isPost = unary.Operator is UnaryOperator.PostIncrement or UnaryOperator.PostDecrement;

        if (unary.Operand is IdentifierExpression ident)
        {
            EmitIdentifier(ident);
            if (isPost)
            {
                var originalLocal = _currentIL.DeclareLocal(GetIdentifierType(ident));
                _currentIL.Emit(OpCodes.Dup);
                _currentIL.Emit(OpCodes.Stloc, originalLocal);
                EmitIncrementDelta(delta, GetIdentifierType(ident));
                StoreIdentifier(ident);
                _currentIL.Emit(OpCodes.Ldloc, originalLocal);
            }
            else
            {
                EmitIncrementDelta(delta, GetIdentifierType(ident));
                StoreIdentifier(ident);
                EmitIdentifier(ident);
            }
            return;
        }

        if (unary.Operand is MemberAccessExpression memberAccess)
        {
            EmitMemberIncrementOrDecrement(memberAccess, delta, isPost);
            return;
        }

        if (unary.Operand is IndexAccessExpression indexAccess)
        {
            EmitIndexIncrementOrDecrement(indexAccess, delta, isPost);
            return;
        }

        throw new NotImplementedException($"Unary operator {unary.Operator} requires an assignable target");
    }

    private void EmitIncrementDelta(int delta, Type operandType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        operandType = NormalizeOverflowCheckedType(operandType);

        if (operandType == typeof(long) || operandType == typeof(ulong))
        {
            _currentIL.Emit(OpCodes.Ldc_I8, 1L);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldc_I4_1);
        }

        if (_overflowCheckingEnabled && IsOverflowCheckedIntegralType(operandType))
        {
            var isUnsigned = IsUnsignedOverflowCheckedType(operandType);
            _currentIL.Emit(delta >= 0
                ? (isUnsigned ? OpCodes.Add_Ovf_Un : OpCodes.Add_Ovf)
                : (isUnsigned ? OpCodes.Sub_Ovf_Un : OpCodes.Sub_Ovf));
            return;
        }

        _currentIL.Emit(delta >= 0 ? OpCodes.Add : OpCodes.Sub);
    }

    private void StoreIdentifier(IdentifierExpression ident)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        if (_locals.TryGetValue(ident.Name, out var local))
        {
            if (IsLiftedIdentifier(ident.Name))
            {
                EmitStoreLiftedLocalValue(local, GetIdentifierType(ident), leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, local);
            }
            return;
        }

        if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            if (paramIndex <= 255)
            {
                _currentIL.Emit(OpCodes.Starg_S, (byte)paramIndex);
            }
            else
            {
                _currentIL.Emit(OpCodes.Starg, paramIndex);
            }
            return;
        }

        if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField) && IsLiftedClosureField(ident.Name))
        {
            EmitStoreLiftedClosureFieldValue(closureField, GetIdentifierType(ident), leaveValueOnStack: false);
            return;
        }

        throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
    }

    private void EmitMemberIncrementOrDecrement(MemberAccessExpression memberAccess, int delta, bool isPost)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        EmitExpression(memberAccess.Object);
        _currentIL.Emit(OpCodes.Dup);

        var objectType = GetExpressionType(memberAccess.Object);
        EmitMemberLoadValue(objectType, memberAccess.MemberName);

        LocalBuilder? originalLocal = null;
        if (isPost)
        {
            originalLocal = _currentIL.DeclareLocal(GetMemberAccessType(memberAccess));
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Stloc, originalLocal);
        }

        EmitIncrementDelta(delta, GetMemberAccessType(memberAccess));
        EmitMemberStoreValue(objectType, memberAccess.MemberName);

        if (isPost)
        {
            _currentIL.Emit(OpCodes.Ldloc, originalLocal!);
        }
        else
        {
            EmitMemberAccess(memberAccess);
        }
    }

    private void EmitIndexIncrementOrDecrement(IndexAccessExpression indexAccess, int delta, bool isPost)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var objectType = GetExpressionType(indexAccess.Object);
        var indexType = GetExpressionType(indexAccess.Index);

        EmitExpression(indexAccess.Object);
        var objectLocal = _currentIL.DeclareLocal(objectType);
        _currentIL.Emit(OpCodes.Stloc, objectLocal);

        EmitExpression(indexAccess.Index);
        var indexLocal = _currentIL.DeclareLocal(indexType);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.Emit(OpCodes.Ldloc, objectLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        EmitIndexLoadValue(indexAccess, objectType);

        LocalBuilder? originalLocal = null;
        if (isPost)
        {
            originalLocal = _currentIL.DeclareLocal(GetIndexAccessType(indexAccess));
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Stloc, originalLocal);
        }

        EmitIncrementDelta(delta, GetIndexAccessType(indexAccess));
        var updatedLocal = _currentIL.DeclareLocal(GetIndexAccessType(indexAccess));
        _currentIL.Emit(OpCodes.Stloc, updatedLocal);
        _currentIL.Emit(OpCodes.Ldloc, objectLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, updatedLocal);
        EmitIndexStoreValue(indexAccess, objectType);

        if (isPost)
        {
            _currentIL.Emit(OpCodes.Ldloc, originalLocal!);
        }
        else
        {
            EmitIndexAccess(indexAccess);
        }
    }

    /// <summary>
    /// Emit IL for a binary expression
    /// </summary>
    private void EmitBinaryExpression(BinaryExpression binary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (binary.Operator == BinaryOperator.NullCoalesce)
        {
            EmitNullCoalesce(binary);
            return;
        }

        if (binary.Operator == BinaryOperator.Add &&
            (GetExpressionType(binary.Left) == typeof(string) || GetExpressionType(binary.Right) == typeof(string)))
        {
            EmitStringConcatenation(binary);
            return;
        }

        if (TryEmitCheckedBinaryOperator(binary))
        {
            return;
        }

        if (TryEmitBinaryOperator(binary))
        {
            return;
        }

        // Emit left and right operands
        EmitExpression(binary.Left);
        EmitExpression(binary.Right);

        // Emit operator
        switch (binary.Operator)
        {
            case BinaryOperator.Add:
                _currentIL.Emit(OpCodes.Add);
                break;
            case BinaryOperator.Subtract:
                _currentIL.Emit(OpCodes.Sub);
                break;
            case BinaryOperator.Multiply:
                _currentIL.Emit(OpCodes.Mul);
                break;
            case BinaryOperator.Divide:
                _currentIL.Emit(OpCodes.Div);
                break;
            case BinaryOperator.Modulo:
                _currentIL.Emit(OpCodes.Rem);
                break;
            case BinaryOperator.Equal:
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.NotEqual:
                _currentIL.Emit(OpCodes.Ceq);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.Less:
                _currentIL.Emit(OpCodes.Clt);
                break;
            case BinaryOperator.Greater:
                _currentIL.Emit(OpCodes.Cgt);
                break;
            case BinaryOperator.LessOrEqual:
                _currentIL.Emit(OpCodes.Cgt);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.GreaterOrEqual:
                _currentIL.Emit(OpCodes.Clt);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.And:
                _currentIL.Emit(OpCodes.And);
                break;
            case BinaryOperator.Or:
                _currentIL.Emit(OpCodes.Or);
                break;
            case BinaryOperator.BitwiseAnd:
                _currentIL.Emit(OpCodes.And);
                break;
            case BinaryOperator.BitwiseOr:
                _currentIL.Emit(OpCodes.Or);
                break;
            case BinaryOperator.BitwiseXor:
                _currentIL.Emit(OpCodes.Xor);
                break;
            case BinaryOperator.LeftShift:
                _currentIL.Emit(OpCodes.Shl);
                break;
            case BinaryOperator.RightShift:
                _currentIL.Emit(OpCodes.Shr);
                break;
            default:
                throw new NotImplementedException($"Binary operator {binary.Operator} not yet implemented in IL compiler");
        }
    }

    private void EmitStringConcatenation(BinaryExpression binary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var leftType = GetExpressionType(binary.Left);
        var rightType = GetExpressionType(binary.Right);
        var concatMethod = typeof(string).GetMethod(
            nameof(string.Concat),
            new[] { typeof(object), typeof(object) });
        if (concatMethod == null)
        {
            throw new InvalidOperationException("Could not resolve string.Concat(object, object)");
        }

        EmitExpression(binary.Left);
        if (leftType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Box, leftType);
        }

        EmitExpression(binary.Right);
        if (rightType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Box, rightType);
        }

        _currentIL.Emit(OpCodes.Call, concatMethod);
    }

    private void EmitNullCoalesce(BinaryExpression binary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var leftType = GetExpressionType(binary.Left);
        if (leftType.IsValueType && Nullable.GetUnderlyingType(leftType) == null)
        {
            EmitExpression(binary.Left);
            return;
        }

        EmitExpression(binary.Left);
        var leftLocal = _currentIL.DeclareLocal(leftType);
        _currentIL.Emit(OpCodes.Stloc, leftLocal);

        var useLeftLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        _currentIL.Emit(OpCodes.Ldloc, leftLocal);
        if (Nullable.GetUnderlyingType(leftType) != null)
        {
            var hasValueGetter = leftType.GetProperty(nameof(Nullable<int>.HasValue))?.GetGetMethod();
            var getValueOrDefault = leftType.GetMethod(nameof(Nullable<int>.GetValueOrDefault), Type.EmptyTypes);
            if (hasValueGetter == null || getValueOrDefault == null)
            {
                throw new InvalidOperationException($"Could not resolve nullable helpers for {leftType}");
            }

            _currentIL.Emit(OpCodes.Pop);
            _currentIL.Emit(OpCodes.Ldloca_S, leftLocal);
            _currentIL.Emit(OpCodes.Call, hasValueGetter);
            _currentIL.Emit(OpCodes.Brtrue, useLeftLabel);
            EmitExpression(binary.Right);
            _currentIL.Emit(OpCodes.Br, endLabel);

            _currentIL.MarkLabel(useLeftLabel);
            _currentIL.Emit(OpCodes.Ldloca_S, leftLocal);
            _currentIL.Emit(OpCodes.Call, getValueOrDefault);
            _currentIL.MarkLabel(endLabel);
            return;
        }

        _currentIL.Emit(OpCodes.Brtrue, useLeftLabel);
        EmitExpression(binary.Right);
        _currentIL.Emit(OpCodes.Br, endLabel);

        _currentIL.MarkLabel(useLeftLabel);
        _currentIL.Emit(OpCodes.Ldloc, leftLocal);
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for a function call
    /// </summary>
    private void EmitCall(CallExpression call)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var calleeType = GetExpressionType(call.Callee);
        if (call.Callee is not MemberAccessExpression &&
            TryGetDelegateInvokeMethod(calleeType, out var delegateInvokeMethod) &&
            delegateInvokeMethod != null)
        {
            if (call.Callee is IdentifierExpression localFunctionIdent
                && _localFunctionDeclarations != null
                && _localFunctionDeclarations.TryGetValue(localFunctionIdent.Name, out var localFunctionDeclaration)
                && TryBindDeclaredParameters(
                    localFunctionDeclaration.Parameters,
                    delegateInvokeMethod.GetParameters(),
                    call.Arguments,
                    out var boundLocalFunctionArguments,
                    out _,
                    out _,
                    out _))
            {
                EmitExpression(call.Callee);
                EmitBoundCallArguments(boundLocalFunctionArguments);
                _currentIL.Emit(OpCodes.Callvirt, delegateInvokeMethod);
                return;
            }

            EmitExpression(call.Callee);
            EmitCallArguments(call.Arguments, GetDelegateInvokeParameterTypes(calleeType, delegateInvokeMethod));
            _currentIL.Emit(OpCodes.Callvirt, delegateInvokeMethod);
            return;
        }

        // Handle instance method calls (obj.Method())
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
            {
                if (staticType is TypeBuilder staticTypeBuilder)
                {
                    var boundStaticCall = BindDeclaredMethodCall(
                        GetMethodKey(staticTypeBuilder, memberAccess.MemberName),
                        call,
                        targetType: staticType,
                        predicate: overload => overload.Builder.IsStatic);
                    if (boundStaticCall != null)
                    {
                        EmitBoundCallArguments(boundStaticCall.Arguments);
                        _currentIL.Emit(OpCodes.Call, boundStaticCall.Method);
                        return;
                    }

                    if (_declaredMethodOverloads.ContainsKey(GetMethodKey(staticTypeBuilder, memberAccess.MemberName)))
                    {
                        throw new InvalidOperationException($"No matching overload for static method {memberAccess.MemberName} on type {GetTypeKey(staticTypeBuilder)}");
                    }

                    if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, memberAccess.MemberName), out var staticMethodBuilder))
                    {
                        var parameterTypes = _declaredMethodParameters.TryGetValue(GetMethodKey(staticTypeBuilder, memberAccess.MemberName), out var declaredParameters)
                            ? declaredParameters.Select(p => ResolveParameterType(p)).ToArray()
                            : staticMethodBuilder.GetParameters().Select(p => p.ParameterType).ToArray();
                        EmitCallArguments(call.Arguments, parameterTypes);
                        _currentIL.Emit(OpCodes.Call, staticMethodBuilder);
                        return;
                    }
                }
                else
                {
                    var boundStaticRuntimeCall = BindRuntimeMethodCall(
                        staticType,
                        memberAccess.MemberName,
                        call,
                        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                    if (boundStaticRuntimeCall != null)
                    {
                        EmitBoundCallArguments(boundStaticRuntimeCall.Arguments);
                        _currentIL.Emit(OpCodes.Call, boundStaticRuntimeCall.Method);
                        return;
                    }
                }

                throw new InvalidOperationException($"Static method {memberAccess.MemberName} not found on type {GetTypeKey(staticType)}");
            }

            var objectType = GetExpressionType(memberAccess.Object);
            if (TryGetUserTypeDefinition(objectType, out var typeBuilder))
            {
                var boundInstanceCall = BindDeclaredMethodCall(
                    GetMethodKey(typeBuilder, memberAccess.MemberName),
                    call,
                    targetType: objectType,
                    predicate: overload => !overload.Builder.IsStatic);
                if (boundInstanceCall != null)
                {
                    var useAddressReceiverForBoundCall = IsValueTypeLike(objectType) && !objectType.IsGenericParameter;
                    if (useAddressReceiverForBoundCall)
                    {
                        EmitAddressableExpression(memberAccess.Object, objectType);
                    }
                    else
                    {
                        EmitExpression(memberAccess.Object);
                    }

                    EmitBoundCallArguments(boundInstanceCall.Arguments);
                    _currentIL.Emit(useAddressReceiverForBoundCall || !boundInstanceCall.Method.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, boundInstanceCall.Method);
                    return;
                }

                if (_declaredMethodOverloads.ContainsKey(GetMethodKey(typeBuilder, memberAccess.MemberName)))
                {
                    throw new InvalidOperationException($"No matching overload for method {memberAccess.MemberName} on type {GetTypeKey(typeBuilder)}");
                }
            }

            var useAddressReceiver = IsValueTypeLike(objectType) && !objectType.IsGenericParameter;
            var extensionCall = BindDeclaredMethodCall(
                memberAccess.MemberName,
                call,
                implicitReceiver: memberAccess.Object,
                predicate: overload => overload.Builder.IsStatic
                    && overload.Declaration.Parameters.Count > 0
                    && overload.Declaration.Parameters[0].IsThis);

            // Check if it's a user-defined type first
            var userDefinedMethod = ResolveUserDefinedMethod(objectType, memberAccess.MemberName);
            if (userDefinedMethod != null)
            {
                if (useAddressReceiver)
                {
                    EmitAddressableExpression(memberAccess.Object, objectType);
                }
                else
                {
                    EmitExpression(memberAccess.Object);
                }

                EmitCallArguments(call.Arguments, userDefinedMethod.GetParameters().Select(p => p.ParameterType).ToArray());
                _currentIL.Emit(useAddressReceiver || !userDefinedMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, userDefinedMethod);
                return;
            }

            if (extensionCall != null)
            {
                EmitBoundCallArguments(extensionCall.Arguments);
                _currentIL.Emit(OpCodes.Call, extensionCall.Method);
                return;
            }

            // Handle constrained calls on generic type parameters
            if (objectType.IsGenericParameter)
            {
                EmitAddressableExpression(memberAccess.Object, objectType);

                // For generic type parameters, we need to find the method on the constraint
                BoundRuntimeMethodCall? boundRuntimeCall = null;

                // Try to find the method on the constraints
                var constraints = objectType.GetGenericParameterConstraints();
                foreach (var constraint in constraints)
                {
                    boundRuntimeCall = BindRuntimeMethodCall(
                        constraint,
                        memberAccess.MemberName,
                        call,
                        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);

                    if (boundRuntimeCall != null)
                    {
                        break;
                    }
                }

                if (boundRuntimeCall != null)
                {
                    EmitBoundCallArguments(boundRuntimeCall.Arguments);

                    // Use constrained callvirt for generic type parameters
                    _currentIL.Emit(OpCodes.Constrained, objectType);
                    _currentIL.Emit(OpCodes.Callvirt, boundRuntimeCall.Method);
                    return;
                }

                throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on generic type parameter {objectType.Name}");
            }

            // Find the method using reflection for built-in types
            var boundRuntimeMethod = BindRuntimeMethodCall(
                objectType,
                memberAccess.MemberName,
                call,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);

            if (boundRuntimeMethod != null)
            {
                if (useAddressReceiver)
                {
                    EmitAddressableExpression(memberAccess.Object, objectType);
                }
                else
                {
                    EmitExpression(memberAccess.Object);
                }

                EmitBoundCallArguments(boundRuntimeMethod.Arguments);
                if (useAddressReceiver || !boundRuntimeMethod.Method.IsVirtual)
                {
                    _currentIL.Emit(OpCodes.Call, boundRuntimeMethod.Method);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Callvirt, boundRuntimeMethod.Method);
                }
                return;
            }

            throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on type {objectType.Name}");
        }

        // Handle special built-in functions
        if (call.Callee is IdentifierExpression ident)
        {
            var boundGenericLocalCall = BindGenericLocalFunctionCall(ident, call);
            if (boundGenericLocalCall != null)
            {
                EmitGenericLocalFunctionReceiver(boundGenericLocalCall.Method);
                EmitBoundCallArguments(boundGenericLocalCall.Arguments);
                _currentIL.Emit(OpCodes.Call, boundGenericLocalCall.Method);
                return;
            }

            if (_localFunctionDeclarations != null
                && _localFunctionDeclarations.TryGetValue(ident.Name, out var localFunctionDeclaration)
                && _genericLocalFunctionBuilders.ContainsKey(localFunctionDeclaration))
            {
                throw new InvalidOperationException($"No matching overload for local function {ident.Name}");
            }

            var boundTopLevelCall = BindDeclaredMethodCall(
                ident.Name,
                call,
                predicate: overload => overload.Builder.IsStatic);
            if (boundTopLevelCall != null)
            {
                EmitBoundCallArguments(boundTopLevelCall.Arguments);
                _currentIL.Emit(OpCodes.Call, boundTopLevelCall.Method);
                return;
            }

            if (_declaredMethodOverloads.ContainsKey(ident.Name))
            {
                throw new InvalidOperationException($"No matching overload for function {ident.Name}");
            }

            if (ident.Name == "print")
            {
                // Emit arguments
                foreach (var arg in call.Arguments)
                {
                    EmitExpression(arg.Value);
                }

                // Call Console.WriteLine
                var writeLineMethod = typeof(Console).GetMethod("WriteLine", new[] { typeof(object) });
                if (writeLineMethod != null)
                {
                    _currentIL.Emit(OpCodes.Call, writeLineMethod);
                }
                return;
            }

            // Check if it's a user-defined function
            if (_methods.TryGetValue(ident.Name, out var methodBuilder))
            {
                var parameterTypes = _declaredMethodParameters.TryGetValue(ident.Name, out var declaredParameters)
                    ? declaredParameters.Select(p => ResolveParameterType(p, _currentGenericParameters)).ToArray()
                    : methodBuilder.GetParameters().Select(p => p.ParameterType).ToArray();
                EmitCallArguments(call.Arguments, parameterTypes);

                // Call the method
                _currentIL.Emit(OpCodes.Call, methodBuilder);
                return;
            }
        }

        throw new NotImplementedException($"Function call {call.Callee} not yet fully implemented in IL compiler");
    }

    private void StoreIdentifierFromLocal(IdentifierExpression ident, LocalBuilder valueLocal)
    {
        if (_currentIL == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        if (_locals != null && _locals.TryGetValue(ident.Name, out var local))
        {
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            if (IsLiftedIdentifier(ident.Name))
            {
                EmitStoreLiftedLocalValue(local, GetIdentifierType(ident), leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, local);
            }
        }
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            if (_byRefParameters != null && _byRefParameters.Contains(ident.Name))
            {
                EmitLoadArgument(paramIndex);
                _currentIL.Emit(OpCodes.Ldloc, valueLocal);
                EmitStoreIndirect(GetIdentifierType(ident));
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, valueLocal);
                EmitStoreArgument(paramIndex);
            }
        }
        else if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField) && IsLiftedClosureField(ident.Name))
        {
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitStoreLiftedClosureFieldValue(closureField, GetIdentifierType(ident), leaveValueOnStack: false);
        }
        else
        {
            var instanceField = _currentTypeBuilder != null
                ? FindPrimaryConstructorField(_currentTypeBuilder, ident.Name) ?? FindField(_currentTypeBuilder, ident.Name)
                : null;

            if (instanceField == null)
            {
                throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
            }

            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            _currentIL.Emit(OpCodes.Stfld, instanceField);
        }
    }

    /// <summary>
    /// Emit IL for an assignment expression
    /// </summary>
    private void EmitAssignment(AssignmentExpression assignment)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        // Handle member access assignments (obj.Field = value)
        if (assignment.Target is MemberAccessExpression memberAccess)
        {
            if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
            {
                var staticMemberType = GetMemberAccessType(memberAccess);

                if (assignment.Operator == AssignmentOperator.NullCoalesceAssign)
                {
                    var currentValueLocal = _currentIL.DeclareLocal(staticMemberType);
                    EmitStaticMemberLoadValue(staticType, memberAccess.MemberName);
                    _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

                    if (!staticMemberType.IsValueType || Nullable.GetUnderlyingType(staticMemberType) != null)
                    {
                        var hasValueLabel = _currentIL.DefineLabel();
                        var endLabel = _currentIL.DefineLabel();

                        EmitBranchIfHasValue(staticMemberType, currentValueLocal, hasValueLabel);
                        if (assignment.Value is DefaultExpression)
                        {
                            EmitDefaultValue(staticMemberType);
                        }
                        else
                        {
                            EmitExpressionWithExpectedType(assignment.Value, staticMemberType);
                        }

                        _currentIL.Emit(OpCodes.Stloc, currentValueLocal);
                        _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                        EmitStaticMemberStoreValue(staticType, memberAccess.MemberName);
                        _currentIL.Emit(OpCodes.Br, endLabel);

                        _currentIL.MarkLabel(hasValueLabel);
                        _currentIL.MarkLabel(endLabel);
                    }

                    _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                    return;
                }

                if (assignment.Operator == AssignmentOperator.Assign)
                {
                    if (assignment.Value is DefaultExpression)
                    {
                        EmitDefaultValue(staticMemberType);
                    }
                    else
                    {
                        EmitExpressionWithExpectedType(assignment.Value, staticMemberType);
                    }
                }
                else
                {
                    EmitStaticMemberLoadValue(staticType, memberAccess.MemberName);
                    if (assignment.Value is DefaultExpression)
                    {
                        EmitDefaultValue(staticMemberType);
                    }
                    else
                    {
                        EmitExpressionWithExpectedType(assignment.Value, staticMemberType);
                    }

                    switch (assignment.Operator)
                    {
                        case AssignmentOperator.AddAssign:
                            _currentIL.Emit(OpCodes.Add);
                            break;
                        case AssignmentOperator.SubtractAssign:
                            _currentIL.Emit(OpCodes.Sub);
                            break;
                        case AssignmentOperator.MultiplyAssign:
                            _currentIL.Emit(OpCodes.Mul);
                            break;
                        case AssignmentOperator.DivideAssign:
                            _currentIL.Emit(OpCodes.Div);
                            break;
                        default:
                            throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented");
                    }
                }

                var assignedValueLocal = _currentIL.DeclareLocal(staticMemberType);
                _currentIL.Emit(OpCodes.Stloc, assignedValueLocal);
                _currentIL.Emit(OpCodes.Ldloc, assignedValueLocal);
                EmitStaticMemberStoreValue(staticType, memberAccess.MemberName);
                _currentIL.Emit(OpCodes.Ldloc, assignedValueLocal);
                return;
            }

            var objectType = GetExpressionType(memberAccess.Object);
            var memberType = GetMemberAccessType(memberAccess);

            if (assignment.Operator == AssignmentOperator.NullCoalesceAssign)
            {
                EmitExpression(memberAccess.Object);
                var objectLocal = _currentIL.DeclareLocal(objectType);
                _currentIL.Emit(OpCodes.Stloc, objectLocal);

                _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                EmitMemberLoadValue(objectType, memberAccess.MemberName);
                var currentValueLocal = _currentIL.DeclareLocal(memberType);
                _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

                if (!memberType.IsValueType || Nullable.GetUnderlyingType(memberType) != null)
                {
                    var hasValueLabel = _currentIL.DefineLabel();
                    var endLabel = _currentIL.DefineLabel();

                    EmitBranchIfHasValue(memberType, currentValueLocal, hasValueLabel);
                    if (assignment.Value is DefaultExpression)
                    {
                        EmitDefaultValue(memberType);
                    }
                    else
                    {
                        EmitExpressionWithExpectedType(assignment.Value, memberType);
                    }

                    _currentIL.Emit(OpCodes.Stloc, currentValueLocal);
                    _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                    _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                    EmitMemberStoreValue(objectType, memberAccess.MemberName);
                    _currentIL.Emit(OpCodes.Br, endLabel);

                    _currentIL.MarkLabel(hasValueLabel);
                    _currentIL.MarkLabel(endLabel);
                    _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                    return;
                }

                _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                return;
            }

            // Emit the object
            var cacheReceiver = !IsValueTypeLike(objectType);
            LocalBuilder? receiverLocal = null;
            if (cacheReceiver)
            {
                EmitExpression(memberAccess.Object);
                receiverLocal = _currentIL.DeclareLocal(objectType);
                _currentIL.Emit(OpCodes.Stloc, receiverLocal);
                _currentIL.Emit(OpCodes.Ldloc, receiverLocal);
            }
            else
            {
                EmitExpression(memberAccess.Object);
            }

            // Handle compound assignment
            if (assignment.Operator != AssignmentOperator.Assign)
            {
                // For compound assignments, we need to load the current value first
                _currentIL.Emit(OpCodes.Dup); // Duplicate object reference

                // Load current field/property value
                if (objectType is TypeBuilder typeBuilder)
                {
                    if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberAccess.MemberName), out var fieldBuilder))
                    {
                        _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                    }
                    else if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberAccess.MemberName}"), out var getterMethod))
                    {
                        _currentIL.Emit(OpCodes.Callvirt, getterMethod);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {GetTypeKey(typeBuilder)}");
                    }
                }
                else
                {
                    var property = objectType.GetProperty(memberAccess.MemberName);
                    if (property != null && property.GetMethod != null)
                    {
                        _currentIL.Emit(OpCodes.Callvirt, property.GetMethod);
                    }
                    else
                    {
                        var field = objectType.GetField(memberAccess.MemberName);
                        if (field != null)
                        {
                            _currentIL.Emit(OpCodes.Ldfld, field);
                        }
                        else
                        {
                            throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
                        }
                    }
                }

                // Emit right-hand side
                if (assignment.Value is DefaultExpression)
                {
                    EmitDefaultValue(GetMemberAccessType(memberAccess));
                }
                else
                {
                    EmitExpressionWithExpectedType(assignment.Value, GetMemberAccessType(memberAccess));
                }

                // Perform operation
                switch (assignment.Operator)
                {
                    case AssignmentOperator.AddAssign:
                        _currentIL.Emit(OpCodes.Add);
                        break;
                    case AssignmentOperator.SubtractAssign:
                        _currentIL.Emit(OpCodes.Sub);
                        break;
                    case AssignmentOperator.MultiplyAssign:
                        _currentIL.Emit(OpCodes.Mul);
                        break;
                    case AssignmentOperator.DivideAssign:
                        _currentIL.Emit(OpCodes.Div);
                        break;
                    default:
                        throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented");
                }
            }
            else
            {
                // Simple assignment - just emit the value
                if (assignment.Value is DefaultExpression)
                {
                    EmitDefaultValue(GetMemberAccessType(memberAccess));
                }
                else
                {
                    EmitExpressionWithExpectedType(assignment.Value, GetMemberAccessType(memberAccess));
                }
            }

            // Store to field/property
            if (objectType is TypeBuilder tb)
            {
                if (_fields.TryGetValue(GetFieldKey(tb, memberAccess.MemberName), out var fb))
                {
                    _currentIL.Emit(OpCodes.Stfld, fb);
                }
                else if (_methods.TryGetValue(GetMethodKey(tb, $"set_{memberAccess.MemberName}"), out var setterMethod))
                {
                    _currentIL.Emit(OpCodes.Callvirt, setterMethod);
                }
                else
                {
                    throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {GetTypeKey(tb)}");
                }
            }
            else
            {
                var prop = objectType.GetProperty(memberAccess.MemberName);
                if (prop != null && prop.SetMethod != null)
                {
                    _currentIL.Emit(OpCodes.Callvirt, prop.SetMethod);
                }
                else
                {
                    var fld = objectType.GetField(memberAccess.MemberName);
                    if (fld != null)
                    {
                        _currentIL.Emit(OpCodes.Stfld, fld);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
                    }
                }
            }

            // Assignment expressions return the assigned value
            // For member assignments, we need to reload the value
            if (receiverLocal != null)
            {
                _currentIL.Emit(OpCodes.Ldloc, receiverLocal);
                EmitMemberLoadValue(objectType, memberAccess.MemberName);
            }
            else
            {
                EmitMemberAccess(memberAccess);
            }

            return;
        }

        // Handle indexed assignments (obj[index] = value)
        if (assignment.Target is IndexAccessExpression indexAccess)
        {
            var objectType = GetExpressionType(indexAccess.Object);
            var indexType = GetExpressionType(indexAccess.Index);
            var valueType = GetIndexAccessType(indexAccess);

            EmitExpression(indexAccess.Object);
            var objectLocal = _currentIL.DeclareLocal(objectType);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);

            EmitExpression(indexAccess.Index);
            var indexLocal = _currentIL.DeclareLocal(indexType);
            _currentIL.Emit(OpCodes.Stloc, indexLocal);

            if (assignment.Operator == AssignmentOperator.NullCoalesceAssign)
            {
                _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                _currentIL.Emit(OpCodes.Ldloc, indexLocal);
                EmitIndexLoadValue(indexAccess, objectType);
                var currentValueLocal = _currentIL.DeclareLocal(valueType);
                _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

                if (!valueType.IsValueType || Nullable.GetUnderlyingType(valueType) != null)
                {
                    var hasValueLabel = _currentIL.DefineLabel();
                    var endLabel = _currentIL.DefineLabel();

                    EmitBranchIfHasValue(valueType, currentValueLocal, hasValueLabel);
                    if (assignment.Value is DefaultExpression)
                    {
                        EmitDefaultValue(valueType);
                    }
                    else
                    {
                        EmitExpressionWithExpectedType(assignment.Value, valueType);
                    }

                    _currentIL.Emit(OpCodes.Stloc, currentValueLocal);
                    _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                    _currentIL.Emit(OpCodes.Ldloc, indexLocal);
                    _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                    EmitIndexStoreValue(indexAccess, objectType);
                    _currentIL.Emit(OpCodes.Br, endLabel);

                    _currentIL.MarkLabel(hasValueLabel);
                    _currentIL.MarkLabel(endLabel);
                    _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                    return;
                }

                _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                return;
            }

            if (assignment.Operator == AssignmentOperator.Assign)
            {
                if (assignment.Value is DefaultExpression)
                {
                    EmitDefaultValue(valueType);
                }
                else
                {
                    EmitExpressionWithExpectedType(assignment.Value, valueType);
                }
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                _currentIL.Emit(OpCodes.Ldloc, indexLocal);
                EmitIndexLoadValue(indexAccess, objectType);
                EmitExpressionWithExpectedType(assignment.Value, valueType);

                switch (assignment.Operator)
                {
                    case AssignmentOperator.AddAssign:
                        _currentIL.Emit(OpCodes.Add);
                        break;
                    case AssignmentOperator.SubtractAssign:
                        _currentIL.Emit(OpCodes.Sub);
                        break;
                    case AssignmentOperator.MultiplyAssign:
                        _currentIL.Emit(OpCodes.Mul);
                        break;
                    case AssignmentOperator.DivideAssign:
                        _currentIL.Emit(OpCodes.Div);
                        break;
                    default:
                        throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented");
                }
            }

            var valueLocal = _currentIL.DeclareLocal(valueType);
            _currentIL.Emit(OpCodes.Stloc, valueLocal);

            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            _currentIL.Emit(OpCodes.Ldloc, indexLocal);
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitIndexStoreValue(indexAccess, objectType);
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            return;
        }

        // Handle simple identifier assignments
        if (assignment.Target is not IdentifierExpression ident)
        {
            throw new NotImplementedException("Only simple variable and member assignments are supported in IL compiler");
        }

        if (assignment.Operator == AssignmentOperator.NullCoalesceAssign)
        {
            var valueType = GetIdentifierType(ident);
            var currentValueLocal = _currentIL.DeclareLocal(valueType);
            EmitIdentifier(ident);
            _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

            if (!valueType.IsValueType || Nullable.GetUnderlyingType(valueType) != null)
            {
                var hasValueLabel = _currentIL.DefineLabel();
                var endLabel = _currentIL.DefineLabel();

                EmitBranchIfHasValue(valueType, currentValueLocal, hasValueLabel);
                if (assignment.Value is DefaultExpression)
                {
                    EmitDefaultValue(valueType);
                }
                else
                {
                    EmitExpressionWithExpectedType(assignment.Value, valueType);
                }

                _currentIL.Emit(OpCodes.Stloc, currentValueLocal);
                StoreIdentifierFromLocal(ident, currentValueLocal);
                _currentIL.Emit(OpCodes.Br, endLabel);

                _currentIL.MarkLabel(hasValueLabel);
                _currentIL.MarkLabel(endLabel);
                _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                return;
            }

            _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
            return;
        }

        // Handle compound assignment operators
        if (assignment.Operator != AssignmentOperator.Assign)
        {
            // For compound assignments like +=, -=, etc., we need to:
            // 1. Load the current value
            // 2. Load the right-hand side
            // 3. Perform the operation
            // 4. Store the result

            // Load current value
            EmitIdentifier(ident);

            // Load right-hand side
            EmitExpressionWithExpectedType(assignment.Value, GetIdentifierType(ident));

            // Perform the operation based on the assignment operator
            switch (assignment.Operator)
            {
                case AssignmentOperator.AddAssign:
                    _currentIL.Emit(OpCodes.Add);
                    break;
                case AssignmentOperator.SubtractAssign:
                    _currentIL.Emit(OpCodes.Sub);
                    break;
                case AssignmentOperator.MultiplyAssign:
                    _currentIL.Emit(OpCodes.Mul);
                    break;
                case AssignmentOperator.DivideAssign:
                    _currentIL.Emit(OpCodes.Div);
                    break;
                default:
                    throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented in IL compiler");
            }
        }
        else
        {
            // Simple assignment: just emit the value
            if (assignment.Value is DefaultExpression)
            {
                EmitDefaultValue(GetIdentifierType(ident));
            }
            else
            {
                EmitExpressionWithExpectedType(assignment.Value, GetIdentifierType(ident));
            }
        }

        // Store the value
        if (_locals.TryGetValue(ident.Name, out var local))
        {
            if (IsLiftedIdentifier(ident.Name))
            {
                EmitStoreLiftedLocalValue(local, GetIdentifierType(ident), leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, local);
            }
        }
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            if (_byRefParameters != null && _byRefParameters.Contains(ident.Name))
            {
                var parameterType = GetIdentifierType(ident);
                var tempLocal = _currentIL.DeclareLocal(parameterType);
                _currentIL.Emit(OpCodes.Stloc, tempLocal);
                EmitLoadArgument(paramIndex);
                _currentIL.Emit(OpCodes.Ldloc, tempLocal);
                EmitStoreIndirect(parameterType);
            }
            else
            {
                EmitStoreArgument(paramIndex);
            }
        }
        else if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField) && IsLiftedClosureField(ident.Name))
        {
            EmitStoreLiftedClosureFieldValue(closureField, GetIdentifierType(ident), leaveValueOnStack: false);
        }
        else
        {
            var instanceField = _currentTypeBuilder != null
                ? FindPrimaryConstructorField(_currentTypeBuilder, ident.Name) ?? FindField(_currentTypeBuilder, ident.Name)
                : null;

            if (instanceField == null)
            {
                throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
            }

            var assignedValueType = GetExpressionType(assignment.Value);
            var tempLocal = _currentIL.DeclareLocal(assignedValueType);
            _currentIL.Emit(OpCodes.Stloc, tempLocal);
            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldloc, tempLocal);
            _currentIL.Emit(OpCodes.Stfld, instanceField);
        }

        // Assignment expressions also return the assigned value, so we need to load it back
        // This allows things like: x = y = 5
        EmitIdentifier(ident);
    }

    /// <summary>
    /// Emit IL for a new object expression
    /// </summary>
    private void EmitNewObject(NewExpression newExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        Type type;
        if (newExpr.Type == null)
        {
            if (_expectedExpressionType == null)
            {
                throw new NotImplementedException("Target-typed new not yet supported in IL compiler without an expected type");
            }

            type = _expectedExpressionType;
        }
        else
        {
            type = ResolveType(newExpr.Type, _currentGenericParameters);
        }

        if (type.IsGenericParameter)
        {
            if (newExpr.ConstructorArguments.Count != 0 || newExpr.Initializer != null)
            {
                throw new InvalidOperationException($"Cannot construct generic type parameter {type.Name} with arguments or an initializer");
            }

            var createInstanceMethod = typeof(Activator).GetMethods(BindingFlags.Public | BindingFlags.Static)
                .FirstOrDefault(method =>
                    method.Name == nameof(Activator.CreateInstance)
                    && method.IsGenericMethodDefinition
                    && method.GetGenericArguments().Length == 1
                    && method.GetParameters().Length == 0)
                ?.MakeGenericMethod(type)
                ?? throw new InvalidOperationException("Could not resolve Activator.CreateInstance<T>()");

            _currentIL.Emit(OpCodes.Call, createInstanceMethod);
            return;
        }

        // Find the constructor
        ConstructorInfo? constructor = null;
        IReadOnlyList<BoundCallArgument>? boundArguments = null;

        // Check if it's a user-defined type
        if (TryGetUserTypeDefinition(type, out var typeBuilder))
        {
            var boundConstructorCall = BindDeclaredConstructorCall(type, newExpr.ConstructorArguments);
            if (boundConstructorCall != null)
            {
                constructor = boundConstructorCall.Constructor;
                boundArguments = boundConstructorCall.Arguments;
            }
            else if (_declaredConstructorOverloads.ContainsKey(GetConstructorKey(typeBuilder)))
            {
                throw new InvalidOperationException($"No matching constructor found for type {type.Name}");
            }
            else
            {
                constructor = ResolveUserDefinedConstructor(type);
                if (constructor == null && !(type.IsValueType && newExpr.ConstructorArguments.Count == 0))
                {
                    throw new InvalidOperationException($"No matching constructor found for type {type.Name}");
                }
            }
        }
        else
        {
            // Built-in type - use reflection
            var parameterTypes = newExpr.ConstructorArguments
                .Select(arg => GetExpressionType(arg.Value))
                .ToArray();

            if (parameterTypes.Length == 0)
            {
                // Default constructor
                constructor = type.GetConstructor(Type.EmptyTypes);
            }
            else
            {
                // Constructor with parameters
                constructor = type.GetConstructor(parameterTypes);
            }

            if (constructor == null)
            {
                if (!(type.IsValueType && parameterTypes.Length == 0))
                {
                    throw new InvalidOperationException($"No matching constructor found for type {type.Name}");
                }
            }
        }

        if (type.IsValueType)
        {
            var valueLocal = _currentIL.DeclareLocal(type);

            if (constructor != null)
            {
                if (boundArguments != null)
                {
                    EmitBoundCallArguments(boundArguments);
                }
                else
                {
                    foreach (var arg in newExpr.ConstructorArguments)
                    {
                        EmitExpression(arg.Value);
                    }
                }

                _currentIL.Emit(OpCodes.Newobj, constructor);
                _currentIL.Emit(OpCodes.Stloc, valueLocal);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloca_S, valueLocal);
                _currentIL.Emit(OpCodes.Initobj, type);
            }

            if (newExpr.Initializer != null)
            {
                foreach (var propInit in newExpr.Initializer.Properties)
                {
                    EmitValueTypeObjectInitializerEntry(type, valueLocal, propInit);
                }
            }

            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            return;
        }

        if (boundArguments != null)
        {
            EmitBoundCallArguments(boundArguments);
        }
        else
        {
            foreach (var arg in newExpr.ConstructorArguments)
            {
                EmitExpression(arg.Value);
            }
        }

        // Call constructor
        _currentIL.Emit(OpCodes.Newobj, constructor);

        // Handle object initializer if present
        if (newExpr.Initializer != null)
        {
            foreach (var propInit in newExpr.Initializer.Properties)
            {
                _currentIL.Emit(OpCodes.Dup);
                EmitObjectInitializerEntry(type, propInit);
            }
        }
    }

    private void EmitValueTypeObjectInitializerEntry(Type targetType, LocalBuilder targetLocal, PropertyInitializer initializer)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (initializer.IsIndexerInitializer)
        {
            var indexExpression = initializer.IndexExpression
                ?? throw new InvalidOperationException("Indexer initializer is missing an index expression");

            if (targetType is TypeBuilder typeBuilder)
            {
                if (_methods.TryGetValue(GetMethodKey(typeBuilder, "set_Item"), out var setMethod))
                {
                    var parameters = setMethod.GetParameters();
                    _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
                    EmitExpressionWithExpectedType(indexExpression, parameters[0].ParameterType);
                    EmitExpressionWithExpectedType(initializer.Value, parameters[1].ParameterType);
                    _currentIL.Emit(OpCodes.Call, setMethod);
                    return;
                }

                throw new InvalidOperationException($"Indexer setter not found on type {GetTypeKey(typeBuilder)}");
            }

            var indexer = targetType.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(property => property.GetIndexParameters().Length == 1);
            if (indexer?.SetMethod == null)
            {
                throw new InvalidOperationException($"Indexer setter not found on type {targetType.Name}");
            }

            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
            EmitExpressionWithExpectedType(indexExpression, indexer.GetIndexParameters()[0].ParameterType);
            EmitExpressionWithExpectedType(initializer.Value, indexer.PropertyType);
            _currentIL.Emit(OpCodes.Call, indexer.SetMethod);
            return;
        }

        if (targetType is TypeBuilder valueTypeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(valueTypeBuilder, initializer.Name), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, fieldBuilder.FieldType);
                _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(valueTypeBuilder, $"set_{initializer.Name}"), out var setterMethod))
            {
                _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, setterMethod.GetParameters()[0].ParameterType);
                _currentIL.Emit(OpCodes.Call, setterMethod);
                return;
            }
        }
        else
        {
            var property = targetType.GetProperty(initializer.Name);
            if (property?.SetMethod != null)
            {
                _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, property.PropertyType);
                _currentIL.Emit(OpCodes.Call, property.SetMethod);
                return;
            }

            var field = targetType.GetField(initializer.Name);
            if (field != null)
            {
                _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, field.FieldType);
                _currentIL.Emit(OpCodes.Stfld, field);
                return;
            }
        }

        throw new InvalidOperationException($"Property or field {initializer.Name} not found on type {targetType.Name}");
    }

    private void EmitObjectInitializerEntry(Type targetType, PropertyInitializer initializer)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (initializer.IsIndexerInitializer)
        {
            var indexExpression = initializer.IndexExpression
                ?? throw new InvalidOperationException("Indexer initializer is missing an index expression");

            if (targetType is TypeBuilder typeBuilder)
            {
                if (_methods.TryGetValue(GetMethodKey(typeBuilder, "set_Item"), out var setMethod))
                {
                    var parameters = setMethod.GetParameters();
                    EmitExpressionWithExpectedType(indexExpression, parameters[0].ParameterType);
                    EmitExpressionWithExpectedType(initializer.Value, parameters[1].ParameterType);
                    _currentIL.Emit(OpCodes.Callvirt, setMethod);
                    return;
                }

                throw new InvalidOperationException($"Indexer setter not found on type {GetTypeKey(typeBuilder)}");
            }

            var indexer = targetType.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(p => p.GetIndexParameters().Length == 1 && p.SetMethod != null);

            if (indexer?.SetMethod == null)
            {
                throw new InvalidOperationException($"Indexer setter not found on type {targetType.Name}");
            }

            var indexType = indexer.GetIndexParameters()[0].ParameterType;
            EmitExpressionWithExpectedType(indexExpression, indexType);
            EmitExpressionWithExpectedType(initializer.Value, indexer.PropertyType);
            _currentIL.Emit(indexer.SetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, indexer.SetMethod);
            return;
        }

        if (initializer.Name == null)
        {
            var addArgument = new Argument(null, initializer.Value);

            if (targetType is TypeBuilder typeBuilder)
            {
                if (_methods.TryGetValue(GetMethodKey(typeBuilder, "Add"), out var addMethod))
                {
                    var parameterTypes = addMethod.GetParameters().Select(p => p.ParameterType).ToArray();
                    EmitCallArguments(new[] { addArgument }, parameterTypes);
                    _currentIL.Emit(OpCodes.Callvirt, addMethod);
                    return;
                }

                throw new InvalidOperationException($"Collection initializer requires an Add method on type {GetTypeKey(typeBuilder)}");
            }

            var boundAddCall = BindRuntimeMethodCall(
                targetType,
                "Add",
                new[] { addArgument },
                null,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);

            if (boundAddCall == null)
            {
                throw new InvalidOperationException($"Collection initializer requires an Add method on type {targetType.Name}");
            }

            EmitBoundCallArguments(boundAddCall.Arguments);
            _currentIL.Emit(boundAddCall.Method.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, boundAddCall.Method);
            return;
        }

        if (targetType is TypeBuilder objectTypeBuilder)
        {
            if (_methods.TryGetValue(GetMethodKey(objectTypeBuilder, $"set_{initializer.Name}"), out var setMethod))
            {
                var valueType = setMethod.GetParameters()[0].ParameterType;
                EmitExpressionWithExpectedType(initializer.Value, valueType);
                _currentIL.Emit(OpCodes.Callvirt, setMethod);
                return;
            }

            if (_fields.TryGetValue(GetFieldKey(objectTypeBuilder, initializer.Name), out var fieldBuilder))
            {
                EmitExpressionWithExpectedType(initializer.Value, fieldBuilder.FieldType);
                _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
                return;
            }

            throw new InvalidOperationException($"Property or field {initializer.Name} not found on type {GetTypeKey(objectTypeBuilder)}");
        }

        var property = targetType.GetProperty(initializer.Name);
        if (property?.SetMethod != null)
        {
            EmitExpressionWithExpectedType(initializer.Value, property.PropertyType);
            _currentIL.Emit(property.SetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, property.SetMethod);
            return;
        }

        var field = targetType.GetField(initializer.Name);
        if (field != null)
        {
            EmitExpressionWithExpectedType(initializer.Value, field.FieldType);
            _currentIL.Emit(OpCodes.Stfld, field);
            return;
        }

        throw new InvalidOperationException($"Property or field {initializer.Name} not found on type {targetType.Name}");
    }

    private void EmitWithExpression(WithExpression withExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var targetType = GetExpressionType(withExpr.Target);
        var cloneLocal = _currentIL.DeclareLocal(targetType);

        if (IsValueTypeLike(targetType))
        {
            EmitExpressionWithExpectedType(withExpr.Target, targetType);
        }
        else
        {
            EmitExpressionWithExpectedType(withExpr.Target, targetType);
            var memberwiseClone = typeof(object).GetMethod("MemberwiseClone", BindingFlags.Instance | BindingFlags.NonPublic);
            if (memberwiseClone == null)
            {
                throw new InvalidOperationException("Could not resolve object.MemberwiseClone");
            }

            _currentIL.Emit(OpCodes.Call, memberwiseClone);
            _currentIL.Emit(OpCodes.Castclass, targetType);
        }

        _currentIL.Emit(OpCodes.Stloc, cloneLocal);

        foreach (var property in withExpr.Properties)
        {
            EmitWithMemberAssignment(cloneLocal, targetType, property);
        }

        _currentIL.Emit(OpCodes.Ldloc, cloneLocal);
    }

    private void EmitWithMemberAssignment(LocalBuilder targetLocal, Type targetType, PropertyInitializer initializer)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (initializer.Name == null || initializer.IsIndexerInitializer)
        {
            throw new InvalidOperationException("with expressions only support named member updates");
        }

        var useAddressReceiver = IsValueTypeLike(targetType);
        var callOpcode = useAddressReceiver ? OpCodes.Call : OpCodes.Callvirt;

        if (targetType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, initializer.Name), out var fieldBuilder))
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, fieldBuilder.FieldType);
                _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{initializer.Name}"), out var setterMethod))
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, setterMethod.GetParameters()[0].ParameterType);
                _currentIL.Emit(callOpcode, setterMethod);
                return;
            }

            throw new InvalidOperationException($"Member {initializer.Name} not found on type {GetTypeKey(typeBuilder)}");
        }

        var field = targetType.GetField(initializer.Name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (field != null)
        {
            _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
            EmitExpressionWithExpectedType(initializer.Value, field.FieldType);
            _currentIL.Emit(OpCodes.Stfld, field);
            return;
        }

        var property = targetType.GetProperty(initializer.Name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property?.SetMethod != null)
        {
            _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
            EmitExpressionWithExpectedType(initializer.Value, property.PropertyType);
            _currentIL.Emit(useAddressReceiver || !property.SetMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, property.SetMethod);
            return;
        }

        throw new InvalidOperationException($"Member {initializer.Name} not found on type {targetType}");
    }

    /// <summary>
    /// Emit IL for an index access expression
    /// </summary>
    private void EmitIndexAccess(IndexAccessExpression indexAccess)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (indexAccess.IsNullConditional)
        {
            var nonNullIndexAccess = indexAccess with { IsNullConditional = false };
            var receiverType = GetExpressionType(nonNullIndexAccess.Object);
            var resultType = GetIndexAccessType(indexAccess);
            var nonNullValueType = GetIndexAccessType(nonNullIndexAccess);

            EmitExpression(nonNullIndexAccess.Object);
            var objectLocal = _currentIL.DeclareLocal(receiverType);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);

            var hasValueLabel = _currentIL.DefineLabel();
            var endLabel = _currentIL.DefineLabel();

            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            _currentIL.Emit(OpCodes.Brtrue, hasValueLabel);
            EmitDefaultValue(resultType);
            _currentIL.Emit(OpCodes.Br, endLabel);

            _currentIL.MarkLabel(hasValueLabel);
            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            EmitExpression(nonNullIndexAccess.Index);
            EmitIndexLoadValue(nonNullIndexAccess, receiverType);
            if (resultType != nonNullValueType)
            {
                var nullableCtor = resultType.GetConstructor(new[] { nonNullValueType });
                if (nullableCtor == null)
                {
                    throw new InvalidOperationException($"Could not resolve nullable constructor for {resultType}");
                }

                _currentIL.Emit(OpCodes.Newobj, nullableCtor);
            }

            _currentIL.MarkLabel(endLabel);
            return;
        }

        var objectType = GetExpressionType(indexAccess.Object);

        EmitExpression(indexAccess.Object);
        EmitExpression(indexAccess.Index);
        EmitIndexLoadValue(indexAccess, objectType);
    }

    private void EmitIndexLoadValue(IndexAccessExpression indexAccess, Type objectType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (objectType.IsArray)
        {
            var elementType = objectType.GetElementType()!;
            var indexType = GetExpressionType(indexAccess.Index);
            var useGenericArrayOpcode = objectType.ContainsGenericParameters
                || elementType.IsGenericParameter
                || elementType.ContainsGenericParameters;

            if (indexType == typeof(Range))
            {
                var rangeLocal = _currentIL.DeclareLocal(typeof(Range));
                var arrayLocal = _currentIL.DeclareLocal(objectType);
                _currentIL.Emit(OpCodes.Stloc, rangeLocal);
                _currentIL.Emit(OpCodes.Stloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldloc, rangeLocal);

                var getSubArray = typeof(System.Runtime.CompilerServices.RuntimeHelpers)
                    .GetMethods(BindingFlags.Public | BindingFlags.Static)
                    .First(m => m.Name == "GetSubArray" && m.IsGenericMethodDefinition && m.GetParameters().Length == 2)
                    .MakeGenericMethod(elementType);

                _currentIL.Emit(OpCodes.Call, getSubArray);
                return;
            }

            if (indexType == typeof(Index))
            {
                var indexLocal = _currentIL.DeclareLocal(typeof(Index));
                var arrayLocal = _currentIL.DeclareLocal(objectType);
                var lengthLocal = _currentIL.DeclareLocal(typeof(int));
                _currentIL.Emit(OpCodes.Stloc, indexLocal);
                _currentIL.Emit(OpCodes.Stloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldlen);
                _currentIL.Emit(OpCodes.Conv_I4);
                _currentIL.Emit(OpCodes.Stloc, lengthLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                EmitIndexOffset(indexLocal, lengthLocal);
                if (useGenericArrayOpcode)
                {
                    _currentIL.Emit(OpCodes.Ldelem, elementType);
                }
                else
                {
                    EmitArrayElementLoad(elementType);
                }
                return;
            }

            if (useGenericArrayOpcode)
            {
                _currentIL.Emit(OpCodes.Ldelem, elementType);
            }
            else
            {
                EmitArrayElementLoad(elementType);
            }
            return;
        }

        if (objectType == typeof(string))
        {
            var stringLengthGetter = typeof(string).GetProperty(nameof(string.Length))?.GetMethod;
            var charGetter = typeof(string).GetProperty("Chars")?.GetMethod;
            if (stringLengthGetter == null || charGetter == null)
            {
                throw new InvalidOperationException("Could not resolve string index helpers");
            }

            var indexType = GetExpressionType(indexAccess.Index);
            if (indexType == typeof(Index))
            {
                var indexLocal = _currentIL.DeclareLocal(typeof(Index));
                var stringLocal = _currentIL.DeclareLocal(typeof(string));
                var lengthLocal = _currentIL.DeclareLocal(typeof(int));
                _currentIL.Emit(OpCodes.Stloc, indexLocal);
                _currentIL.Emit(OpCodes.Stloc, stringLocal);
                _currentIL.Emit(OpCodes.Ldloc, stringLocal);
                _currentIL.Emit(OpCodes.Call, stringLengthGetter);
                _currentIL.Emit(OpCodes.Stloc, lengthLocal);
                _currentIL.Emit(OpCodes.Ldloc, stringLocal);
                EmitIndexOffset(indexLocal, lengthLocal);
                _currentIL.Emit(OpCodes.Call, charGetter);
                return;
            }

            if (indexType == typeof(Range))
            {
                var rangeLocal = _currentIL.DeclareLocal(typeof(Range));
                var stringLocal = _currentIL.DeclareLocal(typeof(string));
                var lengthLocal = _currentIL.DeclareLocal(typeof(int));
                var startIndexLocal = _currentIL.DeclareLocal(typeof(Index));
                var endIndexLocal = _currentIL.DeclareLocal(typeof(Index));
                var startOffsetLocal = _currentIL.DeclareLocal(typeof(int));
                var endOffsetLocal = _currentIL.DeclareLocal(typeof(int));
                var getStart = typeof(Range).GetProperty(nameof(Range.Start))?.GetMethod;
                var getEnd = typeof(Range).GetProperty(nameof(Range.End))?.GetMethod;
                var substring = typeof(string).GetMethod(nameof(string.Substring), new[] { typeof(int), typeof(int) });

                if (getStart == null || getEnd == null || substring == null)
                {
                    throw new InvalidOperationException("Could not resolve string range helpers");
                }

                _currentIL.Emit(OpCodes.Stloc, rangeLocal);
                _currentIL.Emit(OpCodes.Stloc, stringLocal);
                _currentIL.Emit(OpCodes.Ldloc, stringLocal);
                _currentIL.Emit(OpCodes.Call, stringLengthGetter);
                _currentIL.Emit(OpCodes.Stloc, lengthLocal);

                _currentIL.Emit(OpCodes.Ldloca_S, rangeLocal);
                _currentIL.Emit(OpCodes.Call, getStart);
                _currentIL.Emit(OpCodes.Stloc, startIndexLocal);
                EmitIndexOffset(startIndexLocal, lengthLocal);
                _currentIL.Emit(OpCodes.Stloc, startOffsetLocal);

                _currentIL.Emit(OpCodes.Ldloca_S, rangeLocal);
                _currentIL.Emit(OpCodes.Call, getEnd);
                _currentIL.Emit(OpCodes.Stloc, endIndexLocal);
                EmitIndexOffset(endIndexLocal, lengthLocal);
                _currentIL.Emit(OpCodes.Stloc, endOffsetLocal);

                _currentIL.Emit(OpCodes.Ldloc, stringLocal);
                _currentIL.Emit(OpCodes.Ldloc, startOffsetLocal);
                _currentIL.Emit(OpCodes.Ldloc, endOffsetLocal);
                _currentIL.Emit(OpCodes.Ldloc, startOffsetLocal);
                _currentIL.Emit(OpCodes.Sub);
                _currentIL.Emit(OpCodes.Call, substring);
                return;
            }
        }

        if (objectType is TypeBuilder typeBuilder)
        {
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Item"), out var getterMethod))
            {
                _currentIL.Emit(OpCodes.Callvirt, getterMethod);
                return;
            }

            throw new InvalidOperationException($"Type {GetTypeKey(typeBuilder)} does not support index access");
        }

        var reflectionIndexType = GetExpressionType(indexAccess.Index);
        var indexer = objectType.GetDefaultMembers()
            .OfType<PropertyInfo>()
            .FirstOrDefault(p =>
                p.GetIndexParameters().Length == 1 &&
                p.GetMethod != null &&
                AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, reflectionIndexType));

        if (indexer?.GetMethod != null)
        {
            _currentIL.Emit(indexer.GetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, indexer.GetMethod);
            return;
        }

        throw new InvalidOperationException($"Type {objectType.Name} does not support index access");
    }

    private void EmitIndexStoreValue(IndexAccessExpression indexAccess, Type objectType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (objectType.IsArray)
        {
            var elementType = objectType.GetElementType()!;
            var indexType = GetExpressionType(indexAccess.Index);
            var useGenericArrayOpcode = objectType.ContainsGenericParameters
                || elementType.IsGenericParameter
                || elementType.ContainsGenericParameters;

            if (indexType == typeof(Range))
            {
                throw new InvalidOperationException("Range-based indexed assignment is not supported");
            }

            if (indexType == typeof(Index))
            {
                var valueLocal = _currentIL.DeclareLocal(elementType);
                var indexLocal = _currentIL.DeclareLocal(typeof(Index));
                var arrayLocal = _currentIL.DeclareLocal(objectType);
                var lengthLocal = _currentIL.DeclareLocal(typeof(int));
                _currentIL.Emit(OpCodes.Stloc, valueLocal);
                _currentIL.Emit(OpCodes.Stloc, indexLocal);
                _currentIL.Emit(OpCodes.Stloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldlen);
                _currentIL.Emit(OpCodes.Conv_I4);
                _currentIL.Emit(OpCodes.Stloc, lengthLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                EmitIndexOffset(indexLocal, lengthLocal);
                _currentIL.Emit(OpCodes.Ldloc, valueLocal);
                if (useGenericArrayOpcode)
                {
                    _currentIL.Emit(OpCodes.Stelem, elementType);
                }
                else
                {
                    EmitArrayElementStore(elementType);
                }
                return;
            }

            if (useGenericArrayOpcode)
            {
                _currentIL.Emit(OpCodes.Stelem, elementType);
            }
            else
            {
                EmitArrayElementStore(elementType);
            }
            return;
        }

        if (objectType is TypeBuilder typeBuilder)
        {
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, "set_Item"), out var setterMethod))
            {
                _currentIL.Emit(OpCodes.Callvirt, setterMethod);
                return;
            }

            throw new InvalidOperationException($"Type {GetTypeKey(typeBuilder)} does not support indexed assignment");
        }

        var reflectionIndexType = GetExpressionType(indexAccess.Index);
        var indexer = objectType.GetDefaultMembers()
            .OfType<PropertyInfo>()
            .FirstOrDefault(p =>
                p.GetIndexParameters().Length == 1 &&
                p.SetMethod != null &&
                AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, reflectionIndexType));

        if (indexer?.SetMethod != null)
        {
            _currentIL.Emit(indexer.SetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, indexer.SetMethod);
            return;
        }

        throw new InvalidOperationException($"Type {objectType.Name} does not support indexed assignment");
    }

    private void EmitArrayElementLoad(Type elementType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (elementType == typeof(int))
            _currentIL.Emit(OpCodes.Ldelem_I4);
        else if (elementType == typeof(long))
            _currentIL.Emit(OpCodes.Ldelem_I8);
        else if (elementType == typeof(bool) || elementType == typeof(byte))
            _currentIL.Emit(OpCodes.Ldelem_U1);
        else if (elementType == typeof(double))
            _currentIL.Emit(OpCodes.Ldelem_R8);
        else if (elementType == typeof(float))
            _currentIL.Emit(OpCodes.Ldelem_R4);
        else if (elementType.IsValueType)
            _currentIL.Emit(OpCodes.Ldelem, elementType);
        else
            _currentIL.Emit(OpCodes.Ldelem_Ref);
    }

    private void EmitArrayElementStore(Type elementType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (elementType == typeof(int))
            _currentIL.Emit(OpCodes.Stelem_I4);
        else if (elementType == typeof(long))
            _currentIL.Emit(OpCodes.Stelem_I8);
        else if (elementType == typeof(bool) || elementType == typeof(byte))
            _currentIL.Emit(OpCodes.Stelem_I1);
        else if (elementType == typeof(double))
            _currentIL.Emit(OpCodes.Stelem_R8);
        else if (elementType == typeof(float))
            _currentIL.Emit(OpCodes.Stelem_R4);
        else if (elementType.IsGenericParameter || elementType.ContainsGenericParameters)
            _currentIL.Emit(OpCodes.Stelem, elementType);
        else if (elementType.IsValueType)
            _currentIL.Emit(OpCodes.Stelem, elementType);
        else
            _currentIL.Emit(OpCodes.Stelem_Ref);
    }

    private void EmitMemberLoadValue(Type objectType, string memberName)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberName), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberName}"), out var getterMethod))
            {
                _currentIL.Emit(OpCodes.Callvirt, getterMethod);
                return;
            }

            throw new InvalidOperationException($"Member {memberName} not found on type {GetTypeKey(typeBuilder)}");
        }

        var property = objectType.GetProperty(memberName);
        if (property?.GetMethod != null)
        {
            _currentIL.Emit(OpCodes.Callvirt, property.GetMethod);
            return;
        }

        var field = objectType.GetField(memberName);
        if (field != null)
        {
            _currentIL.Emit(OpCodes.Ldfld, field);
            return;
        }

        throw new InvalidOperationException($"Member {memberName} not found on type {objectType.Name}");
    }

    private void EmitStaticMemberLoadValue(Type staticType, string memberName)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (staticType is TypeBuilder staticTypeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, memberName), out var staticField))
            {
                _currentIL.Emit(OpCodes.Ldsfld, staticField);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"get_{memberName}"), out var staticGetter))
            {
                _currentIL.Emit(OpCodes.Call, staticGetter);
                return;
            }

            throw new InvalidOperationException($"Static member {memberName} not found on type {GetTypeKey(staticTypeBuilder)}");
        }

        var staticProperty = staticType.GetProperty(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticProperty?.GetMethod != null)
        {
            _currentIL.Emit(OpCodes.Call, staticProperty.GetMethod);
            return;
        }

        var staticFieldInfo = staticType.GetField(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticFieldInfo != null)
        {
            _currentIL.Emit(OpCodes.Ldsfld, staticFieldInfo);
            return;
        }

        throw new InvalidOperationException($"Static member {memberName} not found on type {GetTypeKey(staticType)}");
    }

    private void EmitMemberStoreValue(Type objectType, string memberName)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberName), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{memberName}"), out var setterMethod))
            {
                _currentIL.Emit(OpCodes.Callvirt, setterMethod);
                return;
            }

            throw new InvalidOperationException($"Member {memberName} not found on type {GetTypeKey(typeBuilder)}");
        }

        var property = objectType.GetProperty(memberName);
        if (property?.SetMethod != null)
        {
            _currentIL.Emit(OpCodes.Callvirt, property.SetMethod);
            return;
        }

        var field = objectType.GetField(memberName);
        if (field != null)
        {
            _currentIL.Emit(OpCodes.Stfld, field);
            return;
        }

        throw new InvalidOperationException($"Member {memberName} not found on type {objectType.Name}");
    }

    private void EmitStaticMemberStoreValue(Type staticType, string memberName)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (staticType is TypeBuilder staticTypeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, memberName), out var staticField))
            {
                _currentIL.Emit(OpCodes.Stsfld, staticField);
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"set_{memberName}"), out var staticSetter))
            {
                _currentIL.Emit(OpCodes.Call, staticSetter);
                return;
            }

            throw new InvalidOperationException($"Static member {memberName} not found on type {GetTypeKey(staticTypeBuilder)}");
        }

        var staticProperty = staticType.GetProperty(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticProperty?.SetMethod != null)
        {
            _currentIL.Emit(OpCodes.Call, staticProperty.SetMethod);
            return;
        }

        var staticFieldInfo = staticType.GetField(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticFieldInfo != null)
        {
            _currentIL.Emit(OpCodes.Stsfld, staticFieldInfo);
            return;
        }

        throw new InvalidOperationException($"Static member {memberName} not found on type {GetTypeKey(staticType)}");
    }

    /// <summary>
    /// Emit IL for member access (field or property)
    /// </summary>
    private void EmitMemberAccess(MemberAccessExpression memberAccess)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (memberAccess.IsNullConditional)
        {
            var nonNullMemberAccess = memberAccess with { IsNullConditional = false };
            var receiverType = GetExpressionType(nonNullMemberAccess.Object);
            var resultType = GetMemberAccessType(memberAccess);
            var nonNullValueType = GetMemberAccessType(nonNullMemberAccess);

            EmitExpression(nonNullMemberAccess.Object);
            var objectLocal = _currentIL.DeclareLocal(receiverType);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);

            var hasValueLabel = _currentIL.DefineLabel();
            var endLabel = _currentIL.DefineLabel();

            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            _currentIL.Emit(OpCodes.Brtrue, hasValueLabel);
            EmitDefaultValue(resultType);
            _currentIL.Emit(OpCodes.Br, endLabel);

            _currentIL.MarkLabel(hasValueLabel);
            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            EmitMemberLoadValue(receiverType, nonNullMemberAccess.MemberName);
            if (resultType != nonNullValueType)
            {
                var nullableCtor = resultType.GetConstructor(new[] { nonNullValueType });
                if (nullableCtor == null)
                {
                    throw new InvalidOperationException($"Could not resolve nullable constructor for {resultType}");
                }

                _currentIL.Emit(OpCodes.Newobj, nullableCtor);
            }

            _currentIL.MarkLabel(endLabel);
            return;
        }

        if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
        {
            if (staticType is TypeBuilder staticTypeBuilder)
            {
                if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, memberAccess.MemberName), out var staticField))
                {
                    var fieldKey = GetFieldKey(staticTypeBuilder, memberAccess.MemberName);
                    if (_fieldConstants.TryGetValue(fieldKey, out var constantValue) && staticField.FieldType == typeof(string))
                    {
                        EmitConstantValue(constantValue, staticField.FieldType);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldsfld, staticField);
                    }
                    return;
                }

                if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"get_{memberAccess.MemberName}"), out var staticGetter))
                {
                    _currentIL.Emit(OpCodes.Call, staticGetter);
                    return;
                }
            }
            else
            {
                var staticProperty = staticType.GetProperty(
                    memberAccess.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticProperty?.GetMethod != null)
                {
                    _currentIL.Emit(OpCodes.Call, staticProperty.GetMethod);
                    return;
                }

                var staticField = staticType.GetField(
                    memberAccess.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticField != null)
                {
                    if (staticField.IsLiteral && staticField.FieldType == typeof(string))
                    {
                        EmitConstantValue(staticField.GetRawConstantValue(), staticField.FieldType);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldsfld, staticField);
                    }
                    return;
                }
            }

            throw new InvalidOperationException($"Static member {memberAccess.MemberName} not found on type {GetTypeKey(staticType)}");
        }

        // Get the object type
        var objectType = GetExpressionType(memberAccess.Object);
        var useAddressReceiver = IsValueTypeLike(objectType);

        if (useAddressReceiver)
        {
            EmitAddressableExpression(memberAccess.Object, objectType);
        }
        else
        {
            EmitExpression(memberAccess.Object);
        }

        // Check if it's a user-defined type
        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberAccess.MemberName), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                return;
            }

            // Check for property getter
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberAccess.MemberName}"), out var getterMethod))
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Call : OpCodes.Callvirt, getterMethod);
                return;
            }

            throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {GetTypeKey(typeBuilder)}");
        }

        // Try to find a property first
        var property = ResolveRuntimeProperty(
            objectType,
            memberAccess.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (property?.Getter != null)
        {
            _currentIL.Emit(useAddressReceiver || !property.Getter.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, property.Getter);
            return;
        }

        // Try to find a field
        var field = ResolveRuntimeField(
            objectType,
            memberAccess.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (field != null)
        {
            if (field.IsStatic)
            {
                _currentIL.Emit(OpCodes.Ldsfld, field);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldfld, field);
            }
            return;
        }

        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
    }

    /// <summary>
    /// Emit IL for a ternary expression
    /// </summary>
    private void EmitTernaryExpression(TernaryExpression ternary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var elseLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        EmitExpression(ternary.Condition);
        _currentIL.Emit(OpCodes.Brfalse, elseLabel);
        EmitExpression(ternary.ThenExpression);
        _currentIL.Emit(OpCodes.Br, endLabel);
        _currentIL.MarkLabel(elseLabel);
        EmitExpression(ternary.ElseExpression);
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for an array literal
    /// </summary>
    private void EmitArrayLiteral(ArrayLiteralExpression arrayLiteral)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (TryGetCollectionExpressionEmissionType(_expectedExpressionType, out var collectionType, out var collectionElementType)
            && !collectionType.IsArray)
        {
            EmitCollectionExpression(arrayLiteral, collectionType, collectionElementType);
            return;
        }

        var arrayType = GetArrayLiteralType(arrayLiteral);
        var elementType = arrayType.GetElementType() ?? typeof(object);

        if (arrayLiteral.Elements.Any(e => e is SpreadExpression))
        {
            var listType = typeof(List<>).MakeGenericType(elementType);
            var enumerableType = typeof(IEnumerable<>).MakeGenericType(elementType);
            var listCtor = listType.GetConstructor(Type.EmptyTypes);
            var addMethod = listType.GetMethod("Add", new[] { elementType });
            var addRangeMethod = listType.GetMethod("AddRange", new[] { enumerableType });
            var toArrayMethod = listType.GetMethod("ToArray", Type.EmptyTypes);

            if (listCtor == null || addMethod == null || addRangeMethod == null || toArrayMethod == null)
            {
                throw new InvalidOperationException($"Could not resolve spread helpers for array literal element type {elementType}");
            }

            _currentIL.Emit(OpCodes.Newobj, listCtor);
            var listLocal = _currentIL.DeclareLocal(listType);
            _currentIL.Emit(OpCodes.Stloc, listLocal);

            foreach (var element in arrayLiteral.Elements)
            {
                _currentIL.Emit(OpCodes.Ldloc, listLocal);
                if (element is SpreadExpression spread)
                {
                    EmitExpressionWithExpectedType(spread.Expression, enumerableType);
                    _currentIL.Emit(OpCodes.Callvirt, addRangeMethod);
                }
                else
                {
                    EmitExpressionWithExpectedType(element, elementType);
                    _currentIL.Emit(OpCodes.Callvirt, addMethod);
                }
            }

            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            _currentIL.Emit(OpCodes.Callvirt, toArrayMethod);
            return;
        }

        _currentIL.Emit(OpCodes.Ldc_I4, arrayLiteral.Elements.Count);
        _currentIL.Emit(OpCodes.Newarr, elementType);

        for (int i = 0; i < arrayLiteral.Elements.Count; i++)
        {
            var element = arrayLiteral.Elements[i];
            if (element is SpreadExpression)
            {
                throw new NotImplementedException("Spread elements in array literals are not yet supported in IL compiler");
            }

            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Ldc_I4, i);
            EmitExpression(element);
            EmitArrayElementStore(elementType);
        }
    }

    /// <summary>
    /// Emit IL for a tuple expression
    /// </summary>
    private void EmitTupleExpression(TupleExpression tuple)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var tupleType = GetTupleExpressionType(tuple);
        var elementTypes = tuple.Elements.Select(e => GetExpressionType(e.Value)).ToArray();
        var constructor = tupleType.GetConstructor(elementTypes);
        if (constructor == null)
        {
            throw new InvalidOperationException($"Could not resolve tuple constructor for {tupleType}");
        }

        foreach (var element in tuple.Elements)
        {
            EmitExpression(element.Value);
        }

        _currentIL.Emit(OpCodes.Newobj, constructor);
    }

    /// <summary>
    /// Emit IL for a cast expression
    /// </summary>
    private void EmitCastExpression(CastExpression cast)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var targetType = ResolveType(cast.TargetType, _currentGenericParameters);
        var sourceType = GetExpressionType(cast.Expression);
        EmitExpression(cast.Expression);

        if (cast.Kind == CastKind.Safe)
        {
            _currentIL.Emit(OpCodes.Isinst, targetType);
            return;
        }

        EmitValueCoercion(sourceType, targetType, allowExplicitUserDefinedConversions: true);
    }

    /// <summary>
    /// Emit IL for an is expression
    /// </summary>
    private void EmitIsExpression(IsExpression isExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var targetType = ResolveType(isExpr.Type, _currentGenericParameters);
        EmitExpression(isExpr.Expression);
        _currentIL.Emit(OpCodes.Isinst, targetType);

        if (isExpr.VariableName != null)
        {
            if (_locals == null)
            {
                throw new InvalidOperationException("Variable binding in is-expression requires local scope");
            }

            var successLabel = _currentIL.DefineLabel();
            var endLabel = _currentIL.DefineLabel();
            var local = DeclareNamedLocal(isExpr.VariableName, targetType);

            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Brtrue, successLabel);
            _currentIL.Emit(OpCodes.Pop);
            _currentIL.Emit(OpCodes.Ldc_I4_0);
            _currentIL.Emit(OpCodes.Br, endLabel);

            _currentIL.MarkLabel(successLabel);
            _currentIL.Emit(OpCodes.Dup);
            if (IsLiftedIdentifier(isExpr.VariableName))
            {
                EmitStoreLiftedLocalValue(local, targetType, leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, local);
            }
            _currentIL.Emit(OpCodes.Pop);
            _currentIL.Emit(OpCodes.Ldc_I4_1);
            _currentIL.MarkLabel(endLabel);
            return;
        }

        _currentIL.Emit(OpCodes.Ldnull);
        _currentIL.Emit(OpCodes.Cgt_Un);
    }

    private void EmitTypeOfExpression(TypeOfExpression typeOfExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var type = ResolveType(typeOfExpr.Type, _currentGenericParameters);
        _currentIL.Emit(OpCodes.Ldtoken, type);
        var getTypeFromHandle = typeof(Type).GetMethod(nameof(Type.GetTypeFromHandle), new[] { typeof(RuntimeTypeHandle) });
        if (getTypeFromHandle == null)
        {
            throw new InvalidOperationException("Could not resolve Type.GetTypeFromHandle");
        }
        _currentIL.Emit(OpCodes.Call, getTypeFromHandle);
    }

    private void EmitNameofExpression(NameofExpression nameofExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var name = nameofExpr.Target switch
        {
            IdentifierExpression ident => ident.Name,
            MemberAccessExpression member => member.MemberName,
            _ => throw new InvalidOperationException($"nameof does not support target {nameofExpr.Target.GetType().Name}")
        };

        _currentIL.Emit(OpCodes.Ldstr, name);
    }

    private void EmitSizeOfExpression(SizeOfExpression sizeofExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var type = ResolveType(sizeofExpr.Type, _currentGenericParameters);
        _currentIL.Emit(OpCodes.Sizeof, type);
        _currentIL.Emit(OpCodes.Conv_I4);
    }

    /// <summary>
    /// Get the .NET type of an expression (simplified type inference)
    /// </summary>
    private Type GetExpressionType(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression => typeof(int),
            FloatLiteralExpression => typeof(double),
            StringLiteralExpression => typeof(string),
            InterpolatedStringExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            IdentifierExpression ident => GetIdentifierType(ident),
            RangeExpression => typeof(Range),
            UnaryExpression unary => GetUnaryExpressionType(unary),
            BinaryExpression binary => GetBinaryExpressionType(binary),
            ParenthesizedExpression paren => GetExpressionType(paren.Inner),
            AssignmentExpression assignment => GetExpressionType(assignment.Value),
            TupleExpression tuple => GetTupleExpressionType(tuple),
            NewExpression newExpr => newExpr.Type != null
                ? ResolveType(newExpr.Type, _currentGenericParameters)
                : _expectedExpressionType ?? typeof(object),
            WithExpression withExpr => GetExpressionType(withExpr.Target),
            AwaitExpression awaitExpression => GetAwaitResultType(GetExpressionType(awaitExpression.Expression)),
            MemberAccessExpression memberAccess => GetMemberAccessType(memberAccess),
            IndexAccessExpression indexAccess => GetIndexAccessType(indexAccess),
            CallExpression call => GetCallExpressionType(call),
            LambdaExpression lambda => GetLambdaExpressionType(lambda),
            MatchExpression match => GetMatchExpressionType(match),
            TernaryExpression ternary => GetExpressionType(ternary.ThenExpression),
            ArrayLiteralExpression arrayLiteral => GetArrayLiteralType(arrayLiteral),
            CastExpression cast => ResolveType(cast.TargetType, _currentGenericParameters),
            IsExpression => typeof(bool),
            ThisExpression => _currentTypeBuilder ?? typeof(object),
            BaseExpression => _currentTypeBuilder?.BaseType ?? typeof(object),
            ThrowExpression => typeof(void),
            TypeOfExpression => typeof(Type),
            NameofExpression => typeof(string),
            SizeOfExpression => typeof(int),
            SpreadExpression spread => GetExpressionType(spread.Expression),
            DefaultExpression => _expectedExpressionType ?? typeof(object),
            OutVariableDeclarationExpression outVar => outVar.Type != null ? ResolveType(outVar.Type, _currentGenericParameters) : typeof(object),
            CheckedExpression checkedExpr => GetExpressionType(checkedExpr.Expression),
            UncheckedExpression uncheckedExpr => GetExpressionType(uncheckedExpr.Expression),
            _ => typeof(object)
        };
    }

    private Type GetLambdaExpressionType(LambdaExpression lambda)
    {
        GetLambdaSignature(lambda, out var parameterTypes, out var returnType);
        return CreateDelegateType(parameterTypes, returnType);
    }

    private Type GetMatchExpressionType(MatchExpression match)
    {
        if (_expectedExpressionType != null && _expectedExpressionType != typeof(void))
        {
            return _expectedExpressionType;
        }

        if (match.Cases.Count == 0)
        {
            return typeof(object);
        }

        var resultType = GetExpressionType(match.Cases[0].Expression);
        foreach (var matchCase in match.Cases.Skip(1))
        {
            var caseType = GetExpressionType(matchCase.Expression);
            if (caseType == resultType)
            {
                continue;
            }

            if (AreTypesAssignmentCompatible(resultType, caseType))
            {
                continue;
            }

            if (AreTypesAssignmentCompatible(caseType, resultType))
            {
                resultType = caseType;
                continue;
            }

            return typeof(object);
        }

        return resultType;
    }

    /// <summary>
    /// Get the type of an identifier
    /// </summary>
    private Type GetIdentifierType(IdentifierExpression ident)
    {
        if (_locals != null && _locals.TryGetValue(ident.Name, out var local))
        {
            return IsLiftedIdentifier(ident.Name) ? GetStrongBoxValueType(local.LocalType) : local.LocalType;
        }

        if (_parameterTypes != null && _parameterTypes.TryGetValue(ident.Name, out var paramType))
        {
            return paramType;
        }

        if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField))
        {
            return IsLiftedClosureField(ident.Name) ? GetStrongBoxValueType(closureField.FieldType) : closureField.FieldType;
        }

        if (_currentTypeBuilder != null)
        {
            var primaryConstructorField = FindPrimaryConstructorField(_currentTypeBuilder, ident.Name);
            if (primaryConstructorField != null)
            {
                return primaryConstructorField.FieldType;
            }

            var field = FindField(_currentTypeBuilder, ident.Name);
            if (field != null)
            {
                return field.FieldType;
            }
        }

        return typeof(object);
    }

    /// <summary>
    /// Get the type of a binary expression
    /// </summary>
    private Type GetBinaryExpressionType(BinaryExpression binary)
    {
        var operatorMethod = ResolveBinaryOperatorMethod(
            binary.Operator,
            GetExpressionType(binary.Left),
            GetExpressionType(binary.Right));
        if (operatorMethod != null)
        {
            return operatorMethod.ReturnType;
        }

        return binary.Operator switch
        {
            BinaryOperator.Equal or BinaryOperator.NotEqual or
            BinaryOperator.Less or BinaryOperator.LessOrEqual or
            BinaryOperator.Greater or BinaryOperator.GreaterOrEqual or
            BinaryOperator.And or BinaryOperator.Or => typeof(bool),
            BinaryOperator.NullCoalesce => GetExpressionType(binary.Left),
            BinaryOperator.Range => typeof(Range),
            _ => GetExpressionType(binary.Left)
        };
    }

    private Type GetUnaryExpressionType(UnaryExpression unary)
    {
        var operatorMethod = ResolveUnaryOperatorMethod(unary.Operator, GetExpressionType(unary.Operand));
        if (operatorMethod != null)
        {
            return operatorMethod.ReturnType;
        }

        return unary.Operator switch
        {
            UnaryOperator.Not => typeof(bool),
            UnaryOperator.IndexFromEnd => typeof(Index),
            _ => GetExpressionType(unary.Operand)
        };
    }

    private Type GetArrayLiteralType(ArrayLiteralExpression arrayLiteral)
    {
        if (TryGetCollectionExpressionEmissionType(_expectedExpressionType, out var collectionType, out _))
        {
            return collectionType;
        }

        if (arrayLiteral.Elements.Count == 0)
        {
            return typeof(object[]);
        }

        var firstType = arrayLiteral.Elements[0] is SpreadExpression firstSpread
            ? GetSpreadElementType(firstSpread)
            : GetExpressionType(arrayLiteral.Elements[0]);

        if (arrayLiteral.Elements.All(e =>
                (e is SpreadExpression spread ? GetSpreadElementType(spread) : GetExpressionType(e)) == firstType))
        {
            return firstType.MakeArrayType();
        }

        return typeof(object[]);
    }

    private Type GetTupleExpressionType(TupleExpression tuple)
    {
        var elementTypes = tuple.Elements.Select(e => GetExpressionType(e.Value)).ToArray();

        return elementTypes.Length switch
        {
            1 => typeof(ValueTuple<>).MakeGenericType(elementTypes),
            2 => typeof(ValueTuple<,>).MakeGenericType(elementTypes),
            3 => typeof(ValueTuple<,,>).MakeGenericType(elementTypes),
            4 => typeof(ValueTuple<,,,>).MakeGenericType(elementTypes),
            5 => typeof(ValueTuple<,,,,>).MakeGenericType(elementTypes),
            6 => typeof(ValueTuple<,,,,,>).MakeGenericType(elementTypes),
            7 => typeof(ValueTuple<,,,,,,>).MakeGenericType(elementTypes),
            _ => typeof(object)
        };
    }

    /// <summary>
    /// Get the type of a member access expression
    /// </summary>
    private Type GetMemberAccessType(MemberAccessExpression memberAccess)
    {
        var unwrapNullConditional = memberAccess.IsNullConditional
            ? memberAccess with { IsNullConditional = false }
            : memberAccess;

        if (memberAccess.IsNullConditional)
        {
            return GetNullConditionalResultType(GetMemberAccessType(unwrapNullConditional));
        }

        if (TryResolveStaticContainer(unwrapNullConditional.Object, out var staticType))
        {
            if (staticType is TypeBuilder staticTypeBuilder)
            {
                if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, unwrapNullConditional.MemberName), out var staticField))
                {
                    return staticField.FieldType;
                }

                if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"get_{unwrapNullConditional.MemberName}"), out var staticGetter))
                {
                    return staticGetter.ReturnType;
                }
            }
            else
            {
                var staticProperty = staticType.GetProperty(
                    unwrapNullConditional.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticProperty != null)
                {
                    return staticProperty.PropertyType;
                }

                var staticField = staticType.GetField(
                    unwrapNullConditional.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticField != null)
                {
                    return staticField.FieldType;
                }
            }

            return typeof(object);
        }

        var objectType = GetExpressionType(unwrapNullConditional.Object);

        // Check user-defined types first
        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, unwrapNullConditional.MemberName), out var fieldBuilder))
            {
                return fieldBuilder.FieldType;
            }

            // Check for property via getter
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{unwrapNullConditional.MemberName}"), out var getterMethod))
            {
                return getterMethod.ReturnType;
            }

            return typeof(object);
        }

        // Try to find a property
        var property = ResolveRuntimeProperty(
            objectType,
            unwrapNullConditional.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (property != null)
        {
            return property.PropertyType;
        }

        // Try to find a field
        var field = ResolveRuntimeField(
            objectType,
            unwrapNullConditional.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (field != null)
        {
            return field.FieldType;
        }

        return typeof(object);
    }

    private Type GetIndexAccessType(IndexAccessExpression indexAccess)
    {
        var unwrapNullConditional = indexAccess.IsNullConditional
            ? indexAccess with { IsNullConditional = false }
            : indexAccess;

        if (indexAccess.IsNullConditional)
        {
            return GetNullConditionalResultType(GetIndexAccessType(unwrapNullConditional));
        }

        var objectType = GetExpressionType(unwrapNullConditional.Object);
        var indexType = GetExpressionType(unwrapNullConditional.Index);
        if (objectType.IsArray)
        {
            return indexType == typeof(Range)
                ? objectType
                : objectType.GetElementType() ?? typeof(object);
        }

        if (objectType == typeof(string))
        {
            return indexType == typeof(Range) ? typeof(string) : typeof(char);
        }

        if (objectType is TypeBuilder typeBuilder)
        {
            if (_indexers.TryGetValue(GetIndexerKey(typeBuilder), out var indexerProperty))
            {
                return indexerProperty.PropertyType;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Item"), out var getterMethod))
            {
                return getterMethod.ReturnType;
            }

            return typeof(object);
        }

        var indexer = objectType.GetDefaultMembers()
            .OfType<PropertyInfo>()
            .FirstOrDefault(p =>
                p.GetIndexParameters().Length == 1 &&
                AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, indexType));

        return indexer?.PropertyType ?? typeof(object);
    }

    /// <summary>
    /// Get the type of a call expression
    /// </summary>
    private Type GetCallExpressionType(CallExpression call)
    {
        var calleeType = GetExpressionType(call.Callee);
        if (call.Callee is not MemberAccessExpression &&
            TryGetDelegateInvokeMethod(calleeType, out var delegateInvokeMethod) &&
            delegateInvokeMethod != null)
        {
            return GetDelegateInvokeReturnType(calleeType, delegateInvokeMethod);
        }

        // Handle instance method calls
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
            {
                if (staticType is TypeBuilder staticTypeBuilder)
                {
                    var boundStaticCall = BindDeclaredMethodCall(
                        GetMethodKey(staticTypeBuilder, memberAccess.MemberName),
                        call,
                    predicate: overload => overload.Builder.IsStatic);
                if (boundStaticCall != null)
                {
                    return GetBoundDeclaredMethodReturnType(boundStaticCall);
                }

                    if (_declaredMethodOverloads.ContainsKey(GetMethodKey(staticTypeBuilder, memberAccess.MemberName)))
                    {
                        return typeof(object);
                    }

                    if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, memberAccess.MemberName), out var staticMethodBuilder))
                    {
                        return staticMethodBuilder.ReturnType;
                    }

                    return typeof(object);
                }

                var boundStaticRuntimeCall = BindRuntimeMethodCall(
                    staticType,
                    memberAccess.MemberName,
                    call,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                return boundStaticRuntimeCall?.Method.ReturnType ?? typeof(object);
            }

            var objectType = GetExpressionType(memberAccess.Object);

            // Check user-defined methods first
            if (TryGetUserTypeDefinition(objectType, out var typeBuilder))
            {
                var boundInstanceCall = BindDeclaredMethodCall(
                    GetMethodKey(typeBuilder, memberAccess.MemberName),
                    call,
                    predicate: overload => !overload.Builder.IsStatic);
                if (boundInstanceCall != null)
                {
                    return GetBoundDeclaredMethodReturnType(boundInstanceCall);
                }

                if (_declaredMethodOverloads.ContainsKey(GetMethodKey(typeBuilder, memberAccess.MemberName)))
                {
                    return typeof(object);
                }

                if (_methods.TryGetValue(GetMethodKey(typeBuilder, memberAccess.MemberName), out var methodBuilder))
                {
                    return methodBuilder.ReturnType;
                }

                return typeof(object);
            }

            // Use reflection for built-in types
            if (objectType.IsGenericParameter)
            {
                foreach (var constraint in objectType.GetGenericParameterConstraints())
                {
                    var constrainedMethod = BindRuntimeMethodCall(
                        constraint,
                        memberAccess.MemberName,
                        call,
                        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                    if (constrainedMethod != null)
                    {
                        return constrainedMethod.Method.ReturnType;
                    }
                }

                return typeof(object);
            }

            var method = BindRuntimeMethodCall(
                objectType,
                memberAccess.MemberName,
                call,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (method != null)
            {
                return method.Method.ReturnType;
            }

            var boundExtensionCall = BindDeclaredMethodCall(
                memberAccess.MemberName,
                call,
                implicitReceiver: memberAccess.Object,
                targetType: null,
                predicate: overload => overload.Builder.IsStatic
                    && overload.Declaration.Parameters.Count > 0
                    && overload.Declaration.Parameters[0].IsThis);
            if (boundExtensionCall != null)
            {
                return GetBoundDeclaredMethodReturnType(boundExtensionCall);
            }

            return typeof(object);
        }

        // Handle static/global function calls
        if (call.Callee is IdentifierExpression ident)
        {
            var boundGenericLocalCall = BindGenericLocalFunctionCall(ident, call);
            if (boundGenericLocalCall != null)
            {
                return GetBoundDeclaredMethodReturnType(boundGenericLocalCall);
            }

            if (_localFunctionDeclarations != null
                && _localFunctionDeclarations.TryGetValue(ident.Name, out var localFunctionDeclaration)
                && localFunctionDeclaration.TypeParameters is { Count: > 0 })
            {
                return GetGenericLocalFunctionCallReturnType(localFunctionDeclaration, call);
            }

            var boundTopLevelCall = BindDeclaredMethodCall(
                ident.Name,
                call,
                targetType: null,
                predicate: overload => overload.Builder.IsStatic);
            if (boundTopLevelCall != null)
            {
                return GetBoundDeclaredMethodReturnType(boundTopLevelCall);
            }

            if (_declaredMethodOverloads.ContainsKey(ident.Name))
            {
                return typeof(object);
            }

            if (_methods.TryGetValue(ident.Name, out var methodBuilder))
            {
                return methodBuilder.ReturnType;
            }
        }

        return typeof(object);
    }

    private Type GetBoundDeclaredMethodReturnType(BoundDeclaredMethodCall boundCall)
    {
        var declaredReturnType = boundCall.Declaration.ReturnType;
        if (declaredReturnType == null
            || boundCall.Declaration.TypeParameters is not { Count: > 0 }
            || boundCall.TypeArguments == null
            || boundCall.TypeArguments.Count != boundCall.Declaration.TypeParameters.Count)
        {
            return boundCall.Method.ReturnType;
        }

        var substitutions = new Dictionary<string, Type>(StringComparer.Ordinal);
        for (int i = 0; i < boundCall.Declaration.TypeParameters.Count; i++)
        {
            substitutions[boundCall.Declaration.TypeParameters[i].Name] = boundCall.TypeArguments[i];
        }

        return ResolveType(declaredReturnType, substitutions);
    }

    /// <summary>
    /// Resolve a type reference to a System.Type
    /// </summary>
    private Type ResolveType(TypeReference typeRef)
    {
        return ResolveType(typeRef, (GenericTypeParameterBuilder[]?)null);
    }

    private Type ResolveType(TypeReference typeRef, IReadOnlyDictionary<string, Type> genericTypeArguments)
    {
        if (typeRef is SimpleTypeReference simpleType && genericTypeArguments.TryGetValue(simpleType.Name, out var substitutedType))
        {
            return substitutedType;
        }

        if (typeRef is GenericTypeReference genericType)
        {
            var baseType = ResolveGenericTypeDefinition(genericType.Name, genericType.TypeArguments.Count);
            if (baseType == null)
            {
                return typeof(object);
            }

            var typeArgs = genericType.TypeArguments
                .Select(typeArgument => ResolveType(typeArgument, genericTypeArguments))
                .ToArray();
            return baseType.MakeGenericType(typeArgs);
        }

        if (typeRef is ArrayTypeReference arrayType)
        {
            return ResolveType(arrayType.ElementType, genericTypeArguments).MakeArrayType();
        }

        if (typeRef is NullableTypeReference nullableType)
        {
            var innerType = ResolveType(nullableType.InnerType, genericTypeArguments);
            return innerType.IsValueType
                ? typeof(Nullable<>).MakeGenericType(innerType)
                : innerType;
        }

        if (typeRef is TupleTypeReference tupleType)
        {
            var elementTypes = tupleType.Elements
                .Select(element => ResolveType(element.Type, genericTypeArguments))
                .ToArray();

            return elementTypes.Length switch
            {
                1 => typeof(ValueTuple<>).MakeGenericType(elementTypes),
                2 => typeof(ValueTuple<,>).MakeGenericType(elementTypes),
                3 => typeof(ValueTuple<,,>).MakeGenericType(elementTypes),
                4 => typeof(ValueTuple<,,,>).MakeGenericType(elementTypes),
                5 => typeof(ValueTuple<,,,,>).MakeGenericType(elementTypes),
                6 => typeof(ValueTuple<,,,,,>).MakeGenericType(elementTypes),
                7 => typeof(ValueTuple<,,,,,,>).MakeGenericType(elementTypes),
                _ => typeof(object)
            };
        }

        if (typeRef is FunctionTypeReference functionType)
        {
            var parameterTypes = functionType.ParameterTypes
                .Select(parameter => ResolveType(parameter, genericTypeArguments))
                .ToArray();
            var returnType = ResolveType(functionType.ReturnType, genericTypeArguments);
            return CreateDelegateType(parameterTypes, returnType);
        }

        return ResolveType(typeRef, _currentGenericParameters);
    }

    /// <summary>
    /// Resolve a type reference to a System.Type, with optional generic parameters
    /// </summary>
    private Type ResolveType(TypeReference typeRef, GenericTypeParameterBuilder[]? genericParameters)
    {
        if (typeRef is SimpleTypeReference simpleType)
        {
            // Check for generic type parameters first
            if (genericParameters != null)
            {
                var genericParam = genericParameters.FirstOrDefault(gp => gp.Name == simpleType.Name);
                if (genericParam != null)
                    return genericParam;
            }

            if (_typeAliases.TryGetValue(simpleType.Name, out var aliasedType))
            {
                return ResolveType(aliasedType, genericParameters);
            }

            if (_stringEnumContainers.ContainsKey(simpleType.Name))
            {
                return typeof(string);
            }

            // Check for built-in types
            var builtInType = simpleType.Name switch
            {
                "byte" => typeof(byte),
                "sbyte" => typeof(sbyte),
                "short" => typeof(short),
                "ushort" => typeof(ushort),
                "int" => typeof(int),
                "uint" => typeof(uint),
                "long" => typeof(long),
                "ulong" => typeof(ulong),
                "float" => typeof(float),
                "double" => typeof(double),
                "decimal" => typeof(decimal),
                "char" => typeof(char),
                "bool" => typeof(bool),
                "string" => typeof(string),
                "void" => typeof(void),
                "object" => typeof(object),
                _ => null
            };

            if (builtInType != null)
                return builtInType;

            // Check for user-defined types
            if (_types.TryGetValue(simpleType.Name, out var typeBuilder))
            {
                return typeBuilder;
            }

            if (_enumTypes.TryGetValue(simpleType.Name, out var enumType))
            {
                return enumType;
            }

            if (TryEnsureUserTypeDeclared(simpleType.Name))
            {
                if (_stringEnumContainers.ContainsKey(simpleType.Name))
                {
                    return typeof(string);
                }

                if (_types.TryGetValue(simpleType.Name, out typeBuilder))
                {
                    return typeBuilder;
                }

                if (_enumTypes.TryGetValue(simpleType.Name, out enumType))
                {
                    return enumType;
                }
            }

            var externalType = ResolveExternalType(simpleType.Name);
            if (externalType != null)
            {
                return externalType;
            }

            // Default to object for unknown types
            return typeof(object);
        }

        if (typeRef is GenericTypeReference genericType)
        {
            var baseType = ResolveGenericTypeDefinition(genericType.Name, genericType.TypeArguments.Count);
            if (baseType == null)
            {
                // Unknown generic type, default to object
                return typeof(object);
            }

            // Resolve type arguments
            var typeArgs = genericType.TypeArguments
                .Select(ta => ResolveType(ta, genericParameters))
                .ToArray();

            // Make the generic type
            return baseType.MakeGenericType(typeArgs);
        }

        if (typeRef is ArrayTypeReference arrayType)
        {
            return ResolveType(arrayType.ElementType, genericParameters).MakeArrayType();
        }

        if (typeRef is NullableTypeReference nullableType)
        {
            var innerType = ResolveType(nullableType.InnerType, genericParameters);
            return innerType.IsValueType
                ? typeof(Nullable<>).MakeGenericType(innerType)
                : innerType;
        }

        if (typeRef is TupleTypeReference tupleType)
        {
            var elementTypes = tupleType.Elements
                .Select(e => ResolveType(e.Type, genericParameters))
                .ToArray();

            return elementTypes.Length switch
            {
                1 => typeof(ValueTuple<>).MakeGenericType(elementTypes),
                2 => typeof(ValueTuple<,>).MakeGenericType(elementTypes),
                3 => typeof(ValueTuple<,,>).MakeGenericType(elementTypes),
                4 => typeof(ValueTuple<,,,>).MakeGenericType(elementTypes),
                5 => typeof(ValueTuple<,,,,>).MakeGenericType(elementTypes),
                6 => typeof(ValueTuple<,,,,,>).MakeGenericType(elementTypes),
                7 => typeof(ValueTuple<,,,,,,>).MakeGenericType(elementTypes),
                _ => typeof(object)
            };
        }

        if (typeRef is FunctionTypeReference functionType)
        {
            var parameterTypes = functionType.ParameterTypes
                .Select(p => ResolveType(p, genericParameters))
                .ToArray();
            var returnType = ResolveType(functionType.ReturnType, genericParameters);
            return CreateDelegateType(parameterTypes, returnType);
        }

        return typeof(object);
    }

    private bool TryEnsureUserTypeDeclared(string name)
    {
        if (_moduleBuilder == null)
        {
            return false;
        }

        if (_types.ContainsKey(name) || _enumTypes.ContainsKey(name) || _stringEnumContainers.ContainsKey(name))
        {
            return true;
        }

        var topLevelName = name.Split('.', 2)[0];
        if (_types.ContainsKey(topLevelName) || _enumTypes.ContainsKey(topLevelName) || _stringEnumContainers.ContainsKey(topLevelName))
        {
            return true;
        }

        if (!_typesBeingDeclared.Add(topLevelName))
        {
            return false;
        }

        try
        {
            var declaration = _compilationUnit.Declarations.FirstOrDefault(candidate => GetDeclaredTypeName(candidate) == topLevelName);
            if (declaration == null)
            {
                return false;
            }

            switch (declaration)
            {
                case ClassDeclaration classDecl:
                    DeclareClass(_moduleBuilder, classDecl);
                    break;
                case StructDeclaration structDecl:
                    DeclareStruct(_moduleBuilder, structDecl);
                    break;
                case RecordDeclaration recordDecl:
                    DeclareRecord(_moduleBuilder, recordDecl);
                    break;
                case InterfaceDeclaration interfaceDecl:
                    DeclareInterface(_moduleBuilder, interfaceDecl);
                    break;
                case EnumDeclaration enumDecl:
                    DeclareEnum(_moduleBuilder, enumDecl);
                    break;
                case UnionDeclaration unionDecl:
                    DeclareUnion(_moduleBuilder, unionDecl);
                    break;
                case NewtypeDeclaration newtypeDecl:
                    DeclareRecord(_moduleBuilder, CreateSyntheticNewtypeRecord(newtypeDecl));
                    break;
                default:
                    return false;
            }

            return _types.ContainsKey(name)
                || _types.ContainsKey(topLevelName)
                || _enumTypes.ContainsKey(name)
                || _enumTypes.ContainsKey(topLevelName)
                || _stringEnumContainers.ContainsKey(name)
                || _stringEnumContainers.ContainsKey(topLevelName);
        }
        finally
        {
            _typesBeingDeclared.Remove(topLevelName);
        }
    }

    private static string? GetDeclaredTypeName(Declaration declaration)
    {
        return declaration switch
        {
            ClassDeclaration classDecl => classDecl.Name,
            StructDeclaration structDecl => structDecl.Name,
            RecordDeclaration recordDecl => recordDecl.Name,
            InterfaceDeclaration interfaceDecl => interfaceDecl.Name,
            EnumDeclaration enumDecl => enumDecl.Name,
            UnionDeclaration unionDecl => unionDecl.Name,
            NewtypeDeclaration newtypeDecl => newtypeDecl.Name,
            _ => null
        };
    }

    private Type? ResolveGenericTypeDefinition(string typeName, int arity)
    {
        Type? baseType = null;

        if (typeName == "Func")
        {
            baseType = typeof(Func<>).Assembly.GetType($"System.Func`{arity}");
        }
        else if (typeName == "Action")
        {
            baseType = typeof(Action).Assembly.GetType($"System.Action`{arity}");
        }

        baseType ??= (typeName, arity) switch
        {
            ("List", 1) => typeof(List<>),
            ("HashSet", 1) => typeof(HashSet<>),
            ("Queue", 1) => typeof(Queue<>),
            ("Stack", 1) => typeof(Stack<>),
            ("LinkedList", 1) => typeof(LinkedList<>),
            ("SortedSet", 1) => typeof(SortedSet<>),
            ("IEnumerable", 1) => typeof(IEnumerable<>),
            ("ICollection", 1) => typeof(ICollection<>),
            ("IList", 1) => typeof(IList<>),
            ("IReadOnlyCollection", 1) => typeof(IReadOnlyCollection<>),
            ("IReadOnlyList", 1) => typeof(IReadOnlyList<>),
            ("ISet", 1) => typeof(ISet<>),
            ("IAsyncEnumerable", 1) => typeof(IAsyncEnumerable<>),
            ("IAsyncEnumerator", 1) => typeof(IAsyncEnumerator<>),
            ("IComparable", 1) => typeof(IComparable<>),
            ("Task", 1) => typeof(System.Threading.Tasks.Task<>),
            ("ValueTask", 1) => typeof(System.Threading.Tasks.ValueTask<>),
            ("Dictionary", 2) => typeof(Dictionary<,>),
            ("SortedDictionary", 2) => typeof(SortedDictionary<,>),
            ("SortedList", 2) => typeof(SortedList<,>),
            ("IDictionary", 2) => typeof(IDictionary<,>),
            ("IReadOnlyDictionary", 2) => typeof(IReadOnlyDictionary<,>),
            ("KeyValuePair", 2) => typeof(KeyValuePair<,>),
            _ => null
        };

        if (baseType == null && TryEnsureUserTypeDeclared(typeName) && _types.TryGetValue(typeName, out var typeBuilder))
        {
            baseType = typeBuilder;
        }

        return baseType ?? ResolveExternalGenericType(typeName, arity);
    }

    private Type? ResolveExternalGenericType(string typeName, int arity)
    {
        var metadataName = typeName.Contains('`', StringComparison.Ordinal)
            ? typeName
            : $"{typeName}`{arity}";
        var candidates = new List<string>();

        if (typeName.Contains('.'))
        {
            candidates.Add(metadataName);
        }
        else
        {
            candidates.Add(metadataName);
            candidates.Add($"System.{metadataName}");

            foreach (var import in _compilationUnit.Imports.Where(i => i.Alias == null))
            {
                candidates.Add($"{import.Namespace}.{metadataName}");
            }
        }

        foreach (var candidate in candidates.Distinct(StringComparer.Ordinal))
        {
            var resolved = Type.GetType(candidate, throwOnError: false);
            if (resolved != null && IsMatchingGenericTypeDefinition(resolved, typeName, arity))
            {
                return resolved;
            }

            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                resolved = assembly.GetType(candidate, throwOnError: false, ignoreCase: false);
                if (resolved != null && IsMatchingGenericTypeDefinition(resolved, typeName, arity))
                {
                    return resolved;
                }
            }
        }

        if (typeName.Contains('.'))
        {
            return null;
        }

        Type? match = null;
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            Type[] types;
            try
            {
                types = assembly.GetTypes()
                    .Where(type => IsMatchingGenericTypeDefinition(type, typeName, arity))
                    .Take(2)
                    .ToArray();
            }
            catch (ReflectionTypeLoadException ex)
            {
                types = ex.Types
                    .Where(type => type != null && IsMatchingGenericTypeDefinition(type, typeName, arity))
                    .Take(2)
                    .Cast<Type>()
                    .ToArray();
            }

            if (types.Length == 1)
            {
                if (match != null && match != types[0])
                {
                    return null;
                }

                match = types[0];
            }
        }

        return match;
    }

    private static bool IsMatchingGenericTypeDefinition(Type type, string typeName, int arity)
    {
        if (!type.IsGenericTypeDefinition || type.GetGenericArguments().Length != arity)
        {
            return false;
        }

        var metadataName = type.Name;
        var tickIndex = metadataName.IndexOf('`');
        if (tickIndex >= 0)
        {
            metadataName = metadataName[..tickIndex];
        }

        if (typeName.Contains('.'))
        {
            return string.Equals(type.FullName?.Split('`')[0], typeName, StringComparison.Ordinal)
                || string.Equals(type.FullName, $"{typeName}`{arity}", StringComparison.Ordinal);
        }

        return string.Equals(metadataName, typeName, StringComparison.Ordinal);
    }

    private Type? ResolveExternalType(string typeName)
    {
        var candidates = new List<string>();
        if (typeName.Contains('.'))
        {
            candidates.Add(typeName);
        }
        else
        {
            candidates.Add(typeName);
            candidates.Add($"System.{typeName}");

            foreach (var import in _compilationUnit.Imports.Where(i => i.Alias == null))
            {
                candidates.Add($"{import.Namespace}.{typeName}");
            }
        }

        foreach (var candidate in candidates.Distinct(StringComparer.Ordinal))
        {
            var resolved = Type.GetType(candidate, throwOnError: false);
            if (resolved != null)
            {
                return resolved;
            }

            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                resolved = assembly.GetType(candidate, throwOnError: false, ignoreCase: false);
                if (resolved != null)
                {
                    return resolved;
                }
            }
        }

        if (!typeName.Contains('.'))
        {
            Type? match = null;
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type[] types;
                try
                {
                    types = assembly.GetTypes().Where(t => t.Name == typeName).Take(2).ToArray();
                }
                catch (ReflectionTypeLoadException ex)
                {
                    types = ex.Types.Where(t => t != null && t.Name == typeName).Take(2).Cast<Type>().ToArray();
                }

                if (types.Length == 1)
                {
                    if (match != null && match != types[0])
                    {
                        return null;
                    }

                    match = types[0];
                }
            }

            if (match != null)
            {
                return match;
            }
        }

        return null;
    }

    /// <summary>
    /// Apply generic constraints to a generic type parameter
    /// </summary>
    private void ApplyGenericConstraints(
        GenericTypeParameterBuilder typeParam,
        GenericConstraint constraint,
        GenericTypeParameterBuilder[]? genericParameters)
    {
        var interfaceConstraints = new List<Type>();
        Type? baseClassConstraint = null;
        var attributes = GenericParameterAttributes.None;

        if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Class))
        {
            attributes |= GenericParameterAttributes.ReferenceTypeConstraint;
        }

        if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Struct))
        {
            attributes |= GenericParameterAttributes.NotNullableValueTypeConstraint
                | GenericParameterAttributes.DefaultConstructorConstraint;
        }
        else if (constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.New))
        {
            attributes |= GenericParameterAttributes.DefaultConstructorConstraint;
        }

        foreach (var typeConstraint in constraint.Constraints)
        {
            var constraintType = ResolveType(typeConstraint, genericParameters);

            if (constraintType.IsClass)
            {
                // Base class constraint (can only have one)
                baseClassConstraint = constraintType;
            }
            else if (constraintType.IsInterface)
            {
                // Interface constraint (can have multiple)
                interfaceConstraints.Add(constraintType);
            }
        }

        if (attributes != GenericParameterAttributes.None)
        {
            typeParam.SetGenericParameterAttributes(attributes);
        }

        // Set base class constraint
        if (baseClassConstraint != null)
        {
            typeParam.SetBaseTypeConstraint(baseClassConstraint);
        }

        // Set interface constraints
        if (interfaceConstraints.Count > 0)
        {
            typeParam.SetInterfaceConstraints(interfaceConstraints.ToArray());
        }
    }

    /// <summary>
    /// Declare a class type (first pass)
    /// </summary>
    private void DeclareClass(ModuleBuilder moduleBuilder, ClassDeclaration classDecl)
    {
        if (_types.ContainsKey(classDecl.Name))
        {
            return;
        }

        var typeAttributes = GetTypeVisibilityAttributes(classDecl.Modifiers) | TypeAttributes.Class;

        if (classDecl.Modifiers.HasFlag(Modifiers.Abstract))
            typeAttributes |= TypeAttributes.Abstract;
        if (classDecl.Modifiers.HasFlag(Modifiers.Sealed))
            typeAttributes |= TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            classDecl.Name,
            typeAttributes);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, classDecl.Attributes);

        RegisterType(classDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, classDecl.TypeParameters);

        var allBaseTypes = new List<Type>();
        if (classDecl.BaseClass != null)
        {
            allBaseTypes.Add(ResolveType(classDecl.BaseClass, genericParameters));
        }

        if (classDecl.Interfaces != null)
        {
            allBaseTypes.AddRange(classDecl.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)));
        }

        Type? baseType = null;
        foreach (var candidateType in allBaseTypes)
        {
            if (candidateType.IsInterface)
            {
                typeBuilder.AddInterfaceImplementation(candidateType);
            }
            else if (candidateType.IsClass)
            {
                if (baseType != null)
                {
                    throw new InvalidOperationException($"Class {classDecl.Name} cannot have multiple base classes");
                }

                baseType = candidateType;
            }
        }

        if (baseType != null)
        {
            typeBuilder.SetParent(baseType);
        }
    }

    /// <summary>
    /// Declare a struct type (first pass)
    /// </summary>
    private void DeclareStruct(ModuleBuilder moduleBuilder, StructDeclaration structDecl)
    {
        if (_types.ContainsKey(structDecl.Name))
        {
            return;
        }

        var typeAttributes = GetTypeVisibilityAttributes(structDecl.Modifiers) | TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            structDecl.Name,
            typeAttributes,
            typeof(ValueType));
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, structDecl.Attributes);

        RegisterType(structDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, structDecl.TypeParameters);

        if (structDecl.Interfaces != null)
        {
            foreach (var interfaceType in structDecl.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                typeBuilder.AddInterfaceImplementation(interfaceType);
            }
        }
    }

    /// <summary>
    /// Declare an interface type (first pass)
    /// </summary>
    private void DeclareInterface(ModuleBuilder moduleBuilder, InterfaceDeclaration interfaceDecl)
    {
        if (_types.ContainsKey(interfaceDecl.Name))
        {
            return;
        }

        // Skip duck interfaces - they are type-erased
        if (interfaceDecl.IsDuckInterface)
            return;

        var typeAttributes = GetTypeVisibilityAttributes(interfaceDecl.Modifiers) | TypeAttributes.Interface | TypeAttributes.Abstract;

        var typeBuilder = moduleBuilder.DefineType(
            interfaceDecl.Name,
            typeAttributes);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, interfaceDecl.Attributes);

        RegisterType(interfaceDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, interfaceDecl.TypeParameters);

        if (interfaceDecl.BaseInterfaces != null)
        {
            foreach (var baseInterface in interfaceDecl.BaseInterfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                typeBuilder.AddInterfaceImplementation(baseInterface);
            }
        }
    }

    /// <summary>
    /// Declare an enum type or string-enum container (first pass)
    /// </summary>
    private void DeclareEnum(ModuleBuilder moduleBuilder, EnumDeclaration enumDecl)
    {
        if (_enumTypes.ContainsKey(enumDecl.Name) || _stringEnumContainers.ContainsKey(enumDecl.Name))
        {
            return;
        }

        if (enumDecl.Type == EnumType.String)
        {
            var typeBuilder = moduleBuilder.DefineType(
                enumDecl.Name,
                GetTypeVisibilityAttributes(enumDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Abstract | TypeAttributes.Sealed);

            RegisterStringEnumContainer(enumDecl.Name, typeBuilder);

            foreach (var member in enumDecl.Members)
            {
                var fieldBuilder = typeBuilder.DefineField(
                    member.Name,
                    typeof(string),
                    FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal | FieldAttributes.HasDefault);

                var constantValue = member.Value is StringLiteralExpression stringLiteral
                    ? stringLiteral.Value.Trim('"')
                    : member.Name;
                fieldBuilder.SetConstant(constantValue);
                _fields[GetFieldKey(typeBuilder, member.Name)] = fieldBuilder;
                _fieldConstants[GetFieldKey(typeBuilder, member.Name)] = constantValue;
            }

            return;
        }

        var enumBuilder = moduleBuilder.DefineEnum(
            enumDecl.Name,
            GetTypeVisibilityAttributes(enumDecl.Modifiers),
            typeof(int));
        ApplyCustomAttributes(enumBuilder.SetCustomAttribute, enumDecl.Attributes);

        _enumTypes[enumDecl.Name] = enumBuilder;

        var nextValue = 0;
        foreach (var member in enumDecl.Members)
        {
            var constantValue = member.Value switch
            {
                IntLiteralExpression intLiteral => int.Parse(intLiteral.Value),
                _ => nextValue
            };

            var fieldBuilder = enumBuilder.DefineLiteral(member.Name, constantValue);
            _fields[$"{enumDecl.Name}.{member.Name}"] = fieldBuilder;
            _fieldConstants[$"{enumDecl.Name}.{member.Name}"] = constantValue;
            nextValue = constantValue + 1;
        }
    }

    /// <summary>
    /// Declare a union base type and its case types (first pass)
    /// </summary>
    private void DeclareUnion(ModuleBuilder moduleBuilder, UnionDeclaration unionDecl)
    {
        if (_types.ContainsKey(unionDecl.Name))
        {
            return;
        }

        var unionType = moduleBuilder.DefineType(
            unionDecl.Name,
            GetTypeVisibilityAttributes(unionDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Abstract);
        ApplyCustomAttributes(unionType.SetCustomAttribute, unionDecl.Attributes);
        RegisterType(unionDecl.Name, unionType);
        var unionCtor = unionType.DefineConstructor(
            MethodAttributes.Family,
            CallingConventions.Standard,
            Type.EmptyTypes);
        _constructors[GetConstructorKey(unionType)] = unionCtor;

        foreach (var unionCase in unionDecl.Cases)
        {
            var caseType = unionType.DefineNestedType(
                unionCase.Name,
                TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed,
                unionType);

            var caseKey = $"{unionDecl.Name}.{unionCase.Name}";
            RegisterType(caseKey, caseType);
            var caseCtor = caseType.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);
            _constructors[GetConstructorKey(caseType)] = caseCtor;

            if (unionCase.Properties == null)
            {
                continue;
            }

            foreach (var property in unionCase.Properties)
            {
                var fieldType = ResolveType(property.Type);
                var fieldBuilder = caseType.DefineField(
                    property.Name,
                    fieldType,
                    FieldAttributes.Public);
                _fields[GetFieldKey(caseType, property.Name)] = fieldBuilder;
            }
        }
    }

    private void EmitUnionBodies(UnionDeclaration unionDecl)
    {
        if (!_types.TryGetValue(unionDecl.Name, out var unionType))
        {
            throw new InvalidOperationException($"Union {unionDecl.Name} not declared");
        }

        if (_constructors.TryGetValue(GetConstructorKey(unionType), out var unionCtor))
        {
            var il = unionCtor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0);
            var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
            if (objectCtor != null)
            {
                il.Emit(OpCodes.Call, objectCtor);
            }
            il.Emit(OpCodes.Ret);
        }

        foreach (var unionCase in unionDecl.Cases)
        {
            var caseKey = $"{unionDecl.Name}.{unionCase.Name}";
            if (!_types.TryGetValue(caseKey, out var caseType))
            {
                throw new InvalidOperationException($"Union case {caseKey} not declared");
            }

            if (_constructors.TryGetValue(GetConstructorKey(caseType), out var caseCtor))
            {
                var il = caseCtor.GetILGenerator();
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Call, unionCtor);
                il.Emit(OpCodes.Ret);
            }
        }
    }

    private static RecordDeclaration CreateSyntheticNewtypeRecord(NewtypeDeclaration newtypeDecl)
    {
        return new RecordDeclaration(
            Name: newtypeDecl.Name,
            TypeParameters: null,
            Interfaces: new List<TypeReference>(),
            Members: new List<Declaration>(),
            PrimaryConstructorParameters: new List<Parameter>
            {
                new("Value", newtypeDecl.UnderlyingType, null, false)
            },
            IsStruct: true,
            Modifiers: Modifiers.Readonly,
            Attributes: new List<AttributeNode>(),
            Line: newtypeDecl.Line,
            Column: newtypeDecl.Column);
    }

    /// <summary>
    /// Declare interface members (second pass)
    /// </summary>
    private void DeclareInterfaceMembers(InterfaceDeclaration interfaceDecl)
    {
        // Skip duck interfaces - they are type-erased
        if (interfaceDecl.IsDuckInterface)
            return;

        if (!_types.TryGetValue(interfaceDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Interface {interfaceDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        foreach (var member in interfaceDecl.Members)
        {
            if (member is FunctionDeclaration funcDecl)
            {
                // Interface methods are abstract by default
                DeclareInterfaceMethod(typeBuilder, funcDecl);
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare an interface method
    /// </summary>
    private void DeclareInterfaceMethod(TypeBuilder typeBuilder, FunctionDeclaration funcDecl)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var returnType = GetDeclaredFunctionReturnType(funcDecl, typeGenericParameters);
        _currentReturnType = returnType;
        _currentReturnType = returnType;

        var parameterTypes = funcDecl.Parameters
            .Select(p => ResolveParameterType(p, typeGenericParameters))
            .ToArray();

        // Interface methods are always public, abstract, and virtual
        var methodAttributes = MethodAttributes.Public | MethodAttributes.Abstract | MethodAttributes.Virtual | MethodAttributes.HideBySig | MethodAttributes.NewSlot;
        if (funcDecl.IsOperatorOverload || funcDecl.IsConversionOperator)
        {
            methodAttributes |= MethodAttributes.SpecialName;
        }

        var methodBuilder = typeBuilder.DefineMethod(
            GetEmittedMethodName(funcDecl),
            methodAttributes,
            returnType,
            parameterTypes);
        ApplyCustomAttributes(methodBuilder.SetCustomAttribute, funcDecl.Attributes);

        // Define parameter names
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(funcDecl.Parameters[i]), funcDecl.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, funcDecl.Parameters[i]);
        }

        // Store method for reference (interface methods don't have bodies)
        _methods[GetMethodKey(typeBuilder, funcDecl.Name)] = methodBuilder;
        _declaredMethodParameters[GetMethodKey(typeBuilder, funcDecl.Name)] = funcDecl.Parameters;
    }

    /// <summary>
    /// Declare class members (second pass)
    /// </summary>
    private void DeclareClassMembers(ClassDeclaration classDecl)
    {
        if (!_types.TryGetValue(classDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {classDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = new List<Type>();

        if (classDecl.BaseClass != null)
        {
            var baseType = ResolveType(classDecl.BaseClass, typeGenericParameters);
            if (baseType.IsInterface)
            {
                implementedInterfaces.Add(baseType);
            }
        }

        if (classDecl.Interfaces != null)
        {
            implementedInterfaces.AddRange(classDecl.Interfaces.Select(typeReference => ResolveType(typeReference, typeGenericParameters)).Where(type => type.IsInterface));
        }

        if (classDecl.PrimaryConstructorParameters != null && classDecl.PrimaryConstructorParameters.Count > 0)
        {
            DeclarePrimaryConstructorMembers(typeBuilder, classDecl.PrimaryConstructorParameters, isValueType: false);
        }

        // Check if there's any constructor declared
        bool hasConstructor = classDecl.Members.Any(m => m is ConstructorDeclaration);

        // If no constructor is declared, create a default parameterless constructor
        if (!hasConstructor && (classDecl.PrimaryConstructorParameters == null || classDecl.PrimaryConstructorParameters.Count == 0))
        {
            var defaultCtor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);

            _constructors[GetConstructorKey(typeBuilder)] = defaultCtor;
        }

        foreach (var member in classDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    DeclareConstructor(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    DeclareMethod(typeBuilder, funcDecl, implementedInterfaces);
                    break;
                case PropertyDeclaration propDecl:
                    DeclareProperty(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    DeclareIndexer(typeBuilder, indexerDecl);
                    break;
            }
        }

        ApplyRequiredMemberTypeAttribute(typeBuilder, classDecl.Members);

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare struct members (second pass)
    /// </summary>
    private void DeclareStructMembers(StructDeclaration structDecl)
    {
        if (!_types.TryGetValue(structDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {structDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = structDecl.Interfaces
            .Select(typeReference => ResolveType(typeReference, typeGenericParameters))
            .Where(type => type.IsInterface)
            .ToList();

        if (structDecl.PrimaryConstructorParameters != null && structDecl.PrimaryConstructorParameters.Count > 0)
        {
            DeclarePrimaryConstructorMembers(typeBuilder, structDecl.PrimaryConstructorParameters, isValueType: true);
        }

        foreach (var member in structDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    DeclareConstructor(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    DeclareMethod(typeBuilder, funcDecl, implementedInterfaces);
                    break;
                case PropertyDeclaration propDecl:
                    DeclareProperty(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    DeclareIndexer(typeBuilder, indexerDecl);
                    break;
            }
        }

        ApplyRequiredMemberTypeAttribute(typeBuilder, structDecl.Members);

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare a field
    /// </summary>
    private Type ResolveFieldDeclarationType(FieldDeclaration fieldDecl, TypeBuilder typeBuilder)
    {
        if (fieldDecl.Type != null)
        {
            return ResolveType(fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

        if (fieldDecl.Initializer == null)
        {
            throw new InvalidOperationException($"Field {fieldDecl.Name} must have either an explicit type or an initializer in IL compiler");
        }

        return GetExpressionType(fieldDecl.Initializer);
    }

    private static bool ShouldEmitFieldAsAutoProperty(FieldDeclaration fieldDecl)
    {
        return fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Required)
            || fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Init);
    }

    private void DeclareFieldAsAutoProperty(TypeBuilder typeBuilder, FieldDeclaration fieldDecl, Type fieldType)
    {
        var propertyBuilder = typeBuilder.DefineProperty(
            fieldDecl.Name,
            PropertyAttributes.None,
            fieldType,
            null);
        ApplyCustomAttributes(propertyBuilder.SetCustomAttribute, fieldDecl.Attributes);

        if (fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Required))
        {
            ApplyRequiredMemberAttribute(propertyBuilder.SetCustomAttribute);
        }

        var backingFieldName = $"<{fieldDecl.Name}>k__BackingField";
        var backingField = typeBuilder.DefineField(
            backingFieldName,
            fieldType,
            FieldAttributes.Private | (fieldDecl.Modifiers.HasFlag(Modifiers.Static) ? FieldAttributes.Static : 0));

        var accessorAttributes = GetConventionMethodVisibilityAttributes(fieldDecl.Name, fieldDecl.Modifiers)
            | MethodAttributes.SpecialName
            | MethodAttributes.HideBySig;
        if (fieldDecl.Modifiers.HasFlag(Modifiers.Static))
        {
            accessorAttributes |= MethodAttributes.Static;
        }

        var getMethod = typeBuilder.DefineMethod(
            $"get_{fieldDecl.Name}",
            accessorAttributes,
            fieldType,
            Type.EmptyTypes);

        var hasInitSetter = fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Init)
            || fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Readonly);
        MethodBuilder setMethod;
        if (hasInitSetter)
        {
            setMethod = typeBuilder.DefineMethod(
                $"set_{fieldDecl.Name}",
                accessorAttributes,
                fieldDecl.Modifiers.HasFlag(Modifiers.Static) ? CallingConventions.Standard : CallingConventions.HasThis,
                typeof(void),
                GetInitOnlySetterReturnRequiredCustomModifiers(),
                null,
                new[] { fieldType },
                null,
                null);
        }
        else
        {
            setMethod = typeBuilder.DefineMethod(
                $"set_{fieldDecl.Name}",
                accessorAttributes,
                typeof(void),
                new[] { fieldType });
        }

        setMethod.DefineParameter(1, ParameterAttributes.None, "value");

        propertyBuilder.SetGetMethod(getMethod);
        propertyBuilder.SetSetMethod(setMethod);

        _methods[GetMethodKey(typeBuilder, $"get_{fieldDecl.Name}")] = getMethod;
        _methods[GetMethodKey(typeBuilder, $"set_{fieldDecl.Name}")] = setMethod;
        _fields[GetFieldKey(typeBuilder, backingFieldName)] = backingField;
    }

    private void DeclareField(TypeBuilder typeBuilder, FieldDeclaration fieldDecl)
    {
        var fieldType = ResolveFieldDeclarationType(fieldDecl, typeBuilder);

        if (ShouldEmitFieldAsAutoProperty(fieldDecl))
        {
            DeclareFieldAsAutoProperty(typeBuilder, fieldDecl, fieldType);
            return;
        }

        var fieldAttributes = GetConventionFieldVisibilityAttributes(fieldDecl.Name, fieldDecl.Modifiers);

        if (fieldDecl.Modifiers.HasFlag(Modifiers.Static))
            fieldAttributes |= FieldAttributes.Static;
        if (fieldDecl.Modifiers.HasFlag(Modifiers.Readonly) || fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Readonly))
            fieldAttributes |= FieldAttributes.InitOnly;

        var fieldBuilder = typeBuilder.DefineField(
            fieldDecl.Name,
            fieldType,
            fieldAttributes);
        ApplyCustomAttributes(fieldBuilder.SetCustomAttribute, fieldDecl.Attributes);

        // Store field with qualified name (TypeName.FieldName)
        _fields[GetFieldKey(typeBuilder, fieldDecl.Name)] = fieldBuilder;

        // If there's an initializer, we'll handle it in the constructor
        // For now, just declare the field
    }

    /// <summary>
    /// Declare a property (auto-property or with custom get/set)
    /// </summary>
    private void DeclareProperty(TypeBuilder typeBuilder, PropertyDeclaration propDecl)
    {
        var propertyType = ResolveType(propDecl.Type, GetTypeGenericParameters(typeBuilder));

        // Define the property
        var propertyBuilder = typeBuilder.DefineProperty(
            propDecl.Name,
            PropertyAttributes.None,
            propertyType,
            null);
        ApplyCustomAttributes(propertyBuilder.SetCustomAttribute, propDecl.Attributes);

        if (propDecl.PropertyModifier.HasFlag(PropertyModifier.Required))
        {
            ApplyRequiredMemberAttribute(propertyBuilder.SetCustomAttribute);
        }

        // For now, we'll implement simple auto-properties with a backing field
        var backingFieldName = $"<{propDecl.Name}>k__BackingField";
        var backingField = typeBuilder.DefineField(
            backingFieldName,
            propertyType,
            FieldAttributes.Private | (propDecl.Modifiers.HasFlag(Modifiers.Static) ? FieldAttributes.Static : 0));

        var accessorAttributes = GetConventionMethodVisibilityAttributes(propDecl.Name, propDecl.Modifiers)
            | MethodAttributes.SpecialName
            | MethodAttributes.HideBySig;
        if (propDecl.Modifiers.HasFlag(Modifiers.Static))
        {
            accessorAttributes |= MethodAttributes.Static;
        }

        // Define get method
        if (propDecl.GetBody != null || propDecl.ExpressionBody != null)
        {
            var getMethod = typeBuilder.DefineMethod(
                $"get_{propDecl.Name}",
                accessorAttributes,
                propertyType,
                Type.EmptyTypes);

            propertyBuilder.SetGetMethod(getMethod);

            // Store the method for later body emission
            _methods[GetMethodKey(typeBuilder, $"get_{propDecl.Name}")] = getMethod;
        }

        // Define set method
        if (propDecl.SetBody != null && !propDecl.PropertyModifier.HasFlag(PropertyModifier.Readonly))
        {
            MethodBuilder setMethod;
            if (propDecl.PropertyModifier.HasFlag(PropertyModifier.Init))
            {
                setMethod = typeBuilder.DefineMethod(
                    $"set_{propDecl.Name}",
                    accessorAttributes,
                    propDecl.Modifiers.HasFlag(Modifiers.Static) ? CallingConventions.Standard : CallingConventions.HasThis,
                    typeof(void),
                    GetInitOnlySetterReturnRequiredCustomModifiers(),
                    null,
                    new[] { propertyType },
                    null,
                    null);
            }
            else
            {
                setMethod = typeBuilder.DefineMethod(
                    $"set_{propDecl.Name}",
                    accessorAttributes,
                    typeof(void),
                    new[] { propertyType });
            }

            setMethod.DefineParameter(1, ParameterAttributes.None, "value");

            propertyBuilder.SetSetMethod(setMethod);

            // Store the method for later body emission
            _methods[GetMethodKey(typeBuilder, $"set_{propDecl.Name}")] = setMethod;
        }

        // Store the backing field
        _fields[GetFieldKey(typeBuilder, backingFieldName)] = backingField;
    }

    private void DeclareIndexer(TypeBuilder typeBuilder, IndexerDeclaration indexerDecl)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var propertyType = ResolveType(indexerDecl.Type, typeGenericParameters);
        var parameterTypes = indexerDecl.Parameters.Select(p => ResolveType(p.Type, typeGenericParameters)).ToArray();

        var propertyBuilder = typeBuilder.DefineProperty(
            "Item",
            PropertyAttributes.None,
            propertyType,
            parameterTypes);
        ApplyCustomAttributes(propertyBuilder.SetCustomAttribute, indexerDecl.Attributes);
        _indexers[GetIndexerKey(typeBuilder)] = propertyBuilder;

        if (indexerDecl.GetBody != null)
        {
            var getMethod = typeBuilder.DefineMethod(
                "get_Item",
                GetVisibilityMethodAttributes(indexerDecl.Modifiers) | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                propertyType,
                parameterTypes);

            for (int i = 0; i < indexerDecl.Parameters.Count; i++)
            {
                var parameterBuilder = getMethod.DefineParameter(i + 1, GetParameterAttributes(indexerDecl.Parameters[i]), indexerDecl.Parameters[i].Name);
                ApplyParameterAttributes(parameterBuilder, indexerDecl.Parameters[i]);
            }

            propertyBuilder.SetGetMethod(getMethod);
            _methods[GetMethodKey(typeBuilder, "get_Item")] = getMethod;
        }

        if (indexerDecl.SetBody != null)
        {
            var setParameterTypes = parameterTypes.Concat(new[] { propertyType }).ToArray();
            var setMethod = typeBuilder.DefineMethod(
                "set_Item",
                GetVisibilityMethodAttributes(indexerDecl.Modifiers) | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                typeof(void),
                setParameterTypes);

            for (int i = 0; i < indexerDecl.Parameters.Count; i++)
            {
                var parameterBuilder = setMethod.DefineParameter(i + 1, GetParameterAttributes(indexerDecl.Parameters[i]), indexerDecl.Parameters[i].Name);
                ApplyParameterAttributes(parameterBuilder, indexerDecl.Parameters[i]);
            }
            setMethod.DefineParameter(indexerDecl.Parameters.Count + 1, ParameterAttributes.None, "value");

            propertyBuilder.SetSetMethod(setMethod);
            _methods[GetMethodKey(typeBuilder, "set_Item")] = setMethod;
        }

        var defaultMemberCtor = typeof(System.Reflection.DefaultMemberAttribute).GetConstructor(new[] { typeof(string) });
        if (defaultMemberCtor != null)
        {
            typeBuilder.SetCustomAttribute(new CustomAttributeBuilder(defaultMemberCtor, new object[] { "Item" }));
        }
    }

    private static bool HasRequiredMembers(IEnumerable<Declaration> members)
    {
        return members.Any(member => member switch
        {
            FieldDeclaration fieldDecl => fieldDecl.PropertyModifier.HasFlag(PropertyModifier.Required),
            PropertyDeclaration propDecl => propDecl.PropertyModifier.HasFlag(PropertyModifier.Required),
            _ => false
        });
    }

    private void ApplyRequiredMemberTypeAttribute(TypeBuilder typeBuilder, IEnumerable<Declaration> members)
    {
        if (!HasRequiredMembers(members))
        {
            return;
        }

        ApplyRequiredMemberAttribute(typeBuilder.SetCustomAttribute);
    }

    private void DeclarePrimaryConstructorMembers(TypeBuilder typeBuilder, List<Parameter> parameters, bool isValueType)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);

        foreach (var parameter in parameters)
        {
            var fieldType = ResolveType(parameter.Type, typeGenericParameters);
            var fieldBuilder = typeBuilder.DefineField(
                $"<>primary_{parameter.Name}",
                fieldType,
                FieldAttributes.Private | (isValueType ? FieldAttributes.InitOnly : FieldAttributes.InitOnly));

            _primaryConstructorFields[GetPrimaryConstructorFieldKey(typeBuilder, parameter.Name)] = fieldBuilder;
        }

        var parameterTypes = parameters.Select(p => ResolveType(p.Type, typeGenericParameters)).ToArray();
        var ctorBuilder = typeBuilder.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            parameterTypes);

        for (int i = 0; i < parameters.Count; i++)
        {
            var parameterBuilder = ctorBuilder.DefineParameter(i + 1, GetParameterAttributes(parameters[i]), parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, parameters[i]);
        }

        _constructors[GetConstructorKey(typeBuilder)] = ctorBuilder;
    }

    /// <summary>
    /// Declare a constructor
    /// </summary>
    private void DeclareConstructor(TypeBuilder typeBuilder, ConstructorDeclaration ctorDecl)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var parameterTypes = ctorDecl.Parameters
            .Select(p => ResolveParameterType(p, typeGenericParameters))
            .ToArray();

        var ctorBuilder = typeBuilder.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            parameterTypes);
        ApplyCustomAttributes(ctorBuilder.SetCustomAttribute, ctorDecl.Attributes);

        // Define parameter names
        for (int i = 0; i < ctorDecl.Parameters.Count; i++)
        {
            var parameterBuilder = ctorBuilder.DefineParameter(i + 1, GetParameterAttributes(ctorDecl.Parameters[i]), ctorDecl.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, ctorDecl.Parameters[i]);
        }

        // Store constructor for later body emission
        _constructors[GetConstructorKey(typeBuilder)] = ctorBuilder;
        RegisterDeclaredConstructorOverload(GetConstructorKey(typeBuilder), ctorDecl, ctorBuilder);
    }

    /// <summary>
    /// Declare a method (instance or static)
    /// </summary>
    private void DeclareMethod(TypeBuilder typeBuilder, FunctionDeclaration funcDecl, IReadOnlyList<Type>? implementedInterfaces = null)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var returnType = funcDecl.ReturnType != null
            ? ResolveType(funcDecl.ReturnType, typeGenericParameters)
            : typeof(void);

        var parameterTypes = funcDecl.Parameters
            .Select(p => ResolveParameterType(p, typeGenericParameters))
            .ToArray();

        var methodAttributes = GetVisibilityMethodAttributes(funcDecl.Modifiers);

        if (funcDecl.IsOperatorOverload || funcDecl.IsConversionOperator)
        {
            methodAttributes = MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig | MethodAttributes.SpecialName;
        }
        else if (funcDecl.Modifiers.HasFlag(Modifiers.Static))
            methodAttributes |= MethodAttributes.Static;
        else
            methodAttributes |= MethodAttributes.HideBySig;

        if (funcDecl.Modifiers.HasFlag(Modifiers.Virtual))
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.NewSlot;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Abstract))
            methodAttributes |= MethodAttributes.Abstract;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Override))
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.ReuseSlot;

        var interfaceMethods = implementedInterfaces == null
            ? new List<MethodInfo>()
            : implementedInterfaces
                .SelectMany(@interface => GetInterfaceMethodCandidates(@interface, funcDecl.Name))
                .Where(method => SignaturesMatch(method, returnType, parameterTypes))
                .ToList();

        if (interfaceMethods.Count > 0 && !funcDecl.Modifiers.HasFlag(Modifiers.Static))
        {
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.NewSlot;
        }

        var methodBuilder = typeBuilder.DefineMethod(
            GetEmittedMethodName(funcDecl),
            methodAttributes,
            returnType,
            parameterTypes);
        ApplyCustomAttributes(methodBuilder.SetCustomAttribute, funcDecl.Attributes);

        // Define parameter names
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(funcDecl.Parameters[i]), funcDecl.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, funcDecl.Parameters[i]);
        }

        // Store method for later body emission
        _methods[GetMethodKey(typeBuilder, funcDecl.Name)] = methodBuilder;
        _declaredMethodParameters[GetMethodKey(typeBuilder, funcDecl.Name)] = funcDecl.Parameters;
        RegisterDeclaredMethodOverload(GetMethodKey(typeBuilder, funcDecl.Name), funcDecl, methodBuilder);

        foreach (var interfaceMethod in interfaceMethods)
        {
            typeBuilder.DefineMethodOverride(methodBuilder, interfaceMethod);
        }
    }

    /// <summary>
    /// Emit class method bodies (third pass)
    /// </summary>
    private void EmitClassBodies(ClassDeclaration classDecl)
    {
        if (!_types.TryGetValue(classDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {classDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Check if there's any constructor declared
        bool hasConstructor = classDecl.Members.Any(m => m is ConstructorDeclaration);

        // If no constructor was declared, emit the synthesized constructor body
        if (!hasConstructor && classDecl.PrimaryConstructorParameters != null && classDecl.PrimaryConstructorParameters.Count > 0)
        {
            EmitPrimaryConstructorBody(typeBuilder, classDecl.PrimaryConstructorParameters, isValueType: false, classDecl.Members);
        }
        else if (!hasConstructor)
        {
            EmitDefaultConstructorBody(typeBuilder, classDecl.Members);
        }

        foreach (var member in classDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    EmitFieldBody(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    EmitConstructorBody(typeBuilder, ctorDecl, classDecl.Members);
                    break;
                case FunctionDeclaration funcDecl:
                    EmitMethodBody(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    EmitPropertyBody(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    EmitIndexerBody(typeBuilder, indexerDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit struct method bodies (third pass)
    /// </summary>
    private void EmitStructBodies(StructDeclaration structDecl)
    {
        if (!_types.TryGetValue(structDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {structDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        if (structDecl.PrimaryConstructorParameters != null && structDecl.PrimaryConstructorParameters.Count > 0 &&
            !structDecl.Members.Any(m => m is ConstructorDeclaration))
        {
            EmitPrimaryConstructorBody(typeBuilder, structDecl.PrimaryConstructorParameters, isValueType: true, structDecl.Members);
        }

        foreach (var member in structDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    EmitFieldBody(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    EmitConstructorBody(typeBuilder, ctorDecl, structDecl.Members);
                    break;
                case FunctionDeclaration funcDecl:
                    EmitMethodBody(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    EmitPropertyBody(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    EmitIndexerBody(typeBuilder, indexerDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    private void EmitDeclaredInstanceFieldInitializers(TypeBuilder typeBuilder, IEnumerable<Declaration> members)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        foreach (var fieldDecl in members.OfType<FieldDeclaration>())
        {
            if (fieldDecl.Initializer == null || fieldDecl.Modifiers.HasFlag(Modifiers.Static))
            {
                continue;
            }

            var storageKey = ShouldEmitFieldAsAutoProperty(fieldDecl)
                ? GetFieldKey(typeBuilder, $"<{fieldDecl.Name}>k__BackingField")
                : GetFieldKey(typeBuilder, fieldDecl.Name);
            if (!_fields.TryGetValue(storageKey, out var storageField))
            {
                throw new InvalidOperationException($"Storage field for {GetTypeKey(typeBuilder)}.{fieldDecl.Name} not declared");
            }

            _currentIL.Emit(OpCodes.Ldarg_0);
            EmitExpressionWithExpectedType(fieldDecl.Initializer, storageField.FieldType);
            _currentIL.Emit(OpCodes.Stfld, storageField);
        }
    }

    private void EmitFieldBody(TypeBuilder typeBuilder, FieldDeclaration fieldDecl)
    {
        if (!ShouldEmitFieldAsAutoProperty(fieldDecl))
        {
            return;
        }

        var backingFieldKey = GetFieldKey(typeBuilder, $"<{fieldDecl.Name}>k__BackingField");
        if (!_fields.TryGetValue(backingFieldKey, out var backingField))
        {
            throw new InvalidOperationException($"Backing field for {GetTypeKey(typeBuilder)}.{fieldDecl.Name} not declared");
        }

        if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{fieldDecl.Name}"), out var getter))
        {
            var il = getter.GetILGenerator();
            if (fieldDecl.Modifiers.HasFlag(Modifiers.Static))
            {
                il.Emit(OpCodes.Ldsfld, backingField);
            }
            else
            {
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Ldfld, backingField);
            }
            il.Emit(OpCodes.Ret);
        }

        if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{fieldDecl.Name}"), out var setter))
        {
            var il = setter.GetILGenerator();
            if (fieldDecl.Modifiers.HasFlag(Modifiers.Static))
            {
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Stsfld, backingField);
            }
            else
            {
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Ldarg_1);
                il.Emit(OpCodes.Stfld, backingField);
            }
            il.Emit(OpCodes.Ret);
        }
    }

    /// <summary>
    /// Emit default constructor body (when no explicit constructor is defined)
    /// </summary>
    private void EmitDefaultConstructorBody(TypeBuilder typeBuilder, IReadOnlyList<Declaration>? members = null)
    {
        if (!_constructors.TryGetValue(GetConstructorKey(typeBuilder), out var constructorBuilder))
        {
            throw new InvalidOperationException($"Default constructor for {GetTypeKey(typeBuilder)} not declared");
        }

        _currentIL = constructorBuilder.GetILGenerator();
        InitializeBodyContext(null, liftLocalsIntoBoxes: false);
        _currentHasThis = true;
        _currentGenericParameters = GetTypeGenericParameters(typeBuilder);

        // Call base constructor (object..ctor)
        _currentIL.Emit(OpCodes.Ldarg_0); // Load 'this'
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
        if (objectCtor != null)
        {
            _currentIL.Emit(OpCodes.Call, objectCtor);
        }

        if (members != null)
        {
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members);
        }

        // Return
        _currentIL.Emit(OpCodes.Ret);

        ClearMethodContext();
        _currentGenericParameters = null;
    }

    private void EmitPrimaryConstructorBody(TypeBuilder typeBuilder, List<Parameter> parameters, bool isValueType, IReadOnlyList<Declaration>? members = null)
    {
        if (!_constructors.TryGetValue(GetConstructorKey(typeBuilder), out var constructorBuilder))
        {
            throw new InvalidOperationException($"Primary constructor for {GetTypeKey(typeBuilder)} not declared");
        }

        _currentIL = constructorBuilder.GetILGenerator();
        InitializeBodyContext(null, liftLocalsIntoBoxes: false);
        _currentHasThis = true;
        _currentGenericParameters = GetTypeGenericParameters(typeBuilder);

        if (!isValueType)
        {
            _currentIL.Emit(OpCodes.Ldarg_0);
            var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
            if (objectCtor != null)
            {
                _currentIL.Emit(OpCodes.Call, objectCtor);
            }
        }

        for (int i = 0; i < parameters.Count; i++)
        {
            var fieldBuilder = FindPrimaryConstructorField(typeBuilder, parameters[i].Name);
            if (fieldBuilder == null)
            {
                throw new InvalidOperationException($"Primary constructor field for {parameters[i].Name} not declared on {GetTypeKey(typeBuilder)}");
            }

            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldarg, i + 1);
            _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
        }

        if (members != null)
        {
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members);
        }

        _currentIL.Emit(OpCodes.Ret);
        ClearMethodContext();
        _currentGenericParameters = null;
    }

    /// <summary>
    /// Emit constructor body
    /// </summary>
    private void EmitConstructorBody(TypeBuilder typeBuilder, ConstructorDeclaration ctorDecl, IReadOnlyList<Declaration>? members = null)
    {
        if (!_constructorBuildersByDeclaration.TryGetValue(ctorDecl, out var constructorBuilder))
        {
            throw new InvalidOperationException($"Constructor for {GetTypeKey(typeBuilder)} not declared");
        }

        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        _currentIL = constructorBuilder.GetILGenerator();
        InitializeBodyContext(null, ContainsNestedFunction(ctorDecl.Body));
        _currentHasThis = true;
        _currentGenericParameters = typeGenericParameters;

        RegisterParameterContext(ctorDecl.Parameters, 1, typeGenericParameters);

        // Call base constructor
        _currentIL.Emit(OpCodes.Ldarg_0); // Load 'this'
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
        if (objectCtor != null)
        {
            _currentIL.Emit(OpCodes.Call, objectCtor);
        }

        if (members != null)
        {
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members);
        }

        // Emit constructor body
        EmitStatement(ctorDecl.Body);

        // Ensure constructor ends with a return
        _currentIL.Emit(OpCodes.Ret);

        // Clear context
        ClearMethodContext();
        _currentGenericParameters = null;
    }

    /// <summary>
    /// Emit method body (instance or static)
    /// </summary>
    private void EmitMethodBody(TypeBuilder typeBuilder, FunctionDeclaration funcDecl)
    {
        if (!_methodBuildersByDeclaration.TryGetValue(funcDecl, out var methodBuilder))
        {
            throw new InvalidOperationException($"Method {GetTypeKey(typeBuilder)}.{funcDecl.Name} not declared");
        }

        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var returnType = GetDeclaredFunctionReturnType(funcDecl, typeGenericParameters);

        _currentIL = methodBuilder.GetILGenerator();
        var bodyReturnType = returnType;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Async) && TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
        {
            _currentAsyncReturnType = returnType;
            _currentAsyncResultType = asyncResultType;
            _currentAsyncReturnsValueTask = returnsValueTask;
            bodyReturnType = asyncResultType ?? typeof(void);
        }

        InitializeBodyContext(bodyReturnType, ContainsNestedFunction(funcDecl.Body)
            || (funcDecl.ExpressionBody != null && ContainsNestedFunction(funcDecl.ExpressionBody)));
        _currentHasThis = !methodBuilder.IsStatic;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Generator))
        {
            if (!TryGetSequenceElementType(returnType, out var yieldElementType, out _))
            {
                throw new InvalidOperationException($"Generator function {funcDecl.Name} must return an enumerable sequence type, but resolved to {returnType}");
            }

            _currentGeneratorReturnType = returnType;
            _currentYieldElementType = yieldElementType;
            _currentYieldBreakLabel = _currentIL.DefineLabel();
            var listType = typeof(List<>).MakeGenericType(yieldElementType);
            _currentYieldListLocal = _currentIL.DeclareLocal(listType);
            var listCtor = listType.GetConstructor(Type.EmptyTypes)
                ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
            _currentIL.Emit(OpCodes.Newobj, listCtor);
            _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
        }
        _currentGenericParameters = typeGenericParameters;

        // Map parameter names to indices
        // For instance methods, parameters start at index 1 (0 is 'this')
        // For static methods, parameters start at index 0
        int startIndex = methodBuilder.IsStatic ? 0 : 1;
        RegisterParameterContext(funcDecl.Parameters, startIndex, typeGenericParameters);

        // Emit method body
        if (funcDecl.Body != null)
        {
            EmitStatement(funcDecl.Body);
        }
        else if (funcDecl.ExpressionBody != null)
        {
            if (_currentAsyncReturnType != null)
            {
                if (_currentAsyncResultType != null)
                {
                    EmitExpressionWithExpectedType(funcDecl.ExpressionBody, _currentAsyncResultType);
                }
                else
                {
                    EmitExpression(funcDecl.ExpressionBody);
                    if (GetExpressionType(funcDecl.ExpressionBody) != typeof(void))
                    {
                        _currentIL.Emit(OpCodes.Pop);
                    }
                }

                EmitWrapCurrentAsyncReturn();
                _currentIL.Emit(OpCodes.Ret);
            }
            else
            {
                EmitExpression(funcDecl.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }
        }

        // Ensure method ends with a return
        if (_currentGeneratorReturnType != null)
        {
            _currentIL.MarkLabel(_currentYieldBreakLabel!.Value);
            EmitGeneratorReturnValue(_currentGeneratorReturnType, _currentYieldListLocal!);
            _currentIL.Emit(OpCodes.Ret);
        }
        else if (_currentAsyncReturnType != null && _currentAsyncResultType == null)
        {
            EmitWrapCurrentAsyncReturn();
            _currentIL.Emit(OpCodes.Ret);
        }
        else if (returnType == typeof(void))
        {
            _currentIL.Emit(OpCodes.Ret);
        }

        // Clear context
        ClearMethodContext();
        _currentGenericParameters = null;
    }

    /// <summary>
    /// Emit property getter/setter bodies
    /// </summary>
    private void EmitPropertyBody(TypeBuilder typeBuilder, PropertyDeclaration propDecl)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var propertyType = ResolveType(propDecl.Type, typeGenericParameters);
        var backingFieldName = $"<{propDecl.Name}>k__BackingField";

        // Emit getter
        if (propDecl.GetBody != null || propDecl.ExpressionBody != null)
        {
            if (!_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{propDecl.Name}"), out var getMethod))
            {
                throw new InvalidOperationException($"Getter for {GetTypeKey(typeBuilder)}.{propDecl.Name} not declared");
            }

            _currentIL = getMethod.GetILGenerator();
            InitializeBodyContext(propertyType, ContainsNestedFunction(propDecl.GetBody)
                || (propDecl.ExpressionBody != null && ContainsNestedFunction(propDecl.ExpressionBody)));
            _currentHasThis = !getMethod.IsStatic;
            _currentGenericParameters = typeGenericParameters;

            if (propDecl.GetBody != null)
            {
                EmitStatement(propDecl.GetBody);
            }
            else if (propDecl.ExpressionBody != null)
            {
                EmitExpression(propDecl.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }

            // Ensure getter ends with a return
            _currentIL.Emit(OpCodes.Ret);

            ClearMethodContext();
            _currentGenericParameters = null;
        }

        // Emit setter
        if (propDecl.SetBody != null)
        {
            if (!_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{propDecl.Name}"), out var setMethod))
            {
                throw new InvalidOperationException($"Setter for {GetTypeKey(typeBuilder)}.{propDecl.Name} not declared");
            }

            _currentIL = setMethod.GetILGenerator();
            InitializeBodyContext(null, ContainsNestedFunction(propDecl.SetBody));
            _currentHasThis = !setMethod.IsStatic;
            _currentGenericParameters = typeGenericParameters;
            _parameters["value"] = setMethod.IsStatic ? 0 : 1;
            _parameterTypes["value"] = propertyType;

            EmitStatement(propDecl.SetBody);

            // Ensure setter ends with a return
            _currentIL.Emit(OpCodes.Ret);

            ClearMethodContext();
            _currentGenericParameters = null;
        }
    }

    private void EmitIndexerBody(TypeBuilder typeBuilder, IndexerDeclaration indexerDecl)
    {
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        if (indexerDecl.GetBody != null)
        {
            if (!_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Item"), out var getMethod))
            {
                throw new InvalidOperationException($"Indexer getter for {GetTypeKey(typeBuilder)} not declared");
            }

            _currentIL = getMethod.GetILGenerator();
            InitializeBodyContext(ResolveType(indexerDecl.Type, typeGenericParameters), ContainsNestedFunction(indexerDecl.GetBody));
            _currentHasThis = !getMethod.IsStatic;
            _currentGenericParameters = typeGenericParameters;

            RegisterParameterContext(indexerDecl.Parameters, 1, typeGenericParameters);

            EmitStatement(indexerDecl.GetBody);
            _currentIL.Emit(OpCodes.Ret);

            ClearMethodContext();
            _currentGenericParameters = null;
        }

        if (indexerDecl.SetBody != null)
        {
            if (!_methods.TryGetValue(GetMethodKey(typeBuilder, "set_Item"), out var setMethod))
            {
                throw new InvalidOperationException($"Indexer setter for {GetTypeKey(typeBuilder)} not declared");
            }

            _currentIL = setMethod.GetILGenerator();
            InitializeBodyContext(null, ContainsNestedFunction(indexerDecl.SetBody));
            _currentHasThis = !setMethod.IsStatic;
            _currentGenericParameters = typeGenericParameters;

            RegisterParameterContext(indexerDecl.Parameters, 1, typeGenericParameters);

            var valueParameterIndex = indexerDecl.Parameters.Count + 1;
            _parameters["value"] = valueParameterIndex;
            _parameterTypes["value"] = ResolveType(indexerDecl.Type, typeGenericParameters);

            EmitStatement(indexerDecl.SetBody);
            _currentIL.Emit(OpCodes.Ret);

            ClearMethodContext();
            _currentGenericParameters = null;
        }
    }

    /// <summary>
    /// Emit IL for a match expression (pattern matching)
    /// </summary>
    private void EmitMatchExpression(MatchExpression match)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var endLabel = _currentIL.DefineLabel();
        var resultType = GetMatchExpressionType(match);
        var caseLabels = new Label[match.Cases.Count];
        var nextCaseLabels = new Label[match.Cases.Count];

        // Define labels for each case
        for (int i = 0; i < match.Cases.Count; i++)
        {
            caseLabels[i] = _currentIL.DefineLabel();
            nextCaseLabels[i] = _currentIL.DefineLabel();
        }

        // Store the matched value in a local (we'll need it for multiple comparisons)
        var matchValueType = GetExpressionType(match.Value);
        EmitExpression(match.Value);
        var matchLocal = _currentIL.DeclareLocal(matchValueType);
        _currentIL.Emit(OpCodes.Stloc, matchLocal);

        // Generate code for each case
        for (int i = 0; i < match.Cases.Count; i++)
        {
            var matchCase = match.Cases[i];
            var savedLocals = _locals != null ? new Dictionary<string, LocalBuilder>(_locals) : null;
            var patternSuccessLabel = matchCase.Guard != null
                ? _currentIL.DefineLabel()
                : caseLabels[i];

            // Emit pattern matching test
            _currentIL.Emit(OpCodes.Ldloc, matchLocal);
            EmitPatternTest(matchCase.Pattern, matchValueType, patternSuccessLabel, nextCaseLabels[i]);

            // Check guard if present
            if (matchCase.Guard != null)
            {
                _currentIL.MarkLabel(patternSuccessLabel);
                EmitExpression(matchCase.Guard);
                _currentIL.Emit(OpCodes.Brfalse, nextCaseLabels[i]); // If guard is false, try next case
            }

            // Mark the label for this case body
            _currentIL.MarkLabel(caseLabels[i]);

            // Emit the case body
            EmitExpressionWithExpectedType(matchCase.Expression, resultType);
            _currentIL.Emit(OpCodes.Br, endLabel); // Jump to end after executing case

            // Mark the label for the next case
            _currentIL.MarkLabel(nextCaseLabels[i]);
            _locals = savedLocals;
        }

        // If no case matched, throw MatchException
        _currentIL.Emit(OpCodes.Ldstr, "No matching case in match expression");
        var matchExceptionCtor = typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) });
        if (matchExceptionCtor != null)
        {
            _currentIL.Emit(OpCodes.Newobj, matchExceptionCtor);
            _currentIL.Emit(OpCodes.Throw);
        }

        // Mark the end label
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL to test if a pattern matches, jumping to successLabel if it does, otherwise falling through to failLabel
    /// </summary>
    private void EmitPatternTest(Pattern pattern, Type matchValueType, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (pattern)
        {
            case LiteralPattern literalPattern:
                // Compare value with literal
                // Stack: [value]
                EmitExpression(literalPattern.Literal);
                // Stack: [value, literal]

                // Use appropriate comparison based on type
                if (matchValueType == typeof(string))
                {
                    var stringEquals = typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) });
                    if (stringEquals != null)
                    {
                        _currentIL.Emit(OpCodes.Call, stringEquals);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                    }
                }
                else if (matchValueType.IsValueType)
                {
                    _currentIL.Emit(OpCodes.Ceq);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                    _currentIL.Emit(OpCodes.Br, failLabel);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ceq);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                    _currentIL.Emit(OpCodes.Br, failLabel);
                }
                break;

            case IdentifierPattern identPattern:
                // Wildcard pattern or variable binding - always matches
                if (identPattern.Name == "_")
                {
                    // Discard pattern - pop the value and jump to success
                    _currentIL.Emit(OpCodes.Pop);
                    _currentIL.Emit(OpCodes.Br, successLabel);
                }
                else if (identPattern.Name.Contains('.') && _types.TryGetValue(identPattern.Name, out var qualifiedCaseType))
                {
                    _currentIL.Emit(OpCodes.Isinst, qualifiedCaseType);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                    _currentIL.Emit(OpCodes.Br, failLabel);
                }
                else if (TryResolvePatternType(identPattern.Name, out var patternType))
                {
                    EmitTypePatternTest(patternType, bindingName: null, matchValueType, successLabel, failLabel);
                }
                else
                {
                    // Variable binding - store the value in a local and jump to success
                    EmitStorePatternBinding(identPattern.Name, matchValueType);
                    _currentIL.Emit(OpCodes.Br, successLabel);
                }
                break;

            case UnionCasePattern unionPattern:
                EmitUnionCasePatternTest(unionPattern, successLabel, failLabel);
                break;

            case ObjectPattern objectPattern:
                EmitObjectPatternTest(matchValueType, objectPattern.Properties, successLabel, failLabel);
                break;

            case PositionalPattern positionalPattern:
                EmitPositionalPatternTest(matchValueType, positionalPattern, successLabel, failLabel);
                break;

            case ListPattern listPattern:
                EmitListPatternTest(matchValueType, listPattern, successLabel, failLabel);
                break;

            case SlicePattern slicePattern:
                if (slicePattern.BindingName != null)
                {
                    if (_locals == null)
                    {
                        _locals = new Dictionary<string, LocalBuilder>();
                    }

                    var local = DeclareNamedLocal(slicePattern.BindingName, matchValueType);
                    if (IsLiftedIdentifier(slicePattern.BindingName))
                    {
                        EmitStoreLiftedLocalValue(local, matchValueType, leaveValueOnStack: false);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Stloc, local);
                    }
                }
                else
                {
                    _currentIL.Emit(OpCodes.Pop);
                }

                _currentIL.Emit(OpCodes.Br, successLabel);
                break;

            case RelationalPattern relationalPattern:
                // Relational pattern (< value, >= value, etc.)
                // Stack: [value]
                EmitExpression(relationalPattern.Value);
                // Stack: [value, relational_value]

                switch (relationalPattern.Operator)
                {
                    case "<":
                        _currentIL.Emit(OpCodes.Clt);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    case ">":
                        _currentIL.Emit(OpCodes.Cgt);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    case "<=":
                        _currentIL.Emit(OpCodes.Cgt);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    case ">=":
                        _currentIL.Emit(OpCodes.Clt);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    case "==":
                        _currentIL.Emit(OpCodes.Ceq);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    case "!=":
                        _currentIL.Emit(OpCodes.Ceq);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                }
                break;

            case AndPattern andPattern:
                // Both patterns must match
                var andNextLabel = _currentIL.DefineLabel();

                // Test first pattern
                _currentIL.Emit(OpCodes.Dup); // Duplicate value for second test
                EmitPatternTest(andPattern.Left, matchValueType, andNextLabel, failLabel);

                // First pattern didn't match, clean up and fail
                _currentIL.Emit(OpCodes.Pop);
                _currentIL.Emit(OpCodes.Br, failLabel);

                // First pattern matched, test second
                _currentIL.MarkLabel(andNextLabel);
                EmitPatternTest(andPattern.Right, matchValueType, successLabel, failLabel);
                break;

            case OrPattern orPattern:
                // Either pattern can match
                var orNextLabel = _currentIL.DefineLabel();

                // Test first pattern
                _currentIL.Emit(OpCodes.Dup); // Duplicate value for second test
                EmitPatternTest(orPattern.Left, matchValueType, successLabel, orNextLabel);

                // First pattern didn't match, try second
                _currentIL.MarkLabel(orNextLabel);
                EmitPatternTest(orPattern.Right, matchValueType, successLabel, failLabel);
                break;

            case NotPattern notPattern:
                // Pattern must NOT match
                var notMatchLabel = _currentIL.DefineLabel();

                // Test the inner pattern
                _currentIL.Emit(OpCodes.Dup);
                EmitPatternTest(notPattern.Pattern, matchValueType, notMatchLabel, successLabel);

                // Pattern matched, so not pattern fails
                _currentIL.MarkLabel(notMatchLabel);
                _currentIL.Emit(OpCodes.Pop);
                _currentIL.Emit(OpCodes.Br, failLabel);
                break;

            case TypePattern typePatternWithName:
                EmitTypePatternTest(
                    ResolveType(typePatternWithName.Type),
                    typePatternWithName.BindingName,
                    matchValueType,
                    successLabel,
                    failLabel);
                break;

            default:
                throw new NotImplementedException($"Pattern type {pattern.GetType().Name} not yet implemented in IL compiler");
        }
    }

    private void EmitTypePatternTest(Type patternType, string? bindingName, Type matchValueType, Label successLabel, Label failLabel)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (matchValueType.IsValueType || matchValueType.IsGenericParameter)
        {
            _currentIL.Emit(OpCodes.Box, matchValueType);
        }

        _currentIL.Emit(OpCodes.Isinst, patternType);
        _currentIL.Emit(OpCodes.Dup);
        var matchedLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Brtrue, matchedLabel);
        _currentIL.Emit(OpCodes.Pop);
        _currentIL.Emit(OpCodes.Br, failLabel);

        _currentIL.MarkLabel(matchedLabel);
        if (bindingName != null)
        {
            if (patternType.IsValueType)
            {
                _currentIL.Emit(OpCodes.Unbox_Any, patternType);
            }
            else if (patternType != typeof(object))
            {
                _currentIL.Emit(OpCodes.Castclass, patternType);
            }

            EmitStorePatternBinding(bindingName, patternType);
        }
        else
        {
            _currentIL.Emit(OpCodes.Pop);
        }

        _currentIL.Emit(OpCodes.Br, successLabel);
    }

    private void EmitStorePatternBinding(string bindingName, Type bindingType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        _locals ??= new Dictionary<string, LocalBuilder>();
        var local = DeclareNamedLocal(bindingName, bindingType);
        if (IsLiftedIdentifier(bindingName))
        {
            EmitStoreLiftedLocalValue(local, bindingType, leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, local);
        }
    }

    private bool TryResolvePatternType(string name, out Type type)
    {
        if (_typeAliases.TryGetValue(name, out var aliasedType))
        {
            type = ResolveType(aliasedType, _currentGenericParameters);
            return true;
        }

        if (_types.TryGetValue(name, out var userType))
        {
            type = userType;
            return true;
        }

        if (_enumTypes.TryGetValue(name, out var enumType))
        {
            type = enumType;
            return true;
        }

        type = name switch
        {
            "byte" => typeof(byte),
            "sbyte" => typeof(sbyte),
            "short" => typeof(short),
            "ushort" => typeof(ushort),
            "int" => typeof(int),
            "uint" => typeof(uint),
            "long" => typeof(long),
            "ulong" => typeof(ulong),
            "float" => typeof(float),
            "double" => typeof(double),
            "decimal" => typeof(decimal),
            "char" => typeof(char),
            "bool" => typeof(bool),
            "string" => typeof(string),
            "object" => typeof(object),
            _ => ResolveExternalType(name) ?? typeof(object)
        };

        return name is "byte" or "sbyte" or "short" or "ushort" or "int" or "uint" or "long" or "ulong"
            or "float" or "double" or "decimal" or "char" or "bool" or "string" or "object"
            || type != typeof(object)
            || string.Equals(name, "object", StringComparison.Ordinal);
    }

    private void EmitUnionCasePatternTest(UnionCasePattern unionPattern, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (!_types.TryGetValue(unionPattern.CaseName, out var caseType))
        {
            throw new InvalidOperationException($"Union case type {unionPattern.CaseName} not declared");
        }

        _currentIL.Emit(OpCodes.Isinst, caseType);
        _currentIL.Emit(OpCodes.Dup);

        var matchedLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Brtrue, matchedLabel);
        _currentIL.Emit(OpCodes.Pop);
        _currentIL.Emit(OpCodes.Br, failLabel);

        _currentIL.MarkLabel(matchedLabel);
        if (unionPattern.Properties == null || unionPattern.Properties.Count == 0)
        {
            _currentIL.Emit(OpCodes.Pop);
            _currentIL.Emit(OpCodes.Br, successLabel);
            return;
        }

        var caseLocal = _currentIL.DeclareLocal(caseType);
        _currentIL.Emit(OpCodes.Stloc, caseLocal);
        EmitPropertyPatternTests(caseType, caseLocal, unionPattern.Properties, successLabel, failLabel);
    }

    private void EmitObjectPatternTest(Type targetType, List<PropertyPattern> properties, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var targetLocal = _currentIL.DeclareLocal(targetType);
        _currentIL.Emit(OpCodes.Stloc, targetLocal);
        EmitPropertyPatternTests(targetType, targetLocal, properties, successLabel, failLabel);
    }

    private void EmitPositionalPatternTest(Type targetType, PositionalPattern positionalPattern, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var targetLocal = _currentIL.DeclareLocal(targetType);
        _currentIL.Emit(OpCodes.Stloc, targetLocal);

        if (TryResolveDeconstructMethod(targetType, positionalPattern.Patterns.Count, out var deconstructMethod, out var elementTypes))
        {
            var elementLocals = elementTypes.Select(_currentIL.DeclareLocal).ToArray();
            var useAddressReceiver = IsValueTypeLike(targetType) && !targetType.IsGenericParameter;

            if (useAddressReceiver)
            {
                _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, targetLocal);
            }

            foreach (var elementLocal in elementLocals)
            {
                _currentIL.Emit(OpCodes.Ldloca_S, elementLocal);
            }

            _currentIL.Emit(useAddressReceiver || !deconstructMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, deconstructMethod);

            for (int i = 0; i < positionalPattern.Patterns.Count; i++)
            {
                var nextElementLabel = _currentIL.DefineLabel();
                _currentIL.Emit(OpCodes.Ldloc, elementLocals[i]);
                EmitPatternTest(positionalPattern.Patterns[i], elementTypes[i], nextElementLabel, failLabel);
                _currentIL.MarkLabel(nextElementLabel);
            }

            _currentIL.Emit(OpCodes.Br, successLabel);
            return;
        }

        for (int i = 0; i < positionalPattern.Patterns.Count; i++)
        {
            var nextElementLabel = _currentIL.DefineLabel();
            var elementType = EmitPositionalPatternElementLoad(targetType, targetLocal, i);
            EmitPatternTest(positionalPattern.Patterns[i], elementType, nextElementLabel, failLabel);
            _currentIL.MarkLabel(nextElementLabel);
        }

        _currentIL.Emit(OpCodes.Br, successLabel);
    }

    private bool TryResolveDeconstructMethod(Type targetType, int arity, out MethodInfo methodInfo, out Type[] elementTypes)
    {
        var candidate = ResolveUserDefinedMethod(targetType, "Deconstruct");
        if (candidate == null)
        {
            candidate = targetType
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .FirstOrDefault(method => method.Name == "Deconstruct" && method.GetParameters().Length == arity);
        }

        if (candidate == null)
        {
            methodInfo = null!;
            elementTypes = Array.Empty<Type>();
            return false;
        }

        var parameters = candidate.GetParameters();
        if (parameters.Length != arity || parameters.Any(parameter => !parameter.ParameterType.IsByRef))
        {
            methodInfo = null!;
            elementTypes = Array.Empty<Type>();
            return false;
        }

        methodInfo = candidate;
        elementTypes = parameters.Select(parameter => GetByRefElementType(parameter.ParameterType)).ToArray();
        return true;
    }

    private Type EmitPositionalPatternElementLoad(Type targetType, LocalBuilder targetLocal, int elementIndex)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var memberName = $"Item{elementIndex + 1}";
        var loadByAddress = IsValueTypeLike(targetType);

        if (loadByAddress)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        if (targetType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberName), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                return fieldBuilder.FieldType;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberName}"), out var getterMethod))
            {
                _currentIL.Emit(loadByAddress ? OpCodes.Call : OpCodes.Callvirt, getterMethod);
                return getterMethod.ReturnType;
            }

            throw new InvalidOperationException($"Positional member {memberName} not found on type {GetTypeKey(typeBuilder)}");
        }

        var field = targetType.GetField(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (field != null)
        {
            _currentIL.Emit(OpCodes.Ldfld, field);
            return field.FieldType;
        }

        var property = targetType.GetProperty(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property?.GetMethod != null)
        {
            _currentIL.Emit(loadByAddress || !property.GetMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, property.GetMethod);
            return property.PropertyType;
        }

        throw new InvalidOperationException($"Positional member {memberName} not found on type {targetType}");
    }

    private sealed record ListPatternShape(Type ElementType, MethodInfo LengthGetter, MethodInfo IndexerGetter);

    private void EmitListPatternTest(Type targetType, ListPattern listPattern, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (targetType.IsArray)
        {
            var elementType = targetType.GetElementType() ?? typeof(object);
            var targetLocal = _currentIL.DeclareLocal(targetType);
            var lengthLocal = _currentIL.DeclareLocal(typeof(int));
            _currentIL.Emit(OpCodes.Stloc, targetLocal);
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
            _currentIL.Emit(OpCodes.Ldlen);
            _currentIL.Emit(OpCodes.Conv_I4);
            _currentIL.Emit(OpCodes.Stloc, lengthLocal);

            var sliceIndex = listPattern.Elements.FindIndex(p => p is SlicePattern);
            var leadingCount = sliceIndex >= 0 ? sliceIndex : listPattern.Elements.Count;
            var trailingCount = sliceIndex >= 0 ? listPattern.Elements.Count - sliceIndex - 1 : 0;
            var minimumLength = leadingCount + trailingCount;

            _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
            _currentIL.Emit(OpCodes.Ldc_I4, sliceIndex >= 0 ? minimumLength : listPattern.Elements.Count);
            _currentIL.Emit(sliceIndex >= 0 ? OpCodes.Blt : OpCodes.Bne_Un, failLabel);

            for (int i = 0; i < leadingCount; i++)
            {
                var nextElementLabel = _currentIL.DefineLabel();
                EmitArrayPatternElementLoad(targetLocal, elementType, i);
                EmitPatternTest(listPattern.Elements[i], elementType, nextElementLabel, failLabel);
                _currentIL.MarkLabel(nextElementLabel);
            }

            if (sliceIndex >= 0 && listPattern.Elements[sliceIndex] is SlicePattern slicePattern && slicePattern.BindingName != null)
            {
                if (_locals == null)
                {
                    _locals = new Dictionary<string, LocalBuilder>();
                }

                var sliceLocal = DeclareNamedLocal(slicePattern.BindingName, targetType);
                EmitArraySlice(targetLocal, targetType, leadingCount, trailingCount);
                if (IsLiftedIdentifier(slicePattern.BindingName))
                {
                    EmitStoreLiftedLocalValue(sliceLocal, targetType, leaveValueOnStack: false);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Stloc, sliceLocal);
                }
            }

            for (int i = 0; i < trailingCount; i++)
            {
                var nextElementLabel = _currentIL.DefineLabel();
                var patternIndex = sliceIndex >= 0 ? sliceIndex + 1 + i : leadingCount + i;
                EmitArrayPatternElementLoadFromEnd(targetLocal, lengthLocal, elementType, trailingCount - i);
                EmitPatternTest(listPattern.Elements[patternIndex], elementType, nextElementLabel, failLabel);
                _currentIL.MarkLabel(nextElementLabel);
            }

            _currentIL.Emit(OpCodes.Br, successLabel);
            return;
        }

        if (!TryGetListPatternShape(targetType, out var shape) || shape == null)
        {
            throw new NotImplementedException($"List patterns are only implemented for arrays and indexable collections, not {targetType}");
        }

        var collectionLocal = _currentIL.DeclareLocal(targetType);
        var collectionLengthLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Stloc, collectionLocal);
        EmitSequenceLengthLoad(collectionLocal, targetType, shape);
        _currentIL.Emit(OpCodes.Stloc, collectionLengthLocal);

        var collectionSliceIndex = listPattern.Elements.FindIndex(p => p is SlicePattern);
        var collectionLeadingCount = collectionSliceIndex >= 0 ? collectionSliceIndex : listPattern.Elements.Count;
        var collectionTrailingCount = collectionSliceIndex >= 0 ? listPattern.Elements.Count - collectionSliceIndex - 1 : 0;
        var collectionMinimumLength = collectionLeadingCount + collectionTrailingCount;

        _currentIL.Emit(OpCodes.Ldloc, collectionLengthLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, collectionSliceIndex >= 0 ? collectionMinimumLength : listPattern.Elements.Count);
        _currentIL.Emit(collectionSliceIndex >= 0 ? OpCodes.Blt : OpCodes.Bne_Un, failLabel);

        for (int i = 0; i < collectionLeadingCount; i++)
        {
            var nextElementLabel = _currentIL.DefineLabel();
            EmitIndexedPatternElementLoad(collectionLocal, targetType, shape, i);
            EmitPatternTest(listPattern.Elements[i], shape.ElementType, nextElementLabel, failLabel);
            _currentIL.MarkLabel(nextElementLabel);
        }

        if (collectionSliceIndex >= 0 && listPattern.Elements[collectionSliceIndex] is SlicePattern collectionSlicePattern && collectionSlicePattern.BindingName != null)
        {
            if (_locals == null)
            {
                _locals = new Dictionary<string, LocalBuilder>();
            }

            var sliceLocal = DeclareNamedLocal(collectionSlicePattern.BindingName, shape.ElementType.MakeArrayType());
            EmitIndexedSequenceSliceToArray(collectionLocal, collectionLengthLocal, targetType, shape, collectionLeadingCount, collectionTrailingCount);
            if (IsLiftedIdentifier(collectionSlicePattern.BindingName))
            {
                EmitStoreLiftedLocalValue(sliceLocal, shape.ElementType.MakeArrayType(), leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, sliceLocal);
            }
        }

        for (int i = 0; i < collectionTrailingCount; i++)
        {
            var nextElementLabel = _currentIL.DefineLabel();
            var patternIndex = collectionSliceIndex >= 0 ? collectionSliceIndex + 1 + i : collectionLeadingCount + i;
            EmitIndexedPatternElementLoadFromEnd(collectionLocal, collectionLengthLocal, targetType, shape, collectionTrailingCount - i);
            EmitPatternTest(listPattern.Elements[patternIndex], shape.ElementType, nextElementLabel, failLabel);
            _currentIL.MarkLabel(nextElementLabel);
        }

        _currentIL.Emit(OpCodes.Br, successLabel);
    }

    private void EmitArrayPatternElementLoad(LocalBuilder arrayLocal, Type elementType, int index)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, index);
        EmitArrayElementLoad(elementType);
    }

    private void EmitArrayPatternElementLoadFromEnd(LocalBuilder arrayLocal, LocalBuilder lengthLocal, Type elementType, int fromEndOffset)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, fromEndOffset);
        _currentIL.Emit(OpCodes.Sub);
        EmitArrayElementLoad(elementType);
    }

    private bool TryGetListPatternShape(Type targetType, out ListPatternShape? shape)
    {
        shape = null;
        if (targetType.IsArray)
        {
            return false;
        }

        if (targetType is TypeBuilder typeBuilder)
        {
            MethodInfo? lengthGetter = null;
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Count"), out var countGetter))
            {
                lengthGetter = countGetter;
            }
            else if (_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Length"), out var lengthMethod))
            {
                lengthGetter = lengthMethod;
            }

            if (lengthGetter == null || lengthGetter.ReturnType != typeof(int))
            {
                return false;
            }

            if (!_methods.TryGetValue(GetMethodKey(typeBuilder, "get_Item"), out var indexerGetter))
            {
                return false;
            }

            var indexerParameters = indexerGetter.GetParameters();
            if (indexerParameters.Length != 1 || indexerParameters[0].ParameterType != typeof(int))
            {
                return false;
            }

            shape = new ListPatternShape(indexerGetter.ReturnType, lengthGetter, indexerGetter);
            return true;
        }

        var bindingFlags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
        var lengthProperty = targetType.GetProperty("Count", bindingFlags)
            ?? targetType.GetProperty("Length", bindingFlags);
        if (lengthProperty?.GetMethod == null || lengthProperty.PropertyType != typeof(int))
        {
            return false;
        }

        var indexerProperty = targetType.GetProperties(bindingFlags)
            .FirstOrDefault(property =>
            {
                if (property.GetMethod == null)
                {
                    return false;
                }

                var parameters = property.GetIndexParameters();
                return parameters.Length == 1 && parameters[0].ParameterType == typeof(int);
            });

        if (indexerProperty?.GetMethod == null)
        {
            return false;
        }

        shape = new ListPatternShape(indexerProperty.PropertyType, lengthProperty.GetMethod, indexerProperty.GetMethod);
        return true;
    }

    private void EmitSequenceLengthLoad(LocalBuilder targetLocal, Type targetType, ListPatternShape shape)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var useAddressReceiver = IsValueTypeLike(targetType) && !targetType.IsGenericParameter;
        if (useAddressReceiver)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        _currentIL.Emit(useAddressReceiver || !shape.LengthGetter.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, shape.LengthGetter);
    }

    private void EmitIndexedPatternElementLoad(LocalBuilder targetLocal, Type targetType, ListPatternShape shape, int index)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var useAddressReceiver = IsValueTypeLike(targetType) && !targetType.IsGenericParameter;
        if (useAddressReceiver)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        _currentIL.Emit(OpCodes.Ldc_I4, index);
        _currentIL.Emit(useAddressReceiver || !shape.IndexerGetter.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, shape.IndexerGetter);
    }

    private void EmitIndexedPatternElementLoadFromEnd(LocalBuilder targetLocal, LocalBuilder lengthLocal, Type targetType, ListPatternShape shape, int fromEndOffset)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var useAddressReceiver = IsValueTypeLike(targetType) && !targetType.IsGenericParameter;
        if (useAddressReceiver)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, fromEndOffset);
        _currentIL.Emit(OpCodes.Sub);
        _currentIL.Emit(useAddressReceiver || !shape.IndexerGetter.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, shape.IndexerGetter);
    }

    private void EmitIndexedSequenceSliceToArray(LocalBuilder targetLocal, LocalBuilder lengthLocal, Type targetType, ListPatternShape shape, int startCount, int trailingCount)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var resultType = shape.ElementType.MakeArrayType();
        var resultLocal = _currentIL.DeclareLocal(resultType);
        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        var sliceLengthLocal = _currentIL.DeclareLocal(typeof(int));
        var loopStartLabel = _currentIL.DefineLabel();
        var loopEndLabel = _currentIL.DefineLabel();

        _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, startCount);
        _currentIL.Emit(OpCodes.Sub);
        _currentIL.Emit(OpCodes.Ldc_I4, trailingCount);
        _currentIL.Emit(OpCodes.Sub);
        _currentIL.Emit(OpCodes.Stloc, sliceLengthLocal);

        _currentIL.Emit(OpCodes.Ldloc, sliceLengthLocal);
        _currentIL.Emit(OpCodes.Newarr, shape.ElementType);
        _currentIL.Emit(OpCodes.Stloc, resultLocal);

        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.MarkLabel(loopStartLabel);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, sliceLengthLocal);
        _currentIL.Emit(OpCodes.Bge, loopEndLabel);

        _currentIL.Emit(OpCodes.Ldloc, resultLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);

        var useAddressReceiver = IsValueTypeLike(targetType) && !targetType.IsGenericParameter;
        if (useAddressReceiver)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, startCount);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(useAddressReceiver || !shape.IndexerGetter.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, shape.IndexerGetter);
        EmitArrayElementStore(shape.ElementType);

        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);
        _currentIL.Emit(OpCodes.Br, loopStartLabel);

        _currentIL.MarkLabel(loopEndLabel);
        _currentIL.Emit(OpCodes.Ldloc, resultLocal);
    }

    private void EmitArraySlice(LocalBuilder arrayLocal, Type arrayType, int startCount, int trailingCount)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var elementType = arrayType.GetElementType() ?? typeof(object);
        var indexCtor = typeof(Index).GetConstructor(new[] { typeof(int), typeof(bool) });
        var rangeCtor = typeof(Range).GetConstructor(new[] { typeof(Index), typeof(Index) });
        var getSubArray = typeof(System.Runtime.CompilerServices.RuntimeHelpers)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .First(m => m.Name == "GetSubArray" && m.IsGenericMethodDefinition && m.GetParameters().Length == 2)
            .MakeGenericMethod(elementType);

        if (indexCtor == null || rangeCtor == null)
        {
            throw new InvalidOperationException("Could not resolve array slice helpers");
        }

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);

        _currentIL.Emit(OpCodes.Ldc_I4, startCount);
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Newobj, indexCtor);

        _currentIL.Emit(OpCodes.Ldc_I4, trailingCount);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Newobj, indexCtor);

        _currentIL.Emit(OpCodes.Newobj, rangeCtor);
        _currentIL.Emit(OpCodes.Call, getSubArray);
    }

    private void EmitPropertyPatternTests(Type targetType, LocalBuilder targetLocal, List<PropertyPattern> properties, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        foreach (var property in properties)
        {
            var nextPropertyLabel = _currentIL.DefineLabel();
            var memberType = EmitPatternMemberLoad(targetType, targetLocal, property.Name);

            if (property.Pattern != null)
            {
                EmitPatternTest(property.Pattern, memberType, nextPropertyLabel, failLabel);
            }
            else
            {
                if (_locals == null)
                {
                    _locals = new Dictionary<string, LocalBuilder>();
                }

                var bindingName = property.BindingName ?? property.Name;
                var bindingLocal = DeclareNamedLocal(bindingName, memberType);
                if (IsLiftedIdentifier(bindingName))
                {
                    EmitStoreLiftedLocalValue(bindingLocal, memberType, leaveValueOnStack: false);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Stloc, bindingLocal);
                }
                _currentIL.Emit(OpCodes.Br, nextPropertyLabel);
            }

            _currentIL.MarkLabel(nextPropertyLabel);
        }

        _currentIL.Emit(OpCodes.Br, successLabel);
    }

    private Type EmitPatternMemberLoad(Type targetType, LocalBuilder targetLocal, string memberName)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var loadByAddress = IsValueTypeLike(targetType);
        if (loadByAddress)
        {
            _currentIL.Emit(OpCodes.Ldloca_S, targetLocal);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        }

        if (targetType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberName), out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                return fieldBuilder.FieldType;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberName}"), out var getterMethod))
            {
                _currentIL.Emit(loadByAddress ? OpCodes.Call : OpCodes.Callvirt, getterMethod);
                return getterMethod.ReturnType;
            }

            throw new InvalidOperationException($"Pattern member {memberName} not found on type {GetTypeKey(typeBuilder)}");
        }

        var property = targetType.GetProperty(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property?.GetMethod != null)
        {
            _currentIL.Emit(loadByAddress || !property.GetMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, property.GetMethod);
            return property.PropertyType;
        }

        var field = targetType.GetField(memberName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (field != null)
        {
            _currentIL.Emit(OpCodes.Ldfld, field);
            return field.FieldType;
        }

        throw new InvalidOperationException($"Pattern member {memberName} not found on type {targetType}");
    }

    /// <summary>
    /// Declare a record type (first pass)
    /// </summary>
    private void DeclareRecord(ModuleBuilder moduleBuilder, RecordDeclaration recordDecl)
    {
        if (_types.ContainsKey(recordDecl.Name))
        {
            return;
        }

        // Records can be either classes (record class, default) or structs (record struct)
        TypeAttributes typeAttributes;
        Type? baseType;

        if (recordDecl.IsStruct)
        {
            // Record struct: value type, sealed
            typeAttributes = GetTypeVisibilityAttributes(recordDecl.Modifiers) | TypeAttributes.Sealed;
            baseType = typeof(ValueType);
        }
        else
        {
            // Record class: reference type, sealed by default
            typeAttributes = GetTypeVisibilityAttributes(recordDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Sealed;
            baseType = typeof(object);
        }

        var typeBuilder = moduleBuilder.DefineType(
            recordDecl.Name,
            typeAttributes,
            baseType);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, recordDecl.Attributes);

        RegisterType(recordDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, recordDecl.TypeParameters);

        if (recordDecl.Interfaces != null)
        {
            foreach (var interfaceType in recordDecl.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                typeBuilder.AddInterfaceImplementation(interfaceType);
            }
        }
    }

    /// <summary>
    /// Declare record members (second pass)
    /// </summary>
    private void DeclareRecordMembers(RecordDeclaration recordDecl)
    {
        if (!_types.TryGetValue(recordDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {recordDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = recordDecl.Interfaces
            .Select(typeReference => ResolveType(typeReference, typeGenericParameters))
            .Where(type => type.IsInterface)
            .ToList();

        // Declare fields for primary constructor parameters (as backing fields for auto-properties)
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var fieldType = ResolveType(param.Type, typeGenericParameters);

                // Define backing field
                var backingFieldName = $"<{param.Name}>k__BackingField";
                var backingField = typeBuilder.DefineField(
                    backingFieldName,
                    fieldType,
                    FieldAttributes.Private | FieldAttributes.InitOnly);

                _fields[GetFieldKey(typeBuilder, backingFieldName)] = backingField;

                // Define property
                var property = typeBuilder.DefineProperty(
                    param.Name,
                    PropertyAttributes.None,
                    fieldType,
                    null);

                // Define getter
                var getter = typeBuilder.DefineMethod(
                    $"get_{param.Name}",
                    MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                    fieldType,
                    Type.EmptyTypes);

                _methods[GetMethodKey(typeBuilder, $"get_{param.Name}")] = getter;
                property.SetGetMethod(getter);
            }

            // Declare primary constructor
            var paramTypes = recordDecl.PrimaryConstructorParameters
                .Select(p => ResolveType(p.Type, typeGenericParameters))
                .ToArray();

            var constructor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                paramTypes);

            _constructors[GetConstructorKey(typeBuilder)] = constructor;
        }
        else
        {
            // No primary constructor - create default parameterless constructor
            var defaultCtor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);

            _constructors[GetConstructorKey(typeBuilder)] = defaultCtor;
        }

        // Declare other members
        foreach (var member in recordDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    DeclareConstructor(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    DeclareMethod(typeBuilder, funcDecl, implementedInterfaces);
                    break;
                case PropertyDeclaration propDecl:
                    DeclareProperty(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    DeclareIndexer(typeBuilder, indexerDecl);
                    break;
            }
        }

        ApplyRequiredMemberTypeAttribute(typeBuilder, recordDecl.Members);

        // Declare Equals(object) override
        var equalsMethod = typeBuilder.DefineMethod(
            "Equals",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(bool),
            new[] { typeof(object) });

        _methods[GetMethodKey(typeBuilder, "Equals")] = equalsMethod;

        // Declare GetHashCode override
        var getHashCodeMethod = typeBuilder.DefineMethod(
            "GetHashCode",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(int),
            Type.EmptyTypes);

        _methods[GetMethodKey(typeBuilder, "GetHashCode")] = getHashCodeMethod;

        // Declare ToString override
        var toStringMethod = typeBuilder.DefineMethod(
            "ToString",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(string),
            Type.EmptyTypes);

        _methods[GetMethodKey(typeBuilder, "ToString")] = toStringMethod;

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit record method bodies (third pass)
    /// </summary>
    private void EmitRecordBodies(RecordDeclaration recordDecl)
    {
        if (!_types.TryGetValue(recordDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {recordDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Emit property getters for primary constructor parameters
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var getterKey = GetMethodKey(typeBuilder, $"get_{param.Name}");
                if (_methods.TryGetValue(getterKey, out var getter))
                {
                    var il = getter.GetILGenerator();
                    var backingFieldKey = GetFieldKey(typeBuilder, $"<{param.Name}>k__BackingField");
                    if (_fields.TryGetValue(backingFieldKey, out var backingField))
                    {
                        il.Emit(OpCodes.Ldarg_0);
                        il.Emit(OpCodes.Ldfld, backingField);
                        il.Emit(OpCodes.Ret);
                    }
                }
            }

            // Emit primary constructor body
            var ctorKey = GetConstructorKey(typeBuilder);
            if (_constructors.TryGetValue(ctorKey, out var constructor))
            {
                _currentIL = constructor.GetILGenerator();
                InitializeBodyContext(null, liftLocalsIntoBoxes: false);
                _currentHasThis = true;
                _currentGenericParameters = GetTypeGenericParameters(typeBuilder);

                // Call base constructor
                var baseType = typeBuilder.BaseType;
                var baseCtor = !recordDecl.IsStruct && baseType != typeof(ValueType)
                    ? baseType?.GetConstructor(Type.EmptyTypes)
                    : null;
                if (baseCtor != null)
                {
                    _currentIL.Emit(OpCodes.Ldarg_0);
                    _currentIL.Emit(OpCodes.Call, baseCtor);
                }

                // Initialize backing fields from parameters
                for (int i = 0; i < recordDecl.PrimaryConstructorParameters.Count; i++)
                {
                    var param = recordDecl.PrimaryConstructorParameters[i];
                    var backingFieldKey = GetFieldKey(typeBuilder, $"<{param.Name}>k__BackingField");
                    if (_fields.TryGetValue(backingFieldKey, out var backingField))
                    {
                        _currentIL.Emit(OpCodes.Ldarg_0);
                        _currentIL.Emit(OpCodes.Ldarg, i + 1); // +1 because arg_0 is 'this'
                        _currentIL.Emit(OpCodes.Stfld, backingField);
                    }
                }

                EmitDeclaredInstanceFieldInitializers(typeBuilder, recordDecl.Members);
                _currentIL.Emit(OpCodes.Ret);
                ClearMethodContext();
                _currentGenericParameters = null;
            }
        }
        else
        {
            // Emit default parameterless constructor
            var ctorKey = GetConstructorKey(typeBuilder);
            if (_constructors.TryGetValue(ctorKey, out var constructor))
            {
                _currentIL = constructor.GetILGenerator();
                InitializeBodyContext(null, liftLocalsIntoBoxes: false);
                _currentHasThis = true;
                _currentGenericParameters = GetTypeGenericParameters(typeBuilder);

                // Call base constructor
                var baseType = typeBuilder.BaseType;
                var baseCtor = !recordDecl.IsStruct && baseType != typeof(ValueType)
                    ? baseType?.GetConstructor(Type.EmptyTypes)
                    : null;
                if (baseCtor != null)
                {
                    _currentIL.Emit(OpCodes.Ldarg_0);
                    _currentIL.Emit(OpCodes.Call, baseCtor);
                }

                EmitDeclaredInstanceFieldInitializers(typeBuilder, recordDecl.Members);
                _currentIL.Emit(OpCodes.Ret);
                ClearMethodContext();
                _currentGenericParameters = null;
            }
        }

        // Emit Equals method
        EmitRecordEquals(recordDecl, typeBuilder);

        // Emit GetHashCode method
        EmitRecordGetHashCode(recordDecl, typeBuilder);

        // Emit ToString method
        EmitRecordToString(recordDecl, typeBuilder);

        // Emit other member bodies
        foreach (var member in recordDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    EmitFieldBody(typeBuilder, fieldDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    EmitMethodBody(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    EmitPropertyBody(typeBuilder, propDecl);
                    break;
                case IndexerDeclaration indexerDecl:
                    EmitIndexerBody(typeBuilder, indexerDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit Equals method for record
    /// </summary>
    private void EmitRecordEquals(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var equalsKey = GetMethodKey(typeBuilder, "Equals");
        if (!_methods.TryGetValue(equalsKey, out var equalsMethod))
            return;

        var il = equalsMethod.GetILGenerator();
        var returnFalse = il.DefineLabel();
        var compareFields = il.DefineLabel();

        // if (obj == null) return false;
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Brfalse, returnFalse);

        // if (!(obj is RecordType)) return false;
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Isinst, typeBuilder);
        il.Emit(OpCodes.Dup);
        il.Emit(OpCodes.Brtrue, compareFields);
        il.Emit(OpCodes.Pop);
        il.Emit(OpCodes.Br, returnFalse);

        // RecordType other = (RecordType)obj;
        il.MarkLabel(compareFields);
        var otherLocal = il.DeclareLocal(typeBuilder);
        il.Emit(OpCodes.Stloc, otherLocal);

        // Compare each field
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                if (_fields.TryGetValue(backingFieldKey, out var backingField))
                {
                    var fieldType = backingField.FieldType;

                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Ldfld, backingField);
                    il.Emit(OpCodes.Ldloc, otherLocal);
                    il.Emit(OpCodes.Ldfld, backingField);

                    // Use Equals for reference types and == for value types
                    if (fieldType.IsValueType)
                    {
                        il.Emit(OpCodes.Ceq);
                        il.Emit(OpCodes.Brfalse, returnFalse);
                    }
                    else
                    {
                        // Call static Object.Equals for proper null handling
                        var objectEqualsMethod = typeof(object).GetMethod("Equals", new[] { typeof(object), typeof(object) });
                        if (objectEqualsMethod != null)
                        {
                            il.Emit(OpCodes.Call, objectEqualsMethod);
                            il.Emit(OpCodes.Brfalse, returnFalse);
                        }
                    }
                }
            }
        }

        // All fields are equal, return true
        il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(OpCodes.Ret);

        // Return false
        il.MarkLabel(returnFalse);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit GetHashCode method for record
    /// </summary>
    private void EmitRecordGetHashCode(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var getHashCodeKey = $"{recordDecl.Name}.GetHashCode";
        if (!_methods.TryGetValue(getHashCodeKey, out var getHashCodeMethod))
            return;

        var il = getHashCodeMethod.GetILGenerator();
        var hashCodeLocal = il.DeclareLocal(typeof(int));

        // int hash = 17;
        il.Emit(OpCodes.Ldc_I4, 17);
        il.Emit(OpCodes.Stloc, hashCodeLocal);

        // Combine hash codes from all fields
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                if (_fields.TryGetValue(backingFieldKey, out var backingField))
                {
                    var fieldType = backingField.FieldType;

                    // hash = hash * 23 + field.GetHashCode();
                    il.Emit(OpCodes.Ldloc, hashCodeLocal);
                    il.Emit(OpCodes.Ldc_I4, 23);
                    il.Emit(OpCodes.Mul);

                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Ldfld, backingField);

                    if (fieldType.IsValueType)
                    {
                        // For value types, box and call GetHashCode
                        il.Emit(OpCodes.Box, fieldType);
                    }

                    // Call GetHashCode (handles null for reference types)
                    var getHashCodeMethodInfo = typeof(object).GetMethod("GetHashCode", Type.EmptyTypes);
                    if (getHashCodeMethodInfo != null)
                    {
                        il.Emit(OpCodes.Callvirt, getHashCodeMethodInfo);
                    }

                    il.Emit(OpCodes.Add);
                    il.Emit(OpCodes.Stloc, hashCodeLocal);
                }
            }
        }

        il.Emit(OpCodes.Ldloc, hashCodeLocal);
        il.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit ToString method for record
    /// </summary>
    private void EmitRecordToString(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var toStringKey = $"{recordDecl.Name}.ToString";
        if (!_methods.TryGetValue(toStringKey, out var toStringMethod))
            return;

        var il = toStringMethod.GetILGenerator();

        // Build string: "RecordName { Prop1 = value1, Prop2 = value2 }"
        if (recordDecl.PrimaryConstructorParameters == null || recordDecl.PrimaryConstructorParameters.Count == 0)
        {
            // No properties, just return the type name
            il.Emit(OpCodes.Ldstr, recordDecl.Name);
            il.Emit(OpCodes.Ret);
            return;
        }

        // Use StringBuilder for efficient string concatenation
        var stringBuilderType = typeof(System.Text.StringBuilder);
        var sbCtor = stringBuilderType.GetConstructor(Type.EmptyTypes);
        var appendStringMethod = stringBuilderType.GetMethod("Append", new[] { typeof(string) });
        var appendObjectMethod = stringBuilderType.GetMethod("Append", new[] { typeof(object) });
        var toStringMethodInfo = stringBuilderType.GetMethod("ToString", Type.EmptyTypes);

        if (sbCtor == null || appendStringMethod == null || appendObjectMethod == null || toStringMethodInfo == null)
        {
            // Fallback: just return type name
            il.Emit(OpCodes.Ldstr, recordDecl.Name);
            il.Emit(OpCodes.Ret);
            return;
        }

        var sbLocal = il.DeclareLocal(stringBuilderType);
        il.Emit(OpCodes.Newobj, sbCtor);
        il.Emit(OpCodes.Stloc, sbLocal);

        // Append "RecordName { "
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Ldstr, $"{recordDecl.Name} {{ ");
        il.Emit(OpCodes.Callvirt, appendStringMethod);
        il.Emit(OpCodes.Pop);

        // Append each property
        for (int i = 0; i < recordDecl.PrimaryConstructorParameters.Count; i++)
        {
            var param = recordDecl.PrimaryConstructorParameters[i];
            var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";

            if (_fields.TryGetValue(backingFieldKey, out var backingField))
            {
                // Append "PropName = "
                il.Emit(OpCodes.Ldloc, sbLocal);
                il.Emit(OpCodes.Ldstr, $"{param.Name} = ");
                il.Emit(OpCodes.Callvirt, appendStringMethod);
                il.Emit(OpCodes.Pop);

                // Append value
                il.Emit(OpCodes.Ldloc, sbLocal);
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Ldfld, backingField);

                // Box value types
                if (backingField.FieldType.IsValueType)
                {
                    il.Emit(OpCodes.Box, backingField.FieldType);
                }

                il.Emit(OpCodes.Callvirt, appendObjectMethod);
                il.Emit(OpCodes.Pop);

                // Append ", " if not last property
                if (i < recordDecl.PrimaryConstructorParameters.Count - 1)
                {
                    il.Emit(OpCodes.Ldloc, sbLocal);
                    il.Emit(OpCodes.Ldstr, ", ");
                    il.Emit(OpCodes.Callvirt, appendStringMethod);
                    il.Emit(OpCodes.Pop);
                }
            }
        }

        // Append " }"
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Ldstr, " }");
        il.Emit(OpCodes.Callvirt, appendStringMethod);
        il.Emit(OpCodes.Pop);

        // Return sb.ToString()
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Callvirt, toStringMethodInfo);
        il.Emit(OpCodes.Ret);
    }
}
