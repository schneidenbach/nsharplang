namespace NSharpLang.TypeArity.Tests

import System
import System.Collections.Generic
import Example


// WHAT A TYPE IS, EXECUTED.
//
// These run against the IL this project's own sources emit, so every claim below is about real CLR
// metadata rather than about a compiler table. Two things are proved together, because they are the
// same fact seen from two sides:
//
//   (1) A NAME AND AN ARITY ARE ONE IDENTITY. `Subscription` and `Subscription<T>` are two types, a
//       reference selects the one whose arity it writes, and the generic one may derive from its
//       non-generic sibling.
//   (2) THE METADATA NAME SAYS SO. A generic type's CLR name carries the arity suffix every other
//       .NET language reads it by — `Subscription``1 — while a non-generic type keeps its bare name.
//       Before this, a generic N# type was emitted under its bare name, so `Subscription` and
//       `Subscription<T>` could not coexist and a C# consumer could not name the generic one at all.
func TypeArityNameOf(value: Type): string {
    return value.get_Name()
}

test "a generic type's CLR metadata name carries its arity, and a non-generic type's does not" {
    generic: Type = typeof(Subscription<int>)
    assert generic.get_Name() == "Subscription`1"

    plain: Type = typeof(Subscription)
    assert plain.get_Name() == "Subscription"
}

test "the open definition behind a constructed type is the arity-named one" {
    definition := typeof(Subscription<int>).GetGenericTypeDefinition()
    assert definition.get_Name() == "Subscription`1"
    assert definition.get_IsGenericTypeDefinition()
    assert definition.GetGenericArguments().Length == 1
}

// THE DEFECT THIS REPLACES, EXECUTED: `class Subscription<T>: Subscription` reported NL306, NL307
// and NL207 at once, because the two declarations were one identity in the analyzer's tables.
test "a generic type may derive from its non-generic sibling of the same name" {
    generic: Type = typeof(Subscription<int>)
    plain: Type = typeof(Subscription)

    assert generic.get_BaseType() == plain
    assert generic.IsSubclassOf(plain)
    assert plain.IsAssignableFrom(generic)
    assert !plain.IsSubclassOf(generic)
}

test "a reference selects the declaration whose arity it writes" {
    fromGeneric: object = MakeSubscription()
    assert fromGeneric.GetType() == typeof(Subscription<int>)
    assert fromGeneric.GetType().get_Name() == "Subscription`1"

    fromPlain: object = MakePlainSubscription()
    assert fromPlain.GetType() == typeof(Subscription)
    assert fromPlain.GetType().get_Name() == "Subscription"
}

test "a generic-typed return keeps the closed type, and its value carries the arity name" {
    typed := MakeTypedSubscription()
    assert typed.Value == 9

    boxed: object = typed
    assert boxed.GetType() == typeof(Subscription<int>)
}

// ── the namespace-qualified pair ──────────────────────────────────────────────────────────────

test "a namespace-qualified base reference resolves to the non-generic sibling" {
    generic: Type = typeof(Handle<string>)
    plain: Type = typeof(Example.Handle)

    assert generic.get_BaseType() == plain
    assert generic.IsSubclassOf(plain)
}

test "the emitted full names carry the namespace and the arity" {
    assert typeof(Example.Handle).get_FullName() == "Example.Handle"
    assert typeof(Handle<string>).GetGenericTypeDefinition().get_FullName() == "Example.Handle`1"
    assert typeof(Example.Handle).get_Namespace() == "Example"
    assert typeof(Handle<string>).get_Namespace() == "Example"
}

test "a namespace-qualified generic value reports the generic sibling's identity" {
    handle: object = MakeHandle()
    assert handle.GetType() == typeof(Handle<string>)
    assert handle.GetType().get_Name() == "Handle`1"
}

// THE TWO SPELLINGS ARE ONE IDENTITY. `Example.Handle` used to fall out of the analyzer's resolution
// walk as a SECOND type instance beside the one `Handle` resolves to, so `func M(): Example.Handle`
// reported NL202 for every value the bare spelling accepted. These call the qualified-return-type,
// qualified-parameter, qualified-local, qualified-`is` and qualified-generic-argument forms and read
// back the SAME runtime type the bare spelling produces.
test "a namespace-qualified return type accepts what the bare one accepts" {
    plain: object = MakeQualifiedHandle()
    assert plain.GetType() == typeof(Handle<string>)
    assert plain.GetType().get_BaseType() == typeof(Example.Handle)

    generic := MakeQualifiedGenericHandle()
    assert generic.Value == "g"

    boxedGeneric: object = generic
    assert boxedGeneric.GetType() == typeof(Example.Handle<string>)
    assert typeof(Example.Handle<string>) == typeof(Handle<string>)
}

test "a namespace-qualified parameter, local and is-test name the same type as the bare spelling" {
    assert QualifiedRoundTrip(new Handle<string>("r")) == "g"
    assert QualifiedRoundTrip(new Handle()) == "g"
}

test "a namespace-qualified type is the same generic argument as the bare one" {
    handles := QualifiedHandleList()
    assert handles.Count == 1

    bare: List<Handle> = handles
    assert bare.Count == 1
}

// ── value types, and three arities of one name ────────────────────────────────────────────────

test "a struct and its generic namesakes are three distinct value types" {
    plain: Type = typeof(Cell)
    one: Type = typeof(Cell<int>)
    two: Type = typeof(Cell<int, string>)

    assert plain.get_Name() == "Cell"
    assert one.get_Name() == "Cell`1"
    assert two.get_Name() == "Cell`2"

    assert plain.get_IsValueType()
    assert one.get_IsValueType()
    assert two.get_IsValueType()

    assert plain != one
    assert one != two
    assert plain != two
}

test "each arity of one struct name constructs and reads back its own shape" {
    plain := MakeCell()
    assert plain.Value == 1

    one := MakeCellOfInt()
    assert one.Value == 2

    two := MakeCellOfIntAndString()
    assert two.Key == 3
    assert two.Value == "three"
}

test "the arity-1 and arity-2 open definitions are two different types" {
    oneDefinition := typeof(Cell<int>).GetGenericTypeDefinition()
    twoDefinition := typeof(Cell<int, string>).GetGenericTypeDefinition()

    assert oneDefinition.GetGenericArguments().Length == 1
    assert twoDefinition.GetGenericArguments().Length == 2
    assert oneDefinition != twoDefinition
}
