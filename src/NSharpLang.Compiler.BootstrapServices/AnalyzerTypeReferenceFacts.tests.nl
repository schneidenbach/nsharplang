namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// Native contracts for the pure decision surface of the analyzer's type-REFERENCE resolver. All three
// rules were inline or `private` in Analyzer.cs, so nothing named them: their behaviour was pinned
// only indirectly, through end-to-end diagnostics. This is their first DIRECT pinning.

func ReferenceFactsSimpleName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    simple := candidate as SimpleTypeInfo
    if simple == null {
        return "<not-simple>"
    }

    return simple.Name
}

func ReferenceFactsNamespaceText(namespaces: List<string?>): string {
    text := ""
    index := 0
    while index < namespaces.Count {
        if index > 0 {
            text = text + ","
        }
        entry := namespaces[index]
        if entry == null {
            text = text + "<global>"
        } else {
            text = text + entry
        }
        index = index + 1
    }
    return text
}

func ReferenceFactsNamespaces(names: string[]): List<string> {
    namespaces := new List<string>()
    index := 0
    while index < names.Length {
        namespaces.Add(names[index])
        index = index + 1
    }
    return namespaces
}

func ReferenceFactsTypeParameters(names: string[]): TypeParameter[] {
    parameters := new TypeParameter[](names.Length)
    index := 0
    while index < names.Length {
        parameters[index] = new TypeParameter(names[index])
        index = index + 1
    }
    return parameters
}

test "the built-in table answers exactly sixteen spellings and nothing else" {
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("int")) == "int"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("long")) == "long"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("float")) == "float"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("double")) == "double"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("decimal")) == "decimal"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("byte")) == "byte"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("sbyte")) == "sbyte"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("short")) == "short"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("ushort")) == "ushort"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("uint")) == "uint"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("ulong")) == "ulong"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("char")) == "char"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("bool")) == "bool"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("string")) == "string"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("void")) == "void"
    assert ReferenceFactsSimpleName(AnalyzerTypeReferenceFacts.BuiltInSimpleType("object")) == "object"

    // The synthesised types are DELIBERATELY not here: a program cannot name them at a type position,
    // and admitting them would let `null` or `never` be written as an annotation.
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("null") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("never") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("unknown") == null

    // `var` is handled earlier by the resolver, with its own diagnostic; it is not a built-in type.
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("var") == null

    // The table is case-SENSITIVE and exact: no CLR spellings, no aliases, no whitespace tolerance.
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("Int") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("INT") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("Int32") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("int32") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("String") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("Boolean") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("nint") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("nuint") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("dynamic") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("int ") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType(" int") == null
    assert AnalyzerTypeReferenceFacts.BuiltInSimpleType("") == null
}

test "the built-in table hands back a fresh SimpleTypeInfo that compares equal by value" {
    first := AnalyzerTypeReferenceFacts.BuiltInSimpleType("int")
    second := AnalyzerTypeReferenceFacts.BuiltInSimpleType("int")
    assert first != null
    assert second != null

    // Two calls are two instances, so callers must compare by VALUE. `BuiltInTypes.Is` is that
    // comparison, and it is what the whole analyzer uses.
    assert !Object.ReferenceEquals(first, second)
    assert BuiltInTypes.Is(first, BuiltInTypes.Int)
    assert BuiltInTypes.IsNot(first, BuiltInTypes.Long)
    assert BuiltInTypes.Is(AnalyzerTypeReferenceFacts.BuiltInSimpleType("object"), BuiltInTypes.Object)
    assert BuiltInTypes.Is(AnalyzerTypeReferenceFacts.BuiltInSimpleType("void"), BuiltInTypes.Void)
}

