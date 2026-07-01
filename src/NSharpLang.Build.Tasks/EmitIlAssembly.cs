using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using Mono.Cecil;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

public class EmitIlAssembly : Task
{
    [Required]
    public ITaskItem[] Sources { get; set; } = Array.Empty<ITaskItem>();

    public ITaskItem[] References { get; set; } = Array.Empty<ITaskItem>();

    [Required]
    public string ProjectRoot { get; set; } = string.Empty;

    public string? ProjectFile { get; set; }

    [Required]
    public string TargetAssemblyPath { get; set; } = string.Empty;

    public string? TargetReferenceAssemblyPath { get; set; }

    public string? AssemblyVersion { get; set; }

    /// <summary>
    /// Build configuration ("Debug"/"Release"); drives whether <c>DEBUG</c> is defined
    /// for conditional compilation, matching the <c>nlc</c> CLI.
    /// </summary>
    public string? Configuration { get; set; }

    /// <summary>
    /// Semicolon/comma-separated conditional-compilation symbols from MSBuild
    /// (<c>$(DefineConstants)</c>), folded into the project's defined symbols.
    /// </summary>
    public string? DefineConstants { get; set; }

    public bool ValidateWithLegacyAnalysis { get; set; } = true;

    public override bool Execute()
    {
        try
        {
            var sourceFiles = Sources
                .Select(source => source.ItemSpec)
                .ToArray();

            var config = ProjectFileParser.Parse(ProjectFile!);
            if (string.IsNullOrWhiteSpace(config.Version) && !string.IsNullOrWhiteSpace(AssemblyVersion))
            {
                config.Version = AssemblyVersion;
            }

            ApplyEffectiveDefines(config);

            AddResolvedDllReferences(config, TargetAssemblyPath, TargetReferenceAssemblyPath);

            var compiler = new MultiFileCompiler(sourceFiles, ProjectRoot, config);
            var result = compiler.CompileToIlAssembly(
                config.EffectiveName,
                TargetAssemblyPath,
                validateWithLegacyAnalysis: ValidateWithLegacyAnalysis);

            foreach (var error in result.Errors)
            {
                LogCompilerDiagnostic(error);
            }

            if (!result.Success)
            {
                return false;
            }

            SynchronizeReferenceAssembly(TargetAssemblyPath, TargetReferenceAssemblyPath, References);
            Log.LogMessage(MessageImportance.High, $"Emitted N# IL assembly to {TargetAssemblyPath}");
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    /// <summary>
    /// Folds build-configuration and MSBuild <c>DefineConstants</c> symbols into the
    /// project's defined symbols so <c>dotnet build</c> resolves <c>#if</c> identically to
    /// <c>nlc</c>: <c>DEBUG</c> is defined for any non-Release configuration.
    /// </summary>
    private void ApplyEffectiveDefines(ProjectConfig config)
    {
        var isRelease = string.Equals(Configuration, "Release", StringComparison.OrdinalIgnoreCase);
        if (!isRelease && !config.Defines.Contains("DEBUG"))
        {
            config.Defines.Add("DEBUG");
        }

        if (string.IsNullOrWhiteSpace(DefineConstants))
        {
            return;
        }

        foreach (var symbol in DefineConstants.Split(new[] { ';', ',' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = symbol.Trim();
            if (trimmed.Length > 0 && !config.Defines.Contains(trimmed))
            {
                config.Defines.Add(trimmed);
            }
        }
    }

    private static void SynchronizeReferenceAssembly(string targetAssemblyPath, string? targetReferenceAssemblyPath, ITaskItem[] references)
    {
        if (string.IsNullOrWhiteSpace(targetReferenceAssemblyPath) || !File.Exists(targetAssemblyPath))
        {
            return;
        }

        var assemblyPath = Path.GetFullPath(targetAssemblyPath);
        var referenceAssemblyPath = Path.GetFullPath(targetReferenceAssemblyPath);
        if (string.Equals(assemblyPath, referenceAssemblyPath, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var referenceAssemblyDirectory = Path.GetDirectoryName(referenceAssemblyPath);
        if (!string.IsNullOrEmpty(referenceAssemblyDirectory))
        {
            Directory.CreateDirectory(referenceAssemblyDirectory);
        }

        var referenceTypeOwners = BuildReferenceTypeOwnerMap(references, assemblyPath, referenceAssemblyPath);
        if (referenceTypeOwners.Count == 0)
        {
            File.Copy(assemblyPath, referenceAssemblyPath, overwrite: true);
            return;
        }

        var readerParameters = new ReaderParameters
        {
            ReadingMode = ReadingMode.Immediate,
            InMemory = true,
        };
        using var assembly = AssemblyDefinition.ReadAssembly(assemblyPath, readerParameters);
        var module = assembly.MainModule;
        foreach (var typeReference in module.GetTypeReferences().ToArray())
        {
            if (typeReference.Scope is not AssemblyNameReference scope
                || !string.Equals(scope.Name, "System.Private.CoreLib", StringComparison.Ordinal)
                || !referenceTypeOwners.TryGetValue(typeReference.FullName, out var owner))
            {
                continue;
            }

            typeReference.Scope = GetOrAddAssemblyReference(module, owner);
        }

        RemoveUnusedCoreLibAssemblyReference(module);
        assembly.Write(referenceAssemblyPath);
    }

    private static Dictionary<string, AssemblyNameDefinition> BuildReferenceTypeOwnerMap(
        ITaskItem[] references,
        string targetAssemblyPath,
        string targetReferenceAssemblyPath)
    {
        var excludedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            Path.GetFullPath(targetAssemblyPath),
            Path.GetFullPath(targetReferenceAssemblyPath),
        };

        var referencePaths = references
            .Select(reference => reference.ItemSpec)
            .Where(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path))
            .Select(Path.GetFullPath)
            .Where(path => !excludedPaths.Contains(path))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var typeDefinitions = new Dictionary<string, AssemblyNameDefinition>(StringComparer.Ordinal);
        var exportedTypes = new Dictionary<string, AssemblyNameDefinition>(StringComparer.Ordinal);

        foreach (var path in referencePaths)
        {
            AssemblyDefinition? referenceAssembly = null;
            try
            {
                referenceAssembly = AssemblyDefinition.ReadAssembly(path, new ReaderParameters { ReadingMode = ReadingMode.Deferred });
                foreach (var type in referenceAssembly.MainModule.Types)
                {
                    AddTypeDefinitionOwners(typeDefinitions, referenceAssembly.Name, type);
                }

                foreach (var exportedType in referenceAssembly.MainModule.ExportedTypes)
                {
                    exportedTypes.TryAdd(exportedType.FullName, referenceAssembly.Name);
                }
            }
            catch (BadImageFormatException)
            {
            }
            catch (IOException)
            {
            }
            finally
            {
                referenceAssembly?.Dispose();
            }
        }

        foreach (var exportedType in exportedTypes)
        {
            typeDefinitions.TryAdd(exportedType.Key, exportedType.Value);
        }

        return typeDefinitions;
    }

    private static void AddTypeDefinitionOwners(
        Dictionary<string, AssemblyNameDefinition> typeOwners,
        AssemblyNameDefinition assemblyName,
        TypeDefinition type)
    {
        if (type.Name != "<Module>")
        {
            typeOwners.TryAdd(type.FullName, assemblyName);
        }

        foreach (var nestedType in type.NestedTypes)
        {
            AddTypeDefinitionOwners(typeOwners, assemblyName, nestedType);
        }
    }

    private static AssemblyNameReference GetOrAddAssemblyReference(ModuleDefinition module, AssemblyNameDefinition owner)
    {
        var existing = module.AssemblyReferences.FirstOrDefault(reference =>
            string.Equals(reference.Name, owner.Name, StringComparison.Ordinal)
            && reference.Version == owner.Version);
        if (existing != null)
        {
            return existing;
        }

        var assemblyReference = new AssemblyNameReference(owner.Name, owner.Version)
        {
            Culture = owner.Culture,
            PublicKeyToken = owner.PublicKeyToken,
        };
        module.AssemblyReferences.Add(assemblyReference);
        return assemblyReference;
    }

    private static void RemoveUnusedCoreLibAssemblyReference(ModuleDefinition module)
    {
        var hasCoreLibTypeReference = module.GetTypeReferences().Any(typeReference =>
            typeReference.Scope is AssemblyNameReference scope
            && string.Equals(scope.Name, "System.Private.CoreLib", StringComparison.Ordinal));
        if (hasCoreLibTypeReference)
        {
            return;
        }

        foreach (var reference in module.AssemblyReferences
                     .Where(reference => string.Equals(reference.Name, "System.Private.CoreLib", StringComparison.Ordinal))
                     .ToArray())
        {
            module.AssemblyReferences.Remove(reference);
        }
    }

    private void LogCompilerDiagnostic(CompilerError error)
    {
        var diagnosticId = GetDiagnosticId(error);
        if (error.Severity == ErrorSeverity.Error)
        {
            Log.LogError(
                subcategory: null,
                errorCode: diagnosticId,
                helpKeyword: null,
                file: error.FileName ?? string.Empty,
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                message: error.FormatForMsBuild());
        }
        else if (error.Severity == ErrorSeverity.Warning)
        {
            Log.LogWarning(
                subcategory: null,
                warningCode: diagnosticId,
                helpKeyword: null,
                file: error.FileName ?? string.Empty,
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                message: error.FormatForMsBuild());
        }
    }

    private static string GetDiagnosticId(CompilerError error)
        => error.DiagnosticIdOverride ?? $"NL{(int)error.Code:D3}";

    private void AddResolvedDllReferences(ProjectConfig config, string targetAssemblyPath, string? targetReferenceAssemblyPath)
    {
        var excludedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            Path.GetFullPath(targetAssemblyPath)
        };

        if (!string.IsNullOrWhiteSpace(targetReferenceAssemblyPath))
        {
            excludedPaths.Add(Path.GetFullPath(targetReferenceAssemblyPath));
        }

        foreach (var referencePath in References
                     .Select(reference => reference.ItemSpec)
                     .Where(path => !string.IsNullOrWhiteSpace(path))
                     .Select(Path.GetFullPath)
                     .Where(path => !excludedPaths.Contains(path)))
        {
            var alreadyPresent = config.Dependencies.Any(dependency =>
                dependency.Type == ReferenceType.Dll &&
                string.Equals(Path.GetFullPath(dependency.Dll!), referencePath, StringComparison.OrdinalIgnoreCase));

            if (!alreadyPresent)
            {
                config.Dependencies.Add(new Reference { Dll = referencePath });
            }
        }
    }
}
