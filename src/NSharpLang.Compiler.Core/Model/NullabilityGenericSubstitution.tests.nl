namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// Native contracts for A SUBSTITUTED TYPE PARAMETER TAKES THE ARGUMENT'S NULLABILITY.
//
// `NullabilityInfoContext` answers `Nullable` for EVERY position declared with a bare type parameter
// — measured here, against the closed instantiation as well as the open definition — and taking that
// answer is what made `Lazy<string>.Value`, `Task<string>.Result` and `Tuple<string, int>.Item1`
// maybe-null and reported NL905 on correct code. The reader has to substitute instead.
//
// The two facts this owner answers are pinned against the BCL rather than against fixtures, because
// the shapes that matter are exactly the ones the BCL happens to have: a property whose type is a
// class parameter, a method that annotates its return `T?` with its own attribute, and one that
// annotates it through a `NullableContextAttribute` on the method while the enclosing type says
// something else.
func SubstitutionDefinitionOf(closed: Type): Type {
    return closed.GetGenericTypeDefinition()
}

func SubstitutionProperty(owner: Type, name: string): PropertyInfo {
    property := owner.GetProperty(name, BindingFlags.Public | BindingFlags.Instance)
    if property == null {
        throw new InvalidOperationException(owner.Name + "." + name + " was not found.")
    }

    return property
}

func SubstitutionMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException(owner.Name + "." + name + " was not found.")
    }

    return method
}

func SubstitutionStaticMethod(owner: Type, name: string, parameterCount: int): MethodInfo {
    methods := owner.GetMethods(BindingFlags.Public | BindingFlags.Static)
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == name && candidate.GetParameters().Length == parameterCount {
            return candidate
        }

        index = index + 1
    }

    throw new InvalidOperationException(owner.Name + "." + name + " was not found.")
}

// ---- the open spelling ------------------------------------------------------------------------

test "A PROPERTY OF A CONSTRUCTED GENERIC IS SPELLED WITH THE DEFINITION'S PARAMETER" {
    closed := SubstitutionProperty(typeof(Lazy<string>), "Value")

    // The CLOSED property already reads `System.String` — the CLR substituted it — and the fact that
    // the source wrote `T` survives only on the definition.
    assert closed.get_PropertyType() == typeof(string)
    assert NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenPropertyType(closed))
}

test "A PROPERTY OF A NON-GENERIC TYPE IS ITS OWN SPELLING" {
    length := SubstitutionProperty(typeof(string), "Length")

    assert NullabilityGenericSubstitution.OpenPropertyType(length) == typeof(int)
    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenPropertyType(length))
}

test "A PROPERTY WHOSE TYPE DOES NOT MENTION A PARAMETER IS NOT A SUBSTITUTED POSITION" {
    count := SubstitutionProperty(typeof(List<string>), "Count")

    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenPropertyType(count))
}

test "A CLOSED GENERIC METHOD'S RETURN IS SPELLED BY ITS OWN DEFINITION" {
    firstOrDefault := SubstitutionStaticMethod(typeof(System.Linq.Enumerable), "FirstOrDefault", 1)
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(string)
    closed := firstOrDefault.MakeGenericMethod(closedArguments)

    // Closed, the return is `System.String`; the method definition still spells it `TSource`.
    assert closed.get_ReturnType() == typeof(string)
    assert NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenParameterType(closed.get_ReturnParameter()))
}

test "A METHOD DECLARED ON A CONSTRUCTED GENERIC TYPE IS SPELLED BY THAT TYPE'S DEFINITION" {
    find := SubstitutionMethod(typeof(List<string>), "Find")

    assert find.get_ReturnType() == typeof(string)
    assert NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenParameterType(find.get_ReturnParameter()))
}

test "A METHOD'S PARAMETER POSITION IS SPELLED THE SAME WAY" {
    add := SubstitutionMethod(typeof(List<string>), "Add")
    parameter := add.GetParameters()[0]

    assert NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenParameterType(parameter))
}

test "A BY-REF SHELL IS TRANSPARENT TO THE QUESTION" {
    tryGetValue := SubstitutionMethod(typeof(Dictionary<string, string>), "TryGetValue")
    outParameter := tryGetValue.GetParameters()[1]
    openType := NullabilityGenericSubstitution.OpenParameterType(outParameter)

    // `out TValue` is `TValue&` in metadata, and `ref T` is still `T` for this question — exactly as
    // the conversion reads through the shell.
    assert openType.get_IsByRef()
    assert NullabilityGenericSubstitution.IsTypeParameterPosition(openType)
}

test "A NON-GENERIC METHOD'S RETURN IS NOT A SUBSTITUTED POSITION" {
    toUpper := typeof(string).GetMethod("ToUpperInvariant")
    assert toUpper != null
    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenParameterType(toUpper.get_ReturnParameter()))
}

