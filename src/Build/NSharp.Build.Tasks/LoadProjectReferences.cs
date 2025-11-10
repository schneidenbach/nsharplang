using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using NewCLILang.Compiler;

namespace NSharp.Build.Tasks;

public class LoadProjectReferences : Task
{
    public string? ProjectFile { get; set; }

    [Output]
    public ITaskItem[] PackageReferences { get; set; } = Array.Empty<ITaskItem>();

    [Output]
    public ITaskItem[] FrameworkReferences { get; set; } = Array.Empty<ITaskItem>();

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

                    // DLL and Project references are handled differently
                    case ReferenceType.Dll:
                    case ReferenceType.Project:
                        // These will be handled by the N# compiler during build
                        break;
                }
            }

            PackageReferences = packageRefs.ToArray();
            FrameworkReferences = frameworkRefs.ToArray();

            Log.LogMessage(MessageImportance.Normal,
                $"Loaded {PackageReferences.Length} package reference(s) and {FrameworkReferences.Length} framework reference(s) from {ProjectFile}");

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }
}
