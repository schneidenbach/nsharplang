using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Threading.Tasks;
using System.Xml.Linq;
using NSharpLang.Compiler.Ast;
using BlobBuilder = System.Reflection.Metadata.BlobBuilder;
using MetadataTokens = System.Reflection.Metadata.Ecma335.MetadataTokens;
using MetadataRootBuilder = System.Reflection.Metadata.Ecma335.MetadataRootBuilder;
using ManagedPEBuilder = System.Reflection.PortableExecutable.ManagedPEBuilder;
using PEHeaderBuilder = System.Reflection.PortableExecutable.PEHeaderBuilder;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// Compiles N# AST directly to IL using System.Reflection.Emit
/// </summary>
public partial class ILCompiler
{
    private const string ThisCaptureName = "<>this";

    private static string GetNuGetPackagesRoot()
    {
        var configuredRoot = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (!string.IsNullOrWhiteSpace(configuredRoot))
        {
            return Path.GetFullPath(configuredRoot);
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nuget",
            "packages");
    }

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
    private Dictionary<string, Type>? _patternBindingTypeHints;
    private Dictionary<string, int>? _parameters;
    private Dictionary<string, Type>? _parameterTypes;
    private Dictionary<string, Type>? _inferredLocalTypes;
    private HashSet<string>? _byRefParameters;
    private GenericTypeParameterBuilder[]? _currentGenericParameters;
    private Type? _currentReturnType;
    private Type? _expectedExpressionType;
    private Type? _currentAsyncReturnType;
    private Type? _currentAsyncResultType;
    private bool _currentAsyncReturnsValueTask;
    private Type? _currentGeneratorReturnType;
    private Label? _currentReturnLabel;
    private LocalBuilder? _currentReturnLocal;
    private bool _usesStructuredReturn;
    private int _exceptionBlockDepth;
    private Type? _currentYieldElementType;
    private LocalBuilder? _currentYieldListLocal;
    private Label? _currentYieldBreakLabel;
    private bool _overflowCheckingEnabled;

    // Global context
    private TypeBuilder? _programType;
    private TypeBuilder? _testType;
    private ModuleBuilder? _moduleBuilder;
    private MethodBuilder? _entryPointWrapper;
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
    private readonly Dictionary<FunctionDeclaration, List<AnonymousUnionShim>> _anonymousUnionShimsByDeclaration = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<ConstructorDeclaration, ConstructorBuilder> _constructorBuildersByDeclaration = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<string, List<DeclaredMethodOverload>> _declaredMethodOverloads = new();
    private readonly Dictionary<string, List<DeclaredConstructorOverload>> _declaredConstructorOverloads = new();
    private readonly Dictionary<Type, string> _typeKeys = new();
    private readonly Dictionary<TypeBuilder, List<Type>> _typeBuilderInterfaces = new();
    private readonly Dictionary<string, TypeReference> _typeAliases = new();
    private readonly Dictionary<string, GenericTypeParameterBuilder[]> _typeGenericParameters = new();
    private readonly Dictionary<Type, AsyncSequenceAdapterInfo> _asyncSequenceAdapters = new();
    private readonly List<TypeBuilder> _generatedHelperTypes = new();
    private readonly Dictionary<Type, Type> _liftedStorageTypes = new();
    private readonly Dictionary<Type, ConstructorInfo> _liftedStorageConstructors = new();
    private readonly Dictionary<Type, FieldInfo> _liftedStorageValueFields = new();
    private readonly Dictionary<Type, Type> _liftedStorageValueTypes = new();
    // Value-struct (allocation-free) union support. For unions classified as
    // value-struct-emittable by NSharpLang.Compiler.Performance.UnionValueLayout, we
    // emit a readonly struct carrying an integer tag instead of the class hierarchy.
    // _valueStructUnions maps the union's struct type to its layout; _valueStructUnionCaseTypes
    // maps each nested case marker type back to the owning union layout.
    private readonly Dictionary<Type, ValueStructUnionLayout> _valueStructUnions = new();
    private readonly Dictionary<Type, ValueStructUnionLayout> _valueStructUnionCaseTypes = new();
    private readonly Dictionary<DelegateSignatureKey, Type> _customDelegateTypes = new();
    private readonly Dictionary<Type, ConstructorInfo> _delegateConstructors = new();
    private readonly Dictionary<Type, MethodInfo> _delegateInvokeMethods = new();
    private readonly HashSet<string> _typesBeingDeclared = new(StringComparer.Ordinal);
    private readonly HashSet<string> _attemptedAssemblyNameLoads = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _attemptedNuGetPackageLoads = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _loadedSharedFrameworks = new(StringComparer.OrdinalIgnoreCase);
    private TypeBuilder? _currentTypeBuilder;
    private int _asyncSequenceAdapterCounter = 0;
    private int _customDelegateCounter = 0;
    private int _delegateCacheCounter = 0;
    private int _liftedStorageCounter = 0;
    private bool _currentHasThis;
    private ConstructorInfo? _nullableAttributeByteConstructor;
    private ConstructorInfo? _nullableAttributeByteArrayConstructor;
    private ConstructorInfo? _nullableContextAttributeConstructor;

    // Lambda and closure support
    private int _lambdaCounter = 0;
    private int _closureCounter = 0;
    private Dictionary<string, FieldBuilder>? _closureFields;
    private readonly List<TypeBuilder> _closureTypes = new();
    private bool _liftLocalsIntoBoxes;
    private HashSet<string>? _localsToLiftIntoBoxes;
    private HashSet<string>? _localsToPredeclareForCapture;
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

    /// <summary>
    /// Layout metadata for a union emitted as an allocation-free value struct.
    /// <see cref="TagField"/> holds the integer discriminator; <see cref="CaseTags"/>
    /// maps each nested case marker type to its assigned tag value. The nested case
    /// types are still emitted (so reflection/type-resolution and existing tooling see
    /// them), but they act purely as tag markers — no instance of a case class is ever
    /// allocated.
    /// </summary>
    private sealed record ValueStructUnionLayout(
        TypeBuilder UnionType,
        FieldBuilder TagField,
        ConstructorBuilder TagConstructor,
        MethodBuilder TagGetter,
        Dictionary<Type, int> CaseTags,
        Dictionary<Type, MethodBuilder> CaseFactories);

