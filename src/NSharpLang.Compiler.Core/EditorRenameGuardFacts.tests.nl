namespace NSharpLang.Compiler.CodeIntelligence

// CONTRACTS FOR WHAT MAY BE RENAMED. These came out of `PrepareRenameHandler.cs`, `RenameHandler.cs`
// and `ReferencesHandler.cs`, where the two tables sat in one handler and the sentences were
// duplicated across the other two.
test "the rename guard refuses the language's own words" {
    assert EditorRenameGuardFacts.IsKeyword("func")
    assert EditorRenameGuardFacts.IsKeyword("class")
    assert EditorRenameGuardFacts.IsKeyword("match")
    assert EditorRenameGuardFacts.IsKeyword("print")
    assert EditorRenameGuardFacts.IsKeyword("assert")
    assert EditorRenameGuardFacts.IsKeyword("explicit")
    assert EditorRenameGuardFacts.IsKeyword("duck")
    assert EditorRenameGuardFacts.IsKeyword("file")
    // `in` IS one, and was missing from this guard while it was only the `for x in xs` keyword: it is
    // now also the read-only by-reference parameter modifier, and a rename to a reserved word cannot be
    // applied either way.
    assert EditorRenameGuardFacts.IsKeyword("in")

    assert !EditorRenameGuardFacts.IsKeyword("Func")
    assert !EditorRenameGuardFacts.IsKeyword("myFunc")
    assert !EditorRenameGuardFacts.IsKeyword("")
}

// THE C# SPELLINGS ARE IN THE TABLE TOO. A reader typing out of C# habit still gets a refusal
// rather than a rename dialog that would produce a syntax error.
test "the rename guard refuses the spellings inherited from C#" {
    assert EditorRenameGuardFacts.IsKeyword("using")
    assert EditorRenameGuardFacts.IsKeyword("foreach")
    assert EditorRenameGuardFacts.IsKeyword("switch")
    assert EditorRenameGuardFacts.IsKeyword("this")
    assert EditorRenameGuardFacts.IsKeyword("base")
}

test "the rename guard refuses a primitive type name" {
    assert EditorRenameGuardFacts.IsPrimitiveTypeName("int")
    assert EditorRenameGuardFacts.IsPrimitiveTypeName("string")
    assert EditorRenameGuardFacts.IsPrimitiveTypeName("sbyte")
    assert EditorRenameGuardFacts.IsPrimitiveTypeName("void")

    assert !EditorRenameGuardFacts.IsPrimitiveTypeName("Int32")
    assert !EditorRenameGuardFacts.IsPrimitiveTypeName("integer")
    assert !EditorRenameGuardFacts.IsPrimitiveTypeName("")
}

// A TYPE NAME IS NOT A KEYWORD AND THE TWO TABLES STAY APART, because the handler logs a
// different sentence for each and a reader deserves to know which refusal they hit.
test "the rename guard keeps its two tables apart" {
    assert !EditorRenameGuardFacts.IsKeyword("int")
    assert !EditorRenameGuardFacts.IsPrimitiveTypeName("func")
}

test "the rename guard says what was refused and that nothing was edited" {
    unresolved := EditorRenameGuardFacts.RenameUnresolvedMessage("Add")
    assert unresolved == "Rename for 'Add' is unavailable because semantic resolution could not safely identify the selected symbol. No edits were applied; refusing fallback rename to avoid editing unrelated symbols."

    textOnly := EditorRenameGuardFacts.RenameTextOnlyMessage("Add")
    assert textOnly == "Rename for 'Add' is unavailable because semantic resolution could not safely identify the selected symbol. No edits were applied; refusing text-only rename to avoid editing unrelated symbols."

    degraded := EditorRenameGuardFacts.RenameDegradedMessage("Add")
    assert degraded == "Rename for 'Add' is unavailable because semantic project analysis is degraded. Save or fix the project files and retry; refusing text-only rename to avoid editing unrelated symbols."

    references := EditorRenameGuardFacts.ReferencesDegradedMessage("Add")
    assert references == "References for 'Add' are unavailable because semantic project analysis is degraded. Save or fix the project files and retry; refusing text-only references to avoid showing unrelated symbols."
}

// THE TWO UNRESOLVED SENTENCES DIFFER BY ONE WORD, and the difference is which side of the guard
// refused: a project that could not resolve the caret, or no project to resolve it with.
test "the two unresolved refusals differ only in how the rename would have degraded" {
    assert EditorRenameGuardFacts.RenameUnresolvedMessage("X") != EditorRenameGuardFacts.RenameTextOnlyMessage("X")
    assert EditorRenameGuardFacts.RenameUnresolvedMessage("X").Contains("fallback rename")
    assert EditorRenameGuardFacts.RenameTextOnlyMessage("X").Contains("text-only rename")
}
