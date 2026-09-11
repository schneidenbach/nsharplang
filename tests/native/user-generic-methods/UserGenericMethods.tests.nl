namespace NSharpLang.UserGenericMethods.Tests

import System
import System.Reflection

// THE EXECUTABLE HALF OF "A USER TYPE MAY DECLARE A GENERIC METHOD".
//
// Every declaration below used to be refused at parse: the columnar struct/class/record member scan
// returned `NL103 — Declined at parse.struct` for ANY member whose signature carried type
// parameters, so `func Map<TResult>(...)` could not be written on a type at all. The estate states
// what the parser, the analyzer and the emitter now answer; this project states what the feature IS,
// by running it — every entry point reaches real IL through the columnar backend and reads a real
// value back.
//
// A GENERIC METHOD IS A REAL CLR GENERIC METHOD, AND THAT IS WHAT IS ASSERTED. One definition with
// open method type parameters, closed per call site with `MakeGenericMethod`; on a generic OWNER the
// definition is first rebound onto the receiver's instantiation. A test that only ran the calls
// could not tell that emission from one that erased the parameter to `object`, so the metadata is
// read back too: `IsGenericMethodDefinition`, the parameter count, and the declared constraints.

// A GENERIC OWNER carrying generic methods. `Of` is static and its parameter is the METHOD's, not
// the type's; `Same` and `Kind` mix the two scopes; `SelfCheck` calls a generic sibling through the
// implicit `this`, which is the only spelling that may name the owner bare.
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    static func Of<U>(value: U): Box<U> {
        return new Box<U>(value)
    }

    func Same<TOther>(other: TOther): bool {
        return other != null
    }

    func Kind<TOther>(): bool {
        return Value is TOther
    }

    func SelfCheck(): bool {
        return Same<int>(1)
    }
}

// A NON-GENERIC OWNER. Its methods' type parameters are the only ones in scope, which is the
// simplest shape and the one that proves the owner's arity does not participate.
class Plain {
    func Echo<T>(value: T): T {
        return value
    }

    func Pick<TFirst, TSecond>(a: TFirst, _b: TSecond): TFirst {
        return a
    }

    static func Wrap<T>(value: T): Box<T> {
        return new Box<T>(value)
    }

    static func Count<T>(values: T[]): int {
        return values.Length
    }
}

// A RECORD owner, so the feature is not quietly limited to the two nominal kinds above.
record Labelled(Label: string) {
    func Tag<T>(_value: T): string {
        return Label
    }
}

// AN UNCONSTRAINED TYPE PARAMETER MAY BE CLOSED OVER EITHER KIND, and its null questions have to
// answer for both. The CLR has one instruction that does: `box !!T` yields the reference itself for a
// reference instantiation and a fresh non-null box for a value one, so `value == null` is false for
// every value instantiation and a real null test for every reference one — C#'s reading. Comparing
// the raw stack value instead compared an unboxed `int` against a null reference and answered TRUE
// for `Nullable<int>(0)`.
struct Unconstrained<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func IsNull(): bool {
        return Value == null
    }

    func IsNotNull(): bool {
        return Value != null
    }

    func OrElse(other: T): T {
        return Value ?? other
    }
}

// A REFERENCE generic owner, so the instance-call opcode split (callvirt for a reference receiver,
// call on the address of a value receiver) is exercised on both sides.
class Holder<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func Match<TOther>(other: TOther): bool {
        return other != null
    }
}

// A DELEGATE PARAMETER written over BOTH scopes — the owner's `TOk`/`TErr` and the method's own
// `TResult`. `Func<TOk, TResult>` is an instantiation whose arguments are unbaked builders, so its
// `Invoke` is reached through the open definition and rebound onto the instantiation; the shape is
// closed at the call site, where the lambda is then contextually typed against a real delegate.
// This is the `Result<TOk, TErr>.Match<TResult>` shape.
struct Outcome<TOk, TErr> {
    State: int
    Ok: TOk
    Err: TErr

    constructor(state: int, ok: TOk, err: TErr) {
        State = state
        Ok = ok
        Err = err
    }

    func Match<TResult>(ok: Func<TOk, TResult>, err: Func<TErr, TResult>): TResult {
        if State == 1 {
            return ok(Ok)
        }
        return err(Err)
    }

    func Select<TResult>(f: Func<TOk, TResult>): TResult {
        return f(Ok)
    }
}

class Seed {
    Number: int

    constructor() {
        Number = 5
    }
}

interface IIdentified {
    func GetId(): int
}

class Identified: IIdentified {
    Id: int

    constructor(id: int) {
        Id = id
    }

    func GetId(): int {
        return Id
    }
}

// CONSTRAINED generic methods, one per special constraint plus a source-interface constraint. The
// constraints are validated at the call site (Reflection.Emit does not validate them for an unbaked
// builder) and they reach CLR metadata, which the reflection tests below read back.
class Constrained {
    static func RequireReference<T>(value: T): bool where T: class {
        return value != null
    }

