using System;

namespace NSharpLang.Cli;

internal static class PublishCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetArgumentSummary(string[] args, out PublishArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length != 0)
            return false;

        var resultIndices = t_resultIndices ??= new int[8];
        try
        {
            var code = bindings.PublishOptionsInto(args, resultIndices);
            if (code < 0 || code > 4)
                return false;

            var validationError = GetValidationError(args, code, resultIndices[7]);
            if (validationError != null)
            {
                summary = new PublishArgumentSummary(
                    validationError,
                    null,
                    null,
                    "Release",
                    null,
                    null,
                    false,
                    false);
                return true;
            }

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var configuration)
                || !TryGetOptionalArg(args, resultIndices[3], out var output)
                || !TryGetOptionalArg(args, resultIndices[4], out var runtime))
            {
                summary = default;
                return false;
            }

            summary = new PublishArgumentSummary(
                null,
                projectOption,
                backendOption,
                configuration ?? "Release",
                output,
                runtime,
                resultIndices[5] != 0,
                resultIndices[6] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    private static string? GetValidationError(string[] args, int code, int errorArgIndex)
    {
        if (code == 0)
            return null;

        if (code == 2)
        {
            return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.";
        }

        if (errorArgIndex < 0 || errorArgIndex >= args.Length)
            return null;

        return code switch
        {
            1 => $"Option '{args[errorArgIndex]}' requires a value.",
            3 => $"Unknown publish option '{args[errorArgIndex]}'. Run 'nlc publish --help' for supported options.",
            4 => $"Unexpected publish argument '{args[errorArgIndex]}'. Run 'nlc publish --help' for usage.",
            _ => null
        };
    }

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<CliPublishOptionsInto>(
                    programType,
                    "CliPublishOptionsInto"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliPublishOptionsInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliPublishOptionsInto PublishOptionsInto);
}
