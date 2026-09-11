namespace NSharpLang.Compiler

import System
import System.Reflection
import System.Threading


// A `ref`/`out` ARGUMENT AS A CALL FACT.
//
// `f(x)` and `f(ref x)` are DIFFERENT CALLS even when `x` has the same type, and only the second may
// bind a `ref` parameter. Until this fact existed the planner typed no by-ref argument at all, so no
// by-ref call reached overload resolution and `Interlocked.Exchange`, `int.TryParse(text, out field)`
// and every user `ref` method with a field argument declined together.
//
// The contracts below are the three halves of that fact: WHAT A BY-REF PARAMETER MAY BE (a reference
// to anything an ordinary slot may hold, and never a reference to a reference), HOW A BY-REF ARGUMENT
// SCORES (exactly, in both directions, with no conversion — an alias to a converted temporary would
// be an alias to something the caller cannot see), and THE END-TO-END SELECTION of
// `Interlocked.Exchange<T>(ref T, T)`, which needs a `T` inferred from the by-ref position and a
// `null` that converts to it rather than contradicting it.
func ByRefFactsFor(argumentCount: int): ColumnarDirectCallArgumentFacts {
    return ColumnarDirectCallArgumentFacts.Empty(argumentCount)
}

func ByRefTypes1(first: Type): Type[] {
    result := new Type[](1)
    result[0] = first
    return result
}

func ByRefTypes2(first: Type, second: Type): Type[] {
    result := new Type[](2)
    result[0] = first
    result[1] = second
    return result
}

// ── what a by-ref parameter may be ────────────────────────────────────────────────────────────

test "a by-reference parameter is supported and a by-reference return is not" {
    empty := new Type[](0)
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(typeof(int).MakeByRefType(), empty)
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(typeof(string).MakeByRefType(), empty)
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(typeof(int), empty)

    // The RETURN question is unchanged: a by-ref return has no owner.
    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType(typeof(int).MakeByRefType(), empty)
}

test "a by-reference parameter may not reference an unsupported shape" {
    empty := new Type[](0)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(typeof(Action<int>).GetGenericTypeDefinition().MakeByRefType(), empty)
}

// ── how a by-ref argument scores ──────────────────────────────────────────────────────────────

test "a by-reference argument matches a by-reference parameter of the same element type" {
    facts := ByRefFactsFor(1)
    facts.IsByRefArgument[0] = true

    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(int).MakeByRefType()), ByRefTypes1(typeof(int)), facts) == 8
    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(string).MakeByRefType()), ByRefTypes1(typeof(string)), facts) == 8
}

// BOTH DIRECTIONS. `f(x)` may not bind `ref`, and `f(ref x)` may not bind an ordinary parameter.
test "a by-reference argument and an ordinary parameter never bind each other" {
    byRef := ByRefFactsFor(1)
    byRef.IsByRefArgument[0] = true
    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(int)), ByRefTypes1(typeof(int)), byRef) == -1

    plain := ByRefFactsFor(1)
    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(int).MakeByRefType()), ByRefTypes1(typeof(int)), plain) == -1
}

// NO CONVERSION. A by-ref argument aliases the caller's storage, so `ref int` may not feed
// `ref long` the way an ordinary `int` feeds a `long` parameter.
test "a by-reference element type is exact" {
    facts := ByRefFactsFor(1)
    facts.IsByRefArgument[0] = true

    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(long).MakeByRefType()), ByRefTypes1(typeof(int)), facts) == -1
    assert ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ByRefTypes1(typeof(object).MakeByRefType()), ByRefTypes1(typeof(string)), facts) == -1
}

test "a by-reference argument cannot also be a literal" {
    facts := ByRefFactsFor(1)
    facts.IsByRefArgument[0] = true
    facts.IsNullLiteral[0] = true

    threw := false
    try {
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(ByRefTypes1(typeof(string)), facts)
    } catch error: InvalidOperationException {
        threw = true
    }

    assert threw
}

// ── the end-to-end selection ──────────────────────────────────────────────────────────────────

// `Interlocked.Exchange(ref count, 0)` binds the NON-generic `Exchange(ref int, int)` overload, and
// nothing about the generic sibling at the same arity may take it.
test "a non-generic by-reference overload is selected by ordinary resolution" {
    facts := ByRefFactsFor(2)
    facts.IsByRefArgument[0] = true
    facts.IsUnsuffixedIntegerLiteral[1] = true

    selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(typeof(Interlocked), "Exchange", ByRefTypes2(typeof(int), typeof(int)), facts, true)
    assert selection.IsSelected
    method := selection.Method
    assert method != null
    assert selection.ParameterTypes.Length == 2
    assert selection.ParameterTypes[0] == typeof(int).MakeByRefType()
    assert selection.ParameterTypes[1] == typeof(int)
    assert selection.ReturnType == typeof(int)
    assert selection.IsStatic
}

// `Interlocked.Exchange(ref handler, null)` binds the GENERIC `Exchange<T>(ref T, T)`: `T` comes from
// the by-ref position, and the `null` — which carries no type at all — contributes nothing instead of
// contradicting it with the `object` placeholder its slot holds.
test "the generic by-reference overload infers its type argument from the by-ref position" {
    facts := ByRefFactsFor(2)
    facts.IsByRefArgument[0] = true
    facts.IsNullLiteral[1] = true

    selection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(typeof(Interlocked), "Exchange", ByRefTypes2(typeof(Action), typeof(object)), facts, true)
    assert selection.IsSelected
    method := selection.Method
    assert method != null
    assert selection.ParameterTypes.Length == 2
    assert selection.ParameterTypes[0] == typeof(Action).MakeByRefType()
    assert selection.ParameterTypes[1] == typeof(Action)
    assert selection.ReturnType == typeof(Action)
    assert selection.IsStatic
}

test "the same overload infers from a written value as well as from a null" {
    facts := ByRefFactsFor(2)
    facts.IsByRefArgument[0] = true

    selection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(typeof(Interlocked), "Exchange", ByRefTypes2(typeof(string), typeof(string)), facts, true)
    assert selection.IsSelected
    assert selection.ParameterTypes[0] == typeof(string).MakeByRefType()
    assert selection.ReturnType == typeof(string)
}

// A by-ref argument that names storage of the WRONG type still refuses, so the new door does not
// widen what binds.
test "the generic by-reference overload refuses a mismatched value" {
    facts := ByRefFactsFor(2)
    facts.IsByRefArgument[0] = true

    selection := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(typeof(Interlocked), "Exchange", ByRefTypes2(typeof(string), typeof(Action)), facts, true)
    assert !selection.IsSelected
}
