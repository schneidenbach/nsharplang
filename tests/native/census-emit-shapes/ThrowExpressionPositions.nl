namespace NSharpLang.CensusEmitShapes

import System
import System.Threading.Tasks

// THE THREE POSITIONS A `throw` MAY STAND IN AS A VALUE, each emitted in place: the exception
// reference, then `throw`. Nothing is left on the stack and nothing follows on that path, so the
// branch structure the throw sits inside is the ordinary one — a `??` still short-circuits, a
// conditional still evaluates only the taken arm — and the SURVIVING side is what the expression is
// worth.

// A counter that makes the evaluation order observable: a left operand read twice, or an untaken
// conditional arm evaluated anyway, would show up here and nowhere else.
class ThrowProbe {
    Reads: int

    constructor() {
        Reads = 0
    }

    func Read(value: string?): string? {
        Reads = Reads + 1
        return value
    }
}

// `x ?? throw e` — a REFERENCE left operand. The expression is worth the left side with its
// nullability removed.
func RequiredName(probe: ThrowProbe, value: string?): string {
    return probe.Read(value) ?? throw new InvalidOperationException("name is required")
}

// The same shape over a `Nullable<T>`: the ABSENT branch raises instead of producing an element.
func RequiredPort(value: int?): int {
    return value ?? throw new InvalidOperationException("port is required")
}

// And over an open type parameter, where the nullness question is asked of the boxed value while the
// result stays `T`.
func RequiredValue<T>(value: T): T {
    return value ?? throw new InvalidOperationException("value is required")
}

// A conditional whose ELSE arm raises — the then arm decides the type.
func PortOrFail(probe: ThrowProbe, ok: bool, value: string): string {
    return ok ? (probe.Read(value) ?? "unset") : throw new ArgumentException("not configured")
}

// A conditional whose THEN arm raises — the mirror.
func FailOrPort(probe: ThrowProbe, reject: bool, value: string): string {
    return reject ? throw new ArgumentException("rejected") : (probe.Read(value) ?? "unset")
}

// An arrow-bodied function whose body IS the throw: there is nothing to return, so the path ends
// with `throw` rather than a `ret`.
func NotImplementedYet(): string => throw new NotImplementedException("later")

// An arrow body that coalesces into a throw.
func TrimmedOrFail(value: string?): string => value ?? throw new InvalidOperationException("empty")

// An arrow-bodied PROPERTY over the same shape.
class Settings {
    Raw: string?

    Name: string => Raw ?? throw new InvalidOperationException("no name")

    constructor(raw: string?) {
        Raw = raw
    }
}

// A `void` arrow body. A throw satisfies EVERY return type, `void` included: control never reaches
// the caller, so there is no value for `void` to object to.
func AlwaysFails() => throw new NotSupportedException("void arrow")

// And the `void` DELEGATE twin.
func VoidRejector(): Action {
    return () => throw new NotSupportedException("void lambda")
}

// A lambda whose expression body is a throw, and the same lambda with a value body for contrast.
func Rejector(): Func<int, string> {
    return n => throw new NotSupportedException("rejected " + n.ToString())
}

// An `async` body: the throw must land on the RETURNED TASK, not on the caller of the async method.
async func LoadName(value: string?): Task<string> {
    await Task.Delay(1)
    return value ?? throw new InvalidOperationException("async name is required")
}

// An `async` LAMBDA whose expression body is a throw — the same guarantee, through the delegate.
func AsyncRejector(): Func<Task<int>> {
    return async () => throw new NotSupportedException("async rejected")
}

// Inside a block-bodied local function: the local function is a method of its own, and the lowering
// is the ordinary one there too.
func ThroughLocalFunction(value: string?): string {
    func inner(candidate: string?): string {
        return candidate ?? throw new InvalidOperationException("local required")
    }

    return inner(value)
}

// A throw expression nested inside a conditional inside a coalesce fallback — the branch structures
// compose without either one losing its shape.
func Nested(primary: string?, fallback: string?, allowFallback: bool): string {
    return primary ?? (allowFallback ? (fallback ?? "default") : throw new ArgumentException("no fallback allowed"))
}
