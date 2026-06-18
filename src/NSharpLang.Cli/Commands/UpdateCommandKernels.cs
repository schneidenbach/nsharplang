using System;

namespace NSharpLang.Cli.Commands;

internal static class UpdateCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetTargetPackage(string[] args, out string? package)
    {
        package = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.FirstPositionalArgIndex(args, Array.Empty<string>());
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            package = args[index];
            return true;
        }
        catch
        {
            package = null;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliFirstPositionalArgIndex>(
                programType,
                "CliFirstPositionalArgIndex")));

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private sealed record Bindings(CliFirstPositionalArgIndex FirstPositionalArgIndex);
}
