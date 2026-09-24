namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// WHAT A FUNCTION TYPE PRINTS AS.
//
// Every other shape in `TypeInfoModels` answers its own WRITTEN form from `ToString`, and
// `FunctionTypeInfo` answered the CLR name of the class instead — so a mismatch between two
// delegates read `should return NSharpLang.Compiler.FunctionTypeInfo but returns
// NSharpLang.Compiler.FunctionTypeInfo`, which states a contradiction and names neither signature.
// Census LAMBDA4 gave it the written form; these pin it, because the rendering is a USER-FACING
// contract that six diagnostic owners read through the `object`-typed `ToString` idiom.
func FunctionDisplaySignature(parameterTypes: List<TypeInfo>?, returnType: TypeInfo?): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.ParameterTypes = parameterTypes
    signature.ReturnType = returnType
    return signature
}

func FunctionDisplayTypes(first: TypeInfo?, second: TypeInfo?): List<TypeInfo> {
    types := new List<TypeInfo>()
    if first != null {
        types.Add(first)
    }

    if second != null {
        types.Add(second)
    }

    return types
}

func FunctionDisplayText(signature: FunctionTypeInfo): string {
    boxed := signature as object
    rendered := boxed.ToString()
    if rendered == null {
        return "<null>"
    }

    return rendered
}

test "a function type prints its signature in N#'s own function-type syntax" {
    oneParameter := FunctionDisplaySignature(FunctionDisplayTypes(BuiltInTypes.Int, null), BuiltInTypes.String)
    assert FunctionDisplayText(oneParameter) == "(int) -> string"

    twoParameters := FunctionDisplaySignature(FunctionDisplayTypes(BuiltInTypes.Int, BuiltInTypes.Bool), BuiltInTypes.String)
    assert FunctionDisplayText(twoParameters) == "(int, bool) -> string"
}

test "a function type that takes nothing and gives nothing still prints both halves" {
    unit := FunctionDisplaySignature(FunctionDisplayTypes(null, null), BuiltInTypes.Void)
    assert FunctionDisplayText(unit) == "() -> void"
}

test "a function type's positions print through the SHAPES they hold, not through their names" {
    nested := FunctionDisplaySignature(FunctionDisplayTypes(BuiltInTypes.Int, null), BuiltInTypes.String)
    outer := FunctionDisplaySignature(FunctionDisplayTypes(nested, null), BuiltInTypes.Bool)
    assert FunctionDisplayText(outer) == "((int) -> string) -> bool"

    arrayParameter := FunctionDisplaySignature(FunctionDisplayTypes(new ArrayTypeInfo(BuiltInTypes.Int), null), new NullableTypeInfo(BuiltInTypes.String))
    assert FunctionDisplayText(arrayParameter) == "(int[]) -> string?"
}

// A SIGNATURE WITH NO POSITIONS IS A DECLARATION FACT, NOT A SHAPE. A method group carried before an
// overload is chosen has neither a parameter list nor a return type, and printing `() -> ` for it
// would claim a shape it does not have — so it answers the NAME it was written with.
test "a function type with no positions prints the name it was written with" {
    synthetic := FunctionDisplaySignature(null, null)
    synthetic.SyntheticName = "Pick"
    assert FunctionDisplayText(synthetic) == "Pick"

    sourceNamed := FunctionDisplaySignature(null, null)
    sourceNamed.SourceName = "greet"
    assert FunctionDisplayText(sourceNamed) == "greet"

    anonymous := FunctionDisplaySignature(null, null)
    assert FunctionDisplayText(anonymous) == "function"
}

// THE SYNTHETIC NAME WINS OVER THE SOURCE NAME, because the synthetic one is what overload
// resolution selected and therefore what a diagnostic about this call should name.
test "a nameless-shape function type prefers its synthetic name over its source name" {
    both := FunctionDisplaySignature(null, null)
    both.SyntheticName = "Pick_1"
    both.SourceName = "Pick"
    assert FunctionDisplayText(both) == "Pick_1"
}

// A HALF-BUILT SIGNATURE IS NOT A SHAPE EITHER. The lambda walk builds the parameter list before it
// knows the return type, and a signature caught mid-build must not print `(int) -> ` with nothing
// after the arrow.
test "a function type with parameters but no return type falls back to its name" {
    halfBuilt := FunctionDisplaySignature(FunctionDisplayTypes(BuiltInTypes.Int, null), null)
    halfBuilt.SourceName = "half"
    assert FunctionDisplayText(halfBuilt) == "half"
}
