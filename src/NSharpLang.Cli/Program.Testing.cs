using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

partial class Program
{
    private static int TestWithIlBackend(
        string projectRoot,
        ProjectConfig? projectConfig,
        string? filter,
        bool verbose,
        bool jsonOutput,
        int? timeoutMs,
        bool noCache,
        bool collectCoverage,
        bool coverageReport,
        System.Diagnostics.Stopwatch stopwatch)
    {
        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (jsonOutput)
            {
                OutputTestJson(null, projectRoot, false, "IL-backed test runs require a project.yml file.");
                return 1;
            }

            return Error("IL-backed test runs require a project.yml file.");
        }

        var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
        if (restoreResult != 0)
        {
            if (!jsonOutput)
            {
                Console.WriteLine($"  Tests failed in {FormatElapsed(stopwatch.Elapsed)}");
            }

            if (jsonOutput)
            {
                OutputTestJson(null, projectRoot, false, "Failed to restore project configuration.");
                return 1;
            }

            return Error("Failed to restore project configuration.");
        }

        projectConfig ??= ProjectFileParser.Parse(projectYmlPath);
        var projectFile = EnsureProjectFiles(projectRoot, projectConfig);
        var artifactsDir = Path.Combine(Path.GetTempPath(), $"nlc-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(artifactsDir);

        try
        {
            var buildArgs = $"build \"{projectFile}\" -v q";
            if (noCache)
            {
                buildArgs += " --no-incremental";
            }
            buildArgs += $" {GetBackendMsBuildProperty(CompilationBackend.Il)}";

            var buildResult = DotnetRunner.Run(buildArgs, workingDirectory: projectRoot);
            if (buildResult.ExitCode != 0)
            {
                var message = $"Test build failed:{Environment.NewLine}{buildResult.Stderr}{buildResult.Stdout}";
                if (jsonOutput)
                {
                    OutputTestJson(null, projectRoot, false, message.Trim());
                    return 1;
                }

                return Error(message.Trim());
            }

            if (!jsonOutput)
            {
                Console.WriteLine();
            }

            var trxFile = Path.Combine(artifactsDir, "results.trx");
            var coverageFile = Path.Combine(artifactsDir, "coverage.opencover.xml");
            var testArgs = new List<string>
            {
                "test",
                $"\"{projectFile}\"",
                "--no-build",
                "-v",
                verbose ? "normal" : "minimal",
                GetBackendMsBuildProperty(CompilationBackend.Il)
            };

            var dotnetFilter = BuildDotnetTestFilter(filter);
            if (!string.IsNullOrWhiteSpace(dotnetFilter))
            {
                testArgs.Add("--filter");
                testArgs.Add($"\"{dotnetFilter}\"");
            }

            if (jsonOutput)
            {
                testArgs.Add("--logger");
                testArgs.Add($"\"trx;LogFileName={trxFile}\"");
            }

            if (collectCoverage)
            {
                testArgs.Add($"/p:CollectCoverage=true");
                testArgs.Add("/p:CoverletOutputFormat=opencover");
                testArgs.Add($"/p:CoverletOutput={coverageFile}");
                testArgs.Add("/p:ExcludeByFile=**/*.g.cs");
            }

            if (timeoutMs.HasValue)
            {
                testArgs.Add("--");
                testArgs.Add($"RunConfiguration.TestSessionTimeout={timeoutMs.Value}");
            }

            var commandLine = string.Join(" ", testArgs);
            int exitCode;
            if (jsonOutput)
            {
                exitCode = DotnetRunner.Run(commandLine, workingDirectory: projectRoot).ExitCode;
                OutputTestJson(trxFile, projectRoot, exitCode == 0);
            }
            else
            {
                exitCode = DotnetRunner.RunPassthrough(commandLine, workingDirectory: projectRoot, verbose: verbose);
            }

            if (collectCoverage && !jsonOutput && File.Exists(coverageFile))
            {
                OutputCoverageSummary(coverageFile);

                if (coverageReport)
                {
                    var reportDir = Path.Combine(projectRoot, "coverage-report");
                    GenerateCoverageReport(coverageFile, reportDir);
                }
            }

            if (!jsonOutput)
            {
                Console.WriteLine($"  Tests completed in {FormatElapsed(stopwatch.Elapsed)}");
            }

            return exitCode;
        }
        catch (Exception ex)
        {
            if (!jsonOutput)
            {
                Console.WriteLine($"  Tests failed in {FormatElapsed(stopwatch.Elapsed)}");
            }

            if (jsonOutput)
            {
                OutputTestJson(null, projectRoot, false, ex.Message);
                return 1;
            }

            return Error($"Test failed: {ex.Message}");
        }
        finally
        {
            CleanupDirectory(artifactsDir);
        }
    }

    private static string? BuildDotnetTestFilter(string? filter)
    {
        if (string.IsNullOrWhiteSpace(filter))
        {
            return null;
        }

        var filterParts = filter.Split('|', StringSplitOptions.RemoveEmptyEntries);
        var predicates = filterParts.Select(part =>
            $"(DisplayName~{part.Trim()}|FullyQualifiedName~{part.Trim()})");
        return string.Join("|", predicates);
    }
}
