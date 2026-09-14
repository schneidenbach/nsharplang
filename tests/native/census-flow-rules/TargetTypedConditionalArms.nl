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
