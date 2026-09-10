namespace NSharpLang.GenericStaticMembers.Tests

import System
import System.Reflection

// THE EXECUTABLE HALF OF "A GENERIC TYPE MAY CARRY STATIC MEMBERS".
//
// Every declaration below used to be refused outright: `NL323 — Static field 'Count' is not supported
// on generic type 'PerTypeState<T>' yet`, with the same sentence for a static property, a static
// method and an operator. The estate contracts state what the parser, the analyzer and the planners
// now answer; this project states what the feature IS, by running it — every entry point reaches
// real IL through the columnar backend and reads a real value back.
//
// THE POINT OF THE FEATURE IS THE SEPARATION, AND THAT IS WHAT IS ASSERTED. A static member of a
// generic type is declared ONCE and the CLR gives every constructed instantiation its own copy:
// `PerTypeState<int>.Count` and `PerTypeState<string>.Count` are two different slots, two different
// `FieldInfo`s, and two different type initializer runs. A test that only read one instantiation
// could not tell a correct emission from one that shared a single static slot across all of them, so
// every stateful case here reads at least two instantiations and compares them.
class PerTypeState<T> {
    static Count: int

    static Current: int => Count

    static func Increment(): int {
        Count = Count + 1
        return Count
    }
}

// A static field with an INITIALIZER, and a `static readonly` one beside it. The initializer runs in
// the type initializer, which the CLR runs once PER CONSTRUCTED TYPE — so `Seeded<int>` and
// `Seeded<string>` each get their own 7 and their own 3, and writing one does not move the other.
class Seeded<T> {
    static readonly Origin: int = 7
    static Slot: int = 3

    static Total: int => Origin + Slot
}

struct Tagged<T> {
    Tag: int

    constructor(tag: int) {
        Tag = tag
    }

    static func operator ==(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag == right.Tag
    }

    static func operator !=(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag != right.Tag
    }
}

struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    // The probe shape from the capability gap: a static factory whose parameter and return type are
    // both written in the type's own parameter, calling the type's own constructor.
    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }

    // A camelCase (package-private) static helper, reached both from a static member and from an
    // INSTANCE member of the same generic type. A bare call to it inside the type must name the
    // current instantiation, not the open definition — a method-definition token on an open generic
    // type is one the CLR refuses to execute.
    static func unwrap(source: Box<T>): T {
        return source.Value
    }

    static func Read(source: Box<T>): T {
        return unwrap(source)
    }

    func Copy(): Box<T> {
        return new Box<T>(unwrap(new Box<T>(Value)))
    }
}

// A private constructor reached only through the type's own static factories — the `Result`/`Union`
// shape, in miniature. `state` is 0 for a default value, 1 for an Ok and 2 for an Err; the arm the
// factory does not carry is left at its zero value, which is what a struct's unassigned field is.
struct Tally<TOk, TErr> {
    ok: TOk
    err: TErr
    state: byte

    private constructor(okValue: TOk, stateValue: byte) {
        ok = okValue
        state = stateValue
    }

    private constructor(errValue: TErr, stateValue: byte, errArm: bool) {
        err = errValue
        state = stateValue
    }

    static func Ok(value: TOk): Tally<TOk, TErr> {
        return new Tally<TOk, TErr>(value, 1)
    }

    static func Err(value: TErr): Tally<TOk, TErr> {
        return new Tally<TOk, TErr>(value, 2, true)
    }

    IsOk: bool => state == 1
    IsErr: bool => state == 2
    OkValue: TOk => ok
    ErrValue: TErr => err
}

// CONVERSION OPERATORS ON A GENERIC TYPE. A conversion operator is a static method under a reserved
// name (`op_Implicit`/`op_Explicit`), so it reaches the emitter through the same constructed-owner
// path as `Create` above — but it is asked for from the OTHER end. `implicit operator Wrap<T>(value: T)`
// is the shape `Union<T0, T1>` needs and it can only be written on the type converted TO: the `T` end
// is whatever the instantiation supplies, and `int` declares nothing about `Wrap`.
struct Wrap<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    implicit operator Wrap<T>(value: T) => new Wrap<T>(value)

    explicit operator T(wrapped: Wrap<T>) => wrapped.Value
}

func TakeWrappedInt(wrapped: Wrap<int>): int {
    return wrapped.Value
}

func ReturnWrappedText(): Wrap<string> {
    return "returned"
}

// A STATIC CALL WHOSE TYPE ARGUMENT IS THE ENCLOSING TYPE'S OWN PARAMETER. `HashCode.Combine(Tag,
// Value)` closes an external generic method over `T`, which Reflection.Emit encodes as a MethodSpec
// over the source type parameter and the CLR resolves once per constructed type. It is what
// `Result<TOk, TErr>.GetHashCode` is made of.
struct Hasher<T> {
    Value: T
    Tag: byte

