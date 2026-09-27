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

func AssignedLocal(flag: bool, n: int): int {
    picked: int? = null
    picked = flag ? n : null
    return picked ?? -1
}

func ArgumentPosition(flag: bool, n: int): int => Unwrap(flag ? n : null)

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
