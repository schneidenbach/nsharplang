using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using Mono.Cecil;
using NSharpLang.Cli;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

/// <summary>
/// Drives N# IL emission from the SDK. Every decision this task takes belongs to
/// <see cref="SdkEmitTaskKernels"/>; what remains here is MSBuild task plumbing and the Mono.Cecil
/// API mechanics that carry those decisions out.
/// </summary>
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

    /// <summary>Build configuration ("Debug"/"Release") from MSBuild.</summary>
    public string? Configuration { get; set; }

    /// <summary>MSBuild <c>$(DefineConstants)</c>.</summary>
    public string? DefineConstants { get; set; }

    public bool ValidateWithLegacyAnalysis { get; set; } = SdkEmitTaskKernels.ValidatesWithLegacyAnalysisByDefault();

    public override bool Execute()
    {
        try
        {
            var sourceFiles = Sources
                .Select(source => source.ItemSpec)
                .ToArray();

            var config = ProjectFileParser.Parse(ProjectFile!);
            config.Version = SdkEmitTaskKernels.ResolveProjectVersion(config.Version, AssemblyVersion);
            SdkEmitTaskKernels.ApplyMsBuildDefines(config, Configuration, DefineConstants);
            AddResolvedDllReferences(config);

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

            SynchronizeReferenceAssembly();
            Log.LogMessage(MessageImportance.High, SdkEmitTaskKernels.GetEmittedAssemblyMessage(TargetAssemblyPath));
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    private void AddResolvedDllReferences(ProjectConfig config)
    {
        foreach (var reference in References)
        {
            var referencePath = reference.ItemSpec;
            if (string.IsNullOrWhiteSpace(referencePath))
            {
                continue;
            }

            var fullPath = Path.GetFullPath(referencePath);
            if (!IsOwnOutput(fullPath)
                && CompilationReferenceResolverKernels.ShouldAddDllReference(config.Dependencies, fullPath))
            {
                config.Dependencies.Add(new Reference { Dll = fullPath });
            }
        }
    }

    private bool IsOwnOutput(string fullPath)
    {
        if (SdkEmitTaskKernels.IsSameOutputPath(fullPath, Path.GetFullPath(TargetAssemblyPath)))
        {
            return true;
        }

        return !string.IsNullOrWhiteSpace(TargetReferenceAssemblyPath)
            && SdkEmitTaskKernels.IsSameOutputPath(fullPath, Path.GetFullPath(TargetReferenceAssemblyPath));
    }

    private void SynchronizeReferenceAssembly()
    {
        if (!SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly(TargetReferenceAssemblyPath, File.Exists(TargetAssemblyPath)))
        {
            return;
        }

        var assemblyPath = Path.GetFullPath(TargetAssemblyPath);
        var referenceAssemblyPath = Path.GetFullPath(TargetReferenceAssemblyPath!);
        if (SdkEmitTaskKernels.IsSameOutputPath(assemblyPath, referenceAssemblyPath))
        {
            return;
        }

        var referenceAssemblyDirectory = Path.GetDirectoryName(referenceAssemblyPath);
        if (!string.IsNullOrEmpty(referenceAssemblyDirectory))
        {
            Directory.CreateDirectory(referenceAssemblyDirectory);
        }

        var owners = BuildReferenceTypeOwners(out var ownerNames);
        if (SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(owners))
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
            var owner = owners.Resolve(typeReference.FullName);
            if (!SdkEmitTaskKernels.ShouldRescopeTypeReference(ScopeName(typeReference), owner != null))
            {
                continue;
            }

            typeReference.Scope = GetOrAddAssemblyReference(module, ownerNames[owner!]);
        }

        RemoveUnusedCoreLibAssemblyReference(module);
        assembly.Write(referenceAssemblyPath);
    }

    private ReferenceTypeOwners BuildReferenceTypeOwners(out Dictionary<string, AssemblyNameDefinition> ownerNames)
    {
        var owners = new ReferenceTypeOwners();
        ownerNames = new Dictionary<string, AssemblyNameDefinition>(StringComparer.Ordinal);
        foreach (var path in ReferencesToScanForOwners())
        {
            AssemblyDefinition? referenceAssembly = null;
            try
            {
                referenceAssembly = AssemblyDefinition.ReadAssembly(path, new ReaderParameters { ReadingMode = ReadingMode.Deferred });
                var ownerKey = referenceAssembly.Name.FullName;
                ownerNames.TryAdd(ownerKey, referenceAssembly.Name);
                foreach (var type in referenceAssembly.MainModule.Types)
                {
                    RecordDefinedTypes(owners, ownerKey, type);
                }

                foreach (var exportedType in referenceAssembly.MainModule.ExportedTypes)
                {
                    owners.RecordForwarder(exportedType.FullName, ownerKey);
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

        return owners;
    }

    private IEnumerable<string> ReferencesToScanForOwners()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var reference in References)
        {
            var referencePath = reference.ItemSpec;
            if (string.IsNullOrWhiteSpace(referencePath))
            {
                continue;
            }

            var fullPath = Path.GetFullPath(referencePath);
            if (SdkEmitTaskKernels.ShouldScanReferenceForOwners(fullPath, File.Exists(referencePath), IsOwnOutput(fullPath))
                && seen.Add(fullPath))
            {
                yield return fullPath;
            }
        }
    }

    private static void RecordDefinedTypes(ReferenceTypeOwners owners, string ownerKey, TypeDefinition type)
    {
        owners.RecordDefinition(type.FullName, ownerKey);
        foreach (var nestedType in type.NestedTypes)
        {
            RecordDefinedTypes(owners, ownerKey, nestedType);
        }
    }

    private static AssemblyNameReference GetOrAddAssemblyReference(ModuleDefinition module, AssemblyNameDefinition owner)
    {
        var existing = module.AssemblyReferences.FirstOrDefault(reference =>
            SdkEmitTaskKernels.AssemblyReferenceMatches(
                reference.Name,
                VersionText(reference.Version),
                owner.Name,
                VersionText(owner.Version)));
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
        var hasCoreLibTypeReference = module.GetTypeReferences()
            .Any(typeReference => SdkEmitTaskKernels.IsImplementationCoreLibrary(ScopeName(typeReference)));
        if (!SdkEmitTaskKernels.ShouldRemoveCoreLibraryReference(hasCoreLibTypeReference))
        {
            return;
        }

        foreach (var reference in module.AssemblyReferences
                     .Where(reference => SdkEmitTaskKernels.IsImplementationCoreLibrary(reference.Name))
                     .ToArray())
        {
            module.AssemblyReferences.Remove(reference);
        }
    }

    private static string? ScopeName(TypeReference typeReference)
        => (typeReference.Scope as AssemblyNameReference)?.Name;

    private static string VersionText(Version? version) => version?.ToString() ?? string.Empty;

    private void LogCompilerDiagnostic(CompilerError error)
    {
        if (error.Severity == ErrorSeverity.Error)
        {
            Log.LogError(
                subcategory: null,
                errorCode: error.DiagnosticId,
                helpKeyword: null,
                file: error.FileName ?? string.Empty,
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.MsBuildEndColumn,
                message: error.FormatForMsBuild());
        }
        else if (error.Severity == ErrorSeverity.Warning)
        {
            Log.LogWarning(
                subcategory: null,
                warningCode: error.DiagnosticId,
                helpKeyword: null,
                file: error.FileName ?? string.Empty,
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.MsBuildEndColumn,
                message: error.FormatForMsBuild());
        }
    }
}
