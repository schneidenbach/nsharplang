using System;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

public class WriteCompilationStub : Task
{
    [Required]
    public string OutputPath { get; set; } = string.Empty;

    public ITaskItem[] Sources { get; set; } = Array.Empty<ITaskItem>();

    [Required]
    public string ProjectRoot { get; set; } = string.Empty;

    public string? ProjectFile { get; set; }

    [Output]
    public ITaskItem[] GeneratedFiles { get; set; } = Array.Empty<ITaskItem>();

    public override bool Execute()
    {
        try
        {
            var config = !string.IsNullOrEmpty(ProjectFile) && File.Exists(ProjectFile)
                ? ProjectFileParser.Parse(ProjectFile)
                : ProjectFileParser.CreateDefault(Path.GetFileName(ProjectRoot));

            Directory.CreateDirectory(OutputPath);

            foreach (var generatedFile in Directory.GetFiles(OutputPath, "*.g.cs", SearchOption.AllDirectories))
            {
                File.Delete(generatedFile);
            }

            var outputFile = Path.Combine(OutputPath, "__NSharpIlStub.g.cs");
            var sourceFiles = Sources
                .Select(source => source.ItemSpec)
                .Where(File.Exists)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var stubSource = CompilationStubEmitter.Generate(config, sourceFiles);
            File.WriteAllText(outputFile, string.IsNullOrWhiteSpace(stubSource) ? GenerateFallbackStubSource(config) : stubSource);

            GeneratedFiles = new[] { new TaskItem(outputFile) };
            Log.LogMessage(MessageImportance.Low, $"Wrote IL compilation stub to {outputFile}");
            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    private static string GenerateFallbackStubSource(ProjectConfig config)
    {
        if (string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
        {
            return """
namespace NSharp.Generated;

internal static class __NSharpIlStub
{
    public static void Main(string[] args)
    {
    }
}
""";
        }

        return """
namespace NSharp.Generated;

internal static class __NSharpIlStub
{
}
""";
    }
}