    constructor(value: T, tag: byte) {
        Value = value
        Tag = tag
    }

    override func GetHashCode(): int {
        return HashCode.Combine(Tag, Value)
    }
}

// An accessor-bodied static property over a camelCase static field, so both accessors are exercised
// through the type name.
class Counter<T> {
    static count: int

    static Value: int {
        get {
            return count
        }
        set {
            count = value
        }
    }
}

test "a static field of a generic type is separate storage per constructed type" {
    PerTypeState<int>.Count = 0
    PerTypeState<string>.Count = 0

    assert PerTypeState<int>.Increment() == 1
    assert PerTypeState<int>.Increment() == 2
    assert PerTypeState<string>.Current == 0
    assert PerTypeState<string>.Increment() == 1
    assert PerTypeState<int>.Count == 2
    assert PerTypeState<string>.Count == 1
}

test "a static field initializer runs once per constructed type" {
    assert Seeded<int>.Origin == 7
    assert Seeded<string>.Origin == 7
    assert Seeded<int>.Total == 10
    assert Seeded<string>.Total == 10

    Seeded<int>.Slot = 100

    assert Seeded<int>.Total == 107
    assert Seeded<string>.Total == 10

    Seeded<int>.Slot = 3
}

test "an accessor-bodied static property reads and writes its own constructed type's storage" {
    Counter<int>.Value = 5
    Counter<string>.Value = 9

    assert Counter<int>.Value == 5
    assert Counter<string>.Value == 9
}

test "a static factory on a generic struct builds the constructed type" {
    boxed := Box<int>.Create(42)
    assert boxed.Value == 42

    text := Box<string>.Create("hi")
    assert text.Value == "hi"
}

test "a package-private static helper is reachable from static and instance members of its own type" {
    assert Box<int>.Read(Box<int>.Create(11)) == 11
    assert Box<string>.Read(Box<string>.Create("x")) == "x"

    copied := Box<int>.Create(6).Copy()
    assert copied.Value == 6
}

test "static factories reach a private constructor of their own generic type" {
    ok := Tally<int, string>.Ok(42)
    assert ok.IsOk
    assert !ok.IsErr
    assert ok.OkValue == 42

    failed := Tally<int, string>.Err("failure")
    assert failed.IsErr
    assert !failed.IsOk
    assert failed.ErrValue == "failure"

    swapped := Tally<string, int>.Ok("value")
    assert swapped.IsOk
    assert swapped.OkValue == "value"
}

test "a static call closed over the enclosing type's own parameter runs per constructed type" {
    assert new Hasher<string>("abc", 1).GetHashCode() == HashCode.Combine((byte)1, "abc")
    assert new Hasher<int>(7, 2).GetHashCode() == HashCode.Combine((byte)2, 7)

    // The same declaration, two instantiations, two different hashes — the MethodSpec is resolved
    // against the constructed type rather than baked at the declaration.
    assert new Hasher<int>(7, 2).GetHashCode() != new Hasher<int>(8, 2).GetHashCode()
}

test "an implicit conversion operator declared by a constructed generic converts into it" {
    assigned: Wrap<int> = 5
    assert assigned.Value == 5

    text: Wrap<string> = "hello"
    assert text.Value == "hello"

    assert TakeWrappedInt(9) == 9
    assert ReturnWrappedText().Value == "returned"
}

test "an explicit conversion operator declared by a constructed generic converts out of it" {
    wrapped := new Wrap<int>(17)
    unwrapped := (int)wrapped
    assert unwrapped == 17

    wrappedText := new Wrap<string>("out")
    assert (string)wrappedText == "out"
}

test "operators declared on a generic struct bind on each constructed type" {
    a := new Tagged<int>(1)
    b := new Tagged<int>(1)
    c := new Tagged<int>(2)

    assert a == b
    assert !(a == c)
    assert a != c
    assert !(a != b)

    s := new Tagged<string>(5)
    t := new Tagged<string>(5)
    assert s == t
    assert !(s != t)
}

// THE METADATA HALF. The runtime assertions above would also pass if two constructed types happened
// to share one slot and the test only ever read one of them; these read the CLR's own answer.
// Deliberately NO name string is asserted: whether a constructed generic's CLR name carries a
// backtick-arity suffix is a separate contract, and `typeof` identity states what this project is
// about without depending on it.
//
// The reflection questions are asked through small helpers rather than inline, because every
// reflection lookup answers a NULLABLE handle and N# holds a test to the same null discipline as any
// other code: the helper proves the handle is there and answers a plain value.

func StaticFieldsAreDistinct(left: Type, right: Type, name: string): bool {
    flags := BindingFlags.Public | BindingFlags.Static
    leftField := left.GetField(name, flags)
    rightField := right.GetField(name, flags)
    if leftField == null || rightField == null {
        return false
    }
    return !Object.ReferenceEquals(leftField, rightField)
}

