namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// NAMED TUPLE ELEMENT NAMES, FLATTENED THE WAY `TupleElementNamesAttribute` SPELLS THEM.
//
// A named tuple has no CLR identity of its own: `(int Min, int Max)` IS `System.ValueTuple<int, int>`,
// and the element names live in a `System.Runtime.CompilerServices.TupleElementNamesAttribute(string[])`
// attached to the POSITION that mentions the tuple -- a return parameter, a parameter, a field, a
// property. Every .NET language that wants a C# consumer to see its element names writes the same
// attribute, and the ORDER of that string array is a contract, not a convention.
//
// THE ORDER IS A PRE-ORDER WALK OF THE WRITTEN TYPE, NAMES FIRST AT EACH TUPLE. Reading the type as a
// tree, every tuple node contributes its element names -- ALL of them, in element order, with a null
// for an element the source left unnamed -- and then the walk descends into that tuple's element
// types, into a generic type's arguments, into an array's element type. That is why
// `(int A, (int B, int C) D)` is `["A", "D", "B", "C"]` and not `["A", "B", "C", "D"]`: the outer
// tuple's own names are complete before the nested tuple is reached. `List<(int Min, int Max)>` is
// `["Min", "Max"]` -- the `List` node names nothing and the walk continues into its argument -- and
// `((int, int) X, int Y)` is `["X", "Y", null, null]`, because an unnamed NESTED tuple still occupies
// two slots. These rows are pinned in the tests against the C# compiler's own output.
//
// TUPLES LONGER THAN SEVEN ELEMENTS NEST, AND THE NESTING IS VISIBLE IN THE ARRAY. `ValueTuple` tops
// out at seven fields plus a `TRest`, so an 8-element tuple is `ValueTuple<T1..T7, ValueTuple<T8>>`.
// The written tuple contributes all eight names, and then the walk reaches the REST tuple -- itself a
// tuple, with no names of its own -- which contributes one null. An 8-element tuple therefore carries
// NINE strings, and a 10-element one carries thirteen. `AppendUnderlyingArguments` is that rule.
//
// AN ANONYMOUS UNION IS NOT DESCENDED INTO. A union arm is not a type argument of the emitted type,
// so a tuple mentioned inside one occupies no slot in the flattened array; descending would describe
// positions the CLR signature does not have. A type whose only tuples are inside a union therefore
// carries no attribute at all.
//
// THE INPUT IS A LABELLED CANONICAL. `ColumnarTypeCanonicalizer` and the parser kernels both produce
// the STRUCTURAL canonical of a type -- `(int,int)`, with element names discarded -- because names are
// metadata rather than identity. The labelled canonical is the same spelling with each named element
// written `name:Type`, which is exactly what the source wrote minus whitespace, and it is the only
// form that still carries the nested and generic-argument names this walk needs.
class ColumnarTupleElementNames {

    // The slot of an element the source left unnamed. A tuple element name is never empty, so the
    // sentinel cannot collide with a real one; the blob writer turns it back into the metadata null
    // that C# emits.
    static Unnamed: string => ""

    // The flattened names for one written type, or null when nothing in it is named. Null is the
    // "emit no attribute" answer -- exactly what C# does for `(int, int)` and for `int`.
    static func Flatten(labeledCanonical: string): string[]? {
        if labeledCanonical == null || labeledCanonical.Length == 0 {
            return null
        }

        collected := new List<string>()
        Append(labeledCanonical, collected)

        index := 0
        while index < collected.Count {
            if collected[index].Length > 0 {
                return collected.ToArray()
            }

            index = index + 1
        }

        return null
    }

