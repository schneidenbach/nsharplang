using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Generates obj/project.g.props from project.yml using the canonical YAML parser.
/// This is the compatibility projection used by NSharpLang.Sdk for direct
/// `dotnet build` scenarios. Native `nlc build` does not require it.
/// </summary>
public static class RestoreCommand
{
    public static int Execute(string[] args)
    {
        var options = RestoreCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(RestoreCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = Directory.GetCurrentDirectory();
        return Restore(projectRoot);
    }

    /// <summary>
    /// Generate obj/project.g.props from project.yml for MSBuild compatibility.
    /// Returns 0 on success, 1 on failure.
    /// </summary>
    public static int Restore(string projectRoot, bool quiet = false)
    {
        return RestoreRecursive(Path.GetFullPath(projectRoot), quiet, new HashSet<string>(StringComparer.OrdinalIgnoreCase))
            ? 0
            : 1;
    }

    private static bool RestoreRecursive(string projectRoot, bool quiet, HashSet<string> visitedProjectRoots)
    {
        if (!visitedProjectRoots.Add(projectRoot))
        {
            return true;
        }

        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (!quiet)
                Console.Error.WriteLine(RestoreCommandKernels.GetMissingProjectFileMessage());
            return false;
        }

        try
        {
            var config = ProjectFileParser.Parse(projectYmlPath);
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";

            var objDir = Path.Combine(projectRoot, "obj");
            Directory.CreateDirectory(objDir);

            var outputType = config.OutputType == "exe" ? "Exe" : "Library";
            var baseSdk = config.Sdk ?? "Microsoft.NET.Sdk";

            var resolvedProjectReferences = RestoreCommandKernels.FilterReferencesByType(config.Dependencies, ReferenceType.Project)
                .Select(reference =>
                {
                    var projectPath = Path.IsPathRooted(reference.Project!)
                        ? reference.Project!
                        : Path.Combine(projectRoot, reference.Project!);
                    return ProjectReferenceResolver.ResolveMsBuildProjectPath(projectPath);
                })
                .ToArray();
            var projectReferences = RestoreCommandKernels.DeduplicateProjectReferences(resolvedProjectReferences);

            var propsPath = Path.Combine(objDir, "project.g.props");
            File.WriteAllText(
                propsPath,
                RestoreCommandKernels.GetGeneratedPropsText(
                    config.TargetFramework,
                    outputType,
                    projectName,
                    "il",
                    config.TestFramework,
                    baseSdk,
                    projectReferences),
                Encoding.UTF8);

            foreach (var dependency in RestoreCommandKernels.FilterReferencesByType(config.Dependencies, ReferenceType.Project))
            {
                var referencedPath = dependency.Project!;
                var absoluteReferencePath = Path.IsPathRooted(referencedPath)
                    ? referencedPath
                    : Path.Combine(projectRoot, referencedPath);
                var referencedProjectRoot = Path.GetDirectoryName(Path.GetFullPath(absoluteReferencePath));

                if (string.IsNullOrWhiteSpace(referencedProjectRoot))
                {
                    continue;
                }

                var referencedProjectYml = Path.Combine(referencedProjectRoot, "project.yml");
                if (!File.Exists(referencedProjectYml))
                {
                    continue;
                }

                if (!RestoreRecursive(referencedProjectRoot, quiet: true, visitedProjectRoots))
                {
                    return false;
                }
            }

            if (!quiet)
                Console.WriteLine(RestoreCommandKernels.GetGeneratedPropsMessage());

            return true;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(RestoreCommandKernels.GetFailedMessage(ex.Message));
            return false;
        }
    }

}
