using System;
using System.IO;
using System.Linq;

namespace NSharpLang.Compiler;

public static class ProjectReferenceResolver
{
    public static string ResolveMsBuildProjectPath(string projectReferencePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(projectReferencePath);

        var fullPath = Path.GetFullPath(projectReferencePath);

        if (fullPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
        {
            return fullPath;
        }

        if (!fullPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase) &&
            !fullPath.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"Unsupported project reference '{projectReferencePath}'. Expected a .csproj or project.yml path.");
        }

        var projectDirectory = Path.GetDirectoryName(fullPath)
            ?? throw new InvalidOperationException($"Could not determine the project directory for '{projectReferencePath}'.");
        var config = ProjectFileParser.Parse(fullPath);

        var namedCsproj = Path.Combine(projectDirectory, $"{config.EffectiveName}.csproj");
        if (File.Exists(namedCsproj))
        {
            return namedCsproj;
        }

        var csprojFiles = Directory.GetFiles(projectDirectory, "*.csproj", SearchOption.TopDirectoryOnly);
        if (csprojFiles.Length == 1)
        {
            return csprojFiles[0];
        }

        var directoryNamedCsproj = Path.Combine(projectDirectory, $"{Path.GetFileName(projectDirectory)}.csproj");
        if (File.Exists(directoryNamedCsproj))
        {
            return directoryNamedCsproj;
        }

        throw new FileNotFoundException(
            $"Could not resolve an MSBuild project for '{projectReferencePath}'. Expected '{namedCsproj}' or a single .csproj in '{projectDirectory}'.");
    }

    public static bool IsNSharpProjectReference(string projectReferencePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(projectReferencePath);

        var fullPath = Path.GetFullPath(projectReferencePath);

        if (fullPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase) ||
            fullPath.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!fullPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) || !File.Exists(fullPath))
        {
            return false;
        }

        var contents = File.ReadAllText(fullPath);
        return contents.Contains("NSharpLang.Sdk", StringComparison.Ordinal);
    }
}