    // True when the flattened array has at least one real name -- the same question `Flatten` answers
    // with null, asked of an already-flattened array.
    static func HasAnyName(names: string[]?): bool {
        if names == null {
            return false
        }

        index := 0
        while index < names.Length {
            if names[index].Length > 0 {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The blob for `[TupleElementNames(new string[] { ... })]`: the prologue, one SZARRAY fixed
    // argument, no named arguments. An unnamed slot is the metadata NULL string, which is what a C#
    // consumer reads back as a `null` transform name.
    static func Blob(names: string[]): byte[] {
        values := new string?[](names.Length)
        index := 0
        while index < names.Length {
            if names[index].Length > 0 {
                values[index] = names[index]
            } else {
                values[index] = null
            }

            index = index + 1
        }

        return ColumnarAttributeBlobs.StringArray(values)
    }

    // The TOP-LEVEL element names of each named-tuple parameter, keyed by parameter name -- what a
    // body needs to rewrite `x.P` into `x.Item1`. A parameter whose type is not a named tuple has no
    // entry, and a signature with no named tuple parameter at all answers null.
    static func ParameterNameMap(parameterNames: string[], parameterTupleElementNames: string[][]?): Dictionary<string, string[]>? {
        if parameterTupleElementNames == null {
            return null
        }

        map: Dictionary<string, string[]>? = null
        index := 0
        while index < parameterNames.Length && index < parameterTupleElementNames.Length {
            elementNames := parameterTupleElementNames[index]
            if elementNames != null {
                if map == null {
                    map = new Dictionary<string, string[]>(StringComparer.Ordinal)
                }

                map[parameterNames[index]] = elementNames
            }

            index = index + 1
        }

        return map
    }

    // The TOP-LEVEL element names of one labelled canonical, or null when it is not a named tuple at
    // its outermost level. This is what a body needs to rewrite `pair.P` into `pair.Item1`, derived
    // from the labelled spelling rather than carried as a separate parser column.
    static func TopLevelNames(labeledCanonical: string?): string[]? {
        if labeledCanonical == null {
            return null
        }

        text := Unwrap(labeledCanonical)
        if text.Length < 2 || text[0] != '(' || text[text.Length - 1] != ')' {
            return null
        }

        elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
        names := new string[](elements.Count)
        named := false
        index := 0
        while index < elements.Count {
            element := elements[index]
            colon := element.IndexOf(':')
            if colon > 0 && ColumnarTypeCanonicalizer.IsBareIdentifier(element.Substring(0, colon)) {
                names[index] = element.Substring(0, colon)
                named = true
            } else {
                names[index] = ""
            }

            index = index + 1
        }

        if !named {
            return null
        }

        return names
    }

    // `ParameterNameMap`, keyed off the labelled canonicals instead of a parser-side name column --
    // the shape a constructor's parameters arrive in.
    static func ParameterNameMapFromLabeled(parameterNames: string[], labeledCanonicals: string[]?): Dictionary<string, string[]>? {
        if labeledCanonicals == null {
            return null
        }

        map: Dictionary<string, string[]>? = null
        index := 0
        while index < parameterNames.Length && index < labeledCanonicals.Length {
            elementNames := TopLevelNames(labeledCanonicals[index])
            if elementNames != null {
                if map == null {
                    map = new Dictionary<string, string[]>(StringComparer.Ordinal)
                }

                map[parameterNames[index]] = elementNames
            }

            index = index + 1
        }

        return map
    }

    static func Append(labeledCanonical: string, collected: List<string>) {
        text := Unwrap(labeledCanonical)
        if text.Length == 0 || HasTopLevelUnionBar(text) {
            return
        }

        if text[0] == '(' && text[text.Length - 1] == ')' {
            AppendTuple(text, collected)
            return
        }

        open := TopLevelGenericArgumentStart(text)
        if open < 0 || text[text.Length - 1] != '>' {
            return
        }

        arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(open + 1, text.Length - open - 2))
        argumentIndex := 0
        while argumentIndex < arguments.Count {
            Append(arguments[argumentIndex], collected)
            argumentIndex = argumentIndex + 1
        }
    }

    // A tuple node: its own element names first, then the arguments of the `ValueTuple` that carries
    // them.
    static func AppendTuple(text: string, collected: List<string>) {
        elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
        names := new List<string>()
        types := new List<string>()
        index := 0
        while index < elements.Count {
            element := elements[index]
            colon := element.IndexOf(':')
            if colon > 0 && ColumnarTypeCanonicalizer.IsBareIdentifier(element.Substring(0, colon)) {
                names.Add(element.Substring(0, colon))
                types.Add(element.Substring(colon + 1))
            } else {
                names.Add("")
                types.Add(element)
            }

            index = index + 1
        }

        nameIndex := 0
        while nameIndex < names.Count {
            collected.Add(names[nameIndex])
            nameIndex = nameIndex + 1
        }

        AppendUnderlyingArguments(types, 0, collected)
    }

    // The type arguments of the `ValueTuple` that represents elements `start` and after. Seven or
    // fewer elements are the arguments themselves; more than seven means the eighth argument is a
    // REST tuple, which contributes one unnamed slot per element it carries before the walk continues
    // inside it.
    static func AppendUnderlyingArguments(types: List<string>, start: int, collected: List<string>) {
        remaining := types.Count - start
        if remaining <= 7 {
            index := start
            while index < types.Count {
                Append(types[index], collected)
                index = index + 1
            }

            return
        }

        index := start
        while index < start + 7 {
            Append(types[index], collected)
            index = index + 1
        }

        restStart := start + 7
        restIndex := restStart
        while restIndex < types.Count {
            collected.Add("")
            restIndex = restIndex + 1
        }

        AppendUnderlyingArguments(types, restStart, collected)
    }

    // `&T` (by-ref), `T[]` and `T?` are all transparent to the walk: the CLR signature still mentions
    // the same tuple, so the attribute describes the tuple inside them.
    static func Unwrap(text: string): string {
        current := text
        changed := true
        while changed {
            changed = false
            if current.Length > 1 && current[0] == '&' {
                current = current.Substring(1)
                changed = true
            }

            if current.Length > 2 && current[current.Length - 2] == '[' && current[current.Length - 1] == ']' {
                current = current.Substring(0, current.Length - 2)
                changed = true
            }

            if current.Length > 1 && current[current.Length - 1] == '?' {
                current = current.Substring(0, current.Length - 1)
                changed = true
            }
        }

        return current
    }

    static func HasTopLevelUnionBar(text: string): bool {
        depth := 0
        index := 0
        while index < text.Length {
            c := text[index]
            if c == '(' || c == '<' || c == '[' {
                depth = depth + 1
            } else if c == ')' || c == '>' || c == ']' {
                depth = depth - 1
            } else if c == '|' && depth == 0 {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The index of the `<` that opens a generic head's argument list, or -1 when the text is not a
    // constructed generic spelling.
    static func TopLevelGenericArgumentStart(text: string): int {
        index := 0
        while index < text.Length {
            if text[index] == '<' {
                return index
            }

            if text[index] == '(' || text[index] == ')' || text[index] == '[' || text[index] == ']' {
                return -1
            }

            index = index + 1
        }

        return -1
    }
}
