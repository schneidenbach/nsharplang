namespace NSharpLang.Compiler

import System
import System.IO

public class ProjectReferenceResolver {
    public static func ResolveNSharpProjectRoot(projectReferencePath: string): string {
        ArgumentException.ThrowIfNullOrWhiteSpace(projectReferencePath)

        fullPath := Path.GetFullPath(projectReferencePath)
        if Directory.Exists(fullPath) {
            projectFile := Path.Combine(fullPath, "project.yml")
            if File.Exists(projectFile) {
                return fullPath
            }

            throw new FileNotFoundException(
                "Project reference '" + projectReferencePath + "' points to a directory, but no project.yml was found in that directory.")
        }

        if !File.Exists(fullPath) {
            throw new FileNotFoundException("Project reference not found: " + projectReferencePath)
        }

        if IsYamlProjectPath(fullPath) {
            projectDirectory := Path.GetDirectoryName(fullPath)
            if projectDirectory == null {
                throw new InvalidOperationException("Could not determine the project directory for '" + projectReferencePath + "'.")
            }

            return projectDirectory
        }

        throw new InvalidOperationException(
            "N# project reference '" + projectReferencePath + "' must point to a project.yml file or a directory containing project.yml. "
                + "Use a DLL reference for prebuilt assemblies, or keep .csproj references inside MSBuild compatibility projects.")
    }

    public static func ResolveMsBuildProjectPath(projectReferencePath: string): string {
        ArgumentException.ThrowIfNullOrWhiteSpace(projectReferencePath)

        fullPath := Path.GetFullPath(projectReferencePath)

        if fullPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) {
            return fullPath
        }

        if !IsYamlProjectPath(fullPath) {
            throw new InvalidOperationException("Unsupported project reference '" + projectReferencePath + "'. Expected a .csproj or project.yml path.")
        }

        projectDirectory := Path.GetDirectoryName(fullPath)
        if projectDirectory == null {
            throw new InvalidOperationException("Could not determine the project directory for '" + projectReferencePath + "'.")
        }

        config := ProjectFileParser.Parse(fullPath)

        namedCsproj := Path.Combine(projectDirectory, config.EffectiveName + ".csproj")
        if File.Exists(namedCsproj) {
            return namedCsproj
        }

        csprojFiles := Directory.GetFiles(projectDirectory, "*.csproj", SearchOption.TopDirectoryOnly)
        if csprojFiles.Length == 1 {
            return csprojFiles[0]
        }

        directoryNamedCsproj := Path.Combine(projectDirectory, Path.GetFileName(projectDirectory) + ".csproj")
        if File.Exists(directoryNamedCsproj) {
            return directoryNamedCsproj
        }

        throw new FileNotFoundException(
            "Could not resolve an MSBuild project for '" + projectReferencePath + "'. Expected '" + namedCsproj + "' or a single .csproj in '" + projectDirectory + "'.")
    }

    static func IsYamlProjectPath(path: string): bool {
        return path.EndsWith(".yml", StringComparison.OrdinalIgnoreCase)
            || path.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase)
    }
}