    static func RequireValue<T>(_value: T): bool where T: struct {
        return true
    }

    // `new()` is declared and VALIDATED at the call site (a type argument without an accessible
    // parameterless constructor does not bind) and reaches metadata. The body does not write
    // `new T()`: constructing a bare type parameter is not emitted for a free generic function
    // either, so it is not this feature's contract.
    static func RequireConstructible<T>(_value: T): bool where T: new() {
        return true
    }

    static func ReadId<T>(value: T): int where T: IIdentified {
        return value.GetId()
    }
}

// ---- EXECUTION -------------------------------------------------------------------------------

func ExplicitOnGenericOwner(): int {
    box := new Box<int>(3)
    total := 0
    if box.Kind<int>() {
        total = total + 1
    }
    if box.Same<string>("x") {
        total = total + 2
    }
    if box.SelfCheck() {
        total = total + 4
    }
    return total
}

func InferredOnGenericOwner(): int {
    box := new Box<int>(3)
    total := 0
    if box.Same(9) {
        total = total + 1
    }
    constructed := Box<int>.Of(4)
    return total + constructed.Value
}

func ExplicitOnGenericOwnerStatic(): int {
    return Box<int>.Of<int>(6).Value
}

func ExplicitOnPlainOwner(): int {
    plain := new Plain()
    return plain.Echo<int>(7) + plain.Pick<int, string>(2, "b")
}

func InferredOnPlainOwner(): int {
    plain := new Plain()
    return plain.Echo(7) + plain.Pick(2, "b")
}

func StaticOnPlainOwner(): int {
    values: int[] = [1, 2, 3]
    return Plain.Wrap<int>(5).Value + Plain.Wrap(6).Value + Plain.Count(values)
}

func OnRecordOwner(): string {
    labelled := new Labelled("tag")
    return labelled.Tag<int>(1) + labelled.Tag(2)
}

func OnReferenceGenericOwner(): int {
    holder := new Holder<int>(3)
    total := 0
    if holder.Match<string>("x") {
        total = total + 1
    }
    if holder.Match(9) {
        total = total + 2
    }
    return total
}

func ConstrainedCalls(): int {
    identified := new Identified(11)
    total := 0
    if Constrained.RequireReference<string>("a") {
        total = total + 1
    }
    if Constrained.RequireValue<int>(1) {
        total = total + 2
    }
    if Constrained.RequireConstructible<Seed>(new Seed()) {
        total = total + 4
    }
    return total + Constrained.ReadId<Identified>(identified)
}

func DelegateOverBothScopes(): string {
    ok := new Outcome<int, string>(1, 3, "")
    err := new Outcome<int, string>(2, 0, "bad")
    return ok.Match<string>(v => v.ToString(), e => e) + err.Match<string>(v => v.ToString(), e => e) + ok.Select<int>(v => v + 1).ToString()
}

func UnconstrainedNullAnswers(): string {
    valueInstantiation := new Unconstrained<int>(0)
    nullReference := new Unconstrained<string?>(null)
    liveReference := new Unconstrained<string?>("x")
    answers := ""
    answers = answers + (valueInstantiation.IsNull() ? "1" : "0")
    answers = answers + (valueInstantiation.IsNotNull() ? "1" : "0")
    answers = answers + (nullReference.IsNull() ? "1" : "0")
    answers = answers + (nullReference.IsNotNull() ? "1" : "0")
    answers = answers + (liveReference.IsNull() ? "1" : "0")
    answers = answers + (liveReference.IsNotNull() ? "1" : "0")
    return answers
}

func UnconstrainedCoalesce(): string {
    valueInstantiation := new Unconstrained<int>(0)
    nullReference := new Unconstrained<string?>(null)
    liveReference := new Unconstrained<string?>("x")
    return valueInstantiation.OrElse(9).ToString() + (nullReference.OrElse("fallback") ?? "?") + (liveReference.OrElse("fallback") ?? "?")
}

// ---- REFLECTION HELPERS ------------------------------------------------------------------------

func InstanceMethod(owner: Type, name: string): MethodInfo? {
    return owner.GetMethod(name, BindingFlags.Public | BindingFlags.Instance)
}

func StaticMethod(owner: Type, name: string): MethodInfo? {
    return owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
}

func GenericArity(method: MethodInfo?): int {
    if method == null {
        return -1
    }
    return method.GetGenericArguments().Length
}

func IsOpenGenericMethod(method: MethodInfo?): bool {
    if method == null {
        return false
    }
    return method.get_IsGenericMethodDefinition()
}

func FirstTypeParameter(method: MethodInfo?): Type? {
    if method == null {
        return null
    }
    arguments := method.GetGenericArguments()
    if arguments.Length == 0 {
        return null
    }
    return arguments[0]
}

func SpecialConstraintWord(method: MethodInfo?): int {
    parameter := FirstTypeParameter(method)
    if parameter == null {
        return -1
    }
    return Convert.ToInt32(parameter.get_GenericParameterAttributes())
}

