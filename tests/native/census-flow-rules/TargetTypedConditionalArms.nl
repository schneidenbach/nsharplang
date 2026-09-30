namespace NSharpLang.CensusFlowRules.Tests

import System


// A CONDITIONAL WHOSE ARM HAS NO TYPE OF ITS OWN TAKES THE TARGET'S.
//
// `flag ? name : null` is the shape a converter writes for every maybe-absent result, and it only
// ever emitted when BOTH arms could be unified against each other — which is to say when the typed
// arm was already a reference. A VALUE arm had nothing to lift to (`flag ? n : null` on an `int?`
// died at emit as `emit.statement.block-child`, kind 20), and `ok ? null : throw a` had no typed arm
// left to borrow from at all (`emit.conditional.throw-and-null`, until now a documented limit).
//
// The TARGET decides both: the return type, the declared local's type, the assigned local's type or
// the parameter's type says what a `null`, a `default` or a lifted value arm is worth. The one shape
// that still has nothing to take is BOTH arms throwing, which C# refuses for the same reason.
func PickReference(flag: bool, name: string): string? => flag ? name : null

func PickReferenceNullFirst(flag: bool, name: string): string? => flag ? null : name

func PickValue(flag: bool, n: int): int? => flag ? n : null

func PickValueNullFirst(flag: bool, n: int): int? => flag ? null : n

func PickDefaultArm(flag: bool, n: int): int? => flag ? n : default

// A conditional arm can itself need the target when one of its arms is typeless. This is the
// original nested regression pair: parentheses must not hide the inner target-typed conditional.
func PickNestedDefault(a: bool, b: bool, n: int): int? => a ? (b ? default : 1) : n

func PickNestedNull(a: bool, b: bool, n: int): int? => a ? (b ? null : 1) : n

func PickNestedDefaultElse(a: bool, b: bool, n: int): int? => a ? n : b ? 1 : default

func PickNestedNullElse(a: bool, b: bool, n: int): int? => a ? n : b ? 1 : null

func PickNestedThrowThen(a: bool, b: bool, n: int, failure: Exception): int? => a ? (b ? throw failure : 2) : n

func PickNestedThrowElse(a: bool, b: bool, n: int, failure: Exception): int? => a ? n : b ? 2 : throw failure

func PickDepthThree(a: bool, b: bool, c: bool, n: int): int? => a ? (b ? (c ? default : 3) : 4) : n

func PickDepthThreeUnparenthesized(a: bool, b: bool, c: bool, n: int): int? => a ? b ? c ? 3 : null : 4 : n

func PickNestedString(a: bool, b: bool, text: string, fallback: string): string? => a ? (b ? default : text) : fallback

func PickNestedStringNull(a: bool, b: bool, text: string, fallback: string): string? => a ? b ? text : null : fallback

func PickNestedStringThrow(a: bool, b: bool, text: string, fallback: string, failure: Exception): string? => a ? (b ? throw failure : text) : fallback

// A THROWING ARM AGAINST A BARE `null`: the raising arm produces no value, so the literal has only
// the target to take its type from.
func NullOrThrowReference(ok: bool, failure: Exception): string? => ok ? null : throw failure

func NullOrThrowValue(ok: bool, failure: Exception): int? => ok ? null : throw failure

func ValueOrThrow(ok: bool, n: int, failure: Exception): int? => ok ? throw failure : n

// THE SAME RULE AT THE OTHER THREE TARGET POSITIONS.
func DeclaredLocal(flag: bool, n: int): int {
    picked: int? = flag ? n : null
    return picked ?? -1
}

func DeclaredNestedLocal(a: bool, b: bool, n: int): int {
    picked: int? = a ? (b ? default : 6) : n
    return picked ?? -1
}

func AssignedLocal(flag: bool, n: int): int {
    picked: int? = null
    picked = flag ? n : null
    return picked ?? -1
}

func AssignedNestedLocal(a: bool, b: bool, n: int): int {
    picked: int? = null
    picked = a ? b ? 7 : null : n
    return picked ?? -1
}

func BlockNestedReturn(a: bool, b: bool, n: int): int? {
    return a ? (b ? default : 8) : n
}

func ArgumentPosition(flag: bool, n: int): int => Unwrap(flag ? n : null)

func NestedArgument(a: bool, b: bool, n: int): int => Unwrap(a ? (b ? default : 9) : n)

func NestedArgumentNullElse(a: bool, b: bool, n: int): int => Unwrap(a ? n : b ? 10 : null)

func Unwrap(value: int?): int => value ?? -1

// A WIDER ELEMENT AND AN ENUM take the same route: the lifted conversion owns the typed arm.
enum Shade {
    Light = 0,
    Dark = 1
}

func PickLong(flag: bool, value: long): long? => flag ? value : null

