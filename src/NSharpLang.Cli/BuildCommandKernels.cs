using System;
using System.IO;
using System.Reflection;

namespace NSharpLang.Cli;

internal static class BuildCommandKernels
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static OperandScratch? t_operandScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            firstOperandIndex = bindings.BuildFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            count = firstOperandIndex >= 0 ? 1 : 0;
            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<CliBuildFirstOperandIndexInto>(
                    programType,
                    "CliBuildFirstOperandIndexInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int CliBuildFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private sealed record Bindings(CliBuildFirstOperandIndexInto BuildFirstOperandIndex);

    private sealed class OperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
                KindIds = new int[count];

            if (NextIndices.Length != count)
                NextIndices = new int[count];

            if (NextOptionIndices.Length != count)
                NextOptionIndices = new int[count];

            if (PreviousIndices.Length != count)
                PreviousIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }
}
