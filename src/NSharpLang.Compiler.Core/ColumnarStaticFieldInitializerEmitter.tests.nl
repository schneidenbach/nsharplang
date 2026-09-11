namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// These are executable boundary controls for the static-field initialization owner.  The source
// compilation checks below exercise its fully emitted .cctor; this first group also keeps the
// small parsing and literal decisions independently observable when a later source declaration
// fails before a type can be baked.
func StaticInitializerLiteralValue(
    fieldType: Type,
    initializerKind: int,
    text: string
): string {
    method := BoundDynamicMethod(
        "StaticInitializerLiteralValue",
        fieldType,
        new Type[](0)
    )
    il := method.GetILGenerator()
    if !ColumnarStaticFieldInitializerEmitter.TryEmitStaticFieldLiteralInitializerLoad(
        il,
        fieldType,
        initializerKind,
        text
    ) {
        throw new InvalidOperationException("The static-initializer literal control unexpectedly declined.")
    }
    il.Emit(OpCodes.Ret)
    return BoundInvokeText(method, new object[](0))
}

func StaticInitializerLiteralDeclines(
    fieldType: Type,
    initializerKind: int,
    text: string
): bool {
    method := BoundDynamicMethod(
        "StaticInitializerLiteralDeclines",
        fieldType,
        new Type[](0)
    )
    return !ColumnarStaticFieldInitializerEmitter.TryEmitStaticFieldLiteralInitializerLoad(
        method.GetILGenerator(),
        fieldType,
        initializerKind,
        text
    )
}

func StaticInitializerHasTypeInitializer(valueType: Type): bool {
    property := typeof(Type).GetProperty("TypeInitializer")
    if property == null {
        throw new InvalidOperationException("Type.TypeInitializer was not found.")
    }
    return property.GetValue(valueType) != null
}

// The pinned compiler cannot spell Array.Empty<string>() directly at this source level.  Reflection
// still reaches the BCL singleton, which lets the control state identity rather than merely length.
func StaticInitializerBclEmptyStringArray(): object {
    emptyDefinition := typeof(Array).GetMethod("Empty")
    if emptyDefinition == null || !emptyDefinition.get_IsGenericMethodDefinition() {
        throw new InvalidOperationException("System.Array.Empty<T>() was not found.")
    }
    typeArguments := new Type[](1)
    typeArguments[0] = typeof(string)
    closedEmpty := emptyDefinition.MakeGenericMethod(typeArguments)
    value := TypeOfRequiredInvocation(closedEmpty, null, new object[](0))
    if value == null {
        throw new InvalidOperationException("System.Array.Empty<string>() returned null.")
    }
    return value
}

func StaticInitializerBake(owner: ColumnarStructDef): Type {
    return IdentityBake(owner.Builder)
}

func StaticInitializerStaticFieldValue(owner: Type, name: string): object {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("The static-initializer field was not found: " + name)
    }
    value := field.GetValue(null)
    if value == null {
        throw new InvalidOperationException("The static-initializer field unexpectedly read null: " + name)
    }
    return value
}

