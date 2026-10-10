namespace NSharpLang.Compiler.Performance

record PerformanceFacts(escape: EscapeKind, capture: CaptureKind, allocation: AllocationKind, dispatch: DispatchKind, valueLayout: ValueLayoutKind, aotSafety: AotSafetyKind) {
    Escape: EscapeKind = escape
    Capture: CaptureKind = capture
    Allocation: AllocationKind = allocation
    Dispatch: DispatchKind = dispatch
    ValueLayout: ValueLayoutKind = valueLayout
    AotSafety: AotSafetyKind = aotSafety

    static Default: PerformanceFacts => new PerformanceFacts(EscapeKind.LocalOnly, CaptureKind.None, AllocationKind.None, DispatchKind.Direct, ValueLayoutKind.ReferenceObject, AotSafetyKind.NoReflection)
}
