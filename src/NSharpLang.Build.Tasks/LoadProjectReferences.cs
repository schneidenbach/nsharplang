using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NSharpLang.Compiler;

namespace NSharpLang.Build.Tasks;

public class LoadProjectReferences : Task
{
    public string? ProjectFile { get; set; }

    [Output]
    public ITaskItem[] PackageReferences { get; set; } = Array.Empty<ITaskItem>();

    [Output]
    public ITaskItem[] FrameworkReferences { get; set; } = Array.Empty<ITaskItem>();

    [Output]
    public ITaskItem[] ProjectReferences { get; set; } = Array.Empty<ITaskItem>();

    public override bool Execute()
    {
        try
        {
            if (string.IsNullOrEmpty(ProjectFile) || !File.Exists(ProjectFile))
            {
                Log.LogMessage(MessageImportance.Low, "No project.yml file found, skipping reference loading.");
                return true;
            }

            var config = ProjectFileParser.Parse(ProjectFile);

            var packageRefs = new List<ITaskItem>();
            var frameworkRefs = new List<ITaskItem>();
            var projectRefs = new List<ITaskItem>();

            // Process dependencies
            foreach (var dep in config.Dependencies)
            {
                switch (dep.Type)
                {
                    case ReferenceType.NuGet:
                        var pkgItem = new TaskItem(dep.Nuget!);
                        if (!string.IsNullOrEmpty(dep.Version))
                        {
                            pkgItem.SetMetadata("Version", dep.Version!);
                        }
                        packageRefs.Add(pkgItem);
                        break;

                    case ReferenceType.Framework:
                        var fwItem = new TaskItem(dep.Framework!);
                        frameworkRefs.Add(fwItem);
                        break;

                    // DLL references are handled by the compiler during build
                    case ReferenceType.Dll:
                        break;

                    case ReferenceType.Project:
                        var projectPath = Path.IsPathRooted(dep.Project!)
                            ? dep.Project!
                            : Path.Combine(Path.GetDirectoryName(ProjectFile)!, dep.Project!);
                        var resolvedProjectPath = ProjectReferenceResolver.ResolveMsBuildProjectPath(projectPath);
                        projectRefs.Add(new TaskItem(resolvedProjectPath));
                        break;
                }
            }

            PackageReferences = packageRefs.ToArray();
            FrameworkReferences = frameworkRefs.ToArray();
            ProjectReferences = projectRefs.ToArray();

            Log.LogMessage(MessageImportance.Normal,
                $"Loaded {PackageReferences.Length} package reference(s), {FrameworkReferences.Length} framework reference(s), and {ProjectReferences.Length} project reference(s) from {ProjectFile}");

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }
}
