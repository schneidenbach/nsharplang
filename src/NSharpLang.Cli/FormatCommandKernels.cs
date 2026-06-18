using System;

namespace NSharpLang.Cli;

internal static class FormatCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryShouldFormatDiscoveredPath(string relativePath, out bool shouldFormat)
    {
        shouldFormat = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var result = bindings.ShouldFormatDiscoveredPath(relativePath);
            if (result is not 0 and not 1)
                return false;

            shouldFormat = result == 1;
            return true;
        }
        catch
        {
            shouldFormat = false;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliShouldFormatDiscoveredPath>(
                programType,
                "CliShouldFormatDiscoveredPath")));

    private delegate int CliShouldFormatDiscoveredPath(string relativePath);

    private sealed record Bindings(CliShouldFormatDiscoveredPath ShouldFormatDiscoveredPath);
}