test "generic head arity distinguishes 'not generic' from 'cannot be checked here'" {
    // Zero: the head is KNOWN and takes no type parameters. The caller reports type arguments on it.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.Int) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.String) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.Void) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.Null) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.Never) == 0

    // Minus one: unresolved external TEXT. Arity is unknowable locally, so nothing is reported.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ExternalTypeInfo("Stranger")) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ExternalTypeInfo("A.B.Stranger")) == -1

    // Every other family is also "cannot be checked": these are not type HEADS at all, they are
    // constructed shapes, and a type-argument list on them was never valid syntax to begin with.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.Unknown) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.InferenceHole) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(BuiltInTypes.DeferredExternal) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ArrayTypeInfo(BuiltInTypes.Int)) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new NullableTypeInfo(BuiltInTypes.Int)) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ObliviousTypeInfo(BuiltInTypes.Int)) == -1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ByRefTypeInfo(BuiltInTypes.Int)) == -1

    armTypes := new List<TypeInfo>()
    armTypes.Add(BuiltInTypes.Int)
    armTypes.Add(BuiltInTypes.String)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new AnonymousUnionTypeInfo(armTypes)) == -1

    elements := new List<TupleTypeElementInfo>()
    elements.Add(new TupleTypeElementInfo(null, BuiltInTypes.Int))
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new TupleTypeInfo(elements)) == -1

    // A GenericTypeInfo is an already-CONSTRUCTED generic, not a head, so it is -1 too. This is the
    // arm that makes the resolver check arity on the resolved NAME rather than on its own result.
    genericArguments := new List<TypeInfo>()
    genericArguments.Add(BuiltInTypes.Int)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new GenericTypeInfo("List", genericArguments, null)) == -1
}

test "generic head arity reads the declared type parameters of every source family" {
    noParameters := ReferenceFactsTypeParameters([])
    oneParameter := ReferenceFactsTypeParameters(["T"])
    twoParameters := ReferenceFactsTypeParameters(["K", "V"])

    plainClass := new ClassTypeInfo(
        "Plain", 1, 1, false, null, new TypeReference[](0), noParameters,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    genericClass := new ClassTypeInfo(
        "Box", 1, 1, false, null, new TypeReference[](0), oneParameter,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    pairClass := new ClassTypeInfo(
        "Pair", 1, 1, false, null, new TypeReference[](0), twoParameters,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plainClass) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(genericClass) == 1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(pairClass) == 2

    plainStruct := new StructTypeInfo(
        "Point", 1, 1, new TypeReference[](0), noParameters,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    genericStruct := new StructTypeInfo(
        "Cell", 1, 1, new TypeReference[](0), oneParameter,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plainStruct) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(genericStruct) == 1

    plainRecord := new RecordTypeInfo(
        "Simple", 1, 1, false, new TypeReference[](0), noParameters,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    genericRecord := new RecordTypeInfo(
        "Wrapped", 1, 1, false, new TypeReference[](0), twoParameters,
        new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plainRecord) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(genericRecord) == 2

    plainInterface := new InterfaceTypeInfo(
        "Named", 1, 1, false, new TypeReference[](0), noParameters,
        new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    genericInterface := new InterfaceTypeInfo(
        "Holder", 1, 1, false, new TypeReference[](0), oneParameter,
        new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plainInterface) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(genericInterface) == 1

    // Enums, newtypes and aliases are always arity ZERO, not -1: writing `Color<int>` is a reportable
    // mistake, and the alias arm reports on the ALIAS rather than silently checking its target.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new AliasTypeInfo(new SimpleTypeReference("int", 0, 0))) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new AliasTypeInfo(new GenericTypeReference("List", new List<TypeReference>(), 0, 0))) == 0
}

test "generic head arity reads a union's OPTIONAL type-parameter list, absent meaning zero" {
    unionParameters := new List<TypeParameter>()
    unionParameters.Add(new TypeParameter("T"))

    withParameters := new UnionTypeInfo(new UnionDeclarationInfo(
        "Maybe", unionParameters, new List<UnionCase>(), 1, 1))
    withoutParameters := new UnionTypeInfo(new UnionDeclarationInfo(
        "Shape", null, new List<UnionCase>(), 1, 1))
    withEmptyParameters := new UnionTypeInfo(new UnionDeclarationInfo(
        "Flat", new List<TypeParameter>(), new List<UnionCase>(), 1, 1))

    assert AnalyzerTypeReferenceFacts.GenericHeadArity(withParameters) == 1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(withoutParameters) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(withEmptyParameters) == 0
}

test "generic head arity treats a reflected type as generic only when it is an open DEFINITION" {
    // An open definition reports its parameter count.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new ReflectionTypeInfo(typeof(List<int>).GetGenericTypeDefinition())) == 1
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new ReflectionTypeInfo(typeof(Dictionary<string, int>).GetGenericTypeDefinition())) == 2

    // A CLOSED generic reports ZERO, not its argument count: it is already constructed, so a further
    // type-argument list on it is the reportable mistake.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ReflectionTypeInfo(typeof(List<int>))) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(
        new ReflectionTypeInfo(typeof(Dictionary<string, int>))) == 0

    // And a non-generic reflected type is zero.
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ReflectionTypeInfo(typeof(int))) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ReflectionTypeInfo(typeof(string))) == 0
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(new ReflectionTypeInfo(typeof(int[]))) == 0
}

test "visible type namespaces put the current one first, then imports in order, deduplicated" {
    // No package or namespace declaration: the GLOBAL namespace is a real candidate and comes first.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(null, ReferenceFactsNamespaces([])))
        == "<global>"
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            null, ReferenceFactsNamespaces(["System", "System.Text"])))
        == "<global>,System,System.Text"

    // A declared namespace comes first, then the imports in declaration order.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces("Alpha", ReferenceFactsNamespaces([])))
        == "Alpha"
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            "Alpha", ReferenceFactsNamespaces(["System", "System.Text", "System.IO"])))
        == "Alpha,System,System.Text,System.IO"

    // The current namespace is not repeated when it is also imported, wherever the import sits.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            "Alpha", ReferenceFactsNamespaces(["Alpha", "System"])))
        == "Alpha,System"
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            "Alpha", ReferenceFactsNamespaces(["System", "Alpha"])))
        == "Alpha,System"

    // Duplicate imports collapse to their FIRST occurrence, which is what keeps the candidate order
    // stable when the same namespace is imported twice.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            "Alpha", ReferenceFactsNamespaces(["System", "System", "System.Text", "System"])))
        == "Alpha,System,System.Text"

    // Deduplication is case-SENSITIVE: namespaces that differ only in case are different candidates.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            "Alpha", ReferenceFactsNamespaces(["alpha", "ALPHA", "Alpha"])))
        == "Alpha,alpha,ALPHA"

    // The global namespace never suppresses an import, and an empty import name is a real (if
    // useless) candidate rather than being silently dropped.
    assert ReferenceFactsNamespaceText(
        AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(
            null, ReferenceFactsNamespaces(["", "System"])))
        == "<global>,,System"
}

