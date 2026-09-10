namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The fix command owns the complete discovery -> analysis -> safety -> write -> output route.
// Command-specific policy stays in FixCommandKernels; this owner only coordinates the existing
// compiler-service and edit engines and keeps writes transactional across all requested files.
class FixCommand {
    static func Execute(args: string[]): int {
        arguments := FixCommandArgumentKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            Console.WriteLine(FixCommandKernels.GetHelpText())
            return 0
        }

        dryRun := arguments.DryRun
        useText := FixCommandArgumentKernels.GetEffectiveOutputMode(arguments.UseText) == 2
        includeReviewNeeded := arguments.IncludeReviewNeeded
        fileArg := arguments.FileOption
        projectDir := FixCommandKernels.GetProjectDirectory(
            arguments.ProjectOption,
            arguments.PositionalProject,
            Directory.GetCurrentDirectory())

        if !Directory.Exists(projectDir) {
            return EmitError(useText, FixCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir), projectDir)
        }

        try {
            files := new List<string>()
            if fileArg != null {
                fullPath := FixCommandKernels.ResolveFilePath(projectDir, fileArg)
                if !File.Exists(fullPath) {
                    return EmitError(useText, FixCommandKernels.GetFileNotFoundMessage(fullPath), projectDir)
                }

                files.Add(fullPath)
            } else {
                config := ProjectFileParser.ParseFromDirectory(projectDir)
                if config == null {
                    defaultConfig := ProjectFileParser.CreateDefault(null)
                    sourceFiles := defaultConfig.GetSourceFiles(projectDir, false)
                    for sourceFile in sourceFiles {
                        files.Add(FixCommandKernels.GetSourceFilePath(sourceFile))
                    }
                } else {
                    sourceFiles := config.GetSourceFiles(projectDir, false)
                    for sourceFile in sourceFiles {
                        files.Add(FixCommandKernels.GetSourceFilePath(sourceFile))
                    }
                }
            }

            if files.Count == 0 {
                if useText {
                    Console.Error.WriteLine(FixCommandKernels.GetNoFilesFoundMessage())
                } else {
                    Console.Write(FixCommandKernels.ResultJson(
                        projectDir,
                        dryRun,
                        includeReviewNeeded,
                        new List<FixEntry>(),
                        new List<FixEntry>(),
                        0))
                }

                return 0
            }

            allResults := new List<FixEntry>()
            allApplied := new List<FixEntry>()
            pendingWrites := new List<FixPendingWrite>()
            filesModified := 0

            for filePath in files {
                source := File.ReadAllText(filePath)
                fixes := FixApplicator.GetFixesForFile(filePath, source)
                if fixes.Count == 0 {
                    continue
                }

                relativeFile := FixCommandKernels.GetRelativeFile(projectDir, filePath)
                safeActions := FixCommandKernels.FilterBySafety(fixes, includeReviewNeeded)

                for fix in fixes {
                    allResults.Add(FixCommandKernels.ToFixEntry(relativeFile, fix))
                }

                fileApplied := new List<FixEntry>(safeActions.Count)
                for fix in safeActions {
                    fileApplied.Add(FixCommandKernels.ToFixEntry(relativeFile, fix))
                }
                allApplied.AddRange(fileApplied)

                if fileApplied.Count > 0 {
                    allEdits := new List<TextEdit>()
                    for fix in safeActions {
                        for edit in fix.Edits {
                            allEdits.Add(edit)
                        }
                    }

                    orderedEdits := FixApplicatorCore.ValidateAndSortEdits(source, allEdits)
                    if dryRun {
                        filesModified = filesModified + 1
                    } else {
                        fixedSource := FixApplicatorCore.ApplyEdits(source, orderedEdits)
                        if fixedSource != source {
                            pendingWrites.Add(new FixPendingWrite(filePath, fixedSource))
                            filesModified = filesModified + 1
                        }
                    }
                }
            }

            if !dryRun {
                for pending in pendingWrites {
                    WriteAllTextAtomic(pending.File, pending.FixedSource)
                }
            }

            if useText {
                writer := Console.Error
                writer.Write(FixCommandKernels.ResultText(
                    allResults,
                    allApplied,
                    filesModified,
                    dryRun,
                    includeReviewNeeded))
            } else {
                Console.Write(FixCommandKernels.ResultJson(
                    projectDir,
                    dryRun,
                    includeReviewNeeded,
                    allResults,
                    allApplied,
                    filesModified))
            }

            return FixCommandKernels.GetExitCode(dryRun, filesModified)
        } catch ex: Exception {
            return EmitError(useText, FixCommandKernels.GetFailedMessage(ex.Message), projectDir)
        }
    }

    private static func EmitError(useText: bool, message: string, projectRoot: string?): int {
        if useText {
            Console.Error.WriteLine(message)
        } else {
            Console.Write(OutputFormatter.ErrorToJson("fix", message, projectRoot, null, null))
        }

        return 1
    }

    private static func WriteAllTextAtomic(path: string, contents: string) {
        tempPath := FixCommandKernels.GetAtomicTempPath(
            path,
            Directory.GetCurrentDirectory(),
            Guid.NewGuid().ToString("N"))

        try {
            File.WriteAllText(tempPath, contents)
            if !OperatingSystem.IsWindows() && File.Exists(path) {
                File.SetUnixFileMode(tempPath, File.GetUnixFileMode(path))
            }

            File.Move(tempPath, path, true)
        } finally {
            if File.Exists(tempPath) {
                File.Delete(tempPath)
            }
        }
    }
}

class FixPendingWrite {
    File: string
    FixedSource: string

    constructor(fileValue: string, fixedSource: string) {
        File = fileValue
        FixedSource = fixedSource
    }
}
