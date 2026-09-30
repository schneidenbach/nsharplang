namespace NSharpLang.CensusOverloadResolution.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Threading.Tasks


// ── the reflected world: the more specific parameter wins, and it really runs ─────────────────
//
// `Task.WhenAll` is the census's own shape read out of metadata: a NON-generic
// `WhenAll(IEnumerable<Task>): Task` sits beside a generic
// `WhenAll<TResult>(IEnumerable<Task<TResult>>): Task<TResult[]>`, and a `List<Task<int>>` satisfies
// both — the non-generic by an interface conversion, the generic by inferring `TResult = int`. Both
// score the same rung of the applicability ladder, so before "better conversion target" existed the
// answer was whichever candidate the MetadataLoadContext produced first, and the call's type became
// a bare `Task` that has no `Result` at all.
//
// THE ASSERTIONS ARE RUNTIME ONES ON PURPOSE. A chosen overload is only really chosen if the IL
// calls it, so the contract is the VALUE the call produced and the CLR type of the task it built,
// not a diagnostic.
func WhenAllOverSourceList(): Task<int[]> {
    tasks := new List<Task<int>>()
    tasks.Add(Task.FromResult<int>(7))
    tasks.Add(Task.FromResult<int>(11))
    return Task.WhenAll(tasks)
}

test "a generic overload whose parameter is the more specific type beats the non-generic one" {
    all := WhenAllOverSourceList()

    // The call's static type is `Task<int[]>` — reading `.Result` at all is the contract, because
    // the non-generic overload returns a `Task` that has no such member.
    results := all.Result
    assert results.Length == 2
    assert results[0] == 7
    assert results[1] == 11

    // AND THE BOUND METHOD IS THE GENERIC ONE, checked through the CLR object the call built rather
    // than through the compiler: the non-generic `WhenAll` cannot produce a `Task<int[]>`.
    built: object = all
    assert typeof(Task<int[]>).IsAssignableFrom(built.GetType())

    // Both candidates really are declared — a run where the non-generic overload had been removed
    // would assert nothing at all.
    candidates := OverloadNamedMethodCount(typeof(Task), "WhenAll")
    assert candidates > 1
}

test "the specific overload is chosen for a plain array receiver too, not only a List" {
    tasks := new Task<string>[2]
    tasks[0] = Task.FromResult<string>("a")
    tasks[1] = Task.FromResult<string>("b")
    all := Task.WhenAll(tasks)
    results := all.Result
    assert results.Length == 2
    assert results[0] == "a"
    assert results[1] == "b"
}

// `TaskExtensions.Unwrap` is the same shape one level further in: `Unwrap(Task<Task>): Task` beside
// `Unwrap<TResult>(Task<Task<TResult>>): Task<TResult>`. A `Task<Task<int>>` converts to `Task<Task>`
// by no conversion at all in the CLR — but `Task<Task<int>>` IS re-expressible as the generic
// parameter with `TResult = int`, and `Task<Task>` is reachable from it by a reference conversion, so
// the two used to tie and the non-generic one won by order.
test "the more specific overload wins when the difference is one type argument deep" {
    inner := Task.FromResult<int>(42)
    outer := Task.FromResult<Task<int>>(inner)
    unwrapped := outer.Unwrap()
    assert unwrapped.Result == 42
}

// ── the source world: the same rule, over N#-declared overloads ───────────────────────────────

class Shape {
    Sides: int

    constructor(sides: int) {
        Sides = sides
    }
}

class Square: Shape {
    constructor(): base(4) {
    }
}

// THE FOUR SPECIFICITY SHAPES THE RULE HAS TO GET RIGHT, each written as a pair whose members
// announce themselves, so the assertion below is a statement about which BODY ran.
class Specific {

    // A derived parameter is more specific than its base: `Square` converts to `Shape`, not back.
    static func Describe(_value: Shape): string {
        return "shape"
    }

    static func Describe(_value: Square): string {
        return "square"
    }

    // `T` bound to the argument's own type is an IDENTITY and beats `object`, which is only a
    // reference conversion away.
    static func Identify(_value: object): string {
        return "object"
    }

    static func Identify<T>(_value: T): string {
        return "generic"
    }

    // A signature that takes the arguments as declared beats one that has to expand a `params` tail.
    static func Collect(_first: int, _second: int): string {
        return "pair"
    }

    static func Collect(params _values: int[]): string {
        return "params"
    }

    // NEITHER parameter is the argument's own type, so the tie is broken purely by which is the more
    // SPECIFIC target: `Shape` converts to `object` and `object` does not convert back.
    static func Accept(_value: object): string {
        return "object"
    }

    static func Accept(_value: Shape): string {
        return "shape"
    }

