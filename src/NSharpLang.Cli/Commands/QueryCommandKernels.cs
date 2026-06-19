using System;

namespace NSharpLang.Cli.Commands;

internal readonly record struct QueryDaemonParameterSummary(
    string? File,
    string? Pos,
    string? Name,
    string? Kind,
    string? Severity,
    bool IncludeKeywords,
    bool Clusters);

internal static class QueryCommandKernels
{
    [ThreadStatic]
    private static int[]? t_resultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetDaemonParameterSummary(string[] args, out QueryDaemonParameterSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_resultIndices ??= new int[7];
        try
        {
            var code = bindings.QueryDaemonParameterSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var file)
                || !TryGetOptionalArg(args, resultIndices[1], out var pos)
                || !TryGetOptionalArg(args, resultIndices[2], out var name)
                || !TryGetOptionalArg(args, resultIndices[3], out var kind)
                || !TryGetOptionalArg(args, resultIndices[4], out var severity))
            {
                summary = default;
                return false;
            }

            summary = new QueryDaemonParameterSummary(
                file,
                pos,
                name,
                kind,
                severity,
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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliQueryDaemonParameterSummaryInto>(
                programType,
                "CliQueryDaemonParameterSummaryInto")));

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

    private delegate int CliQueryDaemonParameterSummaryInto(string[] args, int[] resultIndices);

    private sealed record Bindings(CliQueryDaemonParameterSummaryInto QueryDaemonParameterSummary);
}
