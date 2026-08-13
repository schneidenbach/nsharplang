namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE TYPE TEXT A COMPLETION SHOWS (task 019 slice 1). These are the semantic
// assertions that came out of `CompletionEngine.cs` with the rules: what the SOURCE wrote beats what
// the binder resolved, `params` is not a default, and a reflected type keeps its CLR name unless it
// is one of exactly eight.

func CttFunction(): FunctionTypeInfo {
    return new FunctionTypeInfo()
}

func CttNames(names: string[]): List<string> {
    list := new List<string>()
    index := 0
    while index < names.Length {
        list.Add(names[index])
        index = index + 1
    }

    return list
}

func CttSourceTypes(names: string[]): List<TypeReference> {
    list := new List<TypeReference>()
    index := 0
    while index < names.Length {
        reference: TypeReference = new SimpleTypeReference(names[index])
        list.Add(reference)
        index = index + 1
    }

    return list
}

func CttResolvedTypes(names: string[]): List<TypeInfo> {
    list := new List<TypeInfo>()
    index := 0
    while index < names.Length {
        resolved: TypeInfo = new SimpleTypeInfo(names[index])
        list.Add(resolved)
        index = index + 1
    }

    return list
}

func CttModifiers(modifiers: ParameterModifier[]): List<ParameterModifier> {
    list := new List<ParameterModifier>()
    index := 0
    while index < modifiers.Length {
        list.Add(modifiers[index])
        index = index + 1
    }

    return list
}

func CttAllNone(count: int): List<ParameterModifier> {
    list := new List<ParameterModifier>()
    index := 0
    while index < count {
        list.Add(ParameterModifier.None)
        index = index + 1
    }

    return list
}

test "the source-written return type beats the resolved one and the resolved one beats nothing" {
    // Both present: the SOURCE answers. This is the whole point of the rule — a completion is read
    // beside the source, so it must name the type the way the source named it.
    both := CttFunction()
    both.SourceReturnType = new SimpleTypeReference("Widget")
    both.ReturnType = BuiltInTypes.String
    assert CompletionTypeTextFacts.FormatTypeText(both) == "Widget"

    // Source absent: the resolved type answers.
    resolvedOnly := CttFunction()
    resolvedOnly.ReturnType = BuiltInTypes.String
    assert CompletionTypeTextFacts.FormatTypeText(resolvedOnly) == "string"

    // Neither: the FUNCTION TYPE itself is formatted, not "void" and not an empty string.
    bare := CttFunction()
    bareText := CompletionTypeTextFacts.FormatTypeText(bare)
    assert bareText == NullabilityMetadataReflection.FormatTypeInfo(bare)

    // A type that is not a function type is simply formatted.
    assert CompletionTypeTextFacts.FormatTypeText(BuiltInTypes.Int) == "int"
    assert CompletionTypeTextFacts.FormatTypeText(BuiltInTypes.Bool) == "bool"
}

test "a parameter's type text takes the source list, then the resolved list, then unknown" {
    functionType := CttFunction()
    sourceNames := new string[](2)
    sourceNames[0] = "Widget"
    sourceNames[1] = "Gadget"
    functionType.SourceParameterTypes = CttSourceTypes(sourceNames)

    resolvedNames := new string[](3)
    resolvedNames[0] = "int"
    resolvedNames[1] = "long"
    resolvedNames[2] = "double"
    functionType.ParameterTypes = CttResolvedTypes(resolvedNames)

    // Within the SOURCE list the source answers, even though a resolved type also exists there.
    assert CompletionTypeTextFacts.GetFunctionParameterTypeText(functionType, 0) == "Widget"
    assert CompletionTypeTextFacts.GetFunctionParameterTypeText(functionType, 1) == "Gadget"

    // PAST the source list but inside the resolved one, the resolved type answers. This is the seam
    // the rule turns on and the reason the two lists are read in this order and not merged.
    assert CompletionTypeTextFacts.GetFunctionParameterTypeText(functionType, 2) == "double"

    // Past both: "unknown". The completion still names the parameter; it just cannot type it.
    assert CompletionTypeTextFacts.GetFunctionParameterTypeText(functionType, 3) == "unknown"

    // With no lists at all every index is "unknown", including index 0.
    empty := CttFunction()
    assert CompletionTypeTextFacts.GetFunctionParameterTypeText(empty, 0) == "unknown"
}

