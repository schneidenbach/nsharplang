namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import NSharpLang.Compiler

// `nlc test`, WHOLE: option parsing through the kernels, the preflight refusals, the incremental
// build, the choice of runner, and the two output shapes.
//
// Every sentence, every JSON byte, every exit code and every filter rule is decided by
// `TestCommandKernels` in Compiler.Core. This owner is the ORDER those decisions are made in, plus
// the two things only a host can do: build the project and run the emitted assembly.
//
// This assembly exists so that xunit stays BELOW the CLI. `Compiler.dll` is loaded by the MSBuild
// task host inside every `dotnet build` of every N# project, is published with the LanguageServer
// and sits in the browser-wasm trim graph; a test framework must not travel there. Only
// `src/NSharpLang.Cli` references this project.
static class TestCommandHost {
    static func TestCommand(args: string[]): int {
        testOptions := TestCommandKernels.GetOptionSummary(args)
        if testOptions.ShowHelp {
            Console.WriteLine(TestCommandKernels.GetHelpText())
            return 0
        }

        projectRoot := TestCommandKernels.GetProjectRoot(testOptions.ProjectOption, Directory.GetCurrentDirectory())
        outputMode := TestCommandKernels.GetOutputMode(testOptions.JsonOutput)

        // Parse timeout to milliseconds
        timeoutMs: int? = null
        if testOptions.Timeout != null {
            timeoutMs = TestCommandKernels.GetDurationMilliseconds(testOptions.Timeout)
            if timeoutMs == null {
                message := TestCommandKernels.GetInvalidTimeoutMessage(testOptions.Timeout)
                if outputMode == 1 {
                    OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, message)
                    return 1
                }

                return CliError.Report(message)
            }
        }

        stopwatch := Stopwatch.StartNew()
        try {
            if outputMode == 2 {
                Console.WriteLine(TestCommandKernels.GetProjectStartMessage(projectRoot))
            }

            if testOptions.CollectCoverage || testOptions.CoverageReport {
                message := TestCommandKernels.GetCoverageUnsupportedMessage()
                if outputMode == 1 {
                    OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, message)
                    return 1
                }

                return CliError.Report(message)
            }

