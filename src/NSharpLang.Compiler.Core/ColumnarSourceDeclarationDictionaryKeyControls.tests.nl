namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func SourceDeclarationDictionaryKeyRecord(name: string): ColumnarStructDef {
    definition := SourceCallDefinition(name, false)
    definition.IsRecord = true
    return definition
}

func SourceDeclarationDictionaryKeyDefinitions(
    first: ColumnarStructDef,
    second: ColumnarStructDef
): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](2)
    definitions[0] = first
    definitions[1] = second
    return definitions
}

func SourceDeclarationDictionaryKeyAssertClosed(
    valueType: Type,
    expectedDefinition: Type,
    expectedKey: Type,
    expectedValue: Type
) {
    assert valueType.get_IsGenericType()
    assert !valueType.get_IsGenericTypeDefinition()
    assert valueType.GetGenericTypeDefinition() == expectedDefinition
    arguments := valueType.GetGenericArguments()
    assert arguments.Length == 2
    assert Object.ReferenceEquals(arguments[0], expectedKey)
    assert Object.ReferenceEquals(arguments[1], expectedValue)
}

// EVERY DIRECT SOURCE DECLARATION IS A KEY, and nothing built out of one is. A record struct, a
// plain struct and a source class all carry well-defined equality and hashing the moment they
// exist, so the key admission asks about the DECLARATION and never about which kind it is — no
// registry lookup, and no record-only exception. An open definition names no single type, and an
// array, a byref, a pointer or a constructed source generic is a shape over a declaration rather
// than the declaration itself.
test "Dictionary key admission takes any direct source declaration and stops at the builder leaf" {
    recordDefinition := SourceDeclarationDictionaryKeyRecord(
        "RecordDictionaryControls.Outer.Site"
    )
    ordinary := SourceCallDefinition(
        "RecordDictionaryControls.Outer.Plain",
        false
    )
    generic := SourceCallGenericDefinition(
        "RecordDictionaryControls.GenericSite"
    )
    generic.IsRecord = true
    generic.IsReference = false

    recordType: Type = recordDefinition.Builder
    ordinaryType: Type = ordinary.Builder
    genericDefinition: Type = generic.Builder
    genericArguments := new Type[](1)
    genericArguments[0] = typeof(int)
    constructedGeneric := genericDefinition.MakeGenericType(genericArguments)

    assert ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(recordType)
    assert ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(ordinaryType)
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(recordType)
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(ordinaryType)
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(genericDefinition)
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(constructedGeneric)
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(recordType.MakeArrayType())
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(recordType.MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(recordType.MakePointerType())
}

test "canonical and fragment resolution carry every live source declaration into Dictionary" {
    recordDefinition := SourceDeclarationDictionaryKeyRecord(
        "RecordDictionaryControls.Outer.Site"
    )
    ordinary := SourceCallDefinition(
        "RecordDictionaryControls.Outer.Plain",
        false
    )
    definitions := SourceDeclarationDictionaryKeyDefinitions(recordDefinition, ordinary)
    structs := SemanticEmptyStructs()
    structs[recordDefinition.DeclaredTypeName] = recordDefinition
    structs[ordinary.DeclaredTypeName] = ordinary

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace RecordDictionaryControls\nclass Outer {\n    private record struct Site {}\n    private struct Plain {}\n}\n"
    fileNames[0] = "record-dictionary-controls/owner.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        "RecordDictionaryControls.Outer"
    )

    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    readOnlyDictionaryDefinition := ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition()
    recordType: Type = recordDefinition.Builder
    ordinaryType: Type = ordinary.Builder
    resolved := typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "Dictionary<Site,string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    SourceDeclarationDictionaryKeyAssertClosed(
        resolved,
        dictionaryDefinition,
        recordType,
        typeof(string)
    )

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "IReadOnlyDictionary<Site,string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    SourceDeclarationDictionaryKeyAssertClosed(
        resolved,
        readOnlyDictionaryDefinition,
        recordType,
        typeof(string)
    )

    // The plain struct resolves exactly as the record struct does: the key surface is the
    // declaration, not the kind of declaration.
    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "Dictionary<Plain,string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    SourceDeclarationDictionaryKeyAssertClosed(
        resolved,
        dictionaryDefinition,
        ordinaryType,
        typeof(string)
    )

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    bindings.StructuralTypeReferences.RegisterSourceDefinition(
        recordDefinition.DeclaredTypeName,
        recordType,
        false
    )
    bindings.StructuralTypeReferences.RegisterSourceDefinition(
        ordinary.DeclaredTypeName,
        ordinaryType,
        false
    )
    recordTree := TypeOfGenericTree(
        "Dictionary",
        recordDefinition.DeclaredTypeName,
        "string"
    )
    recordPlan := TypeOfPlan(recordTree, bindings)
    SourceDeclarationDictionaryKeyAssertClosed(
        recordPlan.Types[0],
        dictionaryDefinition,
        recordType,
        typeof(string)
    )

    ordinaryTree := TypeOfGenericTree(
        "Dictionary",
        ordinary.DeclaredTypeName,
        "string"
    )
    ordinaryPlan := TypeOfPlan(ordinaryTree, bindings)
    SourceDeclarationDictionaryKeyAssertClosed(
        ordinaryPlan.Types[0],
        dictionaryDefinition,
        ordinaryType,
        typeof(string)
    )
}
