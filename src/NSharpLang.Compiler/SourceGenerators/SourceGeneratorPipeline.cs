using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Emit;
using Microsoft.CodeAnalysis.Text;
using NSharpLang.Compiler.Ast;
using RoslynDiagnostic = Microsoft.CodeAnalysis.Diagnostic;
using RoslynDiagnosticSeverity = Microsoft.CodeAnalysis.DiagnosticSeverity;

namespace NSharpLang.Compiler.SourceGenerators;

public static class SourceGeneratorPipeline
{
    private const string LanguageName = "C#";

    public static SourceGeneratorRunResult RunForAnalysis(
        ProjectConfig config,
        string projectRoot,
        string assemblyName,
        IReadOnlyDictionary<string, string> sources,
        IEnumerable<CompilationUnit> compilationUnits)
    {
        var referenceDiagnostics = ResolveDiscoveredReferences(config, projectRoot, compilationUnits);

        return Run(
            config,
            projectRoot,
            assemblyName,
            sources,
            compilationUnits,
            SourceGeneratorRunMode.Analysis,
            outputAssemblyPath: null,
            referenceDiagnostics);
    }

    public static SourceGeneratorRunResult EmitFinalAssembly(
        ProjectConfig config,
        string projectRoot,
        string assemblyName,
        IReadOnlyDictionary<string, string> sources,
        IEnumerable<CompilationUnit> compilationUnits,
        string outputAssemblyPath)
    {
        var referenceDiagnostics = ResolveDiscoveredReferences(config, projectRoot, compilationUnits);

        return Run(
            config,
            projectRoot,
            assemblyName,
            sources,
            compilationUnits,
            SourceGeneratorRunMode.Emit,
            outputAssemblyPath,
            referenceDiagnostics);
    }

