namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler
import System
import System.Collections.Generic
import System.IO

public class RestoreCommand {
    public static func Execute(args: string[]): int {
        options := RestoreCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print RestoreCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Environment.CurrentDirectory
        return Restore(projectRoot, false)
    }

    public static func Restore(projectRoot: string, quiet: bool = false): int {
        visitedProjectRoots := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        if RestoreRecursive(Path.GetFullPath(projectRoot), quiet, visitedProjectRoots) {
            return 0
        }

        return 1
    }

    static func RestoreRecursive(projectRoot: string, quiet: bool, visitedProjectRoots: HashSet<string>): bool {
        if !visitedProjectRoots.Add(projectRoot) {
            return true
        }

        projectYmlPath := Path.Combine(projectRoot, "project.yml")
        if !File.Exists(projectYmlPath) {
            if !quiet {
                Console.Error.WriteLine(RestoreCommandKernels.GetMissingProjectFileMessage())
            }

            return false
        }

        try {
            config := ProjectFileParser.Parse(projectYmlPath)
            projectName := config.Name ?? Path.GetFileName(projectRoot) ?? "Project"

            objDir := Path.Combine(projectRoot, "obj")
            Directory.CreateDirectory(objDir)

            outputType := "Library"
            if config.OutputType == "exe" {
                outputType = "Exe"
            }

            baseSdk := config.Sdk ?? "Microsoft.NET.Sdk"
            projectDependencies := RestoreCommandKernels.FilterReferencesByType(config.Dependencies, ReferenceType.Project)
            resolvedProjectReferences := ResolveProjectReferences(projectRoot, projectDependencies)
            projectReferences := RestoreCommandKernels.DeduplicateProjectReferences(resolvedProjectReferences)

            propsPath := Path.Combine(objDir, "project.g.props")
            File.WriteAllText(
                propsPath,
                RestoreCommandKernels.GetGeneratedPropsText(
                    config.TargetFramework,
                    outputType,
                    projectName,
                    "il",
                    config.TestFramework,
                    baseSdk,
                    projectReferences))

            if !RestoreReferencedProjects(projectRoot, quiet, visitedProjectRoots, projectDependencies) {
                return false
            }

            if !quiet {
                print RestoreCommandKernels.GetGeneratedPropsMessage()
            }

            return true
        } catch ex: Exception {
            Console.Error.WriteLine(RestoreCommandKernels.GetFailedMessage(ex.Message))
            return false
        }
    }

    static func ResolveProjectReferences(projectRoot: string, dependencies: List<Reference>): string[] {
        resolvedProjectReferences := new string[](dependencies.Count)

        i := 0
        while i < dependencies.Count {
            reference := dependencies[i]
            projectPathText := reference.Project ?? ""
            projectPath := projectPathText
            if !Path.IsPathRooted(projectPathText) {
                projectPath = Path.Combine(projectRoot, projectPathText)
            }

            resolvedProjectReferences[i] = ProjectReferenceResolver.ResolveMsBuildProjectPath(projectPath)
            i = i + 1
        }

        return resolvedProjectReferences
    }

    static func RestoreReferencedProjects(
        projectRoot: string,
        quiet: bool,
        visitedProjectRoots: HashSet<string>,
        dependencies: List<Reference>): bool {
        i := 0
        while i < dependencies.Count {
            dependency := dependencies[i]
            referencedPath := dependency.Project ?? ""
            absoluteReferencePath := referencedPath
            if !Path.IsPathRooted(referencedPath) {
                absoluteReferencePath = Path.Combine(projectRoot, referencedPath)
            }

            referencedProjectRoot := Path.GetDirectoryName(Path.GetFullPath(absoluteReferencePath))
            if string.IsNullOrWhiteSpace(referencedProjectRoot) {
                i = i + 1
                continue
            }

            referencedProjectYml := Path.Combine(referencedProjectRoot ?? "", "project.yml")
            if !File.Exists(referencedProjectYml) {
                i = i + 1
                continue
            }

            if !RestoreRecursive(referencedProjectRoot ?? "", true, visitedProjectRoots) {
                return false
            }

            i = i + 1
        }

        return true
    }
}
