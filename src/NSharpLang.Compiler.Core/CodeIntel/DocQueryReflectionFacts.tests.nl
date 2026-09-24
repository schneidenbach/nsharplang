namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection


// CONTRACTS FOR WHAT A REFLECTED TYPE READS AS (task 019 slice 6). These are the semantic
// assertions that came out of `DocQuery.cs` with the type-text family: the HUMAN spelling a doc
// answer shows, the QUALIFIED spelling it titles itself with, and the ECMA-334 doc-comment id it
// looks the XML documentation up by.
//
// THE TWO SPELLINGS ARE PINNED AGAINST EACH OTHER ON PURPOSE. `int` and `System.Int32`,
// `List<string>` and `System.Collections.Generic.List{System.String}`, `int[]` and
// `System.Int32[]` are the same `Type` read two ways, and the failure mode this family actually
// has is answering one where the other was wanted — which looks right and finds no documentation.
func DqrfMethodWithFirstParameter(owner: Type, name: string, firstParameterFullName: string, parameterCount: int): MethodInfo? {
    flags := BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance
    methods := owner.GetMethods(flags)
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        parameters := candidate.GetParameters()
        if candidate.get_Name() == name && parameters.Length == parameterCount {
            first := parameters[0]
            firstType := first.get_ParameterType()
            if firstType.get_FullName() == firstParameterFullName {
                return candidate
            }
        }

        index = index + 1
    }

    return null
}

// A `typeof(T)` OF AN ARBITRARY BCL TYPE IS NOT AVAILABLE ON THIS EMIT PATH, so a type that has no
// keyword and no generic construction is found the way the product itself finds one: by name, in an
// assembly that was loaded rather than named.
func DqrfNamedCoreType(fullName: string): Type? {
    coreLibrary := typeof(int).get_Assembly()
    types := coreLibrary.GetTypes()
    index := 0
    while index < types.Length {
        candidate := types[index]
        if candidate.get_FullName() == fullName {
            return candidate
        }

        index = index + 1
    }

    return null
}

func DqrfGenericParameterAt(closed: Type, position: int): Type {
    definition := closed.GetGenericTypeDefinition()
    parameters := definition.GetGenericArguments()
    return parameters[position]
}

test "the human spelling prefers the built-in alias over the CLR name" {
    assert DocQueryReflectionFacts.FormatType(typeof(int)) == "int"
    assert DocQueryReflectionFacts.FormatType(typeof(long)) == "long"
    assert DocQueryReflectionFacts.FormatType(typeof(bool)) == "bool"
    assert DocQueryReflectionFacts.FormatType(typeof(char)) == "char"
    assert DocQueryReflectionFacts.FormatType(typeof(byte)) == "byte"
    assert DocQueryReflectionFacts.FormatType(typeof(float)) == "float"
    assert DocQueryReflectionFacts.FormatType(typeof(double)) == "double"
    assert DocQueryReflectionFacts.FormatType(typeof(string)) == "string"
    assert DocQueryReflectionFacts.FormatType(typeof(object)) == "object"
}

test "a type with no alias reads as its bare name with the arity suffix stripped" {
    assert DocQueryReflectionFacts.FormatType(typeof(DateTime)) == "DateTime"
    listText := DocQueryReflectionFacts.FormatType(typeof(List<int>))
    assert listText.IndexOf('`') < 0
}

test "the human spelling recurses through generic arguments and array elements" {
    assert DocQueryReflectionFacts.FormatType(typeof(List<int>)) == "List<int>"
    assert DocQueryReflectionFacts.FormatType(typeof(List<string>)) == "List<string>"
    assert DocQueryReflectionFacts.FormatType(typeof(Dictionary<string, int>)) == "Dictionary<string, int>"
    assert DocQueryReflectionFacts.FormatType(typeof(List<List<string>>)) == "List<List<string>>"
    assert DocQueryReflectionFacts.FormatType(typeof(int[])) == "int[]"
    assert DocQueryReflectionFacts.FormatType(typeof(string[])) == "string[]"
    assert DocQueryReflectionFacts.FormatType(typeof(int[][])) == "int[][]"
}

