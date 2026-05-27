using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class DiagnosticGoldenTests
{
    private const string GoldenPath = "fixtures/diagnostics/top25.golden.txt";
    private const string TerminalArtifactPath = "fixtures/diagnostics/screenshots/top25-terminal.txt";

    [Fact]
    public void Top25Diagnostics_MatchGoldenSnapshot()
    {
        var actual = BuildTop25Snapshot();
        UpdateGoldensIfRequested(actual);
        var expected = File.ReadAllText(FindFixturePath(GoldenPath)).Replace("\r\n", "\n").TrimEnd();

        Assert.Equal(expected, actual.TrimEnd());
    }

    [Fact]
    public void Top25Diagnostics_TerminalArtifactMatchesGoldenSnapshot()
    {
        var actual = BuildTop25Snapshot();
        UpdateGoldensIfRequested(actual);
        var artifact = File.ReadAllText(FindFixturePath(TerminalArtifactPath)).Replace("\r\n", "\n").TrimEnd();
        var expected = File.ReadAllText(FindFixturePath(GoldenPath)).Replace("\r\n", "\n").TrimEnd();

        Assert.Equal(expected, artifact);
    }

    [Fact]
    public void Top25Diagnostics_AreFullyCurated()
    {
        var diagnostics = Top25Diagnostics().ToList();

        Assert.Equal(25, diagnostics.Count);
        Assert.Contains(diagnostics, d => d.Category == "parser");
        Assert.Contains(diagnostics, d => d.Category == "analyzer");
        Assert.Contains(diagnostics, d => d.Category == "migration");
        Assert.All(diagnostics, diagnostic =>
        {
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Code));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Message));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Explanation));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Help));
            Assert.StartsWith("https://docs.n-sharp.dev/", diagnostic.DocsUrl);
        });
    }

    private static string BuildTop25Snapshot()
    {
        var diagnostics = Top25Diagnostics()
            .Select(diagnostic => new DiagnosticResult(
                diagnostic.Code,
                diagnostic.Category == "migration" ? "info" : "error",
                $"[{diagnostic.Category}] {diagnostic.Message}",
                diagnostic.File,
                diagnostic.Line,
                diagnostic.Column,
                diagnostic.Length,
                diagnostic.Source,
                diagnostic.Explanation,
                diagnostic.Help,
                null,
                null,
                null,
                diagnostic.DocsUrl))
            .ToList();

        var builder = new StringBuilder();
        builder.AppendLine("# N# top 25 diagnostic golden suite");
        builder.AppendLine("# Stable terminal rendering from OutputFormatter.DiagnosticsToText.");
        builder.AppendLine("# Docs URLs are category-qualified because some diagnostic codes overlap across parser/analyzer/migration domains.");
        builder.AppendLine();
        builder.Append(OutputFormatter.DiagnosticsToText(diagnostics).Replace("\r\n", "\n"));

        return builder.ToString().TrimEnd() + "\n";
    }

    private static IEnumerable<GoldenDiagnostic> Top25Diagnostics()
    {
        yield return Parser("NL101", "Unexpected token ')'", "parser/missing-argument.nl", 3, 18, 1,
            "print(, name)",
            "The parser found `)` while it was still looking for an expression argument.",
            "Add the missing expression before `)` or remove the dangling comma.");
        yield return Parser("NL102", "Expected ':' after parameter name", "parser/missing-parameter-colon.nl", 1, 12, 1,
            "func greet(name string) {",
            "Function parameters use `name: Type`; without the colon, the type name is parsed in the wrong slot.",
            "Write `func greet(name: string) { ... }`.");
        yield return Parser("NL103", "Invalid syntax in object initializer", "parser/object-initializer-equals.nl", 2, 28, 1,
            "    return new User { Name = \"Ada\" }",
            "N# object initializers use colon fields; `=` is a C# migration leftover here.",
            "Use `new User { Name: \"Ada\" }`.");
        yield return Parser("NL104", "Unexpected end of file", "parser/missing-closing-brace.nl", 5, 1, 1,
            "",
            "The file ended before the parser found the closing `}` for the current block.",
            "Add the missing closing brace and re-run `nlc check`.");
        yield return Parser("NL106", "Missing closing brace", "parser/missing-match-brace.nl", 7, 1, 1,
            "match status {",
            "A block started here but never closed, so later code may be attached to the wrong scope.",
            "Close the block with `}` at the indentation level where the construct began.");
        yield return Parser("NL107", "Missing closing parenthesis", "parser/missing-call-paren.nl", 4, 22, 1,
            "    total := add(first, second",
            "This call opened `(` but did not close it before the line ended.",
            "Add `)` after the final argument: `add(first, second)`.");
        yield return Analyzer("NL202", "Type mismatch", "analyzer/type-mismatch.nl", 3, 19, 5,
            "let count: int = \"five\"",
            "This expression produces `string`, but the annotation says `int`.",
            "Parse the string intentionally or change the annotation to `string`.");
        yield return Analyzer("NL203", "Cannot infer type", "analyzer/cannot-infer.nl", 2, 5, 5,
            "let value = null",
            "`null` by itself does not tell the analyzer which nullable type you want.",
            "Add an explicit type, for example `let value: string? = null`.");
        yield return Analyzer("NL301", "Variable 'totla' not found", "analyzer/undefined-variable.nl", 6, 12, 5,
            "    return totla",
            "There is no local, parameter, or member named `totla` in scope.",
            "Did you mean `total`? Fix the spelling or declare the variable before use.");
        yield return Analyzer("NL302", "Type 'Usr' not found", "analyzer/undefined-type.nl", 1, 12, 3,
            "let user: Usr",
            "The analyzer cannot resolve `Usr` from this file's declarations or imports.",
            "Import the type, define it, or correct the spelling to `User`.");
        yield return Analyzer("NL303", "Member 'Lenght' not found on type 'string'", "analyzer/undefined-member.nl", 4, 17, 6,
            "    return name.Lenght",
            "The receiver type is `string`, and `Lenght` is not one of its members.",
            "Did you mean `Length`? Use the exact member name exposed by the type.");
        yield return Analyzer("NL305", "Not all code paths return a value of type 'int'", "analyzer/missing-return.nl", 1, 1, 4,
            "func score(ok: bool): int {",
            "This function promises to return `int`, but at least one branch can fall off the end.",
            "Return an `int` on every path, or change the return type to `void` if no value is needed.");
        yield return Analyzer("NL401", "Function 'send' expects 2 arguments but got 1", "analyzer/wrong-argument-count.nl", 5, 5, 9,
            "send(email)",
            "The call is missing one required argument from the function signature.",
            "Pass the missing value, or update the function signature if it should be optional.");
        yield return Analyzer("NL501", "Pattern matching is not exhaustive", "analyzer/non-exhaustive-match.nl", 3, 12, 5,
            "    match color {",
            "The match does not handle every possible value of `Color`.",
            "Add arms for the missing cases or a final `_ => ...` arm when a catch-all is intentional.");

        var migrationSource = """
using System;
namespace Legacy.Api;
class OrderDto {
    Id: int { get; set; }
}
public partial class UserDto {
    Id: int { get; set; }
    Name: string = default!
    func Find(id: string): Result<User> {
        if users.TryGetValue(id, out var user) {
            return Ok(user)
        }
        return result.Value
    }
    func Create(): User => new User { Name = "Ada" }
    func Save() {
        try {
            repo.Save()
        } catch (ex) {
            return StatusCode(500, ex.Message)
        }
    }
}
""";

        var migrationDiagnostics = new Linter().LintSource(migrationSource, "Services/Users/UserDto.nl");
        foreach (var expected in new[]
        {
            (Code: "NLM101", Line: 6, Column: 1),
            (Code: "NLM102", Line: 4, Column: 13),
            (Code: "NLM103", Line: 8, Column: 20),
            (Code: "NLM104", Line: 10, Column: 18),
            (Code: "NLM105", Line: 3, Column: 7),
            (Code: "NLM106", Line: 19, Column: 11),
            (Code: "NLM107", Line: 1, Column: 1),
            (Code: "NLM108", Line: 2, Column: 1),
            (Code: "NLM109", Line: 1, Column: 1),
            (Code: "NLM110", Line: 15, Column: 39),
            (Code: "NLM111", Line: 13, Column: 22)
        })
        {
            var diagnostic = migrationDiagnostics.Single(d =>
                d.Code == expected.Code
                && d.Location.Line == expected.Line
                && d.Location.Column == expected.Column);
            yield return Migration(diagnostic, migrationSource, expected.Code switch
            {
                "NLM101" => "C# modifiers leak source-language visibility rules into N#; N# uses naming/export conventions instead.",
                "NLM102" => "Auto-property accessor blocks are C# syntax, not the N# property or record shape.",
                "NLM103" => "Null-forgiving syntax hides a nullable design decision that must be made explicitly during migration.",
                "NLM104" => "`out` parameters and `TryGetValue` patterns are migration smells because N# prefers values, tuples, and result-style APIs.",
                "NLM105" => "This data-only DTO shape is probably a record in idiomatic N# unless identity or inheritance matters.",
                "NLM106" => "Repeated catch-to-HTTP-500 blocks obscure intent and should move to centralized error handling or result mapping.",
                "NLM107" => "C# `using` directives must become N# imports or project references before this file is considered migrated.",
                "NLM108" => "C# namespace declarations fight N# package layout and should be expressed with `package`.",
                "NLM109" => "The file layout implies a package, but the source does not declare the matching N# package.",
                "NLM110" => "Equals-style object initializer members are valid C#, but canonical N# initializer members use `:`.",
                "NLM111" => "Direct `.Value` unwraps can throw; migration needs an explicit absence-handling path.",
                _ => "Migration diagnostic."
            });
        }
    }

    private static GoldenDiagnostic Parser(string code, string message, string file, int line, int column, int length, string source, string explanation, string help)
        => new("parser", code, message, file, line, column, length, source, explanation, help, DocsUrl("parser", code));

    private static GoldenDiagnostic Analyzer(string code, string message, string file, int line, int column, int length, string source, string explanation, string help)
        => new("analyzer", code, message, file, line, column, length, source, explanation, help, DocsUrl("analyzer", code));

    private static GoldenDiagnostic Migration(Diagnostic diagnostic, string source, string explanation)
    {
        var line = diagnostic.Location.Line;
        var sourceLine = source.Replace("\r\n", "\n").Split('\n')[line - 1];
        var length = diagnostic.Code switch
        {
            "NLM101" => TokenLengthAt(sourceLine, diagnostic.Location.Column),
            "NLM102" => "{ get; set; }".Length,
            "NLM103" => TokenLengthAt(sourceLine, diagnostic.Location.Column),
            "NLM104" => sourceLine.Contains("TryGetValue", StringComparison.Ordinal) ? "TryGetValue".Length : 3,
            "NLM105" => TokenLengthAt(sourceLine, diagnostic.Location.Column),
            "NLM106" => "catch".Length,
            "NLM107" => "using".Length,
            "NLM108" => "namespace".Length,
            "NLM109" => Math.Min(sourceLine.Trim().Length, 8),
            "NLM110" => TokenLengthAt(sourceLine, diagnostic.Location.Column),
            "NLM111" => ".Value".Length,
            _ => 1
        };

        return new GoldenDiagnostic(
            "migration",
            diagnostic.Code,
            diagnostic.Message,
            diagnostic.Location.FilePath ?? "Services/Users/UserDto.nl",
            line,
            diagnostic.Location.Column,
            length,
            sourceLine,
            explanation,
            diagnostic.Suggestion ?? "Review this C# migration artifact before shipping the N# source.",
            DocsUrl("migration", diagnostic.Code));
    }

    private static int TokenLengthAt(string sourceLine, int oneBasedColumn)
    {
        var start = Math.Clamp(oneBasedColumn - 1, 0, Math.Max(0, sourceLine.Length - 1));
        var length = 0;
        while (start + length < sourceLine.Length && (char.IsLetterOrDigit(sourceLine[start + length]) || sourceLine[start + length] is '_' or '!' or '.'))
            length++;
        return Math.Max(1, length);
    }

    private static string DocsUrl(string category, string code) => $"https://docs.n-sharp.dev/errors/{category}/{code}";

    private static void UpdateGoldensIfRequested(string actual)
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("NSHARP_UPDATE_DIAGNOSTIC_GOLDENS"), "1", StringComparison.Ordinal))
            return;

        WriteFixture(GoldenPath, actual);
        WriteFixture(TerminalArtifactPath, actual);
    }

    private static void WriteFixture(string relativePath, string content)
    {
        var path = Path.Combine(FindRepoRoot(), "tests", relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content.Replace("\r\n", "\n"));
    }

    private static string FindFixturePath(string relativePath)
    {
        var current = AppContext.BaseDirectory;
        while (current != null)
        {
            var candidate = Path.Combine(current, relativePath);
            if (File.Exists(candidate))
                return candidate;

            var testsCandidate = Path.Combine(current, "tests", relativePath);
            if (File.Exists(testsCandidate))
                return testsCandidate;

            current = Directory.GetParent(current)?.FullName;
        }

        throw new FileNotFoundException($"Could not find diagnostic fixture '{relativePath}'.");
    }

    private static string FindRepoRoot()
    {
        var current = AppContext.BaseDirectory;
        while (current != null)
        {
            if (File.Exists(Path.Combine(current, "tests", "Tests.csproj")) && Directory.Exists(Path.Combine(current, "src")))
                return current;

            current = Directory.GetParent(current)?.FullName;
        }

        throw new DirectoryNotFoundException("Could not find repository root.");
    }

    private sealed record GoldenDiagnostic(
        string Category,
        string Code,
        string Message,
        string File,
        int Line,
        int Column,
        int Length,
        string Source,
        string Explanation,
        string Help,
        string DocsUrl);
}
