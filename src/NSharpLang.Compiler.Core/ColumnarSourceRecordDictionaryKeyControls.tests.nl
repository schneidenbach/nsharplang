namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func SourceRecordDictionaryKeyRecord(name: string): ColumnarStructDef {
    definition := SourceCallDefinition(name, false)
    definition.IsRecord = true
    return definition
}

func SourceRecordDictionaryKeyDefinitions(
    first: ColumnarStructDef,
    second: ColumnarStructDef
): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](2)
    definitions[0] = first
    definitions[1] = second
    return definitions
}

func SourceRecordDictionaryKeyAssertClosed(
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

test "Dictionary key admission requires the exact registered source record struct fact" {
    recordDefinition := SourceRecordDictionaryKeyRecord(
        "RecordDictionaryControls.Outer.Site"
    )
    ordinary := SourceCallDefinition(
        "RecordDictionaryControls.Outer.Plain",
        false
    )
    unregistered := SourceRecordDictionaryKeyRecord(
        "RecordDictionaryControls.Outer.Unregistered"
    )
    generic := SourceCallGenericDefinition(
        "RecordDictionaryControls.GenericSite"
    )
    generic.IsRecord = true
    generic.IsReference = false

    definitions := SourceRecordDictionaryKeyDefinitions(recordDefinition, ordinary)
    recordType: Type = recordDefinition.Builder
    ordinaryType: Type = ordinary.Builder
    unregisteredType: Type = unregistered.Builder
    genericDefinition: Type = generic.Builder
    genericArguments := new Type[](1)
    genericArguments[0] = typeof(int)
    constructedGeneric := genericDefinition.MakeGenericType(genericArguments)

    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(recordType)
    assert ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        recordType,
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        ordinaryType,
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        unregisteredType,
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        genericDefinition,
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        constructedGeneric,
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        recordType.MakeArrayType(),
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        recordType.MakeByRefType(),
        definitions
    )
    assert !ColumnarTypeOfPlanner.IsAdmissibleDictionaryKeyInCompilation(
        recordType.MakePointerType(),
        definitions
    )
}

test "canonical and fragment resolution carry the live record declaration into Dictionary only" {
    recordDefinition := SourceRecordDictionaryKeyRecord(
        "RecordDictionaryControls.Outer.Site"
    )
    ordinary := SourceCallDefinition(
        "RecordDictionaryControls.Outer.Plain",
        false
    )
    definitions := SourceRecordDictionaryKeyDefinitions(recordDefinition, ordinary)
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
    resolved := typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "Dictionary<Site,string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    SourceRecordDictionaryKeyAssertClosed(
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
    SourceRecordDictionaryKeyAssertClosed(
        resolved,
        readOnlyDictionaryDefinition,
        recordType,
        typeof(string)
    )

    resolved = typeof(object)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "Dictionary<Plain,string>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    assert resolved == null

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    bindings.StructuralTypeReferences.RegisterSourceDefinition(
        recordDefinition.DeclaredTypeName,
        recordType,
        false
    )
    bindings.StructuralTypeReferences.RegisterSourceDefinition(
        ordinary.DeclaredTypeName,
        ordinary.Builder,
        false
    )
    recordTree := TypeOfGenericTree(
        "Dictionary",
        recordDefinition.DeclaredTypeName,
        "string"
    )
    recordPlan := TypeOfPlan(recordTree, bindings)
    SourceRecordDictionaryKeyAssertClosed(
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
    ordinaryPlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        ordinaryTree.Nodes,
        ordinaryTree.Source,
        ordinaryTree.Root,
        bindings,
        ordinaryPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    assert ordinaryPlan.OperationCount == 0
}
