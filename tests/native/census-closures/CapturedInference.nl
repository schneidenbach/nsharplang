namespace NSharpLang.CensusClosures.Tests

import System.Collections.Generic
import System.Linq

// WHAT A LAMBDA BODY CAN SEE WHEN ITS OWN TYPE IS STILL BEING INFERRED.
//
// A generic call whose output type parameter is bound by the lambda's RETURN — `ConvertAll<TOutput>`,
// `Select<TSource, TResult>` — has to type the body BEFORE it can select the method. That typing runs
// in the enclosing frame, and a lambda body sees the enclosing frame: its parameters, its locals and
// the instance alike. Before this it saw only the instance, so a lambda reading a captured parameter
// or local left the output type parameter unbound and the whole call declined at
// `emit.call.instance-member` after the analyzer had accepted the same program.
func BumpAll(xs: List<int>, bump: int): List<int> {
    return xs.ConvertAll(x => x + bump)
}

func BumpAllFromLocal(xs: List<int>): List<int> {
    bump := 3
    return xs.ConvertAll(x => x + bump)
}

// The output type is whatever the body answers, and the body's answer may come from the capture.
func LabelAll(xs: List<int>, prefix: string): List<string> {
    return xs.ConvertAll(x => prefix + x.ToString())
}

// THE CENSUS PROBE: a lambda inside a lambda, each one an argument at a position whose output type
// is still inferring.
func CountGreater(xs: List<int>, ys: List<int>): List<int> {
    return xs.Select(x => ys.Where(y => y > x).Count()).ToList()
}

// A BLOCK body at the same position, reading a capture from inside its `return`.
func ScaleAll(xs: List<int>, factor: int): List<int> {
    return xs.ConvertAll(x => {
        return x * factor + 1
    })
}

class Totals {
    Factor: int

    constructor(factor: int) {
        Factor = factor
    }

    // The instance and a parameter at once, at an inferring position.
    func Weighted(xs: List<int>, bonus: int): List<int> {
        return xs.ConvertAll(x => x * Factor + bonus)
    }
}
