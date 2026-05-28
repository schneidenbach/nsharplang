using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// How a <c>union</c> declaration is laid out at the IL level.
/// </summary>
public enum UnionLayoutKind
{
    /// <summary>
    /// The historical representation: an abstract base class with one nested
    /// sealed class per case. Each construction allocates (<c>newobj</c>) and each
    /// pattern test is a reference-type <c>isinst</c> against the case class.
    /// This is the safe fallback for every union that is not value-struct
    /// eligible, and it preserves full C#-interop class semantics.
    /// </summary>
    ClassHierarchy,

    /// <summary>
    /// An allocation-free representation: a <c>readonly struct</c> carrying an
    /// integer tag (plus, in future, the inlined case payload fields). Construction
    /// writes the tag instead of allocating, and a pattern test is an integer tag
    /// compare. The union type itself is a value type (<c>IsValueType == true</c>),
    /// and remains consumable from C#.
    /// </summary>
    ValueStruct,
}

/// <summary>
/// Pure-analysis pass that decides, per <see cref="UnionDeclaration"/>, whether a
/// union is eligible for the allocation-free value-struct representation.
///
/// This pass has NO emitter side effects; it only answers a yes/no question plus
/// the reason, so the emitter can choose a layout and so tooling can explain the
/// decision. Anything that is not eligible MUST keep the
/// <see cref="UnionLayoutKind.ClassHierarchy"/> representation so existing
/// class-based semantics and C# interop are never regressed.
/// </summary>
public static class UnionValueLayout
{
    /// <summary>
    /// Maximum number of cases for a union to still be considered "small". Beyond
    /// this, the class-hierarchy representation is kept: very large unions gain
    /// little from inlining and the tag-dispatch chain grows unwieldy.
    /// </summary>
    public const int MaxValueStructCases = 16;

    /// <summary>
    /// The result of classifying a single union declaration.
    /// </summary>
    public readonly record struct Decision(UnionLayoutKind Layout, string Reason)
    {
        public bool IsValueStruct => Layout == UnionLayoutKind.ValueStruct;
    }

    /// <summary>
    /// Classify a union declaration's layout.
    /// </summary>
    /// <remarks>
    /// A union is value-struct eligible when ALL of the following hold:
    /// <list type="bullet">
    /// <item>It is closed (declared up front with a fixed set of cases — which every
    /// N# <c>union</c> declaration is; anonymous <c>A | B</c> unions are handled by the
    /// separate runtime-union machinery and never reach here).</item>
    /// <item>It has at least one case and no more than <see cref="MaxValueStructCases"/>.</item>
    /// <item>Every case is value-type-friendly (see <see cref="IsValueFriendlyCase"/>).</item>
    /// </list>
    ///
    /// Named union declarations carry no type parameters today, so the non-generic
    /// requirement is satisfied structurally; should generic unions ever be added,
    /// they will need an explicit guard before reaching the value-struct emitter.
    ///
    /// SCOPE (Unit 15): the initial value-struct emitter only fully lowers
    /// <em>payload-free</em> unions (every case is a bare tag). Cases that carry
    /// payloads are value-type-friendly in principle, but lowering their inlined
    /// field access / construction / binding is deferred. Until that lands,
    /// <see cref="HasPayloads"/> lets the emitter keep payload-carrying unions on the
    /// class path even though they are otherwise eligible, so no existing behavior
    /// regresses. Eligibility itself is computed for the full criteria so the
    /// remaining work is a pure emitter extension.
    /// </remarks>
    public static Decision Classify(UnionDeclaration union)
    {
        if (union is null)
        {
            return new Decision(UnionLayoutKind.ClassHierarchy, "union declaration was null");
        }

        if (union.Cases is null || union.Cases.Count == 0)
        {
            return new Decision(UnionLayoutKind.ClassHierarchy, "union has no cases");
        }

        if (union.Cases.Count > MaxValueStructCases)
        {
            return new Decision(
                UnionLayoutKind.ClassHierarchy,
                $"union has {union.Cases.Count} cases (max {MaxValueStructCases} for value-struct layout)");
        }

        foreach (var unionCase in union.Cases)
        {
            if (!IsValueFriendlyCase(unionCase))
            {
                return new Decision(
                    UnionLayoutKind.ClassHierarchy,
                    $"case '{unionCase.Name}' is not value-type-friendly");
            }
        }

        return new Decision(UnionLayoutKind.ValueStruct, "small, closed, value-friendly union");
    }

    /// <summary>
    /// True when the union qualifies for value-struct layout AND the emitter can
    /// fully lower it today. See the scope note on <see cref="Classify"/>: the
    /// current emitter slice handles payload-free unions only.
    /// </summary>
    public static bool IsValueStructEmittable(UnionDeclaration union)
    {
        return Classify(union).IsValueStruct && !HasPayloads(union);
    }

    /// <summary>True when any case of the union carries one or more payload properties.</summary>
    public static bool HasPayloads(UnionDeclaration union)
    {
        return union?.Cases is { } cases && cases.Any(c => c.Properties is { Count: > 0 });
    }

    /// <summary>
    /// A case is value-type-friendly when its payload (if any) consists only of
    /// fields that can live inside a struct without forcing a heap allocation of
    /// the case itself. A payload-free case is trivially friendly. We intentionally
    /// do NOT recurse into payload field types here: a field whose type is itself a
    /// reference type is fine (the struct just stores the reference); what matters
    /// for the allocation-free win is that the <em>case</em> need not be boxed.
    /// </summary>
    public static bool IsValueFriendlyCase(UnionCase unionCase)
    {
        if (unionCase is null)
        {
            return false;
        }

        // No payload => pure tag, always value-friendly.
        if (unionCase.Properties is null || unionCase.Properties.Count == 0)
        {
            return true;
        }

        // Payload present: each property must have a declared type. (Every union
        // case property is required to declare a type by the parser, so this is a
        // defensive check rather than a real rejection path.)
        return unionCase.Properties.All(p => p.Type is not null);
    }
}
