namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// `System.ValueTuple`N` IS THE TUPLE TYPE `(T1, ..., TN)`, AND THE ANALYZER HAS ONE SPELLING FOR IT.
//
// C# has no second type here: the tuple syntax is a SPELLING of `System.ValueTuple`N`, and the element
// names are an annotation the declaring POSITION carries in `TupleElementNamesAttribute` rather than
// anything the CLR type knows. So a `Dictionary<string, (Item: string, Ranges: List<int>)>` read back
// out of metadata, a `ValueTuple<string, List<int>>` written by hand, and a `(string, List<int>)`
// written in source are the SAME type, assignable in every direction and carrying the same members.
//
// Before this owner existed the analyzer had two representations -- a `GenericTypeInfo` named
// "ValueTuple" for the reflected or hand-written spelling and a `TupleTypeInfo` for the written one --
// and every consumer had to know both. It did not: `g: ValueTuple<string, List<int>> = (x, l)` reported
// NL202 "expected `ValueTuple<string, List<int>>` but got `(string, List<int>)`", the same assignment
// the other way round reported the mirror image, and `group.Ranges` on a value taken out of a
// dictionary declared with a named tuple value reported NL303 because a `GenericTypeInfo` has no
// elements to name.
//
// ONE CLR SHAPE, ONE TypeInfo: THE NORMALISATION HAPPENS AT THE CONVERSION BOUNDARY. This is the rule
// `AnalyzerReflectionTypeConversion` already applies to `Nullable<T>` -- lift at the boundary rather
// than special-case identity, assignability, display, member resolution and overload scoring one at a
// time -- and it is applied here for the same reason. A constructed `ValueTuple`N` becomes a
// `TupleTypeInfo` whose elements are UNNAMED; a position that declares names re-attaches them through
// `AnalyzerTupleElementNames`, whose walk already handles both shapes.
//
// THE REST NESTING IS FLATTENED HERE TOO. `ValueTuple`8`'s eighth argument is a REST tuple, so a
// 10-element tuple is `ValueTuple<T1..T7, ValueTuple<T8, T9, T10>>` in metadata and ten flat elements
// in source. Flattening at the boundary is what lets `AnalyzerTupleElementNames.RewriteUnderlyingArguments`
// spend the attribute's extra nameless slots in the same order the emitter writes them.
//
// ARITY ONE IS LEFT ALONE. `(T)` is not tuple syntax in C# or in N# -- it is a parenthesised type -- so
// `ValueTuple<T>` keeps the constructed-generic shape it has always had, along with its `Item1`. A
// `ValueTuple`8` whose eighth argument is not itself a tuple is not a tuple either, and keeps its shape
// for the same reason: the CLR lets that type be constructed, and C# refuses to read it as a tuple.
class ValueTupleTypeFacts {

    // The lowest arity the tuple syntax can spell.
    static MinimumTupleArity: int => 2

    // The argument position `ValueTuple`8` reserves for the rest tuple.
    static RestArgumentIndex: int => 7

    // True when `definition` is the open `System.ValueTuple`N`. The question is asked of the generic
    // DEFINITION's CLR full name -- metadata, not the written name -- so a user type called
    // `ValueTuple` is never mistaken for one.
    static func IsValueTupleDefinition(definition: TypeInfo?): bool {
        if definition == null {
            return false
        }

        reflection := definition as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        fullName := reflection.Type.FullName
        if fullName == null {
            return false
        }

        return fullName.StartsWith("System.ValueTuple`", StringComparison.Ordinal)
    }

    // The canonical `TupleTypeInfo` for a constructed `ValueTuple`N`, or false when the constructed
    // type is not one of the shapes the tuple syntax spells. `normalized` is only written when the
    // answer is true.
    static func TryNormalizeConstructed(definition: TypeInfo?, arguments: List<TypeInfo>, out normalized: TypeInfo): bool {
        normalized = BuiltInTypes.Unknown
        if !IsValueTupleDefinition(definition) || arguments.Count < MinimumTupleArity {
            return false
        }

        flattened := new List<TypeInfo>()
        if !TryFlatten(arguments, flattened) {
            return false
        }

        elements := new List<TupleTypeElementInfo>()
        for flattenedItem in flattened {
            elements.Add(new TupleTypeElementInfo(null, flattenedItem))
        }

        tuple: TypeInfo = new TupleTypeInfo(elements)
        normalized = tuple
        return true
    }

    // The flat element list of one `ValueTuple`N` argument list. Seven or fewer arguments ARE the
    // elements; an eighth argument must be a tuple, whose own elements continue the list.
    static func TryFlatten(arguments: List<TypeInfo>, flattened: List<TypeInfo>): bool {
        if arguments.Count <= RestArgumentIndex {
            index := 0
            while index < arguments.Count {
                flattened.Add(arguments[index])
                index = index + 1
            }

            return true
        }

        if arguments.Count != RestArgumentIndex + 1 {
            return false
        }

        index := 0
        while index < RestArgumentIndex {
            flattened.Add(arguments[index])
            index = index + 1
        }

        rest := arguments[RestArgumentIndex] as TupleTypeInfo
        if rest == null {
            return false
        }

        for element2 in rest.Elements {
            flattened.Add(element2.Type)
        }

        return true
    }
}
