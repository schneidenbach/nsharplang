namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Performance

// A workspace owns independent N# programs. The nearest project.yml owns each source path, while
// files outside every member boundary remain with the requested root project.
class CheckWorkspaceProject {
    ProjectRoot: string
    Config: ProjectConfig?
    ConfigError: string?
    SourceFiles: string[]

    constructor(ProjectRoot: string, Config: ProjectConfig?, ConfigError: string?, SourceFiles: string[]) {
        this.ProjectRoot = ProjectRoot
        this.Config = Config
        this.ConfigError = ConfigError
        this.SourceFiles = SourceFiles
    }
}

class CheckWorkspacePlan {
    Projects: List<CheckWorkspaceProject>
    ConflictMessage: string?

    constructor(Projects: List<CheckWorkspaceProject>, ConflictMessage: string?) {
        this.Projects = Projects
        this.ConflictMessage = ConflictMessage
    }
}

class CheckWorkspaceProjectResult {
    ProjectRoot: string
    CheckedFiles: int
    Diagnostics: List<DiagnosticResult>
    Summary: DiagnosticSummary
    ErrorMessage: string?
    SystemsReport: SystemsReport?

    constructor(
        ProjectRoot: string,
        CheckedFiles: int,
        Diagnostics: List<DiagnosticResult>,
        Summary: DiagnosticSummary,
        ErrorMessage: string?,
        SystemsReport: SystemsReport?
    ) {
        this.ProjectRoot = ProjectRoot
        this.CheckedFiles = CheckedFiles
        this.Diagnostics = Diagnostics
        this.Summary = Summary
        this.ErrorMessage = ErrorMessage
        this.SystemsReport = SystemsReport
    }

    Succeeded: bool => ErrorMessage == null && Summary.Errors == 0
}

static class CheckWorkspacePlanner {
    static func Discover(projectRoot: string): CheckWorkspacePlan {
        normalizedRoot := Path.GetFullPath(projectRoot)
        roots := new List<string>()
        roots.Add(normalizedRoot)
        roots.AddRange(new ProjectConfig().DiscoverNestedProjectRoots(normalizedRoot))

        configs := new List<ProjectConfig?>()
        configErrors := new List<string?>()
        configIndex := 0
        while configIndex < roots.Count {
            configs.Add(null)
            configErrors.Add(null)
            configIndex = configIndex + 1
        }
        index := 0
        while index < roots.Count {
            projectYml := Path.Combine(roots[index], "project.yml")
            if File.Exists(projectYml) {
                try {
                    configs[index] = ProjectFileParser.ParseFromDirectory(roots[index])
                } catch ex: Exception {
                    configErrors[index] = ex.Message
                }
            }
            index = index + 1
        }

        filesByProject := new List<List<string>>()
        index = 0
        while index < roots.Count {
            filesByProject.Add(new List<string>())
            index = index + 1
        }

        for sourceFile in ProjectConfig.EnumerateSourceFileArray(normalizedRoot) {
            ownerIndex := FindNearestProjectOwner(sourceFile, roots)
            filesByProject[ownerIndex].Add(sourceFile)
        }

        projects := new List<CheckWorkspaceProject>()
        claims := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        conflictMessage: string? = null
        index = 0
        while index < roots.Count {
            config := configs[index]
            filterConfig := config
            if filterConfig == null {
                filterConfig = ProjectFileParser.CreateDefault(null)
            }

            sourceFiles := ProjectSourceFileFilter.Filter(
                filesByProject[index].ToArray(),
                roots[index],
                filterConfig.Exclude.ToArray(),
                true
            )

            for sourceFile in sourceFiles {
                fullPath := Path.GetFullPath(sourceFile)
                existingOwner := ""
                if claims.TryGetValue(fullPath, out existingOwner) {
                    conflictMessage = GetConflictMessage(fullPath, existingOwner, roots[index])
                    break
                }
                claims.Add(fullPath, roots[index])
            }

            // Keep the workspace root as a member when it has project configuration or owns loose
            // source. A source-free directory with no project.yml is only a container for members.
            if index > 0 || File.Exists(Path.Combine(roots[index], "project.yml")) || sourceFiles.Length > 0 {
                projects.Add(new CheckWorkspaceProject(
                    roots[index],
                    config,
                    configErrors[index],
                    CanonicalSourceOrder.Sort(sourceFiles).ToArray()
                ))
            }
            index = index + 1
        }

        return new CheckWorkspacePlan(projects, conflictMessage)
    }

    private static func FindNearestProjectOwner(sourceFile: string, roots: IReadOnlyList<string>): int {
        fullPath := Path.GetFullPath(sourceFile)
        ownerIndex := 0
        ownerLength := roots[0].Length
        index := 1
        while index < roots.Count {
            root := roots[index]
            if root.Length > ownerLength && IsWithinProjectRoot(fullPath, root) {
                ownerIndex = index
                ownerLength = root.Length
            }
            index = index + 1
        }
        return ownerIndex
    }

    private static func IsWithinProjectRoot(path: string, projectRoot: string): bool {
        boundary := projectRoot
        if !boundary.EndsWith(Path.DirectorySeparatorChar.ToString()) {
            boundary = boundary + Path.DirectorySeparatorChar.ToString()
        }
        return path.StartsWith(boundary, StringComparison.OrdinalIgnoreCase)
    }

    private static func GetConflictMessage(sourceFile: string, firstProject: string, secondProject: string): string {
        return CheckCommandKernels.GetWorkspaceProjectConflictMessage(sourceFile, firstProject, secondProject)
    }
}