test "AN ARRAY OF A TYPE PARAMETER IS NOT A TYPE PARAMETER POSITION" {
    toArray := SubstitutionMethod(typeof(List<string>), "ToArray")
    openType := NullabilityGenericSubstitution.OpenParameterType(toArray.get_ReturnParameter())

    // `T[]` is an ARRAY whose ELEMENT is a parameter. The array's own nullability is metadata's to
    // answer and this rule must not take it over — only the element is substituted, and the ordinary
    // walk already handles that.
    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(openType)
}

test "A NULL SPELLING IS NOT A TYPE PARAMETER POSITION" {
    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(null)
}

// ---- the annotation ----------------------------------------------------------------------------

test "AN UNANNOTATED PARAMETER POSITION FOLLOWS THE ARGUMENT" {
    peek := SubstitutionMethod(typeof(Stack<string>), "Peek")
    returnParameter := peek.get_ReturnParameter()

    // `Stack<T>.Peek` returns `T` with no attribute of its own; `NullabilityInfoContext` still calls
    // it Nullable, and that is the answer this rule refuses.
    assert !NullabilityGenericSubstitution.IsAnnotatedNullable(returnParameter.GetCustomAttributesData(), peek)
}

test "`T?` WRITTEN ON THE POSITION IS A NullableAttribute OF 2" {
    find := SubstitutionMethod(SubstitutionDefinitionOf(typeof(List<string>)), "Find")
    returnParameter := find.get_ReturnParameter()

    // `List<T>.Find` returns `T?`, and the annotation is on the position itself.
    assert NullabilityGenericSubstitution.ReadFlag(returnParameter.GetCustomAttributesData(), "System.Runtime.CompilerServices.NullableAttribute") == 2
    assert NullabilityGenericSubstitution.IsAnnotatedNullable(returnParameter.GetCustomAttributesData(), find)
}

test "`T?` WRITTEN THROUGH A NullableContextAttribute ON THE METHOD COUNTS TOO" {
    firstOrDefault := SubstitutionStaticMethod(typeof(System.Linq.Enumerable), "FirstOrDefault", 1)
    first := SubstitutionStaticMethod(typeof(System.Linq.Enumerable), "First", 1)

    // NEITHER return carries an attribute of its own. `FirstOrDefault` is `TSource?` and `First` is
    // `TSource`, and the only thing that says so is the compiler's size optimisation: the METHOD
    // carries `NullableContextAttribute(2)` while the enclosing `Enumerable` carries `(1)`. Reading
    // only the position would make the two mean the same thing.
    assert NullabilityGenericSubstitution.ReadFlag(firstOrDefault.get_ReturnParameter().GetCustomAttributesData(), "System.Runtime.CompilerServices.NullableAttribute") == -1
    assert NullabilityGenericSubstitution.ContextFlag(firstOrDefault) == 2
    assert NullabilityGenericSubstitution.IsAnnotatedNullable(firstOrDefault.get_ReturnParameter().GetCustomAttributesData(), firstOrDefault)

    assert NullabilityGenericSubstitution.ContextFlag(first) == 1
    assert !NullabilityGenericSubstitution.IsAnnotatedNullable(first.get_ReturnParameter().GetCustomAttributesData(), first)
}

test "THE NEAREST CONTEXT WINS — THE ENCLOSING TYPE'S IS ONLY THE FALLBACK" {
    // `Enumerable` itself says 1. A method that says nothing inherits that; one that says 2 does not.
    assert NullabilityGenericSubstitution.ContextFlag(typeof(System.Linq.Enumerable)) == 1
}

test "NO CONTEXT ANYWHERE IS -1, AND -1 IS NOT ANNOTATED NULLABLE" {
    // Nothing found at all is oblivious, which is not "annotated nullable": the substituted argument
    // decides, exactly as it does for an unannotated `T`.
    assert NullabilityGenericSubstitution.ContextFlag(null) == -1
}

test "`[MaybeNullWhen(...)]` IS A POSTCONDITION AND NOT PART OF THE TYPE" {
    tryGetValue := SubstitutionMethod(typeof(Dictionary<string, string>), "TryGetValue")
    outParameter := tryGetValue.GetParameters()[1]

    // `TryGetValue` declares `out TValue value`, so with a `Dictionary<string, string>` receiver the
    // parameter's TYPE is `string` — the false branch's maybe-null is what
    // `AnalyzerNullabilityPostconditions` files against the call. Folding the attribute into the type
    // here makes BOTH branches maybe-null, because the branch the attribute did not name falls back
    // to the declared state, and `if map.TryGetValue(k, out found) { found.Label }` is then NL905 in
    // the branch the call just proved.
    assert !NullabilityGenericSubstitution.IsAnnotatedNullable(outParameter.GetCustomAttributesData(), tryGetValue)
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(outParameter)) == "Simple(string)"
}