test "a generic PARAMETER is answered before anything else, by its own name" {
    parameter := DqrfGenericParameterAt(typeof(List<int>), 0)
    assert parameter.get_IsGenericParameter()
    assert DocQueryReflectionFacts.FormatType(parameter) == "T"
}

test "a DEFINITION shows its parameter names where a CONSTRUCTION shows its arguments" {
    definition := typeof(List<int>).GetGenericTypeDefinition()
    assert DocQueryReflectionFacts.FormatTypeName(definition) == "List<T>"
    assert DocQueryReflectionFacts.FormatTypeName(typeof(List<int>)) == "List<int>"
}

test "the qualified spelling is namespace plus name, not the CLR full name" {
    assert DocQueryReflectionFacts.FormatQualifiedType(typeof(string)) == "System.String"
    assert DocQueryReflectionFacts.FormatQualifiedType(typeof(DateTime)) == "System.DateTime"
    assert DocQueryReflectionFacts.FormatQualifiedType(typeof(List<int>)) == "System.Collections.Generic.List<int>"
}

test "a NESTED type is rendered through its declaring type and never as Outer plus Inner" {
    publicOnly := BindingFlags.Public
    nestedTypes := typeof(List<int>).GetNestedTypes(publicOnly)
    assert nestedTypes.Length > 0

    nested := nestedTypes[0]
    assert nested.get_IsNested()

    declaringType := nested.get_DeclaringType()
    assert declaringType != null

    qualified := DocQueryReflectionFacts.FormatQualifiedType(nested)
    assert qualified.IndexOf('+') < 0
    assert qualified.StartsWith(DocQueryReflectionFacts.FormatQualifiedType(declaringType) + ".", StringComparison.Ordinal)
}

test "the doc-id spelling is the CLR name with nesting flattened to dots" {
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(int)) == "System.Int32"
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(string)) == "System.String"
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(int[])) == "System.Int32[]"
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(int[][])) == "System.Int32[][]"
}

// A DOC-ID KEEPS THE ARITY SUFFIX AND THE HUMAN SPELLING DROPS IT — the two walks are otherwise the
// same shape, and this is the pair of assertions that stops one being substituted for the other.
test "a doc-id names a generic construction with braces and a comma, not angle brackets" {
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(List<string>)) == "System.Collections.Generic.List`1{System.String}"
    assert DocQueryReflectionFacts.FormatTypeForDocId(typeof(Dictionary<string, int>)) == "System.Collections.Generic.Dictionary`2{System.String,System.Int32}"
    assert DocQueryReflectionFacts.FormatType(typeof(List<string>)) == "List<string>"
}

test "a doc-id names a generic parameter by POSITION, and a type's differs from a method's" {
    parameter := DqrfGenericParameterAt(typeof(List<int>), 0)
    assert parameter.get_DeclaringMethod() == null
    assert parameter.get_GenericParameterPosition() == 0
    assert DocQueryReflectionFacts.FormatTypeForDocId(parameter) == "`0"

    secondParameter := DqrfGenericParameterAt(typeof(Dictionary<string, int>), 1)
    assert DocQueryReflectionFacts.FormatTypeForDocId(secondParameter) == "`1"
}

// THE ORDER OF THE DOC-ID ARMS IS THE POLICY AND THIS IS THE ASSERTION THAT PINS IT. A `ref int` is
// a by-ref BEFORE it is anything else, and its id is the ELEMENT's id with `@` appended — testing
// by-ref before array is what stops `ref int[]` reading as `System.Int32@[]`.
test "a by-ref parameter's doc-id decorates the element id, and the by-ref arm runs first" {
    tryParse := DqrfMethodWithFirstParameter(typeof(int), "TryParse", "System.String", 2)
    assert tryParse != null

    parameters := tryParse.GetParameters()
    secondParameter := parameters[1]
    byRefParameter := secondParameter.get_ParameterType()
    assert byRefParameter.get_IsByRef()

    firstParameter := parameters[0]
    assert DocQueryReflectionFacts.FormatTypeForDocId(byRefParameter) == "System.Int32@"
    assert DocQueryReflectionFacts.FormatTypeForDocId(firstParameter.get_ParameterType()) == "System.String"
}

