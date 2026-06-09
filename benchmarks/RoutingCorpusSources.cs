using System;
using System.Text;

namespace NSharpLang.Benchmarks;

// Shared parser-front-end kernel binding delegates (compiled from the .nl sources by the benchmark project and
// bound via Delegate.CreateDelegate), used by the columnar benchmark suite (e.g. ColumnarSemanticPassBenchmarks).
internal delegate int TokenizeMetadataDelegate(
    string source, int[] kinds, int[] starts, int[] valueLengths, int[] lines, int[] columns);

internal delegate int TopLevelDeclarationKindsDelegate(int[] tokenKinds, int count, int[] outKinds);

// Shared synthetic whole-file corpora for the columnar benchmark suite (e.g. ColumnarSemanticPassBenchmarks):
// supported-form N# sources used to measure kernel/pass throughput on realistic and steady-state input.
public enum RoutingCorpus
{
    Representative,
    LargeGenerated,
}

internal static class RoutingCorpusSources
{
    public static string Build(RoutingCorpus corpus) => corpus switch
    {
        RoutingCorpus.Representative => Representative(),
        RoutingCorpus.LargeGenerated => Large(40),
        _ => throw new ArgumentOutOfRangeException(nameof(corpus)),
    };

    // A small, realistic supported-form file: an import + a handful of functions exercising :=, while, if/else,
    // index/member access, calls, arithmetic/logical operators, and a hard cast.
    private static string Representative() =>
        "import System\n\n" +
        "func scan(data: int[], count: int, threshold: int): int {\n" +
        "    total := 0\n" +
        "    i := 0\n" +
        "    while i < count {\n" +
        "        x := data[i]\n" +
        "        if x > threshold && x < count {\n" +
        "            total = total + x * 2 - data[i + 1] % 3\n" +
        "        } else {\n" +
        "            total = total - x\n" +
        "        }\n" +
        "        i = i + 1\n" +
        "    }\n" +
        "    return total\n" +
        "}\n\n" +
        "func toCode(ch: char): int {\n" +
        "    return (int)ch\n" +
        "}\n";

    // Many functions, each with a supported-form body, to measure steady-state whole-file throughput.
    private static string Large(int funcs)
    {
        var sb = new StringBuilder();
        sb.Append("import System\n\n");
        for (var f = 0; f < funcs; f++)
        {
            sb.Append("func f").Append(f).Append("(data: int[], count: int, limit: int): int {\n");
            sb.Append("    acc := 0\n");
            sb.Append("    i := 0\n");
            sb.Append("    while i < count {\n");
            sb.Append("        v := data[i] + acc * 2\n");
            sb.Append("        if v > 0 && v < limit {\n");
            sb.Append("            acc = acc + v * 3 - 1\n");
            sb.Append("        } else {\n");
            sb.Append("            acc = acc - v\n");
            sb.Append("        }\n");
            sb.Append("        i = i + 1\n");
            sb.Append("    }\n");
            sb.Append("    return acc\n");
            sb.Append("}\n\n");
        }

        return sb.ToString();
    }
}
