using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler;

public enum DiagnosticSource
{
    Compiler,
    Linter,
    Migration
}

public enum DiagnosticCategory
{
    Syntax,
    Type,
    Semantic,
    Function,
    Pattern,
    Operator,
    Import,
    TypeDeclaration,
    Hygiene,
    Nullability,
    Style,
    Migration
}

public sealed record DiagnosticDescriptor(
    string Code,
    string Title,
    DiagnosticSource Source,
    DiagnosticCategory Category,
    DiagnosticSeverity DefaultSeverity,
    bool BlocksBuildByDefault,
    bool IsConfigurable = true,
    string? DocsUrl = null);

public static class DiagnosticCatalog
{
    private static readonly Lazy<IReadOnlyDictionary<string, DiagnosticDescriptor>> DescriptorByCode =
        new(BuildDescriptorMap);

    public static IReadOnlyCollection<DiagnosticDescriptor> Descriptors => DescriptorByCode.Value.Values.ToArray();

    public static IReadOnlyCollection<DiagnosticDescriptor> LinterDescriptors =>
        Descriptors
            .Where(descriptor => descriptor.Source is DiagnosticSource.Linter or DiagnosticSource.Migration)
            .ToArray();

    public static bool TryGetDescriptor(string code, out DiagnosticDescriptor descriptor)
        => DescriptorByCode.Value.TryGetValue(code, out descriptor!);

    public static DiagnosticSeverity GetDefaultSeverity(string code, DiagnosticSeverity fallback = DiagnosticSeverity.Warning)
        => TryGetDescriptor(code, out var descriptor) ? descriptor.DefaultSeverity : fallback;

    public static string DocsUrlFor(string code)
        => TryGetDescriptor(code, out var descriptor) && !string.IsNullOrWhiteSpace(descriptor.DocsUrl)
            ? descriptor.DocsUrl
            : $"https://docs.nsharp.dev/errors/{code}";

    private static IReadOnlyDictionary<string, DiagnosticDescriptor> BuildDescriptorMap()
    {
        var descriptors = CompilerDescriptors()
            .Concat(LinterRuleDescriptors())
            .Concat(MigrationRuleDescriptors())
            .ToList();

        var duplicate = descriptors
            .GroupBy(descriptor => descriptor.Code, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate != null)
        {
            throw new InvalidOperationException($"Duplicate diagnostic code '{duplicate.Key}' in diagnostic catalog.");
        }

        return descriptors.ToDictionary(descriptor => descriptor.Code, StringComparer.Ordinal);
    }

    private static IEnumerable<DiagnosticDescriptor> CompilerDescriptors()
    {
        foreach (ErrorCode code in Enum.GetValues<ErrorCode>())
        {
            var diagnosticCode = $"NL{(int)code:D3}";
            var category = code switch
            {
                >= ErrorCode.UnexpectedToken and <= ErrorCode.MissingClosingBracket => DiagnosticCategory.Syntax,
                >= ErrorCode.TypeNotFound and <= ErrorCode.GenericConstraintViolation => DiagnosticCategory.Type,
                >= ErrorCode.UndefinedVariable and <= ErrorCode.InvalidExpressionStatement => DiagnosticCategory.Semantic,
                >= ErrorCode.WrongArgumentCount and <= ErrorCode.InvalidDefaultParameterValue => DiagnosticCategory.Function,
                >= ErrorCode.NonExhaustiveMatch and <= ErrorCode.ImpossiblePattern => DiagnosticCategory.Pattern,
                >= ErrorCode.InvalidOperatorOverload and <= ErrorCode.ConversionOperatorInvalid => DiagnosticCategory.Operator,
                >= ErrorCode.ImportNotFound and <= ErrorCode.NamespaceNotFound => DiagnosticCategory.Import,
                >= ErrorCode.MultipleInheritance and <= ErrorCode.ConstructorError => DiagnosticCategory.TypeDeclaration,
                ErrorCode.PossibleNullAccess or ErrorCode.NullabilityWarning => DiagnosticCategory.Nullability,
                ErrorCode.UnusedVariable or ErrorCode.UnreachableCode or ErrorCode.UnnecessaryTypeAnnotation => DiagnosticCategory.Hygiene,
                ErrorCode.VisibilityConventionWarning or ErrorCode.ObsoleteUsage => DiagnosticCategory.Style,
                _ => DiagnosticCategory.Semantic
            };

            var severity = code switch
            {
                ErrorCode.VisibilityConventionWarning or ErrorCode.ObsoleteUsage or ErrorCode.UnnecessaryTypeAnnotation
                    => DiagnosticSeverity.Warning,
                _ => DiagnosticSeverity.Error
            };

            yield return new DiagnosticDescriptor(
                diagnosticCode,
                ToTitle(code.ToString()),
                DiagnosticSource.Compiler,
                category,
                severity,
                BlocksBuildByDefault: severity == DiagnosticSeverity.Error,
                IsConfigurable: false);
        }
    }