    private sealed record DeclaredMethodOverload(FunctionDeclaration Declaration, MethodBuilder Builder);
    private sealed record DeclaredConstructorOverload(ConstructorDeclaration Declaration, ConstructorBuilder Builder);
    private sealed record AnonymousUnionShim(
        MethodBuilder Builder,
        MethodBuilder Target,
        FunctionDeclaration Declaration,
        Type[] OriginalParameterTypes,
        Type[] ShimParameterTypes);
    private sealed record LocalCaptureStorageInfo(
        HashSet<string> CapturedLocals,
        HashSet<string> LocalsToLiftIntoBoxes);
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
        Type? TargetType,
        IReadOnlyList<Type>? TypeArguments);
    private sealed record BoundDeclaredConstructorCall(
        ConstructorDeclaration Declaration,
        ConstructorInfo Constructor,
        IReadOnlyList<BoundCallArgument> Arguments);
    private enum MethodGroupReceiverKind
    {
        None,
        ImplicitThis,
        LocalFunction
    }

    private sealed record ContextualMethodGroupTarget(
        MethodInfo Method,
        Type DelegateType,
        MethodGroupReceiverKind ReceiverKind,
        int Score);

    public ILCompiler(CompilationUnit compilationUnit, string assemblyName, string outputPath, ProjectConfig? projectConfig = null)
    {
        _compilationUnit = compilationUnit;
        _assemblyName = assemblyName;
        _outputPath = outputPath;
        _projectConfig = projectConfig;
        LoadConfiguredAssemblies();

        foreach (var alias in compilationUnit.Declarations.OfType<TypeAliasDeclaration>())
        {
            _typeAliases[alias.Name] = alias.Type;
        }
    }

    private bool UsesNUnitTestFramework =>
        string.Equals(_projectConfig?.TestFramework, "nunit", StringComparison.OrdinalIgnoreCase);

    private void LoadConfiguredAssemblies()
    {
        if (_projectConfig == null)
        {
            return;
        }

        if (_projectConfig.Sdk.Contains("Web", StringComparison.OrdinalIgnoreCase))
        {
            TryLoadSharedFrameworkAssemblies("Microsoft.AspNetCore.App");
        }

        foreach (var reference in _projectConfig.Dependencies.Concat(_projectConfig.TestDependencies))
        {
            if (reference.Type == ReferenceType.Framework && !string.IsNullOrWhiteSpace(reference.Framework))
            {
                TryLoadSharedFrameworkAssemblies(reference.Framework);
                continue;
            }

            if (reference.Type == ReferenceType.NuGet && !string.IsNullOrWhiteSpace(reference.Nuget))
            {
                TryLoadNuGetAssembly(reference.Nuget, reference.Version);
                continue;
            }

            if (reference.Type != ReferenceType.Dll || string.IsNullOrWhiteSpace(reference.Dll))
            {
                continue;
            }

            var assemblyPath = reference.Dll!;
            if (!Path.IsPathRooted(assemblyPath))
            {
                assemblyPath = Path.GetFullPath(assemblyPath, Environment.CurrentDirectory);
            }

            if (!File.Exists(assemblyPath))
            {
                continue;
            }

            TryLoadAssembly(assemblyPath);
        }
    }

    private void TryLoadNuGetAssembly(string packageName, string? version)
    {
        var packageKey = $"{packageName}@{version ?? "*"}";
        if (!_attemptedNuGetPackageLoads.Add(packageKey))
        {
            return;
        }

        var packageDirectory = Path.Combine(GetNuGetPackagesRoot(), packageName.ToLowerInvariant());
        if (!Directory.Exists(packageDirectory))
        {
            TryLoadAssemblyByName(packageName);
            return;
        }

        var versionDirectory = version != null
            ? Path.Combine(packageDirectory, version)
            : Directory.GetDirectories(packageDirectory).OrderByDescending(path => path).FirstOrDefault();
        if (versionDirectory == null || !Directory.Exists(versionDirectory))
        {
            TryLoadAssemblyByName(packageName);
            return;
        }

        TryLoadNuGetDependencies(versionDirectory);

        var targetFramework = _projectConfig?.TargetFramework ?? "net10.0";
        var candidatePaths = new[]
        {
            Path.Combine(versionDirectory, "lib", targetFramework, $"{packageName}.dll"),
            Path.Combine(versionDirectory, "lib", "net10.0", $"{packageName}.dll"),
            Path.Combine(versionDirectory, "lib", "net9.0", $"{packageName}.dll"),
            Path.Combine(versionDirectory, "lib", "net8.0", $"{packageName}.dll"),
            Path.Combine(versionDirectory, "lib", "netstandard2.1", $"{packageName}.dll"),
            Path.Combine(versionDirectory, "lib", "netstandard2.0", $"{packageName}.dll")
        };

        foreach (var candidatePath in candidatePaths)
        {
            if (File.Exists(candidatePath))
            {
                TryLoadAssembly(candidatePath);
                TryLoadReferencedAssemblies(candidatePath);
                return;
            }
        }

        TryLoadAssemblyByName(packageName);
    }

    private void TryLoadNuGetDependencies(string versionDirectory)
    {
        try
        {
            var nuspecPath = Directory.GetFiles(versionDirectory, "*.nuspec", SearchOption.TopDirectoryOnly)
                .FirstOrDefault();
            if (nuspecPath == null)
            {
                return;
            }

            XNamespace ns = "http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd";
            var document = XDocument.Load(nuspecPath);
            var dependencyElements = document.Descendants(ns + "dependency")
                .Concat(document.Descendants("dependency"));
            foreach (var dependency in dependencyElements)
            {
                var id = dependency.Attribute("id")?.Value;
                if (string.IsNullOrWhiteSpace(id))
                {
                    continue;
                }

                var dependencyVersion = dependency.Attribute("version")?.Value;
                TryLoadNuGetAssembly(id, NormalizeNuGetDependencyVersion(dependencyVersion));
            }
        }
        catch
        {
            // Best-effort dependency loading for NuGet-backed extension methods.
        }
    }

    private static string? NormalizeNuGetDependencyVersion(string? version)
    {
        if (string.IsNullOrWhiteSpace(version))
        {
            return null;
        }

        return version.Trim().Trim('[', ']', '(', ')')
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault();
    }

    private void TryLoadReferencedAssemblies(string assemblyPath)
    {
        try
        {
            var assemblyName = AssemblyName.GetAssemblyName(assemblyPath);
            var assembly = AppDomain.CurrentDomain.GetAssemblies()
                .FirstOrDefault(candidate => AssemblyName.ReferenceMatchesDefinition(candidate.GetName(), assemblyName));
            if (assembly == null)
            {
                return;
            }

            foreach (var reference in assembly.GetReferencedAssemblies())
            {
                TryLoadAssemblyByName(reference.Name ?? string.Empty);
            }
        }
        catch
        {
            // Best-effort dependency loading for NuGet-backed extension methods.
        }
    }

    private void TryLoadSharedFrameworkAssemblies(string frameworkName)
    {
        if (string.IsNullOrWhiteSpace(frameworkName) || !_loadedSharedFrameworks.Add(frameworkName))
        {
            return;
        }

        var frameworkDirectory = FindSharedFrameworkDirectory(frameworkName);
        if (frameworkDirectory == null)
        {
            return;
        }

        foreach (var assemblyPath in Directory.GetFiles(frameworkDirectory, "*.dll", SearchOption.TopDirectoryOnly))
        {
            TryLoadAssembly(assemblyPath);
        }
    }

    private static void TryLoadAssembly(string assemblyPath)
    {
        try
        {
            var assemblyName = AssemblyName.GetAssemblyName(assemblyPath);
            var alreadyLoaded = AppDomain.CurrentDomain.GetAssemblies()
                .Any(assembly => AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName));

            if (!alreadyLoaded)
            {
                AssemblyLoadContext.Default.LoadFromAssemblyPath(assemblyPath);
            }
        }
        catch
        {
            // Best-effort assembly loading for external/test-framework references.
        }
    }

    private void TryLoadAssemblyByName(string assemblyName)
    {
        if (string.IsNullOrWhiteSpace(assemblyName) || !_attemptedAssemblyNameLoads.Add(assemblyName))
        {
            return;
        }

        try
        {
            var alreadyLoaded = AppDomain.CurrentDomain.GetAssemblies()
                .Any(assembly => string.Equals(assembly.GetName().Name, assemblyName, StringComparison.OrdinalIgnoreCase));
            if (alreadyLoaded)
            {
                return;
            }

            Assembly.Load(new AssemblyName(assemblyName));
            return;
        }
        catch
        {
            // Fall back to probing runtime/shared framework directories below.
        }

        var candidatePath = FindRuntimeAssemblyPath(assemblyName);
        if (candidatePath != null)
        {
            TryLoadAssembly(candidatePath);
        }
    }

    private static string? FindRuntimeAssemblyPath(string assemblyName)
    {
        var fileName = assemblyName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
            ? assemblyName
            : $"{assemblyName}.dll";

        foreach (var directory in EnumerateRuntimeAssemblyDirectories())
        {
            var candidatePath = Path.Combine(directory, fileName);
            if (File.Exists(candidatePath))
            {
                return candidatePath;
            }
        }

        return null;
    }

    private static string? FindSharedFrameworkDirectory(string frameworkName)
    {
        foreach (var directory in EnumerateRuntimeAssemblyDirectories())
        {
            var parentDirectory = Path.GetDirectoryName(directory);
            if (!string.IsNullOrWhiteSpace(parentDirectory) &&
                string.Equals(Path.GetFileName(parentDirectory), frameworkName, StringComparison.OrdinalIgnoreCase))
            {
                return directory;
            }
        }

        return null;
    }

    private static IEnumerable<string> EnumerateRuntimeAssemblyDirectories()
    {
        var yielded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var runtimeDirectory = RuntimeEnvironment.GetRuntimeDirectory();
        if (!string.IsNullOrWhiteSpace(runtimeDirectory) &&
            Directory.Exists(runtimeDirectory) &&
            yielded.Add(runtimeDirectory))
        {
            yield return runtimeDirectory;
        }

        var searchDirectory = runtimeDirectory;
        for (var depth = 0; depth < 6 && !string.IsNullOrWhiteSpace(searchDirectory); depth++)
        {
            searchDirectory = Path.GetDirectoryName(searchDirectory);
            if (searchDirectory == null)
            {
                yield break;
            }

            if (!string.Equals(Path.GetFileName(searchDirectory), "shared", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            foreach (var frameworkDirectory in Directory.GetDirectories(searchDirectory))
            {
                foreach (var versionDirectory in Directory.GetDirectories(frameworkDirectory)
                             .OrderByDescending(path => path, StringComparer.OrdinalIgnoreCase))
                {
                    if (yielded.Add(versionDirectory))
                    {
                        yield return versionDirectory;
                    }
                }
            }

            yield break;
        }
    }

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
                    var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(parameter), parameter.Name);
                    ApplyParameterAttributes(parameterBuilder, parameter);
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
            InitializeBodyContextForBody(null, setupDeclaration.Body, null, Array.Empty<Parameter>());
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
            InitializeBodyContextForBody(null, teardownDeclaration.Body, null, Array.Empty<Parameter>());
            _currentHasThis = true;

            EmitStatement(teardownDeclaration.Body);
            _currentIL.Emit(OpCodes.Ret);
            ClearMethodContext();
        }

        foreach (var (declaration, methodBuilder) in _testMethods)
        {
            _currentIL = methodBuilder.GetILGenerator();
            InitializeBodyContextForBody(
                typeof(void),
                declaration.Body,
                null,
                declaration.TableParameters != null ? declaration.TableParameters : Array.Empty<Parameter>());
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

        InitializeBodyContextForBody(bodyReturnType == typeof(void) ? null : bodyReturnType, body, null, Array.Empty<Parameter>());
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
            FloatLiteralExpression floatLiteral => ParseFloatingLiteralObject(floatLiteral.Value),
            CharLiteralExpression charLiteral => ParseCharLiteralValue(charLiteral.Value),
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
        _localsToLiftIntoBoxes = null;
        _localsToPredeclareForCapture = null;
        _liftedIdentifiers = null;
        _liftedClosureFields = null;
        _currentAsyncReturnType = null;
        _currentAsyncResultType = null;
        _currentAsyncReturnsValueTask = false;
        _currentGeneratorReturnType = null;
        _currentReturnLabel = null;
        _currentReturnLocal = null;
        _usesStructuredReturn = false;
        _exceptionBlockDepth = 0;
        _asyncFaultGuardCompletionEmitted = false;
        _currentYieldElementType = null;
        _currentYieldListLocal = null;
        _currentYieldBreakLabel = null;
        _localFunctionDeclarations = null;
        _currentHasThis = false;
    }

    private void InitializeBodyContext(
        Type? returnType,
        bool liftLocalsIntoBoxes,
        HashSet<string>? localsToLiftIntoBoxes = null,
        HashSet<string>? localsToPredeclareForCapture = null)
    {
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();
        _parameterTypes = new Dictionary<string, Type>();
        _byRefParameters = new HashSet<string>();
        _currentReturnType = returnType;
        _liftLocalsIntoBoxes = liftLocalsIntoBoxes;
        _localsToLiftIntoBoxes = liftLocalsIntoBoxes ? localsToLiftIntoBoxes : null;
        _localsToPredeclareForCapture = localsToPredeclareForCapture is { Count: > 0 }
            ? localsToPredeclareForCapture
            : null;
        _liftedIdentifiers = liftLocalsIntoBoxes ? new HashSet<string>() : null;
        _liftedClosureFields = null;
        _currentHasThis = false;
    }

    private void InitializeStructuredReturnContext(Type bodyReturnType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        _currentReturnLabel = _currentIL.DefineLabel();
        var returnLocalType = _currentAsyncReturnType ?? (bodyReturnType == typeof(void) ? null : bodyReturnType);
        _currentReturnLocal = returnLocalType != null ? _currentIL.DeclareLocal(returnLocalType) : null;
        _usesStructuredReturn = false;
        _exceptionBlockDepth = 0;
    }

    private Type CreateStrongBoxType(Type valueType)
    {
        if (RequiresGeneratedLiftedStorageType(valueType))
        {
            if (_liftedStorageTypes.TryGetValue(valueType, out var liftedStorageType))
            {
                return liftedStorageType;
            }

            if (_moduleBuilder == null)
            {
                throw new InvalidOperationException("Module builder has not been initialized");
            }

            var boxType = _moduleBuilder.DefineType(
                $"<>LiftedBox{_liftedStorageCounter++}",
                TypeAttributes.NotPublic | TypeAttributes.Sealed | TypeAttributes.Class);
            var valueField = boxType.DefineField("Value", valueType, FieldAttributes.Public);
            var constructor = boxType.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                new[] { valueType });
            var constructorIl = constructor.GetILGenerator();
            var objectConstructor = typeof(object).GetConstructor(Type.EmptyTypes)
                ?? throw new InvalidOperationException("Could not resolve object::.ctor()");
            constructorIl.Emit(OpCodes.Ldarg_0);
            constructorIl.Emit(OpCodes.Call, objectConstructor);
            constructorIl.Emit(OpCodes.Ldarg_0);
            constructorIl.Emit(OpCodes.Ldarg_1);
            constructorIl.Emit(OpCodes.Stfld, valueField);
            constructorIl.Emit(OpCodes.Ret);

            _generatedHelperTypes.Add(boxType);
            _liftedStorageTypes[valueType] = boxType;
            _liftedStorageConstructors[valueType] = constructor;
            _liftedStorageValueFields[boxType] = valueField;
            _liftedStorageValueTypes[boxType] = valueType;
            return boxType;
        }

        return typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(valueType);
    }

    private static bool RequiresGeneratedLiftedStorageType(Type type)
    {
        if (type is GenericTypeParameterBuilder || type.IsGenericParameter)
        {
            return false;
        }

        if (type is TypeBuilder or EnumBuilder)
        {
            return true;
        }

        try
        {
            if (type.Assembly.IsDynamic)
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
            return true;
        }

        if (type.HasElementType && type.GetElementType() is { } elementType)
        {
            return RequiresGeneratedLiftedStorageType(elementType);
        }

        try
        {
            return type.IsGenericType && type.GetGenericArguments().Any(RequiresGeneratedLiftedStorageType);
        }
        catch (NotSupportedException)
        {
            return true;
        }
    }

    private static bool RequiresTypeBuilderMemberResolution(Type type)
    {
        if (type is TypeBuilder or EnumBuilder or GenericTypeParameterBuilder)
        {
            return true;
        }

        try
        {
            if (type.Assembly.IsDynamic)
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
            return true;
        }

        if (type.HasElementType && type.GetElementType() is { } elementType)
        {
            return RequiresTypeBuilderMemberResolution(elementType);
        }

        try
        {
            return type.IsGenericType && type.GetGenericArguments().Any(RequiresTypeBuilderMemberResolution);
        }
        catch (NotSupportedException)
        {
            return true;
        }
    }

    private IEnumerable<string> GetDeclaredTypeNameCandidates(string typeName)
    {
        if (string.IsNullOrWhiteSpace(typeName))
        {
            yield break;
        }

        yield return typeName;

        if (typeName.Contains('.'))
        {
            var separatorIndex = typeName.IndexOf('.');
            var qualifier = typeName[..separatorIndex];
            var remainder = typeName[(separatorIndex + 1)..];

            foreach (var import in _compilationUnit.Imports.Where(import => string.Equals(import.Alias, qualifier, StringComparison.Ordinal)))
            {
                yield return $"{import.Namespace}.{remainder}";
            }
        }

        var currentUnitNamespace = _compilationUnit.Namespace?.Name ?? _compilationUnit.Package?.Name;
        if (currentUnitNamespace is { Length: > 0 } currentNamespace
            && !typeName.StartsWith(currentNamespace + ".", StringComparison.Ordinal))
        {
            yield return $"{currentNamespace}.{typeName}";
        }

        foreach (var import in _compilationUnit.Imports.Where(import => import.Alias == null))
        {
            yield return $"{import.Namespace}.{typeName}";
        }

        var declaredNames = EnumerateDeclaredTypes()
            .Select(info => info.Name)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Cast<string>()
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        var matchingDeclaredNames = declaredNames
            .Where(name => string.Equals(name, typeName, StringComparison.Ordinal)
                || name.EndsWith("." + typeName, StringComparison.Ordinal))
            .ToArray();

        var importedNamespaceMatches = matchingDeclaredNames
            .Where(name =>
            {
                var namespaceName = GetNamespaceFromTypeName(name);
                return string.IsNullOrEmpty(namespaceName)
                    || _compilationUnit.Imports.Any(import =>
                        import.Alias == null
                        && string.Equals(import.Namespace, namespaceName, StringComparison.Ordinal));
            })
            .ToArray();

        if (importedNamespaceMatches.Length == 1)
        {
            yield return importedNamespaceMatches[0];
        }
        else if (matchingDeclaredNames.Length == 1)
        {
            yield return matchingDeclaredNames[0];
        }
    }

    private static string GetNamespaceFromTypeName(string typeName)
    {
        var separatorIndex = typeName.LastIndexOf('.');
        return separatorIndex >= 0 ? typeName[..separatorIndex] : string.Empty;
    }

    private string? ResolveDeclaredTypeName(string typeName)
    {
        return GetDeclaredTypeNameCandidates(typeName)
            .Distinct(StringComparer.Ordinal)
            .FirstOrDefault(candidate => TryGetDeclaredTypeInfo(candidate, out _));
    }

    private bool TryResolveDeclaredProjectType(string typeName, bool treatStringEnumAsString, out Type type)
    {
        foreach (var candidate in GetDeclaredTypeNameCandidates(typeName).Distinct(StringComparer.Ordinal))
        {
            if (TryLookupDeclaredProjectType(candidate, treatStringEnumAsString, out type))
            {
                return true;
            }
        }

        foreach (var candidate in GetDeclaredTypeNameCandidates(typeName).Distinct(StringComparer.Ordinal))
        {
            if (!TryEnsureUserTypeDeclared(candidate))
            {
                if (TryEnsureNestedDeclaredProjectType(candidate, treatStringEnumAsString, out type))
                {
                    return true;
                }

                continue;
            }

            if (TryLookupDeclaredProjectType(candidate, treatStringEnumAsString, out type))
            {
                return true;
            }
        }

        type = typeof(object);
        return false;
    }

    private bool TryEnsureNestedDeclaredProjectType(string candidate, bool treatStringEnumAsString, out Type type)
    {
        var separatorIndex = candidate.LastIndexOf('.');
        while (separatorIndex > 0)
        {
            var declaringTypeName = candidate[..separatorIndex];
            if (TryEnsureUserTypeDeclared(declaringTypeName)
                && TryLookupDeclaredProjectType(candidate, treatStringEnumAsString, out type))
            {
                return true;
            }

            separatorIndex = candidate.LastIndexOf('.', separatorIndex - 1);
        }

        type = typeof(object);
        return false;
    }

    private bool TryLookupDeclaredProjectType(string typeName, bool treatStringEnumAsString, out Type type)
    {
        if (_stringEnumContainers.TryGetValue(typeName, out var stringEnumContainer))
        {
            type = treatStringEnumAsString ? typeof(string) : stringEnumContainer;
            return true;
        }

        if (TryLookupUniqueDeclaredTypeBySuffix(_stringEnumContainers, typeName, out stringEnumContainer))
        {
            type = treatStringEnumAsString ? typeof(string) : stringEnumContainer;
            return true;
        }

        if (_types.TryGetValue(typeName, out var typeBuilder))
        {
            type = typeBuilder;
            return true;
        }

        if (TryLookupUniqueDeclaredTypeBySuffix(_types, typeName, out typeBuilder))
        {
            type = typeBuilder;
            return true;
        }

        if (_enumTypes.TryGetValue(typeName, out var enumType))
        {
            type = enumType;
            return true;
        }

        if (TryLookupUniqueDeclaredTypeBySuffix(_enumTypes, typeName, out enumType))
        {
            type = enumType;
            return true;
        }

        type = typeof(object);
        return false;
    }

    private static bool TryLookupUniqueDeclaredTypeBySuffix<TType>(IReadOnlyDictionary<string, TType> types, string typeName, out TType type)
        where TType : Type
    {
        var matches = types
            .Where(entry => string.Equals(entry.Key, typeName, StringComparison.Ordinal)
                || entry.Key.EndsWith("." + typeName, StringComparison.Ordinal))
            .Select(entry => entry.Value)
            .Distinct()
            .Take(2)
            .ToArray();

        if (matches.Length == 1)
        {
            type = matches[0];
            return true;
        }

        type = null!;
        return false;
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

    private sealed record ResolvedRuntimeProperty(Type PropertyType, MethodInfo? Getter, MethodInfo? Setter);

    private static bool TryGetDeclaredRuntimeProperty(Type type, string memberName, BindingFlags bindingFlags, out PropertyInfo? property)
    {
        try
        {
            property = type.GetProperty(memberName, bindingFlags);
            if (property != null
                && type.IsGenericType
                && !type.IsGenericTypeDefinition
                && property.DeclaringType == type.GetGenericTypeDefinition())
            {
                var getter = property.GetMethod != null ? TypeBuilder.GetMethod(type, property.GetMethod) : null;
                var setter = property.SetMethod != null ? TypeBuilder.GetMethod(type, property.SetMethod) : null;
                property = getter?.DeclaringType?.GetProperty(property.Name, bindingFlags);
            }
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

    private static bool TryGetDeclaredRuntimeMethod(Type type, string memberName, BindingFlags bindingFlags, Type[]? parameterTypes, out MethodInfo? method)
    {
        try
        {
            if (parameterTypes != null && RequiresGeneratedMethodSignatureResolution(type, parameterTypes))
            {
                return TryGetDeclaredGeneratedRuntimeMethod(type, memberName, bindingFlags, parameterTypes, out method);
            }

            method = parameterTypes == null
                ? type.GetMethod(memberName, bindingFlags)
                : type.GetMethod(memberName, bindingFlags, binder: null, parameterTypes, modifiers: null);
            if (method != null
                && type.IsGenericType
                && !type.IsGenericTypeDefinition
                && method.DeclaringType == type.GetGenericTypeDefinition())
            {
                method = TypeBuilder.GetMethod(type, method);
            }
            return method != null;
        }
        catch (ArgumentException) when (parameterTypes != null && RequiresGeneratedMethodSignatureResolution(type, parameterTypes))
        {
            return TryGetDeclaredGeneratedRuntimeMethod(type, memberName, bindingFlags, parameterTypes, out method);
        }
        catch (AmbiguousMatchException)
        {
            method = type.GetMethods(bindingFlags).FirstOrDefault(candidate => candidate.Name == memberName);
            if (method != null
                && type.IsGenericType
                && !type.IsGenericTypeDefinition
                && method.DeclaringType == type.GetGenericTypeDefinition())
            {
                method = TypeBuilder.GetMethod(type, method);
            }
            return method != null;
        }
        catch (NotSupportedException)
        {
            if (type.IsGenericType && !type.IsGenericTypeDefinition && RequiresTypeBuilderMemberResolution(type))
            {
                var genericDefinition = type.GetGenericTypeDefinition();
                if (TryGetDeclaredRuntimeMethod(genericDefinition, memberName, bindingFlags, parameterTypes, out var openMethod)
                    && openMethod != null)
                {
                    method = TypeBuilder.GetMethod(type, openMethod);
                    return true;
                }
            }

            method = null;
            return false;
        }
    }

    private static bool RequiresGeneratedMethodSignatureResolution(Type type, Type[] parameterTypes)
    {
        return RequiresTypeBuilderMemberResolution(type)
            || parameterTypes.Any(RequiresTypeBuilderMemberResolution);
    }

    private static bool TryGetDeclaredGeneratedRuntimeMethod(
        Type type,
        string memberName,
        BindingFlags bindingFlags,
        Type[] parameterTypes,
        out MethodInfo? method)
    {
        method = null;

        var searchType = type;
        var needsRebinding = false;
        if (type.IsGenericType && !type.IsGenericTypeDefinition && RequiresTypeBuilderMemberResolution(type))
        {
            try
            {
                searchType = type.GetGenericTypeDefinition();
                needsRebinding = true;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        MethodInfo[] candidates;
        try
        {
            candidates = searchType.GetMethods(bindingFlags);
        }
        catch (NotSupportedException)
        {
            return false;
        }

        var selected = candidates.FirstOrDefault(candidate =>
            candidate.Name == memberName
            && AreMethodParameterTypesEquivalent(type, candidate, parameterTypes));
        if (selected == null)
        {
            return false;
        }

        method = needsRebinding ? TypeBuilder.GetMethod(type, selected) : selected;
        return method != null;
    }

    private static bool AreMethodParameterTypesEquivalent(Type closedType, MethodInfo candidate, Type[] parameterTypes)
    {
        var candidateParameters = candidate.GetParameters();
        if (candidateParameters.Length != parameterTypes.Length)
        {
            return false;
        }

        for (int i = 0; i < candidateParameters.Length; i++)
        {
            var candidateParameterType = ResolveGenericSignatureType(closedType, candidateParameters[i].ParameterType);
            if (!AreTypeIdentitiesEquivalent(candidateParameterType, parameterTypes[i]))
            {
                return false;
            }
        }

        return true;
    }

    private static MethodInfo? ResolveRuntimeMethod(Type type, string memberName, BindingFlags bindingFlags, Type[]? parameterTypes = null)
    {
        return ResolveRuntimeMethod(type, memberName, bindingFlags, parameterTypes, new HashSet<Type>());
    }

    private static MethodInfo? ResolveRuntimeMethod(Type type, string memberName, BindingFlags bindingFlags, Type[]? parameterTypes, HashSet<Type> visited)
    {
        if (!visited.Add(type))
        {
            return null;
        }

        if (TryGetDeclaredRuntimeMethod(type, memberName, bindingFlags, parameterTypes, out var method))
        {
            return method;
        }

        foreach (var interfaceType in GetRuntimeInterfaces(type))
        {
            method = ResolveRuntimeMethod(interfaceType, memberName, bindingFlags, parameterTypes, visited);
            if (method != null)
            {
                return method;
            }
        }

        return type.BaseType != null
            ? ResolveRuntimeMethod(type.BaseType, memberName, bindingFlags, parameterTypes, visited)
            : null;
    }

    private static Type ResolveGenericSignatureType(Type closedType, Type signatureType)
    {
        if (!signatureType.ContainsGenericParameters || !closedType.IsGenericType)
        {
            return signatureType;
        }

        Type genericDefinition;
        Type[] definitionArguments;
        Type[] actualArguments;
        try
        {
            genericDefinition = closedType.GetGenericTypeDefinition();
            definitionArguments = genericDefinition.GetGenericArguments();
            actualArguments = closedType.GetGenericArguments();
        }
        catch (NotSupportedException)
        {
            try
            {
                actualArguments = closedType.GetGenericArguments();
                return SubstituteGenericSignatureTypeByPosition(signatureType, actualArguments);
            }
            catch (NotSupportedException)
            {
                return signatureType;
            }
        }

        var substitutions = new Dictionary<(string Name, int Position), Type>();
        for (int i = 0; i < definitionArguments.Length && i < actualArguments.Length; i++)
        {
            substitutions[(definitionArguments[i].Name, definitionArguments[i].GenericParameterPosition)] = actualArguments[i];
        }

        return SubstituteGenericSignatureType(signatureType, substitutions);
    }

    private static Type SubstituteGenericSignatureTypeByPosition(Type signatureType, IReadOnlyList<Type> actualArguments)
    {
        if (signatureType.IsGenericParameter && !IsMethodGenericParameter(signatureType))
        {
            var position = signatureType.GenericParameterPosition;
            if (position >= 0 && position < actualArguments.Count)
            {
                return actualArguments[position];
            }
        }

        if (signatureType.IsByRef)
        {
            return SubstituteGenericSignatureTypeByPosition(signatureType.GetElementType()!, actualArguments).MakeByRefType();
        }

        if (signatureType.IsArray)
        {
            return SubstituteGenericSignatureTypeByPosition(signatureType.GetElementType()!, actualArguments).MakeArrayType();
        }

        if (!signatureType.IsGenericType)
        {
            return signatureType;
        }

        Type genericDefinition;
        try
        {
            genericDefinition = signatureType.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return signatureType;
        }

        var substitutedArguments = signatureType.GetGenericArguments()
            .Select(argument => SubstituteGenericSignatureTypeByPosition(argument, actualArguments))
            .ToArray();
        return genericDefinition.MakeGenericType(substitutedArguments);
    }

    private static bool IsMethodGenericParameter(Type type)
    {
        try
        {
            return type.DeclaringMethod != null;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static Type SubstituteGenericSignatureType(
        Type signatureType,
        IReadOnlyDictionary<(string Name, int Position), Type> substitutions)
    {
        if (signatureType.IsGenericParameter
            && substitutions.TryGetValue((signatureType.Name, signatureType.GenericParameterPosition), out var substitutedType))
        {
            return substitutedType;
        }

        if (signatureType.IsByRef)
        {
            return SubstituteGenericSignatureType(signatureType.GetElementType()!, substitutions).MakeByRefType();
        }

        if (signatureType.IsArray)
        {
            return SubstituteGenericSignatureType(signatureType.GetElementType()!, substitutions).MakeArrayType();
        }

        if (!signatureType.IsGenericType)
        {
            return signatureType;
        }

        Type genericDefinition;
        try
        {
            genericDefinition = signatureType.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return signatureType;
        }

        var substitutedArguments = signatureType.GetGenericArguments()
            .Select(argument => SubstituteGenericSignatureType(argument, substitutions))
            .ToArray();
        return genericDefinition.MakeGenericType(substitutedArguments);
    }

    private static ResolvedRuntimeProperty? ResolveRuntimeProperty(Type type, string memberName, BindingFlags bindingFlags, HashSet<Type> visited)
    {
        if (!visited.Add(type))
        {
            return null;
        }

        if (TryGetDeclaredRuntimeProperty(type, memberName, bindingFlags, out var property))
        {
            return new ResolvedRuntimeProperty(
                ResolveGenericSignatureType(type, property!.GetMethod?.ReturnType ?? property.PropertyType),
                property.GetMethod,
                property.SetMethod);
        }

        if (type.IsGenericType && !type.IsGenericTypeDefinition && RequiresTypeBuilderMemberResolution(type))
        {
            var genericDefinition = type.GetGenericTypeDefinition();
            if (TryGetDeclaredRuntimeProperty(genericDefinition, memberName, bindingFlags, out var openProperty)
                && openProperty?.GetMethod != null)
            {
                var getter = TypeBuilder.GetMethod(type, openProperty.GetMethod);
                var setter = openProperty.SetMethod != null
                    ? TypeBuilder.GetMethod(type, openProperty.SetMethod)
                    : null;
                return new ResolvedRuntimeProperty(
                    ResolveGenericSignatureType(type, openProperty.PropertyType),
                    getter,
                    setter);
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

    private ConstructorInfo GetStrongBoxConstructor(Type valueType)
    {
        if (_liftedStorageConstructors.TryGetValue(valueType, out var liftedConstructor))
        {
            return liftedConstructor;
        }

        var strongBoxType = CreateStrongBoxType(valueType);
        if (_liftedStorageConstructors.TryGetValue(valueType, out liftedConstructor))
        {
            return liftedConstructor;
        }

        var openConstructor = typeof(System.Runtime.CompilerServices.StrongBox<>)
            .GetConstructor(new[] { typeof(System.Runtime.CompilerServices.StrongBox<>).GetGenericArguments()[0] })
            ?? throw new InvalidOperationException("Could not resolve StrongBox<T>(T)");

        if (RequiresTypeBuilderMemberResolution(valueType))
        {
            return TypeBuilder.GetConstructor(strongBoxType, openConstructor);
        }

        try
        {
            var constructor = strongBoxType.GetConstructor(new[] { valueType });
            if (constructor != null)
            {
                return constructor;
            }
        }
        catch (NotSupportedException)
        {
            if (strongBoxType.IsGenericType)
            {
                return TypeBuilder.GetConstructor(strongBoxType, openConstructor);
            }
        }

        throw new InvalidOperationException($"Could not resolve StrongBox constructor for {valueType}");
    }

    private FieldInfo GetStrongBoxValueField(Type strongBoxType)
    {
        if (_liftedStorageValueFields.TryGetValue(strongBoxType, out var liftedValueField))
        {
            return liftedValueField;
        }

        var openField = typeof(System.Runtime.CompilerServices.StrongBox<>).GetField("Value")
            ?? throw new InvalidOperationException("Could not resolve StrongBox<T>.Value");

        if (strongBoxType.IsGenericType
            && strongBoxType.GetGenericArguments().Any(RequiresTypeBuilderMemberResolution))
        {
            return TypeBuilder.GetField(strongBoxType, openField);
        }

        try
        {
            var field = strongBoxType.GetField("Value");
            if (field != null)
            {
                return field;
            }
        }
        catch (NotSupportedException)
        {
            if (strongBoxType.IsGenericType)
            {
                return TypeBuilder.GetField(strongBoxType, openField);
            }
        }

        throw new InvalidOperationException($"Could not resolve StrongBox.Value for {strongBoxType}");
    }

    private Type GetStrongBoxValueType(Type strongBoxType)
    {
        if (_liftedStorageValueTypes.TryGetValue(strongBoxType, out var liftedValueType))
        {
            return liftedValueType;
        }

        return strongBoxType.IsGenericType && strongBoxType.GetGenericTypeDefinition() == typeof(System.Runtime.CompilerServices.StrongBox<>)
            ? strongBoxType.GetGenericArguments()[0]
            : strongBoxType;
    }

    private bool IsLiftedStorageType(Type storageType, Type valueType)
    {
        if (_liftedStorageValueTypes.TryGetValue(storageType, out var liftedValueType))
        {
            return AreTypeIdentitiesEquivalent(liftedValueType, valueType);
        }

        try
        {
            return storageType.IsGenericType
                && storageType.GetGenericTypeDefinition() == typeof(System.Runtime.CompilerServices.StrongBox<>)
                && AreTypeIdentitiesEquivalent(storageType.GetGenericArguments()[0], valueType);
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private bool IsLiftedIdentifier(string name)
    {
        return _liftedIdentifiers?.Contains(name) == true;
    }

    private bool IsLiftedClosureField(string name)
    {
        return _liftedClosureFields?.Contains(name) == true;
    }

    private bool ShouldLiftLocalIntoBox(string name)
    {
        return _liftLocalsIntoBoxes
            && (_localsToLiftIntoBoxes == null || _localsToLiftIntoBoxes.Contains(name));
    }

    private bool ShouldPredeclareLocalForCapture(string name)
    {
        return ShouldLiftLocalIntoBox(name)
            || _localsToPredeclareForCapture?.Contains(name) == true;
    }

    private LocalBuilder DeclareNamedLocal(string name, Type valueType)
    {
        if (_currentIL == null || _locals == null)
            throw new InvalidOperationException("No IL generator context");

        var shouldLift = ShouldLiftLocalIntoBox(name);
        var storageType = shouldLift ? CreateStrongBoxType(valueType) : valueType;
        var local = _currentIL.DeclareLocal(storageType);
        _locals[name] = local;

        if (shouldLift)
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

        if (IsLiftedStorageType(local.LocalType, valueType))
        {
            var storageConstructor = GetStrongBoxConstructor(valueType);
            try
            {
                _currentIL.Emit(OpCodes.Newobj, storageConstructor);
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException or InvalidOperationException)
            {
                throw new InvalidOperationException(
                    $"Could not box lifted local of type {GetTypeKey(valueType)} into storage type {GetTypeKey(local.LocalType)} using constructor {storageConstructor.DeclaringType?.FullName ?? storageConstructor.ToString()}",
                    ex);
            }
        }
        else if (!AreTypeIdentitiesEquivalent(local.LocalType, valueType))
        {
            throw new InvalidOperationException(
                $"Cannot initialize local of type {GetTypeKey(local.LocalType)} with value of type {GetTypeKey(valueType)}");
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

    private void InitializeBodyContextForBody(
        Type? returnType,
        BlockStatement? body,
        Expression? expressionBody,
        IReadOnlyList<Parameter> parameters)
    {
        var captureStorage = GetLocalCaptureStorageInfo(body, expressionBody, parameters);
        InitializeBodyContext(
            returnType,
            captureStorage.LocalsToLiftIntoBoxes.Count > 0,
            captureStorage.LocalsToLiftIntoBoxes,
            captureStorage.CapturedLocals);
    }

    private LocalCaptureStorageInfo GetLocalCaptureStorageInfo(
        BlockStatement? body,
        Expression? expressionBody,
        IReadOnlyList<Parameter> parameters)
    {
        var containsNestedFunction = ContainsNestedFunction(body)
            || (expressionBody != null && ContainsNestedFunction(expressionBody));
        if (!containsNestedFunction)
        {
            return new LocalCaptureStorageInfo(
                new HashSet<string>(StringComparer.Ordinal),
                new HashSet<string>(StringComparer.Ordinal));
        }

        var candidates = new HashSet<string>(parameters.Select(parameter => parameter.Name), StringComparer.Ordinal);
        if (body != null)
        {
            CollectPotentialLocalStorageNames(body, candidates);
        }
        if (expressionBody != null)
        {
            CollectPotentialLocalStorageNames(expressionBody, candidates);
        }

        var captured = new HashSet<string>(StringComparer.Ordinal);
        if (body != null)
        {
            CollectNestedFunctionCapturedStorageNames(body, candidates, captured);
        }

        if (expressionBody != null)
        {
            CollectNestedFunctionCapturedStorageNames(expressionBody, candidates, captured);
        }

        if (captured.Count == 0)
        {
            return new LocalCaptureStorageInfo(
                captured,
                new HashSet<string>(StringComparer.Ordinal));
        }

        var mutated = new HashSet<string>(StringComparer.Ordinal);
        if (body != null)
        {
            CollectMutatedCapturedStorageNames(body, captured, mutated);
        }
        if (expressionBody != null)
        {
            CollectMutatedCapturedStorageNames(expressionBody, captured, mutated);
        }

        CollectEscapingLocalFunctionCapturedStorageNames(body, candidates, mutated);

        return new LocalCaptureStorageInfo(captured, mutated);
    }

    private void CollectEscapingLocalFunctionCapturedStorageNames(
        BlockStatement? block,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        if (block == null)
        {
            return;
        }

        var localFunctions = block.Statements
            .OfType<LocalFunctionStatement>()
            .ToList();
        if (localFunctions.Count > 0)
        {
            var localFunctionNames = localFunctions
                .Select(localFunction => localFunction.Function.Name)
                .ToHashSet(StringComparer.Ordinal);
            var escapingNames = new HashSet<string>(StringComparer.Ordinal);

            foreach (var statement in block.Statements)
            {
                if (statement is LocalFunctionStatement localFunction)
                {
                    if (localFunction.Function.ExpressionBody != null)
                    {
                        FindEscapingLocalFunctionReferences(
                            localFunction.Function.ExpressionBody,
                            localFunctionNames,
                            escapingNames,
                            isDirectCallCallee: false);
                    }

                    if (localFunction.Function.Body != null)
                    {
                        FindEscapingLocalFunctionReferences(
                            localFunction.Function.Body,
                            localFunctionNames,
                            escapingNames);
                    }

                    continue;
                }

                FindEscapingLocalFunctionReferences(statement, localFunctionNames, escapingNames);
            }

            foreach (var localFunction in localFunctions)
            {
                if (escapingNames.Contains(localFunction.Function.Name))
                {
                    CollectFunctionCapturedStorageNames(localFunction.Function, candidates, captured);
                }
            }
        }

        foreach (var statement in block.Statements)
        {
            CollectEscapingLocalFunctionCapturedStorageNames(statement, candidates, captured);
        }
    }

    private void CollectEscapingLocalFunctionCapturedStorageNames(
        Statement statement,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        switch (statement)
        {
            case BlockStatement block:
                CollectEscapingLocalFunctionCapturedStorageNames(block, candidates, captured);
                break;
            case LocalFunctionStatement localFunction:
                CollectEscapingLocalFunctionCapturedStorageNames(localFunction.Function.Body, candidates, captured);
                if (localFunction.Function.ExpressionBody != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(localFunction.Function.ExpressionBody, candidates, captured);
                }
                break;
            case ExpressionStatement expressionStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(expressionStatement.Expression, candidates, captured);
                break;
            case VariableDeclarationStatement variableDeclaration when variableDeclaration.Initializer != null:
                CollectEscapingLocalFunctionCapturedStorageNames(variableDeclaration.Initializer, candidates, captured);
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                CollectEscapingLocalFunctionCapturedStorageNames(tupleDeconstruction.Initializer, candidates, captured);
                break;
            case IfStatement ifStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(ifStatement.ThenStatement, candidates, captured);
                if (ifStatement.ElseStatement != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(ifStatement.ElseStatement, candidates, captured);
                }
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(forStatement.Initializer, candidates, captured);
                }
                if (forStatement.Iterator != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(forStatement.Iterator, candidates, captured);
                }
                CollectEscapingLocalFunctionCapturedStorageNames(forStatement.Body, candidates, captured);
                break;
            case ForeachStatement foreachStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(foreachStatement.Body, candidates, captured);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(awaitForEachStatement.Body, candidates, captured);
                break;
            case WhileStatement whileStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(whileStatement.Body, candidates, captured);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                CollectEscapingLocalFunctionCapturedStorageNames(returnStatement.Value, candidates, captured);
                break;
            case YieldStatement yieldStatement when yieldStatement.Value != null:
                CollectEscapingLocalFunctionCapturedStorageNames(yieldStatement.Value, candidates, captured);
                break;
            case ThrowStatement throwStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(throwStatement.Expression, candidates, captured);
                break;
            case TryStatement tryStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(tryStatement.TryBlock, candidates, captured);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(catchClause.Block, candidates, captured);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(tryStatement.FinallyBlock, candidates, captured);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(usingStatement.Declaration.Initializer, candidates, captured);
                }
                if (usingStatement.Expression != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(usingStatement.Expression, candidates, captured);
                }
                if (usingStatement.Body != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(usingStatement.Body, candidates, captured);
                }
                break;
            case LockStatement lockStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(lockStatement.Body, candidates, captured);
                break;
            case SwitchStatement switchStatement:
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectEscapingLocalFunctionCapturedStorageNames(caseStatement, candidates, captured);
                    }
                }
                break;
            case PrintStatement printStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(printStatement.Value, candidates, captured);
                break;
            case AssertStatement assertStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(assertStatement.Condition, candidates, captured);
                if (assertStatement.Message != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(assertStatement.Message, candidates, captured);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                CollectEscapingLocalFunctionCapturedStorageNames(assertThrowsStatement.Body, candidates, captured);
                break;
        }
    }

    private void CollectEscapingLocalFunctionCapturedStorageNames(
        Expression expression,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        switch (expression)
        {
            case LambdaExpression lambda:
                CollectEscapingLocalFunctionCapturedStorageNames(lambda.BlockBody, candidates, captured);
                break;
            case BinaryExpression binary:
                CollectEscapingLocalFunctionCapturedStorageNames(binary.Left, candidates, captured);
                CollectEscapingLocalFunctionCapturedStorageNames(binary.Right, candidates, captured);
                break;
            case UnaryExpression unary:
                CollectEscapingLocalFunctionCapturedStorageNames(unary.Operand, candidates, captured);
                break;
            case CallExpression call:
                CollectEscapingLocalFunctionCapturedStorageNames(call.Callee, candidates, captured);
                foreach (var argument in call.Arguments)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(argument.Value, candidates, captured);
                }
                break;
            case AssignmentExpression assignment:
                CollectEscapingLocalFunctionCapturedStorageNames(assignment.Target, candidates, captured);
                CollectEscapingLocalFunctionCapturedStorageNames(assignment.Value, candidates, captured);
                break;
            case MemberAccessExpression memberAccess:
                CollectEscapingLocalFunctionCapturedStorageNames(memberAccess.Object, candidates, captured);
                break;
            case IndexAccessExpression indexAccess:
                CollectEscapingLocalFunctionCapturedStorageNames(indexAccess.Object, candidates, captured);
                CollectEscapingLocalFunctionCapturedStorageNames(indexAccess.Index, candidates, captured);
                break;
            case TernaryExpression ternary:
                CollectEscapingLocalFunctionCapturedStorageNames(ternary.Condition, candidates, captured);
                CollectEscapingLocalFunctionCapturedStorageNames(ternary.ThenExpression, candidates, captured);
                CollectEscapingLocalFunctionCapturedStorageNames(ternary.ElseExpression, candidates, captured);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(element, candidates, captured);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(element.Value, candidates, captured);
                }
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectEscapingLocalFunctionCapturedStorageNames(property.IndexExpression, candidates, captured);
                    }
                    CollectEscapingLocalFunctionCapturedStorageNames(property.Value, candidates, captured);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(argument.Value, candidates, captured);
                }
                if (newExpression.Initializer != null)
                {
                    CollectEscapingLocalFunctionCapturedStorageNames(newExpression.Initializer, candidates, captured);
                }
                break;
            case CastExpression castExpression:
                CollectEscapingLocalFunctionCapturedStorageNames(castExpression.Expression, candidates, captured);
                break;
            case MatchExpression matchExpression:
                CollectEscapingLocalFunctionCapturedStorageNames(matchExpression.Value, candidates, captured);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                    {
                        CollectEscapingLocalFunctionCapturedStorageNames(matchCase.Guard, candidates, captured);
                    }
                    CollectEscapingLocalFunctionCapturedStorageNames(matchCase.Expression, candidates, captured);
                }
                break;
            case WithExpression withExpression:
                CollectEscapingLocalFunctionCapturedStorageNames(withExpression.Target, candidates, captured);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectEscapingLocalFunctionCapturedStorageNames(property.IndexExpression, candidates, captured);
                    }
                    CollectEscapingLocalFunctionCapturedStorageNames(property.Value, candidates, captured);
                }
                break;
            case ParenthesizedExpression parenthesizedExpression:
                CollectEscapingLocalFunctionCapturedStorageNames(parenthesizedExpression.Inner, candidates, captured);
                break;
        }
    }

    private static void CollectMutatedCapturedStorageNames(
        Statement statement,
        HashSet<string> captured,
        HashSet<string> mutated)
    {
        switch (statement)
        {
            case BlockStatement block:
                foreach (var innerStatement in block.Statements)
                {
                    CollectMutatedCapturedStorageNames(innerStatement, captured, mutated);
                }
                break;
            case ExpressionStatement expressionStatement:
                CollectMutatedCapturedStorageNames(expressionStatement.Expression, captured, mutated);
                break;
            case VariableDeclarationStatement variableDeclaration when variableDeclaration.Initializer != null:
                CollectMutatedCapturedStorageNames(variableDeclaration.Initializer, captured, mutated);
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                CollectMutatedCapturedStorageNames(tupleDeconstruction.Initializer, captured, mutated);
                break;
            case LocalFunctionStatement localFunction:
                var localFunctionCaptured = RemoveShadowedCapturedNames(
                    captured,
                    localFunction.Function.Parameters.Select(parameter => parameter.Name));
                if (localFunction.Function.ExpressionBody != null)
                {
                    CollectMutatedCapturedStorageNames(localFunction.Function.ExpressionBody, localFunctionCaptured, mutated);
                }
                if (localFunction.Function.Body != null)
                {
                    CollectMutatedCapturedStorageNames(localFunction.Function.Body, localFunctionCaptured, mutated);
                }
                break;
            case IfStatement ifStatement:
                CollectMutatedCapturedStorageNames(ifStatement.Condition, captured, mutated);
                CollectMutatedCapturedStorageNames(ifStatement.ThenStatement, captured, mutated);
                if (ifStatement.ElseStatement != null)
                {
                    CollectMutatedCapturedStorageNames(ifStatement.ElseStatement, captured, mutated);
                }
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectMutatedCapturedStorageNames(forStatement.Initializer, captured, mutated);
                }
                if (forStatement.Condition != null)
                {
                    CollectMutatedCapturedStorageNames(forStatement.Condition, captured, mutated);
                }
                if (forStatement.Iterator != null)
                {
                    CollectMutatedCapturedStorageNames(forStatement.Iterator, captured, mutated);
                }
                CollectMutatedCapturedStorageNames(forStatement.Body, captured, mutated);
                break;
            case ForeachStatement foreachStatement:
                CollectMutatedCapturedStorageNames(foreachStatement.Collection, captured, mutated);
                CollectMutatedCapturedStorageNames(foreachStatement.Body, captured, mutated);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                CollectMutatedCapturedStorageNames(awaitForEachStatement.Collection, captured, mutated);
                CollectMutatedCapturedStorageNames(awaitForEachStatement.Body, captured, mutated);
                break;
            case WhileStatement whileStatement:
                CollectMutatedCapturedStorageNames(whileStatement.Condition, captured, mutated);
                CollectMutatedCapturedStorageNames(whileStatement.Body, captured, mutated);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                CollectMutatedCapturedStorageNames(returnStatement.Value, captured, mutated);
                break;
            case YieldStatement yieldStatement when yieldStatement.Value != null:
                CollectMutatedCapturedStorageNames(yieldStatement.Value, captured, mutated);
                break;
            case ThrowStatement throwStatement:
                CollectMutatedCapturedStorageNames(throwStatement.Expression, captured, mutated);
                break;
            case TryStatement tryStatement:
                CollectMutatedCapturedStorageNames(tryStatement.TryBlock, captured, mutated);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectMutatedCapturedStorageNames(catchClause.Block, captured, mutated);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectMutatedCapturedStorageNames(tryStatement.FinallyBlock, captured, mutated);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                {
                    CollectMutatedCapturedStorageNames(usingStatement.Declaration.Initializer, captured, mutated);
                }
                if (usingStatement.Expression != null)
                {
                    CollectMutatedCapturedStorageNames(usingStatement.Expression, captured, mutated);
                }
                if (usingStatement.Body != null)
                {
                    CollectMutatedCapturedStorageNames(usingStatement.Body, captured, mutated);
                }
                break;
            case LockStatement lockStatement:
                CollectMutatedCapturedStorageNames(lockStatement.LockObject, captured, mutated);
                CollectMutatedCapturedStorageNames(lockStatement.Body, captured, mutated);
                break;
            case SwitchStatement switchStatement:
                CollectMutatedCapturedStorageNames(switchStatement.Value, captured, mutated);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectMutatedCapturedStorageNames(caseStatement, captured, mutated);
                    }
                }
                break;
            case PrintStatement printStatement:
                CollectMutatedCapturedStorageNames(printStatement.Value, captured, mutated);
                break;
            case AssertStatement assertStatement:
                CollectMutatedCapturedStorageNames(assertStatement.Condition, captured, mutated);
                if (assertStatement.Message != null)
                {
                    CollectMutatedCapturedStorageNames(assertStatement.Message, captured, mutated);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                CollectMutatedCapturedStorageNames(assertThrowsStatement.Body, captured, mutated);
                break;
        }
    }

    private static void CollectMutatedCapturedStorageNames(
        Expression expression,
        HashSet<string> captured,
        HashSet<string> mutated)
    {
        switch (expression)
        {
            case AssignmentExpression assignment:
                AddMutatedTargetName(assignment.Target, captured, mutated);
                CollectMutatedCapturedStorageNames(assignment.Value, captured, mutated);
                break;
            case UnaryExpression { Operator: UnaryOperator.PreIncrement or UnaryOperator.PreDecrement or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement } unary:
                AddMutatedTargetName(unary.Operand, captured, mutated);
                break;
            case LambdaExpression lambda:
                var lambdaCaptured = RemoveShadowedCapturedNames(
                    captured,
                    lambda.Parameters.Select(parameter => parameter.Name));
                if (lambda.ExpressionBody != null)
                {
                    CollectMutatedCapturedStorageNames(lambda.ExpressionBody, lambdaCaptured, mutated);
                }
                if (lambda.BlockBody != null)
                {
                    CollectMutatedCapturedStorageNames(lambda.BlockBody, lambdaCaptured, mutated);
                }
                break;
            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                {
                    CollectMutatedCapturedStorageNames(hole.Expression, captured, mutated);
                }
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    CollectMutatedCapturedStorageNames(range.Start, captured, mutated);
                }
                if (range.End != null)
                {
                    CollectMutatedCapturedStorageNames(range.End, captured, mutated);
                }
                break;
            case BinaryExpression binary:
                CollectMutatedCapturedStorageNames(binary.Left, captured, mutated);
                CollectMutatedCapturedStorageNames(binary.Right, captured, mutated);
                break;
            case UnaryExpression unary:
                CollectMutatedCapturedStorageNames(unary.Operand, captured, mutated);
                break;
            case MustExpression mustExpression:
                CollectMutatedCapturedStorageNames(mustExpression.Expression, captured, mutated);
                break;
            case MemberAccessExpression memberAccess:
                CollectMutatedCapturedStorageNames(memberAccess.Object, captured, mutated);
                break;
            case IndexAccessExpression indexAccess:
                CollectMutatedCapturedStorageNames(indexAccess.Object, captured, mutated);
                CollectMutatedCapturedStorageNames(indexAccess.Index, captured, mutated);
                break;
            case CallExpression call:
                CollectMutatedCapturedStorageNames(call.Callee, captured, mutated);
                foreach (var argument in call.Arguments)
                {
                    if (argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out)
                    {
                        AddMutatedTargetName(argument.Value, captured, mutated);
                    }
                    else
                    {
                        CollectMutatedCapturedStorageNames(argument.Value, captured, mutated);
                    }
                }
                break;
            case TernaryExpression ternary:
                CollectMutatedCapturedStorageNames(ternary.Condition, captured, mutated);
                CollectMutatedCapturedStorageNames(ternary.ThenExpression, captured, mutated);
                CollectMutatedCapturedStorageNames(ternary.ElseExpression, captured, mutated);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectMutatedCapturedStorageNames(element, captured, mutated);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectMutatedCapturedStorageNames(element.Value, captured, mutated);
                }
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectMutatedCapturedStorageNames(property.IndexExpression, captured, mutated);
                    }
                    CollectMutatedCapturedStorageNames(property.Value, captured, mutated);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    if (argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out)
                    {
                        AddMutatedTargetName(argument.Value, captured, mutated);
                    }
                    else
                    {
                        CollectMutatedCapturedStorageNames(argument.Value, captured, mutated);
                    }
                }
                if (newExpression.Initializer != null)
                {
                    CollectMutatedCapturedStorageNames(newExpression.Initializer, captured, mutated);
                }
                break;
            case CastExpression castExpression:
                CollectMutatedCapturedStorageNames(castExpression.Expression, captured, mutated);
                break;
            case IsExpression isExpression:
                CollectMutatedCapturedStorageNames(isExpression.Expression, captured, mutated);
                break;
            case MatchExpression matchExpression:
                CollectMutatedCapturedStorageNames(matchExpression.Value, captured, mutated);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                    {
                        CollectMutatedCapturedStorageNames(matchCase.Guard, captured, mutated);
                    }
                    CollectMutatedCapturedStorageNames(matchCase.Expression, captured, mutated);
                }
                break;
            case SpreadExpression spreadExpression:
                CollectMutatedCapturedStorageNames(spreadExpression.Expression, captured, mutated);
                break;
            case WithExpression withExpression:
                CollectMutatedCapturedStorageNames(withExpression.Target, captured, mutated);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectMutatedCapturedStorageNames(property.IndexExpression, captured, mutated);
                    }
                    CollectMutatedCapturedStorageNames(property.Value, captured, mutated);
                }
                break;
            case AwaitExpression awaitExpression:
                CollectMutatedCapturedStorageNames(awaitExpression.Expression, captured, mutated);
                break;
            case ThrowExpression throwExpression:
                CollectMutatedCapturedStorageNames(throwExpression.Expression, captured, mutated);
                break;
            case NameofExpression nameofExpression:
                CollectMutatedCapturedStorageNames(nameofExpression.Target, captured, mutated);
                break;
            case CheckedExpression checkedExpression:
                CollectMutatedCapturedStorageNames(checkedExpression.Expression, captured, mutated);
                break;
            case UncheckedExpression uncheckedExpression:
                CollectMutatedCapturedStorageNames(uncheckedExpression.Expression, captured, mutated);
                break;
            case ParenthesizedExpression parenthesizedExpression:
                CollectMutatedCapturedStorageNames(parenthesizedExpression.Inner, captured, mutated);
                break;
        }
    }

    private static void AddMutatedTargetName(
        Expression target,
        HashSet<string> captured,
        HashSet<string> mutated)
    {
        switch (target)
        {
            case IdentifierExpression identifier when captured.Contains(identifier.Name):
                mutated.Add(identifier.Name);
                break;
            case ParenthesizedExpression parenthesized:
                AddMutatedTargetName(parenthesized.Inner, captured, mutated);
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    AddMutatedTargetName(element.Value, captured, mutated);
                }
                break;
        }
    }

    private static HashSet<string> RemoveShadowedCapturedNames(
        HashSet<string> captured,
        IEnumerable<string> shadowedNames)
    {
        var shadowed = shadowedNames.ToHashSet(StringComparer.Ordinal);
        return shadowed.Count == 0
            ? captured
            : captured.Where(name => !shadowed.Contains(name)).ToHashSet(StringComparer.Ordinal);
    }

    private static void CollectPotentialLocalStorageNames(Statement statement, HashSet<string> candidates)
    {
        switch (statement)
        {
            case BlockStatement block:
                foreach (var innerStatement in block.Statements)
                {
                    CollectPotentialLocalStorageNames(innerStatement, candidates);
                }
                break;
            case VariableDeclarationStatement variableDeclaration:
                candidates.Add(variableDeclaration.Name);
                if (variableDeclaration.Initializer != null)
                {
                    CollectPotentialLocalStorageNames(variableDeclaration.Initializer, candidates);
                }
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                foreach (var name in tupleDeconstruction.Names)
                {
                    if (name != "_")
                    {
                        candidates.Add(name);
                    }
                }
                CollectPotentialLocalStorageNames(tupleDeconstruction.Initializer, candidates);
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectPotentialLocalStorageNames(forStatement.Initializer, candidates);
                }
                if (forStatement.Condition != null)
                {
                    CollectPotentialLocalStorageNames(forStatement.Condition, candidates);
                }
                if (forStatement.Iterator != null)
                {
                    CollectPotentialLocalStorageNames(forStatement.Iterator, candidates);
                }
                CollectPotentialLocalStorageNames(forStatement.Body, candidates);
                break;
            case ForeachStatement foreachStatement:
                candidates.Add(foreachStatement.VariableName);
                CollectPotentialLocalStorageNames(foreachStatement.Collection, candidates);
                CollectPotentialLocalStorageNames(foreachStatement.Body, candidates);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                candidates.Add(awaitForEachStatement.VariableName);
                CollectPotentialLocalStorageNames(awaitForEachStatement.Collection, candidates);
                CollectPotentialLocalStorageNames(awaitForEachStatement.Body, candidates);
                break;
            case IfStatement ifStatement:
                CollectPotentialLocalStorageNames(ifStatement.Condition, candidates);
                CollectPotentialLocalStorageNames(ifStatement.ThenStatement, candidates);
                if (ifStatement.ElseStatement != null)
                {
                    CollectPotentialLocalStorageNames(ifStatement.ElseStatement, candidates);
                }
                break;
            case WhileStatement whileStatement:
                CollectPotentialLocalStorageNames(whileStatement.Condition, candidates);
                CollectPotentialLocalStorageNames(whileStatement.Body, candidates);
                break;
            case TryStatement tryStatement:
                CollectPotentialLocalStorageNames(tryStatement.TryBlock, candidates);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    if (catchClause.VariableName != null)
                    {
                        candidates.Add(catchClause.VariableName);
                    }
                    CollectPotentialLocalStorageNames(catchClause.Block, candidates);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectPotentialLocalStorageNames(tryStatement.FinallyBlock, candidates);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration != null)
                {
                    CollectPotentialLocalStorageNames(usingStatement.Declaration, candidates);
                }
                if (usingStatement.Expression != null)
                {
                    CollectPotentialLocalStorageNames(usingStatement.Expression, candidates);
                }
                if (usingStatement.Body != null)
                {
                    CollectPotentialLocalStorageNames(usingStatement.Body, candidates);
                }
                break;
            case LockStatement lockStatement:
                CollectPotentialLocalStorageNames(lockStatement.LockObject, candidates);
                CollectPotentialLocalStorageNames(lockStatement.Body, candidates);
                break;
            case SwitchStatement switchStatement:
                CollectPotentialLocalStorageNames(switchStatement.Value, candidates);
                foreach (var switchCase in switchStatement.Cases)
                {
                    if (switchCase.Pattern != null)
                    {
                        CollectPatternBindingNames(switchCase.Pattern, candidates);
                    }
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectPotentialLocalStorageNames(caseStatement, candidates);
                    }
                }
                break;
            case ExpressionStatement expressionStatement:
                CollectPotentialLocalStorageNames(expressionStatement.Expression, candidates);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                CollectPotentialLocalStorageNames(returnStatement.Value, candidates);
                break;
            case YieldStatement yieldStatement when yieldStatement.Value != null:
                CollectPotentialLocalStorageNames(yieldStatement.Value, candidates);
                break;
            case ThrowStatement throwStatement:
                CollectPotentialLocalStorageNames(throwStatement.Expression, candidates);
                break;
            case PrintStatement printStatement:
                CollectPotentialLocalStorageNames(printStatement.Value, candidates);
                break;
            case AssertStatement assertStatement:
                CollectPotentialLocalStorageNames(assertStatement.Condition, candidates);
                if (assertStatement.Message != null)
                {
                    CollectPotentialLocalStorageNames(assertStatement.Message, candidates);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                CollectPotentialLocalStorageNames(assertThrowsStatement.Body, candidates);
                break;
            case LocalFunctionStatement:
                break;
        }
    }

    private static void CollectPotentialLocalStorageNames(Expression expression, HashSet<string> candidates)
    {
        switch (expression)
        {
            case LambdaExpression:
                break;
            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                {
                    CollectPotentialLocalStorageNames(hole.Expression, candidates);
                }
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    CollectPotentialLocalStorageNames(range.Start, candidates);
                }
                if (range.End != null)
                {
                    CollectPotentialLocalStorageNames(range.End, candidates);
                }
                break;
            case BinaryExpression binary:
                CollectPotentialLocalStorageNames(binary.Left, candidates);
                CollectPotentialLocalStorageNames(binary.Right, candidates);
                break;
            case UnaryExpression unary:
                CollectPotentialLocalStorageNames(unary.Operand, candidates);
                break;
            case MustExpression mustExpression:
                CollectPotentialLocalStorageNames(mustExpression.Expression, candidates);
                break;
            case MemberAccessExpression memberAccess:
                CollectPotentialLocalStorageNames(memberAccess.Object, candidates);
                break;
            case IndexAccessExpression indexAccess:
                CollectPotentialLocalStorageNames(indexAccess.Object, candidates);
                CollectPotentialLocalStorageNames(indexAccess.Index, candidates);
                break;
            case CallExpression call:
                CollectPotentialLocalStorageNames(call.Callee, candidates);
                foreach (var argument in call.Arguments)
                {
                    CollectPotentialLocalStorageNames(argument.Value, candidates);
                }
                break;
            case AssignmentExpression assignment:
                CollectPotentialLocalStorageNames(assignment.Target, candidates);
                CollectPotentialLocalStorageNames(assignment.Value, candidates);
                break;
            case TernaryExpression ternary:
                CollectPotentialLocalStorageNames(ternary.Condition, candidates);
                CollectPotentialLocalStorageNames(ternary.ThenExpression, candidates);
                CollectPotentialLocalStorageNames(ternary.ElseExpression, candidates);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectPotentialLocalStorageNames(element, candidates);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectPotentialLocalStorageNames(element.Value, candidates);
                }
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectPotentialLocalStorageNames(property.IndexExpression, candidates);
                    }
                    CollectPotentialLocalStorageNames(property.Value, candidates);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    CollectPotentialLocalStorageNames(argument.Value, candidates);
                }
                if (newExpression.Initializer != null)
                {
                    CollectPotentialLocalStorageNames(newExpression.Initializer, candidates);
                }
                break;
            case CastExpression castExpression:
                CollectPotentialLocalStorageNames(castExpression.Expression, candidates);
                break;
            case IsExpression isExpression:
                CollectPotentialLocalStorageNames(isExpression.Expression, candidates);
                if (isExpression.VariableName != null)
                {
                    candidates.Add(isExpression.VariableName);
                }
                break;
            case MatchExpression matchExpression:
                CollectPotentialLocalStorageNames(matchExpression.Value, candidates);
                foreach (var matchCase in matchExpression.Cases)
                {
                    CollectPatternBindingNames(matchCase.Pattern, candidates);
                    if (matchCase.Guard != null)
                    {
                        CollectPotentialLocalStorageNames(matchCase.Guard, candidates);
                    }
                    CollectPotentialLocalStorageNames(matchCase.Expression, candidates);
                }
                break;
            case SpreadExpression spreadExpression:
                CollectPotentialLocalStorageNames(spreadExpression.Expression, candidates);
                break;
            case WithExpression withExpression:
                CollectPotentialLocalStorageNames(withExpression.Target, candidates);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectPotentialLocalStorageNames(property.IndexExpression, candidates);
                    }
                    CollectPotentialLocalStorageNames(property.Value, candidates);
                }
                break;
            case AwaitExpression awaitExpression:
                CollectPotentialLocalStorageNames(awaitExpression.Expression, candidates);
                break;
            case ThrowExpression throwExpression:
                CollectPotentialLocalStorageNames(throwExpression.Expression, candidates);
                break;
            case NameofExpression nameofExpression:
                CollectPotentialLocalStorageNames(nameofExpression.Target, candidates);
                break;
            case CheckedExpression checkedExpression:
                CollectPotentialLocalStorageNames(checkedExpression.Expression, candidates);
                break;
            case UncheckedExpression uncheckedExpression:
                CollectPotentialLocalStorageNames(uncheckedExpression.Expression, candidates);
                break;
            case ParenthesizedExpression parenthesizedExpression:
                CollectPotentialLocalStorageNames(parenthesizedExpression.Inner, candidates);
                break;
        }
    }

    private static void CollectNestedFunctionCapturedStorageNames(
        Statement statement,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        switch (statement)
        {
            case LocalFunctionStatement localFunction:
                CollectFunctionCapturedStorageNames(localFunction.Function, candidates, captured);
                break;
            case BlockStatement block:
                foreach (var innerStatement in block.Statements)
                {
                    CollectNestedFunctionCapturedStorageNames(innerStatement, candidates, captured);
                }
                break;
            case ExpressionStatement expressionStatement:
                CollectNestedFunctionCapturedStorageNames(expressionStatement.Expression, candidates, captured);
                break;
            case VariableDeclarationStatement variableDeclaration when variableDeclaration.Initializer != null:
                CollectNestedFunctionCapturedStorageNames(variableDeclaration.Initializer, candidates, captured);
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                CollectNestedFunctionCapturedStorageNames(tupleDeconstruction.Initializer, candidates, captured);
                break;
            case IfStatement ifStatement:
                CollectNestedFunctionCapturedStorageNames(ifStatement.Condition, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(ifStatement.ThenStatement, candidates, captured);
                if (ifStatement.ElseStatement != null)
                {
                    CollectNestedFunctionCapturedStorageNames(ifStatement.ElseStatement, candidates, captured);
                }
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectNestedFunctionCapturedStorageNames(forStatement.Initializer, candidates, captured);
                }
                if (forStatement.Condition != null)
                {
                    CollectNestedFunctionCapturedStorageNames(forStatement.Condition, candidates, captured);
                }
                if (forStatement.Iterator != null)
                {
                    CollectNestedFunctionCapturedStorageNames(forStatement.Iterator, candidates, captured);
                }
                CollectNestedFunctionCapturedStorageNames(forStatement.Body, candidates, captured);
                break;
            case ForeachStatement foreachStatement:
                CollectNestedFunctionCapturedStorageNames(foreachStatement.Collection, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(foreachStatement.Body, candidates, captured);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                CollectNestedFunctionCapturedStorageNames(awaitForEachStatement.Collection, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(awaitForEachStatement.Body, candidates, captured);
                break;
            case WhileStatement whileStatement:
                CollectNestedFunctionCapturedStorageNames(whileStatement.Condition, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(whileStatement.Body, candidates, captured);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                CollectNestedFunctionCapturedStorageNames(returnStatement.Value, candidates, captured);
                break;
            case YieldStatement yieldStatement when yieldStatement.Value != null:
                CollectNestedFunctionCapturedStorageNames(yieldStatement.Value, candidates, captured);
                break;
            case ThrowStatement throwStatement:
                CollectNestedFunctionCapturedStorageNames(throwStatement.Expression, candidates, captured);
                break;
            case TryStatement tryStatement:
                CollectNestedFunctionCapturedStorageNames(tryStatement.TryBlock, candidates, captured);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectNestedFunctionCapturedStorageNames(catchClause.Block, candidates, captured);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectNestedFunctionCapturedStorageNames(tryStatement.FinallyBlock, candidates, captured);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                {
                    CollectNestedFunctionCapturedStorageNames(usingStatement.Declaration.Initializer, candidates, captured);
                }
                if (usingStatement.Expression != null)
                {
                    CollectNestedFunctionCapturedStorageNames(usingStatement.Expression, candidates, captured);
                }
                if (usingStatement.Body != null)
                {
                    CollectNestedFunctionCapturedStorageNames(usingStatement.Body, candidates, captured);
                }
                break;
            case LockStatement lockStatement:
                CollectNestedFunctionCapturedStorageNames(lockStatement.LockObject, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(lockStatement.Body, candidates, captured);
                break;
            case SwitchStatement switchStatement:
                CollectNestedFunctionCapturedStorageNames(switchStatement.Value, candidates, captured);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectNestedFunctionCapturedStorageNames(caseStatement, candidates, captured);
                    }
                }
                break;
            case PrintStatement printStatement:
                CollectNestedFunctionCapturedStorageNames(printStatement.Value, candidates, captured);
                break;
            case AssertStatement assertStatement:
                CollectNestedFunctionCapturedStorageNames(assertStatement.Condition, candidates, captured);
                if (assertStatement.Message != null)
                {
                    CollectNestedFunctionCapturedStorageNames(assertStatement.Message, candidates, captured);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                CollectNestedFunctionCapturedStorageNames(assertThrowsStatement.Body, candidates, captured);
                break;
        }
    }

    private static void CollectNestedFunctionCapturedStorageNames(
        Expression expression,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        switch (expression)
        {
            case LambdaExpression lambda:
                CollectLambdaCapturedStorageNames(lambda, candidates, captured);
                break;
            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                {
                    CollectNestedFunctionCapturedStorageNames(hole.Expression, candidates, captured);
                }
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    CollectNestedFunctionCapturedStorageNames(range.Start, candidates, captured);
                }
                if (range.End != null)
                {
                    CollectNestedFunctionCapturedStorageNames(range.End, candidates, captured);
                }
                break;
            case BinaryExpression binary:
                CollectNestedFunctionCapturedStorageNames(binary.Left, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(binary.Right, candidates, captured);
                break;
            case UnaryExpression unary:
                CollectNestedFunctionCapturedStorageNames(unary.Operand, candidates, captured);
                break;
            case MustExpression mustExpression:
                CollectNestedFunctionCapturedStorageNames(mustExpression.Expression, candidates, captured);
                break;
            case MemberAccessExpression memberAccess:
                CollectNestedFunctionCapturedStorageNames(memberAccess.Object, candidates, captured);
                break;
            case IndexAccessExpression indexAccess:
                CollectNestedFunctionCapturedStorageNames(indexAccess.Object, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(indexAccess.Index, candidates, captured);
                break;
            case CallExpression call:
                CollectNestedFunctionCapturedStorageNames(call.Callee, candidates, captured);
                foreach (var argument in call.Arguments)
                {
                    CollectNestedFunctionCapturedStorageNames(argument.Value, candidates, captured);
                }
                break;
            case AssignmentExpression assignment:
                CollectNestedFunctionCapturedStorageNames(assignment.Target, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(assignment.Value, candidates, captured);
                break;
            case TernaryExpression ternary:
                CollectNestedFunctionCapturedStorageNames(ternary.Condition, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(ternary.ThenExpression, candidates, captured);
                CollectNestedFunctionCapturedStorageNames(ternary.ElseExpression, candidates, captured);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectNestedFunctionCapturedStorageNames(element, candidates, captured);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectNestedFunctionCapturedStorageNames(element.Value, candidates, captured);
                }
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectNestedFunctionCapturedStorageNames(property.IndexExpression, candidates, captured);
                    }
                    CollectNestedFunctionCapturedStorageNames(property.Value, candidates, captured);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    CollectNestedFunctionCapturedStorageNames(argument.Value, candidates, captured);
                }
                if (newExpression.Initializer != null)
                {
                    CollectNestedFunctionCapturedStorageNames(newExpression.Initializer, candidates, captured);
                }
                break;
            case CastExpression castExpression:
                CollectNestedFunctionCapturedStorageNames(castExpression.Expression, candidates, captured);
                break;
            case IsExpression isExpression:
                CollectNestedFunctionCapturedStorageNames(isExpression.Expression, candidates, captured);
                break;
            case MatchExpression matchExpression:
                CollectNestedFunctionCapturedStorageNames(matchExpression.Value, candidates, captured);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                    {
                        CollectNestedFunctionCapturedStorageNames(matchCase.Guard, candidates, captured);
                    }
                    CollectNestedFunctionCapturedStorageNames(matchCase.Expression, candidates, captured);
                }
                break;
            case SpreadExpression spreadExpression:
                CollectNestedFunctionCapturedStorageNames(spreadExpression.Expression, candidates, captured);
                break;
            case WithExpression withExpression:
                CollectNestedFunctionCapturedStorageNames(withExpression.Target, candidates, captured);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectNestedFunctionCapturedStorageNames(property.IndexExpression, candidates, captured);
                    }
                    CollectNestedFunctionCapturedStorageNames(property.Value, candidates, captured);
                }
                break;
            case AwaitExpression awaitExpression:
                CollectNestedFunctionCapturedStorageNames(awaitExpression.Expression, candidates, captured);
                break;
            case ThrowExpression throwExpression:
                CollectNestedFunctionCapturedStorageNames(throwExpression.Expression, candidates, captured);
                break;
            case NameofExpression nameofExpression:
                CollectNestedFunctionCapturedStorageNames(nameofExpression.Target, candidates, captured);
                break;
            case CheckedExpression checkedExpression:
                CollectNestedFunctionCapturedStorageNames(checkedExpression.Expression, candidates, captured);
                break;
            case UncheckedExpression uncheckedExpression:
                CollectNestedFunctionCapturedStorageNames(uncheckedExpression.Expression, candidates, captured);
                break;
            case ParenthesizedExpression parenthesizedExpression:
                CollectNestedFunctionCapturedStorageNames(parenthesizedExpression.Inner, candidates, captured);
                break;
        }
    }

    private static void CollectFunctionCapturedStorageNames(
        FunctionDeclaration function,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        var shadowed = function.Parameters
            .Select(parameter => parameter.Name)
            .ToHashSet(StringComparer.Ordinal);

        if (function.ExpressionBody != null)
        {
            CollectCandidateIdentifierReferences(function.ExpressionBody, candidates, captured, shadowed);
        }

        if (function.Body != null)
        {
            CollectCandidateIdentifierReferences(function.Body, candidates, captured, shadowed);
        }
    }

    private static void CollectLambdaCapturedStorageNames(
        LambdaExpression lambda,
        HashSet<string> candidates,
        HashSet<string> captured)
    {
        var shadowed = lambda.Parameters
            .Select(parameter => parameter.Name)
            .ToHashSet(StringComparer.Ordinal);

        if (lambda.ExpressionBody != null)
        {
            CollectCandidateIdentifierReferences(lambda.ExpressionBody, candidates, captured, shadowed);
        }

        if (lambda.BlockBody != null)
        {
            CollectCandidateIdentifierReferences(lambda.BlockBody, candidates, captured, shadowed);
        }
    }

    private static void CollectCandidateIdentifierReferences(
        Statement statement,
        HashSet<string> candidates,
        HashSet<string> captured,
        HashSet<string> shadowed)
    {
        switch (statement)
        {
            case BlockStatement block:
                foreach (var innerStatement in block.Statements)
                {
                    CollectCandidateIdentifierReferences(innerStatement, candidates, captured, shadowed);
                }
                break;
            case ExpressionStatement expressionStatement:
                CollectCandidateIdentifierReferences(expressionStatement.Expression, candidates, captured, shadowed);
                break;
            case VariableDeclarationStatement variableDeclaration:
                if (variableDeclaration.Initializer != null)
                {
                    CollectCandidateIdentifierReferences(variableDeclaration.Initializer, candidates, captured, shadowed);
                }
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                CollectCandidateIdentifierReferences(tupleDeconstruction.Initializer, candidates, captured, shadowed);
                break;
            case LocalFunctionStatement localFunction:
                var nestedShadowed = new HashSet<string>(shadowed, StringComparer.Ordinal);
                foreach (var parameter in localFunction.Function.Parameters)
                {
                    nestedShadowed.Add(parameter.Name);
                }
                if (localFunction.Function.ExpressionBody != null)
                {
                    CollectCandidateIdentifierReferences(localFunction.Function.ExpressionBody, candidates, captured, nestedShadowed);
                }
                if (localFunction.Function.Body != null)
                {
                    CollectCandidateIdentifierReferences(localFunction.Function.Body, candidates, captured, nestedShadowed);
                }
                break;
            case IfStatement ifStatement:
                CollectCandidateIdentifierReferences(ifStatement.Condition, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(ifStatement.ThenStatement, candidates, captured, shadowed);
                if (ifStatement.ElseStatement != null)
                {
                    CollectCandidateIdentifierReferences(ifStatement.ElseStatement, candidates, captured, shadowed);
                }
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectCandidateIdentifierReferences(forStatement.Initializer, candidates, captured, shadowed);
                }
                if (forStatement.Condition != null)
                {
                    CollectCandidateIdentifierReferences(forStatement.Condition, candidates, captured, shadowed);
                }
                if (forStatement.Iterator != null)
                {
                    CollectCandidateIdentifierReferences(forStatement.Iterator, candidates, captured, shadowed);
                }
                CollectCandidateIdentifierReferences(forStatement.Body, candidates, captured, shadowed);
                break;
            case ForeachStatement foreachStatement:
                CollectCandidateIdentifierReferences(foreachStatement.Collection, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(foreachStatement.Body, candidates, captured, shadowed);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                CollectCandidateIdentifierReferences(awaitForEachStatement.Collection, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(awaitForEachStatement.Body, candidates, captured, shadowed);
                break;
            case WhileStatement whileStatement:
                CollectCandidateIdentifierReferences(whileStatement.Condition, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(whileStatement.Body, candidates, captured, shadowed);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                CollectCandidateIdentifierReferences(returnStatement.Value, candidates, captured, shadowed);
                break;
            case YieldStatement yieldStatement when yieldStatement.Value != null:
                CollectCandidateIdentifierReferences(yieldStatement.Value, candidates, captured, shadowed);
                break;
            case ThrowStatement throwStatement:
                CollectCandidateIdentifierReferences(throwStatement.Expression, candidates, captured, shadowed);
                break;
            case TryStatement tryStatement:
                CollectCandidateIdentifierReferences(tryStatement.TryBlock, candidates, captured, shadowed);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectCandidateIdentifierReferences(catchClause.Block, candidates, captured, shadowed);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectCandidateIdentifierReferences(tryStatement.FinallyBlock, candidates, captured, shadowed);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                {
                    CollectCandidateIdentifierReferences(usingStatement.Declaration.Initializer, candidates, captured, shadowed);
                }
                if (usingStatement.Expression != null)
                {
                    CollectCandidateIdentifierReferences(usingStatement.Expression, candidates, captured, shadowed);
                }
                if (usingStatement.Body != null)
                {
                    CollectCandidateIdentifierReferences(usingStatement.Body, candidates, captured, shadowed);
                }
                break;
            case LockStatement lockStatement:
                CollectCandidateIdentifierReferences(lockStatement.LockObject, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(lockStatement.Body, candidates, captured, shadowed);
                break;
            case SwitchStatement switchStatement:
                CollectCandidateIdentifierReferences(switchStatement.Value, candidates, captured, shadowed);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectCandidateIdentifierReferences(caseStatement, candidates, captured, shadowed);
                    }
                }
                break;
            case PrintStatement printStatement:
                CollectCandidateIdentifierReferences(printStatement.Value, candidates, captured, shadowed);
                break;
            case AssertStatement assertStatement:
                CollectCandidateIdentifierReferences(assertStatement.Condition, candidates, captured, shadowed);
                if (assertStatement.Message != null)
                {
                    CollectCandidateIdentifierReferences(assertStatement.Message, candidates, captured, shadowed);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                CollectCandidateIdentifierReferences(assertThrowsStatement.Body, candidates, captured, shadowed);
                break;
            case EmptyStatement:
            case BreakStatement:
            case ContinueStatement:
                break;
            default:
                AddUnshadowedCandidates(candidates, captured, shadowed);
                break;
        }
    }

    private static void CollectCandidateIdentifierReferences(
        Expression expression,
        HashSet<string> candidates,
        HashSet<string> captured,
        HashSet<string> shadowed)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                if (!shadowed.Contains(identifier.Name) && candidates.Contains(identifier.Name))
                {
                    captured.Add(identifier.Name);
                }
                break;
            case LambdaExpression lambda:
                var nestedShadowed = new HashSet<string>(shadowed, StringComparer.Ordinal);
                foreach (var parameter in lambda.Parameters)
                {
                    nestedShadowed.Add(parameter.Name);
                }
                if (lambda.ExpressionBody != null)
                {
                    CollectCandidateIdentifierReferences(lambda.ExpressionBody, candidates, captured, nestedShadowed);
                }
                if (lambda.BlockBody != null)
                {
                    CollectCandidateIdentifierReferences(lambda.BlockBody, candidates, captured, nestedShadowed);
                }
                break;
            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                {
                    CollectCandidateIdentifierReferences(hole.Expression, candidates, captured, shadowed);
                }
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    CollectCandidateIdentifierReferences(range.Start, candidates, captured, shadowed);
                }
                if (range.End != null)
                {
                    CollectCandidateIdentifierReferences(range.End, candidates, captured, shadowed);
                }
                break;
            case BinaryExpression binary:
                CollectCandidateIdentifierReferences(binary.Left, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(binary.Right, candidates, captured, shadowed);
                break;
            case UnaryExpression unary:
                CollectCandidateIdentifierReferences(unary.Operand, candidates, captured, shadowed);
                break;
            case MustExpression mustExpression:
                CollectCandidateIdentifierReferences(mustExpression.Expression, candidates, captured, shadowed);
                break;
            case MemberAccessExpression memberAccess:
                CollectCandidateIdentifierReferences(memberAccess.Object, candidates, captured, shadowed);
                break;
            case IndexAccessExpression indexAccess:
                CollectCandidateIdentifierReferences(indexAccess.Object, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(indexAccess.Index, candidates, captured, shadowed);
                break;
            case CallExpression call:
                CollectCandidateIdentifierReferences(call.Callee, candidates, captured, shadowed);
                foreach (var argument in call.Arguments)
                {
                    CollectCandidateIdentifierReferences(argument.Value, candidates, captured, shadowed);
                }
                break;
            case AssignmentExpression assignment:
                CollectCandidateIdentifierReferences(assignment.Target, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(assignment.Value, candidates, captured, shadowed);
                break;
            case TernaryExpression ternary:
                CollectCandidateIdentifierReferences(ternary.Condition, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(ternary.ThenExpression, candidates, captured, shadowed);
                CollectCandidateIdentifierReferences(ternary.ElseExpression, candidates, captured, shadowed);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    CollectCandidateIdentifierReferences(element, candidates, captured, shadowed);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    CollectCandidateIdentifierReferences(element.Value, candidates, captured, shadowed);
                }
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectCandidateIdentifierReferences(property.IndexExpression, candidates, captured, shadowed);
                    }
                    CollectCandidateIdentifierReferences(property.Value, candidates, captured, shadowed);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    CollectCandidateIdentifierReferences(argument.Value, candidates, captured, shadowed);
                }
                if (newExpression.Initializer != null)
                {
                    CollectCandidateIdentifierReferences(newExpression.Initializer, candidates, captured, shadowed);
                }
                break;
            case CastExpression castExpression:
                CollectCandidateIdentifierReferences(castExpression.Expression, candidates, captured, shadowed);
                break;
            case IsExpression isExpression:
                CollectCandidateIdentifierReferences(isExpression.Expression, candidates, captured, shadowed);
                break;
            case MatchExpression matchExpression:
                CollectCandidateIdentifierReferences(matchExpression.Value, candidates, captured, shadowed);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                    {
                        CollectCandidateIdentifierReferences(matchCase.Guard, candidates, captured, shadowed);
                    }
                    CollectCandidateIdentifierReferences(matchCase.Expression, candidates, captured, shadowed);
                }
                break;
            case SpreadExpression spreadExpression:
                CollectCandidateIdentifierReferences(spreadExpression.Expression, candidates, captured, shadowed);
                break;
            case WithExpression withExpression:
                CollectCandidateIdentifierReferences(withExpression.Target, candidates, captured, shadowed);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        CollectCandidateIdentifierReferences(property.IndexExpression, candidates, captured, shadowed);
                    }
                    CollectCandidateIdentifierReferences(property.Value, candidates, captured, shadowed);
                }
                break;
            case AwaitExpression awaitExpression:
                CollectCandidateIdentifierReferences(awaitExpression.Expression, candidates, captured, shadowed);
                break;
            case ThrowExpression throwExpression:
                CollectCandidateIdentifierReferences(throwExpression.Expression, candidates, captured, shadowed);
                break;
            case NameofExpression nameofExpression:
                CollectCandidateIdentifierReferences(nameofExpression.Target, candidates, captured, shadowed);
                break;
            case CheckedExpression checkedExpression:
                CollectCandidateIdentifierReferences(checkedExpression.Expression, candidates, captured, shadowed);
                break;
            case UncheckedExpression uncheckedExpression:
                CollectCandidateIdentifierReferences(uncheckedExpression.Expression, candidates, captured, shadowed);
                break;
            case ParenthesizedExpression parenthesizedExpression:
                CollectCandidateIdentifierReferences(parenthesizedExpression.Inner, candidates, captured, shadowed);
                break;
            case IntLiteralExpression:
            case FloatLiteralExpression:
            case CharLiteralExpression:
            case StringLiteralExpression:
            case BoolLiteralExpression:
            case NullLiteralExpression:
            case ThisExpression:
            case BaseExpression:
            case DefaultExpression:
            case TypeOfExpression:
            case SizeOfExpression:
                break;
            default:
                AddUnshadowedCandidates(candidates, captured, shadowed);
                break;
        }
    }

    private static void AddUnshadowedCandidates(
        HashSet<string> candidates,
        HashSet<string> captured,
        HashSet<string> shadowed)
    {
        foreach (var candidate in candidates)
        {
            if (!shadowed.Contains(candidate))
            {
                captured.Add(candidate);
            }
        }
    }

    private static void CollectPatternBindingNames(Pattern pattern, HashSet<string> candidates)
    {
        switch (pattern)
        {
            case IdentifierPattern identifierPattern:
                candidates.Add(identifierPattern.Name);
                break;
            case UnionCasePattern unionCasePattern when unionCasePattern.Properties != null:
                foreach (var property in unionCasePattern.Properties)
                {
                    if (property.BindingName != null)
                    {
                        candidates.Add(property.BindingName);
                    }
                    if (property.Pattern != null)
                    {
                        CollectPatternBindingNames(property.Pattern, candidates);
                    }
                }
                break;
            case AndPattern andPattern:
                CollectPatternBindingNames(andPattern.Left, candidates);
                CollectPatternBindingNames(andPattern.Right, candidates);
                break;
            case OrPattern orPattern:
                CollectPatternBindingNames(orPattern.Left, candidates);
                CollectPatternBindingNames(orPattern.Right, candidates);
                break;
            case NotPattern notPattern:
                CollectPatternBindingNames(notPattern.Pattern, candidates);
                break;
            case PositionalPattern positionalPattern:
                foreach (var innerPattern in positionalPattern.Patterns)
                {
                    CollectPatternBindingNames(innerPattern, candidates);
                }
                break;
            case ObjectPattern objectPattern:
                foreach (var property in objectPattern.Properties)
                {
                    if (property.BindingName != null)
                    {
                        candidates.Add(property.BindingName);
                    }
                    if (property.Pattern != null)
                    {
                        CollectPatternBindingNames(property.Pattern, candidates);
                    }
                }
                break;
            case ListPattern listPattern:
                foreach (var innerPattern in listPattern.Elements)
                {
                    CollectPatternBindingNames(innerPattern, candidates);
                }
                break;
            case SlicePattern slicePattern when slicePattern.BindingName != null:
                candidates.Add(slicePattern.BindingName);
                break;
            case TypePattern typePattern when typePattern.BindingName != null:
                candidates.Add(typePattern.BindingName);
                break;
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
            MustExpression mustExpression => ContainsNestedFunction(mustExpression.Expression),
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
            MustExpression mustExpression => ContainsAwait(mustExpression.Expression),
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

    private void EnsureNullableMetadataAttributeTypes()
    {
        if (_nullableAttributeByteConstructor != null
            && _nullableAttributeByteArrayConstructor != null
            && _nullableContextAttributeConstructor != null)
        {
            return;
        }

        if (_moduleBuilder == null)
        {
            return;
        }

        var attributeTypeAttributes = TypeAttributes.NotPublic
            | TypeAttributes.Sealed
            | TypeAttributes.Class
            | TypeAttributes.BeforeFieldInit;

        var nullableAttribute = _moduleBuilder.DefineType(
            "System.Runtime.CompilerServices.NullableAttribute",
            attributeTypeAttributes,
            typeof(Attribute));
        _nullableAttributeByteConstructor = DefineNullableAttributeConstructor(nullableAttribute, typeof(byte));
        _nullableAttributeByteArrayConstructor = DefineNullableAttributeConstructor(nullableAttribute, typeof(byte[]));
        _generatedHelperTypes.Add(nullableAttribute);

        var nullableContextAttribute = _moduleBuilder.DefineType(
            "System.Runtime.CompilerServices.NullableContextAttribute",
            attributeTypeAttributes,
            typeof(Attribute));
        _nullableContextAttributeConstructor = DefineNullableAttributeConstructor(nullableContextAttribute, typeof(byte));
        _generatedHelperTypes.Add(nullableContextAttribute);
    }

    private static ConstructorBuilder DefineNullableAttributeConstructor(TypeBuilder attributeType, Type parameterType)
    {
        var baseConstructor = typeof(Attribute).GetConstructor(
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null,
            Type.EmptyTypes,
            modifiers: null)!;
        var constructor = attributeType.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            new[] { parameterType });
        var il = constructor.GetILGenerator();
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Call, baseConstructor);
        il.Emit(OpCodes.Ret);
        return constructor;
    }

    private void ApplyNullableContextAttribute(Action<CustomAttributeBuilder> applyAttribute, byte context = 1)
    {
        EnsureNullableMetadataAttributeTypes();
        if (_nullableContextAttributeConstructor == null)
            return;

        applyAttribute(new CustomAttributeBuilder(_nullableContextAttributeConstructor, new object[] { context }));
    }

    /// <summary>
    /// Emits <see cref="System.Runtime.CompilerServices.IsReadOnlyAttribute"/> on a value type so that
    /// the C# compiler and JIT treat it as a <c>readonly struct</c>. This eliminates defensive copies
    /// when members are invoked through <c>in</c>/readonly references, which is the whole point of
    /// emitting small immutable wrappers (newtypes and readonly record structs) as value types on the
    /// hot path. Without this marker, callers conservatively copy the struct before each member access.
    /// </summary>
    private void ApplyIsReadOnlyAttribute(Action<CustomAttributeBuilder> applyAttribute)
    {
        var attributeType = typeof(System.Runtime.CompilerServices.IsReadOnlyAttribute);
        var constructor = attributeType.GetConstructor(Type.EmptyTypes);
        if (constructor == null)
            return;

        applyAttribute(new CustomAttributeBuilder(constructor, Array.Empty<object>()));
    }

    private void ApplyNullableAttribute(Action<CustomAttributeBuilder> applyAttribute, TypeReference typeReference, GenericTypeParameterBuilder[]? genericParameters = null)
    {
        var flags = GetNullableAttributeFlags(typeReference, genericParameters);
        if (flags.Count == 0 || flags.All(flag => flag == 1))
            return;

        EnsureNullableMetadataAttributeTypes();
        if (flags.Count == 1)
        {
            if (_nullableAttributeByteConstructor != null)
            {
                applyAttribute(new CustomAttributeBuilder(_nullableAttributeByteConstructor, new object[] { flags[0] }));
            }
            return;
        }

        if (_nullableAttributeByteArrayConstructor != null)
        {
            applyAttribute(new CustomAttributeBuilder(_nullableAttributeByteArrayConstructor, new object[] { flags.ToArray() }));
        }
    }

    private List<byte> GetNullableAttributeFlags(TypeReference typeReference, GenericTypeParameterBuilder[]? genericParameters)
    {
        switch (typeReference)
        {
            case NullableTypeReference nullableType:
            {
                var innerFlags = GetNullableAttributeFlags(nullableType.InnerType, genericParameters);
                if (TypeReferenceResolvesToNonNullableValueType(nullableType.InnerType, genericParameters))
                    return innerFlags;

                if (innerFlags.Count == 0)
                    return new List<byte> { 2 };

                innerFlags[0] = 2;
                return innerFlags;
            }

            case ArrayTypeReference arrayType:
            {
                var flags = new List<byte> { 1 };
                flags.AddRange(GetNullableAttributeFlags(arrayType.ElementType, genericParameters));
                return flags;
            }

            case GenericTypeReference genericType:
            {
                var flags = new List<byte>();
                if (!TypeReferenceResolvesToNonNullableValueType(genericType, genericParameters))
                    flags.Add(1);

                foreach (var argument in genericType.TypeArguments)
                    flags.AddRange(GetNullableAttributeFlags(argument, genericParameters));

                return flags;
            }

            case FunctionTypeReference functionType:
            {
                var flags = new List<byte> { 1 };
                foreach (var parameterType in functionType.ParameterTypes)
                    flags.AddRange(GetNullableAttributeFlags(parameterType, genericParameters));
                flags.AddRange(GetNullableAttributeFlags(functionType.ReturnType, genericParameters));
                return flags;
            }

            case UnionTypeReference unionType:
            {
                var flags = new List<byte> { 1 };
                foreach (var arm in FlattenUnionTypeReference(unionType))
                    flags.AddRange(GetNullableAttributeFlags(arm, genericParameters));
                return flags;
            }

            case TupleTypeReference tupleType:
            {
                var flags = new List<byte> { 1 };
                foreach (var element in tupleType.Elements)
                    flags.AddRange(GetNullableAttributeFlags(element.Type, genericParameters));
                return flags;
            }

            default:
                return TypeReferenceResolvesToNonNullableValueType(typeReference, genericParameters)
                    ? new List<byte>()
                    : new List<byte> { 1 };
        }
    }

    private bool TypeReferenceResolvesToNonNullableValueType(TypeReference typeReference, GenericTypeParameterBuilder[]? genericParameters)
    {
        try
        {
            var type = ResolveType(typeReference, genericParameters);
            return type.IsValueType && Nullable.GetUnderlyingType(type) == null;
        }
        catch
        {
            return false;
        }
    }

    private void ApplyParameterAttributes(
        ParameterBuilder parameterBuilder,
        Parameter parameter,
        GenericTypeParameterBuilder[]? genericParameters = null)
    {
        ApplyNullableAttribute(parameterBuilder.SetCustomAttribute, parameter.Type, genericParameters);

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

        if (TryGetEnumUnderlyingType(parameterType) == argumentType)
        {
            return true;
        }

        if (parameterType.IsArray && argumentType.IsArray)
        {
            var parameterElementType = parameterType.GetElementType()!;
            var argumentElementType = argumentType.GetElementType()!;
            return parameterElementType == argumentElementType
                || parameterElementType.IsAssignableFrom(argumentElementType)
                || TryGetEnumUnderlyingType(parameterElementType) == argumentElementType;
        }

        return false;
    }

    private (object? Value, Type Type) EvaluateAttributeArgument(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression intLiteral => (ParseIntLiteralValue(intLiteral.Value), typeof(int)),
            FloatLiteralExpression floatLiteral => EvaluateFloatingLiteralArgument(floatLiteral.Value),
            CharLiteralExpression charLiteral => (ParseCharLiteralValue(charLiteral.Value), typeof(char)),
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

        if (TryGetEnumUnderlyingType(leftType) is { } underlyingType && rightType == leftType)
        {
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

        if (IsEnumType(staticType))
        {
            return (Enum.Parse(staticType, memberAccess.MemberName), staticType);
        }

        if (staticType is TypeBuilder staticTypeBuilder)
        {
            var fieldKey = GetFieldKey(staticTypeBuilder, memberAccess.MemberName);
            if (_fieldConstants.TryGetValue(fieldKey, out var constantValue)
                && _fields.TryGetValue(fieldKey, out var fieldBuilder))
            {
                return (constantValue, GetDeclaredStaticFieldType(staticTypeBuilder, memberAccess.MemberName, fieldBuilder));
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

    private string DescribeCallArgumentTypes(IReadOnlyList<Argument> arguments)
    {
        return string.Join(", ", arguments.Select(argument =>
        {
            var modifier = argument.Modifier switch
            {
                ArgumentModifier.Ref => "ref ",
                ArgumentModifier.Out => "out ",
                _ => string.Empty
            };
            return modifier + GetTypeKey(GetExpressionType(argument.Value));
        }));
    }

    private string GetPrimaryConstructorFieldKey(Type type, string parameterName)
    {
        return $"{GetTypeKey(type)}.<>primary.{parameterName}";
    }

    private string GetIndexerKey(Type type)
    {
        return $"{GetTypeKey(type)}.Item";
    }

    private FieldBuilder? GetCapturedThisField()
    {
        return _closureFields != null && _closureFields.TryGetValue(ThisCaptureName, out var capturedThisField)
            ? capturedThisField
            : null;
    }

    private Type? GetCapturedThisType()
    {
        return GetCapturedThisField()?.FieldType;
    }

    private bool TryGetImplicitInstanceOwnerTypeBuilder(out TypeBuilder typeBuilder)
    {
        var capturedThisType = GetCapturedThisType();
        if (capturedThisType != null && TryGetUserTypeDefinition(capturedThisType, out typeBuilder))
        {
            return true;
        }

        if (_currentHasThis
            && _currentTypeBuilder != null
            && TryGetUserTypeDefinition(_currentTypeBuilder, out typeBuilder))
        {
            return true;
        }

        typeBuilder = null!;
        return false;
    }

    private bool TryGetImplicitInstanceOwnerType(out Type ownerType)
    {
        var capturedThisType = GetCapturedThisType();
        if (capturedThisType != null)
        {
            ownerType = capturedThisType;
            return true;
        }

        if (_currentHasThis && _currentTypeBuilder != null)
        {
            ownerType = _currentTypeBuilder;
            return true;
        }

        ownerType = null!;
        return false;
    }

    private static Type GetImplicitInstanceRuntimeLookupType(Type ownerType)
    {
        return ownerType is TypeBuilder typeBuilder && typeBuilder.BaseType != null
            ? typeBuilder.BaseType
            : ownerType;
    }

    private void EmitLoadImplicitThisReference()
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (GetCapturedThisField() is { } capturedThisField)
        {
            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldfld, capturedThisField);
            return;
        }

        _currentIL.Emit(OpCodes.Ldarg_0);
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
        var unqualifiedGenericTypeKey = typeKey.Contains('`')
            ? typeKey[..typeKey.IndexOf('`')]
            : typeKey;
        foreach (var entry in _typeKeys)
        {
            if ((entry.Value == typeKey || entry.Value == unqualifiedGenericTypeKey)
                && entry.Key is TypeBuilder candidateBuilder)
            {
                typeBuilder = candidateBuilder;
                return true;
            }
        }

        typeBuilder = null!;
        return false;
    }

    /// <summary>
    /// Wraps TypeBuilder.AddInterfaceImplementation and records the interface
    /// so it can be queried before the type is created (.NET 10+ throws
    /// NotSupportedException from TypeBuilder.GetInterfaces() on incomplete types).
    /// </summary>
    private void TrackInterfaceImplementation(TypeBuilder typeBuilder, Type interfaceType)
    {
        typeBuilder.AddInterfaceImplementation(interfaceType);
        if (!_typeBuilderInterfaces.TryGetValue(typeBuilder, out var list))
        {
            list = new List<Type>();
            _typeBuilderInterfaces[typeBuilder] = list;
        }
        list.Add(interfaceType);
    }

    /// <summary>
    /// Returns interfaces for a type, using the tracked list for TypeBuilders
    /// that haven't been created yet (safe on .NET 10+).
    /// </summary>
    private Type[] GetInterfacesSafe(Type type)
    {
        if (type is TypeBuilder tb && _typeBuilderInterfaces.TryGetValue(tb, out var tracked))
        {
            return tracked.ToArray();
        }
        try
        {
            return type.GetInterfaces();
        }
        catch (NotSupportedException)
        {
            return Type.EmptyTypes;
        }
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
            if (type.IsEnum)
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
        }

        try
        {
            return type.BaseType == typeof(Enum);
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (ArgumentException)
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
            return type.BaseType == typeof(Enum) ? typeof(int) : null;
        }
        catch (NotSupportedException)
        {
            return type.BaseType == typeof(Enum) ? typeof(int) : null;
        }
    }

    private bool IsParameterTypeCompatible(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
        {
            return true;
        }

        if (TryGetRuntimeUnionArmTypes(parameterType, out var targetUnionArms))
        {
            if (TryGetRuntimeUnionArmTypes(argumentType, out var sourceUnionArms))
            {
                return sourceUnionArms.All(sourceArm =>
                    targetUnionArms.Any(targetArm => IsParameterTypeCompatible(targetArm, sourceArm)));
            }

            return targetUnionArms.Any(arm => IsParameterTypeCompatible(arm, argumentType));
        }

        if (TryGetRuntimeUnionArmTypes(argumentType, out var argumentUnionArms))
        {
            return argumentUnionArms.All(arm => IsParameterTypeCompatible(parameterType, arm));
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

        var nullableParameterType = Nullable.GetUnderlyingType(parameterType);
        if (nullableParameterType != null && IsParameterTypeCompatible(nullableParameterType, argumentType))
        {
            return true;
        }

        if (parameterType.IsGenericType)
        {
            try
            {
                var constructedArgumentType = FindConstructedGenericMatch(parameterType, argumentType);
                if (constructedArgumentType != null && AreTypeIdentitiesEquivalent(parameterType, constructedArgumentType))
                {
                    return true;
                }
            }
            catch (NotSupportedException)
            {
            }
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
            // .NET 10+ throws when calling IsAssignableFrom on incomplete TypeBuilders.
            // Fall back to checking our tracked interface list.
            if (parameterType.IsInterface && argumentType is TypeBuilder)
            {
                if (GetInterfacesSafe(argumentType).Any(i => AreTypeIdentitiesEquivalent(i, parameterType)))
                {
                    return true;
                }
            }
        }

        var parameterEnumUnderlyingType = TryGetEnumUnderlyingType(parameterType);
        var argumentEnumUnderlyingType = TryGetEnumUnderlyingType(argumentType);
        return IsImplicitNumericConversion(argumentType, parameterType)
            || parameterEnumUnderlyingType == argumentType
            || argumentEnumUnderlyingType == parameterType
            || ResolveConversionOperator(argumentType, parameterType, allowExplicit: false) != null;
    }

    private static bool CanAssignNullToType(Type targetType)
    {
        if (!IsValueTypeLike(targetType))
        {
            return true;
        }

        return Nullable.GetUnderlyingType(targetType) != null || targetType.IsGenericParameter;
    }

    private int GetParameterMatchScore(Type parameterType, Type argumentType)
    {
        if (parameterType == argumentType)
        {
            return 8;
        }

        if (TryGetRuntimeUnionArmTypes(parameterType, out var targetUnionArms))
        {
            var bestArmScore = 0;
            foreach (var arm in targetUnionArms)
            {
                bestArmScore = Math.Max(bestArmScore, GetParameterMatchScore(arm, argumentType));
            }

            return bestArmScore > 0 ? Math.Min(bestArmScore, 5) : 0;
        }

        if (TryGetRuntimeUnionArmTypes(argumentType, out var sourceUnionArms))
        {
            var sourceArmScores = sourceUnionArms
                .Select(arm => GetParameterMatchScore(parameterType, arm))
                .ToArray();
            return sourceArmScores.All(score => score > 0) ? sourceArmScores.Min() : 0;
        }

        if (parameterType.IsGenericParameter)
        {
            return 4;
        }

        if (AreTypeIdentitiesEquivalent(parameterType, argumentType))
        {
            return 8;
        }

        var nullableParameterType = Nullable.GetUnderlyingType(parameterType);
        if (nullableParameterType != null && AreParameterTypesCompatible(nullableParameterType, argumentType))
        {
            return 4;
        }

        if (parameterType.IsGenericType)
        {
            try
            {
                var constructedArgumentType = FindConstructedGenericMatch(parameterType, argumentType);
                if (constructedArgumentType != null && AreTypeIdentitiesEquivalent(parameterType, constructedArgumentType))
                {
                    return 4;
                }
            }
            catch (NotSupportedException)
            {
            }
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

        if ((TryGetEnumUnderlyingType(parameterType) == argumentType)
            || (TryGetEnumUnderlyingType(argumentType) == parameterType))
        {
            return 4;
        }

        if (ResolveConversionOperator(argumentType, parameterType, allowExplicit: false) != null)
        {
            return 5;
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

    private static bool HasOpenGenericBindingType(Type type)
    {
        type = GetByRefElementType(type);

        if (type.IsGenericParameter || type.ContainsGenericParameters)
        {
            return true;
        }

        if (type.IsArray)
        {
            var elementType = type.GetElementType();
            return elementType != null && HasOpenGenericBindingType(elementType);
        }

        if (type.IsGenericType)
        {
            return type.GetGenericArguments().Any(HasOpenGenericBindingType);
        }

        return false;
    }

    private Type GetExpressionTypeForBinding(Expression expression, Type expectedType)
    {
        expectedType = GetByRefElementType(expectedType);

        if (expression is ArrayLiteralExpression arrayLiteral && !HasOpenGenericBindingType(expectedType))
        {
            var savedExpectedType = _expectedExpressionType;
            _expectedExpressionType = expectedType;
            try
            {
                return GetArrayLiteralType(arrayLiteral);
            }
            finally
            {
                _expectedExpressionType = savedExpectedType;
            }
        }

        if (expression is IdentifierExpression methodGroupIdentifier
            && TryResolveContextualMethodGroup(methodGroupIdentifier, expectedType, out var methodGroupTarget))
        {
            return methodGroupTarget.DelegateType;
        }

        if (expression is IdentifierExpression localFunctionIdentifier
            && (expectedType == typeof(Delegate) || expectedType == typeof(MulticastDelegate))
            && TryGetNaturalLocalFunctionDelegateType(localFunctionIdentifier, out var naturalDelegateType))
        {
            return naturalDelegateType;
        }

        return GetExpressionType(expression);
    }

    private bool TryGetNaturalLocalFunctionDelegateType(IdentifierExpression identifier, out Type delegateType)
    {
        delegateType = typeof(object);

        if (_localFunctionDeclarations == null
            || !_localFunctionDeclarations.TryGetValue(identifier.Name, out var localFunctionDeclaration)
            || localFunctionDeclaration.TypeParameters is { Count: > 0 })
        {
            return false;
        }

        delegateType = GetLocalFunctionDelegateType(localFunctionDeclaration);
        return true;
    }

    private bool TryResolveContextualMethodGroup(
        IdentifierExpression identifier,
        Type expectedType,
        out ContextualMethodGroupTarget target)
    {
        return TryResolveContextualMethodGroup(identifier, expectedType, genericBindings: null, out target);
    }

    private bool TryResolveContextualMethodGroup(
        IdentifierExpression identifier,
        Type expectedType,
        Dictionary<string, Type>? genericBindings,
        out ContextualMethodGroupTarget target)
    {
        target = null!;

        if (_locals?.ContainsKey(identifier.Name) == true
            || _parameters?.ContainsKey(identifier.Name) == true
            || _closureFields?.ContainsKey(identifier.Name) == true)
        {
            return false;
        }

        if (!TryGetContextualDelegateSignature(
                expectedType,
                out var delegateType,
                out var delegateParameterTypes,
                out var delegateParameterIsOut,
                out var delegateReturnType))
        {
            return false;
        }

        bool TrySelectBest(
            IReadOnlyList<(MethodInfo Method, MethodGroupReceiverKind ReceiverKind)> candidates,
            out ContextualMethodGroupTarget selected)
        {
            selected = null!;
            ContextualMethodGroupTarget? bestTarget = null;
            Dictionary<string, Type>? bestBindings = null;
            var bestScore = -1;
            var ambiguous = false;
            var seenMethods = new HashSet<MethodInfo>();

            foreach (var (method, receiverKind) in candidates)
            {
                var candidateBindings = genericBindings != null
                    ? new Dictionary<string, Type>(genericBindings)
                    : null;

                if (!seenMethods.Add(method)
                    || !TryGetMethodGroupDelegateMatchScore(method, delegateParameterTypes, delegateParameterIsOut, delegateReturnType, candidateBindings, out var score))
                {
                    continue;
                }

                if (score > bestScore)
                {
                    var closedDelegateType = candidateBindings != null
                        ? ApplyRuntimeGenericBindings(delegateType, candidateBindings)
                        : delegateType;
                    bestTarget = new ContextualMethodGroupTarget(method, closedDelegateType, receiverKind, score);
                    bestBindings = candidateBindings;
                    bestScore = score;
                    ambiguous = false;
                }
                else if (score == bestScore)
                {
                    ambiguous = true;
                }
            }

            if (bestTarget == null || ambiguous)
            {
                return false;
            }

            if (genericBindings != null && bestBindings != null)
            {
                genericBindings.Clear();
                foreach (var (name, type) in bestBindings)
                {
                    genericBindings[name] = type;
                }
            }

            selected = bestTarget;
            return true;
        }

        var localCandidates = new List<(MethodInfo Method, MethodGroupReceiverKind ReceiverKind)>();
        if (_localFunctionDeclarations != null
            && _localFunctionDeclarations.TryGetValue(identifier.Name, out var localFunctionDeclaration))
        {
            if (localFunctionDeclaration.TypeParameters is not { Count: > 0 }
                && _genericLocalFunctionBuilders.TryGetValue(localFunctionDeclaration, out var localFunctionBuilder)
                && _genericLocalFunctionCaptures.TryGetValue(localFunctionDeclaration, out var localFunctionCaptures)
                && localFunctionCaptures.Count == 0)
            {
                localCandidates.Add((
                    localFunctionBuilder,
                    localFunctionBuilder.IsStatic ? MethodGroupReceiverKind.None : MethodGroupReceiverKind.LocalFunction));
            }

            if (TrySelectBest(localCandidates, out target))
                return true;

            return false;
        }

        var currentTypeCandidates = new List<(MethodInfo Method, MethodGroupReceiverKind ReceiverKind)>();
        var hasCurrentTypeName = false;
        if (_currentTypeBuilder != null
            && _declaredMethodOverloads.TryGetValue(GetMethodKey(_currentTypeBuilder, identifier.Name), out var currentTypeOverloads))
        {
            hasCurrentTypeName = true;
            foreach (var overload in currentTypeOverloads)
            {
                if (overload.Declaration.TypeParameters is { Count: > 0 } || !overload.Builder.IsStatic)
                {
                    continue;
                }

                currentTypeCandidates.Add((
                    RetargetMethodGroupCandidateToCurrentGenericType(_currentTypeBuilder, overload.Builder),
                    MethodGroupReceiverKind.None));
            }
        }

        if (TryGetImplicitInstanceOwnerTypeBuilder(out var implicitOwnerTypeBuilder)
            && TryGetImplicitInstanceMethodGroupCandidates(implicitOwnerTypeBuilder, identifier.Name, out var implicitInstanceOverloads))
        {
            hasCurrentTypeName = true;
            foreach (var overload in implicitInstanceOverloads)
            {
                currentTypeCandidates.Add((overload, MethodGroupReceiverKind.ImplicitThis));
            }
        }

        if (hasCurrentTypeName)
        {
            if (TrySelectBest(currentTypeCandidates, out target))
                return true;

            return false;
        }

        var topLevelCandidates = new List<(MethodInfo Method, MethodGroupReceiverKind ReceiverKind)>();
        if (_declaredMethodOverloads.TryGetValue(identifier.Name, out var topLevelOverloads))
        {
            foreach (var overload in topLevelOverloads)
            {
                if (overload.Declaration.TypeParameters is not { Count: > 0 } && overload.Builder.IsStatic)
                {
                    topLevelCandidates.Add((overload.Builder, MethodGroupReceiverKind.None));
                }
            }

            if (TrySelectBest(topLevelCandidates, out target))
                return true;
        }

        return false;
    }

    private bool TryGetImplicitInstanceMethodGroupCandidates(
        Type ownerType,
        string methodName,
        out List<MethodInfo> candidates)
    {
        candidates = new List<MethodInfo>();
        var hiddenSignatures = new HashSet<string>();

        for (var currentType = ownerType; currentType != null && currentType != typeof(object); currentType = currentType.BaseType)
        {
            var levelSignatures = new HashSet<string>();

            if (currentType is TypeBuilder currentTypeBuilder)
            {
                if (_declaredMethodOverloads.TryGetValue(GetMethodKey(currentTypeBuilder, methodName), out var declaredOverloads))
                {
                    foreach (var overload in declaredOverloads)
                    {
                        if (overload.Declaration.TypeParameters is { Count: > 0 } || overload.Builder.IsStatic)
                        {
                            continue;
                        }

                        var method = RetargetMethodGroupCandidateToCurrentGenericType(currentTypeBuilder, overload.Builder);
                        var signatureKey = GetMethodGroupSignatureKey(method);
                        levelSignatures.Add(signatureKey);

                        if (!hiddenSignatures.Contains(signatureKey))
                        {
                            candidates.Add(method);
                        }
                    }
                }
            }
            else
            {
                var bindingFlags = BindingFlags.Public
                    | BindingFlags.NonPublic
                    | BindingFlags.Instance
                    | BindingFlags.DeclaredOnly;

                foreach (var method in GetRuntimeMethodCandidates(currentType, bindingFlags))
                {
                    if (method.Name != methodName
                        || method.IsSpecialName
                        || method.ContainsGenericParameters)
                    {
                        continue;
                    }

                    var signatureKey = GetMethodGroupSignatureKey(method);
                    levelSignatures.Add(signatureKey);

                    if (!hiddenSignatures.Contains(signatureKey))
                    {
                        candidates.Add(method);
                    }
                }
            }

            foreach (var signature in levelSignatures)
            {
                hiddenSignatures.Add(signature);
            }
        }

        return candidates.Count > 0;
    }

    private MethodInfo RetargetMethodGroupCandidateToCurrentGenericType(TypeBuilder declaringType, MethodInfo method)
    {
        var typeGenericParameters = GetTypeGenericParameters(declaringType);
        if (typeGenericParameters is not { Length: > 0 })
        {
            return method;
        }

        try
        {
            var constructedType = declaringType.MakeGenericType(typeGenericParameters);
            return TypeBuilder.GetMethod(constructedType, method);
        }
        catch (ArgumentException)
        {
            return method;
        }
        catch (NotSupportedException)
        {
            return method;
        }
    }

    private string GetMethodGroupSignatureKey(MethodInfo method)
    {
        try
        {
            var parameters = method.GetParameters()
                .Select(parameter =>
                {
                    var modifier = parameter.ParameterType.IsByRef
                        ? parameter.IsOut ? "out " : "ref "
                        : string.Empty;
                    return modifier + GetTypeKey(GetByRefElementType(parameter.ParameterType));
                });
            return $"{method.Name}({string.Join(",", parameters)})";
        }
        catch (NotSupportedException)
        {
            return method.Name;
        }
    }

    private bool TryGetContextualDelegateSignature(
        Type expectedType,
        out Type delegateType,
        out Type[] parameterTypes,
        out bool[] parameterIsOut,
        out Type returnType)
    {
        expectedType = GetByRefElementType(expectedType);
        if (TryGetExpressionTreeDelegateType(expectedType, out _))
        {
            delegateType = typeof(void);
            parameterTypes = Array.Empty<Type>();
            parameterIsOut = Array.Empty<bool>();
            returnType = typeof(void);
            return false;
        }

        delegateType = expectedType;
        parameterTypes = Array.Empty<Type>();
        parameterIsOut = Array.Empty<bool>();
        returnType = typeof(void);

        if (!IsDelegateLikeType(delegateType)
            || !TryGetDelegateInvokeMethod(delegateType, out var invokeMethod)
            || invokeMethod == null)
        {
            return false;
        }

        var invokeParameters = invokeMethod.GetParameters();
        parameterTypes = GetDelegateInvokeParameterTypes(delegateType, invokeMethod);
        parameterIsOut = invokeParameters.Select(parameter => parameter.IsOut).ToArray();
        returnType = GetDelegateInvokeReturnType(delegateType, invokeMethod);
        return true;
    }

    private bool TryGetMethodGroupDelegateMatchScore(
        MethodInfo method,
        IReadOnlyList<Type> delegateParameterTypes,
        IReadOnlyList<bool> delegateParameterIsOut,
        Type delegateReturnType,
        Dictionary<string, Type>? genericBindings,
        out int score)
    {
        score = 0;

        if (HasUnboundMethodGenericParameters(method))
        {
            return false;
        }

        ParameterInfo[] methodParameters;
        try
        {
            methodParameters = method.GetParameters();
        }
        catch (NotSupportedException)
        {
            return false;
        }

        if (methodParameters.Length != delegateParameterTypes.Count)
        {
            return false;
        }

        for (int i = 0; i < methodParameters.Length; i++)
        {
            var rawMethodParameterType = methodParameters[i].ParameterType;
            var rawDelegateParameterType = delegateParameterTypes[i];
            if (rawMethodParameterType.IsByRef != rawDelegateParameterType.IsByRef
                || (rawMethodParameterType.IsByRef
                    && i < delegateParameterIsOut.Count
                    && methodParameters[i].IsOut != delegateParameterIsOut[i]))
            {
                return false;
            }

            var methodParameterType = GetByRefElementType(rawMethodParameterType);
            var delegateParameterType = GetByRefElementType(rawDelegateParameterType);
            var matchScore = GetMethodGroupSignatureMatchScore(methodParameterType, delegateParameterType, genericBindings);
            if (matchScore == 0)
            {
                return false;
            }

            score += matchScore;
        }

        var methodReturnType = GetByRefElementType(method.ReturnType);
        if (delegateReturnType == typeof(void))
        {
            if (methodReturnType != typeof(void))
            {
                return false;
            }

            score += 8;
            return true;
        }

        if (methodReturnType == typeof(void)
            || GetMethodGroupSignatureMatchScore(delegateReturnType, methodReturnType, genericBindings) == 0)
        {
            return false;
        }

        score += GetMethodGroupSignatureMatchScore(delegateReturnType, methodReturnType, genericBindings);
        return true;
    }

    private static bool HasUnboundMethodGenericParameters(MethodInfo method)
    {
        try
        {
            if (!method.IsGenericMethod)
            {
                return false;
            }

            if (method.IsGenericMethodDefinition)
            {
                return true;
            }

            return method.GetGenericArguments().Any(argument =>
                argument.IsGenericParameter && argument.DeclaringMethod == method);
        }
        catch (NotSupportedException)
        {
            return true;
        }
    }

    private int GetMethodGroupSignatureMatchScore(
        Type targetType,
        Type sourceType,
        Dictionary<string, Type>? genericBindings = null)
    {
        targetType = GetByRefElementType(targetType);
        sourceType = GetByRefElementType(sourceType);

        if (genericBindings != null && (targetType.IsGenericParameter || targetType.ContainsGenericParameters))
        {
            var savedBindings = new Dictionary<string, Type>(genericBindings);
            if (TryCollectGenericBindings(targetType, sourceType, genericBindings))
            {
                var score = GetMethodGroupSignatureMatchScore(
                    ApplyRuntimeGenericBindings(targetType, genericBindings),
                    sourceType);
                if (score != 0)
                {
                    return score;
                }
            }

            RestoreGenericBindings(genericBindings, savedBindings);
            return 0;
        }

        if (genericBindings != null && (sourceType.IsGenericParameter || sourceType.ContainsGenericParameters))
        {
            var savedBindings = new Dictionary<string, Type>(genericBindings);
            if (TryCollectGenericBindings(sourceType, targetType, genericBindings))
            {
                var score = GetMethodGroupSignatureMatchScore(
                    targetType,
                    ApplyRuntimeGenericBindings(sourceType, genericBindings));
                if (score != 0)
                {
                    return score;
                }
            }

            RestoreGenericBindings(genericBindings, savedBindings);
            return 0;
        }

        if (targetType == sourceType || AreTypeIdentitiesEquivalent(targetType, sourceType))
        {
            return 8;
        }

        if (targetType.IsValueType || sourceType.IsValueType)
        {
            return 0;
        }

        return AreTypesAssignmentCompatible(targetType, sourceType) ? 4 : 0;
    }

    private static void RestoreGenericBindings(Dictionary<string, Type> bindings, Dictionary<string, Type> savedBindings)
    {
        bindings.Clear();
        foreach (var (name, type) in savedBindings)
        {
            bindings[name] = type;
        }
    }

    private bool TryEmitContextualMethodGroupDelegate(IdentifierExpression identifier, Type expectedType)
    {
        if (_currentIL == null || !TryResolveContextualMethodGroup(identifier, expectedType, out var target))
        {
            return false;
        }

        if (target.ReceiverKind == MethodGroupReceiverKind.None)
        {
            EmitStaticDelegate(target.Method, target.DelegateType);
            return true;
        }

        switch (target.ReceiverKind)
        {
            case MethodGroupReceiverKind.ImplicitThis:
                EmitLoadImplicitThisDelegateReceiver(target.Method);
                break;
            case MethodGroupReceiverKind.LocalFunction:
                EmitGenericLocalFunctionReceiver(target.Method);
                break;
            default:
                throw new InvalidOperationException($"Unsupported method group receiver kind {target.ReceiverKind}");
        }

        if (target.ReceiverKind != MethodGroupReceiverKind.None
            && target.Method.IsVirtual
            && !target.Method.IsFinal)
        {
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Ldvirtftn, target.Method);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldftn, target.Method);
        }

        _currentIL.Emit(OpCodes.Newobj, GetDelegateConstructor(target.DelegateType));
        return true;
    }

    private void EmitLoadImplicitThisDelegateReceiver(MethodInfo targetMethod)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var receiverType = GetCapturedThisType() ?? _currentTypeBuilder ?? targetMethod.DeclaringType;
        if (receiverType == null || !IsValueTypeLike(receiverType))
        {
            EmitLoadImplicitThisReference();
            return;
        }

        if (GetCapturedThisField() is { } capturedThisField)
        {
            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldfld, capturedThisField);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldarg_0);
            _currentIL.Emit(OpCodes.Ldobj, receiverType);
        }

        _currentIL.Emit(OpCodes.Box, receiverType);
    }

    private bool ShouldPassParamsArgumentDirectly(Argument argument, Type parameterType)
    {
        if (argument.Value is DefaultExpression)
        {
            return true;
        }

        var argumentType = GetExpressionTypeForBinding(argument.Value, parameterType);
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

        foreach (var interfaceType in GetImplementedTypes(argumentType))
        {
            if (interfaceType.IsGenericType && interfaceType.GetGenericTypeDefinition() == genericDefinition)
            {
                return interfaceType;
            }
        }

        Type? baseType;
        try
        {
            baseType = argumentType.BaseType;
        }
        catch (NotSupportedException)
        {
            baseType = null;
        }

        while (baseType != null)
        {
            if (baseType.IsGenericType && baseType.GetGenericTypeDefinition() == genericDefinition)
            {
                return baseType;
            }

            try
            {
                baseType = baseType.BaseType;
            }
            catch (NotSupportedException)
            {
                break;
            }
        }

        return null;
    }

    private static IEnumerable<Type> GetImplementedTypes(Type argumentType)
    {
        if (argumentType.IsArray && argumentType.GetElementType() is { } elementType)
        {
            yield return typeof(IEnumerable<>).MakeGenericType(elementType);
            yield return typeof(ICollection<>).MakeGenericType(elementType);
            yield return typeof(IList<>).MakeGenericType(elementType);
            yield return typeof(IReadOnlyCollection<>).MakeGenericType(elementType);
            yield return typeof(IReadOnlyList<>).MakeGenericType(elementType);
        }

        if (argumentType.IsGenericType && !argumentType.IsGenericTypeDefinition)
        {
            Type genericDefinition;
            try
            {
                genericDefinition = argumentType.GetGenericTypeDefinition();
            }
            catch (NotSupportedException)
            {
                genericDefinition = null!;
            }

            if (genericDefinition != null)
            {
                Type[] genericInterfaces;
                try
                {
                    genericInterfaces = genericDefinition.GetInterfaces();
                }
                catch (NotSupportedException)
                {
                    genericInterfaces = Array.Empty<Type>();
                }

                foreach (var interfaceType in genericInterfaces)
                {
                    yield return ResolveGenericSignatureType(argumentType, interfaceType);
                }

                Type? genericBaseType;
                try
                {
                    genericBaseType = genericDefinition.BaseType;
                }
                catch (NotSupportedException)
                {
                    genericBaseType = null;
                }

                if (genericBaseType != null)
                {
                    yield return ResolveGenericSignatureType(argumentType, genericBaseType);
                }
            }
        }

        Type[] interfaces;
        try
        {
            interfaces = argumentType.GetInterfaces();
        }
        catch (NotSupportedException)
        {
            yield break;
        }

        foreach (var interfaceType in interfaces)
        {
            yield return interfaceType;
        }
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
        var runtimeParameterIndex = 0;
        var suppliedArgumentIndex = 0;
        if (implicitReceiver != null)
        {
            if (runtimeParameters.Length == 0 || !TryCollectGenericBindings(runtimeParameters[0].ParameterType, GetExpressionType(implicitReceiver), bindings))
            {
                return null;
            }

            runtimeParameterIndex = 1;
        }

        for (int declarationIndex = implicitReceiver != null ? 1 : 0;
             declarationIndex < declaration.Parameters.Count && runtimeParameterIndex < runtimeParameters.Length;
             declarationIndex++, runtimeParameterIndex++)
        {
            var declarationParameter = declaration.Parameters[declarationIndex];
            var runtimeParameter = runtimeParameters[runtimeParameterIndex].ParameterType;

            if (declarationParameter.Modifier == Ast.ParameterModifier.Params && declarationIndex == declaration.Parameters.Count - 1)
            {
                if (!TryGetParamsElementType(runtimeParameter, out var elementType))
                {
                    return null;
                }

                var remainingArguments = call.Arguments.Skip(suppliedArgumentIndex).ToList();
                if (remainingArguments.Count == 1 && ShouldPassParamsArgumentDirectly(remainingArguments[0], runtimeParameter))
                {
                    if (!TryCollectGenericBindings(runtimeParameter, GetExpressionTypeForBinding(remainingArguments[0].Value, runtimeParameter), bindings))
                    {
                        return null;
                    }
                }
                else
                {
                    foreach (var argument in remainingArguments)
                    {
                        if (!TryCollectGenericBindings(elementType, GetExpressionTypeForBinding(argument.Value, elementType), bindings))
                        {
                            return null;
                        }
                    }
                }

                suppliedArgumentIndex = call.Arguments.Count;
                break;
            }

            if (suppliedArgumentIndex >= call.Arguments.Count)
            {
                break;
            }

            if (!TryCollectGenericBindings(runtimeParameter, GetExpressionTypeForBinding(call.Arguments[suppliedArgumentIndex].Value, runtimeParameter), bindings))
            {
                return null;
            }

            suppliedArgumentIndex++;
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

                    if (supplied.Argument.Value is DefaultExpression)
                    {
                        score += 8;
                        break;
                    }

                    if (supplied.Argument.Value is NullLiteralExpression)
                    {
                        if (!CanAssignNullToType(expectedType))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += 8;
                        break;
                    }

                    if (supplied.Argument.Value is LambdaExpression lambda)
                    {
                        if (!TryBindLambdaToRuntimeParameter(expectedType, lambda, new Dictionary<string, Type>(), out var lambdaScore))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += lambdaScore;
                        break;
                    }

                    var argumentType = GetExpressionTypeForBinding(supplied.Argument.Value, expectedType);
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

                    if (expressionBound.Expression is NullLiteralExpression)
                    {
                        if (!CanAssignNullToType(expectedType))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += 8;
                        break;
                    }

                    var argumentType = GetExpressionTypeForBinding(expressionBound.Expression, expectedType);
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

                        if (paramsArgument.Value is NullLiteralExpression)
                        {
                            if (!CanAssignNullToType(paramsBound.ElementType))
                            {
                                boundArguments = Array.Empty<BoundCallArgument>();
                                return false;
                            }

                            score += 8;
                            continue;
                        }

                        if (paramsArgument.Value is LambdaExpression paramsLambda)
                        {
                            if (!TryBindLambdaToRuntimeParameter(paramsBound.ElementType, paramsLambda, new Dictionary<string, Type>(), out var lambdaScore))
                            {
                                boundArguments = Array.Empty<BoundCallArgument>();
                                return false;
                            }

                            score += lambdaScore;
                            continue;
                        }

                        var argumentType = GetExpressionTypeForBinding(paramsArgument.Value, paramsBound.ElementType);
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

        return BindDeclaredMethodCall(overloads, call, implicitReceiver, targetType, predicate);
    }

    private BoundDeclaredMethodCall? BindDeclaredMethodCall(
        IEnumerable<DeclaredMethodOverload> overloads,
        CallExpression call,
        Expression? implicitReceiver = null,
        Type? targetType = null,
        Func<DeclaredMethodOverload, bool>? predicate = null)
    {
        var overloadList = overloads.ToList();
        if (overloadList.Count == 0)
        {
            return null;
        }

        BoundDeclaredMethodCall? best = null;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;
        var bestIsGeneric = true;

        foreach (var overload in overloadList)
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
                : candidateMethod.GetParameters()
                    .Select(parameter => ResolveTargetGenericSignatureType(targetType, parameter.ParameterType))
                    .ToArray();

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
                    targetType,
                    candidateTypeArguments);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
                bestIsGeneric = isGeneric;
            }
        }

        return best;
    }

    private BoundDeclaredMethodCall? BindDeclaredExtensionMethodCall(
        string methodName,
        CallExpression call,
        Expression implicitReceiver)
    {
        var extensionOverloads = _declaredMethodOverloads
            .Where(entry => string.Equals(entry.Key, methodName, StringComparison.Ordinal)
                || entry.Key.EndsWith($".{methodName}", StringComparison.Ordinal))
            .SelectMany(entry => entry.Value);

        return BindDeclaredMethodCall(
            extensionOverloads,
            call,
            implicitReceiver,
            predicate: overload => overload.Builder.IsStatic
                && overload.Declaration.Parameters.Count > 0
                && overload.Declaration.Parameters[0].IsThis);
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
                    if (runtimeDefault.Value == DBNull.Value
                        || runtimeDefault.Value == Missing.Value
                        || (runtimeDefault.Value == null && runtimeDefault.ParameterType.IsValueType))
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

                var spanCtor = ResolveCollectionConstructor(
                    parameterType,
                    constructor =>
                    {
                        var parameters = constructor.GetParameters();
                        return parameters.Length == 1
                            && AreParameterTypesCompatible(parameters[0].ParameterType, arrayType);
                    })
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

        var ctor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
            ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
        var addMethod = ResolveCollectionMethod(listType, "Add", method => HasParameterCount(method, 1))
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

        if (TryResolveDeclaredProjectType(typeName, treatStringEnumAsString: false, out type))
        {
            return true;
        }

        foreach (var candidate in GetDeclaredTypeNameCandidates(typeName).Distinct(StringComparer.Ordinal))
        {
            var externalType = ResolveExternalType(candidate);
            if (externalType != null)
            {
                type = externalType;
                return true;
            }
        }

        type = typeof(object);
        return false;
    }

    private bool TryResolveStaticContainer(Expression expression, out Type type)
    {
        if (ExpressionStartsWithValueIdentifier(expression))
        {
            type = typeof(object);
            return false;
        }

        if (TryGetQualifiedName(expression, out var qualifiedName))
        {
            return TryResolveStaticContainer(qualifiedName, out type);
        }

        type = typeof(object);
        return false;
    }

    private bool ExpressionStartsWithValueIdentifier(Expression expression)
    {
        return expression switch
        {
            IdentifierExpression ident => IsValueIdentifierInScope(ident.Name),
            MemberAccessExpression memberAccess when !memberAccess.IsNullConditional => ExpressionStartsWithValueIdentifier(memberAccess.Object),
            _ => false
        };
    }

    private bool IsValueIdentifierInScope(string name)
    {
        if (_locals?.ContainsKey(name) == true
            || _parameters?.ContainsKey(name) == true
            || _closureFields?.ContainsKey(name) == true)
        {
            return true;
        }

        if (!TryGetImplicitInstanceOwnerTypeBuilder(out var currentTypeBuilder))
        {
            return false;
        }

        return TryResolveCurrentTypeMember(currentTypeBuilder, name, out _, out _, out _, out _);
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
        type = GetByRefElementType(type);
        if (type is TypeBuilder typeBuilder)
        {
            return typeBuilder.BaseType == typeof(ValueType)
                || typeBuilder.BaseType == typeof(Enum);
        }

        return type.IsValueType;
    }

    private static Type GetByRefElementType(Type type)
    {
        return type.IsByRef ? type.GetElementType() ?? typeof(object) : type;
    }

    /// <summary>
    /// Decides whether a virtual instance method dispatch can be safely lowered from
    /// <c>callvirt</c> to a non-virtual <c>call</c>.
    ///
    /// A <c>callvirt</c> does two things that a <c>call</c> does not: (1) it performs a
    /// null-check on the receiver, and (2) it dispatches virtually based on the receiver's
    /// runtime type. Devirtualizing is therefore only correct when BOTH:
    ///   * the dispatch target is statically exact (no derived override can change it), and
    ///   * the null-check is unnecessary because the receiver is provably non-null.
    ///
    /// We stay strictly conservative: we only devirtualize when the receiver expression
    /// produces a value whose runtime type is exactly known and which can never be null.
    /// The canonical safe cases are object creation (<c>new T()</c>) and string-producing
    /// literals, both of which yield a non-null reference of an exact runtime type, so virtual
    /// dispatch resolves deterministically and the null-check is provably redundant.
    /// </summary>
    private static bool CanDevirtualizeInstanceCall(Expression receiver, Type receiverType)
    {
        // Value-type receivers are already dispatched with `call` by the caller; nothing to do.
        if (IsValueTypeLike(receiverType))
            return false;

        // Open generic parameters use constrained dispatch; never devirtualize them here.
        if (receiverType.IsGenericParameter)
            return false;

        // The receiver must be provably non-null AND of an exactly-known runtime type so that
        // dropping both the null-check and the virtual dispatch preserves semantics.
        return IsExactlyTypedNonNullReceiver(receiver);
    }

    /// <summary>
    /// Returns true when the receiver expression yields a non-null reference whose runtime type
    /// is exactly the static type (so virtual dispatch resolves deterministically). These are
    /// expressions that construct a fresh value: <c>new T()</c> and string-producing literals.
    /// </summary>
    private static bool IsExactlyTypedNonNullReceiver(Expression receiver)
    {
        return receiver switch
        {
            // `new T()` yields a non-null reference whose runtime type is exactly T.
            NewExpression => true,
            // String literals and interpolated strings yield a non-null System.String (sealed).
            StringLiteralExpression => true,
            InterpolatedStringExpression => true,
            _ => false,
        };
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

        var enumerableInterface = GetRuntimeInterfaces(collectionType)
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

            if (ShouldLiftLocalIntoBox(parameter.Name))
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

            if (ShouldLiftLocalIntoBox(parameter.Name))
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

        if (TryGetEnumUnderlyingType(parameterType) == argumentType)
        {
            return true;
        }

        if (TryGetEnumUnderlyingType(argumentType) == parameterType)
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

        var implementedTypes = GetImplementedTypes(returnType).ToArray();

        var enumerableInterface = implementedTypes
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IEnumerable<>));
        if (enumerableInterface != null)
        {
            elementType = enumerableInterface.GetGenericArguments()[0];
            return true;
        }

        var asyncEnumerableInterface = implementedTypes
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>));
        if (asyncEnumerableInterface != null)
        {
            elementType = asyncEnumerableInterface.GetGenericArguments()[0];
            return true;
        }

        var asyncEnumeratorInterface = implementedTypes
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
        TrackInterfaceImplementation(enumeratorType, asyncEnumeratorType);
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
        TrackInterfaceImplementation(enumerableType, asyncEnumerableType);
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

    private static TypeAttributes GetTypeVisibilityAttributes(string name, Modifiers modifiers)
    {
        return VisibilityConventions.GetTopLevelTypeAttributes(name, modifiers);
    }

    private TypeAttributes GetInterfaceTypeVisibilityAttributes(InterfaceDeclaration interfaceDecl)
    {
        if (!interfaceDecl.IsDuckInterface
            || interfaceDecl.Modifiers.HasFlag(Modifiers.Public)
            || interfaceDecl.Modifiers.HasFlag(Modifiers.Internal)
            || interfaceDecl.Modifiers.HasFlag(Modifiers.File))
        {
            return GetTypeVisibilityAttributes(interfaceDecl.Name, interfaceDecl.Modifiers);
        }

        var hasPublicImplementor = _compilationUnit.Declarations.Any(declaration => declaration switch
        {
            ClassDeclaration classDecl => !string.IsNullOrEmpty(classDecl.Name)
                && VisibilityConventions.IsExportedIdentifier(classDecl.Name)
                && StructurallyMatchesDuckInterface(classDecl.Members, interfaceDecl),
            StructDeclaration structDecl => !string.IsNullOrEmpty(structDecl.Name)
                && VisibilityConventions.IsExportedIdentifier(structDecl.Name)
                && StructurallyMatchesDuckInterface(structDecl.Members, interfaceDecl),
            RecordDeclaration recordDecl => !string.IsNullOrEmpty(recordDecl.Name)
                && VisibilityConventions.IsExportedIdentifier(recordDecl.Name)
                && StructurallyMatchesDuckInterface(recordDecl.Members, interfaceDecl),
            _ => false
        });

        return hasPublicImplementor ? TypeAttributes.Public : TypeAttributes.NotPublic;
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
        return VisibilityConventions.HasExplicitVisibility(modifiers);
    }

    private static FieldAttributes GetConventionFieldVisibilityAttributes(string name, Modifiers modifiers)
    {
        if (HasExplicitVisibility(modifiers))
        {
            return GetVisibilityFieldAttributes(modifiers);
        }

        return VisibilityConventions.GetMemberFieldAttributes(name, modifiers);
    }

    private static MethodAttributes GetConventionMethodVisibilityAttributes(string name, Modifiers modifiers)
    {
        if (HasExplicitVisibility(modifiers))
        {
            return GetVisibilityMethodAttributes(modifiers);
        }

        return VisibilityConventions.GetMemberMethodAttributes(name, modifiers);
    }

    private IEnumerable<InterfaceDeclaration> GetMatchingDuckInterfaces(IReadOnlyList<Declaration> typeMembers)
    {
        return _compilationUnit.Declarations
            .OfType<InterfaceDeclaration>()
            .Where(interfaceDecl => interfaceDecl.IsDuckInterface && StructurallyMatchesDuckInterface(typeMembers, interfaceDecl));
    }

    private static bool StructurallyMatchesDuckInterface(IReadOnlyList<Declaration> typeMembers, InterfaceDeclaration duckInterface)
    {
        foreach (var interfaceMember in duckInterface.Members.OfType<FunctionDeclaration>())
        {
            var hasMatch = typeMembers
                .OfType<FunctionDeclaration>()
                .Any(typeMember => FunctionSignaturesMatch(typeMember, interfaceMember));

            if (!hasMatch)
            {
                return false;
            }
        }

        return true;
    }

    private static bool FunctionSignaturesMatch(FunctionDeclaration implementation, FunctionDeclaration contract)
    {
        return implementation.Name == contract.Name
            && implementation.Parameters.Count == contract.Parameters.Count
            && ParameterListsMatch(implementation.Parameters, contract.Parameters)
            && TypeReferencesMatch(implementation.ReturnType, contract.ReturnType);
    }

    private static bool ParameterListsMatch(IReadOnlyList<Parameter> left, IReadOnlyList<Parameter> right)
    {
        for (int i = 0; i < left.Count; i++)
        {
            if (left[i].Modifier != right[i].Modifier
                || !TypeReferencesMatch(left[i].Type, right[i].Type))
            {
                return false;
            }
        }

        return true;
    }

    private static bool TypeReferencesMatch(TypeReference? left, TypeReference? right)
    {
        if (left == null || right == null)
        {
            return left == right;
        }

        return GetTypeReferenceIdentity(left) == GetTypeReferenceIdentity(right);
    }

    private static string GetTypeReferenceIdentity(TypeReference typeReference)
    {
        return typeReference switch
        {
            SimpleTypeReference simpleType => $"S:{simpleType.Name}",
            GenericTypeReference genericType => $"G:{genericType.Name}<{string.Join(",", genericType.TypeArguments.Select(GetTypeReferenceIdentity))}>",
            ArrayTypeReference arrayType => $"A:{GetTypeReferenceIdentity(arrayType.ElementType)}",
            NullableTypeReference nullableType => $"N:{GetTypeReferenceIdentity(nullableType.InnerType)}",
            UnionTypeReference unionType => $"U:({string.Join("|", FlattenUnionTypeReference(unionType).Select(GetTypeReferenceIdentity))})",
            TupleTypeReference tupleType => $"T:({string.Join(",", tupleType.Elements.Select(element => GetTypeReferenceIdentity(element.Type)))})",
            FunctionTypeReference functionType => $"F:({string.Join(",", functionType.ParameterTypes.Select(GetTypeReferenceIdentity))})->{GetTypeReferenceIdentity(functionType.ReturnType)}",
            _ => typeReference.ToString() ?? string.Empty
        };
    }

    private Type ResolveDuckInterfaceType(InterfaceDeclaration interfaceDecl, GenericTypeParameterBuilder[]? genericParameters)
    {
        if (!TryEnsureUserTypeDeclared(interfaceDecl.Name))
        {
            throw new InvalidOperationException($"Duck interface {interfaceDecl.Name} was not declared");
        }

        return ResolveType(new SimpleTypeReference(interfaceDecl.Name, interfaceDecl.Line, interfaceDecl.Column), genericParameters);
    }

    private List<Type> GetImplementedInterfaces(
        IReadOnlyList<Declaration> typeMembers,
        IReadOnlyList<TypeReference>? explicitInterfaces,
        GenericTypeParameterBuilder[]? genericParameters,
        TypeReference? baseTypeReference = null)
    {
        var implementedInterfaces = new List<Type>();

        if (baseTypeReference != null)
        {
            var baseType = ResolveType(baseTypeReference, genericParameters);
            if (baseType.IsInterface)
            {
                implementedInterfaces.Add(baseType);
            }
        }

        if (explicitInterfaces != null)
        {
            implementedInterfaces.AddRange(
                explicitInterfaces
                    .Select(typeReference => ResolveType(typeReference, genericParameters))
                    .Where(type => type.IsInterface));
        }

        foreach (var duckInterface in GetMatchingDuckInterfaces(typeMembers))
        {
            var duckInterfaceType = ResolveDuckInterfaceType(duckInterface, genericParameters);
            if (duckInterfaceType.IsInterface)
            {
                implementedInterfaces.Add(duckInterfaceType);
            }
        }

        return implementedInterfaces
            .GroupBy(GetTypeKey, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToList();
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
            if (expression is IdentifierExpression methodGroupIdentifier
                && TryEmitContextualMethodGroupDelegate(methodGroupIdentifier, _expectedExpressionType))
            {
                return;
            }

            if (expression is LambdaExpression)
            {
                EmitLambda((LambdaExpression)expression, _expectedExpressionType);
                return;
            }

            if (_expectedExpressionType == typeof(void))
            {
                EmitExpression(expression);
                if (GetExpressionType(expression) != typeof(void))
                {
                    _currentIL?.Emit(OpCodes.Pop);
                }

                return;
            }

            if (expression is NullLiteralExpression && Nullable.GetUnderlyingType(_expectedExpressionType) != null)
            {
                EmitDefaultValue(_expectedExpressionType);
                return;
            }

            if (expression is NullLiteralExpression && CanAssignNullToType(_expectedExpressionType))
            {
                _currentIL!.Emit(OpCodes.Ldnull);
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

        if (type.IsGenericParameter || type.ContainsGenericParameters)
            _currentIL.Emit(OpCodes.Ldobj, type);
        else if (IsEnumType(type) || type == typeof(int))
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

        if (type.IsGenericParameter || type.ContainsGenericParameters)
            _currentIL.Emit(OpCodes.Stobj, type);
        else if (IsEnumType(type) || type == typeof(int) || type == typeof(uint))
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

        if (TryGetEnumUnderlyingType(targetType) is { } enumUnderlyingType)
        {
            EmitConstantValue(Convert.ChangeType(value, enumUnderlyingType), enumUnderlyingType);
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
        var assemblyName = new AssemblyName(_assemblyName)
        {
            Version = GetAssemblyVersion()
        };
        var assemblyBuilder = new PersistedAssemblyBuilder(
            assemblyName,
            typeof(object).Assembly);

        // Create module builder
        _moduleBuilder = assemblyBuilder.DefineDynamicModule(_assemblyName);
        EnsureNullableMetadataAttributeTypes();

        // Create Program class (entry point container)
        _programType = _moduleBuilder.DefineType(
            "Program",
            TypeAttributes.Public | TypeAttributes.Class);
        ApplyNullableContextAttribute(_programType.SetCustomAttribute);

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
            ApplyNullableContextAttribute(_testType.SetCustomAttribute);
            RegisterType("NSharpTests", _testType);
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
            else if (declaration is InterfaceDeclaration interfaceDecl)
            {
                EmitInterfaceBodies(interfaceDecl);
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

        EnsureRuntimeEntryPointWrapper();

        foreach (var enumType in _enumTypes.Values.OfType<EnumBuilder>())
        {
            enumType.CreateType();
        }

        foreach (var nestedEnumType in _enumTypes.Values
                     .OfType<TypeBuilder>()
                     .OrderByDescending(typeBuilder => GetTypeKey(typeBuilder).Count(c => c == '.')))
        {
            nestedEnumType.CreateType();
        }

        foreach (var stringEnumContainer in _stringEnumContainers.Values
                     .OrderByDescending(typeBuilder => GetTypeKey(typeBuilder).Count(c => c == '.')))
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

        SaveAssembly(assemblyBuilder);

    }

    private void SaveAssembly(PersistedAssemblyBuilder assemblyBuilder)
    {
        var entryPoint = _entryPointWrapper ?? GetEntryPointMethod();
        if (string.Equals(_projectConfig?.OutputType, "exe", StringComparison.OrdinalIgnoreCase)
            && entryPoint != null)
        {
            var metadataBuilder = assemblyBuilder.GenerateMetadata(out var ilStream, out var mappedFieldData);
            var peBuilder = new ManagedPEBuilder(
                header: PEHeaderBuilder.CreateExecutableHeader(),
                metadataRootBuilder: new MetadataRootBuilder(metadataBuilder),
                ilStream: ilStream,
                mappedFieldData: mappedFieldData,
                entryPoint: MetadataTokens.MethodDefinitionHandle(entryPoint.MetadataToken));

            var peBlob = new BlobBuilder();
            peBuilder.Serialize(peBlob);

            using var executableStream = new FileStream(_outputPath, FileMode.Create, FileAccess.Write);
            peBlob.WriteContentTo(executableStream);
            return;
        }

        using var stream = new FileStream(_outputPath, FileMode.Create, FileAccess.Write);
        assemblyBuilder.Save(stream);
    }

    private Version GetAssemblyVersion()
    {
        if (!string.IsNullOrWhiteSpace(_projectConfig?.Version)
            && Version.TryParse(_projectConfig.Version, out var configuredVersion))
        {
            return NormalizeAssemblyVersion(configuredVersion);
        }

        return new Version(1, 0, 0, 0);
    }

    private static Version NormalizeAssemblyVersion(Version version)
    {
        return new Version(
            version.Major >= 0 ? version.Major : 1,
            version.Minor >= 0 ? version.Minor : 0,
            version.Build >= 0 ? version.Build : 0,
            version.Revision >= 0 ? version.Revision : 0);
    }

    private MethodBuilder? GetEntryPointMethod()
    {
        if (_methods.TryGetValue("main", out var lowerMain))
        {
            return lowerMain;
        }

        if (_methods.TryGetValue("Main", out var main))
        {
            return main;
        }

        var candidates = _methods
            .Where(candidate =>
                candidate.Value.IsStatic
                && string.Equals(candidate.Value.Name, "Main", StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(candidate => string.Equals(candidate.Key, "Program.Main", StringComparison.Ordinal))
            .ThenBy(candidate => candidate.Key, StringComparer.Ordinal)
            .ToList();

        if (candidates.Count > 1)
        {
            throw new InvalidOperationException(
                $"Multiple entry point methods found: {string.Join(", ", candidates.Select(candidate => candidate.Key))}");
        }

        return candidates.Count == 1 ? candidates[0].Value : null;
    }

    private void EnsureRuntimeEntryPointWrapper()
    {
        if (!string.Equals(_projectConfig?.OutputType, "exe", StringComparison.OrdinalIgnoreCase)
            || _programType == null
            || _entryPointWrapper != null)
        {
            return;
        }

        var entryPoint = GetEntryPointMethod();
        if (entryPoint == null || !TryUnwrapAsyncReturnType(entryPoint.ReturnType, out var resultType, out _))
        {
            return;
        }

        var wrapperReturnType = resultType == typeof(int) || resultType == typeof(uint)
            ? resultType
            : typeof(void);
        var parameterTypes = GetEntryPointParameterTypes(entryPoint);

        var wrapper = _programType.DefineMethod(
            "__NSharpEntryPoint",
            MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig,
            wrapperReturnType,
            parameterTypes);

        var il = wrapper.GetILGenerator();
        for (int i = 0; i < parameterTypes.Length; i++)
        {
            il.Emit(OpCodes.Ldarg, i);
        }

        il.Emit(OpCodes.Call, entryPoint);

        var savedIl = _currentIL;
        _currentIL = il;
        try
        {
            EmitAwaiterGetResult(entryPoint.ReturnType);
        }
        finally
        {
            _currentIL = savedIl;
        }

        if (wrapperReturnType == typeof(void) && resultType != null)
        {
            il.Emit(OpCodes.Pop);
        }

        il.Emit(OpCodes.Ret);
        _entryPointWrapper = wrapper;
    }

    private static Type[] GetEntryPointParameterTypes(MethodBuilder entryPoint)
    {
        try
        {
            return entryPoint.GetParameters()
                .Select(parameter => parameter.ParameterType)
                .ToArray();
        }
        catch (NotSupportedException)
        {
            return Type.EmptyTypes;
        }
    }

    /// <summary>
    /// Declare a function (method signature only, no body)
    /// </summary>
    private void DeclareFunction(TypeBuilder typeBuilder, FunctionDeclaration function)
    {
        var emittedMethodName = GetEmittedMethodName(function);

        // Create method (without return type and parameter types yet if generic)
        var methodAttributes = VisibilityConventions.GetMemberMethodAttributes(function.Name, function.Modifiers)
            | MethodAttributes.Static
            | MethodAttributes.HideBySig
            | (function.IsOperatorOverload || function.IsConversionOperator ? MethodAttributes.SpecialName : 0);

        var methodBuilder = typeBuilder.DefineMethod(
            emittedMethodName,
            methodAttributes);

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
        ApplyNullableContextAttribute(methodBuilder.SetCustomAttribute);
        if (function.ReturnType != null)
        {
            var returnParameter = methodBuilder.DefineParameter(0, ParameterAttributes.Retval, null);
            ApplyNullableAttribute(returnParameter.SetCustomAttribute, function.ReturnType, genericParameters);
        }

        // Define parameter names
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(function.Parameters[i]), function.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, function.Parameters[i], genericParameters);
        }

        // Store method builder for later reference
        _methods[function.Name] = methodBuilder;
        _declaredMethodParameters[function.Name] = function.Parameters;
        RegisterDeclaredMethodOverload(function.Name, function, methodBuilder);
        DeclareAnonymousUnionParameterShims(
            typeBuilder,
            function,
            methodBuilder,
            methodAttributes,
            returnType,
            parameterTypes,
            genericParameters);
    }

    private void DeclareAnonymousUnionParameterShims(
        TypeBuilder typeBuilder,
        FunctionDeclaration function,
        MethodBuilder target,
        MethodAttributes targetAttributes,
        Type returnType,
        Type[] originalParameterTypes,
        GenericTypeParameterBuilder[]? genericParameters)
    {
        if (function.IsOperatorOverload
            || function.IsConversionOperator
            || function.Modifiers.HasFlag(Modifiers.Abstract)
            || function.TypeParameters is { Count: > 0 }
            || (targetAttributes & MethodAttributes.MemberAccessMask) != MethodAttributes.Public)
        {
            return;
        }

        var unionParameters = function.Parameters
            .Select((parameter, index) => (parameter, index, arms: TryGetTwoArmAnonymousUnion(parameter.Type)))
            .Where(entry => entry.arms != null)
            .ToList();

        if (unionParameters.Count == 0)
            return;

        if (unionParameters.Any(entry => entry.parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out or Ast.ParameterModifier.Params))
            return;

        var shimAttributes = MethodAttributes.Public | MethodAttributes.HideBySig;
        if ((targetAttributes & MethodAttributes.Static) == MethodAttributes.Static)
            shimAttributes |= MethodAttributes.Static;

        foreach (var choice in EnumerateAnonymousUnionArmChoices(unionParameters))
        {
            var shimParameterTypes = function.Parameters
                .Select((parameter, index) =>
                    choice.TryGetValue(index, out var arm)
                        ? ResolveParameterType(parameter with { Type = arm }, genericParameters)
                        : originalParameterTypes[index])
                .ToArray();

            var shim = typeBuilder.DefineMethod(
                target.Name,
                shimAttributes,
                returnType,
                shimParameterTypes);
            ApplyNullableContextAttribute(shim.SetCustomAttribute);

            if (function.ReturnType != null)
            {
                var returnParameter = shim.DefineParameter(0, ParameterAttributes.Retval, null);
                ApplyNullableAttribute(returnParameter.SetCustomAttribute, function.ReturnType, genericParameters);
            }

            for (var i = 0; i < function.Parameters.Count; i++)
            {
                var parameter = function.Parameters[i];
                var parameterForAttributes = choice.TryGetValue(i, out var arm)
                    ? parameter with { Type = arm }
                    : parameter;
                var parameterBuilder = shim.DefineParameter(i + 1, GetParameterAttributes(parameter), parameter.Name);
                ApplyParameterAttributes(parameterBuilder, parameterForAttributes, genericParameters);
            }

            if (!_anonymousUnionShimsByDeclaration.TryGetValue(function, out var shims))
            {
                shims = new List<AnonymousUnionShim>();
                _anonymousUnionShimsByDeclaration[function] = shims;
            }

            shims.Add(new AnonymousUnionShim(shim, target, function, originalParameterTypes, shimParameterTypes));
        }
    }

    private static List<TypeReference>? TryGetTwoArmAnonymousUnion(TypeReference typeReference)
    {
        if (typeReference is not UnionTypeReference union)
            return null;

        var arms = FlattenUnionTypeReference(union).ToList();
        return arms.Count == 2 ? arms : null;
    }

    private static IEnumerable<Dictionary<int, TypeReference>> EnumerateAnonymousUnionArmChoices(
        List<(Parameter parameter, int index, List<TypeReference>? arms)> unionParameters)
    {
        var choices = new List<Dictionary<int, TypeReference>> { new() };
        foreach (var (_, index, arms) in unionParameters)
        {
            var next = new List<Dictionary<int, TypeReference>>();
            foreach (var choice in choices)
            {
                foreach (var arm in arms!)
                {
                    var clone = new Dictionary<int, TypeReference>(choice)
                    {
                        [index] = arm
                    };
                    next.Add(clone);
                }
            }

            choices = next;
        }

        return choices;
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

            // Selection point for pooled async builders (inert until real state machines land).
            ApplyAsyncMethodBuilderAttribute(methodBuilder, returnType);
        }

        InitializeBodyContextForBody(bodyReturnType, function.Body, function.ExpressionBody, function.Parameters);
        InitializeStructuredReturnContext(bodyReturnType);
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
            var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
                ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
            _currentIL.Emit(OpCodes.Newobj, listCtor);
            _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
        }

        RegisterParameterContext(function.Parameters, 0, _currentGenericParameters);

        // Wrap async bodies in a fault guard so a synchronously-thrown exception is surfaced as a
        // faulted task (C# async semantics), rather than escaping the method synchronously.
        var asyncFaultGuard = BeginAsyncFaultGuard();

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
                EmitAsyncReturnFromValueOnStack(asyncFaultGuard);
            }
            else
            {
                EmitExpression(function.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }
        }

        if (asyncFaultGuard)
        {
            EndAsyncFaultGuard();
        }
        // Ensure function ends with a return
        else if (_usesStructuredReturn)
        {
            EmitStructuredReturnTarget();
        }
        else if (_currentGeneratorReturnType != null)
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
        EmitAnonymousUnionParameterShims(function);
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

        var savedLocals = new Dictionary<string, LocalBuilder>(_locals);
        var savedLocalFunctionDeclarations = _localFunctionDeclarations != null
            ? new Dictionary<string, FunctionDeclaration>(_localFunctionDeclarations)
            : null;

        try
        {
            EmitBlockCore(block, savedLocals);
        }
        finally
        {
            _locals = savedLocals;
            _localFunctionDeclarations = savedLocalFunctionDeclarations;
        }
    }

    private void EmitBlockCore(BlockStatement block, IReadOnlyDictionary<string, LocalBuilder> outerLocals)
    {
        if (_currentIL == null || _locals == null)
            throw new InvalidOperationException("No IL generator context");

        var localFunctions = block.Statements
            .OfType<LocalFunctionStatement>()
            .ToList();
        var directLambdaLocals = GetDirectLambdaLocalDeclarations(block, localFunctions);

        foreach (var localFunction in localFunctions)
        {
            _localFunctionDeclarations ??= new Dictionary<string, FunctionDeclaration>();
            _localFunctionDeclarations[localFunction.Function.Name] = localFunction.Function;
        }

        foreach (var directLambdaLocal in directLambdaLocals.Values)
        {
            _localFunctionDeclarations ??= new Dictionary<string, FunctionDeclaration>();
            _localFunctionDeclarations[directLambdaLocal.Function.Name] = directLambdaLocal.Function;
        }

        if (_liftLocalsIntoBoxes || _localsToPredeclareForCapture is { Count: > 0 })
        {
            var predeclaredNames = new HashSet<string>();
            foreach (var statement in block.Statements)
            {
                switch (statement)
                {
                    case VariableDeclarationStatement variableDeclaration:
                        if (directLambdaLocals.ContainsKey(variableDeclaration))
                            break;

                        if (!ShouldPredeclareLocalForCapture(variableDeclaration.Name))
                            break;

                        if (!predeclaredNames.Add(variableDeclaration.Name))
                            break;

                        if (outerLocals.ContainsKey(variableDeclaration.Name))
                            _locals.Remove(variableDeclaration.Name);

                        if (_locals.ContainsKey(variableDeclaration.Name))
                            break;

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
                        for (int i = 0; i < tupleDeconstruction.Names.Count; i++)
                        {
                            var name = tupleDeconstruction.Names[i];
                            if (name == "_" || !ShouldPredeclareLocalForCapture(name) || !predeclaredNames.Add(name))
                            {
                                continue;
                            }

                            if (outerLocals.ContainsKey(name))
                                _locals.Remove(name);

                            if (_locals.ContainsKey(name))
                                continue;

                            if (!TryGetTupleDeconstructionElementType(tupleDeconstruction, i, out var elementType))
                            {
                                continue;
                            }

                            var tupleLocal = DeclareNamedLocal(name, elementType);
                            if (tupleLocal.LocalType != elementType)
                            {
                                EmitInitializeNamedLocal(tupleLocal, elementType, emitDefaultValue: true, initializer: null);
                            }
                        }
                        break;
                }
            }
        }

        var directLocalFunctions = GetDirectLocalFunctionDeclarations(block, localFunctions);

        foreach (var localFunction in localFunctions)
        {
            if (localFunction.Function.TypeParameters is { Count: > 0 }
                || directLocalFunctions.Contains(localFunction.Function))
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

        foreach (var directLambdaLocal in directLambdaLocals.Values)
        {
            DeclareGenericLocalFunction(directLambdaLocal);
        }

        foreach (var localFunction in localFunctions)
        {
            if (localFunction.Function.TypeParameters is { Count: > 0 }
                || directLocalFunctions.Contains(localFunction.Function))
            {
                EmitGenericLocalFunctionBody(localFunction);
                continue;
            }

            EmitLocalFunctionInitialization(localFunction);
        }

        foreach (var directLambdaLocal in directLambdaLocals.Values)
        {
            EmitGenericLocalFunctionBody(directLambdaLocal);
        }

        var declaredNames = new HashSet<string>();
        foreach (var statement in block.Statements)
        {
            if (statement is LocalFunctionStatement localFunction)
            {
                continue;
            }

            ShadowOuterLocalsForBlockDeclaration(statement, outerLocals, declaredNames);
            if (statement is VariableDeclarationStatement variableDeclaration
                && directLambdaLocals.ContainsKey(variableDeclaration))
            {
                continue;
            }

            EmitStatement(statement);
        }
    }

    private void ShadowOuterLocalsForBlockDeclaration(
        Statement statement,
        IReadOnlyDictionary<string, LocalBuilder> outerLocals,
        HashSet<string> declaredNames)
    {
        if (_locals == null)
            return;

        switch (statement)
        {
            case VariableDeclarationStatement variableDeclaration:
                ShadowOuterLocalForBlockDeclaration(variableDeclaration.Name, outerLocals, declaredNames);
                break;

            case TupleDeconstructionStatement tupleDeconstruction:
                foreach (var name in tupleDeconstruction.Names)
                {
                    ShadowOuterLocalForBlockDeclaration(name, outerLocals, declaredNames);
                }
                break;
        }
    }

    private void ShadowOuterLocalForBlockDeclaration(
        string name,
        IReadOnlyDictionary<string, LocalBuilder> outerLocals,
        HashSet<string> declaredNames)
    {
        if (_locals == null || name == "_" || !declaredNames.Add(name))
            return;

        if (IsLiftedIdentifier(name))
            return;

        if (outerLocals.ContainsKey(name))
            _locals.Remove(name);
    }

    private Type GetLocalFunctionDelegateType(FunctionDeclaration function)
    {
        var parameterTypes = function.Parameters
            .Select(parameter => ResolveParameterType(parameter, _currentGenericParameters))
            .ToArray();
        var returnType = GetLocalFunctionReturnType(function);
        return CreateDelegateType(parameterTypes, returnType);
    }

    private Type GetLocalFunctionReturnType(FunctionDeclaration function, GenericTypeParameterBuilder[]? genericParameters = null)
    {
        // A generic local function's own type parameters (e.g. `func f<T>(): T`) are NOT in the
        // enclosing method's generic parameter set, so the return type must be resolved against the
        // combined parameters supplied by the caller. Falling back to _currentGenericParameters here
        // erased a `T` return to `object`, producing GC-unsafe IL (the body returns an unboxed T while
        // the signature claimed object) that crashes the x64 JIT.
        var innerReturnType = function.ReturnType != null
            ? ResolveType(function.ReturnType, genericParameters ?? _currentGenericParameters)
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
            local = existingLocal!;
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

        var isErrorHandling = tupleDecl.Names.Count == 2 && tupleDecl.Names[1] == "err";
        if (isErrorHandling)
        {
            EmitErrorTupleDeconstruction(tupleDecl);
            return;
        }

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
                local = existingLocal!;
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

    private bool TryGetTupleDeconstructionElementType(
        TupleDeconstructionStatement tupleDeconstruction,
        int index,
        out Type elementType)
    {
        if (IsErrorTupleDeconstruction(tupleDeconstruction))
        {
            if (index == 0)
            {
                elementType = GetExpressionType(tupleDeconstruction.Initializer);
                return true;
            }

            if (index == 1)
            {
                elementType = typeof(Exception);
                return true;
            }
        }

        var tupleType = GetExpressionType(tupleDeconstruction.Initializer);
        var field = ResolveRuntimeField(
            tupleType,
            $"Item{index + 1}",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (field == null)
        {
            elementType = typeof(object);
            return false;
        }

        elementType = field.FieldType;
        return true;
    }

    private static bool IsErrorTupleDeconstruction(TupleDeconstructionStatement tupleDeconstruction)
    {
        return tupleDeconstruction.Names.Count == 2 && tupleDeconstruction.Names[1] == "err";
    }

    private void EmitErrorTupleDeconstruction(TupleDeconstructionStatement tupleDecl)
    {
        if (_currentIL == null || _locals == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var resultName = tupleDecl.Names[0];
        var errName = tupleDecl.Names[1];
        var resultType = GetExpressionType(tupleDecl.Initializer);
        LocalBuilder? resultLocal = null;

        if (resultName != "_")
        {
            var hadExistingResult = _locals.TryGetValue(resultName, out var existingResultLocal);
            resultLocal = hadExistingResult ? existingResultLocal : DeclareNamedLocal(resultName, resultType);

            EmitDefaultValue(resultType);
            if (hadExistingResult && IsLiftedIdentifier(resultName))
            {
                EmitStoreLiftedLocalValue(resultLocal!, resultType, leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, resultLocal!);
            }
        }

        var hadExistingErr = _locals.TryGetValue(errName, out var existingErrLocal);
        var errLocal = hadExistingErr ? existingErrLocal : DeclareNamedLocal(errName, typeof(Exception));

        _currentIL.Emit(OpCodes.Ldnull);
        if (hadExistingErr && IsLiftedIdentifier(errName))
        {
            EmitStoreLiftedLocalValue(errLocal!, typeof(Exception), leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, errLocal!);
        }

        _currentIL.BeginExceptionBlock();
        if (resultName == "_")
        {
            EmitExpression(tupleDecl.Initializer);
            if (GetExpressionType(tupleDecl.Initializer) != typeof(void))
            {
                _currentIL.Emit(OpCodes.Pop);
            }
        }
        else
        {
            EmitExpressionWithExpectedType(tupleDecl.Initializer, resultType);
            if (IsLiftedIdentifier(resultName))
            {
                EmitStoreLiftedLocalValue(resultLocal!, resultType, leaveValueOnStack: false);
            }
            else
            {
                _currentIL.Emit(OpCodes.Stloc, resultLocal!);
            }
        }

        _currentIL.BeginCatchBlock(typeof(Exception));
        if (IsLiftedIdentifier(errName))
        {
            EmitStoreLiftedLocalValue(errLocal!, typeof(Exception), leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, errLocal!);
        }

        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for a return statement
    /// </summary>
    private Type GetAwaitResultType(Type awaitableType)
    {
        var getAwaiter = ResolveRuntimeMethod(
            awaitableType,
            "GetAwaiter",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaitable type {awaitableType} does not expose GetAwaiter()");
        var awaiterType = ResolveGenericSignatureType(awaitableType, getAwaiter.ReturnType);
        var getResult = ResolveRuntimeMethod(
            awaiterType,
            "GetResult",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaiter type {awaiterType} does not expose GetResult()");
        return ResolveGenericSignatureType(awaiterType, getResult.ReturnType);
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

        var getAwaiter = ResolveRuntimeMethod(
            awaitableType,
            "GetAwaiter",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            Type.EmptyTypes)
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

        var awaiterType = ResolveGenericSignatureType(awaitableType, getAwaiter.ReturnType);
        var getResult = ResolveRuntimeMethod(
            awaiterType,
            "GetResult",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Awaiter type {awaiterType} does not expose GetResult()");
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
            if (_exceptionBlockDepth > 0)
            {
                EmitStructuredReturnValueOnStack();
                return;
            }

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

        if (_exceptionBlockDepth > 0)
        {
            EmitStructuredReturnValueOnStack();
            return;
        }

        _currentIL.Emit(OpCodes.Ret);
    }

    private void EmitStructuredReturnValueOnStack()
    {
        if (_currentIL == null || _currentReturnLabel == null)
        {
            throw new InvalidOperationException("No structured return context");
        }

        _usesStructuredReturn = true;
        if (_currentReturnLocal != null)
        {
            _currentIL.Emit(OpCodes.Stloc, _currentReturnLocal);
        }

        _currentIL.Emit(OpCodes.Leave, _currentReturnLabel.Value);
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

        Type elementType;
        Type? enumerableInterface = null;
        MethodInfo? getEnumeratorMethod;
        Type enumeratorType;

        // Single-dimension, zero-based arrays (SZArrays) get the allocation-free
        // index-loop fast path (ldlen + index + ldelem) with no enumerator allocation.
        // Multi-dimension or non-zero-based / variable-bound rank-1 arrays fall through
        // to the enumerator path, since ldlen/ldelem are only valid for SZArrays.
        if (IsSingleDimensionZeroBasedArray(collectionType))
        {
            elementType = collectionType.GetElementType()!;
            EmitForeachForArray(foreachStmt, collectionType, elementType);
            return;
        }

        // Span<T> / ReadOnlySpan<T> get an allocation-free index-loop fast path
        // (Length + indexer) with no enumerator allocation. Spans are ref structs,
        // so the enumerator path would be undesirable anyway.
        if (TryGetSpanElementType(collectionType, out var spanElementType, out _))
        {
            EmitForeachForSpan(foreachStmt, collectionType, spanElementType);
            return;
        }

        enumerableInterface = GetRuntimeInterfaces(collectionType)
            .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>));

        if (enumerableInterface == null && collectionType.IsGenericType &&
            collectionType.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>))
        {
            enumerableInterface = collectionType;
        }

        if (enumerableInterface != null)
        {
            getEnumeratorMethod = ResolveRuntimeMethod(enumerableInterface, "GetEnumerator", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes);
            enumeratorType = getEnumeratorMethod != null
                ? ResolveGenericSignatureType(enumerableInterface, getEnumeratorMethod.ReturnType)
                : typeof(System.Collections.Generic.IEnumerator<>).MakeGenericType(enumerableInterface.GetGenericArguments()[0]);
            elementType = enumerableInterface.GetGenericArguments()[0];
        }
        else
        {
            getEnumeratorMethod = ResolveRuntimeMethod(collectionType, "GetEnumerator", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes);
            if (getEnumeratorMethod != null)
            {
                enumeratorType = ResolveGenericSignatureType(collectionType, getEnumeratorMethod.ReturnType);
                elementType = ResolveRuntimeProperty(enumeratorType, "Current", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)?.PropertyType ?? typeof(object);
            }
            else
            {
                getEnumeratorMethod = typeof(System.Collections.IEnumerable).GetMethod("GetEnumerator");
                enumeratorType = typeof(System.Collections.IEnumerator);
                elementType = typeof(object);
            }
        }

        if (getEnumeratorMethod == null)
        {
            throw new InvalidOperationException($"Cannot find GetEnumerator method for type {collectionType}");
        }

        EmitExpression(foreachStmt.Collection);
        _currentIL.Emit(collectionType.IsValueType || !getEnumeratorMethod.IsVirtual ? OpCodes.Call : OpCodes.Callvirt, getEnumeratorMethod);

        var enumeratorLocal = _currentIL.DeclareLocal(enumeratorType);
        _currentIL.Emit(OpCodes.Stloc, enumeratorLocal);

        var moveNextMethod = ResolveRuntimeMethod(enumeratorType, "MoveNext", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes)
            ?? typeof(System.Collections.IEnumerator).GetMethod("MoveNext");
        if (moveNextMethod == null)
        {
            throw new InvalidOperationException("Cannot find MoveNext method");
        }

        var currentProperty = ResolveRuntimeProperty(enumeratorType, "Current", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (currentProperty == null)
        {
            throw new InvalidOperationException("Cannot find Current property");
        }

        var getCurrentMethod = currentProperty.Getter;
        if (getCurrentMethod == null)
        {
            throw new InvalidOperationException("Cannot find get_Current method");
        }

        var loopStart = _currentIL.DefineLabel();
        var loopBody = _currentIL.DefineLabel();
        var disposeLabel = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        _currentIL.MarkLabel(loopStart);

        if (enumeratorType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Ldloca, enumeratorLocal);
            _currentIL.Emit(OpCodes.Call, moveNextMethod);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
            _currentIL.Emit(moveNextMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, moveNextMethod);
        }
        _currentIL.Emit(OpCodes.Brtrue, loopBody);
        _currentIL.Emit(OpCodes.Br, disposeLabel);

        _currentIL.MarkLabel(loopBody);
        if (enumeratorType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Ldloca, enumeratorLocal);
            _currentIL.Emit(OpCodes.Call, getCurrentMethod);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
            _currentIL.Emit(getCurrentMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getCurrentMethod);
        }

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
        var disposeMethod = ResolveRuntimeMethod(enumeratorType, nameof(IDisposable.Dispose), BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes);
        if (disposeMethod != null)
        {
            if (enumeratorType.IsValueType)
            {
                _currentIL.Emit(OpCodes.Ldloca, enumeratorLocal);
                _currentIL.Emit(OpCodes.Call, disposeMethod);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
                _currentIL.Emit(disposeMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, disposeMethod);
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
            : GetRuntimeInterfaces(collectionType).FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IAsyncEnumerable<>));
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
        var addMethod = ResolveCollectionMethod(listType, "Add", method => HasParameterCount(method, 1))
            ?? throw new InvalidOperationException($"Could not resolve Add({_currentYieldElementType}) on {listType}");

        _currentIL.Emit(OpCodes.Ldloc, _currentYieldListLocal);
        EmitExpressionWithExpectedType(yieldStmt.Value, _currentYieldElementType);
        _currentIL.Emit(OpCodes.Callvirt, addMethod);
    }

    /// <summary>
    /// Returns true only for single-dimension, zero-based arrays (SZArrays, i.e. <c>T[]</c>).
    /// These are the only arrays for which <c>ldlen</c>/<c>ldelem</c> are valid IL and for
    /// which the allocation-free index-loop fast path is safe. Multi-dimension arrays
    /// (<c>T[,]</c>) and non-zero-based / variable-bound rank-1 arrays (<c>T[*]</c>) must use
    /// the enumerator path to preserve correct row-major semantics.
    /// </summary>
    private static bool IsSingleDimensionZeroBasedArray(Type type)
    {
        // Type.IsSZArray is the purpose-built predicate: it is true only for single-dimension,
        // zero-based arrays (T[]) and false for multi-dimension (T[,]) and variable-bound
        // rank-1 arrays (T[*]). It is reliable across runtime types, generic-parameter element
        // types, and reflection-only/builder types in the compiler context.
        return type.IsSZArray;
    }

    /// <summary>
    /// Emit IL for foreach over an array (using index-based iteration)
    /// </summary>
    private void EmitForeachForArray(ForeachStatement foreachStmt, Type arrayType, Type elementType)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Store the array in a local
        EmitExpression(foreachStmt.Collection);
        var arrayLocal = _currentIL.DeclareLocal(arrayType);
        _currentIL.Emit(OpCodes.Stloc, arrayLocal);

        // Create index variable (int)
        var indexLocal = _currentIL.DeclareLocal(typeof(int));

        // Initialize index to 0
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // Define labels
        var loopStart = _currentIL.DefineLabel();
        var continueLabel = _currentIL.DefineLabel();
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
        else
            EmitArrayElementLoad(elementType);

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

        _breakLabels.Push(new BranchTarget(loopEnd, useLeave: false));
        _continueLabels.Push(new BranchTarget(continueLabel, useLeave: false));
        try
        {
            EmitStatement(foreachStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.MarkLabel(continueLabel);

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
    /// Emit IL for foreach over a Span&lt;T&gt; or ReadOnlySpan&lt;T&gt; using an
    /// allocation-free index loop. Reads the span's Length once and loads each element
    /// through MemoryMarshal.GetReference + Unsafe.Add + ldind, exactly as span indexing
    /// does. No enumerator is allocated and the ref struct never escapes the stack frame.
    /// </summary>
    private void EmitForeachForSpan(ForeachStatement foreachStmt, Type spanType, Type elementType)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Store the span in a local (ref struct value type — stays on the stack frame).
        EmitExpression(foreachStmt.Collection);
        var spanLocal = _currentIL.DeclareLocal(spanType);
        _currentIL.Emit(OpCodes.Stloc, spanLocal);

        // Cache the length once so the bounds check does not re-read it each iteration.
        var lengthGetter = ResolveRuntimeProperty(spanType, "Length", BindingFlags.Public | BindingFlags.Instance)?.Getter
            ?? throw new InvalidOperationException($"Cannot find Length property for span type {spanType}");
        var lengthLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Ldloca, spanLocal);
        _currentIL.Emit(OpCodes.Call, lengthGetter);
        _currentIL.Emit(OpCodes.Stloc, lengthLocal);

        // Index variable initialized to 0.
        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        var loopStart = _currentIL.DefineLabel();
        var continueLabel = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        _currentIL.MarkLabel(loopStart);

        // if (index >= length) break;
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, lengthLocal);
        _currentIL.Emit(OpCodes.Bge, loopEnd);

        // Load span[index] via GetReference + Unsafe.Add + ldind (the span indexer shape).
        _currentIL.Emit(OpCodes.Ldloc, spanLocal);
        _currentIL.Emit(OpCodes.Call, ResolveSpanGetReferenceMethod(spanType));
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Call, ResolveUnsafeAddMethod(elementType));
        EmitLoadIndirect(elementType);

        // Declare loop variable and store the element.
        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingSpanLoopVar))
        {
            loopVar = existingSpanLoopVar;
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

        _breakLabels.Push(new BranchTarget(loopEnd, useLeave: false));
        _continueLabels.Push(new BranchTarget(continueLabel, useLeave: false));
        try
        {
            EmitStatement(foreachStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.MarkLabel(continueLabel);

        // index++
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.Emit(OpCodes.Br, loopStart);

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
        _exceptionBlockDepth++;

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
        _exceptionBlockDepth--;
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

            case CharLiteralExpression charLit:
                EmitCharLiteral(charLit);
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

            case MustExpression mustExpression:
                EmitMustExpression(mustExpression);
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
                EmitLoadImplicitThisReference();
                break;

            case BaseExpression:
                EmitLoadImplicitThisReference();
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

        if (IsDecimalLiteral(floatLit.Value))
        {
            EmitDecimalLiteral(ParseDecimalLiteralValue(floatLit.Value));
            return;
        }

        if (IsSingleLiteral(floatLit.Value))
        {
            _currentIL.Emit(OpCodes.Ldc_R4, (float)ParseFloatLiteralValue(floatLit.Value));
            return;
        }

        var value = ParseFloatLiteralValue(floatLit.Value);
        _currentIL.Emit(OpCodes.Ldc_R8, value);
    }

    private void EmitDecimalLiteral(decimal value)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var bits = decimal.GetBits(value);
        var scale = (byte)((bits[3] >> 16) & 0x7F);
        var sign = (bits[3] & unchecked((int)0x80000000)) != 0;
        var ctor = typeof(decimal).GetConstructor(new[] { typeof(int), typeof(int), typeof(int), typeof(bool), typeof(byte) })
            ?? throw new InvalidOperationException("decimal constructor not found");

        _currentIL.Emit(OpCodes.Ldc_I4, bits[0]);
        _currentIL.Emit(OpCodes.Ldc_I4, bits[1]);
        _currentIL.Emit(OpCodes.Ldc_I4, bits[2]);
        _currentIL.Emit(sign ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Ldc_I4_S, (sbyte)scale);
        _currentIL.Emit(OpCodes.Newobj, ctor);
    }

    private static object ParseFloatingLiteralObject(string text)
    {
        if (IsDecimalLiteral(text))
            return ParseDecimalLiteralValue(text);
        if (IsSingleLiteral(text))
            return (float)ParseFloatLiteralValue(text);
        return ParseFloatLiteralValue(text);
    }

    private static (object? Value, Type Type) EvaluateFloatingLiteralArgument(string text)
    {
        if (IsDecimalLiteral(text))
            return (ParseDecimalLiteralValue(text), typeof(decimal));
        if (IsSingleLiteral(text))
            return ((float)ParseFloatLiteralValue(text), typeof(float));
        return (ParseFloatLiteralValue(text), typeof(double));
    }

    private static bool IsDecimalLiteral(string text) => text.Trim().EndsWith("m", StringComparison.OrdinalIgnoreCase);

    private static bool IsSingleLiteral(string text) => text.Trim().EndsWith("f", StringComparison.OrdinalIgnoreCase);

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

    private static decimal ParseDecimalLiteralValue(string text)
    {
        var span = text.AsSpan().Trim();
        while (span.Length > 0 && (span[^1] is 'm' or 'M'))
        {
            span = span[..^1];
        }

        var clean = span.ToString().Replace("_", "");
        return decimal.Parse(clean, System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// Parse an integer literal value, handling hex (0x), binary (0b), octal (0o),
    /// underscore separators, and integer suffixes (u, l, ul, etc.)
    /// </summary>
    private static int ParseIntLiteralValue(string text)
    {
        var magnitude = ParseIntLiteralMagnitude(text);
        return checked((int)magnitude);
    }

    private static bool TryParseIntLiteralMagnitude(string text, out long value)
    {
        try
        {
            value = ParseIntLiteralMagnitude(text);
            return true;
        }
        catch
        {
            value = 0;
            return false;
        }
    }

    private static long ParseIntLiteralMagnitude(string text)
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
            return long.Parse(clean[2..], System.Globalization.NumberStyles.HexNumber);
        if (clean.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
            return Convert.ToInt64(clean[2..], 2);
        if (clean.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
            return Convert.ToInt64(clean[2..], 8);

        return long.Parse(clean);
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

    private void EmitCharLiteral(CharLiteralExpression charLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldc_I4, ParseCharLiteralValue(charLit.Value));
    }

    private static char ParseCharLiteralValue(string text)
    {
        if (text.Length < 3 || text[0] != '\'' || text[^1] != '\'')
        {
            throw new FormatException($"Invalid char literal: {text}");
        }

        var body = text[1..^1];
        if (body.Length == 1)
        {
            return body[0];
        }

        if (body.Length == 2 && body[0] == '\\')
        {
            return body[1] switch
            {
                '\'' => '\'',
                '"' => '"',
                '\\' => '\\',
                '0' => '\0',
                'a' => '\a',
                'b' => '\b',
                'f' => '\f',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'v' => '\v',
                _ => throw new FormatException($"Invalid char escape sequence: {text}")
            };
        }

        throw new FormatException($"Invalid char literal: {text}");
    }

    private void EmitDefaultValue(Type targetType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (!IsValueTypeLike(targetType))
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

        _currentIL.Emit(OpCodes.Ldc_I4, parts.Count);
        _currentIL.Emit(OpCodes.Newarr, typeof(string));

        for (int index = 0; index < parts.Count; index++)
        {
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Ldc_I4, index);
            EmitInterpolatedStringPart(parts[index]);
            _currentIL.Emit(OpCodes.Stelem_Ref);
        }

        var concatArrayMethod = typeof(string).GetMethod("Concat", new[] { typeof(string[]) })
            ?? throw new InvalidOperationException("Could not resolve string.Concat(string[])");
        _currentIL.Emit(OpCodes.Call, concatArrayMethod);
    }

    private void EmitInterpolatedStringPart(InterpolatedStringPart part)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (part)
        {
            case InterpolatedStringText text:
                _currentIL.Emit(OpCodes.Ldstr, text.Text);
                break;
            case InterpolatedStringHole hole:
                var exprType = GetExpressionType(hole.Expression);

                if (!string.IsNullOrEmpty(hole.FormatClause))
                {
                    var stringFormatMethod = typeof(string).GetMethod("Format", new[] { typeof(string), typeof(object) })
                        ?? throw new InvalidOperationException("Could not resolve string.Format(string, object)");
                    _currentIL.Emit(OpCodes.Ldstr, "{0:" + hole.FormatClause + "}");
                    EmitExpression(hole.Expression);
                    if (exprType.IsValueType)
                    {
                        _currentIL.Emit(OpCodes.Box, exprType);
                    }

                    _currentIL.Emit(OpCodes.Call, stringFormatMethod);
                    break;
                }

                EmitExpression(hole.Expression);
                if (exprType != typeof(string))
                {
                    if (exprType.IsValueType)
                    {
                        _currentIL.Emit(OpCodes.Box, exprType);
                    }

                    var concatObjectMethod = typeof(string).GetMethod("Concat", new[] { typeof(object) })
                        ?? throw new InvalidOperationException("Could not resolve string.Concat(object)");
                    _currentIL.Emit(OpCodes.Call, concatObjectMethod);
                }
                break;
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
        else if (_localFunctionDeclarations != null
            && _localFunctionDeclarations.TryGetValue(ident.Name, out var localFunctionDeclaration)
            && TryEmitDirectLocalFunctionDelegateValue(localFunctionDeclaration))
        {
            return;
        }
        else if (TryResolveCurrentTypeMember(ident.Name, out _, out var fieldInfo, out var getter, out _))
        {
            if (fieldInfo != null)
            {
                if (fieldInfo.IsStatic)
                {
                    _currentIL.Emit(OpCodes.Ldsfld, fieldInfo);
                }
                else
                {
                    EmitLoadImplicitThisReference();
                    _currentIL.Emit(OpCodes.Ldfld, fieldInfo);
                }

                return;
            }

            if (getter != null)
            {
                if (!getter.IsStatic)
                {
                    EmitLoadImplicitThisReference();
                }

                _currentIL.Emit(getter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getter);
            }
            else
            {
                throw new InvalidOperationException($"Undefined variable, parameter, field, or property: {ident.Name}");
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
        var fieldBuilder = FindDeclaredField(typeBuilder, fieldName);
        if (fieldBuilder != null)
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

    private FieldBuilder? FindDeclaredField(TypeBuilder typeBuilder, string fieldName)
    {
        var fieldKey = GetFieldKey(typeBuilder, fieldName);
        return _fields.TryGetValue(fieldKey, out var fieldBuilder) ? fieldBuilder : null;
    }

    private bool TryResolveCurrentTypeMember(
        Type type,
        string memberName,
        out Type memberType,
        out FieldInfo? field,
        out MethodInfo? getter,
        out MethodInfo? setter)
    {
        field = null;
        getter = null;
        setter = null;
        memberType = typeof(object);

        if (type is TypeBuilder typeBuilder)
        {
            field = FindPrimaryConstructorField(typeBuilder, memberName);
            if (field != null)
            {
                memberType = field.FieldType;
                return true;
            }

            field = FindDeclaredField(typeBuilder, memberName);
            if (field != null)
            {
                memberType = field.FieldType;
                return true;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberName}"), out var declaredGetter))
            {
                getter = declaredGetter;
                _methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{memberName}"), out var declaredSetter);
                setter = declaredSetter;
                memberType = getter.ReturnType;
                return true;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{memberName}"), out var setterOnly))
            {
                setter = setterOnly;
                memberType = setter.GetParameters().LastOrDefault()?.ParameterType ?? typeof(object);
                return true;
            }

            if (typeBuilder.BaseType != null && typeBuilder.BaseType != typeof(object))
            {
                return TryResolveCurrentTypeMember(typeBuilder.BaseType, memberName, out memberType, out field, out getter, out setter);
            }

            return false;
        }

        var runtimeProperty = ResolveRuntimeProperty(
            type,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (runtimeProperty != null && (runtimeProperty.Getter != null || runtimeProperty.Setter != null))
        {
            getter = runtimeProperty.Getter;
            setter = runtimeProperty.Setter;
            memberType = runtimeProperty.PropertyType;
            return true;
        }

        field = ResolveRuntimeField(
            type,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static);
        if (field != null)
        {
            memberType = field.FieldType;
            return true;
        }

        return false;
    }

    private bool TryResolveCurrentTypeMember(
        string memberName,
        out Type memberType,
        out FieldInfo? field,
        out MethodInfo? getter,
        out MethodInfo? setter)
    {
        if (TryGetImplicitInstanceOwnerTypeBuilder(out var ownerTypeBuilder))
        {
            return TryResolveCurrentTypeMember(ownerTypeBuilder, memberName, out memberType, out field, out getter, out setter);
        }

        memberType = typeof(object);
        field = null;
        getter = null;
        setter = null;
        return false;
    }

    private void EmitStoreResolvedCurrentTypeMember(FieldInfo? field, MethodInfo? setter, Type memberType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var tempLocal = _currentIL.DeclareLocal(memberType);
        _currentIL.Emit(OpCodes.Stloc, tempLocal);

        if (field != null)
        {
            if (field.IsStatic)
            {
                _currentIL.Emit(OpCodes.Ldloc, tempLocal);
                _currentIL.Emit(OpCodes.Stsfld, field);
            }
            else
            {
                EmitLoadImplicitThisReference();
                _currentIL.Emit(OpCodes.Ldloc, tempLocal);
                _currentIL.Emit(OpCodes.Stfld, field);
            }

            return;
        }

        if (setter != null)
        {
            if (!setter.IsStatic)
            {
                EmitLoadImplicitThisReference();
            }

            _currentIL.Emit(OpCodes.Ldloc, tempLocal);
            _currentIL.Emit(setter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, setter);
            return;
        }

        throw new InvalidOperationException("No assignable current-type member was resolved");
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
                if (operandType == typeof(int)
                    && unary.Operand is IntLiteralExpression negatedIntLiteral
                    && TryParseIntLiteralMagnitude(negatedIntLiteral.Value, out var intLiteralMagnitude)
                    && intLiteralMagnitude == (long)int.MaxValue + 1)
                {
                    _currentIL.Emit(OpCodes.Ldc_I4, int.MinValue);
                    return;
                }

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

    private void EmitMustExpression(MustExpression mustExpression)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var operandType = GetExpressionType(mustExpression.Expression);
        var nullableUnderlyingType = Nullable.GetUnderlyingType(operandType);

        if (nullableUnderlyingType != null)
        {
            EmitExpression(mustExpression.Expression);
            var nullableLocal = _currentIL.DeclareLocal(operandType);
            _currentIL.Emit(OpCodes.Stloc, nullableLocal);

            var hasValueLabel = _currentIL.DefineLabel();
            EmitNullableHasValue(nullableLocal);
            _currentIL.Emit(OpCodes.Brtrue, hasValueLabel);
            EmitNullableMustFailure();

            _currentIL.MarkLabel(hasValueLabel);
            EmitNullableValue(nullableLocal, nullableUnderlyingType);
            return;
        }

        if (!operandType.IsValueType || operandType.IsGenericParameter)
        {
            EmitExpression(mustExpression.Expression);
            var hasValueLabel = _currentIL.DefineLabel();
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Brtrue, hasValueLabel);
            _currentIL.Emit(OpCodes.Pop);
            EmitNullableMustFailure();
            _currentIL.MarkLabel(hasValueLabel);
            return;
        }

        EmitExpression(mustExpression.Expression);
    }

    private void EmitNullableHasValue(LocalBuilder nullableLocal)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var hasValueGetter = nullableLocal.LocalType.GetProperty(nameof(Nullable<int>.HasValue))?.GetMethod
            ?? throw new InvalidOperationException($"Could not resolve HasValue for {nullableLocal.LocalType}");
        _currentIL.Emit(OpCodes.Ldloca_S, nullableLocal);
        _currentIL.Emit(OpCodes.Call, hasValueGetter);
    }

    private void EmitNullableValue(LocalBuilder nullableLocal, Type underlyingType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var valueGetter = nullableLocal.LocalType.GetProperty(nameof(Nullable<int>.Value))?.GetMethod
            ?? throw new InvalidOperationException($"Could not resolve Value for {nullableLocal.LocalType}");
        _currentIL.Emit(OpCodes.Ldloca_S, nullableLocal);
        _currentIL.Emit(OpCodes.Call, valueGetter);

        if (valueGetter.ReturnType != underlyingType)
        {
            EmitValueCoercion(valueGetter.ReturnType, underlyingType, allowExplicitUserDefinedConversions: false);
        }
    }

    private void EmitNullableMustFailure()
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var ctor = typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })
            ?? throw new InvalidOperationException("Could not resolve InvalidOperationException(string)");
        _currentIL.Emit(OpCodes.Ldstr, "must unwrap failed: value was null");
        _currentIL.Emit(OpCodes.Newobj, ctor);
        _currentIL.Emit(OpCodes.Throw);
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

        if (TryResolveCurrentTypeMember(ident.Name, out var memberType, out var field, out _, out var setter))
        {
            EmitStoreResolvedCurrentTypeMember(field, setter, memberType);
            return;
        }

        throw new InvalidOperationException($"Undefined variable, parameter, field, or property: {ident.Name}");
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

        if (TryEmitNullEqualityComparison(binary))
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

    private bool TryEmitNullEqualityComparison(BinaryExpression binary)
    {
        if (binary.Operator is not (BinaryOperator.Equal or BinaryOperator.NotEqual))
        {
            return false;
        }

        var leftIsNull = binary.Left is NullLiteralExpression;
        var rightIsNull = binary.Right is NullLiteralExpression;
        if (!leftIsNull && !rightIsNull)
        {
            return false;
        }

        var equalToNull = binary.Operator == BinaryOperator.Equal;
        if (leftIsNull && rightIsNull)
        {
            EmitBooleanConstant(equalToNull);
            return true;
        }

        var valueExpression = leftIsNull ? binary.Right : binary.Left;
        var valueType = GetExpressionType(valueExpression);
        var nullableUnderlyingType = Nullable.GetUnderlyingType(valueType);
        if (nullableUnderlyingType != null)
        {
            EmitNullableNullEqualityComparison(valueExpression, valueType, equalToNull);
            return true;
        }

        if (IsValueTypeLike(valueType) && !valueType.IsGenericParameter)
        {
            EmitExpression(valueExpression);
            if (valueType != typeof(void))
            {
                _currentIL!.Emit(OpCodes.Pop);
            }

            EmitBooleanConstant(!equalToNull);
            return true;
        }

        EmitReferenceNullEqualityComparison(valueExpression, equalToNull);
        return true;
    }

    private void EmitNullableNullEqualityComparison(Expression valueExpression, Type nullableType, bool equalToNull)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var hasValueGetter = nullableType.GetProperty(nameof(Nullable<int>.HasValue))?.GetGetMethod();
        if (hasValueGetter == null)
        {
            throw new InvalidOperationException($"Could not resolve nullable HasValue for {nullableType}");
        }

        EmitExpression(valueExpression);
        var valueLocal = _currentIL.DeclareLocal(nullableType);
        _currentIL.Emit(OpCodes.Stloc, valueLocal);
        _currentIL.Emit(OpCodes.Ldloca_S, valueLocal);
        _currentIL.Emit(OpCodes.Call, hasValueGetter);

        if (equalToNull)
        {
            _currentIL.Emit(OpCodes.Ldc_I4_0);
            _currentIL.Emit(OpCodes.Ceq);
        }
    }

    private void EmitReferenceNullEqualityComparison(Expression valueExpression, bool equalToNull)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var matchedLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        EmitExpression(valueExpression);
        _currentIL.Emit(equalToNull ? OpCodes.Brfalse : OpCodes.Brtrue, matchedLabel);
        EmitBooleanConstant(false);
        _currentIL.Emit(OpCodes.Br, endLabel);

        _currentIL.MarkLabel(matchedLabel);
        EmitBooleanConstant(true);
        _currentIL.MarkLabel(endLabel);
    }

    private void EmitBooleanConstant(bool value)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(value ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
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
        if (IsValueTypeLike(leftType))
        {
            _currentIL.Emit(OpCodes.Box, leftType);
        }

        EmitExpression(binary.Right);
        if (IsValueTypeLike(rightType))
        {
            _currentIL.Emit(OpCodes.Box, rightType);
        }

        _currentIL.Emit(OpCodes.Call, concatMethod);
    }

    private void EmitNullCoalesce(BinaryExpression binary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var leftType = GetExpressionType(binary.Left);
        if (IsValueTypeLike(leftType) && Nullable.GetUnderlyingType(leftType) == null)
        {
            EmitExpression(binary.Left);
            return;
        }

        var resultType = GetNullCoalesceExpressionType(binary);
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
            EmitExpressionWithExpectedType(binary.Right, resultType);
            _currentIL.Emit(OpCodes.Br, endLabel);

            _currentIL.MarkLabel(useLeftLabel);
            if (AreTypeIdentitiesEquivalent(resultType, leftType))
            {
                _currentIL.Emit(OpCodes.Ldloc, leftLocal);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldloca_S, leftLocal);
                _currentIL.Emit(OpCodes.Call, getValueOrDefault);
                EmitValueCoercion(Nullable.GetUnderlyingType(leftType)!, resultType, allowExplicitUserDefinedConversions: false);
            }
            _currentIL.MarkLabel(endLabel);
            return;
        }

        _currentIL.Emit(OpCodes.Brtrue, useLeftLabel);
        EmitExpressionWithExpectedType(binary.Right, resultType);
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
                        throw new InvalidOperationException($"No matching overload for static method {memberAccess.MemberName} on type {GetTypeKey(staticTypeBuilder)} with arguments ({DescribeCallArgumentTypes(call.Arguments)})");
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

                throw new InvalidOperationException($"Static method {memberAccess.MemberName} not found on type {GetTypeKey(staticType)} with arguments ({DescribeCallArgumentTypes(call.Arguments)})");
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
                    var useDirectBoundCall = useAddressReceiverForBoundCall
                        || !boundInstanceCall.Method.IsVirtual
                        || CanDevirtualizeInstanceCall(memberAccess.Object, objectType);
                    _currentIL.Emit(useDirectBoundCall ? OpCodes.Call : OpCodes.Callvirt, boundInstanceCall.Method);
                    return;
                }

                if (_declaredMethodOverloads.ContainsKey(GetMethodKey(typeBuilder, memberAccess.MemberName)))
                {
                    throw new InvalidOperationException($"No matching overload for method {memberAccess.MemberName} on type {GetTypeKey(typeBuilder)} with arguments ({DescribeCallArgumentTypes(call.Arguments)})");
                }
            }

            var useAddressReceiver = IsValueTypeLike(objectType) && !objectType.IsGenericParameter;

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
                var useDirectUserCall = useAddressReceiver
                    || !userDefinedMethod.IsVirtual
                    || CanDevirtualizeInstanceCall(memberAccess.Object, objectType);
                _currentIL.Emit(useDirectUserCall ? OpCodes.Call : OpCodes.Callvirt, userDefinedMethod);
                return;
            }

            // Handle constrained calls on generic type parameters. Loading the
            // receiver by address and emitting a `constrained.` prefix lets the
            // runtime dispatch on the concrete type argument without boxing the
            // value when `T` is instantiated with a value type.
            if (objectType.IsGenericParameter)
            {
                EmitAddressableExpression(memberAccess.Object, objectType);

                var constraints = objectType.GetGenericParameterConstraints();

                // Prefer declared/duck interface (or class) constraints that are
                // defined in this compilation: their methods live in TypeBuilders
                // and cannot be resolved through runtime reflection binding.
                foreach (var constraint in constraints)
                {
                    if (!TryGetUserTypeDefinition(constraint, out var constraintBuilder))
                    {
                        continue;
                    }

                    var boundDeclaredCall = BindDeclaredMethodCall(
                        GetMethodKey(constraintBuilder, memberAccess.MemberName),
                        call,
                        targetType: constraint,
                        predicate: overload => !overload.Builder.IsStatic);
                    if (boundDeclaredCall != null)
                    {
                        EmitBoundCallArguments(boundDeclaredCall.Arguments);

                        // constrained. on the type parameter avoids boxing the
                        // receiver when the method is dispatched virtually.
                        _currentIL.Emit(OpCodes.Constrained, objectType);
                        _currentIL.Emit(OpCodes.Callvirt, boundDeclaredCall.Method);
                        return;
                    }

                    // Interface declarations only register their members in the
                    // method table (not the overload table), so fall back to a
                    // direct lookup and bind the call arguments positionally.
                    var declaredMethod = ResolveUserDefinedMethod(constraint, memberAccess.MemberName);
                    if (declaredMethod != null)
                    {
                        EmitCallArguments(call.Arguments, declaredMethod.GetParameters().Select(parameter => parameter.ParameterType).ToArray());

                        _currentIL.Emit(OpCodes.Constrained, objectType);
                        _currentIL.Emit(OpCodes.Callvirt, declaredMethod);
                        return;
                    }
                }

                // Otherwise resolve the method against a runtime (BCL) constraint.
                BoundRuntimeMethodCall? boundRuntimeCall = null;
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

                throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on generic type parameter {objectType.Name} with arguments ({DescribeCallArgumentTypes(call.Arguments)})");
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
                if (useAddressReceiver
                    || !boundRuntimeMethod.Method.IsVirtual
                    || CanDevirtualizeInstanceCall(memberAccess.Object, objectType))
                {
                    _currentIL.Emit(OpCodes.Call, boundRuntimeMethod.Method);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Callvirt, boundRuntimeMethod.Method);
                }
                return;
            }

            var extensionCall = BindDeclaredExtensionMethodCall(
                memberAccess.MemberName,
                call,
                memberAccess.Object);
            if (extensionCall != null)
            {
                EmitBoundCallArguments(extensionCall.Arguments);
                _currentIL.Emit(OpCodes.Call, extensionCall.Method);
                return;
            }

            var runtimeExtensionMethod = BindRuntimeExtensionMethodCall(
                objectType,
                memberAccess.MemberName,
                memberAccess.Object,
                call);
            if (runtimeExtensionMethod != null)
            {
                EmitBoundCallArguments(runtimeExtensionMethod.Arguments);
                _currentIL.Emit(OpCodes.Call, runtimeExtensionMethod.Method);
                return;
            }

            throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on type {objectType.Name} at {call.Line}:{call.Column} with arguments ({DescribeCallArgumentTypes(call.Arguments)})");
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

            if (_currentTypeBuilder != null)
            {
                var currentTypeStaticCall = BindDeclaredMethodCall(
                    GetMethodKey(_currentTypeBuilder, ident.Name),
                    call,
                    predicate: overload => overload.Builder.IsStatic);
                if (currentTypeStaticCall != null)
                {
                    EmitBoundCallArguments(currentTypeStaticCall.Arguments);
                    _currentIL.Emit(OpCodes.Call, currentTypeStaticCall.Method);
                    return;
                }

                if (TryGetImplicitInstanceOwnerTypeBuilder(out var implicitInstanceTypeBuilder))
                {
                    var currentTypeInstanceCall = BindDeclaredMethodCall(
                        GetMethodKey(implicitInstanceTypeBuilder, ident.Name),
                        call,
                        predicate: overload => !overload.Builder.IsStatic);
                    if (currentTypeInstanceCall != null)
                    {
                        EmitLoadImplicitThisReference();
                        EmitBoundCallArguments(currentTypeInstanceCall.Arguments);
                        _currentIL.Emit(currentTypeInstanceCall.Method.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, currentTypeInstanceCall.Method);
                        return;
                    }
                }

                if (_declaredMethodOverloads.ContainsKey(GetMethodKey(_currentTypeBuilder, ident.Name))
                    || (TryGetImplicitInstanceOwnerTypeBuilder(out var overloadOwnerTypeBuilder)
                        && _declaredMethodOverloads.ContainsKey(GetMethodKey(overloadOwnerTypeBuilder, ident.Name))))
                {
                    var ownerType = TryGetImplicitInstanceOwnerTypeBuilder(out var errorOwnerTypeBuilder)
                        ? errorOwnerTypeBuilder
                        : _currentTypeBuilder;
                    throw new InvalidOperationException($"No matching overload for method {GetTypeKey(ownerType)}.{ident.Name}");
                }
            }

            if (TryGetImplicitInstanceOwnerType(out var implicitOwnerType))
            {
                var runtimeLookupType = GetImplicitInstanceRuntimeLookupType(implicitOwnerType);
                var boundImplicitRuntimeCall = BindRuntimeMethodCall(
                    runtimeLookupType,
                    ident.Name,
                    call,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                if (boundImplicitRuntimeCall != null)
                {
                    EmitLoadImplicitThisReference();
                    EmitBoundCallArguments(boundImplicitRuntimeCall.Arguments);
                    _currentIL.Emit(boundImplicitRuntimeCall.Method.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, boundImplicitRuntimeCall.Method);
                    return;
                }
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
            if (!TryResolveCurrentTypeMember(ident.Name, out var memberType, out var field, out _, out var setter))
            {
                throw new InvalidOperationException($"Undefined variable, parameter, field, or property: {ident.Name}");
            }

            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitStoreResolvedCurrentTypeMember(field, setter, memberType);
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
                    EmitMemberLoadValue(objectType, memberAccess.MemberName);
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
                EmitMemberStoreValue(objectType, memberAccess.MemberName);
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
            if (!TryResolveCurrentTypeMember(ident.Name, out var memberType, out var field, out _, out var setter))
            {
                throw new InvalidOperationException($"Undefined variable, parameter, field, or property: {ident.Name}");
            }

            EmitStoreResolvedCurrentTypeMember(field, setter, memberType);
        }

        // Assignment expressions also return the assigned value, so we need to load it back
        // This allows things like: x = y = 5
        EmitIdentifier(ident);
    }

    /// <summary>
    /// Emit construction of a value-struct union case by calling the case's static
    /// factory on the union struct. This leaves the union value on the stack with no
    /// per-case heap allocation in the caller (a single <c>call</c>).
    /// </summary>
    private void EmitValueStructUnionConstruction(ValueStructUnionLayout layout, Type caseType)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var factory = layout.CaseFactories[caseType];
        _currentIL.Emit(OpCodes.Call, factory);
    }

    /// <summary>
    /// Emit IL for a new object expression
    /// </summary>
    private void EmitNewObject(NewExpression newExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var type = ResolveNewExpressionType(newExpr);

        // Allocation-free value-struct union case construction: `new U.Case` produces a
        // U struct value via the case's static factory, instead of allocating a case class.
        if (TryGetValueStructUnionCase(type, out var unionLayout, out _))
        {
            EmitValueStructUnionConstruction(unionLayout, type);
            return;
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
                throw new InvalidOperationException($"No matching constructor found for type {type.Name} with arguments ({DescribeCallArgumentTypes(newExpr.ConstructorArguments)})");
            }
            else
            {
                constructor = ResolveUserDefinedConstructor(type);
                if (constructor == null && !(type.IsValueType && newExpr.ConstructorArguments.Count == 0))
                {
                    throw new InvalidOperationException($"No matching constructor found for type {type.Name} with arguments ({DescribeCallArgumentTypes(newExpr.ConstructorArguments)})");
                }
            }
        }
        else
        {
            var boundRuntimeConstructorCall = BindRuntimeConstructorCall(type, newExpr.ConstructorArguments);
            if (boundRuntimeConstructorCall != null)
            {
                constructor = boundRuntimeConstructorCall.Constructor;
                boundArguments = boundRuntimeConstructorCall.Arguments;
            }

            if (constructor == null)
            {
                if (!(type.IsValueType && newExpr.ConstructorArguments.Count == 0))
                {
                    throw new InvalidOperationException($"No matching constructor found for type {type.Name} with arguments ({DescribeCallArgumentTypes(newExpr.ConstructorArguments)})");
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
            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"set_{initializer.Name}"), out var setterMethod))
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, setterMethod.GetParameters()[0].ParameterType);
                _currentIL.Emit(callOpcode, setterMethod);
                return;
            }

            var primaryConstructorField = FindPrimaryConstructorField(typeBuilder, initializer.Name);
            if (primaryConstructorField != null)
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, primaryConstructorField.FieldType);
                _currentIL.Emit(OpCodes.Stfld, primaryConstructorField);
                return;
            }

            if (_fields.TryGetValue(GetFieldKey(typeBuilder, initializer.Name), out var fieldBuilder))
            {
                _currentIL.Emit(useAddressReceiver ? OpCodes.Ldloca_S : OpCodes.Ldloc, targetLocal);
                EmitExpressionWithExpectedType(initializer.Value, fieldBuilder.FieldType);
                _currentIL.Emit(OpCodes.Stfld, fieldBuilder);
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
    private static bool TryGetSpanElementType(Type objectType, out Type elementType, out bool isReadOnlySpan)
    {
        elementType = typeof(object);
        isReadOnlySpan = false;

        if (!objectType.IsGenericType || objectType.IsGenericTypeDefinition)
        {
            return false;
        }

        Type genericDefinition;
        try
        {
            genericDefinition = objectType.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return false;
        }

        if (genericDefinition != typeof(Span<>) && genericDefinition != typeof(ReadOnlySpan<>))
        {
            return false;
        }

        elementType = objectType.GetGenericArguments()[0];
        isReadOnlySpan = genericDefinition == typeof(ReadOnlySpan<>);
        return true;
    }

    private static MethodInfo ResolveSpanGetReferenceMethod(Type spanType)
    {
        var genericDefinition = spanType.GetGenericTypeDefinition();
        var openMethod = typeof(System.Runtime.InteropServices.MemoryMarshal)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .First(method =>
            {
                if (method.Name != "GetReference" || !method.IsGenericMethodDefinition)
                {
                    return false;
                }

                var parameters = method.GetParameters();
                return parameters.Length == 1
                    && parameters[0].ParameterType.IsGenericType
                    && parameters[0].ParameterType.GetGenericTypeDefinition() == genericDefinition;
            });

        return openMethod.MakeGenericMethod(spanType.GetGenericArguments()[0]);
    }

    private static MethodInfo ResolveUnsafeAddMethod(Type elementType)
    {
        var openMethod = typeof(System.Runtime.CompilerServices.Unsafe)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .First(method =>
            {
                if (method.Name != "Add" || !method.IsGenericMethodDefinition)
                {
                    return false;
                }

                var parameters = method.GetParameters();
                return parameters.Length == 2
                    && parameters[0].ParameterType.IsByRef
                    && parameters[1].ParameterType == typeof(int);
            });

        return openMethod.MakeGenericMethod(elementType);
    }

    private bool TryEmitRuntimeIndexAccess(IndexAccessExpression indexAccess, Type objectType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (objectType.IsArray || objectType == typeof(string) || objectType is TypeBuilder)
        {
            return false;
        }

        var indexType = GetExpressionType(indexAccess.Index);
        if (TryGetSpanElementType(objectType, out var spanElementType, out _))
        {
            var objectLocal = _currentIL.DeclareLocal(objectType);
            var indexLocal = _currentIL.DeclareLocal(indexType);
            EmitExpression(indexAccess.Object);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);
            EmitExpression(indexAccess.Index);
            _currentIL.Emit(OpCodes.Stloc, indexLocal);
            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            _currentIL.Emit(OpCodes.Call, ResolveSpanGetReferenceMethod(objectType));
            _currentIL.Emit(OpCodes.Ldloc, indexLocal);
            _currentIL.Emit(OpCodes.Call, ResolveUnsafeAddMethod(spanElementType));
            EmitLoadIndirect(spanElementType);
            return true;
        }

        var runtimeIndexerGetter = ResolveRuntimeMethod(
            objectType,
            "get_Item",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            new[] { indexType });
        if (runtimeIndexerGetter == null)
        {
            return false;
        }

        var useAddressReceiver = IsValueTypeLike(objectType) && !objectType.IsGenericParameter;
        if (useAddressReceiver)
        {
            var objectLocal = _currentIL.DeclareLocal(objectType);
            EmitExpression(indexAccess.Object);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);
            _currentIL.Emit(OpCodes.Ldloca_S, objectLocal);
        }
        else
        {
            EmitExpression(indexAccess.Object);
        }

        EmitExpression(indexAccess.Index);
        _currentIL.Emit(runtimeIndexerGetter.IsVirtual && !useAddressReceiver ? OpCodes.Callvirt : OpCodes.Call, runtimeIndexerGetter);

        var returnType = ResolveGenericSignatureType(objectType, runtimeIndexerGetter.ReturnType);
        if (returnType.IsByRef)
        {
            EmitLoadIndirect(GetByRefElementType(returnType));
        }

        return true;
    }

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

        if (TryEmitRuntimeIndexAccess(indexAccess, objectType))
        {
            return;
        }

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
                EmitArrayElementLoad(elementType);
                return;
            }

            EmitArrayElementLoad(elementType);
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
        var runtimeIndexerGetter = ResolveRuntimeMethod(
            objectType,
            "get_Item",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            new[] { reflectionIndexType });
        if (runtimeIndexerGetter != null)
        {
            _currentIL.Emit(runtimeIndexerGetter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, runtimeIndexerGetter);
            var runtimeReturnType = ResolveGenericSignatureType(objectType, runtimeIndexerGetter.ReturnType);
            if (runtimeReturnType.IsByRef)
            {
                EmitLoadIndirect(GetByRefElementType(runtimeReturnType));
            }

            return;
        }

        PropertyInfo? indexer = null;
        try
        {
            indexer = objectType.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(p =>
                    p.GetIndexParameters().Length == 1 &&
                    p.GetMethod != null &&
                    AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, reflectionIndexType));
        }
        catch (NotSupportedException)
        {
        }
        catch (NotImplementedException)
        {
        }

        if (indexer?.GetMethod != null)
        {
            _currentIL.Emit(indexer.GetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, indexer.GetMethod);
            if (indexer.GetMethod.ReturnType.IsByRef)
            {
                EmitLoadIndirect(GetByRefElementType(indexer.GetMethod.ReturnType));
            }

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
                EmitArrayElementStore(elementType);
                return;
            }

            EmitArrayElementStore(elementType);
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
        if (TryGetSpanElementType(objectType, out var spanElementType, out var isReadOnlySpan)
            && !isReadOnlySpan)
        {
            var valueLocal = _currentIL.DeclareLocal(spanElementType);
            var indexLocal = _currentIL.DeclareLocal(reflectionIndexType);
            var objectLocal = _currentIL.DeclareLocal(objectType);

            _currentIL.Emit(OpCodes.Stloc, valueLocal);
            _currentIL.Emit(OpCodes.Stloc, indexLocal);
            _currentIL.Emit(OpCodes.Stloc, objectLocal);
            _currentIL.Emit(OpCodes.Ldloc, objectLocal);
            _currentIL.Emit(OpCodes.Call, ResolveSpanGetReferenceMethod(objectType));
            _currentIL.Emit(OpCodes.Ldloc, indexLocal);
            _currentIL.Emit(OpCodes.Call, ResolveUnsafeAddMethod(spanElementType));
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitStoreIndirect(spanElementType);
            return;
        }

        var runtimeIndexerSetter = ResolveRuntimeMethod(
            objectType,
            "set_Item",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            new[] { reflectionIndexType, GetIndexAccessType(indexAccess) });
        if (runtimeIndexerSetter != null)
        {
            _currentIL.Emit(runtimeIndexerSetter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, runtimeIndexerSetter);
            return;
        }

        var runtimeIndexerGetter = ResolveRuntimeMethod(
            objectType,
            "get_Item",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            new[] { reflectionIndexType });
        if (runtimeIndexerGetter != null)
        {
            var runtimeReturnType = ResolveGenericSignatureType(objectType, runtimeIndexerGetter.ReturnType);
            if (runtimeReturnType.IsByRef)
            {
                var valueType = GetByRefElementType(runtimeReturnType);
                var valueLocal = _currentIL.DeclareLocal(valueType);
                var indexLocal = _currentIL.DeclareLocal(reflectionIndexType);
                var objectLocal = _currentIL.DeclareLocal(objectType);
                var useAddressReceiver = IsValueTypeLike(objectType) && !objectType.IsGenericParameter;

                _currentIL.Emit(OpCodes.Stloc, valueLocal);
                _currentIL.Emit(OpCodes.Stloc, indexLocal);
                _currentIL.Emit(OpCodes.Stloc, objectLocal);

                if (useAddressReceiver)
                {
                    _currentIL.Emit(OpCodes.Ldloca_S, objectLocal);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldloc, objectLocal);
                }

                _currentIL.Emit(OpCodes.Ldloc, indexLocal);
                _currentIL.Emit(runtimeIndexerGetter.IsVirtual && !useAddressReceiver ? OpCodes.Callvirt : OpCodes.Call, runtimeIndexerGetter);
                _currentIL.Emit(OpCodes.Ldloc, valueLocal);
                EmitStoreIndirect(valueType);
                return;
            }
        }

        PropertyInfo? indexer = null;
        try
        {
            indexer = objectType.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(p =>
                    p.GetIndexParameters().Length == 1 &&
                    p.SetMethod != null &&
                    AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, reflectionIndexType));
        }
        catch (NotSupportedException)
        {
        }
        catch (NotImplementedException)
        {
        }

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
        else if (elementType.IsGenericParameter || elementType.ContainsGenericParameters)
        {
            _currentIL.Emit(OpCodes.Ldelema, elementType);
            EmitLoadIndirect(elementType);
        }
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
        {
            var valueLocal = _currentIL.DeclareLocal(elementType);
            _currentIL.Emit(OpCodes.Stloc, valueLocal);
            _currentIL.Emit(OpCodes.Ldelema, elementType);
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitStoreIndirect(elementType);
        }
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

        var property = ResolveRuntimeProperty(
            objectType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property?.Getter != null)
        {
            _currentIL.Emit(OpCodes.Callvirt, property.Getter);
            return;
        }

        var field = ResolveRuntimeField(
            objectType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
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
                if (!TryEmitDeclaredStaticConstant(staticTypeBuilder, memberName))
                {
                    _currentIL.Emit(OpCodes.Ldsfld, staticField);
                }
                return;
            }

            if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"get_{memberName}"), out var staticGetter))
            {
                _currentIL.Emit(OpCodes.Call, staticGetter);
                return;
            }

            throw new InvalidOperationException($"Static member {memberName} not found on type {GetTypeKey(staticTypeBuilder)}");
        }

        var declaredStaticFieldKey = GetFieldKey(staticType, memberName);
        if (_fields.TryGetValue(declaredStaticFieldKey, out var declaredStaticField))
        {
            if (_fieldConstants.TryGetValue(declaredStaticFieldKey, out var declaredConstantValue))
            {
                EmitConstantValue(declaredConstantValue, declaredStaticField.FieldType);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldsfld, declaredStaticField);
            }
            return;
        }

        var staticProperty = ResolveRuntimeProperty(
            staticType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticProperty?.Getter != null)
        {
            _currentIL.Emit(OpCodes.Call, staticProperty.Getter);
            return;
        }

        var staticFieldInfo = ResolveRuntimeField(
            staticType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticFieldInfo != null)
        {
            if (staticFieldInfo.IsLiteral)
            {
                EmitConstantValue(staticFieldInfo.GetRawConstantValue(), staticFieldInfo.FieldType);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldsfld, staticFieldInfo);
            }
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

        var property = ResolveRuntimeProperty(
            objectType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property?.Setter != null)
        {
            _currentIL.Emit(OpCodes.Callvirt, property.Setter);
            return;
        }

        var field = ResolveRuntimeField(
            objectType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
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

        var staticProperty = ResolveRuntimeProperty(
            staticType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        if (staticProperty?.Setter != null)
        {
            _currentIL.Emit(OpCodes.Call, staticProperty.Setter);
            return;
        }

        var staticFieldInfo = ResolveRuntimeField(
            staticType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
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

        var nullableObjectType = GetExpressionType(memberAccess.Object);
        var nullableUnderlyingType = Nullable.GetUnderlyingType(nullableObjectType);
        if (nullableUnderlyingType != null
            && (memberAccess.MemberName == "HasValue" || memberAccess.MemberName == "Value"))
        {
            EmitExpression(memberAccess.Object);
            var nullableLocal = _currentIL.DeclareLocal(nullableObjectType);
            _currentIL.Emit(OpCodes.Stloc, nullableLocal);

            if (memberAccess.MemberName == "HasValue")
            {
                EmitNullableHasValue(nullableLocal);
                return;
            }

            EmitNullableValue(nullableLocal, nullableUnderlyingType);
            return;
        }

        if (TryResolveStaticContainer(memberAccess.Object, out var staticType))
        {
            if (staticType is TypeBuilder staticTypeBuilder)
            {
                if (_fields.TryGetValue(GetFieldKey(staticTypeBuilder, memberAccess.MemberName), out var staticField))
                {
                    if (TryEmitDeclaredStaticConstant(staticTypeBuilder, memberAccess.MemberName))
                    {
                        return;
                    }

                    _currentIL.Emit(OpCodes.Ldsfld, staticField);
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
                var declaredStaticFieldKey = GetFieldKey(staticType, memberAccess.MemberName);
                if (_fields.TryGetValue(declaredStaticFieldKey, out var declaredStaticField))
                {
                    if (_fieldConstants.TryGetValue(declaredStaticFieldKey, out var declaredConstantValue))
                    {
                        EmitConstantValue(declaredConstantValue, declaredStaticField.FieldType);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldsfld, declaredStaticField);
                    }
                    return;
                }

                var staticProperty = ResolveRuntimeProperty(
                    staticType,
                    memberAccess.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticProperty?.Getter != null)
                {
                    _currentIL.Emit(OpCodes.Call, staticProperty.Getter);
                    return;
                }

                var staticField = ResolveRuntimeField(
                    staticType,
                    memberAccess.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticField != null)
                {
                    if (staticField.IsLiteral)
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
        var objectType = nullableObjectType;
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
            var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0));
            var addMethod = ResolveCollectionMethod(listType, "Add", method => HasParameterCount(method, 1));
            var addRangeMethod = ResolveCollectionMethod(listType, "AddRange", method => HasSingleEnumerableParameter(method));
            var toArrayMethod = ResolveCollectionMethod(listType, "ToArray", method => HasParameterCount(method, 0));

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

        if (IsRuntimeUnionType(sourceType) && !AreTypeIdentitiesEquivalent(sourceType, targetType))
        {
            if (cast.Kind == CastKind.Safe)
            {
                EmitRuntimeUnionTryCast(cast.Expression, sourceType, targetType);
            }
            else
            {
                EmitRuntimeUnionAsCast(cast.Expression, sourceType, targetType);
            }
            return;
        }

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
        var sourceType = GetExpressionType(isExpr.Expression);
        if (IsRuntimeUnionType(sourceType))
        {
            EmitRuntimeUnionIsExpression(isExpr, sourceType, targetType);
            return;
        }

        // `unionValue is U.Case` on a value-struct union is an integer tag compare, not a
        // reference-type isinst (which would be invalid IL against a value type). The case
        // carries no payload, so there is nothing to bind; produce the boolean result.
        if (TryGetValueStructUnionCase(targetType, out var vsIsLayout, out var vsIsTag))
        {
            EmitValueStructUnionIsTest(isExpr.Expression, vsIsLayout, vsIsTag);
            return;
        }

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

    private void EmitRuntimeUnionAsCast(Expression expression, Type unionType, Type targetType)
    {
        var unionLocal = _currentIL!.DeclareLocal(unionType);
        EmitExpression(expression);
        _currentIL.Emit(OpCodes.Stloc, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca, unionLocal);
        _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(unionType, nameof(NSharpLang.Runtime.Union<int, string>.As)).MakeGenericMethod(targetType));
    }

    private void EmitRuntimeUnionTryCast(Expression expression, Type unionType, Type targetType)
    {
        var unionLocal = _currentIL!.DeclareLocal(unionType);
        var resultLocal = _currentIL.DeclareLocal(targetType);
        var successLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        EmitExpression(expression);
        _currentIL.Emit(OpCodes.Stloc, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca, resultLocal);
        _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(unionType, nameof(NSharpLang.Runtime.Union<int, string>.TryGet)).MakeGenericMethod(targetType));
        _currentIL.Emit(OpCodes.Brtrue, successLabel);

        EmitDefaultValue(targetType);
        _currentIL.Emit(OpCodes.Br, endLabel);

        _currentIL.MarkLabel(successLabel);
        _currentIL.Emit(OpCodes.Ldloc, resultLocal);
        _currentIL.MarkLabel(endLabel);
    }

    private void EmitRuntimeUnionIsExpression(IsExpression isExpr, Type unionType, Type targetType)
    {
        var unionLocal = _currentIL!.DeclareLocal(unionType);
        EmitExpression(isExpr.Expression);
        _currentIL.Emit(OpCodes.Stloc, unionLocal);

        if (isExpr.VariableName == null)
        {
            _currentIL.Emit(OpCodes.Ldloca, unionLocal);
            _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(unionType, nameof(NSharpLang.Runtime.Union<int, string>.Is)).MakeGenericMethod(targetType));
            return;
        }

        if (_locals == null)
        {
            throw new InvalidOperationException("Variable binding in is-expression requires local scope");
        }

        var local = DeclareNamedLocal(isExpr.VariableName, targetType);
        if (IsLiftedIdentifier(isExpr.VariableName))
        {
            var tempLocal = _currentIL.DeclareLocal(targetType);
            var endLabel = _currentIL.DefineLabel();

            _currentIL.Emit(OpCodes.Ldloca, unionLocal);
            _currentIL.Emit(OpCodes.Ldloca, tempLocal);
            _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(unionType, nameof(NSharpLang.Runtime.Union<int, string>.TryGet)).MakeGenericMethod(targetType));
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Brfalse, endLabel);
            _currentIL.Emit(OpCodes.Ldloc, tempLocal);
            EmitStoreLiftedLocalValue(local, targetType, leaveValueOnStack: false);
            _currentIL.MarkLabel(endLabel);
            return;
        }

        _currentIL.Emit(OpCodes.Ldloca, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca, local);
        _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(unionType, nameof(NSharpLang.Runtime.Union<int, string>.TryGet)).MakeGenericMethod(targetType));
    }

    private static bool IsRuntimeUnionType(Type type)
    {
        try
        {
            return type.IsGenericType && type.GetGenericTypeDefinition() == typeof(NSharpLang.Runtime.Union<,>);
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool TryGetRuntimeUnionArmTypes(Type type, out Type[] arms)
    {
        if (IsRuntimeUnionType(type))
        {
            arms = type.GetGenericArguments();
            return arms.Length == 2;
        }

        arms = Array.Empty<Type>();
        return false;
    }

    private static MethodInfo GetRuntimeUnionImplicitConversionOperator(Type unionType, int armIndex)
    {
        var openMethod = typeof(NSharpLang.Runtime.Union<,>)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(method =>
            {
                if (method.Name != "op_Implicit")
                {
                    return false;
                }

                var parameters = method.GetParameters();
                return parameters.Length == 1
                    && parameters[0].ParameterType.IsGenericParameter
                    && parameters[0].ParameterType.GenericParameterPosition == armIndex;
            })
            ?? throw new InvalidOperationException($"Could not find runtime union implicit operator for arm {armIndex} on {unionType}.");

        if (RequiresTypeBuilderMemberResolution(unionType))
        {
            return TypeBuilder.GetMethod(unionType, openMethod);
        }

        var arms = unionType.GetGenericArguments();
        return unionType.GetMethods(BindingFlags.Public | BindingFlags.Static)
                   .FirstOrDefault(method =>
                   {
                       if (method.Name != "op_Implicit")
                       {
                           return false;
                       }

                       var parameters = method.GetParameters();
                       return parameters.Length == 1
                           && armIndex < arms.Length
                           && AreTypeIdentitiesEquivalent(parameters[0].ParameterType, arms[armIndex]);
                   })
               ?? openMethod;
    }

    private static MethodInfo GetRuntimeUnionGenericMethod(Type unionType, string methodName)
    {
        var openMethod = typeof(NSharpLang.Runtime.Union<,>)
            .GetMethods(BindingFlags.Public | BindingFlags.Instance)
            .FirstOrDefault(method => method.Name == methodName && method.IsGenericMethodDefinition)
            ?? throw new InvalidOperationException($"Could not find runtime union method '{methodName}' on {unionType}.");

        return RequiresTypeBuilderMemberResolution(unionType)
            ? TypeBuilder.GetMethod(unionType, openMethod)
            : unionType.GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .FirstOrDefault(method => method.Name == methodName && method.IsGenericMethodDefinition)
                ?? openMethod;
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
            FloatLiteralExpression floatLiteral when IsDecimalLiteral(floatLiteral.Value) => typeof(decimal),
            FloatLiteralExpression floatLiteral when IsSingleLiteral(floatLiteral.Value) => typeof(float),
            FloatLiteralExpression => typeof(double),
            CharLiteralExpression => typeof(char),
            StringLiteralExpression => typeof(string),
            InterpolatedStringExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            IdentifierExpression ident => GetIdentifierType(ident),
            RangeExpression => typeof(Range),
            UnaryExpression unary => GetUnaryExpressionType(unary),
            MustExpression mustExpression => GetMustExpressionType(mustExpression),
            BinaryExpression binary => GetBinaryExpressionType(binary),
            ParenthesizedExpression paren => GetExpressionType(paren.Inner),
            AssignmentExpression assignment => GetExpressionType(assignment.Value),
            TupleExpression tuple => GetTupleExpressionType(tuple),
            NewExpression newExpr => newExpr.Type != null || _expectedExpressionType != null || IsAnonymousObjectCreation(newExpr)
                ? MapValueStructUnionCaseToUnion(ResolveNewExpressionType(newExpr))
                : typeof(object),
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
            ThisExpression => GetCapturedThisType() ?? _currentTypeBuilder ?? typeof(object),
            BaseExpression => (GetCapturedThisType() ?? _currentTypeBuilder)?.BaseType ?? typeof(object),
            ThrowExpression => typeof(void),
            TypeOfExpression => typeof(Type),
            NameofExpression => typeof(string),
            SizeOfExpression => typeof(int),
            SpreadExpression spread => GetExpressionType(spread.Expression),
            DefaultExpression => _expectedExpressionType ?? typeof(object),
            CheckedExpression checkedExpr => GetExpressionType(checkedExpr.Expression),
            UncheckedExpression uncheckedExpr => GetExpressionType(uncheckedExpr.Expression),
            _ => typeof(object)
        };
    }

    private Type GetLambdaExpressionType(LambdaExpression lambda)
    {
        if (_expectedExpressionType != null && TryGetExpressionTreeDelegateType(_expectedExpressionType, out _))
        {
            return _expectedExpressionType;
        }

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

        var matchValueType = GetExpressionType(match.Value);
        var resultType = GetMatchCaseExpressionType(match.Cases[0], matchValueType);
        foreach (var matchCase in match.Cases.Skip(1))
        {
            var caseType = GetMatchCaseExpressionType(matchCase, matchValueType);
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

    private Type GetMatchCaseExpressionType(MatchCase matchCase, Type matchValueType)
    {
        var savedPatternBindingTypes = _patternBindingTypeHints;
        _patternBindingTypeHints = savedPatternBindingTypes != null
            ? new Dictionary<string, Type>(savedPatternBindingTypes)
            : new Dictionary<string, Type>();

        AddPatternBindingTypeHints(matchCase.Pattern, matchValueType);

        try
        {
            return GetExpressionType(matchCase.Expression);
        }
        finally
        {
            _patternBindingTypeHints = savedPatternBindingTypes;
        }
    }

    private void AddPatternBindingTypeHints(Pattern pattern, Type valueType)
    {
        switch (pattern)
        {
            case IdentifierPattern identifierPattern:
                if (identifierPattern.Name != "_"
                    && !identifierPattern.Name.Contains('.')
                    && !TryResolvePatternType(identifierPattern.Name, out _))
                {
                    AddPatternBindingTypeHint(identifierPattern.Name, Nullable.GetUnderlyingType(valueType) ?? valueType);
                }
                break;

            case TypePattern typePattern:
                if (typePattern.BindingName != null)
                {
                    AddPatternBindingTypeHint(typePattern.BindingName, ResolveType(typePattern.Type));
                }
                break;

            case UnionCasePattern unionCasePattern:
                if (TryResolveDeclaredProjectType(unionCasePattern.CaseName, treatStringEnumAsString: false, out var caseType)
                    && unionCasePattern.Properties != null)
                {
                    AddPropertyPatternBindingTypeHints(caseType, unionCasePattern.Properties);
                }
                break;

            case ObjectPattern objectPattern:
                AddPropertyPatternBindingTypeHints(valueType, objectPattern.Properties);
                break;

            case PositionalPattern positionalPattern:
                AddPositionalPatternBindingTypeHints(valueType, positionalPattern);
                break;

            case ListPattern listPattern:
                AddListPatternBindingTypeHints(valueType, listPattern);
                break;

            case SlicePattern slicePattern when slicePattern.BindingName != null:
                AddPatternBindingTypeHint(slicePattern.BindingName, valueType);
                break;

            case AndPattern andPattern:
                AddPatternBindingTypeHints(andPattern.Left, valueType);
                AddPatternBindingTypeHints(andPattern.Right, valueType);
                break;
        }
    }

    private void AddPropertyPatternBindingTypeHints(Type targetType, IReadOnlyList<PropertyPattern> properties)
    {
        foreach (var property in properties)
        {
            if (!TryGetPatternMemberType(targetType, property.Name, out var memberType))
            {
                continue;
            }

            if (property.Pattern != null)
            {
                AddPatternBindingTypeHints(property.Pattern, memberType);
            }
            else
            {
                AddPatternBindingTypeHint(property.BindingName ?? property.Name, memberType);
            }
        }
    }

    private void AddPositionalPatternBindingTypeHints(Type targetType, PositionalPattern positionalPattern)
    {
        if (TryResolveDeconstructMethod(targetType, positionalPattern.Patterns.Count, out _, out var elementTypes))
        {
            for (var i = 0; i < positionalPattern.Patterns.Count; i++)
            {
                AddPatternBindingTypeHints(positionalPattern.Patterns[i], elementTypes[i]);
            }

            return;
        }

        for (var i = 0; i < positionalPattern.Patterns.Count; i++)
        {
            if (TryGetPatternMemberType(targetType, $"Item{i + 1}", out var elementType))
            {
                AddPatternBindingTypeHints(positionalPattern.Patterns[i], elementType);
            }
        }
    }

    private void AddListPatternBindingTypeHints(Type valueType, ListPattern listPattern)
    {
        var elementType = valueType.IsArray
            ? valueType.GetElementType() ?? typeof(object)
            : TryGetListPatternShape(valueType, out var shape) && shape != null
                ? shape.ElementType
                : typeof(object);

        foreach (var elementPattern in listPattern.Elements)
        {
            if (elementPattern is SlicePattern slicePattern && slicePattern.BindingName != null)
            {
                AddPatternBindingTypeHint(slicePattern.BindingName, elementType.MakeArrayType());
                continue;
            }

            AddPatternBindingTypeHints(elementPattern, elementType);
        }
    }

    private void AddPatternBindingTypeHint(string name, Type type)
    {
        _patternBindingTypeHints ??= new Dictionary<string, Type>();
        _patternBindingTypeHints[name] = type;
    }

    private bool TryGetPatternMemberType(Type targetType, string memberName, out Type memberType)
    {
        if (targetType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(typeBuilder, memberName), out var fieldBuilder))
            {
                memberType = fieldBuilder.FieldType;
                return true;
            }

            if (_methods.TryGetValue(GetMethodKey(typeBuilder, $"get_{memberName}"), out var getterMethod))
            {
                memberType = getterMethod.ReturnType;
                return true;
            }

            memberType = typeof(object);
            return false;
        }

        var property = ResolveRuntimeProperty(
            targetType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (property != null)
        {
            memberType = property.PropertyType;
            return true;
        }

        var field = ResolveRuntimeField(
            targetType,
            memberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (field != null)
        {
            memberType = field.FieldType;
            return true;
        }

        memberType = typeof(object);
        return false;
    }

    /// <summary>
    /// Get the type of an identifier
    /// </summary>
    private Type GetIdentifierType(IdentifierExpression ident)
    {
        if (_patternBindingTypeHints != null && _patternBindingTypeHints.TryGetValue(ident.Name, out var patternBindingType))
        {
            return patternBindingType;
        }

        if (_inferredLocalTypes != null && _inferredLocalTypes.TryGetValue(ident.Name, out var inferredLocalType))
        {
            return inferredLocalType;
        }

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

        if (TryResolveCurrentTypeMember(ident.Name, out var memberType, out _, out _, out _))
        {
            return memberType;
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
            BinaryOperator.NullCoalesce => GetNullCoalesceExpressionType(binary),
            BinaryOperator.Range => typeof(Range),
            _ => GetExpressionType(binary.Left)
        };
    }

    private Type GetNullCoalesceExpressionType(BinaryExpression binary)
    {
        var leftType = GetExpressionType(binary.Left);
        var nullableUnderlyingType = Nullable.GetUnderlyingType(leftType);
        if (nullableUnderlyingType == null)
        {
            return leftType;
        }

        var rightType = GetExpressionType(binary.Right);
        return Nullable.GetUnderlyingType(rightType) != null
            ? rightType
            : nullableUnderlyingType;
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

    private Type GetMustExpressionType(MustExpression mustExpression)
    {
        var operandType = GetExpressionType(mustExpression.Expression);
        return Nullable.GetUnderlyingType(operandType) ?? operandType;
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
                    return GetDeclaredStaticFieldType(staticTypeBuilder, unwrapNullConditional.MemberName, staticField);
                }

                if (_methods.TryGetValue(GetMethodKey(staticTypeBuilder, $"get_{unwrapNullConditional.MemberName}"), out var staticGetter))
                {
                    return staticGetter.ReturnType;
                }
            }
            else
            {
                var declaredStaticFieldKey = GetFieldKey(staticType, unwrapNullConditional.MemberName);
                if (_fields.TryGetValue(declaredStaticFieldKey, out var declaredStaticField))
                {
                    return declaredStaticField.FieldType;
                }

                var staticProperty = ResolveRuntimeProperty(
                    staticType,
                    unwrapNullConditional.MemberName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                if (staticProperty != null)
                {
                    return staticProperty.PropertyType;
                }

                var staticField = ResolveRuntimeField(
                    staticType,
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
        var nullableUnderlyingType = Nullable.GetUnderlyingType(objectType);
        if (nullableUnderlyingType != null)
        {
            if (unwrapNullConditional.MemberName == "HasValue")
            {
                return typeof(bool);
            }

            if (unwrapNullConditional.MemberName == "Value")
            {
                return nullableUnderlyingType;
            }
        }

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

        if (TryGetSpanElementType(objectType, out var spanElementType, out _))
        {
            return spanElementType;
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

        var runtimeIndexerGetter = ResolveRuntimeMethod(
            objectType,
            "get_Item",
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
            new[] { indexType });
        if (runtimeIndexerGetter != null)
        {
            return GetByRefElementType(ResolveGenericSignatureType(objectType, runtimeIndexerGetter.ReturnType));
        }

        PropertyInfo? indexer = null;
        try
        {
            indexer = objectType.GetDefaultMembers()
                .OfType<PropertyInfo>()
                .FirstOrDefault(p =>
                    p.GetIndexParameters().Length == 1 &&
                    AreParameterTypesCompatible(p.GetIndexParameters()[0].ParameterType, indexType));
        }
        catch (NotSupportedException)
        {
        }
        catch (NotImplementedException)
        {
        }

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
                        targetType: staticType,
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
                return boundStaticRuntimeCall?.ReturnType ?? typeof(object);
            }

            var objectType = GetExpressionType(memberAccess.Object);

            // Check user-defined methods first
            if (TryGetUserTypeDefinition(objectType, out var typeBuilder))
            {
                var boundInstanceCall = BindDeclaredMethodCall(
                    GetMethodKey(typeBuilder, memberAccess.MemberName),
                    call,
                    targetType: objectType,
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
                var genericConstraints = objectType.GetGenericParameterConstraints();

                // Declared/duck interface (or class) constraints defined in this
                // compilation resolve through the TypeBuilder method tables.
                foreach (var constraint in genericConstraints)
                {
                    if (!TryGetUserTypeDefinition(constraint, out var constraintBuilder))
                    {
                        continue;
                    }

                    var boundDeclaredCall = BindDeclaredMethodCall(
                        GetMethodKey(constraintBuilder, memberAccess.MemberName),
                        call,
                        targetType: constraint,
                        predicate: overload => !overload.Builder.IsStatic);
                    if (boundDeclaredCall != null)
                    {
                        return GetBoundDeclaredMethodReturnType(boundDeclaredCall);
                    }

                    var declaredMethod = ResolveUserDefinedMethod(constraint, memberAccess.MemberName);
                    if (declaredMethod != null)
                    {
                        return declaredMethod.ReturnType;
                    }
                }

                foreach (var constraint in genericConstraints)
                {
                    var constrainedMethod = BindRuntimeMethodCall(
                        constraint,
                        memberAccess.MemberName,
                        call,
                        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                    if (constrainedMethod != null)
                    {
                        return constrainedMethod.ReturnType;
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
                return method.ReturnType;
            }

            var boundExtensionCall = BindDeclaredExtensionMethodCall(
                memberAccess.MemberName,
                call,
                memberAccess.Object);
            if (boundExtensionCall != null)
            {
                return GetBoundDeclaredMethodReturnType(boundExtensionCall);
            }

            var runtimeExtensionMethod = BindRuntimeExtensionMethodCall(
                objectType,
                memberAccess.MemberName,
                memberAccess.Object,
                call);
            if (runtimeExtensionMethod != null)
            {
                return runtimeExtensionMethod.ReturnType;
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

            if (_currentTypeBuilder != null)
            {
                var currentTypeStaticCall = BindDeclaredMethodCall(
                    GetMethodKey(_currentTypeBuilder, ident.Name),
                    call,
                    predicate: overload => overload.Builder.IsStatic);
                if (currentTypeStaticCall != null)
                {
                    return GetBoundDeclaredMethodReturnType(currentTypeStaticCall);
                }

                if (TryGetImplicitInstanceOwnerTypeBuilder(out var implicitInstanceTypeBuilder))
                {
                    var currentTypeInstanceCall = BindDeclaredMethodCall(
                        GetMethodKey(implicitInstanceTypeBuilder, ident.Name),
                        call,
                        predicate: overload => !overload.Builder.IsStatic);
                    if (currentTypeInstanceCall != null)
                    {
                        return GetBoundDeclaredMethodReturnType(currentTypeInstanceCall);
                    }
                }

                if (_declaredMethodOverloads.ContainsKey(GetMethodKey(_currentTypeBuilder, ident.Name))
                    || (TryGetImplicitInstanceOwnerTypeBuilder(out var overloadOwnerTypeBuilder)
                        && _declaredMethodOverloads.ContainsKey(GetMethodKey(overloadOwnerTypeBuilder, ident.Name))))
                {
                    return typeof(object);
                }

                if (_methods.TryGetValue(GetMethodKey(_currentTypeBuilder, ident.Name), out methodBuilder))
                {
                    return methodBuilder.ReturnType;
                }
            }

            if (TryGetImplicitInstanceOwnerType(out var implicitOwnerType))
            {
                var runtimeLookupType = GetImplicitInstanceRuntimeLookupType(implicitOwnerType);
                var boundImplicitRuntimeCall = BindRuntimeMethodCall(
                    runtimeLookupType,
                    ident.Name,
                    call,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                if (boundImplicitRuntimeCall != null)
                {
                    return boundImplicitRuntimeCall.ReturnType;
                }
            }
        }

        return typeof(object);
    }

    private Type GetBoundDeclaredMethodReturnType(BoundDeclaredMethodCall boundCall)
    {
        var declaredReturnType = boundCall.Declaration.ReturnType;
        if (declaredReturnType == null)
        {
            return ResolveTargetGenericSignatureType(
                boundCall.TargetType,
                ResolveMethodOwnerGenericSignatureType(boundCall.Method, boundCall.Method.ReturnType));
        }

        var substitutions = GetDeclaredMethodReturnTypeSubstitutions(boundCall);
        if (substitutions.Count > 0)
        {
            return ResolveType(declaredReturnType, substitutions);
        }

        return ResolveTargetGenericSignatureType(
            boundCall.TargetType,
            ResolveMethodOwnerGenericSignatureType(boundCall.Method, boundCall.Method.ReturnType));
    }

    private Dictionary<string, Type> GetDeclaredMethodReturnTypeSubstitutions(BoundDeclaredMethodCall boundCall)
    {
        var substitutions = new Dictionary<string, Type>(StringComparer.Ordinal);

        TypeBuilder? ownerTypeBuilder = null;
        Type? ownerType = boundCall.TargetType;
        if (ownerType != null)
        {
            TryGetUserTypeDefinition(ownerType, out ownerTypeBuilder);
        }
        else if (boundCall.Method.DeclaringType != null
            && TryGetUserTypeDefinition(boundCall.Method.DeclaringType, out var declaringTypeBuilder))
        {
            ownerTypeBuilder = declaringTypeBuilder;
            ownerType = boundCall.Method.DeclaringType;
        }

        if (ownerTypeBuilder != null && GetTypeGenericParameters(ownerTypeBuilder) is { Length: > 0 } ownerParameters)
        {
            var ownerArguments = GetDeclaredOwnerTypeArguments(ownerType, ownerParameters);
            for (int i = 0; i < ownerParameters.Length && i < ownerArguments.Length; i++)
            {
                substitutions[ownerParameters[i].Name] = ownerArguments[i];
            }
        }

        if (boundCall.Declaration.TypeParameters is { Count: > 0 }
            && boundCall.TypeArguments != null
            && boundCall.TypeArguments.Count == boundCall.Declaration.TypeParameters.Count)
        {
            for (int i = 0; i < boundCall.Declaration.TypeParameters.Count; i++)
            {
                substitutions[boundCall.Declaration.TypeParameters[i].Name] = boundCall.TypeArguments[i];
            }
        }

        return substitutions;
    }

    private static Type[] GetDeclaredOwnerTypeArguments(Type? ownerType, IReadOnlyList<Type> ownerParameters)
    {
        if (ownerType != null)
        {
            try
            {
                if (ownerType.IsGenericType && !ownerType.IsGenericTypeDefinition)
                {
                    return ownerType.GetGenericArguments();
                }
            }
            catch (NotSupportedException)
            {
            }
        }

        return ownerParameters.ToArray();
    }

    private static Type ResolveTargetGenericSignatureType(Type? targetType, Type signatureType)
    {
        if (targetType != null
            && targetType.IsGenericType
            && !targetType.IsGenericTypeDefinition)
        {
            return ResolveGenericSignatureType(targetType, signatureType);
        }

        return signatureType;
    }

    private static Type ResolveMethodOwnerGenericSignatureType(MethodInfo method, Type signatureType)
    {
        var declaringType = method.DeclaringType;
        if (declaringType != null
            && declaringType.IsGenericType
            && !declaringType.IsGenericTypeDefinition)
        {
            return ResolveGenericSignatureType(declaringType, signatureType);
        }

        return signatureType;
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

        if (typeRef is UnionTypeReference unionType)
        {
            var arms = FlattenUnionTypeReference(unionType).ToList();
            if (arms.Count != 2)
                return typeof(object);

            return typeof(NSharpLang.Runtime.Union<,>).MakeGenericType(
                ResolveType(arms[0], genericTypeArguments),
                ResolveType(arms[1], genericTypeArguments));
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

            if (TryResolveDeclaredProjectType(simpleType.Name, treatStringEnumAsString: true, out var declaredType))
            {
                return declaredType;
            }

            foreach (var candidate in GetDeclaredTypeNameCandidates(simpleType.Name).Distinct(StringComparer.Ordinal))
            {
                var externalType = ResolveExternalType(candidate);
                if (externalType != null)
                {
                    return externalType;
                }
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

        if (typeRef is UnionTypeReference unionType)
        {
            var arms = FlattenUnionTypeReference(unionType).ToList();
            if (arms.Count != 2)
                return typeof(object);

            return typeof(NSharpLang.Runtime.Union<,>).MakeGenericType(
                ResolveType(arms[0], genericParameters),
                ResolveType(arms[1], genericParameters));
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

    private static IEnumerable<TypeReference> FlattenUnionTypeReference(TypeReference typeReference)
    {
        if (typeReference is UnionTypeReference union)
        {
            foreach (var arm in union.Arms)
            {
                foreach (var nestedArm in FlattenUnionTypeReference(arm))
                    yield return nestedArm;
            }
        }
        else
        {
            yield return typeReference;
        }
    }

    private bool TryEnsureUserTypeDeclared(string name)
    {
        if (_moduleBuilder == null)
        {
            return false;
        }

        var resolvedTypeName = ResolveDeclaredTypeName(name);
        if (resolvedTypeName == null)
        {
            return false;
        }

        if (_types.ContainsKey(resolvedTypeName) || _enumTypes.ContainsKey(resolvedTypeName) || _stringEnumContainers.ContainsKey(resolvedTypeName))
        {
            return true;
        }

        if (!_typesBeingDeclared.Add(resolvedTypeName))
        {
            return false;
        }

        try
        {
            if (!TryGetDeclaredTypeInfo(resolvedTypeName, out var declaredType))
            {
                return false;
            }

            switch (declaredType.Declaration)
            {
                case ClassDeclaration classDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareClass(_moduleBuilder, classDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingClass))
                    {
                        DeclareClass(containingClass, classDecl, resolvedTypeName);
                    }
                    break;
                case StructDeclaration structDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareStruct(_moduleBuilder, structDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingStruct))
                    {
                        DeclareStruct(containingStruct, structDecl, resolvedTypeName);
                    }
                    break;
                case RecordDeclaration recordDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareRecord(_moduleBuilder, recordDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingRecord))
                    {
                        DeclareRecord(containingRecord, recordDecl, resolvedTypeName);
                    }
                    break;
                case InterfaceDeclaration interfaceDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareInterface(_moduleBuilder, interfaceDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingInterface))
                    {
                        DeclareInterface(containingInterface, interfaceDecl, resolvedTypeName);
                    }
                    break;
                case EnumDeclaration enumDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareEnum(_moduleBuilder, enumDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingEnum))
                    {
                        DeclareEnum(containingEnum, enumDecl, resolvedTypeName);
                    }
                    break;
                case UnionDeclaration unionDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareUnion(_moduleBuilder, unionDecl);
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingUnion))
                    {
                        DeclareUnion(containingUnion, unionDecl, resolvedTypeName);
                    }
                    break;
                case NewtypeDeclaration newtypeDecl:
                    if (declaredType.ContainingTypeName == null)
                    {
                        DeclareRecord(_moduleBuilder, CreateSyntheticNewtypeRecord(newtypeDecl));
                    }
                    else if (TryEnsureUserTypeDeclared(declaredType.ContainingTypeName)
                             && _types.TryGetValue(declaredType.ContainingTypeName, out var containingNewtype))
                    {
                        DeclareRecord(containingNewtype, CreateSyntheticNewtypeRecord(newtypeDecl), resolvedTypeName);
                    }
                    break;
                default:
                    return false;
            }

            return _types.ContainsKey(resolvedTypeName)
                || _enumTypes.ContainsKey(resolvedTypeName)
                || _stringEnumContainers.ContainsKey(resolvedTypeName);
        }
        finally
        {
            _typesBeingDeclared.Remove(resolvedTypeName);
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

        if (baseType == null
            && TryResolveDeclaredProjectType(typeName, treatStringEnumAsString: false, out var declaredType)
            && declaredType is TypeBuilder typeBuilder)
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
        return ResolveExternalType(typeName, allowGlobalSimpleNameFallback: true);
    }

    private void EnsureExternalAssembliesLoaded(string typeName)
    {
        foreach (var assemblyName in GetExternalAssemblyNameCandidates(typeName))
        {
            TryLoadAssemblyByName(assemblyName);
        }
    }

    private static IEnumerable<string> GetExternalAssemblyNameCandidates(string typeName)
    {
        if (string.IsNullOrWhiteSpace(typeName))
        {
            yield break;
        }

        var normalizedTypeName = typeName.Replace('+', '.');
        var segments = normalizedTypeName.Split('.', StringSplitOptions.RemoveEmptyEntries);
        for (var length = segments.Length - 1; length >= 1; length--)
        {
            yield return string.Join(".", segments.Take(length));
        }
    }

    private static IEnumerable<string> GetExternalTypeMetadataNameCandidates(string typeName)
    {
        if (string.IsNullOrWhiteSpace(typeName))
        {
            yield break;
        }

        yield return typeName;

        var normalizedTypeName = typeName.Replace('+', '.');
        var segments = normalizedTypeName.Split('.', StringSplitOptions.RemoveEmptyEntries);
        for (var nestedSegmentCount = 1; nestedSegmentCount < segments.Length; nestedSegmentCount++)
        {
            var namespaceSegmentCount = segments.Length - nestedSegmentCount;
            if (namespaceSegmentCount <= 0)
            {
                break;
            }

            yield return string.Join(".", segments.Take(namespaceSegmentCount))
                + "+"
                + string.Join("+", segments.Skip(namespaceSegmentCount));
        }
    }

    private static Type? TryResolveLoadedExternalType(string candidate)
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

        return null;
    }

    private Type? ResolveExternalType(string typeName, bool allowGlobalSimpleNameFallback)
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
            foreach (var metadataCandidate in GetExternalTypeMetadataNameCandidates(candidate).Distinct(StringComparer.Ordinal))
            {
                var resolved = TryResolveLoadedExternalType(metadataCandidate);
                if (resolved != null)
                {
                    return resolved;
                }

                EnsureExternalAssembliesLoaded(metadataCandidate);

                resolved = TryResolveLoadedExternalType(metadataCandidate);
                if (resolved != null)
                {
                    return resolved;
                }
            }
        }

        if (allowGlobalSimpleNameFallback && !typeName.Contains('.'))
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

        var typeAttributes = GetTypeVisibilityAttributes(classDecl.Name, classDecl.Modifiers) | TypeAttributes.Class;

        if (classDecl.Modifiers.HasFlag(Modifiers.Abstract))
            typeAttributes |= TypeAttributes.Abstract;
        if (classDecl.Modifiers.HasFlag(Modifiers.Sealed))
            typeAttributes |= TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            classDecl.Name,
            typeAttributes);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, classDecl.Attributes);
        ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

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

        allBaseTypes.AddRange(GetMatchingDuckInterfaces(classDecl.Members).Select(interfaceDecl => ResolveDuckInterfaceType(interfaceDecl, genericParameters)));

        Type? baseType = null;
        foreach (var candidateType in allBaseTypes)
        {
            if (candidateType.IsInterface)
            {
                TrackInterfaceImplementation(typeBuilder, candidateType);
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

        DeclareNestedTypes(typeBuilder, classDecl.Members, classDecl.Name);
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

        var typeAttributes = GetTypeVisibilityAttributes(structDecl.Name, structDecl.Modifiers) | TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            structDecl.Name,
            typeAttributes,
            typeof(ValueType));
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, structDecl.Attributes);
        ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

        RegisterType(structDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, structDecl.TypeParameters);

        if (structDecl.Interfaces != null)
        {
            foreach (var interfaceType in structDecl.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                TrackInterfaceImplementation(typeBuilder, interfaceType);
            }
        }

        foreach (var duckInterface in GetMatchingDuckInterfaces(structDecl.Members))
        {
            TrackInterfaceImplementation(typeBuilder, ResolveDuckInterfaceType(duckInterface, genericParameters));
        }

        DeclareNestedTypes(typeBuilder, structDecl.Members, structDecl.Name);
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

        var typeAttributes = GetInterfaceTypeVisibilityAttributes(interfaceDecl) | TypeAttributes.Interface | TypeAttributes.Abstract;

        var typeBuilder = moduleBuilder.DefineType(
            interfaceDecl.Name,
            typeAttributes);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, interfaceDecl.Attributes);
        ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

        RegisterType(interfaceDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, interfaceDecl.TypeParameters);

        if (interfaceDecl.BaseInterfaces != null)
        {
            foreach (var baseInterface in interfaceDecl.BaseInterfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                TrackInterfaceImplementation(typeBuilder, baseInterface);
            }
        }

        DeclareNestedTypes(typeBuilder, interfaceDecl.Members, interfaceDecl.Name);
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
                GetTypeVisibilityAttributes(enumDecl.Name, enumDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Abstract | TypeAttributes.Sealed);
            ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

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
            GetTypeVisibilityAttributes(enumDecl.Name, enumDecl.Modifiers),
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

        // Allocation-free path: small, closed, value-friendly, payload-free unions are
        // emitted as a readonly struct with an integer tag instead of a class hierarchy.
        if (Performance.UnionValueLayout.IsValueStructEmittable(unionDecl))
        {
            DeclareValueStructUnion(moduleBuilder, unionDecl);
            return;
        }

        var unionType = moduleBuilder.DefineType(
            unionDecl.Name,
            GetTypeVisibilityAttributes(unionDecl.Name, unionDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Abstract);
        ApplyCustomAttributes(unionType.SetCustomAttribute, unionDecl.Attributes);
        ApplyNullableContextAttribute(unionType.SetCustomAttribute);
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
                VisibilityConventions.GetNestedTypeAttributes(unionCase.Name, Modifiers.None) | TypeAttributes.Class | TypeAttributes.Sealed,
                unionType);
            ApplyNullableContextAttribute(caseType.SetCustomAttribute);

            var caseKey = $"{unionDecl.Name}.{unionCase.Name}";
            RegisterType(caseKey, caseType);
            var defaultCaseCtor = caseType.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);
            _constructors[GetConstructorKey(caseType)] = defaultCaseCtor;
            var defaultConstructorDeclaration = new ConstructorDeclaration(
                new List<Parameter>(),
                new BlockStatement(new List<Statement>(), unionCase.Line, unionCase.Column),
                Initializer: null,
                Modifiers.None,
                new List<AttributeNode>(),
                unionCase.Line,
                unionCase.Column);
            RegisterDeclaredConstructorOverload(GetConstructorKey(caseType), defaultConstructorDeclaration, defaultCaseCtor);

            var caseParameters = unionCase.Properties?
                .Select(property => new Parameter(
                    property.Name,
                    property.Type,
                    DefaultValue: null,
                    IsThis: false))
                .ToList();
            var caseParameterTypes = caseParameters?
                .Select(parameter => ResolveType(parameter.Type))
                .ToArray()
                ?? Type.EmptyTypes;
            if (caseParameters != null)
            {
                var caseCtor = caseType.DefineConstructor(
                    MethodAttributes.Public,
                    CallingConventions.Standard,
                    caseParameterTypes);
                for (int i = 0; i < caseParameters.Count; i++)
                {
                    var parameterBuilder = caseCtor.DefineParameter(i + 1, GetParameterAttributes(caseParameters[i]), caseParameters[i].Name);
                    ApplyParameterAttributes(parameterBuilder, caseParameters[i]);
                }

                var syntheticConstructor = new ConstructorDeclaration(
                    caseParameters,
                    new BlockStatement(new List<Statement>(), unionCase.Line, unionCase.Column),
                    Initializer: null,
                    Modifiers.None,
                    new List<AttributeNode>(),
                    unionCase.Line,
                    unionCase.Column);
                RegisterDeclaredConstructorOverload(GetConstructorKey(caseType), syntheticConstructor, caseCtor);
            }

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
                    VisibilityConventions.GetMemberFieldAttributes(property.Name, Modifiers.None));
                ApplyNullableAttribute(fieldBuilder.SetCustomAttribute, property.Type);
                _fields[GetFieldKey(caseType, property.Name)] = fieldBuilder;
            }
        }
    }

    /// <summary>
    /// Emit a small, closed, payload-free union as an allocation-free
    /// <c>readonly struct</c> with an integer discriminator tag. Each case is assigned
    /// a distinct tag value; construction writes the tag (no <c>newobj</c>) and pattern
    /// tests compare the tag (no <c>isinst</c>). Nested case marker types are still
    /// emitted so reflection / type-resolution / tooling continue to see
    /// <c>Union+Case</c>, but they are never instantiated.
    /// </summary>
    private void DeclareValueStructUnion(ModuleBuilder moduleBuilder, UnionDeclaration unionDecl)
    {
        var unionType = moduleBuilder.DefineType(
            unionDecl.Name,
            GetTypeVisibilityAttributes(unionDecl.Name, unionDecl.Modifiers) | TypeAttributes.Sealed | TypeAttributes.SequentialLayout,
            typeof(ValueType));
        ApplyCustomAttributes(unionType.SetCustomAttribute, unionDecl.Attributes);
        ApplyNullableContextAttribute(unionType.SetCustomAttribute);
        ApplyIsReadOnlyAttribute(unionType.SetCustomAttribute);
        RegisterType(unionDecl.Name, unionType);

        // Integer discriminator. InitOnly is valid because it is only ever written in
        // the private tag constructor, keeping the struct a genuine readonly struct.
        var tagField = unionType.DefineField(
            "_tag",
            typeof(int),
            FieldAttributes.Private | FieldAttributes.InitOnly);
        _fields[GetFieldKey(unionType, "_tag")] = tagField;

        // Private constructor: U(int tag) { _tag = tag; }. Construction goes through the
        // per-case static factories below, never directly from call sites, so the field
        // stays encapsulated and the readonly-struct invariant holds.
        var tagCtor = unionType.DefineConstructor(
            MethodAttributes.Private | MethodAttributes.HideBySig | MethodAttributes.SpecialName | MethodAttributes.RTSpecialName,
            CallingConventions.Standard,
            new[] { typeof(int) });
        var ctorIl = tagCtor.GetILGenerator();
        ctorIl.Emit(OpCodes.Ldarg_0);
        ctorIl.Emit(OpCodes.Ldarg_1);
        ctorIl.Emit(OpCodes.Stfld, tagField);
        ctorIl.Emit(OpCodes.Ret);

        // Public Tag accessor so the discriminator is inspectable from C#.
        var tagGetter = unionType.DefineMethod(
            "get_Tag",
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
            typeof(int),
            Type.EmptyTypes);
        var tagIl = tagGetter.GetILGenerator();
        tagIl.Emit(OpCodes.Ldarg_0);
        tagIl.Emit(OpCodes.Ldfld, tagField);
        tagIl.Emit(OpCodes.Ret);
        var tagProperty = unionType.DefineProperty("Tag", PropertyAttributes.None, typeof(int), Type.EmptyTypes);
        tagProperty.SetGetMethod(tagGetter);

        var caseTags = new Dictionary<Type, int>();
        var caseFactories = new Dictionary<Type, MethodBuilder>();
        var layout = new ValueStructUnionLayout(unionType, tagField, tagCtor, tagGetter, caseTags, caseFactories);

        int tag = 0;
        foreach (var unionCase in unionDecl.Cases)
        {
            // Marker nested type, preserved for reflection/tooling parity with the
            // class-hierarchy representation. It is sealed/abstract and never instantiated.
            var caseType = unionType.DefineNestedType(
                unionCase.Name,
                VisibilityConventions.GetNestedTypeAttributes(unionCase.Name, Modifiers.None) | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.Abstract,
                typeof(object));
            ApplyNullableContextAttribute(caseType.SetCustomAttribute);

            var caseKey = $"{unionDecl.Name}.{unionCase.Name}";
            RegisterType(caseKey, caseType);

            // Public int constant exposing the tag value (e.g. Union.Case.Tag) for C# consumers.
            var caseTagConst = caseType.DefineField(
                "Tag",
                typeof(int),
                FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal);
            caseTagConst.SetConstant(tag);

            caseTags[caseType] = tag;
            _valueStructUnionCaseTypes[caseType] = layout;
            tag++;
        }

        // Per-case static factories on the union struct: `static U <Case>() => new U(tag)`.
        // Call sites invoke these with a single `call`, so no per-case object is allocated
        // in the caller. The factory name is prefixed to avoid colliding with the nested
        // marker type of the same case name.
        int factoryTag = 0;
        foreach (var unionCase in unionDecl.Cases)
        {
            var caseKey = $"{unionDecl.Name}.{unionCase.Name}";
            var caseType = _types[caseKey];

            var factory = unionType.DefineMethod(
                $"Create_{unionCase.Name}",
                MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig,
                unionType,
                Type.EmptyTypes);
            var factoryIl = factory.GetILGenerator();
            factoryIl.Emit(OpCodes.Ldc_I4, factoryTag);
            factoryIl.Emit(OpCodes.Newobj, tagCtor);
            factoryIl.Emit(OpCodes.Ret);

            caseFactories[caseType] = factory;
            factoryTag++;
        }

        _valueStructUnions[unionType] = layout;
    }

    /// <summary>Returns the value-struct layout for a union type, or null if it is not value-struct represented.</summary>
    private ValueStructUnionLayout? GetValueStructUnionLayout(Type type)
    {
        return _valueStructUnions.TryGetValue(type, out var layout) ? layout : null;
    }

    /// <summary>
    /// If <paramref name="type"/> is a value-struct union case marker, returns the owning
    /// union struct type; otherwise returns <paramref name="type"/> unchanged. A
    /// constructed value-struct union case (<c>new U.Case</c>) yields a <c>U</c> value, so
    /// its expression type must be reported as <c>U</c> — not the marker — to avoid a
    /// spurious box/unbox coercion when the value is stored or returned.
    /// </summary>
    private Type MapValueStructUnionCaseToUnion(Type type)
    {
        return _valueStructUnionCaseTypes.TryGetValue(type, out var layout) ? layout.UnionType : type;
    }

    /// <summary>Returns the owning union layout and tag for a value-struct union case marker type, or false.</summary>
    private bool TryGetValueStructUnionCase(Type caseType, out ValueStructUnionLayout layout, out int tag)
    {
        if (_valueStructUnionCaseTypes.TryGetValue(caseType, out var found))
        {
            layout = found;
            tag = found.CaseTags[caseType];
            return true;
        }

        layout = null!;
        tag = 0;
        return false;
    }

    private void EmitUnionBodies(UnionDeclaration unionDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? unionDecl.Name;
        if (!_types.TryGetValue(typeName, out var unionType))
        {
            throw new InvalidOperationException($"Union {typeName} not declared");
        }

        // Value-struct unions have no per-case bodies/constructors to emit; everything
        // is inlined at construction/match sites and the struct itself needs no body.
        if (GetValueStructUnionLayout(unionType) != null)
        {
            return;
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
            var caseKey = $"{typeName}.{unionCase.Name}";
            if (!_types.TryGetValue(caseKey, out var caseType))
            {
                throw new InvalidOperationException($"Union case {caseKey} not declared");
            }

            if (_constructors.TryGetValue(GetConstructorKey(caseType), out var defaultCaseCtor))
            {
                var il = defaultCaseCtor.GetILGenerator();
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Call, unionCtor);
                il.Emit(OpCodes.Ret);
            }

            if (_declaredConstructorOverloads.TryGetValue(GetConstructorKey(caseType), out var overloads))
            {
                foreach (var overload in overloads.Where(overload => overload.Builder != defaultCaseCtor))
                {
                    var il = overload.Builder.GetILGenerator();
                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Call, unionCtor);

                    if (unionCase.Properties != null)
                    {
                        for (int i = 0; i < unionCase.Properties.Count; i++)
                        {
                            var property = unionCase.Properties[i];
                            if (!_fields.TryGetValue(GetFieldKey(caseType, property.Name), out var fieldBuilder))
                            {
                                throw new InvalidOperationException($"Union case field {caseKey}.{property.Name} not declared");
                            }

                            il.Emit(OpCodes.Ldarg_0);
                            il.Emit(OpCodes.Ldarg, i + 1);
                            il.Emit(OpCodes.Stfld, fieldBuilder);
                        }
                    }

                    il.Emit(OpCodes.Ret);
                }
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
    private void DeclareInterfaceMembers(InterfaceDeclaration interfaceDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? interfaceDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Interface {typeName} not declared");
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

        DeclareNestedTypeMembers(interfaceDecl.Members, typeName);

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
        ApplyNullableContextAttribute(methodBuilder.SetCustomAttribute);
        if (funcDecl.ReturnType != null)
        {
            var returnParameter = methodBuilder.DefineParameter(0, ParameterAttributes.Retval, null);
            ApplyNullableAttribute(returnParameter.SetCustomAttribute, funcDecl.ReturnType, typeGenericParameters);
        }

        // Define parameter names
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(funcDecl.Parameters[i]), funcDecl.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, funcDecl.Parameters[i], typeGenericParameters);
        }

        // Store method for reference (interface methods don't have bodies)
        _methods[GetMethodKey(typeBuilder, funcDecl.Name)] = methodBuilder;
        _declaredMethodParameters[GetMethodKey(typeBuilder, funcDecl.Name)] = funcDecl.Parameters;
    }

    /// <summary>
    /// Declare class members (second pass)
    /// </summary>
    private void DeclareClassMembers(ClassDeclaration classDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? classDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = GetImplementedInterfaces(
            classDecl.Members,
            classDecl.Interfaces,
            typeGenericParameters,
            classDecl.BaseClass);

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
                    DeclareField(typeBuilder, fieldDecl, FieldOwnerKind.Class);
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

        ApplyRequiredMemberTypeAttribute(typeBuilder, classDecl.Members, FieldOwnerKind.Class);

        DeclareNestedTypeMembers(classDecl.Members, typeName);

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare struct members (second pass)
    /// </summary>
    private void DeclareStructMembers(StructDeclaration structDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? structDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = GetImplementedInterfaces(
            structDecl.Members,
            structDecl.Interfaces,
            typeGenericParameters);

        if (structDecl.PrimaryConstructorParameters != null && structDecl.PrimaryConstructorParameters.Count > 0)
        {
            DeclarePrimaryConstructorMembers(typeBuilder, structDecl.PrimaryConstructorParameters, isValueType: true);
        }

        foreach (var member in structDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl, FieldOwnerKind.Struct);
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

        ApplyRequiredMemberTypeAttribute(typeBuilder, structDecl.Members, FieldOwnerKind.Struct);

        DeclareNestedTypeMembers(structDecl.Members, typeName);

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

    private enum FieldOwnerKind
    {
        Class,
        Struct,
        Record
    }

    private readonly record struct FieldEmission(PropertyModifier PropertyModifier, bool EmitsAsAutoProperty);

    private static FieldEmission GetFieldEmission(FieldDeclaration fieldDecl, FieldOwnerKind ownerKind)
    {
        var propertyModifier = fieldDecl.PropertyModifier;
        var isExportedClassOrRecordMember = ownerKind is FieldOwnerKind.Class or FieldOwnerKind.Record
            && VisibilityConventions.IsExportedIdentifier(fieldDecl.Name, fieldDecl.Modifiers);

        if (ownerKind == FieldOwnerKind.Record && isExportedClassOrRecordMember)
        {
            propertyModifier |= PropertyModifier.Init;
            if (fieldDecl.Initializer == null)
            {
                propertyModifier |= PropertyModifier.Required;
            }
        }

        var emitsAsAutoProperty = isExportedClassOrRecordMember
            || propertyModifier.HasFlag(PropertyModifier.Required)
            || propertyModifier.HasFlag(PropertyModifier.Init);

        return new FieldEmission(propertyModifier, emitsAsAutoProperty);
    }

    private void DeclareFieldAsAutoProperty(
        TypeBuilder typeBuilder,
        FieldDeclaration fieldDecl,
        Type fieldType,
        PropertyModifier effectivePropertyModifier)
    {
        var propertyBuilder = typeBuilder.DefineProperty(
            fieldDecl.Name,
            PropertyAttributes.None,
            fieldType,
            null);
        ApplyCustomAttributes(propertyBuilder.SetCustomAttribute, fieldDecl.Attributes);
        if (fieldDecl.Type != null)
        {
            ApplyNullableAttribute(propertyBuilder.SetCustomAttribute, fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

        if (effectivePropertyModifier.HasFlag(PropertyModifier.Required))
        {
            ApplyRequiredMemberAttribute(propertyBuilder.SetCustomAttribute);
        }

        var backingFieldName = $"<{fieldDecl.Name}>k__BackingField";
        var backingField = typeBuilder.DefineField(
            backingFieldName,
            fieldType,
            FieldAttributes.Assembly | (fieldDecl.Modifiers.HasFlag(Modifiers.Static) ? FieldAttributes.Static : 0));
        if (fieldDecl.Type != null)
        {
            ApplyNullableAttribute(backingField.SetCustomAttribute, fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

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
        if (fieldDecl.Type != null)
        {
            ApplyNullableAttribute(getMethod.DefineParameter(0, ParameterAttributes.Retval, null).SetCustomAttribute, fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

        var hasInitSetter = effectivePropertyModifier.HasFlag(PropertyModifier.Init)
            || effectivePropertyModifier.HasFlag(PropertyModifier.Readonly);
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

        var valueParameter = setMethod.DefineParameter(1, ParameterAttributes.None, "value");
        if (fieldDecl.Type != null)
        {
            ApplyNullableAttribute(valueParameter.SetCustomAttribute, fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

        propertyBuilder.SetGetMethod(getMethod);
        propertyBuilder.SetSetMethod(setMethod);

        _methods[GetMethodKey(typeBuilder, $"get_{fieldDecl.Name}")] = getMethod;
        _methods[GetMethodKey(typeBuilder, $"set_{fieldDecl.Name}")] = setMethod;
        _fields[GetFieldKey(typeBuilder, fieldDecl.Name)] = backingField;
        _fields[GetFieldKey(typeBuilder, backingFieldName)] = backingField;
    }

    private void DeclareField(TypeBuilder typeBuilder, FieldDeclaration fieldDecl, FieldOwnerKind ownerKind)
    {
        var fieldType = ResolveFieldDeclarationType(fieldDecl, typeBuilder);
        var fieldEmission = GetFieldEmission(fieldDecl, ownerKind);

        if (fieldEmission.EmitsAsAutoProperty)
        {
            DeclareFieldAsAutoProperty(typeBuilder, fieldDecl, fieldType, fieldEmission.PropertyModifier);
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
        if (fieldDecl.Type != null)
        {
            ApplyNullableAttribute(fieldBuilder.SetCustomAttribute, fieldDecl.Type, GetTypeGenericParameters(typeBuilder));
        }

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
        ApplyNullableAttribute(propertyBuilder.SetCustomAttribute, propDecl.Type, GetTypeGenericParameters(typeBuilder));

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
        ApplyNullableAttribute(backingField.SetCustomAttribute, propDecl.Type, GetTypeGenericParameters(typeBuilder));

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
            ApplyNullableAttribute(getMethod.DefineParameter(0, ParameterAttributes.Retval, null).SetCustomAttribute, propDecl.Type, GetTypeGenericParameters(typeBuilder));

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

            var valueParameter = setMethod.DefineParameter(1, ParameterAttributes.None, "value");
            ApplyNullableAttribute(valueParameter.SetCustomAttribute, propDecl.Type, GetTypeGenericParameters(typeBuilder));

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
        ApplyNullableAttribute(propertyBuilder.SetCustomAttribute, indexerDecl.Type, typeGenericParameters);
        _indexers[GetIndexerKey(typeBuilder)] = propertyBuilder;

        if (indexerDecl.GetBody != null)
        {
            var getMethod = typeBuilder.DefineMethod(
                "get_Item",
                GetVisibilityMethodAttributes(indexerDecl.Modifiers) | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                propertyType,
                parameterTypes);
            ApplyNullableAttribute(getMethod.DefineParameter(0, ParameterAttributes.Retval, null).SetCustomAttribute, indexerDecl.Type, typeGenericParameters);

            for (int i = 0; i < indexerDecl.Parameters.Count; i++)
            {
                var parameterBuilder = getMethod.DefineParameter(i + 1, GetParameterAttributes(indexerDecl.Parameters[i]), indexerDecl.Parameters[i].Name);
                ApplyParameterAttributes(parameterBuilder, indexerDecl.Parameters[i], typeGenericParameters);
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
                ApplyParameterAttributes(parameterBuilder, indexerDecl.Parameters[i], typeGenericParameters);
            }
            var valueParameter = setMethod.DefineParameter(indexerDecl.Parameters.Count + 1, ParameterAttributes.None, "value");
            ApplyNullableAttribute(valueParameter.SetCustomAttribute, indexerDecl.Type, typeGenericParameters);

            propertyBuilder.SetSetMethod(setMethod);
            _methods[GetMethodKey(typeBuilder, "set_Item")] = setMethod;
        }

        var defaultMemberCtor = typeof(System.Reflection.DefaultMemberAttribute).GetConstructor(new[] { typeof(string) });
        if (defaultMemberCtor != null)
        {
            typeBuilder.SetCustomAttribute(new CustomAttributeBuilder(defaultMemberCtor, new object[] { "Item" }));
        }
    }

    private static bool HasRequiredMembers(IEnumerable<Declaration> members, FieldOwnerKind ownerKind)
    {
        return members.Any(member => member switch
        {
            FieldDeclaration fieldDecl => GetFieldEmission(fieldDecl, ownerKind).PropertyModifier.HasFlag(PropertyModifier.Required),
            PropertyDeclaration propDecl => propDecl.PropertyModifier.HasFlag(PropertyModifier.Required),
            _ => false
        });
    }

    private void ApplyRequiredMemberTypeAttribute(TypeBuilder typeBuilder, IEnumerable<Declaration> members, FieldOwnerKind ownerKind)
    {
        if (!HasRequiredMembers(members, ownerKind))
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
            ApplyNullableAttribute(fieldBuilder.SetCustomAttribute, parameter.Type, typeGenericParameters);

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
            ApplyParameterAttributes(parameterBuilder, parameters[i], typeGenericParameters);
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
            ApplyParameterAttributes(parameterBuilder, ctorDecl.Parameters[i], typeGenericParameters);
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

        var methodAttributes = GetConventionMethodVisibilityAttributes(funcDecl.Name, funcDecl.Modifiers);

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
            methodAttributes &= ~MethodAttributes.MemberAccessMask;
            methodAttributes |= MethodAttributes.Public;
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.NewSlot;
        }

        var methodBuilder = typeBuilder.DefineMethod(
            GetEmittedMethodName(funcDecl),
            methodAttributes,
            returnType,
            parameterTypes);
        ApplyCustomAttributes(methodBuilder.SetCustomAttribute, funcDecl.Attributes);
        ApplyNullableContextAttribute(methodBuilder.SetCustomAttribute);
        if (funcDecl.ReturnType != null)
        {
            var returnParameter = methodBuilder.DefineParameter(0, ParameterAttributes.Retval, null);
            ApplyNullableAttribute(returnParameter.SetCustomAttribute, funcDecl.ReturnType, typeGenericParameters);
        }

        // Define parameter names
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            var parameterBuilder = methodBuilder.DefineParameter(i + 1, GetParameterAttributes(funcDecl.Parameters[i]), funcDecl.Parameters[i].Name);
            ApplyParameterAttributes(parameterBuilder, funcDecl.Parameters[i], typeGenericParameters);
        }

        // Store method for later body emission
        _methods[GetMethodKey(typeBuilder, funcDecl.Name)] = methodBuilder;
        _declaredMethodParameters[GetMethodKey(typeBuilder, funcDecl.Name)] = funcDecl.Parameters;
        RegisterDeclaredMethodOverload(GetMethodKey(typeBuilder, funcDecl.Name), funcDecl, methodBuilder);
        DeclareAnonymousUnionParameterShims(
            typeBuilder,
            funcDecl,
            methodBuilder,
            methodAttributes,
            returnType,
            parameterTypes,
            typeGenericParameters);

        foreach (var interfaceMethod in interfaceMethods)
        {
            typeBuilder.DefineMethodOverride(methodBuilder, interfaceMethod);
        }
    }

    /// <summary>
    /// Emit class method bodies (third pass)
    /// </summary>
    private void EmitClassBodies(ClassDeclaration classDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? classDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
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
                    EmitFieldBody(typeBuilder, fieldDecl, FieldOwnerKind.Class);
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

        EmitNestedTypeBodies(classDecl.Members, typeName);

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit struct method bodies (third pass)
    /// </summary>
    private void EmitStructBodies(StructDeclaration structDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? structDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
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
                    EmitFieldBody(typeBuilder, fieldDecl, FieldOwnerKind.Struct);
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

        EmitNestedTypeBodies(structDecl.Members, typeName);

        _currentTypeBuilder = null;
    }

    private void EmitDeclaredInstanceFieldInitializers(TypeBuilder typeBuilder, IEnumerable<Declaration> members, FieldOwnerKind ownerKind)
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

            var storageKey = GetFieldEmission(fieldDecl, ownerKind).EmitsAsAutoProperty
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

    private void EmitFieldBody(TypeBuilder typeBuilder, FieldDeclaration fieldDecl, FieldOwnerKind ownerKind)
    {
        if (!GetFieldEmission(fieldDecl, ownerKind).EmitsAsAutoProperty)
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
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members, FieldOwnerKind.Class);
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
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members, isValueType ? FieldOwnerKind.Struct : FieldOwnerKind.Class);
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
        InitializeBodyContextForBody(null, ctorDecl.Body, null, ctorDecl.Parameters);
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
            EmitDeclaredInstanceFieldInitializers(typeBuilder, members, typeBuilder.BaseType == typeof(ValueType) ? FieldOwnerKind.Struct : FieldOwnerKind.Class);
        }

        // Emit constructor body
        EmitStatement(ctorDecl.Body);

        // Ensure constructor ends with a return
        _currentIL.Emit(OpCodes.Ret);

        // Clear context
        ClearMethodContext();
        _currentGenericParameters = null;
    }

    private void EmitAnonymousUnionParameterShims(FunctionDeclaration function)
    {
        if (!_anonymousUnionShimsByDeclaration.TryGetValue(function, out var shims))
            return;

        foreach (var shim in shims)
        {
            EmitAnonymousUnionParameterShim(shim);
        }
    }

    private void EmitAnonymousUnionParameterShim(AnonymousUnionShim shim)
    {
        var savedIl = _currentIL;
        var savedGenericParameters = _currentGenericParameters;

        _currentIL = shim.Builder.GetILGenerator();
        _currentGenericParameters = null;

        var targetIsStatic = shim.Target.IsStatic;
        var shimArgIndex = 0;
        if (!targetIsStatic)
        {
            _currentIL.Emit(OpCodes.Ldarg_0);
            shimArgIndex = 1;
        }

        for (var i = 0; i < shim.Declaration.Parameters.Count; i++)
        {
            _currentIL.Emit(OpCodes.Ldarg, shimArgIndex + i);

            var shimParameterType = shim.ShimParameterTypes[i];
            var originalParameterType = shim.OriginalParameterTypes[i];
            if (!AreTypeIdentitiesEquivalent(shimParameterType, originalParameterType))
            {
                EmitValueCoercion(shimParameterType, originalParameterType, allowExplicitUserDefinedConversions: false);
            }
        }

        _currentIL.Emit(OpCodes.Call, shim.Target);
        _currentIL.Emit(OpCodes.Ret);

        _currentIL = savedIl;
        _currentGenericParameters = savedGenericParameters;
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

        InitializeBodyContextForBody(bodyReturnType, funcDecl.Body, funcDecl.ExpressionBody, funcDecl.Parameters);
        InitializeStructuredReturnContext(bodyReturnType);
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
            var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
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

        // Wrap async bodies in a fault guard so a synchronously-thrown exception is surfaced as a
        // faulted task (C# async semantics), rather than escaping the method synchronously.
        var asyncFaultGuard = BeginAsyncFaultGuard();

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
                EmitAsyncReturnFromValueOnStack(asyncFaultGuard);
            }
            else
            {
                EmitExpression(funcDecl.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }
        }

        if (asyncFaultGuard)
        {
            EndAsyncFaultGuard();
        }
        // Ensure method ends with a return
        else if (_usesStructuredReturn)
        {
            EmitStructuredReturnTarget();
        }
        else if (_currentGeneratorReturnType != null)
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

    private void EmitStructuredReturnTarget()
    {
        if (_currentIL == null || _currentReturnLabel == null)
        {
            throw new InvalidOperationException("No structured return context");
        }

        _currentIL.MarkLabel(_currentReturnLabel.Value);
        if (_currentReturnLocal != null)
        {
            _currentIL.Emit(OpCodes.Ldloc, _currentReturnLocal);
        }

        _currentIL.Emit(OpCodes.Ret);
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
                var nullableLiteralUnderlyingType = Nullable.GetUnderlyingType(matchValueType);
                if (nullableLiteralUnderlyingType != null)
                {
                    var nullableLocal = _currentIL.DeclareLocal(matchValueType);
                    _currentIL.Emit(OpCodes.Stloc, nullableLocal);

                    if (literalPattern.Literal is NullLiteralExpression)
                    {
                        EmitNullableHasValue(nullableLocal);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                        break;
                    }

                    EmitNullableHasValue(nullableLocal);
                    _currentIL.Emit(OpCodes.Brfalse, failLabel);
                    EmitNullableValue(nullableLocal, nullableLiteralUnderlyingType);
                    EmitExpression(literalPattern.Literal);
                    _currentIL.Emit(OpCodes.Ceq);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                    _currentIL.Emit(OpCodes.Br, failLabel);
                    break;
                }

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
                else if (Nullable.GetUnderlyingType(matchValueType) is Type nullableIdentifierUnderlyingType
                         && !identPattern.Name.Contains('.')
                         && !TryResolvePatternType(identPattern.Name, out _))
                {
                    var nullableLocal = _currentIL.DeclareLocal(matchValueType);
                    _currentIL.Emit(OpCodes.Stloc, nullableLocal);
                    EmitNullableHasValue(nullableLocal);
                    _currentIL.Emit(OpCodes.Brfalse, failLabel);
                    EmitNullableValue(nullableLocal, nullableIdentifierUnderlyingType);
                    EmitStorePatternBinding(identPattern.Name, nullableIdentifierUnderlyingType);
                    _currentIL.Emit(OpCodes.Br, successLabel);
                }
                else if (identPattern.Name.Contains('.') && _types.TryGetValue(identPattern.Name, out var qualifiedCaseType))
                {
                    if (TryGetValueStructUnionCase(qualifiedCaseType, out var qualifiedLayout, out var qualifiedTag))
                    {
                        EmitValueStructUnionTagTest(qualifiedLayout, qualifiedTag, successLabel, failLabel);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Isinst, qualifiedCaseType);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        _currentIL.Emit(OpCodes.Br, failLabel);
                    }
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

        if (IsRuntimeUnionType(matchValueType))
        {
            var unionLocal = _currentIL.DeclareLocal(matchValueType);
            _currentIL.Emit(OpCodes.Stloc, unionLocal);

            if (bindingName == null)
            {
                _currentIL.Emit(OpCodes.Ldloca, unionLocal);
                _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(matchValueType, nameof(NSharpLang.Runtime.Union<int, string>.Is)).MakeGenericMethod(patternType));
                _currentIL.Emit(OpCodes.Brtrue, successLabel);
                _currentIL.Emit(OpCodes.Br, failLabel);
                return;
            }

            var valueLocal = _currentIL.DeclareLocal(patternType);
            _currentIL.Emit(OpCodes.Ldloca, unionLocal);
            _currentIL.Emit(OpCodes.Ldloca, valueLocal);
            _currentIL.Emit(OpCodes.Call, GetRuntimeUnionGenericMethod(matchValueType, nameof(NSharpLang.Runtime.Union<int, string>.TryGet)).MakeGenericMethod(patternType));
            _currentIL.Emit(OpCodes.Brfalse, failLabel);
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
            EmitStorePatternBinding(bindingName, patternType);
            _currentIL.Emit(OpCodes.Br, successLabel);
            return;
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

        if (TryResolveDeclaredProjectType(name, treatStringEnumAsString: false, out var declaredType))
        {
            type = declaredType;
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

        if (!TryResolveDeclaredProjectType(unionPattern.CaseName, treatStringEnumAsString: false, out var caseType))
        {
            throw new InvalidOperationException($"Union case type {unionPattern.CaseName} not declared");
        }

        // Value-struct union: compare the discriminator tag instead of using isinst.
        // Payload-free emittable unions never have pattern properties.
        if (TryGetValueStructUnionCase(caseType, out var vsLayout, out var vsTag))
        {
            EmitValueStructUnionTagTest(vsLayout, vsTag, successLabel, failLabel);
            return;
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

    /// <summary>
    /// Emit a value-struct union case test: the union value is on the stack; store it,
    /// read its discriminator tag, and branch to success when it equals the case tag.
    /// </summary>
    private void EmitValueStructUnionTagTest(ValueStructUnionLayout layout, int tag, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Read the discriminator via the public Tag accessor so the private backing
        // field stays encapsulated (and so the read is legal from any calling method).
        var unionLocal = _currentIL.DeclareLocal(layout.UnionType);
        _currentIL.Emit(OpCodes.Stloc, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca_S, unionLocal);
        _currentIL.Emit(OpCodes.Call, layout.TagGetter);
        _currentIL.Emit(OpCodes.Ldc_I4, tag);
        _currentIL.Emit(OpCodes.Beq, successLabel);
        _currentIL.Emit(OpCodes.Br, failLabel);
    }

    /// <summary>
    /// Emit a boolean `unionValue is U.Case` test for a value-struct union: evaluate the
    /// union value, read its tag via the public accessor, and compare to the case tag.
    /// Leaves a bool (1/0) on the stack.
    /// </summary>
    private void EmitValueStructUnionIsTest(Expression expression, ValueStructUnionLayout layout, int tag)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var unionLocal = _currentIL.DeclareLocal(layout.UnionType);
        EmitExpression(expression);
        _currentIL.Emit(OpCodes.Stloc, unionLocal);
        _currentIL.Emit(OpCodes.Ldloca_S, unionLocal);
        _currentIL.Emit(OpCodes.Call, layout.TagGetter);
        _currentIL.Emit(OpCodes.Ldc_I4, tag);
        _currentIL.Emit(OpCodes.Ceq);
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
            typeAttributes = GetTypeVisibilityAttributes(recordDecl.Name, recordDecl.Modifiers) | TypeAttributes.Sealed;
            baseType = typeof(ValueType);
        }
        else
        {
            // Record class: reference type, sealed by default
            typeAttributes = GetTypeVisibilityAttributes(recordDecl.Name, recordDecl.Modifiers) | TypeAttributes.Class | TypeAttributes.Sealed;
            baseType = typeof(object);
        }

        var typeBuilder = moduleBuilder.DefineType(
            recordDecl.Name,
            typeAttributes,
            baseType);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, recordDecl.Attributes);
        ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

        // A readonly value-type wrapper (e.g. a newtype, which lowers to `readonly record struct`)
        // must carry IsReadOnlyAttribute so consumers avoid defensive copies on the hot path.
        if (recordDecl.IsStruct && recordDecl.Modifiers.HasFlag(Modifiers.Readonly))
        {
            ApplyIsReadOnlyAttribute(typeBuilder.SetCustomAttribute);
        }

        RegisterType(recordDecl.Name, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, recordDecl.TypeParameters);

        if (recordDecl.Interfaces != null)
        {
            foreach (var interfaceType in recordDecl.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
            {
                TrackInterfaceImplementation(typeBuilder, interfaceType);
            }
        }

        foreach (var duckInterface in GetMatchingDuckInterfaces(recordDecl.Members))
        {
            TrackInterfaceImplementation(typeBuilder, ResolveDuckInterfaceType(duckInterface, genericParameters));
        }

        DeclareNestedTypes(typeBuilder, recordDecl.Members, recordDecl.Name);
    }

    /// <summary>
    /// Declare record members (second pass)
    /// </summary>
    private void DeclareRecordMembers(RecordDeclaration recordDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? recordDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
        }

        _currentTypeBuilder = typeBuilder;
        var typeGenericParameters = GetTypeGenericParameters(typeBuilder);
        var implementedInterfaces = GetImplementedInterfaces(
            recordDecl.Members,
            recordDecl.Interfaces,
            typeGenericParameters);

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
                ApplyNullableAttribute(backingField.SetCustomAttribute, param.Type, typeGenericParameters);

                _fields[GetFieldKey(typeBuilder, backingFieldName)] = backingField;
                _primaryConstructorFields[GetPrimaryConstructorFieldKey(typeBuilder, param.Name)] = backingField;

                // Define property
                var property = typeBuilder.DefineProperty(
                    param.Name,
                    PropertyAttributes.None,
                    fieldType,
                    null);
                ApplyNullableAttribute(property.SetCustomAttribute, param.Type, typeGenericParameters);

                // Define getter
                var getter = typeBuilder.DefineMethod(
                    $"get_{param.Name}",
                    MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                    fieldType,
                    Type.EmptyTypes);
                ApplyNullableAttribute(getter.DefineParameter(0, ParameterAttributes.Retval, null).SetCustomAttribute, param.Type, typeGenericParameters);

                _methods[GetMethodKey(typeBuilder, $"get_{param.Name}")] = getter;
                property.SetGetMethod(getter);

                var setter = typeBuilder.DefineMethod(
                    $"set_{param.Name}",
                    MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                    CallingConventions.HasThis,
                    typeof(void),
                    GetInitOnlySetterReturnRequiredCustomModifiers(),
                    null,
                    new[] { fieldType },
                    null,
                    null);
                var setterParameter = setter.DefineParameter(1, ParameterAttributes.None, "value");
                ApplyNullableAttribute(setterParameter.SetCustomAttribute, param.Type, typeGenericParameters);

                _methods[GetMethodKey(typeBuilder, $"set_{param.Name}")] = setter;
                property.SetSetMethod(setter);
            }

            // Declare primary constructor
            var paramTypes = recordDecl.PrimaryConstructorParameters
                .Select(p => ResolveType(p.Type, typeGenericParameters))
                .ToArray();

            var constructor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                paramTypes);

            for (int i = 0; i < recordDecl.PrimaryConstructorParameters.Count; i++)
            {
                var parameter = recordDecl.PrimaryConstructorParameters[i];
                var parameterBuilder = constructor.DefineParameter(i + 1, GetParameterAttributes(parameter), parameter.Name);
                ApplyParameterAttributes(parameterBuilder, parameter, typeGenericParameters);
            }

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
                    DeclareField(typeBuilder, fieldDecl, FieldOwnerKind.Record);
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

        ApplyRequiredMemberTypeAttribute(typeBuilder, recordDecl.Members, FieldOwnerKind.Record);

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

        DeclareNestedTypeMembers(recordDecl.Members, typeName);

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit record method bodies (third pass)
    /// </summary>
    private void EmitRecordBodies(RecordDeclaration recordDecl, string? declaredTypeName = null)
    {
        var typeName = declaredTypeName ?? recordDecl.Name;
        if (!_types.TryGetValue(typeName, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {typeName} not declared");
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

                var setterKey = GetMethodKey(typeBuilder, $"set_{param.Name}");
                if (_methods.TryGetValue(setterKey, out var setter))
                {
                    var il = setter.GetILGenerator();
                    var backingFieldKey = GetFieldKey(typeBuilder, $"<{param.Name}>k__BackingField");
                    if (_fields.TryGetValue(backingFieldKey, out var backingField))
                    {
                        il.Emit(OpCodes.Ldarg_0);
                        il.Emit(OpCodes.Ldarg_1);
                        il.Emit(OpCodes.Stfld, backingField);
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

                EmitDeclaredInstanceFieldInitializers(typeBuilder, recordDecl.Members, FieldOwnerKind.Record);
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

                EmitDeclaredInstanceFieldInitializers(typeBuilder, recordDecl.Members, FieldOwnerKind.Record);
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
                    EmitFieldBody(typeBuilder, fieldDecl, FieldOwnerKind.Record);
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

        EmitNestedTypeBodies(recordDecl.Members, typeName);

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
