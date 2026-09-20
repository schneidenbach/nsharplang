using System;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Cli.Commands;

namespace NSharpLang.Cli;

partial class Program
{
    static int Main(string[] args)
        => InternalErrorBoundary.Execute(() => Execute(args));

    internal static int Execute(string[] args)
    {
        var commandKind = ProgramCommandKernels.GetCommandKind(args);

        if (commandKind == 29)
        {
            Console.WriteLine(ProgramCommandKernels.GetHelpText(GetVersion()));
            return 0;
        }

        if (commandKind == 30)
        {
            Console.WriteLine(ProgramCommandKernels.GetVersionText(GetVersion()));
            return 0;
        }

        return commandKind switch
        {
            1 => ProgramCommands.BuildCommand(GetCommandArgs(args)),
            2 => ProgramCommands.RunCommand(GetCommandArgs(args)),
            3 => ProgramCommands.PublishCommand(GetCommandArgs(args)),
            4 => ProgramCommands.NewCommand(GetCommandArgs(args)),
            5 => TestCommand(GetCommandArgs(args)),
            6 => ProgramCommands.FormatCommand(GetCommandArgs(args)),
            7 => Commands.LintCommand.Execute(GetCommandArgs(args)),
            8 => RestoreCommand.Execute(GetCommandArgs(args)),
            9 => CleanCommand.Execute(GetCommandArgs(args)),
            10 => WatchCommand.Execute(GetCommandArgs(args)),
            11 => DocCommand.Execute(GetCommandArgs(args)),
            12 => CompletionCommand.Execute(GetCommandArgs(args)),
            13 => Commands.CheckCommand.Execute(GetCommandArgs(args)),
            14 => FixCommand.Execute(GetCommandArgs(args)),
            15 => QueryCommand.Execute(GetCommandArgs(args)),
            16 => DaemonCommand.Execute(GetCommandArgs(args)),
            17 => AddCommand.Execute(GetCommandArgs(args)),
            18 => TidyCommand.Execute(GetCommandArgs(args)),
            19 => RemoveCommand.Execute(GetCommandArgs(args)),
            20 => UpdateCommand.Execute(GetCommandArgs(args)),
            21 => InitCommand.Execute(GetCommandArgs(args)),
            22 => EnvCommand.Execute(GetCommandArgs(args)),
            23 => DoctorCommand.Execute(GetCommandArgs(args)),
            24 => TreeCommand.Execute(GetCommandArgs(args)),
            25 => AuditCommand.Execute(GetCommandArgs(args)),
            26 => PackCommand.Execute(GetCommandArgs(args)),
            _ => CliError.Report(ProgramCommandKernels.GetUnknownCommandMessage(
                args.Length == 0 ? string.Empty : args[0]))
        };
    }

    private static string[] GetCommandArgs(string[] args)
        => args.Length <= 1 ? Array.Empty<string>() : args.Skip(1).ToArray();

    static int TestCommand(string[] args)
    {
        var testOptions = TestCommandKernels.GetOptionSummary(args);
        if (testOptions.ShowHelp)
        {
            Console.WriteLine(TestCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = TestCommandKernels.GetProjectRoot(testOptions.ProjectOption, Directory.GetCurrentDirectory());
        var outputMode = TestCommandKernels.GetOutputMode(testOptions.JsonOutput);

        // Parse timeout to milliseconds
        int? timeoutMs = null;
        if (testOptions.Timeout != null)
        {
            timeoutMs = TestCommandKernels.GetDurationMilliseconds(testOptions.Timeout);
            if (timeoutMs == null)
            {
                var message = TestCommandKernels.GetInvalidTimeoutMessage(testOptions.Timeout);
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, message);
                    return 1;
                }

                return CliError.Report(message);
            }
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            if (outputMode == 2) Console.WriteLine(TestCommandKernels.GetProjectStartMessage(projectRoot));

            if (testOptions.CollectCoverage || testOptions.CoverageReport)
            {
                var message = TestCommandKernels.GetCoverageUnsupportedMessage();
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, message);
                    return 1;
                }

                return CliError.Report(message);
            }

            // Find all .tests.nl files
            var testFiles = Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories);

            if (testFiles.Length == 0)
            {
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, true, Array.Empty<NativeTestResult>(), new NativeTestSummary(true, 0, 0, 0, 0));
                    return 0;
                }
                Console.WriteLine(TestCommandKernels.GetNoTestFilesMessage());
                return 0;
            }

            if (outputMode == 2) Console.WriteLine(TestCommandKernels.GetFoundTestFilesMessage(testFiles.Length));

            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
            CompilationBackendSelectionKernels.Validate(testOptions.BackendOption, projectConfig);

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
                sw);
        }
        catch (Exception ex)
        {
            if (outputMode == 2)
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)));
            if (outputMode == 1) { OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, ex.Message); return 1; }
            return CliError.Report(TestCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    internal static string GetVersion()
    {
        return typeof(Program).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            ?? typeof(Program).Assembly.GetName().Version?.ToString()
            ?? "unknown";
    }

}
