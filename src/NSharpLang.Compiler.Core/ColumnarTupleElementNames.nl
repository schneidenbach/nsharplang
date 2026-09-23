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

        for collectedItem in collected {
            if collectedItem.Length > 0 {
                return collected.ToArray()
            }
        }

        return null
    }

    // True when the flattened array has at least one real name -- the same question `Flatten` answers
    // with null, asked of an already-flattened array.
    static func HasAnyName(names: string[]?): bool {
        if names == null {
            return false
        }

        for name in names {
            if name.Length > 0 {
                return true
            }
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

    // EVERY parameter's type AS WRITTEN, keyed by parameter name. The map keeps the whole labelled
    // spelling rather than the outermost element names, because a body that
    // reads `rows[0].Item` needs the names that sit INSIDE `List<(Item: string, Count: int)>` and the
    // top-level answer for that parameter is "not a tuple". A parameter whose written type mentions
    // no tuple at all is still recorded: the map is "what was written", and every reader asks it a
    // question that answers null for a type with no names in it.
    static func ParameterLabeledMap(parameterNames: string[], labeledCanonicals: string[]?): Dictionary<string, string>? {
        if labeledCanonicals == null {
            return null
        }

        map: Dictionary<string, string>? = null
        index := 0
        while index < parameterNames.Length && index < labeledCanonicals.Length {
            labeled := labeledCanonicals[index]
            if labeled != null && labeled.Length > 0 {
                if map == null {
                    map = new Dictionary<string, string>(StringComparer.Ordinal)
                }

                map[parameterNames[index]] = labeled
            }

            index = index + 1
        }

        return map
    }

    // THE STRUCTURAL CANONICAL OF A LABELLED ONE: every `name:` element prefix removed, at EVERY
    // level. `StripTupleElementNames` answers only the outermost tuple, because that is all the
    // declared positions needed; a walk that resolves an arbitrary WRITTEN sub-type back to its CLR
    // handle needs the whole spelling cleaned, or `List<(Item:string,Count:int)>` reaches the type
    // resolver with an element label still in it.
    static func StripAllElementNames(labeledCanonical: string): string {
        if labeledCanonical == null || labeledCanonical.Length == 0 {
            return ""
        }

        text := labeledCanonical
        if HasTopLevelUnionBar(text) {
            return text
        }

        if text.Length > 1 && text[0] == '&' {
            return "&" + StripAllElementNames(text.Substring(1))
        }

        if text.Length > 1 && text[text.Length - 1] == '?' {
            return StripAllElementNames(text.Substring(0, text.Length - 1)) + "?"
        }

        if text.Length > 2 && text[text.Length - 2] == '[' && text[text.Length - 1] == ']' {
            return StripAllElementNames(text.Substring(0, text.Length - 2)) + "[]"
        }

        builder := new System.Text.StringBuilder()
        if text.Length >= 2 && text[0] == '(' && text[text.Length - 1] == ')' {
            elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
            builder.Append('(')
            index := 0
            while index < elements.Count {
                if index > 0 {
                    builder.Append(',')
                }

                builder.Append(StripAllElementNames(ElementTypeText(elements[index])))
                index = index + 1
            }

            builder.Append(')')
            return builder.ToString()
        }

        open := TopLevelGenericArgumentStart(text)
        if open < 0 || text[text.Length - 1] != '>' {
            return text
        }

        arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(open + 1, text.Length - open - 2))
        builder.Append(text.Substring(0, open))
        builder.Append('<')
        argumentIndex := 0
        while argumentIndex < arguments.Count {
            if argumentIndex > 0 {
                builder.Append(',')
            }

            builder.Append(StripAllElementNames(arguments[argumentIndex]))
            argumentIndex = argumentIndex + 1
        }

        builder.Append('>')
        return builder.ToString()
    }

    // One tuple element's TYPE, with the `name:` prefix removed when it has one.
    static func ElementTypeText(element: string): string {
        colon := element.IndexOf(':')
        if colon > 0 && ColumnarTypeCanonicalizer.IsBareIdentifier(element.Substring(0, colon)) {
            return element.Substring(colon + 1)
        }

        return element
    }

    // THE TOP-LEVEL TYPE ARGUMENTS of a constructed generic's written spelling, each still labelled,
    // or null when the text is not a constructed generic.
    static func TopLevelGenericArguments(labeledCanonical: string?): List<string>? {
        if labeledCanonical == null {
            return null
        }

        text := labeledCanonical
        open := TopLevelGenericArgumentStart(text)
        if open < 0 || text.Length == 0 || text[text.Length - 1] != '>' {
            return null
        }

        return ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(open + 1, text.Length - open - 2))
    }

    // The written ELEMENT type of an array's written spelling, or null when the text is not one.
    static func ArrayElementText(labeledCanonical: string?): string? {
        if labeledCanonical == null || labeledCanonical.Length <= 2 {
            return null
        }

        if labeledCanonical[labeledCanonical.Length - 2] != '[' || labeledCanonical[labeledCanonical.Length - 1] != ']' {
            return null
        }

        return labeledCanonical.Substring(0, labeledCanonical.Length - 2)
    }

    // EVERY TYPE WRITTEN INSIDE ONE WRITTEN TYPE, itself first, each still labelled. This is what
    // lets a value read OUT of a declared type find the names that declared type gave it: the
    // receiver's written type is searched for the one sub-type whose CLR handle the value has.
    // An anonymous union is not descended into, for the same reason the attribute walk does not:
    // its arms are not positions of the emitted type.
    static func CollectSubtrees(labeledCanonical: string, collected: List<string>) {
        if labeledCanonical == null || labeledCanonical.Length == 0 {
            return
        }

        collected.Add(labeledCanonical)
        CollectChildSubtrees(labeledCanonical, collected)
    }

    static func CollectChildSubtrees(text: string, collected: List<string>) {
        if HasTopLevelUnionBar(text) {
            return
        }

        if text.Length > 1 && text[0] == '&' {
            CollectSubtrees(text.Substring(1), collected)
            return
        }

        if text.Length > 1 && text[text.Length - 1] == '?' {
            CollectSubtrees(text.Substring(0, text.Length - 1), collected)
            return
        }

        if text.Length > 2 && text[text.Length - 2] == '[' && text[text.Length - 1] == ']' {
            CollectSubtrees(text.Substring(0, text.Length - 2), collected)
            return
        }

        if text.Length >= 2 && text[0] == '(' && text[text.Length - 1] == ')' {
            elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
            for element in elements {
                CollectSubtrees(ElementTypeText(element), collected)
            }

            return
        }

        open := TopLevelGenericArgumentStart(text)
        if open < 0 || text[text.Length - 1] != '>' {
            return
        }

        arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(open + 1, text.Length - open - 2))
        for argument in arguments {
            CollectSubtrees(argument, collected)
        }
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
        for argument in arguments {
            Append(argument, collected)
        }
    }

    // A tuple node: its own element names first, then the arguments of the `ValueTuple` that carries
    // them.
    static func AppendTuple(text: string, collected: List<string>) {
        elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
        names := new List<string>()
        types := new List<string>()
        for element in elements {
            colon := element.IndexOf(':')
            if colon > 0 && ColumnarTypeCanonicalizer.IsBareIdentifier(element.Substring(0, colon)) {
                names.Add(element.Substring(0, colon))
                types.Add(element.Substring(colon + 1))
            } else {
                names.Add("")
                types.Add(element)
            }
        }

        for name in names {
            collected.Add(name)
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
        for c in text {
            if c == '(' || c == '<' || c == '[' {
                depth = depth + 1
            } else if c == ')' || c == '>' || c == ']' {
                depth = depth - 1
            } else if c == '|' && depth == 0 {
                return true
            }
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
