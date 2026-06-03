using System;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Baseline corpus for rewriting compiler services in N#.
///
/// This benchmark intentionally starts with the current C# lexer only. A ported N# lexer
/// candidate must add a matching benchmark over the same corpus and return the same token count.
/// The dogfood rewrite gate is C# mean / N# mean >= <see cref="RequiredNSharpSpeedup"/>.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerBenchmarks
{
    public const double RequiredNSharpSpeedup = 5.0;

    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = Corpus switch
        {
            CompilerLexerCorpus.Representative => BuildRepresentativeCorpus(),
            CompilerLexerCorpus.LargeGenerated => BuildLargeGeneratedCorpus(),
            _ => throw new InvalidOperationException($"Unknown lexer corpus: {Corpus}")
        };
    }

    [Benchmark(Baseline = true)]
    public int CSharpLexer_Tokenize()
    {
        var lexer = new Lexer(_source, $"{Corpus}.nl");
        return lexer.Tokenize().Count;
    }

    private static string BuildRepresentativeCorpus()
    {
        var builder = new StringBuilder(capacity: 8 * 1024);
        builder.AppendLine("import System");
        builder.AppendLine("import System.Collections.Generic");
        builder.AppendLine();
        builder.AppendLine("package CompilerDogfood");
        builder.AppendLine();
        builder.AppendLine("// Single-line comments and doc comments are preserved for formatter trivia.");
        builder.AppendLine("/// <summary>A representative lexer service input.</summary>");
        builder.AppendLine("class DiagnosticFormatter {");
        builder.AppendLine("    cache: Dictionary<string, string> = new Dictionary<string, string>()");
        builder.AppendLine("    readonly prefix: string");
        builder.AppendLine();
        builder.AppendLine("    constructor(prefix: string) {");
        builder.AppendLine("        this.prefix = prefix");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    func Format(code: string, message: string, line: int, column: int): string {");
        builder.AppendLine("        if code == \"\" {");
        builder.AppendLine("            return $\"[{prefix}] {line}:{column} {message}\"");
        builder.AppendLine("        }");
        builder.AppendLine();
        builder.AppendLine("        return $\"[{prefix}:{code}] {line}:{column} {message}\"");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    func Classify(severity: int): string {");
        builder.AppendLine("        return match severity {");
        builder.AppendLine("            0 => \"info\",");
        builder.AppendLine("            1 => \"warning\",");
        builder.AppendLine("            2 => \"error\",");
        builder.AppendLine("            _ => \"unknown\"");
        builder.AppendLine("        }");
        builder.AppendLine("    }");
        builder.AppendLine("}");
        builder.AppendLine();
        builder.AppendLine("func tokenizeProbe(input: string): int {");
        builder.AppendLine("    total := 0");
        builder.AppendLine("    for i := 0; i < input.Length; i++ {");
        builder.AppendLine("        ch := input[i]");
        builder.AppendLine("        if ch == ' ' || ch == '\\n' || ch == '\\t' {");
        builder.AppendLine("            continue");
        builder.AppendLine("        }");
        builder.AppendLine();
        builder.AppendLine("        total += 1");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    return total");
        builder.AppendLine("}");
        builder.AppendLine();
        builder.AppendLine("func rawText(): string {");
        builder.AppendLine("    return \"\"\"");
        builder.AppendLine("This block forces raw-string scanning, CR/LF accounting, and indentation retention.");
        builder.AppendLine("{ \"diagnostic\": \"NL001\", \"message\": \"unused local\" }");
        builder.AppendLine("\"\"\"");
        builder.AppendLine("}");
        return builder.ToString();
    }

    private static string BuildLargeGeneratedCorpus()
    {
        var builder = new StringBuilder(capacity: 512 * 1024);
        builder.AppendLine("import System");
        builder.AppendLine("import System.Collections.Generic");
        builder.AppendLine("package CompilerDogfood.Generated");
        builder.AppendLine();

        for (var i = 0; i < 500; i++)
        {
            builder.AppendLine($"class GeneratedService{i} {{");
            builder.AppendLine("    readonly name: string");
            builder.AppendLine("    items: List<string> = new List<string>()");
            builder.AppendLine();
            builder.AppendLine($"    constructor() {{");
            builder.AppendLine($"        name = \"GeneratedService{i}\"");
            builder.AppendLine("    }");
            builder.AppendLine();
            builder.AppendLine("    func Add(value: string) {");
            builder.AppendLine("        if value == null || value.Length == 0 {");
            builder.AppendLine("            return");
            builder.AppendLine("        }");
            builder.AppendLine();
            builder.AppendLine("        items.Add($\"{name}:{value}\")");
            builder.AppendLine("    }");
            builder.AppendLine();
            builder.AppendLine("    func Score(seed: int): int {");
            builder.AppendLine("        total := seed");
            builder.AppendLine("        foreach item in items {");
            builder.AppendLine("            total = total + item.Length");
            builder.AppendLine("        }");
            builder.AppendLine();
            builder.AppendLine("        return match total {");
            builder.AppendLine("            0 => 0,");
            builder.AppendLine("            x when x < 10 => x + 1,");
            builder.AppendLine("            x when x < 100 => x + 10,");
            builder.AppendLine("            _ => total");
            builder.AppendLine("        }");
            builder.AppendLine("    }");
            builder.AppendLine("}");
            builder.AppendLine();
        }

        return builder.ToString();
    }
}

public enum CompilerLexerCorpus
{
    Representative,
    LargeGenerated
}
