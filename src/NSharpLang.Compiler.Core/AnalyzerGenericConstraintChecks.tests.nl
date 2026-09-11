namespace NSharpLang.Compiler


// THE CONSTRAINT PREDICATES AND SENTENCES, CROSSED WITHOUT AN ANALYZER.
//
// These lived inside `AnalyzerSyntheticCallValidator`, reachable only from a `CallExpression`, which
// is precisely why `new Box<string>()` under `class Box<T> where T : struct` was accepted in silence
// for as long as generic types have existed: NL208 could not be asked at a type-argument site
// because the question itself was locked inside the call validator. Lifting it here is what let the
// two reporters share one answer, and it is what makes the answer assertable at all.
func GcStruct(name: string): TypeInfo {
    return new StructTypeInfo(name, 1, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

func GcClass(name: string, hasParameterlessConstructor: bool): TypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), hasParameterlessConstructor)
}

// ── The special constraints ─────────────────────────────────────────────────────────────────────
test "the `class` constraint refuses a value type and admits a reference type" {
    classOnly := Convert.ToInt32(SpecialConstraintKind.Class)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(classOnly, BuiltInTypes.Int) == AnalyzerGenericConstraintChecks.ViolationClass()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(classOnly, BuiltInTypes.String) == AnalyzerGenericConstraintChecks.ViolationNone()
}

test "the `struct` constraint refuses a reference type AND a nullable value type" {
    structOnly := Convert.ToInt32(SpecialConstraintKind.Struct)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(structOnly, BuiltInTypes.String) == AnalyzerGenericConstraintChecks.ViolationStruct()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(structOnly, BuiltInTypes.Int) == AnalyzerGenericConstraintChecks.ViolationNone()

    // `int?` is a value type and still fails: the constraint is NON-NULLABLE value type, which is the
    // row that separates this predicate from a plain `IsReferenceType` test.
    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(structOnly, nullableInt) == AnalyzerGenericConstraintChecks.ViolationStruct()
}

test "the `new()` constraint reads the declared type, and every value type satisfies it implicitly" {
    newOnly := Convert.ToInt32(SpecialConstraintKind.New)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(newOnly, GcStruct("Point")) == AnalyzerGenericConstraintChecks.ViolationNone()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(newOnly, GcClass("Made", true)) == AnalyzerGenericConstraintChecks.ViolationNone()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(newOnly, GcClass("Unmade", false)) == AnalyzerGenericConstraintChecks.ViolationNew()
}

test "AT MOST ONE special violation is reported per parameter, in CLR order" {
    // `where T : class, new()` against a value type fails BOTH — it is not a reference type and, being
    // reported once, the `class` failure is the one named. Reporting both would bury the cause.
    both := Convert.ToInt32(SpecialConstraintKind.Class) | Convert.ToInt32(SpecialConstraintKind.New)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(both, GcClass("Unmade", false)) == AnalyzerGenericConstraintChecks.ViolationNew()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(both, BuiltInTypes.Int) == AnalyzerGenericConstraintChecks.ViolationClass()
}

test "no constraint at all is always satisfied" {
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(0, BuiltInTypes.Int) == AnalyzerGenericConstraintChecks.ViolationNone()
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(0, BuiltInTypes.String) == AnalyzerGenericConstraintChecks.ViolationNone()
}

test "an UNKNOWN type satisfies `new()`, because a constraint report on an unresolved type is noise" {
    newOnly := Convert.ToInt32(SpecialConstraintKind.New)
    assert AnalyzerGenericConstraintChecks.SpecialViolationKind(newOnly, BuiltInTypes.Unknown) == AnalyzerGenericConstraintChecks.ViolationNone()
    assert AnalyzerGenericConstraintChecks.HasParameterlessConstructor(BuiltInTypes.Unknown)
}

// ── The sentences ───────────────────────────────────────────────────────────────────────────────
test "the MESSAGE is identical for both reporters, and names the owner it was written on" {
    // THE POINT OF SHARING: a violation is the same fact whoever wrote it, so a call site and a
    // type-argument site must state it in the same words with only the owner's name differing.
    call := AnalyzerGenericConstraintChecks.SpecialViolationMessage(AnalyzerGenericConstraintChecks.ViolationStruct(), "string", "T", "Echo")
    typeArgument := AnalyzerGenericConstraintChecks.SpecialViolationMessage(AnalyzerGenericConstraintChecks.ViolationStruct(), "string", "T", "Box")
    assert call == "`string` is not a non-nullable value type, but type parameter `T` of `Echo` requires one (the `struct` constraint)", call
    assert typeArgument == "`string` is not a non-nullable value type, but type parameter `T` of `Box` requires one (the `struct` constraint)", typeArgument

    assert AnalyzerGenericConstraintChecks.TypeConstraintMessage("int", "Marker", "T", "Bounded") == "`int` does not implement `Marker`, which type parameter `T` of `Bounded` requires"
}

test "the SUGGESTIONS differ, because a type argument is written rather than passed" {
    // The one place the two reporters are allowed to diverge. Telling someone to "pass" a type they
    // wrote in a field declaration would be a small lie, so the type-argument wording says "use".
    kind := AnalyzerGenericConstraintChecks.ViolationClass()
    assert AnalyzerGenericConstraintChecks.CallSuggestion(kind, "int", "T", "Echo").StartsWith("Pass a class instance")
    assert AnalyzerGenericConstraintChecks.TypeArgumentSuggestion(kind, "int", "T", "Box").StartsWith("Use a reference type")

    // The `new()` suggestion is about the BOUND type, not the site, so it is the same either way.
    newKind := AnalyzerGenericConstraintChecks.ViolationNew()
    assert AnalyzerGenericConstraintChecks.CallSuggestion(newKind, "Unmade", "T", "Echo") == AnalyzerGenericConstraintChecks.TypeArgumentSuggestion(newKind, "Unmade", "T", "Echo")
}
