namespace NSharpLang.Cli

import System
import NSharpLang.Cli.Commands

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
static class CliPipeline {
    static func Execute(args: string[], version: string): int {
        commandKind := ProgramCommandKernels.GetCommandKind(args)

        if commandKind == 29 {
            Console.WriteLine(ProgramCommandKernels.GetHelpText(version))
            return 0
        }

        if commandKind == 30 {
            Console.WriteLine(ProgramCommandKernels.GetVersionText(version))
            return 0
        }

        if commandKind == 1 {
            return ProgramCommands.BuildCommand(GetCommandArgs(args))
        }
        if commandKind == 2 {
            return ProgramCommands.RunCommand(GetCommandArgs(args))
        }
        if commandKind == 3 {
            return ProgramCommands.PublishCommand(GetCommandArgs(args))
        }
        if commandKind == 4 {
            return ProgramCommands.NewCommand(GetCommandArgs(args))
        }
        if commandKind == 5 {
            return TestCommandHost.TestCommand(GetCommandArgs(args))
        }
        if commandKind == 6 {
            return ProgramCommands.FormatCommand(GetCommandArgs(args))
        }
        if commandKind == 7 {
            return LintCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 8 {
            return RestoreCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 9 {
            return CleanCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 10 {
            return WatchCommandHost.Execute(GetCommandArgs(args), version)
        }
        if commandKind == 11 {
            return DocCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 12 {
            return CompletionCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 13 {
            return CheckCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 14 {
            return FixCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 15 {
            return QueryCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 16 {
            return DaemonCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 17 {
            return AddCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 18 {
            return TidyCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 19 {
            return RemoveCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 20 {
            return UpdateCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 21 {
            return InitCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 22 {
            return EnvCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 23 {
            return DoctorCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 24 {
            return TreeCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 25 {
            return AuditCommand.Execute(GetCommandArgs(args))
        }
        if commandKind == 26 {
            return PackCommand.Execute(GetCommandArgs(args))
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
