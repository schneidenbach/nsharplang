using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler;

public enum DiagnosticSource
{
    Compiler,
    Linter
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
    Performance,
    Aot
}

public sealed record DiagnosticDescriptor(
    string Code,
    string Title,
    DiagnosticSource Source,
    DiagnosticCategory Category,
    DiagnosticSeverity DefaultSeverity,
    bool BlocksBuildByDefault,
    bool IsConfigurable = true,
    string? DocsUrl = null,
    string? Explanation = null);

public static class DiagnosticCatalog
{
    private static readonly Lazy<IReadOnlyDictionary<string, DiagnosticDescriptor>> DescriptorByCode =
        new(BuildDescriptorMap);

    public static IReadOnlyCollection<DiagnosticDescriptor> Descriptors => DescriptorByCode.Value.Values.ToArray();

    public static IReadOnlyCollection<DiagnosticDescriptor> LinterDescriptors =>
        Descriptors
            .Where(descriptor => descriptor.Source is DiagnosticSource.Linter)
            .ToArray();

    public static bool TryGetDescriptor(string code, out DiagnosticDescriptor descriptor)
        => DescriptorByCode.Value.TryGetValue(code, out descriptor!);

    public static DiagnosticSeverity GetDefaultSeverity(string code, DiagnosticSeverity fallback = DiagnosticSeverity.Warning)
        => TryGetDescriptor(code, out var descriptor) ? descriptor.DefaultSeverity : fallback;

    public static string DocsUrlFor(string code)
        => TryGetDescriptor(code, out var descriptor) && !string.IsNullOrWhiteSpace(descriptor.DocsUrl)
            ? descriptor.DocsUrl
            : $"https://docs.n-sharp.dev/errors/{code}";

