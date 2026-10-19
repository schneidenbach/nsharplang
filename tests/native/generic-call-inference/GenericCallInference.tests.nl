namespace NSharpLang.GenericCallInference.Tests

import System
import System.Collections.Immutable
import System.Collections.Generic
import System.Text.Json
import System.Text
import System.Linq
import System.Threading.Tasks
import Microsoft.Extensions.DependencyInjection

// GENERIC METHOD CALLS WHOSE TYPE ARGUMENTS ARE NOT ALL SPELLED OUT, OR WHOSE ARGUMENTS NEED THEM
// BEFORE THEY CAN BIND.
//
// Four shapes the columnar emitter used to decline although every one is ordinary C#:
//   1. an INFERRED type argument beside an OMITTED optional parameter (`Serialize(value)`);
//   2. an INFERRED type argument beside a `params` tail the call fills (`Create(1, 2, 3, 4, 5)`);
//   3. WRITTEN type arguments beside an INLINE LAMBDA (`AddSingleton<Svc>(sp => ...)`), where the
//      lambda can only be bound once the written arguments have closed the delegate parameter;
//   4. an INHERITED generic method called on `this` or on the implicit receiver.
// Every row executes the call and reads the value back.

record Point {
    X: int
    Y: int
}

class Svc {
    N: int
}

class Holder {
    Items: List<int> = new List<int>()
}

class Registry {
    func Add<T>(): int {
        return 1
    }
}

class PublicDefaultConstructorSource {
    Value: int

    constructor() {
        Value = 19
    }
}

class InheritedSetPerson {
}

class GenericSetBase {
    func Set<T>(): int {
        return 31
    }
}

class SetOverloadDerived: GenericSetBase {
    func Set(count: int): int {
        return count
    }

    func ReadPeople(): int {
        return Set<InheritedSetPerson>()
    }
}

// ─── 1. INFERRED TYPE ARGUMENT, OMITTED OPTIONAL PARAMETER ────────────────────────────────────────

test "an inferred type argument with an omitted optional parameter binds: int" {
    assert JsonSerializer.Serialize(5) == "5"
}

test "an inferred type argument with an omitted optional parameter binds: string" {
    assert JsonSerializer.Serialize("a") == "\"a\""
}

test "an inferred type argument with an omitted optional parameter binds: record" {
    p := new Point { X: 1, Y: 2 }
    assert JsonSerializer.Serialize(p) == "{\"X\":1,\"Y\":2}"
}

test "control: the optional argument supplied and the type argument written still bind" {
    o := new JsonSerializerOptions()
    assert JsonSerializer.Serialize(5, o) == "5"
    assert JsonSerializer.Serialize<int>(5) == "5"
}

test "an inferred generic serialization composes inside Encoding.GetBytes" {
    d := new string[](1)
    d[0] = "a"

    bytes := Encoding.UTF8.GetBytes(JsonSerializer.Serialize(d))
    assert Encoding.UTF8.GetString(bytes) == "[\"a\"]"
    assert bytes.Length == 5

    empty := new string[](0)
    emptyBytes := Encoding.UTF8.GetBytes(JsonSerializer.Serialize(empty))
    assert Encoding.UTF8.GetString(emptyBytes) == "[]"
}

test "an inferred type accepts lower bounds when one converts to the other" {
    storage := new List<object>()
    storage.Add("found")
    objects: IEnumerable<object> = storage

    assert Enumerable.Contains(objects, "found")
    assert !Enumerable.Contains(objects, new object())

    strings := new List<string>()
    strings.Add("found")
    assert Enumerable.Contains(strings, "found")
}

test "a source class with a public parameterless constructor satisfies an external new constraint" {
    created := Activator.CreateInstance<PublicDefaultConstructorSource>()
    assert created != null
    assert created.Value == 19
    assert Activator.CreateInstance<int>() == 0
}

test "a different generic arity does not hide an inherited generic source method" {
    context := new SetOverloadDerived()
    assert context.ReadPeople() == 31
    assert context.Set(7) == 7
}

// ─── 2. INFERRED TYPE ARGUMENT, PARAMS TAIL ───────────────────────────────────────────────────────

test "an inferred static generic method packs its params tail" {
    a := ImmutableArray.Create(1, 2, 3, 4, 5)
    assert a.Length == 5
    assert a[4] == 5
    assert ImmutableArray.Create("only").Length == 1
}

// ─── 3. WRITTEN TYPE ARGUMENTS, INLINE LAMBDA ─────────────────────────────────────────────────────

test "written type arguments close a delegate parameter for an inline lambda" {
    services := new ServiceCollection()
    services.AddSingleton<Svc>(sp => new Svc { N: 7 })
    provider := services.BuildServiceProvider()
    assert provider.GetRequiredService<Svc>().N == 7
}