            // Find all .tests.nl files
            testFiles := Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories)

            if testFiles.Length == 0 {
                if outputMode == 1 {
                    OutputNativeTestJson(projectRoot, true, new NativeTestResult[](0), new NativeTestSummary(true, 0, 0, 0, 0), null)
                    return 0
                }
                Console.WriteLine(TestCommandKernels.GetNoTestFilesMessage())
                return 0
            }

            if outputMode == 2 {
                Console.WriteLine(TestCommandKernels.GetFoundTestFilesMessage(testFiles.Length))
            }

            projectConfig := ProjectFileParser.ParseFromDirectory(projectRoot)
            CompilationBackendSelectionKernels.Validate(testOptions.BackendOption, projectConfig)

            return TestWithIlBackend(
                projectRoot,
                projectConfig,
                testOptions.Filter,
                testOptions.Verbose,
                outputMode,
                timeoutMs,
                testOptions.NoCache,
                testOptions.CollectCoverage,
                testOptions.CoverageReport,
                stopwatch
            )
        } catch commandError: Exception {
            if outputMode == 2 {
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)))
            }
            if outputMode == 1 {
                OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, commandError.Message)
                return 1
            }
            return CliError.Report(TestCommandKernels.GetFailedMessage(commandError.Message))
        }
    }

    static func TestWithIlBackend(
        projectRoot: string,
        projectConfig: ProjectConfig?,
        filter: string?,
        verbose: bool,
        outputMode: int,
        timeoutMs: int?,
        noCache: bool,
        collectCoverage: bool,
        coverageReport: bool,
        stopwatch: Stopwatch
    ): int {
        projectYmlPath := TestCommandKernels.GetProjectYmlPath(projectRoot)
        if !File.Exists(projectYmlPath) {
            missingProjectMessage := TestCommandKernels.GetMissingProjectFileMessage()
            if TestCommandKernels.IsJsonOutputMode(outputMode) {
                OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, missingProjectMessage)
                return TestCommandKernels.GetExitCode(false)
            }

            return CliError.Report(missingProjectMessage)
        }

        if collectCoverage || coverageReport {
            coverageMessage := TestCommandKernels.GetCoverageUnsupportedMessage()
            if TestCommandKernels.IsJsonOutputMode(outputMode) {
                OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, coverageMessage)
                return TestCommandKernels.GetExitCode(false)
            }

            return CliError.Report(coverageMessage)
        }

        resolvedConfig := projectConfig ?? ProjectFileParser.Parse(projectYmlPath)
        testOutputDir := TestCommandKernels.GetTestOutputDirectory(projectRoot, resolvedConfig.TargetFramework)

        // `--no-cache` IS the whole cache story: deleting the test output directory is what stops
        // the incremental IL build from reusing it.
        if noCache && Directory.Exists(testOutputDir) {
            Directory.Delete(testOutputDir, true)
        }

        try {
            outputPath := CliIlBackend.BuildProjectWithIlBackendForCommand(
                projectRoot,
                resolvedConfig,
                TestCommandKernels.GetTestBuildConfiguration(),
                testOutputDir,
                true,
                verbose
            )

            if outputPath == null {
                buildFailedMessage := TestCommandKernels.GetBuildFailedMessage()
                if TestCommandKernels.IsJsonOutputMode(outputMode) {
                    OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, buildFailedMessage)
                    return TestCommandKernels.GetExitCode(false)
                }

                return CliError.Report(buildFailedMessage)
            }

            testRun := RunSelectedRunner(resolvedConfig, outputPath, filter, verbose, outputMode, timeoutMs)
            summary := TestCommandKernels.SummarizeNativeTestRun(testRun)

            if TestCommandKernels.IsJsonOutputMode(outputMode) {
                OutputNativeTestJson(projectRoot, summary.Ok, testRun.Results, summary, null)
            } else {
                Console.WriteLine(TestCommandKernels.GetSummaryMessage(summary.Passed, summary.Failed, summary.Skipped, summary.Total))
                Console.WriteLine(TestCommandKernels.GetCompletedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)))
            }

            return TestCommandKernels.GetExitCode(summary.Ok)
        } catch runError: Exception {
            if TestCommandKernels.IsTextOutputMode(outputMode) {
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)))
            }

            if TestCommandKernels.IsJsonOutputMode(outputMode) {
                OutputNativeTestJson(projectRoot, false, new NativeTestResult[](0), NativeTestSummary.EmptyFailure, runError.Message)
                return TestCommandKernels.GetExitCode(false)
            }

            return CliError.Report(TestCommandKernels.GetFailedMessage(runError.Message))
        }
    }

    // WHICH RUNNER, AND WHOSE STDOUT. In JSON mode the document has to be alone on stdout, so the
    // run itself writes to stderr and the original writer is restored BEFORE the envelope is
    // printed — a test's own `print` goes to stderr, the envelope goes to stdout, and a throwing
    // run still restores.
    static func RunSelectedRunner(
        projectConfig: ProjectConfig,
        outputPath: string,
        filter: string?,
        verbose: bool,
        outputMode: int,
        timeoutMs: int?
    ): NativeTestRun {
        stdout := Console.Out
        if TestCommandKernels.IsJsonOutputMode(outputMode) {
            Console.SetOut(Console.Error)
        }

        try {
            if TestCommandKernels.ShouldRunNUnit(projectConfig.TestFramework) {
                return ReflectionTestRunner.Run(outputPath, filter, verbose, timeoutMs)
            }

            return XunitTestRunner.Run(outputPath, filter, verbose, timeoutMs)
        } finally {
            Console.SetOut(stdout)
        }
    }

    // The N# outcome summary is REQUIRED, and the SIGNATURE is what requires it — not a sentence.
    static func OutputNativeTestJson(
        projectRoot: string,
        ok: bool,
        testResults: IReadOnlyList<NativeTestResult>,
        summary: NativeTestSummary,
        errorMessage: string?
    ) {
        Console.WriteLine(TestCommandKernels.NativeTestJson(projectRoot, ok, testResults, errorMessage, summary))
    }
}