// ---- the built-in spelling set, and the three answers it reconciles --------------------------

// The eighteen spellings, and a handful of names that are emphatically not spellings: a CLR name
// (`Int32`), a well-known struct (`DateTime`), a user type, and a near-miss of case.
func BuiltInSpellingNames(): string[] {
    return [
        "bool", "byte", "sbyte", "short", "ushort", "int", "uint", "long", "ulong",
        "nint", "nuint", "char", "float", "double", "decimal", "string", "object", "void"
    ]
}

func NonBuiltInSpellingNames(): string[] {
    return ["Int32", "System.Int32", "Int", "String", "DateTime", "Guid", "TimeSpan", "never", "null", "Customer", ""]
}

// The membership itself, both directions.
test "analyzer type reference facts own the eighteen built-in spellings" {
    spellings := BuiltInSpellingNames()
    assert spellings.Length == 18

    index := 0
    while index < spellings.Length {
        assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName(spellings[index])
        index = index + 1
    }

    others := NonBuiltInSpellingNames()
    index = 0
    while index < others.Length {
        assert !AnalyzerTypeReferenceFacts.IsBuiltInTypeName(others[index])
        index = index + 1
    }
}

// THE TWO HALVES OF THE OWNER ANSWER THE SAME MEMBERSHIP. A spelling that resolves to a CLR name
// must be a spelling, and one that does not must not be.
test "analyzer type reference facts resolve exactly the spellings they admit" {
    spellings := BuiltInSpellingNames()
    index := 0
    while index < spellings.Length {
        name := spellings[index]
        assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName(name) == (AnalyzerTypeReferenceFacts.BuiltInClrTypeName(name) != null)
        index = index + 1
    }

    others := NonBuiltInSpellingNames()
    index = 0
    while index < others.Length {
        name := others[index]
        assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName(name) == (AnalyzerTypeReferenceFacts.BuiltInClrTypeName(name) != null)
        index = index + 1
    }
}

