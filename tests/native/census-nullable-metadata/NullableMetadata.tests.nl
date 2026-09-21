namespace Census.NullableMetadata

import System
import System.Reflection


// REFERENCE-TYPE NULLABILITY HAS TO SURVIVE THE ASSEMBLY BOUNDARY, AND THE ONLY PROOF IS METADATA.
//
// `Dictionary<string, object?>` and `Dictionary<string, object>` are the same CLR type. What tells
// them apart is a `NullableAttribute` on the POSITION, and an N# assembly that omits it reads back
// as oblivious — which the analyzer resolves to `!` at every depth, so an N# caller in ANOTHER
// assembly could not pass the very type the owner's source declares. These assertions read this
// project's own emitted assembly through `NullabilityInfoContext`, the same reader the analyzer
// uses for a referenced assembly, so a regression is a failing test rather than a signature that
// silently loses its annotations.
class NullableFacts {
    static func Context(): NullabilityInfoContext {
        return new NullabilityInfoContext()
    }

    static func Method(owner: Type, name: string): MethodInfo {
        return owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
    }

    static func ReturnState(name: string): string {
        method := Method(typeof(Signatures), name)
        if method == null {
            return "<no method>"
        }

        return Describe(Context().Create(method.get_ReturnParameter()))
    }

    static func ParameterState(name: string, ordinal: int): string {
        method := Method(typeof(Signatures), name)
        if method == null {
            return "<no method>"
        }

        parameters := method.GetParameters()
        if ordinal >= parameters.Length {
            return "<no parameter>"
        }

        return Describe(Context().Create(parameters[ordinal]))
    }

    static func FieldState(owner: Type, name: string): string {
        field := owner.GetField(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)
        if field == null {
            return "<no field>"
        }

        return Describe(Context().Create(field))
    }

    static func PropertyState(owner: Type, name: string): string {
        property := owner.GetProperty(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)
        if property == null {
            return "<no property>"
        }

        return Describe(Context().Create(property))
    }

    // The read state of one position and of everything written inside it, in the same pre-order the
    // flags themselves are written in.
    static func Describe(info: NullabilityInfo): string {
        text := StateWord(info.get_ReadState())
        arguments := info.get_GenericTypeArguments()
        if arguments != null && arguments.Length > 0 {
            text = text + "<"
            index := 0
            while index < arguments.Length {
                if index > 0 {
                    text = text + ","
                }

                text = text + Describe(arguments[index])
                index = index + 1
            }

            text = text + ">"
        }

        element := info.get_ElementType()
        if element != null {
            text = text + "[" + Describe(element) + "]"
        }

        return text
    }

    static func StateWord(state: NullabilityState): string {
        if state == NullabilityState.Nullable {
            return "?"
        }

        if state == NullabilityState.NotNull {
            return "!"
        }

        return "oblivious"
    }
}

test "an annotated return reads back annotated, and a bare one reads back non-null" {
    assert NullableFacts.ReturnState("Name") == "?"
    assert NullableFacts.ReturnState("Required") == "!"
    assert NullableFacts.ReturnState("Total") == "!"
}

test "a nested type argument keeps its own annotation across the boundary" {
    assert NullableFacts.ParameterState("Take", 0) == "?<!,?>"
    assert NullableFacts.ReturnState("Map") == "!<!,?>"
    assert NullableFacts.ReturnState("Ints") == "!<!>"
}

test "an array and its element are annotated independently" {
    assert NullableFacts.ReturnState("MaybeNames") == "?[!]"
    assert NullableFacts.ReturnState("NamesWithHoles") == "![?]"
}

test "a named tuple's element annotations survive beside its element names" {
    assert NullableFacts.ReturnState("Pair") == "!<!,?>"
}

test "a field states its own annotation" {
    assert NullableFacts.FieldState(typeof(Signatures), "Label") == "?"
    assert NullableFacts.FieldState(typeof(Signatures), "Plain") == "!"
    assert NullableFacts.FieldState(typeof(Signatures), "Count") == "!"
}

test "an init-only property keeps its annotation on the property and its backing field" {
    assert NullableFacts.PropertyState(typeof(SignatureInitOnly), "Tag") == "?"
    assert NullableFacts.PropertyState(typeof(SignatureInitOnly), "Registry") == "!<!,?>"
    assert NullableFacts.PropertyState(typeof(SignatureInitOnly), "Total") == "!"
    assert NullableFacts.FieldState(typeof(SignatureInitOnly), "<Tag>k__BackingField") == "?"
}

test "a property states its own annotation, at every depth" {
    assert NullableFacts.PropertyState(typeof(SignatureProperties), "Lookup") == "!<!,?>"
    assert NullableFacts.PropertyState(typeof(SignatureProperties), "Tally") == "!"
    assert NullableFacts.FieldState(typeof(SignatureProperties), "Names") == "!<?>"
    assert NullableFacts.FieldState(typeof(SignatureProperties), "Slot") == "?"
}