func ConstraintCount(method: MethodInfo?): int {
    parameter := FirstTypeParameter(method)
    if parameter == null {
        return -1
    }
    return parameter.GetGenericParameterConstraints().Length
}

func FirstConstraintName(method: MethodInfo?): string {
    parameter := FirstTypeParameter(method)
    if parameter == null {
        return ""
    }
    constraints := parameter.GetGenericParameterConstraints()
    if constraints.Length == 0 {
        return ""
    }
    return constraints[0].get_Name()
}

// ---- TESTS -------------------------------------------------------------------------------------

test "a generic method on a generic owner runs with written type arguments" {
    assert ExplicitOnGenericOwner() == 7
}

test "a generic method on a generic owner infers its type arguments" {
    assert InferredOnGenericOwner() == 5
}

test "a generic static on a constructed generic owner runs both ways" {
    assert ExplicitOnGenericOwnerStatic() == 6
}

test "a generic method on a non-generic owner runs with written type arguments" {
    assert ExplicitOnPlainOwner() == 9
}

test "a generic method on a non-generic owner infers its type arguments" {
    assert InferredOnPlainOwner() == 9
}

test "a generic static on a non-generic owner runs both ways" {
    assert StaticOnPlainOwner() == 14
}

test "a record may declare a generic method" {
    assert OnRecordOwner() == "tagtag"
}

test "a generic method on a reference generic owner runs both ways" {
    assert OnReferenceGenericOwner() == 3
}

test "constrained generic methods run and their arguments satisfy the constraints" {
    assert ConstrainedCalls() == 18
}

test "a delegate parameter written over both scopes is invoked through its instantiation" {
    assert DelegateOverBothScopes() == "3bad4"
}

test "an unconstrained type parameter answers its null questions for both kinds" {
    // A VALUE instantiation is never null; a REFERENCE one answers by its reference.
    assert UnconstrainedNullAnswers() == "011001"
}

test "coalescing over an unconstrained type parameter keeps the value instantiation's value" {
    assert UnconstrainedCoalesce() == "0fallbackx"
}

test "a generic method is a real CLR generic method definition" {
    boxDefinition := typeof(Box<int>).GetGenericTypeDefinition()
    assert IsOpenGenericMethod(InstanceMethod(boxDefinition, "Same"))
    assert GenericArity(InstanceMethod(boxDefinition, "Same")) == 1
    assert IsOpenGenericMethod(StaticMethod(boxDefinition, "Of"))
    assert GenericArity(StaticMethod(boxDefinition, "Of")) == 1

    // The OWNER's arity and the METHOD's are independent: `Box<T>` has one, `Of<U>` has one, and
    // `Pick<TFirst, TSecond>` on a non-generic owner has two.
    assert boxDefinition.GetGenericArguments().Length == 1
    assert GenericArity(InstanceMethod(typeof(Plain), "Pick")) == 2
    assert IsOpenGenericMethod(InstanceMethod(typeof(Plain), "Echo"))
    assert typeof(Plain).GetGenericArguments().Length == 0
}

test "a non-generic method beside a generic one keeps its own metadata" {
    boxDefinition := typeof(Box<int>).GetGenericTypeDefinition()
    assert !IsOpenGenericMethod(InstanceMethod(boxDefinition, "SelfCheck"))
    assert GenericArity(InstanceMethod(boxDefinition, "SelfCheck")) == 0
}

test "a method type parameter is a method parameter, not the owner's" {
    boxDefinition := typeof(Box<int>).GetGenericTypeDefinition()
    parameter := FirstTypeParameter(InstanceMethod(boxDefinition, "Same"))
    assert parameter != null
    if parameter != null {
        assert parameter.get_IsGenericMethodParameter()
        assert !parameter.get_IsGenericTypeParameter()
        assert parameter.get_Name() == "TOther"
    }

    ownerParameter := boxDefinition.GetGenericArguments()[0]
    assert ownerParameter.get_IsGenericTypeParameter()
    assert ownerParameter.get_Name() == "T"
}

test "generic method constraints reach CLR metadata" {
    // ECMA-335 GenericParameterAttributes: ReferenceTypeConstraint 0x04, NotNullableValueType 0x08,
    // DefaultConstructor 0x10. The value-type constraint implies the default-constructor bit.
    assert (SpecialConstraintWord(StaticMethod(typeof(Constrained), "RequireReference")) & 4) != 0
    assert (SpecialConstraintWord(StaticMethod(typeof(Constrained), "RequireValue")) & 8) != 0
    assert (SpecialConstraintWord(StaticMethod(typeof(Constrained), "RequireConstructible")) & 16) != 0
    assert SpecialConstraintWord(StaticMethod(typeof(Constrained), "ReadId")) == 0
    assert ConstraintCount(StaticMethod(typeof(Constrained), "ReadId")) == 1
    assert FirstConstraintName(StaticMethod(typeof(Constrained), "ReadId")) == "IIdentified"
    assert ConstraintCount(StaticMethod(typeof(Constrained), "RequireReference")) == 0
}
