namespace NSharpLang.Compiler

// THE STORAGE RULE AS A TABLE (`MemberStorageRules`, website/docs/types.md "Fields and properties").
// Every row is one bare `Name: T` member: where it is declared, how it is spelled, and whether it is a
// get/set auto-property. The `Modifiers` bits are the declaration's own word: Public 1, Private 2,
// Internal 4, Protected 8, Static 16, Readonly 512, Const 1024, Init 16384.
func StorageRuleRow(inReferenceType: bool, name: string, modifiers: int, expected: bool): string {
    if MemberStorageRules.IsAutoPropertyDeclaration(inReferenceType, name, modifiers) == expected {
        return ""
    }

    return name + "/" + modifiers.ToString() + (inReferenceType ? " in a class" : " in a struct") + " should be " + (expected ? "a property" : "a field") + "; "
}

test "the storage rule makes exported instance members of a class or record properties, and nothing else" {
    misses := ""
    misses = misses + StorageRuleRow(true, "Name", 0, true)
    misses = misses + StorageRuleRow(true, "name", 0, false)
    misses = misses + StorageRuleRow(true, "Name", 2, false)
    misses = misses + StorageRuleRow(true, "name", 1, true)
    misses = misses + StorageRuleRow(true, "Seed", 8, true)
    misses = misses + StorageRuleRow(true, "seed", 4, true)
    misses = misses + StorageRuleRow(true, "Seed", 10, true)
    misses = misses + StorageRuleRow(true, "Count", 16, false)
    misses = misses + StorageRuleRow(true, "Stamp", 512, false)
    misses = misses + StorageRuleRow(true, "Max", 1024, false)
    misses = misses + StorageRuleRow(false, "X", 0, false)
    misses = misses + StorageRuleRow(false, "X", 1, false)
    misses = misses + StorageRuleRow(true, "Id", 16384, true)
    misses = misses + StorageRuleRow(false, "Id", 16384, true)
    misses = misses + StorageRuleRow(true, "id", 16384, true)
    misses = misses + StorageRuleRow(true, "Id", 16400, false)
    assert misses == "", misses
}

test "an event is never an auto-property, however it is spelled" {
    assert !MemberStorageRules.IsAutoPropertyMember(true, "Changed", 0, false, false, false, true, false)
}