func StaticInitializerIntMethod(
    owner: ColumnarStructDef,
    name: string,
    value: int
): ColumnarStaticMethodDef {
    definition := SourceCallPublicStatic(owner, name, new Type[](0), typeof(int))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldc_I4, value)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerIntParameterMethod(
    owner: ColumnarStructDef,
    name: string,
    value: int
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    definition := SourceCallPublicStatic(owner, name, parameterTypes, typeof(int))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldc_I4, value)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerStringParameterIntMethod(
    owner: ColumnarStructDef,
    name: string,
    value: int
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    definition := SourceCallPublicStatic(owner, name, parameterTypes, typeof(int))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldc_I4, value)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerIntParameterStringMethod(
    owner: ColumnarStructDef,
    name: string
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    definition := SourceCallPublicStatic(owner, name, parameterTypes, typeof(string))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldstr, "unselected")
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerStringEchoMethod(
    owner: ColumnarStructDef,
    name: string
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    definition := SourceCallPublicStatic(owner, name, parameterTypes, typeof(string))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerModifiedStringEchoMethod(
    owner: ColumnarStructDef,
    name: string,
    modifierKind: int
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    modifierKinds := new int[](1)
    modifierKinds[0] = modifierKind
    definition := SourceCallDefineStatic(owner, name, parameterTypes, modifierKinds, typeof(string), (MethodAttributes)22)
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerPrefixStringMethod(
    owner: ColumnarStructDef,
    name: string,
    prefix: FieldBuilder
): ColumnarStaticMethodDef {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    definition := SourceCallPublicStatic(owner, name, parameterTypes, typeof(string))
    il := TypeOfMethodBuilderIL(definition.Builder)
    concatTypes := new Type[](2)
    concatTypes[0] = typeof(string)
    concatTypes[1] = typeof(string)
    concat := ExecutorRequiredMethod(typeof(string), "Concat", concatTypes)
    il.Emit(OpCodes.Ldsfld, prefix)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Call, concat)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerStringMethod(
    owner: ColumnarStructDef,
    name: string,
    value: string
): ColumnarStaticMethodDef {
    definition := SourceCallPublicStatic(owner, name, new Type[](0), typeof(string))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldstr, value)
    il.Emit(OpCodes.Ret)
    return definition
}

func StaticInitializerReadIntFieldMethod(
    owner: ColumnarStructDef,
    name: string,
    field: FieldBuilder
): ColumnarStaticMethodDef {
    definition := SourceCallPublicStatic(owner, name, new Type[](0), typeof(int))
    il := TypeOfMethodBuilderIL(definition.Builder)
    il.Emit(OpCodes.Ldsfld, field)
    il.Emit(OpCodes.Ret)
    return definition
}

class StaticInitializerSiblingProbe {
    static func SiblingSeed(): int {
        return 23
    }

    static func SiblingEcho(value: string): string {
        return value
    }
}

func StaticInitializerExpressionDeclinesWithoutIl(
    owner: ColumnarStructDef,
    fieldType: Type,
    text: string,
    siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
) {
    method := BoundDynamicMethod(
        "StaticInitializerExpressionDeclinesWithoutIl",
        fieldType,
        new Type[](0)
    )
    il := method.GetILGenerator()
    assert !ColumnarStaticFieldInitializerEmitter.TryEmitStaticFieldExpressionInitializerLoad(
        il,
        owner,
        fieldType,
        text,
        siblings
    )
    assert StructuralPoolRequiredIntProperty(il, "ILOffset") == 0
}

test "static initializer call and generic receiver parsers preserve success names and failure out slots" {
    methodName := "sentinel"
    assert ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall(
        "  Owner.Seed_2(   )  ",
        "Owner",
        out methodName
    )
    assert methodName == "Seed_2"

    assert ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall(
        "_local9()",
        "Owner",
        out methodName
    )
    assert methodName == "_local9"

    methodName = "sentinel"
    assert !ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall(
        "Else.Seed()",
        "Owner",
        out methodName
    )
    assert methodName == ""

    methodName = "sentinel"
    assert !ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall(
        "Seed(1)",
        "Owner",
        out methodName
    )
    assert methodName == ""

    nullText: string = null
    methodName = "sentinel"
    assert throws NullReferenceException {
        ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall(
            nullText,
            "Owner",
            out methodName
        )
    }
    // The original parser reset its out slot before calling Trim, whose null receiver threw.
    assert methodName == ""

    assert ColumnarStaticFieldInitializerEmitter.IsSimpleIdentifierText(((char)916).ToString() + "9_")
    assert !ColumnarStaticFieldInitializerEmitter.IsSimpleIdentifierText("9bad")
    assert !ColumnarStaticFieldInitializerEmitter.IsSimpleIdentifierText("has-dash")

    names := new string[](1)
    names[0] = "sentinel"
    assert ColumnarStaticFieldInitializerEmitter.IsSupportedGenericExtensionReceiverChainText(
        "root.Next_2." + ((char)916).ToString(),
        out names
    )
    assert names.Length == 3
    assert names[0] == "root"
    assert names[1] == "Next_2"
    assert names[2] == ((char)916).ToString()

    names = new string[](1)
    names[0] = "sentinel"
    assert !ColumnarStaticFieldInitializerEmitter.IsSupportedGenericExtensionReceiverChainText(
        "root..next",
        out names
    )
    // The split has already occurred when a segment fails validation.  Callers that inspect the
    // failure out slot therefore retain the three exact source segments.
    assert names.Length == 3
    assert names[0] == "root"
    assert names[1] == ""
    assert names[2] == "next"

    names = new string[](1)
    names[0] = "sentinel"
    assert !ColumnarStaticFieldInitializerEmitter.IsSupportedGenericExtensionReceiverChainText(
        "root(call)",
        out names
    )
    assert names.Length == 0
    assert Object.ReferenceEquals(names, StaticInitializerBclEmptyStringArray())
}

test "static initializer literal emission executes exact scalar values and retains lexical boundaries" {
    assert StaticInitializerLiteralValue(typeof(int), 1, "-42") == "-42"
    assert StaticInitializerLiteralValue(typeof(long), 1, "9000L") == "9000"
    assert StaticInitializerLiteralValue(typeof(ulong), 1, "18446744073709551615UL") == "18446744073709551615"
    assert StaticInitializerLiteralValue(typeof(ulong), 1, "1LuL") == "1"

    assert StaticInitializerLiteralValue(typeof(double), 2, "1_234.5") == "1234.5"
    assert StaticInitializerLiteralValue(typeof(float), 2, "-1.25F") == "-1.25"
    parsed := 0.0
    assert ColumnarStaticFieldInitializerEmitter.TryParseFloatingLiteralBody("1,234.5", out parsed)
    assert parsed == 1234.5
    // This is the inverse grouping/decimal arrangement.  It is accepted by a comma-decimal
    // ambient culture but rejected here because the owner deliberately parses invariantly.
    assert !ColumnarStaticFieldInitializerEmitter.TryParseFloatingLiteralBody("1.234,5", out parsed)

    newline := StaticInitializerLiteralValue(typeof(char), 3, "'\\n'")
    assert newline.Length == 1
    assert (int)newline[0] == 10

    ordinary := StaticInitializerLiteralValue(typeof(string), 4, "\"slash\\n\"")
    assert ordinary.Length == 6
    assert (int)ordinary[5] == 10
    assert StaticInitializerLiteralValue(typeof(string), 4, "\"\"\"slash\\n\"\"\"") == "slash\\n"
    assert StaticInitializerLiteralValue(typeof(bool), 44, "true") == "True"
    assert StaticInitializerLiteralValue(typeof(bool), 45, "false") == "False"

    assert StaticInitializerLiteralDeclines(typeof(int), 1, "1_000")
    assert StaticInitializerLiteralDeclines(typeof(int), 1, "9UL")
    assert StaticInitializerLiteralDeclines(typeof(ulong), 1, "-1UL")
    assert StaticInitializerLiteralDeclines(typeof(float), 2, "1.25")
    assert StaticInitializerLiteralDeclines(typeof(double), 2, "1m")
    assert StaticInitializerLiteralDeclines(typeof(string), 4, "$\"interpolated\"")
    assert StaticInitializerLiteralDeclines(typeof(char), 3, "'ab'")
}

test "static initializer expression emission prefers matching owner overloads and never reads siblings on that hit" {
    owner := SourceCallDefinition("StaticInitializerOwnerFirst", true)
    first := ConstructionDefineField(owner.Builder, "First", typeof(int), 22)
    observed := ConstructionDefineField(owner.Builder, "Observed", typeof(int), 22)
    selected := ConstructionDefineField(owner.Builder, "Selected", typeof(int), 22)

    StaticInitializerReadIntFieldMethod(owner, "ReadFirst", first)
    StaticInitializerIntParameterMethod(owner, "Seed", 99)
    StaticInitializerStringMethod(owner, "Seed", "wrong-return")
    parameterless := StaticInitializerIntMethod(owner, "Seed", 11)
    // Parameterless selection did not read modifier metadata before argument support was added.
    // A corrupt-but-previously-unobserved null slot therefore remains outside this path.
    parameterless.ParamModifierKinds = null

    rows := new List<ColumnarStaticFieldInitializer>()
    rows.Add(new ColumnarStaticFieldInitializer(owner, first, typeof(int), 1, "7"))
    rows.Add(new ColumnarStaticFieldInitializer(owner, observed, typeof(int), 1001, "ReadFirst()"))
    rows.Add(new ColumnarStaticFieldInitializer(owner, selected, typeof(int), 1001, "StaticInitializerOwnerFirst.Seed()"))
    definitions := new ColumnarStructDef[](1)
    definitions[0] = owner

    // A successful source-owned overload must return before the sibling registry is touched.  The
    // null reference is intentionally a hostile live boundary rather than an empty substitute.
    siblings: Dictionary<string, ColumnarSiblingMethodDefinition> = null
    assert ColumnarStaticFieldInitializerEmitter.TryEmitAll(definitions, rows, siblings)

    baked := StaticInitializerBake(owner)
    assert Convert.ToInt32(StaticInitializerStaticFieldValue(baked, "First")) == 7
    // `ReadFirst` executes after the First store, so this is an executable cctor-order assertion.
    assert Convert.ToInt32(StaticInitializerStaticFieldValue(baked, "Observed")) == 7
    assert Convert.ToInt32(StaticInitializerStaticFieldValue(baked, "Selected")) == 11
}

test "static initializer helper calls emit one string or qualified nameof argument after exact owner overload selection" {
    owner := SourceCallDefinition("StaticInitializerArgumentOwner", true)
    first := ConstructionDefineField(owner.Builder, "First", typeof(string), 22)
    second := ConstructionDefineField(owner.Builder, "Second", typeof(string), 22)

    // Both wrong candidates precede the selected overload. The initializer owner must preserve
    // declaration order while matching both the argument and return types.
    StaticInitializerStringMethod(owner, "Echo", "wrong-arity")
    StaticInitializerStringParameterIntMethod(owner, "Echo", 99)
    StaticInitializerStringEchoMethod(owner, "Echo")
    StaticInitializerPrefixStringMethod(owner, "Prefix", first)

    rows := new List<ColumnarStaticFieldInitializer>()
    rows.Add(new ColumnarStaticFieldInitializer(owner, first, typeof(string), 1001, "Echo(\"line\\n\")"))
    rows.Add(new ColumnarStaticFieldInitializer(owner, second, typeof(string), 1001, "StaticInitializerArgumentOwner.Prefix(nameof(NSharpLang.Runtime.SimdReductions.SumInt32))"))
    definitions := new ColumnarStructDef[](1)
    definitions[0] = owner

    // A successful owner match returns before the sibling registry is observed.
    siblings: Dictionary<string, ColumnarSiblingMethodDefinition> = null
    assert ColumnarStaticFieldInitializerEmitter.TryEmitAll(definitions, rows, siblings)

    baked := StaticInitializerBake(owner)
    firstValue := (string)StaticInitializerStaticFieldValue(baked, "First")
    secondValue := (string)StaticInitializerStaticFieldValue(baked, "Second")
    assert firstValue.Length == 5
    assert (int)firstValue[4] == 10
    // Prefix reads First during the second initializer, proving the first store precedes the
    // qualified-nameof helper call; NameOfPlanner contributes only the final source name.
    assert secondValue == firstValue + "SumInt32"
}

test "static initializer one-argument calls reject unsupported syntax arity receiver and signatures before IL emission" {
    owner := SourceCallDefinition("StaticInitializerArgumentDeclines", true)
    validField := ConstructionDefineField(owner.Builder, "Valid", typeof(string), 22)
    StaticInitializerStringEchoMethod(owner, "Echo")
    StaticInitializerStringParameterIntMethod(owner, "WrongReturn", 1)
    StaticInitializerIntParameterStringMethod(owner, "WrongParameter")
    StaticInitializerModifiedStringEchoMethod(owner, "RefParameter", 1)
    StaticInitializerModifiedStringEchoMethod(owner, "OutParameter", 2)
    StaticInitializerModifiedStringEchoMethod(owner, "ParamsParameter", 3)
    noSiblings := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)

    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "WrongParameter(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "RefParameter(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "OutParameter(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "ParamsParameter(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "WrongReturn(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Echo(\"one\", \"two\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Else.Echo(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Missing(\"value\")", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Echo(\"value\") true", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Echo(\"unterminated)", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Echo(nameof(left + right))", noSiblings)
    StaticInitializerExpressionDeclinesWithoutIl(owner, typeof(string), "Echo(value)", noSiblings)

    siblingTypes := new Type[](1)
    siblingTypes[0] = typeof(string)
    siblingModifiers := new int[](1)
    siblingModifiers[0] = 1
    siblingMethod := ExecutorRequiredMethod(typeof(StaticInitializerSiblingProbe), "SiblingEcho", siblingTypes)
    modifiedSibling := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
    modifiedSibling["SiblingEcho"] = new ColumnarSiblingMethodDefinition(
        siblingMethod,
        siblingTypes,
        siblingModifiers,
        typeof(string),
        new Type[](0),
        new int[](0),
        new Type?[](0),
        new Type[][](0)
    )
    StaticInitializerExpressionDeclinesWithoutIl(
        SourceCallDefinition("StaticInitializerModifiedSibling", true),
        typeof(string),
        "SiblingEcho(\"value\")",
        modifiedSibling
    )

    rows := new List<ColumnarStaticFieldInitializer>()
    rows.Add(new ColumnarStaticFieldInitializer(owner, validField, typeof(string), 1001, "Echo(\"value\")"))
    definitions := new ColumnarStructDef[](1)
    definitions[0] = owner
    assert ColumnarStaticFieldInitializerEmitter.TryEmitAll(definitions, rows, noSiblings)
    baked := StaticInitializerBake(owner)
    assert (string)StaticInitializerStaticFieldValue(baked, "Valid") == "value"
}

test "static initializer expression lookup preserves null owner and sibling failures before fallback" {
    noTypes := new Type[](0)
    matchingMethod := ExecutorRequiredMethod(typeof(StaticInitializerSiblingProbe), "SiblingSeed", noTypes)
    matchingSiblings := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
    matchingSiblings["Seed"] = new ColumnarSiblingMethodDefinition(
        matchingMethod,
        noTypes,
        new int[](0),
        typeof(int),
        new Type[](0),
        new int[](0),
        new Type?[](0),
        new Type[][](0)
    )

    // A present source key with a null overload list faulted in the original concrete list walk.
    // The matching sibling must therefore not turn that source-state failure into a successful call.
    nullOwner := SourceCallDefinition("StaticInitializerNullOwnerOverloads", true)
    nullOverloads: List<ColumnarStaticMethodDef> = null
    nullOwner.StaticMethods["Seed"] = nullOverloads
    ownerProbe := BoundDynamicMethod(
        "StaticInitializerNullOwnerOverloadsProbe",
        typeof(int),
        noTypes
    )
    assert throws NullReferenceException {
        ColumnarStaticFieldInitializerEmitter.TryEmitStaticFieldExpressionInitializerLoad(
            ownerProbe.GetILGenerator(),
            nullOwner,
            typeof(int),
            "Seed()",
            matchingSiblings
        )
    }

    // The N# sibling data owner carries live fields without defensive substitution. A found null
    // entry must likewise fault at lookup rather than decline as an absent call.
    nullSiblingOwner := SourceCallDefinition("StaticInitializerNullSibling", true)
    nullSibling: ColumnarSiblingMethodDefinition = null
    nullSiblings := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
    nullSiblings["Seed"] = nullSibling
    siblingProbe := BoundDynamicMethod(
        "StaticInitializerNullSiblingProbe",
        typeof(int),
        noTypes
    )
    assert throws NullReferenceException {
        ColumnarStaticFieldInitializerEmitter.TryEmitStaticFieldExpressionInitializerLoad(
            siblingProbe.GetILGenerator(),
            nullSiblingOwner,
            typeof(int),
            "Seed()",
            nullSiblings
        )
    }
}

test "static initializer expression emission calls an eligible top-level sibling only after owner lookup misses" {
    owner := SourceCallDefinition("StaticInitializerSiblingFallback", true)
    field := ConstructionDefineField(owner.Builder, "Value", typeof(int), 22)
    textField := ConstructionDefineField(owner.Builder, "Text", typeof(string), 22)
    noTypes := new Type[](0)
    method := ExecutorRequiredMethod(typeof(StaticInitializerSiblingProbe), "SiblingSeed", noTypes)
    siblings := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
    siblings["SiblingSeed"] = new ColumnarSiblingMethodDefinition(
        method,
        noTypes,
        new int[](0),
        typeof(int),
        new Type[](0),
        new int[](0),
        new Type?[](0),
        new Type[][](0)
    )
    stringTypes := new Type[](1)
    stringTypes[0] = typeof(string)
    echo := ExecutorRequiredMethod(typeof(StaticInitializerSiblingProbe), "SiblingEcho", stringTypes)
    siblings["SiblingEcho"] = new ColumnarSiblingMethodDefinition(
        echo,
        stringTypes,
        new int[](0),
        typeof(string),
        new Type[](0),
        new int[](0),
        new Type?[](0),
        new Type[][](0)
    )
    rows := new List<ColumnarStaticFieldInitializer>()
    rows.Add(new ColumnarStaticFieldInitializer(owner, field, typeof(int), 1001, "SiblingSeed()"))
    rows.Add(new ColumnarStaticFieldInitializer(owner, textField, typeof(string), 1001, "SiblingEcho(\"sibling\")"))
    definitions := new ColumnarStructDef[](1)
    definitions[0] = owner

    assert ColumnarStaticFieldInitializerEmitter.TryEmitAll(definitions, rows, siblings)
    baked := StaticInitializerBake(owner)
    assert Convert.ToInt32(StaticInitializerStaticFieldValue(baked, "Value")) == 23
    assert (string)StaticInitializerStaticFieldValue(baked, "Text") == "sibling"
}

test "static initializer driver creates no cctor for rows owned by another definition and stops before later owners" {
    target := SourceCallDefinition("StaticInitializerIdentitySharedName", true)
    foreign := SourceCallDefinition("StaticInitializerIdentitySharedName", true)
    assert !Object.ReferenceEquals(target, foreign)
    assert !Object.ReferenceEquals(target.Builder, foreign.Builder)
    assert target.Builder.get_Name() == foreign.Builder.get_Name()
    foreignField := ConstructionDefineField(foreign.Builder, "Foreign", typeof(int), 22)
    foreignRows := new List<ColumnarStaticFieldInitializer>()
    foreignRows.Add(new ColumnarStaticFieldInitializer(foreign, foreignField, typeof(int), 1, "7"))
    targetDefinitions := new ColumnarStructDef[](1)
    targetDefinitions[0] = target
    emptySiblings := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)

    assert ColumnarStaticFieldInitializerEmitter.TryEmitAll(targetDefinitions, foreignRows, emptySiblings)
    assert !StaticInitializerHasTypeInitializer(StaticInitializerBake(target))

    failing := SourceCallDefinition("StaticInitializerStops", true)
    bad := ConstructionDefineField(failing.Builder, "Bad", typeof(int), 22)
    later := SourceCallDefinition("StaticInitializerLater", true)
    laterField := ConstructionDefineField(later.Builder, "Later", typeof(int), 22)
    rows := new List<ColumnarStaticFieldInitializer>()
    // Kind 4 is a string literal and therefore rejects the int target before the later owner is
    // visited.  The first owner's half-emitted cctor is intentionally never baked.
    rows.Add(new ColumnarStaticFieldInitializer(failing, bad, typeof(int), 4, "\"bad\""))
    rows.Add(new ColumnarStaticFieldInitializer(later, laterField, typeof(int), 1, "9"))
    definitions := new ColumnarStructDef[](2)
    definitions[0] = failing
    definitions[1] = later

    assert !ColumnarStaticFieldInitializerEmitter.TryEmitAll(definitions, rows, emptySiblings)
    assert !StaticInitializerHasTypeInitializer(StaticInitializerBake(later))
}
