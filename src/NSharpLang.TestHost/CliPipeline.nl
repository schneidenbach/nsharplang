namespace NSharpLang.Cli

import System
import System.Diagnostics
import System.IO
import System.Runtime.CompilerServices
import NSharpLang.Cli.Commands
import NSharpLang.Cli.Daemon
import NSharpLang.Compiler

// THE `nlc` DISPATCH PIPELINE.
//
// `ProgramCommandKernels.GetCommandKind` turns the argument vector into a command NUMBER, and this
// owner is the one place that number becomes a call. Every arm is already an N# owner; what used to
// keep this switch in C# was `nlc test`, which is now `TestCommandHost` in this same assembly.
//
// THE VERSION IS A PARAMETER, NOT A LOOKUP. `nlc --version` and `nlc help` report the version of
// `Cli.dll` — the assembly the whole gate greps for provenance — and only the C# entry point can
// read its own assembly's `AssemblyInformationalVersionAttribute`. So `Main` reads it and hands it
// here; nothing in this assembly asks a second time, and the answer cannot drift between the two
// sentences that print it.
//
// `--stats` IS THE ONE OPTION THIS OWNER READS ITSELF. It belongs to no single command: it measures
// whichever of `build`, `check` or `test` runs, so it is split out of the command's arguments here
// (`CliStatsKernels.Extract`), the command runs exactly as it would without it, and the stats line
// is written after it returns.
static class CliPipeline {

    // DAEMON FIRST. A routed command (`check`, `build`, `test`, `run`, `format`, `lint`, `fix`) is
    // offered to the workspace server before it runs here; the server answers with the exit code of
    // the same dispatch below, run on this process's behalf, or declines and the command runs here
    // exactly as it always has. `DaemonExecKernels` owns which commands route and every switch that
    // turns routing off.
    //
    // THE FRONT DOOR COMES FIRST. A NativeAOT `nlc` is only the front door (see `FrontDoor`): it
    // answers `--version` and help itself and hands everything else, daemon routing included, to the
    // JIT-compiled compiler host it execs.
    static func Execute(args: string[], version: string): int {
        // This test is a compile-time constant in a NativeAOT image, and it stands ALONE so the AOT
        // compiler can fold it and trim the compiler and the daemon client out of the native image;
        // folded into one condition with the force switch it would not.
        if !RuntimeFeature.IsDynamicCodeSupported {
            return FrontDoor.Execute(args, version)
        }

        if FrontDoor.IsForced() {
            return FrontDoor.Execute(args, version)
        }

        DaemonBuildIdentity.SetCliVersion(version)
        if TestWorkerHost.IsWorkerInvocation(args) {
            return TestWorkerHost.Run()
        }

        routedExitCode := 0
        if DaemonExecClient.TryExecute(args, version, out routedExitCode) {
            return routedExitCode
        }

        localArgs := args
        if args.Length > 0 && DaemonExecKernels.IsRoutedCommandName(args[0]) {
            localArgs = DaemonExecKernels.StripNoDaemonFlag(args)
        }

        return ExecuteLocal(localArgs, version)
    }

    // The dispatch itself: what an `nlc` process runs for itself, and what the workspace server runs
    // for a client.
    static func ExecuteLocal(args: string[], version: string): int {
        commandKind := ProgramCommandKernels.GetCommandKind(args)
        stats := CliStatsKernels.Extract(GetCommandArgs(args))
        if !stats.Requested {
            return Dispatch(commandKind, args, stats.CommandArgs, version)
        }

        if stats.Error != null {
            return CliError.Report(stats.Error ?? "")
        }

        if !CliStatsKernels.SupportsStats(commandKind) {
            return CliError.Report(CliStatsKernels.UnsupportedCommandMessage(args[0]))
        }

        return ExecuteWithStats(commandKind, args, stats, version)
    }

