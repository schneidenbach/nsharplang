namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Reflection

test "a private source record struct is a value-equality Dictionary key including a null component" {
    siteType := typeof(SourceRecordDictionaryKeyEmitFacts).GetNestedType(
        "Site",
        BindingFlags.NonPublic
    )
    if siteType == null {
        throw new InvalidOperationException("The private Site record struct was not emitted.")
    }
    assert siteType.get_IsNestedPrivate()
    assert siteType.get_IsValueType()

    fieldFlags := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic
    nameField := siteType.GetField("Name", fieldFlags)
    containingTypeField := siteType.GetField("ContainingType", fieldFlags)
    lineField := siteType.GetField("Line", fieldFlags)
    columnField := siteType.GetField("Column", fieldFlags)
    parameterCountField := siteType.GetField("ParameterCount", fieldFlags)
    if nameField == null || containingTypeField == null || lineField == null || columnField == null || parameterCountField == null {
        throw new InvalidOperationException("The complete immutable Site component set was not emitted.")
    }
    assert nameField.get_IsInitOnly()
    assert containingTypeField.get_IsInitOnly()
    assert lineField.get_IsInitOnly()
    assert columnField.get_IsInitOnly()
    assert parameterCountField.get_IsInitOnly()

    values := new SourceRecordDictionaryKeyEmitFacts()

    values.Put("alpha", "Owner", 7, 9, 2, "first")
    assert values.Count() == 1
    assert values.TryRead("alpha", "Owner", 7, 9, 2) == "first"
    assert values.Read("alpha", "Owner", 7, 9, 2) == "first"
    assert values.TryRead("beta", "Owner", 7, 9, 2) == "missing"
    assert values.TryRead("alpha", "Other", 7, 9, 2) == "missing"
    assert values.TryRead("alpha", "Owner", 8, 9, 2) == "missing"
    assert values.TryRead("alpha", "Owner", 7, 10, 2) == "missing"
    assert values.TryRead("alpha", "Owner", 7, 9, 3) == "missing"

    values.Put("alpha", "Owner", 7, 9, 2, "replacement")
    assert values.Count() == 1
    assert values.TryRead("alpha", "Owner", 7, 9, 2) == "replacement"

    values.Put("nullable", null, 11, 13, 4, "null-containing-type")
    assert values.Count() == 2
    assert values.Contains("nullable", null, 11, 13, 4)
    assert values.TryRead("nullable", null, 11, 13, 4) == "null-containing-type"
    assert values.Read("nullable", null, 11, 13, 4) == "null-containing-type"
    assert values.TryRead("nullable", "", 11, 13, 4) == "missing"

    assert values.ReadUnits() == "first=one|second=two"

    values.Clear()
    assert values.Count() == 0
    assert !values.Contains("alpha", "Owner", 7, 9, 2)
    assert !values.Contains("nullable", null, 11, 13, 4)
}
