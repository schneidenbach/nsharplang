using System;

namespace NSharpLang.Cli;

internal enum ProgramCommandKind
{
    Unknown = 0,
    Build = 1,
    Run = 2,
    Publish = 3,
    New = 4,
    Test = 5,
    Format = 6,
    Lint = 7,
    Restore = 8,
    Clean = 9,
    Watch = 10,
    Doc = 11,
    Completion = 12,
    Check = 13,
    Fix = 14,
    Query = 15,
    Daemon = 16,
    Add = 17,
    Tidy = 18,
    Remove = 19,
    Update = 20,
    Init = 21,
    Env = 22,
    Doctor = 23,
    Tree = 24,
    Audit = 25,
    Pack = 26,
    Export = 27,
    Help = 29,
    Version = 30,
    Transpile = 31
}

internal static class ProgramCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static ProgramCommandKind GetCommandKind(string[] args)
    {
        var value = RequiredBindings.CommandKind(args);
        if (!Enum.IsDefined(typeof(ProgramCommandKind), value))
            throw new InvalidOperationException("N# dogfood compiler services rejected the top-level CLI command routing result.");

        return (ProgramCommandKind)value;
    }

    internal static string GetVersionText(string version)
        => RequiredBindings.ProgramVersionText(version);

    internal static string GetHelpText(string version)
        => RequiredBindings.ProgramHelpText(version);

    internal static string GetTranspileRemovedMessage()
        => RequiredBindings.ProgramTranspileRemovedMessage();

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
            DogfoodKernelLoader.CreateDelegate<CliProgramTranspileRemovedMessage>(
                programType,
                "CliProgramTranspileRemovedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliProgramUnknownCommandMessage>(
                programType,
                "CliProgramUnknownCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliProgramErrorLine>(
                programType,
                "CliProgramErrorLine")));

    private delegate int CliProgramCommandKind(string[] args);
    private delegate string CliProgramVersionText(string version);
    private delegate string CliProgramHelpText(string version);
    private delegate string CliProgramTranspileRemovedMessage();
    private delegate string CliProgramUnknownCommandMessage(string command);
    private delegate string CliProgramErrorLine(string message);

    private sealed record Bindings(
        CliProgramCommandKind CommandKind,
        CliProgramVersionText ProgramVersionText,
        CliProgramHelpText ProgramHelpText,
        CliProgramTranspileRemovedMessage ProgramTranspileRemovedMessage,
        CliProgramUnknownCommandMessage ProgramUnknownCommandMessage,
        CliProgramErrorLine ProgramErrorLine);
}
