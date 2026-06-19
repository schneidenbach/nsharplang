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

    internal static bool TryGetCommandKind(string[] args, out ProgramCommandKind commandKind)
    {
        commandKind = ProgramCommandKind.Unknown;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var value = bindings.CommandKind(args);
            if (!Enum.IsDefined(typeof(ProgramCommandKind), value))
                return false;

            commandKind = (ProgramCommandKind)value;
            return true;
        }
        catch
        {
            commandKind = ProgramCommandKind.Unknown;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliProgramCommandKind>(
                programType,
                "CliProgramCommandKind")));

    private delegate int CliProgramCommandKind(string[] args);

    private sealed record Bindings(CliProgramCommandKind CommandKind);
}
