namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Aggregate bundle of performance facts attached to a Bound IR node / source position.
/// Purely descriptive data — carries no behavior and is not yet wired into emission.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public record PerformanceFacts(
    EscapeKind Escape,
    CaptureKind Capture,
    AllocationKind Allocation,
    DispatchKind Dispatch,
    ValueLayoutKind ValueLayout,
    AotSafetyKind AotSafety)
{
    /// <summary>
    /// The most conservative default: nothing escapes, nothing captures, nothing allocates,
    /// dispatch is direct, layout is a reference object, and the construct is AOT safe.
    /// Analyses widen these facts as evidence accumulates.
    /// </summary>
    public static PerformanceFacts Default { get; } = new(
        EscapeKind.LocalOnly,
        CaptureKind.None,
        AllocationKind.None,
        DispatchKind.Direct,
        ValueLayoutKind.ReferenceObject,
        AotSafetyKind.NoReflection);
}
