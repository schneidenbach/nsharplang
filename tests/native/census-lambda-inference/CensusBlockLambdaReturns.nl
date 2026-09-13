namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq


// A BLOCK-BODIED LAMBDA'S RETURN TYPE, WHERE THE POSITION IT IS WRITTEN AT IS STILL OPEN.
//
// `names.Select(name => { line0 := …; return new Range(line0, line0 + 1) }).ToList()` reported TWO
// diagnostics about a program with nothing wrong with it:
//
//   NL202  Function 'this function' should return TResult but returns Range
//   NL202  Function 'MakeRanges' should return List<Range> but returns List<TResult>
//
// The lambda was handed `Func<string, TResult>` — with `TResult` being exactly what the lambda was
// being asked to decide — and a BLOCK body's return type was the signature's whatever the block did.
// So the block's `return` statements were CHECKED against an unbound type parameter, and the lambda
// contributed nothing to the inference that would have bound it.
//
// The rule is C# §12.6.3.13's: a position that is not decided offers no target, and the lambda's
// inferred return type is the best common type of its `return` expressions. It closes `TResult` and
// the enclosing call's result type follows.
class Span2 {
    Start: int
    End: int

    constructor(start: int, end: int) {
        Start = start
        End = end
    }
}

class Marker: Span2 {
    Label: string

    constructor(start: int, label: string): base(start, start + 1) {
        Label = label
    }
}

// THE CENSUS SITE, in the shape the language server writes it.
func SpansOf(names: List<string>): List<Span2> {
    return names.Select(name => {
        line0 := name.Length
        return new Span2(line0, line0 + 1)
    }).ToList()
}

// A BLOCK WITH BRANCHES: every `return` the block itself executes takes part, wherever it is written.
func ScoresOf(names: List<string>): List<int> {
    return names.Select(name => {
        if name.Length > 3 {
            return 1
        }

        return 0
    }).ToList()
}

func FirstLongIndexIn(rows: List<List<string>>): List<int> {
    return rows.Select(row => {
        for index := 0; index < row.Count; index++ {
            if row[index].Length > 3 {
                return index
            }
        }

        return -1
    }).ToList()
}

// A `null` ARM CONSTRAINS NOTHING and takes the type the other arms agree on.
func UpperOrNull(names: List<string>): List<string> {
    return names.Select(name => {
        if name.Length == 0 {
            return null
        }

        return name.ToUpperInvariant()
    }).ToList()
}

// TWO ARMS THAT ARE NOT THE SAME TYPE JOIN AT WHAT THEY SHARE — here a base class the analyzer's own
// match-expression join already knows how to find.
func SpansOrMarkers(names: List<string>): List<int> {
    spans := names.Select(name => {
        if name.Length > 3 {
            return new Marker(name.Length, name)
        }

        return new Span2(0, 1)
    }).ToList()
    return spans.Select(span => span.Start).ToList()
}

// A NESTED LAMBDA OWNS ITS OWN RETURNS. The inner block returns a `string` and the outer one returns
// an `int`; the outer lambda's type is decided by the outer returns alone.
func NestedInnerLengths(names: List<string>): List<int> {
    return names.Select(name => {
        inner: Func<string, string> = value => {
            return value + "!"
        }
        if inner(name).Length > 0 {
            return name.Length + 1
        }

        return 0
    }).ToList()
}

// THE BLOCK SHAPE AT A `bool` POSITION, where the target's return type was never open — the same
// program before and after, kept so the unchanged half is pinned too.
func LongNames(names: List<string>): List<string> {
    return names.Where(name => {
        return name.Length > 3
    }).ToList()
}

// THE SAME QUESTION FOR A GENERIC THIS COMPILATION DECLARES ITSELF, whose open return position is a
// SOURCE type parameter rather than a reflected one.
func MapAll<T, R>(items: List<T>, selector: Func<T, R>): List<R> {
    result := new List<R>()
    for item in items {
        result.Add(selector(item))
    }

    return result
}

func MappedSpans(names: List<string>): List<Span2> {
    return MapAll(names, name => {
        line0 := name.Length
        return new Span2(line0, line0 + 1)
    })
}

func MappedLengths(names: List<string>): List<int> {
    return MapAll(names, name => {
        return name.Length
    })
}

func SampleNames(): List<string> {
    names := new List<string>()
    names.Add("alpha")
    names.Add("be")
    return names
}