test "a function type's parameter list renders defaults, refuses to default params, and is null without names" {
    // No parameter NAMES at all is no list — `null`, not "()". A caller shows nothing rather than
    // an empty signature.
    nameless := CttFunction()
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(nameless) == null

    names := new string[](3)
    names[0] = "count"
    names[1] = "label"
    names[2] = "extras"

    types := new string[](3)
    types[0] = "int"
    types[1] = "string"
    types[2] = "string[]"

    // Required = 1, so `label` and `extras` are past it; `extras` is `params` and must NOT read
    // `= ...`, because `params` is variadic, not defaulted.
    modifiers := new ParameterModifier[](3)
    modifiers[0] = ParameterModifier.None
    modifiers[1] = ParameterModifier.None
    modifiers[2] = ParameterModifier.Params

    requiredOne: int? = 1
    requiredNone: int? = 0
    requiredTwo: int? = 2

    withDefaults := CttFunction()
    withDefaults.ParameterNames = CttNames(names)
    withDefaults.SourceParameterTypes = CttSourceTypes(types)
    withDefaults.ParameterModifiers = CttModifiers(modifiers)
    withDefaults.RequiredParameterCount = requiredOne
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(withDefaults) ==
        "(count int, label string = ..., extras string[])"

    // NO required count is no default anywhere: the rule needs a number to compare against and
    // will not invent one.
    unknownRequired := CttFunction()
    unknownRequired.ParameterNames = CttNames(names)
    unknownRequired.SourceParameterTypes = CttSourceTypes(types)
    unknownRequired.ParameterModifiers = CttModifiers(modifiers)
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(unknownRequired) ==
        "(count int, label string, extras string[])"

    // Required = 0 defaults everything that is not `params`.
    allOptional := CttFunction()
    allOptional.ParameterNames = CttNames(names)
    allOptional.SourceParameterTypes = CttSourceTypes(types)
    allOptional.ParameterModifiers = CttModifiers(modifiers)
    allOptional.RequiredParameterCount = requiredNone
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(allOptional) ==
        "(count int = ..., label string = ..., extras string[])"

    // A MISSING modifier list still defaults — the modifier read is total and answers `None`.
    noModifiers := CttFunction()
    noModifiers.ParameterNames = CttNames(names)
    noModifiers.SourceParameterTypes = CttSourceTypes(types)
    noModifiers.RequiredParameterCount = requiredTwo
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(noModifiers) ==
        "(count int, label string, extras string[] = ...)"

    // A name with no type on either list still appears, typed "unknown".
    untypedNames := new string[](1)
    untypedNames[0] = "value"
    untyped := CttFunction()
    untyped.ParameterNames = CttNames(untypedNames)
    untyped.ParameterModifiers = CttAllNone(1)
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(untyped) == "(value unknown)"

    // Zero names is an empty list, which IS "()" — distinct from `null` above.
    emptyNames := new string[](0)
    zero := CttFunction()
    zero.ParameterNames = CttNames(emptyNames)
    assert CompletionTypeTextFacts.FormatFunctionTypeParameters(zero) == "()"
}

test "the reflected type text aliases exactly eight full names and keeps every other CLR name" {
    // The eight, by FULL NAME.
    voidType := Type.GetType("System.Void")
    if voidType == null {
        throw new InvalidOperationException("System.Void did not resolve.")
    }

    assert CompletionTypeTextFacts.FormatClrTypeText(voidType) == "void"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(int)) == "int"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(long)) == "long"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(string)) == "string"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(bool)) == "bool"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(double)) == "double"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(float)) == "float"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(object)) == "object"

    // EVERYTHING ELSE KEEPS ITS CLR NAME. This is the difference from
    // `NullabilityMetadataReflection.FormatClrTypeName`, which would say "byte" and "decimal" here,
    // and it is why the two rules are deliberately not folded into one.
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(byte)) == "Byte"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(decimal)) == "Decimal"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(short)) == "Int16"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(char)) == "Char"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(Exception)) == "Exception"

    // A generic type loses its arity tick and shows its arguments, recursively — and the arguments
    // go through the SAME eight aliases.
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(List<int>)) == "List<int>"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(Dictionary<string, int>)) ==
        "Dictionary<string, int>"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(List<List<string>>)) ==
        "List<List<string>>"
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(Dictionary<string, List<byte>>)) ==
        "Dictionary<string, List<Byte>>"

    // An ARRAY is not special-cased: it keeps the CLR spelling of its name.
    assert CompletionTypeTextFacts.FormatClrTypeText(typeof(int[])) == "Int32[]"
}
