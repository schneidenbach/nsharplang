using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace NSharpLang.Cli.Commands;

public static class IdiomCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static readonly string[] SourceExtensions = [".nl", ".cs"];
    private static readonly string[] IgnoredDirectoryNames = [".git", ".idea", ".vs", "bin", "obj", "node_modules", "dist", "build"];
    private static readonly string[] PackageLayoutNames = ["Commands", "Database", "Endpoints", "Handlers", "Models", "Services", "Types", "Views", "Workflow", "Workflows"];

    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            return ShowHelp();
        }

        var projectDir = GetOptionValue(args, "--project") ?? GetOptionValue(args, "-p") ?? Directory.GetCurrentDirectory();
        var fullProjectDir = Path.GetFullPath(projectDir);
        if (!Directory.Exists(fullProjectDir))
        {
            return WriteError(fullProjectDir, "directoryNotFound", $"Directory not found: {fullProjectDir}");
        }

        try
        {
            var report = BuildReport(fullProjectDir);
            Console.Write(JsonSerializer.Serialize(report, JsonOptions));
            return 0;
        }
        catch (Exception ex)
        {
            return WriteError(fullProjectDir, "idiomReportFailed", $"Idiom report failed: {ex.Message}");
        }
    }

    internal static object BuildReport(string projectRoot)
    {
        var files = EnumerateSourceFiles(projectRoot).ToArray();
        var fileReports = files.Select(file => AnalyzeFile(projectRoot, file)).ToArray();

        var csharpIsms = new
        {
            modifiers = fileReports.Sum(file => file.CSharpModifiers.Count),
            semicolons = fileReports.Sum(file => file.Semicolons.Count),
            propertySyntax = fileReports.Sum(file => file.PropertySyntax.Count),
            underscoreFields = fileReports.Sum(file => file.UnderscoreFields.Count),
            nullForgiving = fileReports.Sum(file => file.NullForgiving.Count),
            outVar = fileReports.Sum(file => file.OutVar.Count),
            tryGetValue = fileReports.Sum(file => file.TryGetValue.Count),
            actionResults = fileReports.Sum(file => file.ActionResults.Count),
            anonymousApiDtos = fileReports.Sum(file => file.AnonymousApiDtos.Count),
            querySyntax = fileReports.Sum(file => file.QuerySyntax.Count),
            equalsInitializers = fileReports.Sum(file => file.EqualsInitializers.Count),
            unsafeValueAccess = fileReports.Sum(file => file.UnsafeValueAccess.Count),
            examples = new
            {
                modifiers = Sample(fileReports.SelectMany(file => file.CSharpModifiers)),
                semicolons = Sample(fileReports.SelectMany(file => file.Semicolons)),
                propertySyntax = Sample(fileReports.SelectMany(file => file.PropertySyntax)),
                underscoreFields = Sample(fileReports.SelectMany(file => file.UnderscoreFields)),
                nullForgiving = Sample(fileReports.SelectMany(file => file.NullForgiving)),
                outVar = Sample(fileReports.SelectMany(file => file.OutVar)),
                tryGetValue = Sample(fileReports.SelectMany(file => file.TryGetValue)),
                actionResults = Sample(fileReports.SelectMany(file => file.ActionResults)),
                anonymousApiDtos = Sample(fileReports.SelectMany(file => file.AnonymousApiDtos)),
                querySyntax = Sample(fileReports.SelectMany(file => file.QuerySyntax)),
                equalsInitializers = Sample(fileReports.SelectMany(file => file.EqualsInitializers)),
                unsafeValueAccess = Sample(fileReports.SelectMany(file => file.UnsafeValueAccess))
            }
        };

        var packageLayoutDirectories = CountPackageLayoutDirectories(projectRoot, files);
        var adoption = new
        {
            records = fileReports.Sum(file => file.Records.Count),
            matchExpressions = fileReports.Sum(file => file.MatchExpressions.Count),
            resultMentions = fileReports.Sum(file => file.ResultMentions.Count),
            packageLayoutDirectories,
            examples = new
            {
                records = Sample(fileReports.SelectMany(file => file.Records)),
                matchExpressions = Sample(fileReports.SelectMany(file => file.MatchExpressions)),
                resultMentions = Sample(fileReports.SelectMany(file => file.ResultMentions))
            }
        };

        var dtoClasses = fileReports.SelectMany(file => file.DtoClasses).ToArray();
        var casingVisibilityIssues = fileReports.SelectMany(file => file.CasingVisibilityIssues).ToArray();
        var manualReviewIslands = fileReports.SelectMany(file => file.ManualReviewIslands).ToArray();

        var csharpDebt = csharpIsms.modifiers
            + csharpIsms.semicolons
            + csharpIsms.propertySyntax
            + csharpIsms.underscoreFields
            + csharpIsms.nullForgiving
            + csharpIsms.outVar
            + csharpIsms.tryGetValue
            + csharpIsms.actionResults
            + csharpIsms.anonymousApiDtos
            + csharpIsms.querySyntax
            + csharpIsms.equalsInitializers
            + csharpIsms.unsafeValueAccess
            + dtoClasses.Length
            + casingVisibilityIssues.Length
            + manualReviewIslands.Length;
        var adoptionSignals = adoption.records
            + adoption.matchExpressions
            + adoption.resultMentions
            + adoption.packageLayoutDirectories;
        var score = CalculateScore(adoptionSignals, csharpDebt);

        return new
        {
            schemaVersion = 1,
            command = "idiom",
            ok = true,
            projectRoot = NormalizePath(projectRoot),
            scannedFiles = files.Length,
            score,
            grade = Grade(score),
            summary = new
            {
                csharpDebt,
                adoptionSignals,
                grade = Grade(score)
            },
            signals = new
            {
                csharpIsms,
                nsharpAdoption = adoption,
                dtoClasses = new { count = dtoClasses.Length, examples = Sample(dtoClasses) },
                casingVisibilityIssues = new { count = casingVisibilityIssues.Length, examples = Sample(casingVisibilityIssues) },
                manualReviewIslands = new { count = manualReviewIslands.Length, examples = Sample(manualReviewIslands) }
            },
            files = fileReports.Select(file => new
            {
                file = file.File,
                csharpDebt = file.CSharpDebt,
                adoptionSignals = file.AdoptionSignals,
                manualReviewIslands = file.ManualReviewIslands.Count
            }).ToArray(),
            recommendations = BuildRecommendations(csharpIsms.modifiers, csharpIsms.semicolons, csharpIsms.propertySyntax,
                csharpIsms.underscoreFields, csharpIsms.nullForgiving, csharpIsms.outVar, csharpIsms.tryGetValue,
                csharpIsms.actionResults, csharpIsms.anonymousApiDtos, csharpIsms.querySyntax,
                csharpIsms.equalsInitializers, csharpIsms.unsafeValueAccess, dtoClasses.Length,
                casingVisibilityIssues.Length, manualReviewIslands.Length,
                adoption.records, adoption.matchExpressions, adoption.resultMentions, adoption.packageLayoutDirectories),
            thresholds = new
            {
                checkErrors = 0,
                blockingCsharpArtifacts = 0,
                safeFixesRemaining = 0,
                reviewNeededFixes = "applied-or-waived",
                tests = "pass-after-source-changes"
            }
        };
    }

    private static FileIdiomReport AnalyzeFile(string projectRoot, string file)
    {
        var text = File.ReadAllText(file);
        var relative = NormalizePath(Path.GetRelativePath(projectRoot, file));
        var lineStarts = GetLineStarts(text);

        var csharpModifiers = FindMatches(text, relative, lineStarts,
            new Regex(@"\b(public|private|protected|internal|sealed|abstract|static|readonly|virtual|override|async)\b", RegexOptions.Compiled));
        var semicolons = Path.GetExtension(file).Equals(".nl", StringComparison.OrdinalIgnoreCase)
            ? FindSemicolonArtifacts(text, relative)
            : [];
        var propertySyntax = FindMatches(text, relative, lineStarts,
            new Regex(@"\{\s*get\s*;\s*(?:set|init)\s*;\s*\}", RegexOptions.Compiled));
        var underscoreFields = FindMatches(text, relative, lineStarts,
            new Regex(@"(?:\bprivate\s+\w+(?:<[^>]+>)?\??\s+_\w+\b|\bprivate\s+_\w+\s*:|\b_\w+\s*:)", RegexOptions.Compiled));
        var nullForgiving = FindMatches(text, relative, lineStarts,
            new Regex(@"\b(?:null|default)!|(?<=[A-Za-z0-9_\]])!(?![=])", RegexOptions.Compiled));
        var outVar = FindMatches(text, relative, lineStarts,
            new Regex(@"\bout\s+var\s+\w+", RegexOptions.Compiled));
        var tryGetValue = FindMatches(text, relative, lineStarts,
            new Regex(@"\bTryGetValue\s*\(", RegexOptions.Compiled));
        var actionResults = FindMatches(text, relative, lineStarts,
            new Regex(@"\bIActionResult\b", RegexOptions.Compiled));
        var anonymousApiDtos = FindMatches(text, relative, lineStarts,
            new Regex(@"\bnew\s*\{", RegexOptions.Compiled));
        var querySyntax = FindMatches(text, relative, lineStarts,
            new Regex(@"\bfrom\s+\w+\s+in\b", RegexOptions.Compiled));
        var equalsInitializers = FindMatches(text, relative, lineStarts,
            new Regex(@"\bnew\s+[^\n{]+\{[^\n{}]*\w+\s*=", RegexOptions.Compiled));
        var unsafeValueAccess = FindMatches(text, relative, lineStarts,
            new Regex(@"\.\s*Value\b", RegexOptions.Compiled));
        var dtoClasses = FindMatches(text, relative, lineStarts,
            new Regex(@"\bclass\s+\w*(?:Dto|DTO|Request|Response|ViewModel)\b", RegexOptions.Compiled));
        var records = FindMatches(text, relative, lineStarts,
            new Regex(@"\brecord\b", RegexOptions.Compiled));
        var matchExpressions = FindMatches(text, relative, lineStarts,
            new Regex(@"\bmatch\s+[^\s{]+", RegexOptions.Compiled));
        var resultMentions = FindMatches(text, relative, lineStarts,
            new Regex(@"\bResult(?:<|\.)", RegexOptions.Compiled));
        var casingVisibilityIssues = FindCasingVisibilityIssues(text, relative, lineStarts);
        var manualReviewIslands = FindManualReviewIslands(text, relative, lineStarts);

        return new FileIdiomReport(
            relative,
            csharpModifiers,
            semicolons,
            propertySyntax,
            underscoreFields,
            nullForgiving,
            outVar,
            tryGetValue,
            actionResults,
            anonymousApiDtos,
            querySyntax,
            equalsInitializers,
            unsafeValueAccess,
            dtoClasses,
            records,
            matchExpressions,
            resultMentions,
            casingVisibilityIssues,
            manualReviewIslands);
    }

    private static IEnumerable<string> EnumerateSourceFiles(string projectRoot)
    {
        return Directory.EnumerateFiles(projectRoot, "*.*", SearchOption.AllDirectories)
            .Where(file => SourceExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase))
            .Where(file => !IsIgnoredPath(projectRoot, file))
            .Where(file => !Path.GetFileName(file).EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase))
            .Where(file => !Path.GetFileName(file).EndsWith(".Designer.cs", StringComparison.OrdinalIgnoreCase))
            .OrderBy(file => NormalizePath(Path.GetRelativePath(projectRoot, file)), StringComparer.OrdinalIgnoreCase);
    }

    private static bool IsIgnoredPath(string projectRoot, string file)
    {
        var relative = Path.GetRelativePath(projectRoot, file);
        var parts = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return parts.Any(part => IgnoredDirectoryNames.Contains(part, StringComparer.OrdinalIgnoreCase));
    }

    private static int CountPackageLayoutDirectories(string projectRoot, IReadOnlyList<string> files)
    {
        return files
            .Select(file => Path.GetDirectoryName(Path.GetRelativePath(projectRoot, file)) ?? string.Empty)
            .Where(dir => !string.IsNullOrWhiteSpace(dir))
            .SelectMany(dir => dir.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count(part => PackageLayoutNames.Contains(part, StringComparer.OrdinalIgnoreCase));
    }

    private static List<Occurrence> FindMatches(string text, string file, IReadOnlyList<int> lineStarts, Regex regex)
    {
        return regex.Matches(text)
            .Cast<Match>()
            .Select(match => ToOccurrence(text, file, lineStarts, match.Index, match.Length))
            .ToList();
    }

    private static List<Occurrence> FindSemicolonArtifacts(string text, string file)
    {
        var issues = new List<Occurrence>();
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var trimmed = line.TrimStart();
            if (trimmed.StartsWith("for ", StringComparison.Ordinal))
            {
                continue;
            }

            var semicolonColumn = line.IndexOf(';');
            if (semicolonColumn >= 0)
            {
                issues.Add(new Occurrence(file, i + 1, semicolonColumn + 1, line.Trim()));
            }
        }

        return issues;
    }

    private static List<Occurrence> FindCasingVisibilityIssues(string text, string file, IReadOnlyList<int> lineStarts)
    {
        var issues = new List<Occurrence>();
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var trimmed = line.TrimStart();
            var match = Regex.Match(trimmed, @"^(public|private)\s+(.*)$");
            if (match.Success && TryExtractDeclaredName(match.Groups[2].Value, out var name))
            {
                var modifier = match.Groups[1].Value;
                if ((modifier == "public" && char.IsLower(name[0])) || (modifier == "private" && char.IsUpper(name[0])))
                {
                    issues.Add(new Occurrence(file, i + 1, line.Length - trimmed.Length + 1, line.Trim()));
                }
            }
        }

        return issues;
    }

    private static bool TryExtractDeclaredName(string declaration, out string name)
    {
        name = string.Empty;
        var withoutInitializer = declaration.Split('=', '{', '(', ';')[0].Trim();
        if (withoutInitializer.Length == 0)
        {
            return false;
        }

        var declarationKeywords = new HashSet<string>(StringComparer.Ordinal)
        {
            "class", "record", "struct", "interface", "func"
        };
        var parts = Regex.Matches(withoutInitializer, @"[A-Za-z_]\w*")
            .Cast<Match>()
            .Select(match => match.Value)
            .ToArray();
        if (parts.Length == 0)
        {
            return false;
        }

        if (declarationKeywords.Contains(parts[0]))
        {
            if (parts.Length < 2)
            {
                return false;
            }

            name = parts[1];
            return true;
        }

        name = withoutInitializer.Contains(':') || parts.Length == 1
            ? parts[0]
            : parts[^1];
        return true;
    }

    private static List<Occurrence> FindManualReviewIslands(string text, string file, IReadOnlyList<int> lineStarts)
    {
        var issues = new List<Occurrence>();
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (line.Contains("TODO", StringComparison.OrdinalIgnoreCase)
                || line.Contains("FIXME", StringComparison.OrdinalIgnoreCase)
                || line.Contains("HACK", StringComparison.OrdinalIgnoreCase)
                || line.Contains("manual review", StringComparison.OrdinalIgnoreCase)
                || line.Contains("manual-review", StringComparison.OrdinalIgnoreCase))
            {
                issues.Add(new Occurrence(file, i + 1, 1, line.Trim()));
            }
        }

        return issues;
    }

    private static List<int> GetLineStarts(string text)
    {
        var starts = new List<int> { 0 };
        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '\n')
            {
                starts.Add(i + 1);
            }
        }

        return starts;
    }

    private static Occurrence ToOccurrence(string text, string file, IReadOnlyList<int> lineStarts, int index, int length)
    {
        var lineIndex = 0;
        for (var i = 0; i < lineStarts.Count; i++)
        {
            if (lineStarts[i] > index)
            {
                break;
            }

            lineIndex = i;
        }

        var lineStart = lineStarts[lineIndex];
        var lineEnd = text.IndexOf('\n', lineStart);
        if (lineEnd < 0)
        {
            lineEnd = text.Length;
        }

        var lineText = text.Substring(lineStart, lineEnd - lineStart).Trim();
        return new Occurrence(file, lineIndex + 1, index - lineStart + 1, lineText);
    }

    private static Occurrence[] Sample(IEnumerable<Occurrence> occurrences)
        => occurrences.Take(10).ToArray();

    private static int CalculateScore(int adoptionSignals, int csharpDebt)
    {
        if (adoptionSignals == 0 && csharpDebt == 0)
        {
            return 100;
        }

        var score = (int)Math.Round(100.0 * adoptionSignals / Math.Max(1, adoptionSignals + csharpDebt));
        return Math.Clamp(score, 0, 100);
    }

    private static string Grade(int score) => score switch
    {
        >= 85 => "idiomatic",
        >= 65 => "mostly-idiomatic",
        >= 40 => "mixed",
        >= 20 => "csharp-heavy",
        _ => "needs-migration"
    };

    private static string[] BuildRecommendations(
        int modifiers,
        int semicolons,
        int propertySyntax,
        int underscoreFields,
        int nullForging,
        int outVar,
        int tryGetValue,
        int actionResults,
        int anonymousApiDtos,
        int querySyntax,
        int equalsInitializers,
        int unsafeValueAccess,
        int dtoClasses,
        int casingVisibilityIssues,
        int manualReviewIslands,
        int records,
        int matchExpressions,
        int resultMentions,
        int packageLayoutDirectories)
    {
        var recommendations = new List<string>();
        if (semicolons > 0) recommendations.Add("Remove C# statement semicolons from migrated N# files except where syntax explicitly requires them.");
        if (propertySyntax > 0) recommendations.Add("Replace C# property blocks with N# field/property syntax.");
        if (underscoreFields > 0) recommendations.Add("Rename private `_field` members to camelCase N# fields.");
        if (nullForging > 0) recommendations.Add("Review null-forgiving/default-forgiving operators and model nullability explicitly.");
        if (outVar > 0 || tryGetValue > 0) recommendations.Add("Replace out-var/TryGetValue flows with result-returning helpers or matchable results.");
        if (actionResults > 0) recommendations.Add("Prefer typed ASP.NET results or concrete return records over IActionResult defaults when endpoint shape is known.");
        if (anonymousApiDtos > 0) recommendations.Add("Promote anonymous API DTOs to named N# records at framework boundaries.");
        if (querySyntax > 0) recommendations.Add("Rewrite C# query syntax to fluent LINQ calls or explicit loops.");
        if (equalsInitializers > 0) recommendations.Add("Use canonical N# object initialization with colon fields: new Type { Name: value }.");
        if (unsafeValueAccess > 0) recommendations.Add("Replace unsafe .Value access on result/option-like values with match or checked unwrap helpers.");
        if (dtoClasses > records) recommendations.Add("Convert DTO-shaped classes to records where identity/mutation is not required.");
        if (matchExpressions == 0) recommendations.Add("Introduce match expressions for branching over unions, enums, and sentinel states.");
        if (resultMentions == 0) recommendations.Add("Prefer Result-style unions for recoverable failures instead of sentinel values or out parameters.");
        if (casingVisibilityIssues > 0) recommendations.Add("Fix visibility/casing conflicts so public names are PascalCase and private names are camelCase unless intentionally overridden.");
        if (manualReviewIslands > 0) recommendations.Add("Resolve TODO/manual-review islands left by conversion before considering the migration complete.");
        if (modifiers > 0) recommendations.Add("Audit explicit C# modifiers; N# should lean on convention-based visibility where possible.");
        if (packageLayoutDirectories == 0) recommendations.Add("Group migrated code into package-style folders such as Models, Services, Commands, or Endpoints.");

        return recommendations.Distinct(StringComparer.Ordinal).ToArray();
    }

    private static string? GetOptionValue(string[] args, string option)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == option)
            {
                return args[i + 1];
            }
        }

        return null;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Idiom Score

