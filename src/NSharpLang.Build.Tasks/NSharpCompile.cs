using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

public class NSharpCompile : Task
{
    [Required]
    public ITaskItem[] Sources { get; set; } = Array.Empty<ITaskItem>();

    public ITaskItem[] References { get; set; } = Array.Empty<ITaskItem>();

    [Required]
    public string OutputPath { get; set; } = string.Empty;

    [Required]
    public string ProjectRoot { get; set; } = string.Empty;

    public string? ProjectFile { get; set; }

    [Output]
    public ITaskItem[] GeneratedFiles { get; set; } = Array.Empty<ITaskItem>();

    public override bool Execute()
    {
        if (Sources == null || Sources.Length == 0)
        {
            Log.LogMessage(MessageImportance.Low, "No N# source files to compile.");
            return true;
        }

        Log.LogMessage(MessageImportance.High, $"Compiling {Sources.Length} N# file(s)...");
        Log.LogMessage(MessageImportance.High, $"ProjectRoot: {ProjectRoot}");

        try
        {
            Log.LogMessage(MessageImportance.High, "About to process source files...");
            var sourceFiles = Sources.Select(s => s.ItemSpec).ToList();
            Log.LogMessage(MessageImportance.High, $"Processed {sourceFiles.Count} source files");

            // Load project config from project.yml if available, otherwise use default
            var config = !string.IsNullOrEmpty(ProjectFile) && File.Exists(ProjectFile)
                ? ProjectFileParser.Parse(ProjectFile)
                : ProjectFileParser.CreateDefault();

            Log.LogMessage(MessageImportance.Low,
                $"Using config: {(string.IsNullOrEmpty(ProjectFile) ? "default" : ProjectFile)}");

            var compiler = new MultiFileCompiler(sourceFiles, ProjectRoot, config);
            var result = compiler.Compile();

            if (!result.Success)
            {
                foreach (var error in result.Errors)
                {
                    LogCompilerError(error);
                }
                return false;
            }

            // Run linter on all source files — same checks the LSP and `nlc check` run.
            // Lint errors block compilation; lint warnings are reported as MSBuild warnings.
            var hasLintErrors = RunLinter(compiler, sourceFiles);

            if (hasLintErrors)
            {
                return false;
            }

            // Write transpiled C# files to output
            var generatedFiles = new List<ITaskItem>();
            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;

                var relativePath = Path.GetRelativePath(ProjectRoot, sourceFile);
                var relativeDirectory = Path.GetDirectoryName(relativePath);
                var outputDirectory = string.IsNullOrEmpty(relativeDirectory)
                    ? OutputPath
                    : Path.Combine(OutputPath, relativeDirectory);

                Directory.CreateDirectory(outputDirectory);

                // Write the C# file
                var fileName = Path.GetFileNameWithoutExtension(sourceFile);
                var outputFile = Path.Combine(outputDirectory, $"{fileName}.g.cs");
                File.WriteAllText(outputFile, csharpCode);

                Log.LogMessage(MessageImportance.Normal, $"  {Path.GetFileName(sourceFile)} -> {Path.GetFileName(outputFile)}");

                var item = new TaskItem(outputFile);
                generatedFiles.Add(item);
            }

            GeneratedFiles = generatedFiles.ToArray();
            Log.LogMessage(MessageImportance.High, $"Successfully compiled {Sources.Length} N# file(s).");
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    /// <summary>
    /// Runs the linter on all source files using the same pipeline as the LSP and `nlc check`.
    /// Reuses already-parsed CompilationUnits from the compiler to avoid redundant parsing.
    /// Returns true if any lint diagnostic has Error severity.
    /// </summary>
    private bool RunLinter(MultiFileCompiler compiler, List<string> sourceFiles)
    {
        var hasErrors = false;

        foreach (var sourceFile in sourceFiles)
        {
            if (!compiler.CompilationUnits.TryGetValue(sourceFile, out var compilationUnit))
                continue;

            string source;
            try
            {
                source = File.ReadAllText(sourceFile);
            }
            catch (Exception ex)
            {
                Log.LogWarning($"Could not read '{sourceFile}' for linting: {ex.Message}");
                continue;
            }

            var fileDir = Path.GetDirectoryName(sourceFile);
            if (string.IsNullOrEmpty(fileDir))
                fileDir = ProjectRoot;
            var linterConfig = LinterConfig.FromEditorConfig(fileDir);
            var linter = new Linter(linterConfig);
            var diagnostics = linter.Lint(compilationUnit, sourceFile, source);

            foreach (var diagnostic in diagnostics)
            {
                var file = diagnostic.Location.FilePath ?? sourceFile;

                if (diagnostic.Severity == DiagnosticSeverity.Error)
                {
                    Log.LogError(
                        subcategory: "lint",
                        errorCode: diagnostic.Code,
                        helpKeyword: null,
                        file: file,
                        lineNumber: diagnostic.Location.Line,
                        columnNumber: diagnostic.Location.Column,
                        endLineNumber: diagnostic.Location.Line,
                        endColumnNumber: diagnostic.Location.Column,
                        message: FormatLintMessage(diagnostic)
                    );
                    hasErrors = true;
                }
                else if (diagnostic.Severity == DiagnosticSeverity.Warning)
                {
                    Log.LogWarning(
                        subcategory: "lint",
                        warningCode: diagnostic.Code,
                        helpKeyword: null,
                        file: file,
                        lineNumber: diagnostic.Location.Line,
                        columnNumber: diagnostic.Location.Column,
                        endLineNumber: diagnostic.Location.Line,
                        endColumnNumber: diagnostic.Location.Column,
                        message: FormatLintMessage(diagnostic)
                    );
                }
            }
        }

        return hasErrors;
    }

    private static string FormatLintMessage(Diagnostic diagnostic)
    {
        if (diagnostic.Suggestion != null)
            return $"{diagnostic.Message} [{diagnostic.Suggestion}]";
        return diagnostic.Message;
    }

    private void LogCompilerError(CompilerError error)
    {
        if (error.Severity == ErrorSeverity.Error)
        {
            Log.LogError(
                subcategory: null,
                errorCode: error.DiagnosticId,
                helpKeyword: null,
                file: error.FileName ?? "",
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                message: error.FormatForMsBuild()
            );
        }
        else if (error.Severity == ErrorSeverity.Warning)
        {
            Log.LogWarning(
                subcategory: null,
                warningCode: error.DiagnosticId,
                helpKeyword: null,
                file: error.FileName ?? "",
                lineNumber: error.Line,
                columnNumber: error.Column,
                endLineNumber: error.Line,
                endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                message: error.FormatForMsBuild()
            );
        }
    }
}
