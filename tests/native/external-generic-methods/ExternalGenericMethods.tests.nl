namespace NSharpLang.ExternalGenericMethods

import System
import System.Collections
import System.Collections.Generic
import System.Linq
import System.Text.Json
import System.Threading
import System.Threading.Tasks

// GENERIC METHODS DECLARED BY A REFERENCED ASSEMBLY, CALLED THE TWO WAYS C# ALLOWS THEM.
//
// A generic method's type arguments are either WRITTEN at the call site or INFERRED from the
// arguments, and until this project existed only the second half worked for a declaration that came
// from referenced metadata: `Task.FromResult(value)` bound, `Task.FromResult<int>(1)` did not.
// Every row here is a REAL BCL call whose result is executed, not a metadata assertion about one.
//
// WHAT THE ROWS ARE FOR. The instance/static split is the dispatch (`callvirt` on a reference
// receiver, `call` with an address on a value one); the explicit/inferred split is where the type
// arguments come from; the lambda rows prove an argument is bound against the SUBSTITUTED parameter
// type, which is the only way a lambda can know its own parameter's type; the `out` row proves a
// by-ref parameter closes over the written argument and writes through it; and the constructed-owner
// rows prove the member is chosen on the CLOSED type rather than on its open definition.
class Plain {
    Name: string = "plain"
}

func AgesJson(): string {
    return "{\"Ada\":36,\"Grace\":45}"
}

func Numbers(): List<int> {
    values := new List<int>()
    values.Add(3)
    values.Add(1)
    values.Add(2)
    return values
}

// ─── EXTERNAL STATIC GENERIC METHODS, TYPE ARGUMENTS WRITTEN ──────────────────────────────────────

test "a written type argument closes an external static generic method and it runs" {
    empty := Enumerable.Empty<int>()
    count := 0
    for value in empty {
        count = count + value
    }

    assert count == 0
    assert Array.Empty<string>().Length == 0
}

test "the closed method's RESULT is the constructed type the written arguments name" {
    completed := Task.FromResult<int>(7)
    boxed: object = completed

    assert completed.Result == 7
    assert boxed.GetType().GetGenericTypeDefinition().FullName == "System.Threading.Tasks.Task`1"
    assert boxed.GetType().GetGenericArguments()[0].FullName == "System.Int32"
}

test "the same method INFERS the same instantiation when the list is omitted" {
    source := 7
    inferred := Task.FromResult(source)
    written := Task.FromResult<int>(source)
    inferredBoxed: object = inferred
    writtenBoxed: object = written

    assert inferred.Result == written.Result
    assert inferredBoxed.GetType().FullName == writtenBoxed.GetType().FullName
}

test "a written type argument names a SOURCE type the same compilation is emitting" {
    made := Activator.CreateInstance<Plain>()

    assert made != null
    assert made.Name == "plain"
}

// A trailing optional parameter with a null metadata default is filled, so the site need not write
// `options` to reach `Deserialize<TValue>(string, JsonSerializerOptions?)`.
test "a written type argument reaches a method whose trailing optional is filled from its default" {
    ages := JsonSerializer.Deserialize<Dictionary<string, int>>(AgesJson())

    assert ages != null
    assert ages.Count == 2
    assert ages["Ada"] == 36
    assert ages["Grace"] == 45
}

test "the round trip through the written-argument serializer returns the same text" {
    ages := JsonSerializer.Deserialize<Dictionary<string, int>>(AgesJson())
    written := JsonSerializer.Serialize<Dictionary<string, int>>(ages)
    again := JsonSerializer.Deserialize<Dictionary<string, int>>(written)

    assert written == AgesJson()
    assert again != null
    assert again["Ada"] == ages["Ada"]
    assert again["Grace"] == ages["Grace"]
}

// ─── BY-REF ARGUMENTS ─────────────────────────────────────────────────────────────────────────────

test "a written type argument closes a BY-REF parameter and the call writes through it" {
    slot := "before"
    previous := Interlocked.Exchange<string>(ref slot, "after")

    assert previous == "before"
    assert slot == "after"
}

test "the same by-ref method infers the same instantiation" {
    slot := "before"
    previous := Interlocked.Exchange(ref slot, "after")

    assert previous == "before"
    assert slot == "after"
}

// ─── EXTERNAL INSTANCE GENERIC METHODS ────────────────────────────────────────────────────────────

test "a written type argument closes an external INSTANCE generic method, and its lambda argument is bound against the substituted parameter" {
    values := Numbers()
    texts := values.ConvertAll<string>(value => value.ToString())

    assert texts.Count == 3
    assert texts[0] == "3"
    assert texts[1] == "1"
    assert texts[2] == "2"
}

// NOT YET: `values.ConvertAll(value => value.ToString())`. Inference from a LAMBDA's own result is
// C#'s second inference phase — the argument has no type until the parameter it is bound to supplies
// one, so there is nothing for the first phase to unify. Every inferred row in this file infers from
// an argument that carries a type; a written type-argument list is how a lambda-only position says
// what it means.

// ─── STATIC MEMBERS ON A CONSTRUCTED GENERIC OWNER ────────────────────────────────────────────────

// `Comparer<T>.Create` is NOT itself generic: the type argument belongs to the OWNER, so the member
// has to be chosen on the closed `Comparer<int>` for `Comparison<int>` to be the parameter a lambda
// can take its shape from.
test "a static member on a constructed external generic owner runs, with a lambda argument" {
    descending := Comparer<int>.Create((left, right) => right - left)
    values := Numbers()
    values.Sort(descending)

    assert values[0] == 3
    assert values[1] == 2
    assert values[2] == 1
    assert descending.Compare(1, 2) > 0
}

test "the same owner's Default answers the ordinary ascending order" {
    values := Numbers()
    values.Sort(Comparer<int>.Default)

    assert values[0] == 1
    assert values[2] == 3
}

// ─── EXTENSION-SHAPED GENERIC STATICS ─────────────────────────────────────────────────────────────

test "a written type argument reaches a generic extension written in static form" {
    boxed := new ArrayList()
    boxed.Add("one")
    boxed.Add("two")

    texts := Enumerable.Cast<string>(boxed)
    joined := ""
    for text in texts {
        joined = joined + text + ";"
    }

    assert joined == "one;two;"
}

// ─── THE EMITTED METADATA ─────────────────────────────────────────────────────────────────────────

// Every row above executes, so the IL is already proven to run. This one says what the emitted
// method REFERENCES: a written type argument produces a call to the CLOSED method, so the value the
// call site holds has the instantiation's own type and not the definition's open one.
test "the instance call's RESULT is the constructed type the written argument names" {
    values := Numbers()
    texts := values.ConvertAll<string>(value => value.ToString())
    boxed: object = texts

    assert boxed.GetType().GetGenericTypeDefinition().FullName == "System.Collections.Generic.List`1"
    assert boxed.GetType().GetGenericArguments()[0].FullName == "System.String"
}
