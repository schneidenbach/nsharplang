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

        var logPath = Path.Combine(ProjectRoot, "compile-debug.log");
        try
        {
            try { File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] NSharpCompile.Execute ENTRY (ProjectRoot={ProjectRoot})\n"); } catch (Exception ex) { Log.LogMessage(MessageImportance.High, $"Failed to write log: {ex.Message}"); }
            Log.LogMessage(MessageImportance.High, "About to process source files...");
            var sourceFiles = Sources.Select(s => s.ItemSpec).ToList();
            Log.LogMessage(MessageImportance.High, $"Processed {sourceFiles.Count} source files");
            try { File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Source files: {string.Join(", ", sourceFiles.Select(Path.GetFileName))}\n"); } catch { }

            // Load project config from project.yml if available, otherwise use default
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Loading project config from: {ProjectFile ?? "default"}\n");
            var config = !string.IsNullOrEmpty(ProjectFile) && File.Exists(ProjectFile)
                ? ProjectFileParser.Parse(ProjectFile)
                : ProjectFileParser.CreateDefault();
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Config loaded\n");

            Log.LogMessage(MessageImportance.Low,
                $"Using config: {(string.IsNullOrEmpty(ProjectFile) ? "default" : ProjectFile)}");

            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Creating MultiFileCompiler\n");
            var compiler = new MultiFileCompiler(sourceFiles, ProjectRoot, config);
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Calling compiler.Compile()\n");
            var result = compiler.Compile();
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] compiler.Compile() returned\n");

            if (!result.Success)
            {
                foreach (var error in result.Errors)
                {
                    if (error.Severity == ErrorSeverity.Error)
                    {
                        Log.LogError(
                            subcategory: null,
                            errorCode: error.Code.ToString(),
                            helpKeyword: null,
                            file: error.FileName ?? "",
                            lineNumber: error.Line,
                            columnNumber: error.Column,
                            endLineNumber: error.Line,
                            endColumnNumber: error.Column,
                            message: error.Message
                        );
                    }
                    else if (error.Severity == ErrorSeverity.Warning)
                    {
                        Log.LogWarning(
                            subcategory: null,
                            warningCode: error.Code.ToString(),
                            helpKeyword: null,
                            file: error.FileName ?? "",
                            lineNumber: error.Line,
                            columnNumber: error.Column,
                            endLineNumber: error.Line,
                            endColumnNumber: error.Column,
                            message: error.Message
                        );
                    }
                }
                return false;
            }

            // Write transpiled C# files to output
            var generatedFiles = new List<ITaskItem>();
            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;

                // Generate output path
                var fileName = Path.GetFileNameWithoutExtension(sourceFile);
                var outputFile = Path.Combine(OutputPath, $"{fileName}.g.cs");

                // Ensure output directory exists
                Directory.CreateDirectory(OutputPath);

                // Write the C# file
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
}
