using System;

namespace NSharpLang.Cli;

internal static class RunCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetSourceOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.RunFirstOperandIndex(args);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
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
                DogfoodKernelLoader.CreateDelegate<CliRunFirstOperandIndex>(
                    programType,
                    "CliRunFirstOperandIndex"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliRunFirstOperandIndex(string[] args);

    private sealed record Bindings(CliRunFirstOperandIndex RunFirstOperandIndex);
}