func PickShade(flag: bool, value: Shade): Shade? => flag ? value : null

func ShadeOrDefault(value: Shade?): Shade => value ?? Shade.Light

// AN ARGUMENT WHOSE CALLEE IS CHOSEN BY ITS ARGUMENTS. A static or instance method the emitter binds by
// asking whether every argument can match a declared parameter -- a framework method, and a method of a
// class in a REFERENCED assembly (`census-external-operands` holds that half) -- was told a conditional
// with a typeless arm could not match, so `string.IsNullOrEmpty(flag ? null : name)` declined the whole
// program at `emit.call.static-member-unmodeled` while a sibling `func` took the same argument. The
// methods below are the SAME-assembly controls, and a framework static is the external one this project
// can reach on its own. A typed arm that is a DERIVED class reaches a base-class parameter, as it does
// when it is passed alone.
class Shape {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

class Circle: Shape {
    constructor(name: string): base(name) {
    }
}

class Describer {
    Prefix: string

    constructor(prefix: string) {
        Prefix = prefix
    }

    static func Describe(label: string?, count: int): string {
        if label == null {
            return "none:" + count.ToString()
        }
        return label + ":" + count.ToString()
    }

    static func NameOf(shape: Shape?): string {
        if shape == null {
            return "<none>"
        }
        return shape.Name
    }

    static func CountOf(value: int?): int => value ?? -1

    func Label(suffix: string?): string {
        if suffix == null {
            return Prefix
        }
        return Prefix + suffix
    }
}

func StaticNullFirst(flag: bool, label: string): string => Describer.Describe(flag ? null : label, 1)

func StaticNullSecond(flag: bool, label: string): string => Describer.Describe(flag ? label : null, 2)

func DerivedArm(flag: bool, circle: Circle): string => Describer.NameOf(flag ? null : circle)

func LiftedArm(flag: bool, n: int): int => Describer.CountOf(flag ? null : n)

func InstanceArgument(flag: bool, describer: Describer, suffix: string): string => describer.Label(flag ? null : suffix)

func FrameworkStatic(flag: bool, text: string): bool => string.IsNullOrEmpty(flag ? null : text)

func FrameworkStaticNullSecond(flag: bool, text: string): bool => string.IsNullOrEmpty(flag ? text : null)

// A TYPELESS ARM WHERE THE CALLEE IS AN OVERLOAD GROUP. A group — N#'s own or a framework's — walks
// each argument BEFORE a parameter is chosen, so the analyzer had no target to give a `default` and said
// "I can't figure out what type 'default' should be" (NL203) about a call whose parameter says exactly
// that; and the conditional answered `unknown`, which every overload accepts, so `Measure(flag ? null :
// n)` was ambiguous (NL414) and the `default` form was both. The OTHER arm now decides which overload
// applies — made nullable beside a `null` — and the chosen parameter decides what the `default` is:
// `null` for an `int?` or a `string?`, zero for an `int`.
class Meter {
    Offset: long

    constructor(offset: long) {
        Offset = offset
    }

    static func Measure(value: int?): int => value ?? -1

    static func Measure(value: string?): int {
        if value == null {
            return -2
        }
        return value.Length
    }

    static func Plain(value: int): int => value + 100

    static func Plain(value: string): int => value.Length

    func Shift(value: long?): long => (value ?? -1) + Offset

    func Shift(value: string?): long {
        if value == null {
            return -5
        }
        return value.Length + Offset
    }
}

func MeasureDefaultFirst(flag: bool, n: int): int => Meter.Measure(flag ? default : n)

func MeasureDefaultSecond(flag: bool, text: string): int => Meter.Measure(flag ? text : default)

func MeasureNullFirst(flag: bool, n: int): int => Meter.Measure(flag ? null : n)

func MeasureNullSecond(flag: bool, text: string): int => Meter.Measure(flag ? text : null)

// A NON-NULLABLE PARAMETER: its `default` is zero, not an absent value.
func PlainDefault(flag: bool, n: int): int => Meter.Plain(flag ? default : n)

func ShiftDefault(flag: bool, meter: Meter, n: long): long => meter.Shift(flag ? default : n)

func ShiftNull(flag: bool, meter: Meter, text: string): long => meter.Shift(flag ? null : text)

func FrameworkStaticDefault(flag: bool, text: string): bool => string.IsNullOrEmpty(flag ? default : text)

func FrameworkValueDefault(flag: bool, n: int): int => Math.Max(flag ? default : n, -3)
func NestedFrameworkNull(a: bool, b: bool, text: string, fallback: string): bool => string.IsNullOrEmpty(a ? (b ? null : text) : fallback)

func NestedFrameworkThrow(a: bool, b: bool, text: string, fallback: string, failure: Exception): bool => string.IsNullOrEmpty(a ? (b ? throw failure : text) : fallback)