test "A BYTE FLAG IS READ FROM THE BOXED VALUE, AND ONLY 0, 1 AND 2 ARE FLAGS" {
    // Under a MetadataLoadContext an argument's own `ArgumentType` is a projected `System.Byte` that
    // is not `typeof(byte)`, while `Value` is still a live boxed CLR byte — so the comparison is
    // against boxed bytes and nothing else.
    zero: object = NullabilityGenericSubstitution.ByteOf(0)
    one: object = NullabilityGenericSubstitution.ByteOf(1)
    two: object = NullabilityGenericSubstitution.ByteOf(2)
    three: object = NullabilityGenericSubstitution.ByteOf(3)
    boxedInt: object = 2

    assert NullabilityGenericSubstitution.ByteValue(zero) == 0
    assert NullabilityGenericSubstitution.ByteValue(one) == 1
    assert NullabilityGenericSubstitution.ByteValue(two) == 2
    assert NullabilityGenericSubstitution.ByteValue(three) == -1
    assert NullabilityGenericSubstitution.ByteValue(null) == -1

    // A boxed INT is not a boxed byte, which is why the comparison cannot be written against `2`.
    assert NullabilityGenericSubstitution.ByteValue(boxedInt) == -1
}

// ---- the answers the reader gives -------------------------------------------------------------

test "A CLASS PARAMETER PROPERTY OF A CLOSED GENERIC IS NOT MAYBE-NULL" {
    lazyValue := SubstitutionProperty(typeof(Lazy<string>), "Value")
    taskResult := SubstitutionProperty(typeof(System.Threading.Tasks.Task<string>), "Result")
    tupleItem := SubstitutionProperty(typeof(Tuple<string, int>), "Item1")

    // All three read `Nullable(Simple(string))` while the reader took `NullabilityInfoContext`'s
    // answer, which is where NL905 "`docQuery.Value` is maybe-null" came from.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertProperty(lazyValue)) == "Simple(string)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertProperty(taskResult)) == "Simple(string)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertProperty(tupleItem)) == "Simple(string)"
}

test "A METHOD PARAMETER THAT IS A CLASS PARAMETER IS NOT MAYBE-NULL EITHER" {
    invoke := SubstitutionMethod(typeof(Predicate<string>), "Invoke")
    parameter := invoke.GetParameters()[0]

    // This is the lambda-parameter half: `xs.Find(s => s.Length > 0)` reported `s` maybe-null.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(parameter)) == "Simple(string)"
}

test "A `T?` RETURN STAYS MAYBE-NULL AFTER THE SUBSTITUTION" {
    find := SubstitutionMethod(typeof(List<string>), "Find")

    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertReturn(find)) == "Nullable(Simple(string))"
}

test "A VALUE-TYPE ARGUMENT SUBSTITUTES WITHOUT ACQUIRING A NULLABLE SHELL" {
    lazyValue := SubstitutionProperty(typeof(Lazy<int>), "Value")

    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertProperty(lazyValue)) == "Simple(int)"
}

test "THE COMPILER'S OWN GENERIC MEMBERS READ THE SAME WAY AS THE BCL'S" {
    // `ColumnarSemanticDefinitionIndex<TDefinition>.TryGetExact(name, out TDefinition)` is an N#
    // declaration in this very assembly, so its metadata is what the N# EMITTER wrote rather than
    // what Roslyn wrote — and the rule has to read it identically. The `out` position is a bare
    // parameter, and closing the type over a non-nullable reference argument makes it non-nullable.
    closed := typeof(ColumnarSemanticDefinitionIndex<string>)
    tryGetExact := SubstitutionMethod(closed, "TryGetExact")
    outParameter := tryGetExact.GetParameters()[1]

    openType := NullabilityGenericSubstitution.OpenParameterType(outParameter)
    assert openType.get_IsByRef()
    assert NullabilityGenericSubstitution.IsTypeParameterPosition(openType)
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(outParameter)) == "Simple(string)"
}

test "A COMPILER GENERIC'S LIST-OF-PARAMETER MEMBER IS NOT A SUBSTITUTED POSITION" {
    closed := typeof(ColumnarSemanticDefinitionIndex<string>)
    values := SubstitutionProperty(closed, "Values")

    // `List<TDefinition>` mentions the parameter but IS NOT one: the outer `List` has a nullability
    // of its own and the element is substituted by the ordinary walk.
    assert !NullabilityGenericSubstitution.IsTypeParameterPosition(NullabilityGenericSubstitution.OpenPropertyType(values))
}