    private static IReadOnlyDictionary<string, DiagnosticDescriptor> BuildDescriptorMap()
    {
        var descriptors = CompilerDescriptors()
            .Concat(PerformanceDescriptors())
            .Concat(AotDescriptors())
            .Concat(LinterRuleDescriptors())
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
            // Performance and AOT diagnostics are described explicitly in
            // PerformanceDescriptors() / AotDescriptors().
            if (IsPerformanceCode(code) || IsAotCode(code))
            {
                continue;
            }

            var diagnosticCode = $"NL{(int)code:D3}";
            var category = code switch
            {
                >= ErrorCode.UnexpectedToken and <= ErrorCode.ReservedKeywordAsName => DiagnosticCategory.Syntax,
                >= ErrorCode.TypeNotFound and <= ErrorCode.GenericConstraintViolation => DiagnosticCategory.Type,
                >= ErrorCode.UndefinedVariable and <= ErrorCode.ShadowedDeclaration => DiagnosticCategory.Semantic,
                >= ErrorCode.WrongArgumentCount and <= ErrorCode.UndefinedFunction => DiagnosticCategory.Function,
                >= ErrorCode.NonExhaustiveMatch and <= ErrorCode.ImpossiblePattern => DiagnosticCategory.Pattern,
                >= ErrorCode.InvalidOperatorOverload and <= ErrorCode.ConversionOperatorInvalid => DiagnosticCategory.Operator,
                >= ErrorCode.ImportNotFound and <= ErrorCode.NamespaceNotFound => DiagnosticCategory.Import,
                >= ErrorCode.MultipleInheritance and <= ErrorCode.ConstructorError => DiagnosticCategory.TypeDeclaration,
                ErrorCode.PossibleNullAccess or ErrorCode.NullabilityWarning => DiagnosticCategory.Nullability,
                ErrorCode.UnusedVariable or ErrorCode.UnreachableCode => DiagnosticCategory.Hygiene,
                ErrorCode.VisibilityConventionWarning or ErrorCode.ObsoleteUsage => DiagnosticCategory.Style,
                _ => DiagnosticCategory.Semantic
            };

            // All compiler diagnostics are build-blocking errors. N# is strict: semantic and
            // correctness signals (visibility convention NL903, obsolete usage NL904, possible
            // null access NL905, nullability NL907) all block the build rather than warn.
            const DiagnosticSeverity severity = DiagnosticSeverity.Error;

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
        yield return Linter("NL003", "Unnecessary null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL004", "Async without await", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL006", "Unreachable code", DiagnosticCategory.Semantic, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL010", "Unused import", DiagnosticCategory.Import, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL011", "Empty catch", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL012", "Unused parameter", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL016", "Redundant null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
        yield return Linter("NL020", "Shadowed variable", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, blocksBuild: true);
    }

    private static DiagnosticDescriptor Linter(
        string code,
        string title,
        DiagnosticCategory category,
        DiagnosticSeverity severity,
        bool blocksBuild = false)
        => new(code, title, DiagnosticSource.Linter, category, severity, blocksBuild);

    /// <summary>
    /// Descriptors for the performance diagnostics (NL950-NL999) the optimizer emits to
    /// explain allocations and dispatch decisions. These are advisory and never block builds.
    /// </summary>
    private static IEnumerable<DiagnosticDescriptor> PerformanceDescriptors()
    {
        yield return Performance(
            ErrorCode.AllocationHere,
            "Allocation here",
            DiagnosticSeverity.Info,
            "Allocates here because the value escapes its enclosing scope, so it cannot live on the stack.");

        yield return Performance(
            ErrorCode.BoxingHere,
            "Boxing here",
            DiagnosticSeverity.Warning,
            "Boxes here because a value type is used through an interface or object, forcing a heap allocation.");

        yield return Performance(
            ErrorCode.VirtualDispatchNotDevirtualized,
            "Virtual dispatch not devirtualized",
            DiagnosticSeverity.Info,
            "Uses callvirt here because the receiver type is not proven exact, so the call cannot be devirtualized or inlined.");

        yield return Performance(
            ErrorCode.ClosureAllocation,
            "Closure allocation",
            DiagnosticSeverity.Warning,
            "Allocates a closure here because the lambda captures variables from its enclosing scope.");

        yield return Performance(
            ErrorCode.DelegateAllocation,
            "Delegate allocation",
            DiagnosticSeverity.Warning,
            "Allocates a delegate here because a method group or lambda is converted to a delegate instance.");
    }

    private static DiagnosticDescriptor Performance(
        ErrorCode code,
        string title,
        DiagnosticSeverity severity,
        string explanation)
        => new(
            $"NL{(int)code:D3}",
            title,
            DiagnosticSource.Compiler,
            DiagnosticCategory.Performance,
            severity,
            BlocksBuildByDefault: false,
            IsConfigurable: true,
            DocsUrl: null,
            Explanation: explanation);

    private static bool IsPerformanceCode(ErrorCode code)
        => code is >= ErrorCode.AllocationHere and <= ErrorCode.DelegateAllocation;

    /// <summary>
    /// Descriptors for the AOT/trimming safety diagnostics (NL960-NL969). These are advisory
    /// (info) by default so ordinary builds are not blocked, but the AOT analysis pass promotes
    /// them to build-blocking errors when the user opts in with <c>--aot</c>.
    /// </summary>
    private static IEnumerable<DiagnosticDescriptor> AotDescriptors()
    {
        yield return Aot(
            ErrorCode.AotReflectionUse,
            "Reflection blocks AOT",
            "Uses runtime reflection here. The trimmer cannot see which members are accessed reflectively, so they may be removed, and Native AOT cannot resolve them ahead of time.");

        yield return Aot(
            ErrorCode.AotDynamicCode,
            "Dynamic code blocks AOT",
            "Generates or invokes code at runtime here (e.g. Reflection.Emit, Activator.CreateInstance, or dynamic dispatch). Native AOT has no JIT, so dynamically generated code cannot run.");

        yield return Aot(
            ErrorCode.AotMakeGenericType,
            "Runtime generic instantiation blocks AOT",
            "Constructs a generic type or method at runtime here (MakeGenericType / MakeGenericMethod). Native AOT only instantiates the generic combinations it can see at compile time.");

        yield return Aot(
            ErrorCode.AotExpressionTree,
            "Expression tree blocks AOT",
            "Builds or compiles a LINQ expression tree here. Compiling an expression tree emits IL at runtime, which Native AOT cannot do.");
    }

    private static DiagnosticDescriptor Aot(
        ErrorCode code,
        string title,
        string explanation)
        => new(
            $"NL{(int)code:D3}",
            title,
            DiagnosticSource.Compiler,
            DiagnosticCategory.Aot,
            DiagnosticSeverity.Info,
            BlocksBuildByDefault: false,
            IsConfigurable: true,
            DocsUrl: $"https://docs.n-sharp.dev/errors/NL{(int)code:D3}",
            Explanation: explanation);

    private static bool IsAotCode(ErrorCode code)
        => code is >= ErrorCode.AotReflectionUse and <= ErrorCode.AotExpressionTree;

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
