using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

/// <summary>
/// MSBuild task that transpiles .tests.nl files into xUnit test classes
/// </summary>
public class TranspileTests : Task
{
    [Required]
    public ITaskItem[] TestFiles { get; set; } = Array.Empty<ITaskItem>();

    [Required]
    public string OutputPath { get; set; } = string.Empty;

    [Required]
    public string ProjectRoot { get; set; } = string.Empty;

    public string? ProjectFile { get; set; }

    [Output]
    public ITaskItem[] GeneratedFiles { get; set; } = Array.Empty<ITaskItem>();

    public override bool Execute()
    {
        if (TestFiles == null || TestFiles.Length == 0)
        {
            Log.LogMessage(MessageImportance.Low, "No N# test files to transpile.");
            return true;
        }

        Log.LogMessage(MessageImportance.High, $"Transpiling {TestFiles.Length} N# test file(s)...");

        try
        {
            var ilStubPath = Path.Combine(OutputPath, "__NSharpIlStub.g.cs");
            if (File.Exists(ilStubPath))
            {
                File.Delete(ilStubPath);
            }

            var testFiles = TestFiles.Select(t => t.ItemSpec).ToList();

            // Load project config from project.yml if available, otherwise use default
            var config = !string.IsNullOrEmpty(ProjectFile) && File.Exists(ProjectFile)
                ? ProjectFileParser.Parse(ProjectFile)
                : ProjectFileParser.CreateDefault();

            Log.LogMessage(MessageImportance.Low,
                $"Using config: {(string.IsNullOrEmpty(ProjectFile) ? "default" : ProjectFile)}");

            // Compile each test file separately
            var generatedFiles = new List<ITaskItem>();
            var allErrors = new List<CompilerError>();

            foreach (var testFile in testFiles)
            {
                try
                {
                    // Compile the test file using the existing compiler
                    var compiler = new MultiFileCompiler(new[] { testFile }, ProjectRoot, config);
                    var result = compiler.Compile();

                    if (!result.Success)
                    {
                        foreach (var error in result.Errors)
                        {
                            if (error.Severity == ErrorSeverity.Error)
                            {
                                Log.LogError(
                                    subcategory: null,
                                    errorCode: error.DiagnosticId,
                                    helpKeyword: null,
                                    file: error.FileName ?? testFile,
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
                                    file: error.FileName ?? testFile,
                                    lineNumber: error.Line,
                                    columnNumber: error.Column,
                                    endLineNumber: error.Line,
                                    endColumnNumber: error.Column + Math.Max(0, error.Length - 1),
                                    message: error.FormatForMsBuild()
                                );
                            }
                        }
                        allErrors.AddRange(result.Errors);
                        continue;
                    }

                    // Write transpiled C# files to output
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
                }
                catch (Exception ex)
                {
                    Log.LogError($"Failed to transpile test file {testFile}: {ex.Message}");
                    Log.LogMessage(MessageImportance.Low, ex.StackTrace);
                    return false;
                }
            }

            GeneratedFiles = generatedFiles.ToArray();

            // Return false if there were any errors
            if (allErrors.Any(e => e.Severity == ErrorSeverity.Error))
            {
                Log.LogError($"Failed to transpile {TestFiles.Length} test file(s) with errors.");
                return false;
            }

            Log.LogMessage(MessageImportance.High, $"Successfully transpiled {TestFiles.Length} N# test file(s).");
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }
}