Usage: nlc idiom [--project <dir>]

Scans .nl and non-generated .cs files and emits a machine-readable JSON report
for migration quality. The report counts remaining C#-isms, idiomatic N#
adoption signals, package layout signals, casing/visibility conflicts, and
TODO/manual-review islands.

Options:
  --project <dir>   Project directory to scan (default: current directory)
  --help, -h        Show this help text

Exit codes:
  0  Report emitted successfully
  1  Report failed");
        return 0;
    }

    private static int WriteError(string projectRoot, string code, string message)
    {
        var envelope = new
        {
            schemaVersion = 1,
            command = "idiom",
            ok = false,
            projectRoot = NormalizePath(projectRoot),
            error = new
            {
                code,
                message
            }
        };
        Console.Write(JsonSerializer.Serialize(envelope, JsonOptions));
        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private sealed record Occurrence(string File, int Line, int Column, string Text);

    private sealed record FileIdiomReport(
        string File,
        List<Occurrence> CSharpModifiers,
        List<Occurrence> Semicolons,
        List<Occurrence> PropertySyntax,
        List<Occurrence> UnderscoreFields,
        List<Occurrence> NullForgiving,
        List<Occurrence> OutVar,
        List<Occurrence> TryGetValue,
        List<Occurrence> ActionResults,
        List<Occurrence> AnonymousApiDtos,
        List<Occurrence> QuerySyntax,
        List<Occurrence> EqualsInitializers,
        List<Occurrence> UnsafeValueAccess,
        List<Occurrence> DtoClasses,
        List<Occurrence> Records,
        List<Occurrence> MatchExpressions,
        List<Occurrence> ResultMentions,
        List<Occurrence> CasingVisibilityIssues,
        List<Occurrence> ManualReviewIslands)
    {
        public int CSharpDebt => CSharpModifiers.Count
            + Semicolons.Count
            + PropertySyntax.Count
            + UnderscoreFields.Count
            + NullForgiving.Count
            + OutVar.Count
            + TryGetValue.Count
            + ActionResults.Count
            + AnonymousApiDtos.Count
            + QuerySyntax.Count
            + EqualsInitializers.Count
            + UnsafeValueAccess.Count
            + DtoClasses.Count
            + CasingVisibilityIssues.Count
            + ManualReviewIslands.Count;

        public int AdoptionSignals => Records.Count + MatchExpressions.Count + ResultMentions.Count;
    }
}
