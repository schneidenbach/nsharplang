namespace NSharpLang.Cli

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Performance

class BuildOperandSummary {
    Count: int
    FirstOperandIndex: int

    constructor(count: int, firstOperandIndex: int) {
        Count = count
        FirstOperandIndex = firstOperandIndex
    }
}

class BuildCommandKernels {
    static func GetOperandSummary(args: string[]): BuildOperandSummary {
        length := args.Length
        if length == 0 {
            return new BuildOperandSummary(0, -1)
        }

        kindIds := new int[](length)
        nextIndices := new int[](length)
        previousIndices := new int[](length)
        nextOptionIndices := new int[](length)

        first := -1
        last := -1
        count := 0
        outputHead := -1
        outputTail := -1
        shortOutputHead := -1
        shortOutputTail := -1
        backendHead := -1
        backendTail := -1
        projectHead := -1
        projectTail := -1

        i := 0
        while i < length {
            kind := BuildArgumentKind(args[i])
            kindIds[i] = kind
            nextIndices[i] = -1
            previousIndices[i] = -1
            nextOptionIndices[i] = -1

            if kind == 5 {
                kindIds[i] = -1
                i = i + 1
                continue
            }

            if last >= 0 {
                nextIndices[last] = i
                previousIndices[i] = last
            } else {
                first = i
            }

            last = i
            count = count + 1

            if kind == 1 {
                if outputTail >= 0 {
                    nextOptionIndices[outputTail] = i
                } else {
                    outputHead = i
                }

                outputTail = i
            } else if kind == 2 {
                if shortOutputTail >= 0 {
                    nextOptionIndices[shortOutputTail] = i
                } else {
                    shortOutputHead = i
                }

                shortOutputTail = i
            } else if kind == 3 {
                if backendTail >= 0 {
                    nextOptionIndices[backendTail] = i
                } else {
                    backendHead = i
                }

                backendTail = i
            } else if kind == 4 {
                if projectTail >= 0 {
                    nextOptionIndices[projectTail] = i
                } else {
                    projectHead = i
                }

                projectTail = i
            }

            i = i + 1
        }

        firstOperandIndex := first
        pass := 1
        while pass <= 4 {
            sourceIndex := outputHead
            optionKind := 1
            if pass == 2 {
                sourceIndex = shortOutputHead
                optionKind = 2
            } else if pass == 3 {
                sourceIndex = backendHead
                optionKind = 3
            } else if pass == 4 {
                sourceIndex = projectHead
                optionKind = 4
            }

            while sourceIndex >= 0 {
                nextOptionIndex := nextOptionIndices[sourceIndex]
                if kindIds[sourceIndex] == optionKind {
                    valueIndex := nextIndices[sourceIndex]
                    if valueIndex >= 0 {
                        previousIndex := previousIndices[sourceIndex]
                        afterIndex := nextIndices[valueIndex]
                        if previousIndex >= 0 {
                            nextIndices[previousIndex] = afterIndex
                        } else {
                            firstOperandIndex = afterIndex
                        }

                        if afterIndex >= 0 {
                            previousIndices[afterIndex] = previousIndex
                        }

                        kindIds[sourceIndex] = -1
                        kindIds[valueIndex] = -1
                        count = count - 2
                    }
                }

                sourceIndex = nextOptionIndex
            }

            pass = pass + 1
        }

        return new BuildOperandSummary(count, firstOperandIndex)
    }

    static func GetOptionSummary(args: string[]): BuildOptionSummary {
        outputLong: string? = null
        outputShort: string? = null
        backend: string? = null
        project: string? = null
        release := false
        verbose := false
        timings := false
        perfReport := false
        aot := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            kind := BuildOptionSummaryKind(arg)
            if kind == 1 {
                if outputLong == null && i + 1 < args.Length {
                    outputLong = args[i + 1]
                }
            } else if kind == 2 {
                if outputShort == null && i + 1 < args.Length {
                    outputShort = args[i + 1]
                }
            } else if kind == 3 {
                if backend == null && i + 1 < args.Length {
                    backend = args[i + 1]
                }
            } else if kind == 4 {
                if project == null && i + 1 < args.Length {
                    project = args[i + 1]
                }
            } else if kind == 5 {
                release = true
            } else if kind == 6 {
                verbose = true
            } else if kind == 7 {
                timings = true
            } else if kind == 8 {
                perfReport = true
            } else if kind == 9 {
                aot = true
            } else if kind == 10 {
                showHelp = true
            }

            i = i + 1
        }

        output := outputShort
        if outputLong != null {
            output = outputLong
        }

