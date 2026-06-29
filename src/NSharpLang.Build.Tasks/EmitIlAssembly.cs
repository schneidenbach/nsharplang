using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
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

            SynchronizeReferenceAssembly(TargetAssemblyPath, TargetReferenceAssemblyPath);
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

    private static void SynchronizeReferenceAssembly(string targetAssemblyPath, string? targetReferenceAssemblyPath)
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

        File.Copy(assemblyPath, referenceAssemblyPath, overwrite: true);
    }

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
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
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
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                message: error.FormatForMsBuild());
        }
    }

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
