using System;
using System.Collections.Generic;
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

    public override bool Execute()
    {
        try
        {
            var config = ProjectFileParser.Parse(ProjectFile!);

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

                    // DLL references are handled by the compiler during build
                    case ReferenceType.Dll:
                        break;
                }
            }

            PackageReferences = packageRefs.ToArray();
            FrameworkReferences = frameworkRefs.ToArray();

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }
}