test "a method's doc-id is M colon owner dot name with its parameters' DOC-ID spellings" {
    tryParse := DqrfMethodWithFirstParameter(typeof(int), "TryParse", "System.String", 2)
    assert tryParse != null
    assert DocQueryReflectionFacts.GetMethodDocId(tryParse) == "M:System.Int32.TryParse(System.String,System.Int32@)"
}

test "a signature shows types before names and a parameter list shows names before types" {
    tryParse := DqrfMethodWithFirstParameter(typeof(int), "TryParse", "System.String", 2)
    assert tryParse != null

    signature := DocQueryReflectionFacts.FormatMethodSignature(tryParse)
    assert signature.StartsWith("TryParse(string ", StringComparison.Ordinal)
    assert signature.EndsWith(")", StringComparison.Ordinal)

    // A BY-REF HAS NO HUMAN ALIAS: `System.Int32&` matches no built-in, so the human spelling falls
    // through to the bare CLR name and keeps the ampersand. The doc-id spelling of the same
    // parameter is `System.Int32@`, which is the assertion above.
    assert signature.IndexOf("Int32& ") >= 0

    parameterList := DocQueryReflectionFacts.FormatParameters(tryParse)
    assert parameterList.StartsWith("(", StringComparison.Ordinal)
    assert parameterList.EndsWith(")", StringComparison.Ordinal)
    assert parameterList.IndexOf(": string") >= 0
    assert parameterList.IndexOf(": Int32&") >= 0
}

test "a constructor's signature is named after its declaring type, not after dot-ctor" {
    instanceOnly := BindingFlags.Public | BindingFlags.Instance
    constructors := typeof(List<int>).GetConstructors(instanceOnly)
    assert constructors.Length > 0

    constructor: MethodBase = constructors[0]
    signature := DocQueryReflectionFacts.FormatMethodSignature(constructor)
    assert signature.StartsWith("List(", StringComparison.Ordinal)
    assert signature.IndexOf(".ctor") < 0

    docId := DocQueryReflectionFacts.GetMethodDocId(constructor)
    assert docId.IndexOf("#ctor") >= 0
    assert docId.StartsWith("M:System.Collections.Generic.List", StringComparison.Ordinal)
}

test "the five kind words are ranked, and enum beats struct" {
    enumType := DqrfNamedCoreType("System.StringComparison")
    assert enumType != null
    assert enumType.get_IsValueType()
    assert DocQueryReflectionFacts.GetTypeKind(enumType) == "enum"

    interfaceType := DqrfNamedCoreType("System.IDisposable")
    assert interfaceType != null
    assert DocQueryReflectionFacts.GetTypeKind(interfaceType) == "interface"

    abstractType := DqrfNamedCoreType("System.IO.Stream")
    assert abstractType != null
    assert DocQueryReflectionFacts.GetTypeKind(abstractType) == "abstract class"

    assert DocQueryReflectionFacts.GetTypeKind(typeof(int)) == "struct"
    assert DocQueryReflectionFacts.GetTypeKind(typeof(DateTime)) == "struct"
    assert DocQueryReflectionFacts.GetTypeKind(typeof(string)) == "class"
}

test "the base list shows what a type inherits and implements, and drops System.Object" {
    baseTypes := DocQueryReflectionFacts.GetBaseTypes(typeof(string))
    assert baseTypes.Length > 0

    index := 0
    sawObject := false
    sawComparable := false
    while index < baseTypes.Length {
        entry := baseTypes[index]
        if entry == "object" {
            sawObject = true
        }

        if entry.StartsWith("IComparable", StringComparison.Ordinal) {
            sawComparable = true
        }

        index = index + 1
    }

    assert !sawObject
    assert sawComparable
}

test "a type with no base type at all still answers a list" {
    baseTypes := DocQueryReflectionFacts.GetBaseTypes(typeof(object))
    assert baseTypes != null
    assert baseTypes.Length == 0
}
