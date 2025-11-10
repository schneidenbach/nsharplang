using System;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

/// <summary>
/// MSBuild task that loads project.yml and sets MSBuild properties
/// This allows the .csproj file to be minimal - just &lt;Project Sdk="Microsoft.NET.Sdk.NSharp" /&gt;
/// </summary>
public class LoadProjectConfig : Task
{
    /// <summary>
    /// Project directory (usually $(MSBuildProjectDirectory))
    /// </summary>
    [Required]
    public string ProjectDirectory { get; set; } = string.Empty;

    /// <summary>
    /// Output: Target framework from project.yml (e.g., "net9.0")
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
    /// Output: SDK type (e.g., "Microsoft.NET.Sdk", "Microsoft.NET.Sdk.Web")
    /// </summary>
    [Output]
    public string Sdk { get; set; } = string.Empty;

    /// <summary>
    /// Output: NuGet package references (semicolon-separated "Package;Version" pairs)
    /// </summary>
    [Output]
    public ITaskItem[] PackageReferences { get; set; } = Array.Empty<ITaskItem>();

    /// <summary>
    /// Output: Project references (paths to .csproj or project.yml files)
    /// </summary>
    [Output]
    public ITaskItem[] ProjectReferences { get; set; } = Array.Empty<ITaskItem>();

    /// <summary>
    /// Output: Framework references (e.g., "Microsoft.AspNetCore.App")
    /// </summary>
    [Output]
    public ITaskItem[] FrameworkReferences { get; set; } = Array.Empty<ITaskItem>();

    public override bool Execute()
    {
        try
        {
            var projectYmlPath = Path.Combine(ProjectDirectory, "project.yml");

            // If no project.yml exists, use defaults
            if (!File.Exists(projectYmlPath))
            {
                Log.LogMessage(MessageImportance.Low, "No project.yml found, using defaults");
                SetDefaults();
                return true;
            }

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
            Sdk = config.Sdk;

            // Convert dependencies to MSBuild items
            var packageRefs = new System.Collections.Generic.List<ITaskItem>();
            var projectRefs = new System.Collections.Generic.List<ITaskItem>();
            var frameworkRefs = new System.Collections.Generic.List<ITaskItem>();

            foreach (var dep in config.Dependencies)
            {
                switch (dep.Type)
                {
                    case ReferenceType.NuGet:
                        var item = new TaskItem(dep.Nuget!);
                        if (!string.IsNullOrEmpty(dep.Version))
                        {
                            item.SetMetadata("Version", dep.Version);
                        }
                        packageRefs.Add(item);
                        break;

                    case ReferenceType.Project:
                        var projPath = Path.IsPathRooted(dep.Project!)
                            ? dep.Project!
                            : Path.Combine(ProjectDirectory, dep.Project!);
                        projectRefs.Add(new TaskItem(projPath));
                        break;

                    case ReferenceType.Framework:
                        frameworkRefs.Add(new TaskItem(dep.Framework!));
                        break;

                    case ReferenceType.Dll:
                        // DLL references are handled differently - we'll add support later if needed
                        Log.LogWarning($"DLL references not yet supported in SDK: {dep.Dll}");
                        break;
                }
            }

            PackageReferences = packageRefs.ToArray();
            ProjectReferences = projectRefs.ToArray();
            FrameworkReferences = frameworkRefs.ToArray();

            Log.LogMessage(MessageImportance.Low,
                $"Loaded config: {AssemblyName} ({OutputType}), framework={TargetFramework}, " +
                $"{PackageReferences.Length} packages, {ProjectReferences.Length} projects");

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }

    private void SetDefaults()
    {
        TargetFramework = "net9.0";
        OutputType = "Exe";
        AssemblyName = Path.GetFileName(ProjectDirectory);
        Sdk = "Microsoft.NET.Sdk";
        PackageReferences = Array.Empty<ITaskItem>();
        ProjectReferences = Array.Empty<ITaskItem>();
        FrameworkReferences = Array.Empty<ITaskItem>();
    }
}
