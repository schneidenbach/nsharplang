using System;

namespace NSharpLang.Cli;

internal static class ProgramCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static int GetCommandKind(string[] args)
        => RequiredBindings.CommandKind(args);

    internal static string GetVersionText(string version)
        => RequiredBindings.ProgramVersionText(version);

    internal static string GetHelpText(string version)
        => RequiredBindings.ProgramHelpText(version);

    internal static string GetUnknownCommandMessage(string command)
        => RequiredBindings.ProgramUnknownCommandMessage(command);

    internal static string GetErrorLine(string message)
        => RequiredBindings.ProgramErrorLine(message);

    private static Bindings RequiredBindings
        => s_bindings.Value
           ?? throw new InvalidOperationException("N# dogfood compiler services are required for top-level CLI command text.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliProgramCommandKind>(
                programType,
                "CliProgramCommandKind"),
            DogfoodKernelLoader.CreateDelegate<CliProgramVersionText>(
                programType,
                "CliProgramVersionText"),
            DogfoodKernelLoader.CreateDelegate<CliProgramHelpText>(
                programType,
                "CliProgramHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliProgramUnknownCommandMessage>(
                programType,
                "CliProgramUnknownCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliProgramErrorLine>(
                programType,
                "CliProgramErrorLine")));

    private delegate int CliProgramCommandKind(string[] args);
    private delegate string CliProgramVersionText(string version);
    private delegate string CliProgramHelpText(string version);
    private delegate string CliProgramUnknownCommandMessage(string command);
    private delegate string CliProgramErrorLine(string message);

    private sealed record Bindings(
        CliProgramCommandKind CommandKind,
        CliProgramVersionText ProgramVersionText,
        CliProgramHelpText ProgramHelpText,
        CliProgramUnknownCommandMessage ProgramUnknownCommandMessage,
        CliProgramErrorLine ProgramErrorLine);
}
