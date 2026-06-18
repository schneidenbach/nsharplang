using System;

namespace NSharpLang.Cli.Commands;

internal static class FixCommandArgumentKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetProjectOperand(
        string[] args,
        string[] optionsWithValues,
        out string? project)
    {
        project = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            project = args[index];
            return true;
        }
        catch
        {
            project = null;
            return false;
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                    programType,
                    "CliFirstPositionalArgIndex"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private sealed record Bindings(CliFirstPositionalArgIndex FirstPositionalArgIndex);
}
