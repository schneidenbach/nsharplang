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

    public override bool Execute()
    {
        try
        {
            var sourceFiles = Sources
                .Select(source => source.ItemSpec)
                .Where(File.Exists)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            if (sourceFiles.Length == 0)
            {
                Log.LogMessage(MessageImportance.Low, "No N# source files to emit as IL.");
                return true;
            }

            var config = !string.IsNullOrEmpty(ProjectFile) && File.Exists(ProjectFile)
                ? ProjectFileParser.Parse(ProjectFile)
                : ProjectFileParser.CreateDefault(Path.GetFileName(ProjectRoot));
            AddResolvedDllReferences(config, TargetAssemblyPath, TargetReferenceAssemblyPath);

            var compiler = new MultiFileCompiler(sourceFiles, ProjectRoot, config);
            var result = compiler.Compile(CompilationBackend.Il, config.EffectiveName, TargetAssemblyPath);

            foreach (var error in result.Errors)
            {
                LogCompilerDiagnostic(error);
            }

            if (!result.Success)
            {
                return false;
            }

            Log.LogMessage(MessageImportance.High, $"Emitted N# IL assembly to {TargetAssemblyPath}");
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
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
                     .Where(File.Exists)
                     .Where(path => !excludedPaths.Contains(path))
                     .Distinct(StringComparer.OrdinalIgnoreCase))
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
