using System;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

/// <summary>
/// MSBuild task that loads project.yml and sets MSBuild properties
/// This allows the .csproj file to be minimal - just &lt;Project Sdk="NSharpLang.Sdk" /&gt;
/// </summary>
public class LoadProjectConfig : Task
{
    /// <summary>
    /// Project directory (usually $(MSBuildProjectDirectory))
    /// </summary>
    [Required]
    public string ProjectDirectory { get; set; } = string.Empty;

    /// <summary>
    /// Output: Target framework from project.yml (e.g., "net10.0")
    /// </summary>
    [Output]
    public string TargetFramework { get; set; } = string.Empty;

    /// <summary>
    /// Output: Output type from project.yml (e.g., "Exe", "Library")
    /// </summary>
    [Output]
    public string OutputType { get; set; } = string.Empty;

    /// <summary>
    /// Output: Assembly name from project.yml name field
    /// </summary>
    [Output]
    public string AssemblyName { get; set; } = string.Empty;

    /// <summary>
    /// Output: Version from project.yml
    /// </summary>
    [Output]
    public string Version { get; set; } = string.Empty;

    /// <summary>
    /// Output: CLR-compatible AssemblyVersion derived from Version.
    /// </summary>
    [Output]
    public string AssemblyVersion { get; set; } = string.Empty;

    /// <summary>
    /// Output: CLR-compatible FileVersion derived from Version.
    /// </summary>
    [Output]
    public string FileVersion { get; set; } = string.Empty;

    /// <summary>
    /// Output: SDK type (e.g., "Microsoft.NET.Sdk", "Microsoft.NET.Sdk.Web")
    /// </summary>
    [Output]
    public string Sdk { get; set; } = string.Empty;

    /// <summary>
    /// Output: Test framework (e.g., "xunit", "nunit")
    /// </summary>
    [Output]
    public string TestFramework { get; set; } = "xunit";

    public override bool Execute()
    {
        try
        {
            var projectYmlPath = Path.Combine(ProjectDirectory, "project.yml");

            Log.LogMessage(MessageImportance.Low, $"Loading project configuration from {projectYmlPath}");

            // Parse project.yml
            var config = ProjectFileParser.Parse(projectYmlPath);

            // Set output properties
            TargetFramework = config.TargetFramework;

            // Convert outputType to MSBuild format (capitalize first letter)
            OutputType = config.OutputType.ToLowerInvariant() switch
            {
                "exe" => "Exe",
                "library" => "Library",
                _ => "Exe"
            };

            AssemblyName = config.Name ?? Path.GetFileName(ProjectDirectory);
            Version = config.Version ?? string.Empty;
            SetClrVersionOutputs(Version);
            Sdk = config.Sdk;
            TestFramework = config.TestFramework;

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    private void SetClrVersionOutputs(string? packageVersion)
    {
        if (string.IsNullOrWhiteSpace(packageVersion))
        {
            AssemblyVersion = string.Empty;
            FileVersion = string.Empty;
            return;
        }

        var clrVersion = AssemblyVersionUtilities.GetAssemblyVersionOrDefault(packageVersion).ToString();
        AssemblyVersion = clrVersion;
        FileVersion = clrVersion;
    }
}
