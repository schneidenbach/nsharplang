namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq


// THE SHAPES THE 2026-09-12 CONVERTER CENSUS FOUND, AS RUNNING CODE.
//
// Two faults, both about method type inference. `values.Count(predicate)` reported NL203 "I can't
// figure out the type of lambda parameter" because `List<T>.Count` is an `int` PROPERTY and a
// property that cannot be called was allowed to hide `Enumerable.Count<TSource>` (14 sites);
// `names.ToDictionary(keySelector, elementSelector)` typed as `Dictionary<string, string>` because
// the second lambda was handed the first lambda's result, so returning it where an interface was
// declared reported NL202 (18 sites).
//
// Everything here EXECUTES. The assertions are runtime values and CLR metadata, not shapes: a
// signature that inferred wrongly would still compile in a world where only the declared type was
// checked, and the runtime type of what comes back is what proves it did not.

// The runtime type of a value read through an INTERFACE. N#'s member surface does not offer the
// inherited `object` members on an interface-typed receiver, so the value crosses as `object` and
// answers there — which is the point of the assertion anyway: the declared type is the interface
// and the runtime type is whatever the call actually produced.
func RuntimeTypeOf(value: object): Type {
    return value.GetType()
}

func Words(): List<string> {
    values := new List<string>()
    values.Add("alpha")
    values.Add("be")
    values.Add("gamma")
    return values
}

func Lengths(): List<int> {
    values := new List<int>()
    values.Add(3)
    values.Add(1)
    values.Add(2)
    return values
}

// A USER-DECLARED generic function taking a delegate: the same inference the framework's own
// extensions get, with nothing in the compiler that knows this function's name.
func Apply<T, R>(items: List<T>, projection: Func<T, R>): List<R> {
    mapped := new List<R>()
    for item in items {
        mapped.Add(projection(item))
    }

    return mapped
}

func IsLong(value: string): bool {
    return value.Length > 3
}

func LengthOf(value: string): int {
    return value.Length
}

// The widening cases: an extension call's result is an expression of its DECLARED return type, and
// assignability to the declared target is the ordinary relation — nothing about an extension result
// is special.
func AsReadOnlyDictionary(values: List<string>): IReadOnlyDictionary<string, int> {
    return values.ToDictionary(word => word, word => word.Length)
}

func AsSequence(values: List<string>): IEnumerable<string> {
    return values.ToList()
}

func AsReadOnlyList(values: List<string>): IReadOnlyList<string> {
    return values.ToList()
}

func ArrayAsSequence(values: List<string>): IEnumerable<string> {
    return values.ToArray()
}

func CountSequence(values: IEnumerable<string>): int {
    return values.Count()
}

func WidenedThroughArgument(values: List<string>): int {
    return CountSequence(values.ToList())
}

func WidenedThroughLocal(values: List<string>): int {
    sequence: IEnumerable<string> = values.ToList()
    return CountSequence(sequence)
}
