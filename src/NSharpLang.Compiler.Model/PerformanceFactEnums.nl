namespace NSharpLang.Compiler.Performance

enum EscapeKind {
    LocalOnly,
    Returned,
    Stored,
    PassedToUnknown,
    PublicAbi,
    ExpressionTree,
    ReflectionBoundary
}

enum CaptureKind {
    None,
    ByValue,
    ByMutableStorage,
    CapturesThis,
    CapturesRefLike
}

enum AllocationKind {
    None,
    Delegate,
    Closure,
    Array,
    IteratorStateMachine,
    Boxing,
    Unknown
}

enum DispatchKind {
    Direct,
    ConstrainedValueType,
    Virtual,
    Interface,
    DelegateInvoke,
    ReflectionDynamic
}

enum ValueLayoutKind {
    Primitive,
    Enum,
    Struct,
    RefStruct,
    Nullable,
    UnionRepresentation,
    ReferenceObject
}

enum AotSafetyKind {
    NoReflection,
    MetadataRequired,
    DynamicCodeRequired,
    ExpressionTreeRequired
}
