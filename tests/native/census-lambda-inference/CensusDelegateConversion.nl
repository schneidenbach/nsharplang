namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic


// A LAMBDA CONVERTS TO ANY DELEGATE TYPE, AND SO DOES A METHOD GROUP.
//
// The census found `cancelHandler: ConsoleCancelEventHandler = (ignored, eventArgs) => { ... }`
// reported NL202 "typed as ConsoleCancelEventHandler, but the value is FunctionTypeInfo": the
// conversion was written for `Func` and `Action` by NAME, with one hand-placed bridge for
// `ThreadStart`, so every other delegate — the event-handler family, `Predicate<T>`,
// `Comparison<T>`, `Converter<T, R>` — was refused.
//
// A delegate carries its signature on its `Invoke`, and reading it from there is the whole rule.
// Everything below EXECUTES: the delegates are invoked, the sorts and searches really run, and the
// CLR type of what was built is asserted, because a conversion that produced the wrong delegate
// type would still satisfy a check that only looked at the source text.
//
// `RuntimeTypeOf` and `Words` are declared once for this namespace, in `CensusLambdaInference.nl`: a
// free-function name has one declaration per namespace (NL306), and this file reaches both with no
// import.
func DescendingComparison(): Comparison<int> {
    ordering: Comparison<int> = (left, right) => right - left
    return ordering
}

func LongerThanTwo(): Predicate<string> {
    predicate: Predicate<string> = value => value.Length > 2
    return predicate
}

func TextOfInt(): Converter<int, string> {
    converter: Converter<int, string> = value => value.ToString()
    return converter
}

func CancelHandler(): ConsoleCancelEventHandler {
    cancelHandler: ConsoleCancelEventHandler = (ignored, eventArgs) => {
        eventArgs.Cancel = true
    }

    return cancelHandler
}

// A METHOD GROUP into the same delegate types, through the same rule.
func IsShort(value: string): bool {
    return value.Length <= 2
}

func Descending(left: int, right: int): int {
    return right - left
}

func ShortPredicate(): Predicate<string> {
    predicate: Predicate<string> = IsShort
    return predicate
}

func DescendingGroup(): Comparison<int> {
    ordering: Comparison<int> = Descending
    return ordering
}

// A DELEGATE-TYPED PARAMETER of a function this project declares takes a lambda at its call site,
// exactly as a framework method's does.
func CountMatching(values: List<string>, predicate: Predicate<string>): int {
    matched := 0
    for value in values {
        if predicate(value) {
            matched = matched + 1
        }
    }

    return matched
}

func SortedDescending(values: int[]): int[] {
    Array.Sort(values, (left, right) => right - left)
    return values
}

func SortedThrough(values: int[], ordering: Comparison<int>): int[] {
    Array.Sort(values, ordering)
    return values
}