    // Reference discovery (which can build generator project references) must never crash
    // analysis/emit — convert any unexpected failure into a diagnostic (H6).
    private static IReadOnlyList<CompilerError> ResolveDiscoveredReferences(
        ProjectConfig config,
        string projectRoot,
        IEnumerable<CompilationUnit> compilationUnits)
    {
        try
        {
            return SourceGeneratorReferenceResolver.PopulateDiscoveredReferences(
                config,
                projectRoot,
                compilationUnits,
                buildProjectReferences: true);
        }
        catch (Exception ex)
        {
            return new[]
            {
                new CompilerError(
                    ErrorCode.SourceGeneratorLoadFailure,
                    $"Source generator reference discovery failed: {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error)
                {
                    DiagnosticIdOverride = "NL920",
                    HumanExplanation = "The compiler could not resolve the project's source-generator references.",
                    ContextualHint = "Reference discovery probes NuGet analyzer assets, framework reference packs, and project references; a failure there is reported instead of crashing analysis.",
                    Suggestion = "Restore packages, build referenced generator projects, or fix the project.yml references.",
                    RelatedInfo = new Dictionary<string, string> { ["exception"] = ex.ToString() }
                }
            };
        }
    }

    private static SourceGeneratorRunResult Run(
        ProjectConfig config,
        string projectRoot,
        string assemblyName,
        IReadOnlyDictionary<string, string> sources,
        IEnumerable<CompilationUnit> compilationUnits,
        SourceGeneratorRunMode mode,
        string? outputAssemblyPath,
        IReadOnlyList<CompilerError> referenceDiagnostics)
    {
        var generatorReferences = config.SourceGenerators
            .DistinctBy(reference => Path.GetFullPath(reference.Path), StringComparer.OrdinalIgnoreCase)
            .OrderBy(reference => reference.Kind)
            .ThenBy(reference => reference.Origin, StringComparer.Ordinal)
            .ThenBy(reference => reference.Path, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (generatorReferences.Length == 0)
        {
            // No generators in play. Still surface any reference-discovery diagnostics so a
            // failed generator project reference is reported rather than silently dropped.
            return referenceDiagnostics.Count == 0
                ? SourceGeneratorRunResult.Inactive
                : new SourceGeneratorRunResult(
                    true,
                    false,
                    referenceDiagnostics,
                    GeneratedSymbolIndex.Empty,
                    null,
                    Array.Empty<string>());
        }

        var diagnostics = new List<CompilerError>(referenceDiagnostics);
        var missingReferences = generatorReferences
            .Where(reference => !File.Exists(reference.Path))
            .ToArray();
        foreach (var reference in missingReferences)
        {
            diagnostics.Add(new CompilerError(
                ErrorCode.SourceGeneratorLoadFailure,
                $"Source generator '{reference.Origin}' could not be loaded because '{reference.Path}' does not exist.",
                0,
                0,
                ErrorSeverity.Error)
            {
                DiagnosticIdOverride = "NL920",
                HumanExplanation = "The compiler discovered a source generator reference, but the generator assembly was not present on disk.",
                ContextualHint = "Source generators are resolved from restored NuGet package analyzer assets, framework reference packs, or built project references.",
                Suggestion = "Restore/build the generator dependency, fix the project.yml reference, or remove the missing generator reference.",
                RelatedInfo = new Dictionary<string, string>
                {
                    ["origin"] = reference.Origin,
                    ["path"] = reference.Path,
                    ["kind"] = reference.Kind.ToString()
                }
            });
        }

        if (missingReferences.Length > 0)
        {
            return new SourceGeneratorRunResult(
                true,
                false,
                diagnostics,
                GeneratedSymbolIndex.Empty,
                null,
                Array.Empty<string>());
        }

        var outputDirectory = PrepareGeneratedSourceDirectory(projectRoot, assemblyName, mode);
        var compilation = CreateCompilation(config, assemblyName, sources, mode);
        var loadResult = LoadGenerators(generatorReferences);
        diagnostics.AddRange(loadResult.Diagnostics);
        if (loadResult.Generators.Length == 0)
        {
            return new SourceGeneratorRunResult(
                diagnostics.Count > 0,
                false,
                diagnostics,
                GeneratedSymbolIndex.Empty,
                null,
                Array.Empty<string>());
        }

        GeneratorDriver driver = CSharpGeneratorDriver.Create(
            loadResult.Generators,
            additionalTexts: Array.Empty<AdditionalText>(),
            parseOptions: ParseOptions);

        Compilation updatedCompilation;
        try
        {
            // The out-param diagnostics here are the same per-generator diagnostics surfaced by
            // ConvertGeneratorRunDiagnostics(runResult) below; adding both double-reports every
            // generator diagnostic (M7). Discard these and emit from the run result only.
            driver = driver.RunGeneratorsAndUpdateCompilation(
                compilation,
                out updatedCompilation,
                out _);
        }
        catch (Exception ex)
        {
            diagnostics.Add(new CompilerError(
                ErrorCode.SourceGeneratorFailure,
                $"Source generator execution failed: {ex.Message}",
                0,
                0,
                ErrorSeverity.Error)
            {
                DiagnosticIdOverride = "NL921",
                HumanExplanation = "A source generator threw before Roslyn could produce generated C# for this project.",
                ContextualHint = "Generator crashes are treated as compiler errors because generated members may be required by semantic analysis and final emission.",
                Suggestion = "Inspect the generator stack trace, update the generator package, or reduce the input that triggers the crash.",
                RelatedInfo = new Dictionary<string, string> { ["exception"] = ex.ToString() }
            });
            return new SourceGeneratorRunResult(true, false, diagnostics, GeneratedSymbolIndex.Empty, null, Array.Empty<string>());
        }

        var runResult = driver.GetRunResult();
        diagnostics.AddRange(ConvertGeneratorRunDiagnostics(runResult));
        var generatedSourcePaths = WriteGeneratedSources(runResult, outputDirectory);

        diagnostics.AddRange(updatedCompilation.GetDiagnostics()
            .Where(diagnostic => diagnostic.Severity == RoslynDiagnosticSeverity.Error && IsGeneratedTreeDiagnostic(runResult, diagnostic))
            .Select(diagnostic => ConvertDiagnostic(diagnostic, ErrorCode.GeneratedSourceInvalid, "NL922")));

        var generatedSymbols = BuildGeneratedSymbolIndex(
            updatedCompilation,
            EnumerateDeclaredTypeFullNames(compilationUnits));

        string? analysisAssemblyPath = null;
        if (mode == SourceGeneratorRunMode.Analysis
            && !diagnostics.Any(diagnostic => diagnostic.Severity == ErrorSeverity.Error))
        {
            analysisAssemblyPath = Path.Combine(outputDirectory, $"{SanitizePathSegment(assemblyName)}.SourceGenerators.dll");
            diagnostics.AddRange(EmitCompilation(updatedCompilation, analysisAssemblyPath, ErrorCode.GeneratedSourceInvalid, "NL922"));
            if (diagnostics.Any(diagnostic => diagnostic.Severity == ErrorSeverity.Error))
            {
                analysisAssemblyPath = null;
            }
        }

        if (mode == SourceGeneratorRunMode.Emit && outputAssemblyPath != null)
        {
            diagnostics.AddRange(EmitCompilation(updatedCompilation, outputAssemblyPath, ErrorCode.GeneratedSourceInvalid, "NL922"));
        }

        return new SourceGeneratorRunResult(
            true,
            true,
            diagnostics,
            generatedSymbols,
            analysisAssemblyPath,
            generatedSourcePaths);
    }

    // One shared loader for the process. It caches an AssemblyLoadContext per (path, mtime,
    // length), so repeated runs reuse the same context instead of leaking a new non-collectible
    // ALC per analysis/emit run (H7). Generator INSTANCES are still created fresh per run below,
    // so concurrent compilations never share mutable generator state (Roslyn's own pattern).
    private static readonly SourceGeneratorAssemblyLoader SharedAssemblyLoader = new();

    private static SourceGeneratorLoadResult LoadGenerators(IReadOnlyList<SourceGeneratorReference> references)
    {
        var diagnostics = new List<CompilerError>();
        var generators = ImmutableArray.CreateBuilder<ISourceGenerator>();

        foreach (var reference in references)
        {
            try
            {
                // A fresh AnalyzerFileReference yields fresh generator instances each run; the
                // shared loader still reuses the underlying ALC for an unchanged generator
                // assembly (no per-run leak, no cross-run shared generator state).
                var analyzerReference = new AnalyzerFileReference(reference.Path, SharedAssemblyLoader);
                var loadedGenerators = analyzerReference.GetGenerators(LanguageName);
                foreach (var generator in loadedGenerators)
                {
                    generators.Add(generator);
                }
            }
            catch (Exception ex)
            {
                diagnostics.Add(new CompilerError(
                    ErrorCode.SourceGeneratorLoadFailure,
                    $"Source generator '{reference.Origin}' could not be loaded from '{reference.Path}': {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error)
                {
                    DiagnosticIdOverride = "NL920",
                    HumanExplanation = "Roslyn could not load the source generator assembly or one of its dependencies.",
                    ContextualHint = "Generator assemblies must be managed .NET assemblies compatible with the current compiler host.",
                    Suggestion = "Restore the generator package/project and make sure its dependencies are present next to the generator assembly.",
                    RelatedInfo = new Dictionary<string, string>
                    {
                        ["origin"] = reference.Origin,
                        ["path"] = reference.Path,
                        ["kind"] = reference.Kind.ToString(),
                        ["exception"] = ex.ToString()
                    }
                });
            }
        }

        return new SourceGeneratorLoadResult(generators.ToImmutable(), diagnostics);
    }

    private static CSharpCompilation CreateCompilation(
        ProjectConfig config,
        string assemblyName,
        IReadOnlyDictionary<string, string> sources,
        SourceGeneratorRunMode mode)
    {
        var syntaxTrees = sources
            .OrderBy(source => source.Key, StringComparer.OrdinalIgnoreCase)
            .Select(source => CSharpSyntaxTree.ParseText(
                SourceText.From(source.Value, Encoding.UTF8),
                ParseOptions,
                path: source.Key))
            .ToList();

        var assemblyInfo = CreateAssemblyInfoSource(config);
        if (!string.IsNullOrWhiteSpace(assemblyInfo))
        {
            syntaxTrees.Add(CSharpSyntaxTree.ParseText(
                SourceText.From(assemblyInfo, Encoding.UTF8),
                ParseOptions,
                path: $"{assemblyName}.NSharpAssemblyInfo.g.cs"));
        }

        return CSharpCompilation.Create(
            assemblyName,
            syntaxTrees,
            CreateMetadataReferences(config),
            new CSharpCompilationOptions(
                string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase)
                    ? OutputKind.ConsoleApplication
                    : OutputKind.DynamicallyLinkedLibrary,
                nullableContextOptions: NullableContextOptions.Enable,
                optimizationLevel: mode == SourceGeneratorRunMode.Emit ? OptimizationLevel.Release : OptimizationLevel.Debug,
                allowUnsafe: true,
                deterministic: true));
    }

    private static string? CreateAssemblyInfoSource(ProjectConfig config)
    {
        if (string.IsNullOrWhiteSpace(config.Version)
            || !Version.TryParse(config.Version, out var configuredVersion))
        {
            return null;
        }

        var assemblyVersion = NormalizeAssemblyVersion(configuredVersion).ToString();
        var informationalVersion = EscapeStringLiteral(config.Version);
        return $$"""
[assembly: System.Reflection.AssemblyVersion("{{assemblyVersion}}")]
[assembly: System.Reflection.AssemblyFileVersion("{{assemblyVersion}}")]
[assembly: System.Reflection.AssemblyInformationalVersion("{{informationalVersion}}")]
""";
    }

    private static Version NormalizeAssemblyVersion(Version version)
    {
        return new Version(
            version.Major >= 0 ? version.Major : 1,
            version.Minor >= 0 ? version.Minor : 0,
            version.Build >= 0 ? version.Build : 0,
            version.Revision >= 0 ? version.Revision : 0);
    }

    private static string EscapeStringLiteral(string value)
        => value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal);

    private static IReadOnlyList<MetadataReference> CreateMetadataReferences(ProjectConfig config)
    {
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES") is string trustedPlatformAssemblies)
        {
            foreach (var path in trustedPlatformAssemblies.Split(Path.PathSeparator))
            {
                if (File.Exists(path))
                {
                    paths.Add(Path.GetFullPath(path));
                }
            }
        }

        foreach (var dependency in config.Dependencies.Where(reference => reference.Type == ReferenceType.Dll))
        {
            if (!string.IsNullOrWhiteSpace(dependency.Dll) && File.Exists(dependency.Dll))
            {
                paths.Add(Path.GetFullPath(dependency.Dll));
            }
        }

        var runtimeAssembly = typeof(NSharpLang.Runtime.Result<,>).Assembly.Location;
        if (!string.IsNullOrWhiteSpace(runtimeAssembly) && File.Exists(runtimeAssembly))
        {
            paths.Add(Path.GetFullPath(runtimeAssembly));
        }

        return paths
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .Select(path => MetadataReference.CreateFromFile(path))
            .ToArray();
    }

    private static IReadOnlyList<CompilerError> EmitCompilation(
        Compilation compilation,
        string outputAssemblyPath,
        ErrorCode code,
        string diagnosticId)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(outputAssemblyPath) ?? Environment.CurrentDirectory);
        using var stream = File.Create(outputAssemblyPath);
        var emitResult = compilation.Emit(stream, options: new EmitOptions(debugInformationFormat: DebugInformationFormat.Embedded));
        return emitResult.Success
            ? Array.Empty<CompilerError>()
            : emitResult.Diagnostics
                .Where(diagnostic => diagnostic.Severity is RoslynDiagnosticSeverity.Error or RoslynDiagnosticSeverity.Warning)
                .Select(diagnostic => ConvertDiagnostic(diagnostic, code, diagnosticId))
                .ToArray();
    }

    private static IReadOnlyList<CompilerError> ConvertGeneratorRunDiagnostics(GeneratorDriverRunResult runResult)
    {
        var diagnostics = new List<CompilerError>();
        foreach (var result in runResult.Results)
        {
            foreach (var diagnostic in result.Diagnostics)
            {
                diagnostics.Add(ConvertDiagnostic(diagnostic, ErrorCode.SourceGeneratorFailure, "NL921"));
            }

            if (result.Exception != null)
            {
                var generatorName = result.Generator.GetType().FullName ?? result.Generator.GetType().Name;
                diagnostics.Add(new CompilerError(
                    ErrorCode.SourceGeneratorFailure,
                    $"Source generator '{generatorName}' crashed: {result.Exception.Message}",
                    0,
                    0,
                    ErrorSeverity.Error)
                {
                    DiagnosticIdOverride = "NL921",
                    HumanExplanation = "The generator threw while producing C# for this N# project.",
                    ContextualHint = "The compiler stops because generated members may be required for semantic analysis or final assembly emission.",
                    Suggestion = "Inspect the generator exception, update the generator dependency, or isolate the source input that triggers the crash.",
                    RelatedInfo = new Dictionary<string, string>
                    {
                        ["generator"] = generatorName,
                        ["exception"] = result.Exception.ToString()
                    }
                });
            }
        }

        return diagnostics;
    }

    private static bool IsGeneratedTreeDiagnostic(GeneratorDriverRunResult runResult, RoslynDiagnostic diagnostic)
    {
        if (!diagnostic.Location.IsInSource)
        {
            return true;
        }

        var tree = diagnostic.Location.SourceTree;
        return tree != null && runResult.GeneratedTrees.Contains(tree);
    }

    private static CompilerError ConvertDiagnostic(RoslynDiagnostic diagnostic, ErrorCode code, string diagnosticId)
    {
        var severity = diagnostic.Severity == RoslynDiagnosticSeverity.Error
            ? ErrorSeverity.Error
            : ErrorSeverity.Warning;
        var lineSpan = diagnostic.Location.IsInSource
            ? diagnostic.Location.GetLineSpan()
            : default;
        var line = diagnostic.Location.IsInSource ? lineSpan.StartLinePosition.Line + 1 : 0;
        var column = diagnostic.Location.IsInSource ? lineSpan.StartLinePosition.Character + 1 : 0;
        var length = diagnostic.Location.IsInSource
            ? Math.Max(1, lineSpan.EndLinePosition.Character - lineSpan.StartLinePosition.Character)
            : 1;

        return new CompilerError(
            code,
            diagnostic.GetMessage(),
            line,
            column,
            severity)
        {
            DiagnosticIdOverride = diagnosticId,
            FileName = diagnostic.Location.IsInSource ? lineSpan.Path : null,
            Length = length,
            SourceSnippet = TryGetSourceSnippet(diagnostic),
            HumanExplanation = code switch
            {
                ErrorCode.SourceGeneratorFailure => "A source generator reported a diagnostic while processing the generated-source input model.",
                ErrorCode.GeneratedSourceInvalid => "Generated C# did not compile cleanly, so the compiler cannot safely merge generated symbols into N#.",
                _ => null
            },
            ContextualHint = diagnostic.Id.StartsWith("CS", StringComparison.Ordinal)
                ? $"Roslyn diagnostic {diagnostic.Id} came from generated or generator-input C#."
                : $"Generator diagnostic {diagnostic.Id} was reported by Roslyn.",
            RelatedInfo = new Dictionary<string, string>
            {
                ["roslynDiagnosticId"] = diagnostic.Id,
                ["severity"] = diagnostic.Severity.ToString()
            }
        };
    }

    private static string? TryGetSourceSnippet(RoslynDiagnostic diagnostic)
    {
        if (!diagnostic.Location.IsInSource || diagnostic.Location.SourceTree == null)
        {
            return null;
        }

        try
        {
            var text = diagnostic.Location.SourceTree.GetText();
            var line = diagnostic.Location.GetLineSpan().StartLinePosition.Line;
            return line >= 0 && line < text.Lines.Count
                ? text.Lines[line].ToString()
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static IReadOnlyList<string> WriteGeneratedSources(
        GeneratorDriverRunResult runResult,
        string outputDirectory)
    {
        var paths = new List<string>();
        foreach (var result in runResult.Results.OrderBy(
                     result => result.Generator.GetType().FullName,
                     StringComparer.Ordinal))
        {
            var generatorName = result.Generator.GetType().FullName ?? result.Generator.GetType().Name;
            var generatorDirectory = Path.Combine(outputDirectory, SanitizePathSegment(generatorName));
            Directory.CreateDirectory(generatorDirectory);

            foreach (var source in result.GeneratedSources.OrderBy(source => source.HintName, StringComparer.Ordinal))
            {
                var fileName = SanitizeHintName(source.HintName);
                if (!fileName.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
                {
                    fileName += ".cs";
                }

                var path = Path.Combine(generatorDirectory, fileName);
                File.WriteAllText(path, source.SourceText.ToString(), Encoding.UTF8);
                paths.Add(path);
            }
        }

        return paths
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string PrepareGeneratedSourceDirectory(
        string projectRoot,
        string assemblyName,
        SourceGeneratorRunMode mode)
    {
        var directory = Path.Combine(
            projectRoot,
            "obj",
            "nsharp",
            "generated",
            SanitizePathSegment(assemblyName),
            mode == SourceGeneratorRunMode.Analysis ? "analysis" : "emit");

        if (Directory.Exists(directory))
        {
            Directory.Delete(directory, recursive: true);
        }

        Directory.CreateDirectory(directory);
        return directory;
    }

    private static GeneratedSymbolIndex BuildGeneratedSymbolIndex(
        Compilation compilation,
        IEnumerable<string> declaredTypeFullNames)
    {
        var generatedTypes = new List<GeneratedTypeSymbols>();
        foreach (var fullName in declaredTypeFullNames.Distinct(StringComparer.Ordinal))
        {
            var type = compilation.GetTypeByMetadataName(fullName);
            if (type == null)
            {
                continue;
            }

            var members = type.GetMembers()
                .Where(member => !member.IsImplicitlyDeclared)
                .Select(ToGeneratedMember)
                .Where(member => member != null)
                .Cast<GeneratedMemberSymbol>()
                .ToArray();

            if (members.Length > 0)
            {
                generatedTypes.Add(new GeneratedTypeSymbols(fullName, type.Name, members));
            }
        }

        return generatedTypes.Count == 0
            ? GeneratedSymbolIndex.Empty
            : new GeneratedSymbolIndex(generatedTypes);
    }

    private static GeneratedMemberSymbol? ToGeneratedMember(ISymbol symbol)
    {
        return symbol switch
        {
            IPropertySymbol property => new GeneratedMemberSymbol(
                property.Name,
                GeneratedMemberKind.Property,
                ConvertTypeSymbol(property.Type),
                property.IsStatic,
                property.ContainingType?.ToDisplayString(MetadataNameFormat)),
            IFieldSymbol field when !field.IsImplicitlyDeclared => new GeneratedMemberSymbol(
                field.Name,
                GeneratedMemberKind.Field,
                ConvertTypeSymbol(field.Type),
                field.IsStatic,
                field.ContainingType?.ToDisplayString(MetadataNameFormat)),
            IMethodSymbol method when method.MethodKind == MethodKind.Ordinary => new GeneratedMemberSymbol(
                method.Name,
                GeneratedMemberKind.Method,
                new FunctionTypeInfo(null)
                {
                    ReturnType = ConvertTypeSymbol(method.ReturnType),
                    ParameterTypes = method.Parameters.Select(parameter => ConvertTypeSymbol(parameter.Type)).ToList()
                },
                method.IsStatic,
                method.ContainingType?.ToDisplayString(MetadataNameFormat)),
            INamedTypeSymbol nested when nested.ContainingType != null => new GeneratedMemberSymbol(
                nested.Name,
                GeneratedMemberKind.NestedType,
                new ExternalTypeInfo(nested.ToDisplayString(MetadataNameFormat)),
                IsStatic: true,
                nested.ContainingType.ToDisplayString(MetadataNameFormat)),
            _ => null
        };
    }

    private static TypeInfo ConvertTypeSymbol(ITypeSymbol? symbol)
    {
        if (symbol == null)
        {
            return BuiltInTypes.Unknown;
        }

        return symbol.SpecialType switch
        {
            SpecialType.System_Int32 => BuiltInTypes.Int,
            SpecialType.System_Int64 => BuiltInTypes.Long,
            SpecialType.System_Single => BuiltInTypes.Float,
            SpecialType.System_Double => BuiltInTypes.Double,
            SpecialType.System_Decimal => BuiltInTypes.Decimal,
            SpecialType.System_Byte => BuiltInTypes.Byte,
            SpecialType.System_SByte => BuiltInTypes.SByte,
            SpecialType.System_Int16 => BuiltInTypes.Short,
            SpecialType.System_UInt16 => BuiltInTypes.UShort,
            SpecialType.System_UInt32 => BuiltInTypes.UInt,
            SpecialType.System_UInt64 => BuiltInTypes.ULong,
            SpecialType.System_Char => BuiltInTypes.Char,
            SpecialType.System_Boolean => BuiltInTypes.Bool,
            SpecialType.System_String => BuiltInTypes.String,
            SpecialType.System_Void => BuiltInTypes.Void,
            SpecialType.System_Object => BuiltInTypes.Object,
            _ => ConvertNonSpecialTypeSymbol(symbol)
        };
    }

    private static TypeInfo ConvertNonSpecialTypeSymbol(ITypeSymbol symbol)
    {
        if (symbol is IArrayTypeSymbol array)
        {
            return new ArrayTypeInfo(ConvertTypeSymbol(array.ElementType));
        }

        if (symbol is INamedTypeSymbol { IsGenericType: true } generic)
        {
            var name = generic.ConstructedFrom.ToDisplayString(MetadataNameFormat);
            var tickIndex = name.IndexOf('`');
            if (tickIndex >= 0)
            {
                name = name[..tickIndex];
            }

            return new GenericTypeInfo(
                name,
                generic.TypeArguments.Select(ConvertTypeSymbol).ToList());
        }

        return new ExternalTypeInfo(symbol.ToDisplayString(MetadataNameFormat));
    }

    private static IEnumerable<string> EnumerateDeclaredTypeFullNames(IEnumerable<CompilationUnit> compilationUnits)
    {
        foreach (var unit in compilationUnits)
        {
            var ns = unit.Package?.Name ?? unit.Namespace?.Name;
            foreach (var declaration in unit.Declarations)
            {
                foreach (var fullName in EnumerateDeclaredTypeFullNames(declaration, ns, containingMetadataName: null))
                {
                    yield return fullName;
                }
            }
        }
    }

    private static IEnumerable<string> EnumerateDeclaredTypeFullNames(
        Declaration declaration,
        string? namespaceName,
        string? containingMetadataName)
    {
        var name = declaration switch
        {
            ClassDeclaration classDeclaration => classDeclaration.Name,
            StructDeclaration structDeclaration => structDeclaration.Name,
            RecordDeclaration recordDeclaration => recordDeclaration.Name,
            InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Name,
            EnumDeclaration enumDeclaration => enumDeclaration.Name,
            UnionDeclaration unionDeclaration => unionDeclaration.Name,
            _ => null
        };

        if (name == null)
        {
            yield break;
        }

        var metadataName = containingMetadataName == null
            ? string.IsNullOrWhiteSpace(namespaceName) ? name : $"{namespaceName}.{name}"
            : $"{containingMetadataName}+{name}";
        yield return metadataName;

        IEnumerable<Declaration> members = declaration switch
        {
            ClassDeclaration classDeclaration => classDeclaration.Members,
            StructDeclaration structDeclaration => structDeclaration.Members,
            RecordDeclaration recordDeclaration => recordDeclaration.Members,
            InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Members,
            _ => Array.Empty<Declaration>()
        };

        foreach (var member in members)
        {
            foreach (var nestedName in EnumerateDeclaredTypeFullNames(member, namespaceName, metadataName))
            {
                yield return nestedName;
            }
        }
    }

    private static string SanitizeHintName(string hintName)
    {
        var segments = hintName
            .Replace('\\', '/')
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(SanitizePathSegment)
            .ToArray();
        return segments.Length == 0 ? "generated.g.cs" : string.Join("__", segments);
    }

    private static string SanitizePathSegment(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var builder = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            builder.Append(invalid.Contains(character) || character is '<' or '>' or ':' or '"' or '/' or '\\' or '|' or '?' or '*'
                ? '_'
                : character);
        }

        return builder.Length == 0 ? "_" : builder.ToString();
    }

    private static readonly CSharpParseOptions ParseOptions =
        CSharpParseOptions.Default
            .WithLanguageVersion(LanguageVersion.Preview)
            .WithDocumentationMode(DocumentationMode.Parse);

    private static readonly SymbolDisplayFormat MetadataNameFormat =
        SymbolDisplayFormat.FullyQualifiedFormat
            .WithGlobalNamespaceStyle(SymbolDisplayGlobalNamespaceStyle.Omitted)
            .WithGenericsOptions(SymbolDisplayGenericsOptions.IncludeTypeParameters);

    private enum SourceGeneratorRunMode
    {
        Analysis,
        Emit
    }

    private sealed record SourceGeneratorLoadResult(
        ImmutableArray<ISourceGenerator> Generators,
        IReadOnlyList<CompilerError> Diagnostics);

    private sealed class SourceGeneratorAssemblyLoader : IAnalyzerAssemblyLoader
    {
        // Concurrent: GeneratorLoadContext.Load reads this while other threads may be adding
        // dependency locations for a different generator load.
        private readonly ConcurrentDictionary<string, string> _dependencyLocations = new(StringComparer.OrdinalIgnoreCase);

        // (path|mtime|length) -> ALC. One context per generator-assembly version, reused across
        // runs so we don't leak a non-collectible ALC per run (H7). A changed assembly gets a new
        // key (and a new context); the superseded one is bounded by the number of versions seen.
        private readonly object _contextGate = new();
        private readonly Dictionary<string, GeneratorLoadContext> _contexts = new(StringComparer.Ordinal);

        public void AddDependencyLocation(string fullPath)
        {
            if (string.IsNullOrWhiteSpace(fullPath) || !File.Exists(fullPath))
            {
                return;
            }

            try
            {
                var assemblyName = AssemblyName.GetAssemblyName(fullPath).Name;
                if (!string.IsNullOrWhiteSpace(assemblyName))
                {
                    _dependencyLocations[assemblyName] = Path.GetFullPath(fullPath);
                }
            }
            catch
            {
                // Ignore native or otherwise non-managed dependency paths.
            }
        }

        public Assembly LoadFromPath(string fullPath)
        {
            fullPath = Path.GetFullPath(fullPath);
            AddDependencyLocation(fullPath);

            var directory = Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrWhiteSpace(directory) && Directory.Exists(directory))
            {
                foreach (var dependency in Directory.GetFiles(directory, "*.dll", SearchOption.TopDirectoryOnly))
                {
                    AddDependencyLocation(dependency);
                }
            }

            var contextKey = BuildContextKey(fullPath);
            GeneratorLoadContext context;
            lock (_contextGate)
            {
                if (!_contexts.TryGetValue(contextKey, out context!))
                {
                    context = new GeneratorLoadContext(fullPath, _dependencyLocations);
                    _contexts[contextKey] = context;
                }
            }

            return context.LoadFromAssemblyPath(fullPath);
        }

        private static string BuildContextKey(string fullPath)
        {
            try
            {
                var info = new FileInfo(fullPath);
                return $"{fullPath}|{info.LastWriteTimeUtc.Ticks}|{info.Length}";
            }
            catch
            {
                return fullPath;
            }
        }
    }

    public const string GeneratorLoadContextName = "NSharpGeneratorLoadContext";

    private sealed class GeneratorLoadContext(
        string mainAssemblyPath,
        IReadOnlyDictionary<string, string> dependencyLocations) : AssemblyLoadContext(GeneratorLoadContextName, isCollectible: false)
    {
        private readonly AssemblyDependencyResolver _resolver = new(mainAssemblyPath);

        protected override Assembly? Load(AssemblyName assemblyName)
        {
            if (IsSharedCompilerAssembly(assemblyName.Name))
            {
                try
                {
                    return Assembly.Load(assemblyName);
                }
                catch
                {
                    return null;
                }
            }

            if (!string.IsNullOrWhiteSpace(assemblyName.Name)
                && dependencyLocations.TryGetValue(assemblyName.Name, out var dependencyPath)
                && File.Exists(dependencyPath))
            {
                return LoadFromAssemblyPath(dependencyPath);
            }

            var resolvedPath = _resolver.ResolveAssemblyToPath(assemblyName);
            return resolvedPath != null ? LoadFromAssemblyPath(resolvedPath) : null;
        }

        private static bool IsSharedCompilerAssembly(string? name)
            => name is "Microsoft.CodeAnalysis"
                or "Microsoft.CodeAnalysis.CSharp"
                or "System.Collections.Immutable"
                or "System.Reflection.Metadata";
    }
}

public sealed record SourceGeneratorRunResult(
    bool IsActive,
    bool HasLoadedGenerators,
    IReadOnlyList<CompilerError> Diagnostics,
    GeneratedSymbolIndex GeneratedSymbols,
    string? AnalysisAssemblyPath,
    IReadOnlyList<string> GeneratedSourcePaths)
{
    public static SourceGeneratorRunResult Inactive { get; } = new(
        false,
        false,
        Array.Empty<CompilerError>(),
        GeneratedSymbolIndex.Empty,
        null,
        Array.Empty<string>());
}
