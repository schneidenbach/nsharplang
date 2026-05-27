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
        Assert.Contains(diagnostics, d => d.Category == "linter");
        Assert.All(diagnostics, diagnostic =>
        {
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Code));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Message));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Explanation));
            Assert.False(string.IsNullOrWhiteSpace(diagnostic.Help));
            Assert.StartsWith("https://docs.n-sharp.dev/", diagnostic.DocsUrl);
        });
    }

    [Fact]
    public void Top25Diagnostics_SpansStartOnVisibleTokensAndCoverIdentifierTokens()
    {
        foreach (var diagnostic in Top25Diagnostics())
        {
            if (string.IsNullOrEmpty(diagnostic.Source))
                continue;

            Assert.InRange(diagnostic.Column, 1, diagnostic.Source.Length);
            var start = diagnostic.Column - 1;
            var startChar = diagnostic.Source[start];

            Assert.False(char.IsWhiteSpace(startChar),
                $"{diagnostic.Code} in {diagnostic.File} starts on whitespace at column {diagnostic.Column}.");

            if (!IsIdentifierStart(startChar))
                continue;

            var identifierLength = IdentifierLengthAt(diagnostic.Source, start);
            Assert.True(diagnostic.Length >= identifierLength,
                $"{diagnostic.Code} in {diagnostic.File} underlines {diagnostic.Length} character(s), but should cover identifier `{diagnostic.Source.Substring(start, identifierLength)}`.");
        }
    }

    private static string BuildTop25Snapshot()
    {
        var diagnostics = Top25Diagnostics()
            .Select(diagnostic => new DiagnosticResult(
                diagnostic.Code,
                DiagnosticCatalog.GetDefaultSeverity(diagnostic.Code, DiagnosticSeverity.Error) switch
                {
                    DiagnosticSeverity.Error => "error",
                    DiagnosticSeverity.Warning => "warning",
                    _ => "info"
                },
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
        builder.AppendLine("# Docs URLs are category-qualified where parser/analyzer/linter docs are split.");
        builder.AppendLine();
        builder.Append(OutputFormatter.DiagnosticsToText(diagnostics).Replace("\r\n", "\n"));

        return builder.ToString().TrimEnd() + "\n";
    }

    private static IEnumerable<GoldenDiagnostic> Top25Diagnostics()
    {
        yield return Parser("NL101", "Unexpected token ')'", "parser/missing-argument.nl", 3, 17, 1,
            "    print(name, )",
            "The parser found `)` while it was still looking for an expression argument.",
            "Add the missing expression before `)` or remove the dangling comma.");
        yield return Parser("NL102", "Expected ':' after parameter name", "parser/missing-parameter-colon.nl", 1, 12, 4,
            "func greet(name string) {",
            "Function parameters use `name: Type`; without the colon, the type name is parsed in the wrong slot.",
            "Write `func greet(name: string) { ... }`.");
        yield return Parser("NL103", "Invalid syntax in object initializer", "parser/object-initializer-equals.nl", 2, 23, 4,
            "    return new User { Name = \"Ada\" }",
            "N# object initializers use colon fields; `=` is C# object-initializer syntax.",
            "Use `new User { Name: \"Ada\" }`.");
        yield return Parser("NL104", "Unexpected end of file", "parser/missing-closing-brace.nl", 5, 1, 1,
            "",
            "The file ended before the parser found the closing `}` for the current block.",
            "Add the missing closing brace and re-run `nlc check`.");
        yield return Parser("NL106", "Missing closing brace", "parser/missing-match-brace.nl", 7, 1, 5,
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

        yield return Linter("NL001", "Variable 'temp' is declared but never read", "linter/unused-variable.nl", 2, 5, 4,
            "    temp := 42",
            "Unused locals are almost always stale code or a missed side effect.",
            "Remove the declaration or prefix it with `_` when the unused value is intentional.");
        yield return Linter("NL006", "Unreachable code detected", "linter/unreachable-code.nl", 4, 5, 5,
            "    print \"done\"",
            "Statements after a guaranteed exit cannot run and often hide a control-flow bug.",
            "Move the statement before the exit or delete it.");
        yield return Linter("NL010", "Import 'System.Linq' is never used", "linter/unused-import.nl", 1, 1, 6,
            "import System.Linq",
            "Unused imports make dependency intent harder to read and can mask stale code.",
            "Remove the import or use a symbol from it.");
        yield return Linter("NL003", "Unnecessary null check on non-nullable value", "linter/unnecessary-null-check.nl", 3, 4, 4,
            "if name != null {",
            "The value is already known to be non-nullable, so the condition adds noise without protecting anything.",
            "Delete the null check and keep the useful branch body.");
        yield return Linter("NL004", "Async function has no await", "linter/async-without-await.nl", 1, 1, 10,
            "async func Load(): Task<int> {",
            "An async function with no await usually does not need the async state machine.",
            "Remove `async` or await the asynchronous operation that should drive this function.");
        yield return Linter("NL005", "Use pattern matching", "linter/use-pattern-matching.nl", 3, 1, 2,
            "if value is string {",
            "A chain of type or shape checks is easier to audit when expressed as one match.",
            "Rewrite the branch as a `match` when several related cases are being handled.");
        yield return Linter("NL011", "Empty catch block", "linter/empty-catch.nl", 5, 7, 5,
            "} catch (ex) {",
            "Swallowing errors silently makes failures hard to debug and can corrupt program state.",
            "Handle the error, log it, or explain the intentional suppression with a comment.");
        yield return Linter("NL012", "Parameter 'options' is never used", "linter/unused-parameter.nl", 1, 15, 7,
            "func Save(options: SaveOptions) {",
            "Unused parameters usually mean the call contract drifted from the implementation.",
            "Use the parameter, remove it from the signature, or prefix it with `_` if required by an interface.");
        yield return Linter("NL013", "Prefer string interpolation", "linter/prefer-interpolation.nl", 2, 12, 1,
            "message := \"Hello, \" + name",
            "Interpolation keeps formatting intent in one string instead of splitting it across concatenation.",
            "Use `$\"Hello, {name}\"`.");
        yield return Linter("NL015", "Variable 'limit' can be const", "linter/prefer-const.nl", 2, 5, 5,
            "let limit := 10",
            "Values that never change are clearer when declared as constants.",
            "Change `let` to `const`.");
        yield return Linter("NL020", "Variable 'count' shadows an outer variable", "linter/shadowed-variable.nl", 4, 9, 5,
            "        count := item.Count",
            "Shadowing makes reads ambiguous and can cause updates to affect the wrong variable.",
            "Rename the inner variable or reuse the existing one intentionally.");
    }

    private static GoldenDiagnostic Parser(string code, string message, string file, int line, int column, int length, string source, string explanation, string help)
        => new("parser", code, message, file, line, column, length, source, explanation, help, DocsUrl("parser", code));

    private static GoldenDiagnostic Analyzer(string code, string message, string file, int line, int column, int length, string source, string explanation, string help)
        => new("analyzer", code, message, file, line, column, length, source, explanation, help, DocsUrl("analyzer", code));

    private static GoldenDiagnostic Linter(string code, string message, string file, int line, int column, int length, string source, string explanation, string help)
        => new("linter", code, message, file, line, column, length, source, explanation, help, DocsUrl("linter", code));

    private static string DocsUrl(string category, string code) => $"https://docs.n-sharp.dev/errors/{category}/{code}";

    private static bool IsIdentifierStart(char ch)
        => char.IsLetter(ch) || ch == '_';

    private static int IdentifierLengthAt(string source, int start)
    {
        var end = start;
        while (end < source.Length && (char.IsLetterOrDigit(source[end]) || source[end] == '_'))
            end++;

        return Math.Max(1, end - start);
    }

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
