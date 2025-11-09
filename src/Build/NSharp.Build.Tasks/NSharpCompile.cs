using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NewCLILang.Compiler;

namespace NSharp.Build.Tasks;

public class NSharpCompile : Task
{
    [Required]
    public ITaskItem[] Sources { get; set; } = Array.Empty<ITaskItem>();

    public ITaskItem[] References { get; set; } = Array.Empty<ITaskItem>();

    [Required]
    public string OutputPath { get; set; } = string.Empty;

    [Required]
    public string ProjectRoot { get; set; } = string.Empty;

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

        try
        {
            var sourceFiles = Sources.Select(s => s.ItemSpec).ToList();

            // Create a default project config
            var config = ProjectFileParser.CreateDefault();

            var compiler = new MultiFileCompiler(sourceFiles, ProjectRoot, config);
            var result = compiler.Compile();

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
