namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection


// These contracts cover immutable identity rows only. The selecting table remains deliberately
// mutable catalog state and is used here solely to obtain real selected references.
func StructuralImmutabilityDeclaredInstanceFields(owner: Type): FieldInfo[] {
    flags := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    return owner.GetFields(flags)
}

func StructuralImmutabilityRequiredField(owner: Type, name: string): FieldInfo {
    fields := StructuralImmutabilityDeclaredInstanceFields(owner)
    i := 0
    while i < fields.Length {
        field := fields[i]
        if field.get_Name() == name {
            return field
        }
        i += 1
    }
    throw new InvalidOperationException(
        "Expected immutable identity field '" + owner.get_Name() + "." + name + "'."
    )
}

func StructuralImmutabilityAssertDeclaredFieldsInitOnly(owner: Type): bool {
    fields := StructuralImmutabilityDeclaredInstanceFields(owner)
    assert fields.Length > 0
    i := 0
    while i < fields.Length {
        field := fields[i]
        assert !field.get_IsStatic()
        assert field.get_IsInitOnly()
        i += 1
    }
    return true
}

func StructuralImmutabilityRequiredKey(
    selected: ColumnarSelectedTypeReference,
    description: string
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(description + " did not select a structural key.")
    }
    return key
}

func StructuralImmutabilityRequiredIList(
    instance: object,
    fieldName: string
): IList {
    field := StructuralImmutabilityRequiredField(instance.GetType(), fieldName)
    value := field.GetValue(instance)
    list := value as IList
    if list == null {
        throw new InvalidOperationException(
            "Expected '" + instance.GetType().get_Name() + "." + fieldName + "' to expose IList storage."
        )
    }
    return list
}

func StructuralImmutabilityRejectsIListItemMutation(
    values: IList,
    index: int,
    value: object
): bool {
    setter := typeof(IList).GetMethod("set_Item")
    if setter == null {
        throw new InvalidOperationException("IList.set_Item was not found.")
    }
    arguments := new object[](2)
    ExecutorSetObject(arguments, 0, index)
    ExecutorSetObject(arguments, 1, value)
    rejected := false
    try {
        setter.Invoke(values, arguments)
    } catch ex: Exception {
        innerBox: object? = ex.get_InnerException()
        rejected = innerBox != null && innerBox.GetType() == typeof(NotSupportedException)
    }
    return rejected
}

func StructuralImmutabilityRequiredAssemblyIdentity(runtimeType: Type): string {
    identity := runtimeType.get_Assembly().GetName().get_FullName()
    if identity == null {
        throw new InvalidOperationException("Expected a runtime assembly identity.")
    }
    return identity
}

test "structural identity rows compile to initonly fields while retaining selected scalar facts" {
    owner := ColumnarStructuralGenericOwnerIdentity.SourceType(
        73,
        "Models.ImmutableOwner"
    )
    parameter := new ColumnarStructuralGenericParameterIdentity(owner, 2)
    table := new ColumnarStructuralTypeReferenceTable()
    selected := table.SelectRuntimeType(typeof(int))
    entry := new ColumnarStructuralTypePoolEntry(table, selected)
    key := StructuralImmutabilityRequiredKey(selected, "int")

    assert owner.Kind == ColumnarStructuralGenericOwnerKind.SourceType
    assert owner.SourceFileId == 73
    assert owner.DeclaringTypeName == "Models.ImmutableOwner"
    assert owner.MemberOrdinal == -1
    assert Object.ReferenceEquals(parameter.Owner, owner)
    assert parameter.ParameterOrdinal == 2
    assert selected.HasRuntimeType
    assert selected.RuntimeType == typeof(int)
    assert Object.ReferenceEquals(selected.EmissionIdentity, table.Identity)
    assert key.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.PrimitiveName == "int32"
    assert Object.ReferenceEquals(entry.Table, table)
    assert Object.ReferenceEquals(entry.Selected, selected)
    assert entry.MatchesRuntime(typeof(int))

    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarStructuralGenericOwnerIdentity)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarStructuralGenericParameterIdentity)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarStructuralTypeKey)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarSelectedTypeReference)
    )
    assert StructuralImmutabilityAssertDeclaredFieldsInitOnly(
        typeof(ColumnarStructuralTypePoolEntry)
    )
}

test "structural keys snapshot caller nested-name arrays before exposing immutable storage" {
    table := new ColumnarStructuralTypeReferenceTable()
    dateTimeType := typeof(DateTime)
    inputNames := new string[](1)
    inputNames[0] = "DateTime"
    key := new ColumnarStructuralTypeKey(
        ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition,
        null,
        "",
        "",
        StructuralImmutabilityRequiredAssemblyIdentity(dateTimeType),
        "System",
        inputNames,
        true,
        ColumnarStructuralGenericOwnerKind.SourceType,
        -1,
        "",
        -1,
        -1,
        new ColumnarStructuralTypeKey[](0)
    )
    selected := new ColumnarSelectedTypeReference(
        table.Identity,
        key,
        dateTimeType,
        true,
        null,
        ""
    )

    inputNames[0] = "ChangedAfterSelection"
    assert selected.Key != null
    assert selected.Key.NestedNameCount == 1
    assert selected.Key.NestedName(0) == "DateTime"
    assert table.ValidatePair(selected, dateTimeType)

    names := StructuralImmutabilityRequiredIList(key, "nestedNamesValue")
    assert names.Count == 1
    assert StructuralImmutabilityRejectsIListItemMutation(
        names,
        0,
        "MutatedThroughIList"
    )
    assert selected.Key.NestedName(0) == "DateTime"
}

test "table selected generic keys snapshot argument arrays and reject IList child mutation" {
    table := new ColumnarStructuralTypeReferenceTable()
    listType := typeof(List<int>)
    definitionType := listType.GetGenericTypeDefinition()
    definition := table.SelectRuntimeType(definitionType)
    intArgument := table.SelectRuntimeType(typeof(int))
    stringArgument := table.SelectRuntimeType(typeof(string))
    arguments := new ColumnarSelectedTypeReference[](1)
    arguments[0] = intArgument
    selected := table.SelectConstructedGeneric(listType, definition, arguments)
    key := StructuralImmutabilityRequiredKey(selected, "List<int>")

    arguments[0] = stringArgument
    assert key.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert key.ChildCount == 2
    assert key.Child(0).Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert key.Child(1).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.Child(1).PrimitiveName == "int32"
    assert table.ValidatePair(selected, listType)

    children := StructuralImmutabilityRequiredIList(key, "childrenValue")
    replacement := StructuralImmutabilityRequiredKey(stringArgument, "string")
    assert children.Count == 2
    assert StructuralImmutabilityRejectsIListItemMutation(
        children,
        1,
        replacement
    )
    assert key.Child(1).PrimitiveName == "int32"
    assert table.ValidatePair(selected, listType)
}
