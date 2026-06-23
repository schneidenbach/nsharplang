using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Which AOT-safety annotations a declaration needs on the public surface, derived from the
/// AOT blockers found inside it. The IL emitter consults this to stamp
/// <c>[RequiresUnreferencedCode]</c> (for reflection/trimming) and
/// <c>[RequiresDynamicCode]</c> (for runtime code generation / expression trees) onto the
/// methods that contain blockers, so downstream C#/AOT consumers see the same warnings the
/// .NET BCL emits. Attribute emission is metadata-only and does not change emitted IL bodies,
/// keeping output verifiable and GC-safe.
/// </summary>
public sealed class AotRequirements
{
    /// <summary>The annotations a single declaration requires.</summary>
    public readonly record struct Annotation(
        bool RequiresUnreferencedCode,
        bool RequiresDynamicCode,
        string Message);

    private readonly Dictionary<string, Annotation> _byDeclaration;

    private AotRequirements(Dictionary<string, Annotation> byDeclaration)
    {
        _byDeclaration = byDeclaration;
    }

    internal static AotRequirements FromMap(Dictionary<string, Annotation> byDeclaration) =>
        new(byDeclaration);

    /// <summary>An empty requirement set (no annotations needed).</summary>
    public static AotRequirements Empty { get; } = new(new Dictionary<string, Annotation>(StringComparer.Ordinal));

    public bool IsEmpty => _byDeclaration.Count == 0;

    /// <summary>
    /// Look up the annotation a declaration (by its N# name) requires, if any.
    /// </summary>
    public bool TryGet(string declarationName, out Annotation annotation)
        => _byDeclaration.TryGetValue(declarationName, out annotation);

    /// <summary>
    /// Build the requirement set from analysis blockers. Only blockers on the public CLR
    /// surface produce annotations — file-private/internal/local code is invisible to external
    /// consumers, so annotating it would be noise. A declaration that contains a reflection
    /// blocker gets <c>[RequiresUnreferencedCode]</c>; one that generates code at runtime (dynamic
    /// code, runtime generics, expression trees) gets <c>[RequiresDynamicCode]</c>. A declaration
    /// can require both.
    /// </summary>
    public static AotRequirements FromBlockers(IEnumerable<AotBlocker> blockers)
    {
        var blockerList = blockers as IReadOnlyList<AotBlocker> ?? new List<AotBlocker>(blockers);
        if (blockerList.Count == 0)
            return Empty;

        return AotRequirementSelector.BuildRequirements(blockerList);
    }

    internal static string CreateAnnotationMessage(IEnumerable<string> constructs) =>
        $"Uses AOT-unsafe constructs ({string.Join(", ", constructs)}); not safe under Native AOT or trimming.";
}