func HasStaticField(owner: Type, name: string): bool {
    return owner.GetField(name, BindingFlags.Public | BindingFlags.Static) != null
}

func HasStaticMethod(owner: Type, name: string, publicOnly: bool): bool {
    flags := publicOnly ? BindingFlags.Public | BindingFlags.Static : BindingFlags.NonPublic | BindingFlags.Static
    method := owner.GetMethod(name, flags)
    if method == null {
        return false
    }
    return method.get_IsStatic()
}

func IsStaticSpecialName(owner: Type, name: string): bool {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
    if method == null {
        return false
    }
    return method.get_IsStatic() && method.get_IsSpecialName()
}

func StaticMethodReturn(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
    if method == null {
        return typeof(object)
    }
    return method.get_ReturnType()
}

func StaticMethodFirstParameter(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
    if method == null {
        return typeof(object)
    }
    parameters := method.GetParameters()
    if parameters.Length == 0 {
        return typeof(object)
    }
    return parameters[0].get_ParameterType()
}

func StaticMethodsAreDistinct(left: Type, right: Type, name: string): bool {
    flags := BindingFlags.Public | BindingFlags.Static
    leftMethod := left.GetMethod(name, flags)
    rightMethod := right.GetMethod(name, flags)
    if leftMethod == null || rightMethod == null {
        return false
    }
    return !Object.ReferenceEquals(leftMethod, rightMethod)
}

test "each constructed type owns its own static FieldInfo over one shared declaration" {
    assert HasStaticField(typeof(PerTypeState<int>), "Count")
    assert HasStaticField(typeof(PerTypeState<string>), "Count")
    assert StaticFieldsAreDistinct(typeof(PerTypeState<int>), typeof(PerTypeState<string>), "Count")
    assert typeof(PerTypeState<int>) != typeof(PerTypeState<string>)
    assert typeof(PerTypeState<int>).GetGenericTypeDefinition() == typeof(PerTypeState<string>).GetGenericTypeDefinition()
}

test "a static method and an operator are declared on the open definition and are static in metadata" {
    definition := typeof(Box<int>).GetGenericTypeDefinition()
    assert HasStaticMethod(definition, "Create", true)
    assert HasStaticMethod(definition, "unwrap", false)

    taggedDefinition := typeof(Tagged<int>).GetGenericTypeDefinition()
    assert IsStaticSpecialName(taggedDefinition, "op_Equality")
    assert IsStaticSpecialName(taggedDefinition, "op_Inequality")
}

test "the constructed static method is the one declaration seen through its instantiation" {
    assert StaticMethodsAreDistinct(typeof(Box<int>), typeof(Box<string>), "Create")
    assert StaticMethodReturn(typeof(Box<int>), "Create") == typeof(Box<int>)
    assert StaticMethodReturn(typeof(Box<string>), "Create") == typeof(Box<string>)
    assert StaticMethodFirstParameter(typeof(Box<int>), "Create") == typeof(int)
    assert StaticMethodFirstParameter(typeof(Box<string>), "Create") == typeof(string)
}

// The conversion operators are ordinary special-name statics on the OPEN definition, and each
// instantiation sees them with its own arguments substituted — the same one-declaration/many-views
// relation the static factory has.
test "conversion operators are special-name statics on the open definition, seen per instantiation" {
    definition := typeof(Wrap<int>).GetGenericTypeDefinition()
    assert IsStaticSpecialName(definition, "op_Implicit")
    assert IsStaticSpecialName(definition, "op_Explicit")

    assert StaticMethodReturn(typeof(Wrap<int>), "op_Implicit") == typeof(Wrap<int>)
    assert StaticMethodFirstParameter(typeof(Wrap<int>), "op_Implicit") == typeof(int)
    assert StaticMethodReturn(typeof(Wrap<string>), "op_Implicit") == typeof(Wrap<string>)
    assert StaticMethodFirstParameter(typeof(Wrap<string>), "op_Implicit") == typeof(string)

    assert StaticMethodReturn(typeof(Wrap<int>), "op_Explicit") == typeof(int)
    assert StaticMethodFirstParameter(typeof(Wrap<int>), "op_Explicit") == typeof(Wrap<int>)
}

// A private constructor stays private in metadata even though the type's own static factories reach
// it: the accessibility is the declaration's, not the call site's.
test "the private constructor of a generic struct is private in metadata" {
    definition := typeof(Tally<int, string>).GetGenericTypeDefinition()
    publicConstructors := definition.GetConstructors(BindingFlags.Public | BindingFlags.Instance)
    privateConstructors := definition.GetConstructors(BindingFlags.NonPublic | BindingFlags.Instance)

    assert publicConstructors.Length == 0
    assert privateConstructors.Length == 2
}