    // A narrower numeric target is the better conversion target: a `short` widens to both, and `int`
    // converts to `long` while `long` does not convert back.
    static func Widen(_value: int): string {
        return "int"
    }

    static func Widen(_value: long): string {
        return "long"
    }
}

test "a derived parameter beats its base, and the base still binds for a base-typed argument" {
    square := new Square()
    assert Specific.Describe(square) == "square"

    plain := new Shape(3)
    assert Specific.Describe(plain) == "shape"
}

test "a type parameter bound to the argument's own type beats an `object` parameter" {
    assert Specific.Identify(5) == "generic"
    assert Specific.Identify("text") == "generic"
}

test "a signature that fits as written beats one that has to expand a params tail" {
    assert Specific.Collect(1, 2) == "pair"
    assert Specific.Collect(1, 2, 3) == "params"
    assert Specific.Collect() == "params"
}

test "the more specific target wins even when neither parameter is the argument's own type" {
    // `Square` is neither `object` nor `Shape`, so no position is an identity and the whole answer is
    // "which of the two parameter types is the more specific" — which is the rule that used to be
    // missing entirely.
    square := new Square()
    assert Specific.Accept(square) == "shape"

    // And a genuinely unrelated argument still reaches the only parameter that accepts it.
    assert Specific.Accept("text") == "object"
}

test "the narrower numeric parameter is the better conversion target for a widening argument" {
    small := Convert.ToInt16(3)
    assert Specific.Widen(small) == "int"

    wide := Convert.ToInt64(3)
    assert Specific.Widen(wide) == "long"
}

// ── the answer does not depend on the order the candidates were declared in ───────────────────
//
// "Better function member" is a PARTIAL order, and a running-best fold over a partial order answers
// whatever the declaration order makes it answer. These two classes declare the SAME overload set in
// OPPOSITE orders; a resolver that broke ties by order would disagree with itself here.
class DeclaredSpecificFirst {
    static func Of(_value: Square): string {
        return "square"
    }

    static func Of(_value: Shape): string {
        return "shape"
    }
}

class DeclaredGeneralFirst {
    static func Of(_value: Shape): string {
        return "shape"
    }

    static func Of(_value: Square): string {
        return "square"
    }
}

test "declaration order does not decide which overload a call binds" {
    square := new Square()
    assert DeclaredSpecificFirst.Of(square) == DeclaredGeneralFirst.Of(square)
    assert DeclaredSpecificFirst.Of(square) == "square"

    // And the same holds through the reflected world, whose candidate list arrives from a
    // MetadataLoadContext in no guaranteed order: two calls written the same way agree.
    first := Task.WhenAll(OverloadTaskList())
    second := Task.WhenAll(OverloadTaskList())
    assert first.Result.Length == second.Result.Length
    assert first.Result[0] == second.Result[0]
}

func OverloadTaskList(): List<Task<int>> {
    tasks := new List<Task<int>>()
    tasks.Add(Task.FromResult<int>(1))
    return tasks
}

// ── an `out` overload set accepts the very call the `out` signature exists for ─────────────────
//
// The census site is a seven-parameter `compileProjectWithIlBackend(..., out facts, ...)` whose
// sibling overload omits the `out` parameter. Scoring dropped the by-ref shell from the parameter
// while the argument carried one, so the ONLY candidate that fits was scored inapplicable and the
// call reported NL402 — but only when a sibling existed, because a lone declaration is never scored.
class Facts {
    Count: int

    constructor(count: int) {
        Count = count
    }
}

class Builder {
    static func Compile(root: string, out facts: Facts, includeTests: bool): string {
        facts = new Facts(root.Length)
        if includeTests {
            return root + "+tests"
        }

        return root
    }

    static func Compile(root: string, includeTests: bool): string {
        ignored: Facts = new Facts(0)
        return Compile(root, out ignored, includeTests)
    }
}

test "an overload set containing an `out` signature binds the call that passes `out`" {
    produced: Facts = new Facts(0)
    label := Builder.Compile("root", out produced, true)
    assert label == "root+tests"
    assert produced.Count == 4

    // The sibling overload reaches the `out` one itself, which is the census's own call shape.
    assert Builder.Compile("abc", false) == "abc"
}

// ── helpers ───────────────────────────────────────────────────────────────────────────────────

// How many public methods of a reflected type carry this name. Used to prove a candidate SET was in
// play, so a contract cannot pass by there being only one overload to choose from.
func OverloadNamedMethodCount(declaringType: Type, name: string): int {
    methods := declaringType.GetMethods(BindingFlags.Public | BindingFlags.Static)
    count := 0
    index := 0
    while index < methods.Length {
        if methods[index].Name == name {
            count = count + 1
        }

        index = index + 1
    }

    return count
}