        return new BuildOptionSummary(output, backend, project, release, verbose, timings, perfReport, aot, showHelp)
    }

    static func GetHelpText(): string {
        return "N# Build\n" + "\n" + "Usage: nlc build [file.nl] [options]\n" + "\n" + "Build a project or a single N# source file.\n" + "\n" + "When run in a directory with project.yml, compiles directly from project.yml\n" + "through the native IL backend. No user-authored .csproj is needed.\n" + "\n" + "Options:\n" + "  --backend <mode>   Compilation backend: il\n" + "  --project <dir>    Project root directory (default: current directory)\n" + "  --release          Build with Release configuration/output layout (default: Debug)\n" + "  --verbose          Show detailed build output\n" + "  --timings          Emit per-phase timing breakdown after build\n" + "  --perf-report      Emit a versioned JSON performance report after build\n" + "  --aot              Analyze for Native AOT safety; AOT blockers become build errors\n" + "  --output <path>    Output directory for build artifacts (-o shorthand)\n" + "  --define <symbol>  Define a conditional-compilation symbol for #if (-d shorthand);\n" + "                     repeatable, and accepts comma-separated lists\n" + "  --help, -h         Show this help text\n" + "\n" + "Conditional compilation:\n" + "  DEBUG is defined automatically for debug builds (omitted with --release).\n" + "  Project-wide symbols can also be set via 'defines:' in project.yml.\n" + "\n" + "Examples:\n" + "  nlc build              Build the current project\n" + "  nlc build --backend il Build the current project with the IL backend\n" + "  nlc build --release    Release configuration/output layout\n" + "  nlc build --verbose    Show detailed build output\n" + "  nlc build --timings    Show phase-level timing breakdown\n" + "  nlc build --perf-report Emit a JSON performance report\n" + "  nlc build --aot        Fail the build on Native AOT blockers\n" + "  nlc build -o ./dist    Build to a specific output directory\n" + "  nlc build --define FEATURE_X  Build with FEATURE_X defined\n" + "  nlc build Program.nl   Build a single file\n" + "\n" + "Exit codes:\n" + "  0  Build succeeded\n" + "  1  Build failed"
    }

    static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    static func GetFailedMessage(message: string): string {
        return "Build failed: " + message
    }

    static func GetProjectStartMessage(projectRoot: string): string {
        return "Building project in " + projectRoot + " with the IL backend..."
    }

    static func GetSingleFileStartMessage(sourceFile: string): string {
        return "Building " + sourceFile + " with the IL backend..."
    }

    static func GetMissingProjectFileMessage(): string {
        return "No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file."
    }

    static func GetFailedElapsedMessage(elapsedText: string): string {
        return "  Build failed in " + elapsedText
    }

    static func GetSuccessElapsedMessage(release: bool, elapsedText: string): string {
        configuration := "debug"
        if release {
            configuration = "release"
        }

        return "Build successful! (il, " + configuration + ") [" + elapsedText + "]"
    }

    static func GetSuccessMessage(release: bool): string {
        configuration := "debug"
        if release {
            configuration = "release"
        }

        return "Build successful! (il, " + configuration + ")"
    }

    static func GetOutputPathMessage(outputPath: string): string {
        return "Output: " + outputPath
    }

    static func GetProjectRoot(projectOption: string?, currentDirectory: string): string {
        if projectOption != null {
            return Path.GetFullPath(projectOption ?? "")
        }

        return currentDirectory
    }

    static func GetSourceDirectory(sourceFile: string, currentDirectory: string): string {
        return Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? currentDirectory
    }

    static func GetSourceFileAssemblyName(sourceFile: string): string {
        fileName := Path.GetFileName(sourceFile) ?? sourceFile
        dot := -1
        i := fileName.Length - 1
        while i >= 0 {
            if fileName[i] == '.' {
                dot = i
                break
            }

            i = i - 1
        }

        if dot <= 0 {
            return fileName
        }

        return fileName.Substring(0, dot)
    }

    static func NormalizeProjectRoot(projectRoot: string): string {
        return Path.GetFullPath(projectRoot)
    }

    static func GetTempBuildDirectory(tempRoot: string, uniqueName: string): string {
        return Path.Combine(tempRoot, "nlc-build-" + uniqueName)
    }

    static func GetTimingsMessage(resolveElapsed: string, compileElapsed: string, totalElapsed: string): string {
        return "Build timings:\n" + "  Resolve:    " + resolveElapsed + "\n" + "  Emit IL:    " + compileElapsed + "\n" + "  Total:      " + totalElapsed
    }

    // ── THE BUILD CONFIGURATION NAMES ─────────────────────────────────────────
    //
    // The configuration name picks the output DIRECTORY and, read back through
    // `ShouldApplyDebugDefine`, the `DEBUG` define. Those were two separately spelled answers —
    // `release ? "Release" : "Debug"` in the CLI and a bare `"Release"` here — so this is now one
    // owner and the predicate is DEFINED IN TERMS OF it rather than restating the word.
    static func GetConfigurationName(release: bool): string {
        if release {
            return "Release"
        }

        return "Debug"
    }

    static func ShouldApplyDebugDefine(configuration: string): bool {
        return !string.Equals(configuration, GetConfigurationName(true), StringComparison.OrdinalIgnoreCase)
    }

    // A build's exit code is decided by whether it produced an output assembly. This is the same
    // shape as `TestCommandKernels.GetExitCode`, and it replaces bare `1`s that carried no sentence
    // and therefore had nothing else classifying them.
    static func GetExitCode(built: bool): int {
        if built {
            return 0
        }

        return 1
    }

    static func GetOutputDirectory(projectRoot: string, configuration: string, targetFramework: string, outputDir: string?): string {
        if outputDir != null {
            return Path.GetFullPath(outputDir)
        }

        return CompilationReferenceResolverKernels.GetStableOutputDirectory(projectRoot, configuration, targetFramework)
    }

    static func ApplyEffectiveDefines(config: ProjectConfig, debug: bool, cliDefines: IReadOnlyList<string>?) {
        if debug && !ContainsDefine(config.Defines, "DEBUG") {
            config.Defines.Add("DEBUG")
        }

        if cliDefines == null {
            return
        }

        for symbol in cliDefines {
            if !String.IsNullOrWhiteSpace(symbol) && !ContainsDefine(config.Defines, symbol) {
                config.Defines.Add(symbol)
            }
        }
    }

    static func ToPerfReportFacts(report: SystemsReport): BuildPerfReportFacts {
        allocationSites := new List<PerfReportSite>()
        delegateSites := new List<PerfReportSite>()
        boxingSites := new List<PerfReportSite>()
        dispatchSites := new List<PerfReportSite>()
        closureCaptures := new List<PerfReportSite>()
        poolSites := new List<PerfReportSite>()
        resourceSites := new List<PerfReportSite>()
        boundaryLeakSites := new List<PerfReportSite>()
        hotReadinessSites := new List<PerfReportSite>()
        implicitTrapSites := new List<PerfReportSite>()

        for finding in report.Findings {
            site := new PerfReportSite(finding.Code, finding.Effect, finding.File, finding.Line, finding.Column, finding.Message, finding.Function, finding.Suggestion)

            AddPerfReportSite(site, allocationSites, delegateSites, boxingSites, dispatchSites, closureCaptures, poolSites, resourceSites, boundaryLeakSites, hotReadinessSites, implicitTrapSites)
        }

        trustedSites := new List<PerfReportTrustedSite>()
        for site in report.TrustedSites {
            trustedSites.Add(new PerfReportTrustedSite(site.Function, site.File, site.Line, site.Column, site.Owner, site.Review, site.Expires, site.HasUnsafe, site.BodyStatementCount))
        }

        return new BuildPerfReportFacts(allocationSites.ToArray(), delegateSites.ToArray(), boxingSites.ToArray(), dispatchSites.ToArray(), closureCaptures.ToArray(), poolSites.ToArray(), resourceSites.ToArray(), boundaryLeakSites.ToArray(), hotReadinessSites.ToArray(), implicitTrapSites.ToArray(), trustedSites.ToArray())
    }

    static func BuildOptionSummaryKind(arg: string): int {
        if arg == "--output" {
            return 1
        }

        if arg == "-o" {
            return 2
        }

        if arg == "--backend" {
            return 3
        }

        if arg == "--project" {
            return 4
        }

        if arg == "--release" {
            return 5
        }

        if arg == "--verbose" {
            return 6
        }

        if arg == "--timings" {
            return 7
        }

        if arg == "--perf-report" {
            return 8
        }

        if arg == "--aot" {
            return 9
        }

        if arg == "--help" || arg == "-h" {
            return 10
        }

        return 0
    }

    static func ContainsDefine(defines: List<string>, symbol: string): bool {
        for define in defines {
            if define == symbol {
                return true
            }
        }

        return false
    }

    static func AddPerfReportSite(site: PerfReportSite, allocationSites: List<PerfReportSite>, delegateSites: List<PerfReportSite>, boxingSites: List<PerfReportSite>, dispatchSites: List<PerfReportSite>, closureCaptures: List<PerfReportSite>, poolSites: List<PerfReportSite>, resourceSites: List<PerfReportSite>, boundaryLeakSites: List<PerfReportSite>, hotReadinessSites: List<PerfReportSite>, implicitTrapSites: List<PerfReportSite>) {
        if site.Effect == "allocation" {
            allocationSites.Add(site)
        } else if site.Effect == "delegate" {
            delegateSites.Add(site)
        } else if site.Effect == "boxing" {
            boxingSites.Add(site)
        } else if site.Effect == "dispatch" {
            dispatchSites.Add(site)
        } else if site.Effect == "closure" {
            closureCaptures.Add(site)
        } else if site.Effect == "pool" {
            poolSites.Add(site)
        } else if site.Effect == "resource" {
            resourceSites.Add(site)
        } else if site.Effect == "boundaryLeak" {
            boundaryLeakSites.Add(site)
        } else if site.Effect == "hotReadiness" {
            hotReadinessSites.Add(site)
        } else if site.Effect == "implicitTrap" {
            implicitTrapSites.Add(site)
        }
    }

    static func BuildArgumentKind(arg: string): int {
        if arg == "--output" {
            return 1
        }

        if arg == "-o" {
            return 2
        }

        if arg == "--backend" {
            return 3
        }

        if arg == "--project" {
            return 4
        }

        if arg == "--aot" || arg == "--release" || arg == "--timings" || arg == "--verbose" || arg == "--perf-report" {
            return 5
        }

        return 0
    }
}