test "analyzer type reference facts name the CLR type each spelling denotes" {
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("int") == "System.Int32"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("uint") == "System.UInt32"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("long") == "System.Int64"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("ulong") == "System.UInt64"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("short") == "System.Int16"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("ushort") == "System.UInt16"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("byte") == "System.Byte"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("sbyte") == "System.SByte"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("bool") == "System.Boolean"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("char") == "System.Char"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("float") == "System.Single"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("double") == "System.Double"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("decimal") == "System.Decimal"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("string") == "System.String"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("object") == "System.Object"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("void") == "System.Void"

    // The two the analyzer cannot resolve to a `TypeInfo` still have a CLR name, and it is the one
    // the columnar binder already binds them to.
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("nint") == "System.IntPtr"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("nuint") == "System.UIntPtr"
}

// THE ANALYZER'S GAP, PINNED TO EXACTLY TWO NAMES. Every spelling the owner admits must either
// resolve through `BuiltInSimpleType` or be one of `nint`/`nuint`. When `BuiltInTypes` grows a
// member for either, this assertion fails and the owner's comment is corrected rather than quietly
// outliving the gap it describes.
test "analyzer type reference facts pin the nint gap to exactly two spellings" {
    spellings := BuiltInSpellingNames()
    unresolved := 0

    index := 0
    while index < spellings.Length {
        name := spellings[index]
        if AnalyzerTypeReferenceFacts.BuiltInSimpleType(name) == null {
            unresolved = unresolved + 1
            assert name == "nint" || name == "nuint"
        }

        index = index + 1
    }

    assert unresolved == 2
}

// THE COLUMNAR BINDER'S GAP, PINNED TO EXACTLY ONE NAME. Every spelling the owner admits must bind
// to a runtime type except `void`, which is not a type a local can hold.
test "analyzer type reference facts pin the columnar void gap to exactly one spelling" {
    spellings := BuiltInSpellingNames()
    unbound := 0

    index := 0
    while index < spellings.Length {
        name := spellings[index]
        bound := typeof(object)
        if !ColumnarBindingScopeFacts.TryResolveExplicitBuiltin(name, out bound) {
            unbound = unbound + 1
            assert name == "void"
        }

        index = index + 1
    }

    assert unbound == 1
}

// THE VALUE-TYPE PREDICATES ARE A DIFFERENT QUESTION, AND THIS IS THE PROOF THE EDITOR MUST NOT BE
// ROUTED TO THEM. `string` and `object` are built-in spellings and are NOT primitive value types;
// routing a "colour this as a built-in type" question to a "may this live on the stack" answer
// would silently stop colouring both.
test "analyzer type reference facts stay distinct from the primitive value type predicates" {
    assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName("string")
    assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName("object")
    assert !AnalyzerResourceStatements.IsPrimitiveValueTypeName("string")
    assert !AnalyzerResourceStatements.IsPrimitiveValueTypeName("object")

    // And the other way: the value-type predicate admits nothing the spelling set refuses, so the
    // spelling set is the wider of the two over the names they share.
    assert AnalyzerResourceStatements.IsPrimitiveValueTypeName("int")
    assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName("int")
}

// THE NUMERIC LIMIT OWNER AGREES ON EVERY SPELLING IT KNOWS. `PrimitiveLimitTypeName` answers a
// narrower question — which type owns `MinValue`/`MaxValue` — over eight of the eighteen spellings,
// and it must never name a different CLR type than the spelling owner does.
test "analyzer type reference facts agree with the numeric limit owner" {
    numerics := ["int", "uint", "long", "ulong", "short", "ushort", "byte", "sbyte"]

    index := 0
    while index < numerics.Length {
        name := numerics[index]
        assert ColumnarExternalBindingPlans.PrimitiveLimitTypeName(name) == AnalyzerTypeReferenceFacts.BuiltInClrTypeName(name)
        index = index + 1
    }

    // And it deliberately declines the ten it does not own, rather than guessing.
    assert ColumnarExternalBindingPlans.PrimitiveLimitTypeName("string") == ""
    assert ColumnarExternalBindingPlans.PrimitiveLimitTypeName("bool") == ""
    assert ColumnarExternalBindingPlans.PrimitiveLimitTypeName("nint") == ""
}