    private static IEnumerable<DiagnosticDescriptor> LinterRuleDescriptors()
    {
        yield return Linter("NL001", "Unused variable", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL002", "Missing import", DiagnosticCategory.Import, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL003", "Unnecessary null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Warning);
        yield return Linter("NL004", "Async without await", DiagnosticCategory.Hygiene, DiagnosticSeverity.Warning);
        yield return Linter("NL005", "Use pattern matching", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL006", "Unreachable code", DiagnosticCategory.Semantic, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL008", "Camel-case local", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL010", "Unused import", DiagnosticCategory.Import, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL011", "Empty catch", DiagnosticCategory.Hygiene, DiagnosticSeverity.Warning);
        yield return Linter("NL012", "Unused parameter", DiagnosticCategory.Hygiene, DiagnosticSeverity.Info);
        yield return Linter("NL013", "Prefer interpolation", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL014", "Unnecessary type annotation", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL015", "Prefer const", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL016", "Redundant null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Warning);
        yield return Linter("NL018", "Prefer readonly", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL019", "Empty block", DiagnosticCategory.Style, DiagnosticSeverity.Info);
        yield return Linter("NL020", "Shadowed variable", DiagnosticCategory.Hygiene, DiagnosticSeverity.Warning);
    }

    private static IEnumerable<DiagnosticDescriptor> MigrationRuleDescriptors()
    {
        yield return Migration("NLM101", "C# modifier in N# file");
        yield return Migration("NLM102", "C# auto-property accessors");
        yield return Migration("NLM103", "Null-forgiving artifact");
        yield return Migration("NLM104", "Out parameter migration candidate");
        yield return Migration("NLM105", "DTO record candidate");
        yield return Migration("NLM106", "HTTP 500 catch boilerplate");
        yield return Migration("NLM107", "C# using directive");
        yield return Migration("NLM108", "C# namespace declaration");
        yield return Migration("NLM109", "Package declaration mismatch");
        yield return Migration("NLM110", "C# equals-style object initializer");
        yield return Migration("NLM111", "Unsafe value access migration smell");
    }

    private static DiagnosticDescriptor Linter(
        string code,
        string title,
        DiagnosticCategory category,
        DiagnosticSeverity severity,
        bool blocksBuild = false)
        => new(code, title, DiagnosticSource.Linter, category, severity, blocksBuild);

    private static DiagnosticDescriptor Migration(string code, string title)
        => new(code, title, DiagnosticSource.Migration, DiagnosticCategory.Migration, DiagnosticSeverity.Info, BlocksBuildByDefault: false);

    private static string ToTitle(string pascalCase)
    {
        var title = new System.Text.StringBuilder();
        for (var i = 0; i < pascalCase.Length; i++)
        {
            if (i > 0 && char.IsUpper(pascalCase[i]))
            {
                title.Append(' ');
            }

            title.Append(pascalCase[i]);
        }

        return title.ToString();
    }
}
