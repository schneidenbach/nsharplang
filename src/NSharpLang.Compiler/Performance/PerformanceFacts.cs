namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Why a value escapes (or does not escape) its defining frame.
/// Ordered from least to most escape: a value's effective escape is the
/// "widest" reason recorded for it, so callers can merge by taking the max.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum EscapeKind
{
    /// <summary>Value never leaves its defining frame.</summary>
    LocalOnly = 0,

    /// <summary>Value is returned from the function.</summary>
    Returned = 1,

    /// <summary>Value is stored into a field, array, or other heap location.</summary>
    Stored = 2,

    /// <summary>Value is passed to a call whose body the compiler cannot see.</summary>
    PassedToUnknown = 3,

    /// <summary>Value crosses a public ABI boundary consumable by other assemblies.</summary>
    PublicAbi = 4,

    /// <summary>Value is captured by an expression tree.</summary>
    ExpressionTree = 5,

    /// <summary>Value crosses a reflection or dynamic boundary.</summary>
    ReflectionBoundary = 6,
}

/// <summary>
/// How a closure captures state from its enclosing scope.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum CaptureKind
{
    /// <summary>No state is captured.</summary>
    None = 0,

    /// <summary>State is captured by value (readonly copy).</summary>
    ByValue = 1,

    /// <summary>State is captured by mutable shared storage (requires lifting).</summary>
    ByMutableStorage = 2,

    /// <summary>The enclosing instance (<c>this</c>) is captured.</summary>
    CapturesThis = 3,

    /// <summary>A ref-like value (e.g. <c>ref struct</c>/<c>Span&lt;T&gt;</c>) is captured.</summary>
    CapturesRefLike = 4,
}

/// <summary>
/// What kind of heap allocation, if any, a construct forces.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum AllocationKind
{
    /// <summary>Guaranteed no heap allocation.</summary>
    None = 0,

    /// <summary>A delegate object is allocated.</summary>
    Delegate = 1,

    /// <summary>A closure (display) class is allocated.</summary>
    Closure = 2,

    /// <summary>An array is allocated.</summary>
    Array = 3,

    /// <summary>An iterator or async state machine is allocated.</summary>
    IteratorStateMachine = 4,

    /// <summary>A value type is boxed.</summary>
    Boxing = 5,

    /// <summary>Allocation behavior could not be determined.</summary>
    Unknown = 6,
}

/// <summary>
/// How a call site dispatches to its target.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum DispatchKind
{
    /// <summary>Direct, statically resolved call.</summary>
    Direct = 0,

    /// <summary>Constrained call on a value type (no boxing).</summary>
    ConstrainedValueType = 1,

    /// <summary>Virtual dispatch through a class vtable.</summary>
    Virtual = 2,

    /// <summary>Interface dispatch.</summary>
    Interface = 3,

    /// <summary>Invocation through a delegate.</summary>
    DelegateInvoke = 4,

    /// <summary>Dispatch resolved via reflection or the dynamic runtime.</summary>
    ReflectionDynamic = 5,
}

/// <summary>
/// The runtime layout chosen for a value.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum ValueLayoutKind
{
    /// <summary>A primitive (int, double, bool, etc.).</summary>
    Primitive = 0,

    /// <summary>An enum.</summary>
    Enum = 1,

    /// <summary>An ordinary value-type struct.</summary>
    Struct = 2,

    /// <summary>A ref struct (stack-only).</summary>
    RefStruct = 3,

    /// <summary>A nullable value (<c>Nullable&lt;T&gt;</c> or nullable reference).</summary>
    Nullable = 4,

    /// <summary>A union represented as a tagged value layout.</summary>
    UnionRepresentation = 5,

    /// <summary>A heap reference object.</summary>
    ReferenceObject = 6,
}

/// <summary>
/// AOT/trimming safety classification for a construct.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public enum AotSafetyKind
{
    /// <summary>No reflection dependency; fully AOT/trim safe.</summary>
    NoReflection = 0,

    /// <summary>Requires runtime metadata to be preserved.</summary>
    MetadataRequired = 1,

    /// <summary>Requires dynamic code generation (not AOT compatible).</summary>
    DynamicCodeRequired = 2,

    /// <summary>Requires an expression tree (forces metadata/dynamic code).</summary>
    ExpressionTreeRequired = 3,
}

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
