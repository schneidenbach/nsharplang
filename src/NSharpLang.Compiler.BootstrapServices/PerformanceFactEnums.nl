namespace NSharpLang.Compiler.Performance

public enum EscapeKind {
    LocalOnly,
    Returned,
    Stored,
    PassedToUnknown,
    PublicAbi,
    ExpressionTree,
    ReflectionBoundary
}

public enum CaptureKind {
    None,
    ByValue,
    ByMutableStorage,
    CapturesThis,
    CapturesRefLike
}

public enum AllocationKind {
    None,
    Delegate,
    Closure,
    Array,
    IteratorStateMachine,
    Boxing,
    Unknown
}

public enum DispatchKind {
    Direct,
    ConstrainedValueType,
    Virtual,
    Interface,
    DelegateInvoke,
    ReflectionDynamic
}

public enum ValueLayoutKind {
    Primitive,
    Enum,
    Struct,
    RefStruct,
    Nullable,
    UnionRepresentation,
    ReferenceObject
}

public enum AotSafetyKind {
    NoReflection,
    MetadataRequired,
    DynamicCodeRequired,
    ExpressionTreeRequired
}