    static func ExecuteWithStats(commandKind: int, args: string[], stats: CliStatsRequest, version: string): int {
        // IN THE WORKSPACE SERVER the counters are already this request's alone (a delta, and one
        // command runs at a time), but the process's CPU total is the server's whole life, so the CPU
        // figure becomes this request's delta too. In-process it stays the process total, start-up
        // included, exactly as before.
        cpuBaselineTicks := 0L
        if CliInvocationContext.IsRemoteInvocation() {
            baselineProcess := Process.GetCurrentProcess()
            cpuBaselineTicks = baselineProcess.TotalProcessorTime.Ticks
            baselineProcess.Dispose()
        }

        // The phase ledger rides along: the same rows `--timings` prints, as the line's `phases`.
        CompilerPhaseTimings.Enable()
        before := CompilerWorkCounters.Shared.Snapshot()
        elapsed := Stopwatch.StartNew()
        exitCode := Dispatch(commandKind, args, stats.CommandArgs, version)
        elapsed.Stop()
        counters := CompilerWorkCounters.Shared.Snapshot().Since(before)

        process := Process.GetCurrentProcess()
        process.Refresh()
        json := CliStatsKernels.ToJson(
            args[0].ToLowerInvariant(),
            exitCode,
            elapsed.ElapsedMilliseconds,
            (process.TotalProcessorTime.Ticks - cpuBaselineTicks) / TimeSpan.TicksPerMillisecond,
            process.PeakWorkingSet64,
            counters,
            CompilerPhaseTimings.Snapshot()
        )
        process.Dispose()

        outputPath := stats.OutputPath
        if outputPath == null {
            Console.Error.WriteLine(json)
            return exitCode
        }

        try {
            File.WriteAllText(outputPath ?? "", json + "\n")
        } catch writeFailure: Exception {
            Console.Error.WriteLine("Could not write --stats to " + (outputPath ?? "") + ": " + writeFailure.Message)
        }

        return exitCode
    }

    static func Dispatch(commandKind: int, args: string[], commandArgs: string[], version: string): int {
        if commandKind == 29 {
            Console.WriteLine(ProgramCommandKernels.GetHelpText(version))
            return 0
        }

        if commandKind == 30 {
            Console.WriteLine(ProgramCommandKernels.GetVersionText(version))
            return 0
        }

        if commandKind == 1 {
            return ProgramCommands.BuildCommand(commandArgs)
        }
        if commandKind == 2 {
            return ProgramCommands.RunCommand(commandArgs)
        }
        if commandKind == 3 {
            return ProgramCommands.PublishCommand(commandArgs)
        }
        if commandKind == 4 {
            return ProgramCommands.NewCommand(commandArgs)
        }
        if commandKind == 5 {
            return TestCommandHost.TestCommand(commandArgs)
        }
        if commandKind == 6 {
            return ProgramCommands.FormatCommand(commandArgs)
        }
        if commandKind == 7 {
            return LintCommand.Execute(commandArgs)
        }
        if commandKind == 8 {
            return RestoreCommand.Execute(commandArgs)
        }
        if commandKind == 9 {
            return CleanCommand.Execute(commandArgs)
        }
        if commandKind == 10 {
            return WatchCommandHost.Execute(commandArgs, version)
        }
        if commandKind == 11 {
            return DocCommand.Execute(commandArgs)
        }
        if commandKind == 12 {
            return CompletionCommand.Execute(commandArgs)
        }
        if commandKind == 13 {
            return CheckCommand.Execute(commandArgs)
        }
        if commandKind == 14 {
            return FixCommand.Execute(commandArgs)
        }
        if commandKind == 15 {
            return QueryCommand.Execute(commandArgs)
        }
        if commandKind == 16 {
            DaemonExecHost.Configure(version, serverArgs => CliPipeline.ExecuteLocal(serverArgs, version))
            DaemonExecHost.AddWarmupHook(() => TestWorkerHost.Replenish())
            return DaemonCommand.Execute(commandArgs)
        }
        if commandKind == 17 {
            return AddCommand.Execute(commandArgs)
        }
        if commandKind == 18 {
            return TidyCommand.Execute(commandArgs)
        }
        if commandKind == 19 {
            return RemoveCommand.Execute(commandArgs)
        }
        if commandKind == 20 {
            return UpdateCommand.Execute(commandArgs)
        }
        if commandKind == 21 {
            return InitCommand.Execute(commandArgs)
        }
        if commandKind == 22 {
            return EnvCommand.Execute(commandArgs)
        }
        if commandKind == 23 {
            return DoctorCommand.Execute(commandArgs)
        }
        if commandKind == 24 {
            return TreeCommand.Execute(commandArgs)
        }
        if commandKind == 25 {
            return AuditCommand.Execute(commandArgs)
        }
        if commandKind == 26 {
            return PackCommand.Execute(commandArgs)
        }

        firstArgument := ""
        if args.Length != 0 {
            firstArgument = args[0]
        }

        return CliError.Report(ProgramCommandKernels.GetUnknownCommandMessage(firstArgument))
    }

    static func GetCommandArgs(args: string[]): string[] {
        if args.Length <= 1 {
            return new string[](0)
        }

        commandArgs := new string[](args.Length - 1)
        index := 1
        while index < args.Length {
            commandArgs[index - 1] = args[index]
            index = index + 1
        }

        return commandArgs
    }
}
