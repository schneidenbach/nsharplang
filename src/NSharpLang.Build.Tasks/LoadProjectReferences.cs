using System;
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
    public string[] FrameworkReferences { get; set; } = Array.Empty<string>();

    public string[] ExistingProjectReferences { get; set; } = Array.Empty<string>();

    [Output]
    public string[] ProjectReferences { get; set; } = Array.Empty<string>();

    public override bool Execute()
    {
        try
        {
            var projection = SdkProjectReferenceProjection.Resolve(ProjectFile!, ExistingProjectReferences);
            var packageReferences = new ITaskItem[projection.PackageReferences.Length];
            for (var i = 0; i < packageReferences.Length; i++)
            {
                var reference = projection.PackageReferences[i];
                packageReferences[i] = new TaskItem(reference.Identity, reference.Metadata);
            }

            PackageReferences = packageReferences;
            FrameworkReferences = projection.FrameworkReferences;
            ProjectReferences = projection.ProjectReferences;

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex, showStackTrace: true);
            return false;
        }
    }
}
