using System;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// A single construct that prevents Native AOT / trimming, located at a source position
/// and tagged with the kind of safety guarantee it violates. Purely descriptive: produced
/// </summary>
public sealed record AotBlocker(
    AotSafetyKind Kind,
    string File,
    int Line,
    int Column,
    int Length,
    string Construct,
    AbiBoundary EnclosingBoundary,
    string? EnclosingDeclaration)
{
    /// <summary>The diagnostic code that describes this blocker.</summary>
    public ErrorCode DiagnosticCode => Kind switch
    {
        AotSafetyKind.MetadataRequired => ErrorCode.AotReflectionUse,
        AotSafetyKind.DynamicCodeRequired => Construct.Contains("MakeGeneric", StringComparison.Ordinal)
            ? ErrorCode.AotMakeGenericType
            : ErrorCode.AotDynamicCode,
        AotSafetyKind.ExpressionTreeRequired => ErrorCode.AotExpressionTree,
        _ => ErrorCode.AotDynamicCode,
    };

    public bool IsOnPublicSurface => EnclosingBoundary == AbiBoundary.ClrPublic;
}