test "written type arguments close an extension's delegate parameter for an inline lambda" {
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    viaExtension := values.Select<int, int>((x, i) => x + i).ToList()
    assert viaExtension[1] == 3
    viaExtensionOne := values.Select<int, string>(x => x.ToString() + "!").ToList()
    assert viaExtensionOne[1] == "2!"
}

test "written type arguments close a static generic method's delegate parameter for an inline lambda" {
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    mapped := Enumerable.Select<int, string>(values, x => x.ToString() + "!").ToList()
    assert mapped[1] == "2!"
}

// ─── 4. INHERITED GENERIC METHOD ON THIS ──────────────────────────────────────────────────────────

// Random is an unsealed BCL class with generic instance methods (`Shuffle<T>(T[])`,
// `GetItems<T>(T[], int)`), the smallest external base that has one.
class Dice: Random {
    func ShuffledLength(items: int[]): int {
        this.Shuffle<int>(items)
        return items.Length
    }

    func ShuffledBare(items: int[]): int {
        Shuffle<int>(items)
        return items.Length
    }

    func ShuffledInferred(items: int[]): int {
        Shuffle(items)
        return items.Length
    }

    func PickedThis(items: int[]): int {
        return this.GetItems<int>(items, 4).Length
    }

    func PickedBare(items: int[]): int {
        return GetItems<int>(items, 5).Length
    }
}

class Pool {
    func Take<T>(item: T): T {
        return item
    }
}

class DerivedPool: Pool {
    func ViaThis(): int {
        return this.Take<int>(4)
    }

    func ViaBare(): int {
        return Take<int>(5)
    }
}

func Three(): int[] {
    return [1, 2, 3]
}

test "an inherited external generic method resolves on this" {
    dice := new Dice()
    assert dice.ShuffledLength(Three()) == 3
    assert dice.PickedThis(Three()) == 4
}

test "an inherited external generic method resolves on the implicit receiver" {
    dice := new Dice()
    assert dice.ShuffledBare(Three()) == 3
    assert dice.PickedBare(Three()) == 5
    assert dice.ShuffledInferred(Three()) == 3
}

test "an inherited source generic method resolves on this and on the implicit receiver" {
    pool := new DerivedPool()
    assert pool.ViaThis() == 4
    assert pool.ViaBare() == 5
}

// A GENERIC external base: the substituted base is `List<string>`, and `ConvertAll<TOutput>` is
// closed over the written argument.
class Names: List<string> {
    func Lengths(): int {
        measure: Converter<string, int> = s => s.Length
        converted := ConvertAll<int>(measure)
        return converted.Count
    }

    func LengthsViaThis(): int {
        measure: Converter<string, int> = s => s.Length
        return this.ConvertAll<int>(measure).Count
    }
}

test "an inherited generic method resolves on a generic external base" {
    names := new Names()
    names.Add("a")
    names.Add("bb")
    assert names.Lengths() == 2
    assert names.LengthsViaThis() == 2
}

test "a discard lambda binds the delegate of its arity" {
    values := new List<int>()
    values.Add(4)
    values.Add(5)
    ones := values.Select<int, int>(_ => 1).ToList()
    assert ones[0] + ones[1] == 2
}

// ─── BETTER FUNCTION MEMBER: THE GENERIC CANDIDATE WINS ON A BETTER CONVERSION ────────────────────
//
// `Task.WhenAll(first, second)` over two `Task<int>` has a non-generic `WhenAll(params Task[])` and a
// generic `WhenAll<TResult>(params Task<TResult>[])`. The generic one converts each argument by
// identity and the other by a reference conversion, so it is the better member and the call is a
// `Task<int[]>` — reading `.Result` as an `int[]` is what compiles only if it was chosen.

test "WhenAll over typed tasks takes the generic overload and yields the values" {
    first := Task.FromResult(1)
    second := Task.FromResult(2)
    all := Task.WhenAll(first, second)
    values := all.Result
    assert values.Length == 2
    assert values[0] + values[1] == 3
}

test "WhenAll over a prebuilt array of typed tasks takes the generic overload" {
    tasks: Task<int>[] = [Task.FromResult(4), Task.FromResult(5)]
    values := Task.WhenAll(tasks).Result
    assert values[1] == 5
}

test "WhenAny over typed tasks yields the completed typed task" {
    only := Task.FromResult(7)
    winner := Task.WhenAny(only, only).Result
    assert winner.Result == 7
}

test "Array.Sort and Array.IndexOf over a typed array keep their results" {
    values: int[] = [3, 1, 2]
    Array.Sort(values)
    assert values[0] == 1
    assert values[2] == 3
    assert Array.IndexOf(values, 3) == 2
}

test "a generic params factory with no packed argument and a written type argument" {
    assert ImmutableArray.Create<int>().Length == 0
}
