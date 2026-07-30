namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's TypeInfo → CLR `Type` construction funnel. Every member of the
// family was `private` in Analyzer.cs, so no test named any of them: their behaviour was pinned only
// indirectly, through end-to-end analyzer diagnostics. This is their first DIRECT pinning, and it is
// written against the two entry points plus the one helper an outside caller reaches
// (TryConstructDelegateType), which is the whole of the owner's public surface.

func ClrConversionFacts(context: MetadataLoadContext): AnalyzerWellKnownTypes {
    core := context.LoadFromAssemblyName("System.Runtime")
    return new AnalyzerWellKnownTypes(context, core)
}

func ClrConversionContext(path: string): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    declarations := new List<object>()
    declarations.Add(new NSharpLang.Compiler.TestStubs.ClassDeclaration("Widget", null))
    context.Reset("/tmp", assemblies)
    context.AddCompilationUnit(path, new AnalyzerContextTestUnit(declarations))
    return context
}

func ClrTypeName(candidate: Type?): string {
    if candidate == null {
        return "<null>"
    }

    return candidate.get_FullName()
}

// A constructed generic printed as definition + arguments, so a contract can name the shape it
// expects without depending on the load context's assembly-qualified argument spelling.
func ClrGenericShape(candidate: Type?): string {
    if candidate == null {
        return "<null>"
    }

    if !candidate.get_IsGenericType() {
        return ClrTypeName(candidate)
    }

    builder := new StringBuilder()
    builder.Append(candidate.GetGenericTypeDefinition().get_FullName())
    builder.Append("<")
    arguments := candidate.GetGenericArguments()
    index := 0
    while index < arguments.Length {
        if index > 0 {
            builder.Append(",")
        }

        // Recursive, because a constructed generic's own FullName spells its arguments
        // assembly-qualified and a contract should not have to name a version.
        argument := arguments[index]
        builder.Append(ClrGenericShape(argument))
        index = index + 1
    }

    builder.Append(">")
    return builder.ToString()
}

func ClrConversionArgs(first: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    return result
}

func ClrConversionArgs2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    result := ClrConversionArgs(first)
    result.Add(second)
    return result
}

func ClrConversionFunction(
    returnType: TypeInfo?,
    parameters: List<TypeInfo>): FunctionTypeInfo {
    functionType := new FunctionTypeInfo()
    functionType.ParameterTypes = parameters
    functionType.ReturnType = returnType
    return functionType
}

func ClrConversionVoidFunction(parameterCount: int): FunctionTypeInfo {
    parameters := new List<TypeInfo>()
    index := 0
    while index < parameterCount {
        parameters.Add(BuiltInTypes.Int)
        index = index + 1
    }

    return ClrConversionFunction(BuiltInTypes.Void, parameters)
}

func ClrConversionValueFunction(parameterCount: int): FunctionTypeInfo {
    parameters := new List<TypeInfo>()
    index := 0
    while index < parameterCount {
        parameters.Add(BuiltInTypes.Int)
        index = index + 1
    }

    return ClrConversionFunction(BuiltInTypes.String, parameters)
}

func ClrConversionEmptyTypeParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func ClrConversionRecord(name: string): RecordTypeInfo {
    return new RecordTypeInfo(
        name,
        0,
        0,
        false,
        new TypeReference[](0),
        ClrConversionEmptyTypeParameters(),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func ClrConversionStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(
        name,
        0,
        0,
        new TypeReference[](0),
        ClrConversionEmptyTypeParameters(),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func ClrConversionInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        name,
        0,
        0,
        false,
        new TypeReference[](0),
        ClrConversionEmptyTypeParameters(),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func ClrConversionEnum(name: string): EnumTypeInfo {
    members := new List<EnumMemberInfo>()
    return new EnumTypeInfo(new EnumDeclarationInfo(name, members, EnumType.Int, 0, 0))
}

func ClrConversionUnion(name: string): UnionTypeInfo {
    cases := new List<UnionCase>()
    return new UnionTypeInfo(new UnionDeclarationInfo(name, null, cases, 0, 0))
}

test "the exact conversion answers metadata types for the built-ins and nothing for a stranger" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-simple.nl"), facts)

        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Int)) == "System.Int32"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Long)) == "System.Int64"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Float)) == "System.Single"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Double)) == "System.Double"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Decimal)) == "System.Decimal"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Byte)) == "System.Byte"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.SByte)) == "System.SByte"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Short)) == "System.Int16"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.UShort)) == "System.UInt16"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.UInt)) == "System.UInt32"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.ULong)) == "System.UInt64"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Char)) == "System.Char"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Bool)) == "System.Boolean"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.String)) == "System.String"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Void)) == "System.Void"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Object)) == "System.Object"

        // These are the LOAD CONTEXT's types, not the compiler's own. Confusing the two is the exact
        // bug the metadata-backed path exists to prevent.
        assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Int) != typeof(int)
        assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.String) != typeof(string)

        // `null` and `never` are simple TypeInfo values with no CLR spelling; so is any other name.
        assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Null) == null
        assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Never) == null
        assert funnel.TryConvertTypeInfoToClrType(new SimpleTypeInfo("NoSuchBuiltIn")) == null
        assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Unknown) == null
    } finally {
        scan.Dispose()
    }
}

test "arrays and nullables rebuild their shell, and a reference nullable is its inner type" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-shells.nl"), facts)

        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(BuiltInTypes.Int))) == "System.Int32[]"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(new ArrayTypeInfo(BuiltInTypes.String)))) == "System.String[][]"

        // A value-type nullable is Nullable<T>; a reference-type nullable has no CLR shape of its own.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new NullableTypeInfo(BuiltInTypes.Int))) == "System.Nullable`1<System.Int32>"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new NullableTypeInfo(BuiltInTypes.String))) == "System.String"

        // The oblivious wrapper is transparent, at any depth and under any shell.
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ObliviousTypeInfo(BuiltInTypes.Int))) == "System.Int32"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ObliviousTypeInfo(new ObliviousTypeInfo(BuiltInTypes.Bool)))) == "System.Boolean"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(new ObliviousTypeInfo(BuiltInTypes.Char)))) == "System.Char[]"

        // An unconvertible position poisons the whole shell rather than being skipped.
        assert funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(new SimpleTypeInfo("NoSuchBuiltIn"))) == null
        assert funnel.TryConvertTypeInfoToClrType(
            new NullableTypeInfo(new SimpleTypeInfo("NoSuchBuiltIn"))) == null
    } finally {
        scan.Dispose()
    }
}

test "compiler-known generics construct at their own arity and at no other" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-generic.nl"), facts)

        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(BuiltInTypes.Int))))
            == "System.Collections.Generic.List`1<System.Int32>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "Dictionary",
                ClrConversionArgs2(BuiltInTypes.String, BuiltInTypes.Int))))
            == "System.Collections.Generic.Dictionary`2<System.String,System.Int32>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("Task", ClrConversionArgs(BuiltInTypes.Int))))
            == "System.Threading.Tasks.Task`1<System.Int32>"

        // Nesting re-enters the funnel at every argument position.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "IEnumerable",
                ClrConversionArgs(new ArrayTypeInfo(BuiltInTypes.Int)))))
            == "System.Collections.Generic.IEnumerable`1<System.Int32[]>"

        // Arity is exact and the name table is case-sensitive.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs2(BuiltInTypes.Int, BuiltInTypes.Int)))
            == null
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("Dictionary", ClrConversionArgs(BuiltInTypes.Int))) == null
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("list", ClrConversionArgs(BuiltInTypes.Int))) == null
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("NotAKnownName", ClrConversionArgs(BuiltInTypes.Int))) == null

        // An unconvertible type argument declines the whole construction.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(new SimpleTypeInfo("NoSuchBuiltIn"))))
            == null
    } finally {
        scan.Dispose()
    }
}

test "a carried generic definition overrides the table and is normalized to an open definition" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-carried.nl"), facts)

        // A CLOSED definition gives up its open definition rather than being rejected, and the NAME
        // is ignored entirely once a definition is carried.
        closed := new ReflectionTypeInfo(typeof(List<string>)) as TypeInfo
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("NotAKnownName", ClrConversionArgs(BuiltInTypes.Int), closed)))
            == "System.Collections.Generic.List`1<System.Int32>"

        // A non-generic definition is not a definition at all.
        nonGeneric := new ReflectionTypeInfo(typeof(string)) as TypeInfo
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(BuiltInTypes.Int), nonGeneric)) == null

        // A carried definition that is not a ReflectionTypeInfo suppresses the table lookup and
        // leaves nothing behind: a present-but-unusable definition is NOT a fallback to the table.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(BuiltInTypes.Int), BuiltInTypes.Int))
            == null

        // The carried definition's arity still has to match the written argument list.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "NotAKnownName",
                ClrConversionArgs2(BuiltInTypes.Int, BuiltInTypes.Int),
                closed)) == null
    } finally {
        scan.Dispose()
    }
}

test "JsonTypeInfo is the one generic whose type argument may be a surrogate" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        path := "/tmp/clr-json.nl"
        declarationContext := ClrConversionContext(path)
        funnel := new AnalyzerClrTypeConversion(declarationContext, facts)

        widget := ClrConversionRecord("Widget") as TypeInfo

        // The exception: an N#-declared argument is accepted THROUGH the surrogate conversion, in
        // both spellings the analyzer may carry for the name.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("JsonTypeInfo", ClrConversionArgs(widget))))
            == "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1<System.Object>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "System.Text.Json.Serialization.Metadata.JsonTypeInfo",
                ClrConversionArgs(widget))))
            == "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1<System.Object>"

        // The rule is JsonTypeInfo's alone: every other compiler-known generic declines.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(widget))) == null
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("Task", ClrConversionArgs(widget))) == null

        // And it is not a licence to accept ANY unconvertible argument — a stranger simple name has
        // no surrogate either.
        assert funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "JsonTypeInfo",
                ClrConversionArgs(new SimpleTypeInfo("NoSuchBuiltIn")))) == null
    } finally {
        scan.Dispose()
    }
}

test "function types reify as Action or Func across every supported arity and decline past it" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-fn.nl"), facts)

        // A void return picks Action; the parameterless case is the non-generic Action.
        assert ClrTypeName(funnel.TryConstructDelegateType(
            ClrConversionVoidFunction(0))) == "System.Action"
        assert ClrGenericShape(funnel.TryConstructDelegateType(
            ClrConversionVoidFunction(1))) == "System.Action`1<System.Int32>"
        assert ClrGenericShape(funnel.TryConstructDelegateType(
            ClrConversionVoidFunction(4)))
            == "System.Action`4<System.Int32,System.Int32,System.Int32,System.Int32>"
        assert funnel.TryConstructDelegateType(ClrConversionVoidFunction(5)) == null

        // Everything else picks Func, whose arguments are the parameters THEN the return type.
        assert ClrGenericShape(funnel.TryConstructDelegateType(
            ClrConversionValueFunction(0))) == "System.Func`1<System.String>"
        assert ClrGenericShape(funnel.TryConstructDelegateType(
            ClrConversionValueFunction(1))) == "System.Func`2<System.Int32,System.String>"
        assert ClrGenericShape(funnel.TryConstructDelegateType(
            ClrConversionValueFunction(4)))
            == "System.Func`5<System.Int32,System.Int32,System.Int32,System.Int32,System.String>"
        assert funnel.TryConstructDelegateType(ClrConversionValueFunction(5)) == null

        // The type-shaped entry point routes a FunctionTypeInfo to exactly the same answer.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(ClrConversionValueFunction(1)))
            == "System.Func`2<System.Int32,System.String>"

        // A missing half of the signature, or an unconvertible position, declines.
        assert funnel.TryConstructDelegateType(
            ClrConversionFunction(null, new List<TypeInfo>())) == null
        assert funnel.TryConstructDelegateType(ClrConversionFunction(
            BuiltInTypes.Int,
            ClrConversionArgs(new SimpleTypeInfo("NoSuchBuiltIn")))) == null
    } finally {
        scan.Dispose()
    }
}

test "an anonymous union reifies at arity two and at no other arity" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext("/tmp/clr-union.nl"), facts)

        // The runtime assembly is not part of this load context, so the union open definition is
        // absent and every arity answers null — including the arity that WOULD construct. That is
        // the contract: a project that does not reference the runtime never constructs one.
        assert funnel.TryConvertTypeInfoToClrType(new AnonymousUnionTypeInfo(
            ClrConversionArgs2(BuiltInTypes.Int, BuiltInTypes.String))) == null
        assert funnel.TryConvertTypeInfoToClrType(new AnonymousUnionTypeInfo(
            ClrConversionArgs(BuiltInTypes.Int))) == null
        assert funnel.TryConvertTypeInfoToClrType(
            new AnonymousUnionTypeInfo(new List<TypeInfo>())) == null

        // The surrogate conversion does not invent one either: an anonymous union is not one of the
        // families that gets an `object` surrogate.
        assert funnel.TryConvertTypeInfoToClrTypeForBinding(new AnonymousUnionTypeInfo(
            ClrConversionArgs2(BuiltInTypes.Int, BuiltInTypes.String))) == null
    } finally {
        scan.Dispose()
    }
}

test "the surrogate conversion substitutes object for every declared family and rebuilds shells" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        path := "/tmp/clr-surrogate.nl"
        funnel := new AnalyzerClrTypeConversion(ClrConversionContext(path), facts)

        recordType := ClrConversionRecord("Point") as TypeInfo
        structType := ClrConversionStruct("Vec") as TypeInfo
        interfaceType := ClrConversionInterface("Shape") as TypeInfo
        enumType := ClrConversionEnum("Color") as TypeInfo
        unionType := ClrConversionUnion("Payload") as TypeInfo
        distinct := new NewtypeInfo("UserId", new SimpleTypeReference("int")) as TypeInfo

        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(recordType)) == "System.Object"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(structType)) == "System.Object"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(interfaceType))
            == "System.Object"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(enumType)) == "System.Object"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(unionType)) == "System.Object"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(distinct)) == "System.Object"

        // The EXACT conversion refuses all of them — that difference is the reason both exist.
        assert funnel.TryConvertTypeInfoToClrType(recordType) == null
        assert funnel.TryConvertTypeInfoToClrType(enumType) == null
        assert funnel.TryConvertTypeInfoToClrType(distinct) == null

        // Shells are rebuilt around the surrogate.
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new ArrayTypeInfo(recordType))) == "System.Object[]"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new NullableTypeInfo(recordType))) == "System.Object"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("List", ClrConversionArgs(recordType))))
            == "System.Collections.Generic.List`1<System.Object>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("Dictionary", ClrConversionArgs2(BuiltInTypes.String, recordType))))
            == "System.Collections.Generic.Dictionary`2<System.String,System.Object>"

        // A convertible value still takes the exact answer: the surrogate is a fallback, not a rule.
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrTypeForBinding(BuiltInTypes.Int))
            == "System.Int32"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new NullableTypeInfo(BuiltInTypes.Int))) == "System.Nullable`1<System.Int32>"

        // And a shape with no surrogate of its own stays unconvertible.
        assert funnel.TryConvertTypeInfoToClrTypeForBinding(
            new SimpleTypeInfo("NoSuchBuiltIn")) == null
        assert funnel.TryConvertTypeInfoToClrTypeForBinding(BuiltInTypes.Unknown) == null
    } finally {
        scan.Dispose()
    }
}

test "the surrogate generic vocabulary is strictly smaller than the exact one" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        funnel := new AnalyzerClrTypeConversion(
            ClrConversionContext("/tmp/clr-vocabulary.nl"),
            facts)

        recordType := ClrConversionRecord("Point") as TypeInfo

        // In the shared vocabulary a declared type argument becomes `object`.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("Task", ClrConversionArgs(recordType))))
            == "System.Threading.Tasks.Task`1<System.Object>"

        // `Result` and the qualified spellings are deliberately NOT in the surrogate table: a
        // reconstructed `Result<object,object>` would name a type the program never wrote.
        assert funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("Result", ClrConversionArgs2(recordType, BuiltInTypes.String))) == null
        assert funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo(
                "NSharpLang.Runtime.Result",
                ClrConversionArgs2(recordType, BuiltInTypes.String))) == null
        // JsonTypeInfo is absent from the surrogate table too — but it never needs it, because the
        // EXACT conversion already accepts a surrogate argument for that one name. Both spellings
        // therefore answer, and the answer comes from the exact path, not from this vocabulary.
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("JsonTypeInfo", ClrConversionArgs(recordType))))
            == "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1<System.Object>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo(
                "System.Text.Json.Serialization.Metadata.JsonTypeInfo",
                ClrConversionArgs(recordType))))
            == "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1<System.Object>"
    } finally {
        scan.Dispose()
    }
}

test "a declared alias is resolved at every position the funnel descends through" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        facts := ClrConversionFacts(context)
        path := "/tmp/clr-alias.nl"
        declarationContext := ClrConversionContext(path)
        funnel := new AnalyzerClrTypeConversion(declarationContext, facts)

        meters := new AliasTypeInfo(new SimpleTypeReference("int"))
        declarationContext.RegisterDeclaredAlias(path, meters)
        alias := meters as TypeInfo

        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(alias)) == "System.Int32"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(alias))) == "System.Int32[]"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ArrayTypeInfo(new ArrayTypeInfo(alias)))) == "System.Int32[][]"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new NullableTypeInfo(alias))) == "System.Nullable`1<System.Int32>"
        assert ClrTypeName(funnel.TryConvertTypeInfoToClrType(
            new ObliviousTypeInfo(alias))) == "System.Int32"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo("List", ClrConversionArgs(alias))))
            == "System.Collections.Generic.List`1<System.Int32>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
            new GenericTypeInfo(
                "List",
                ClrConversionArgs(new GenericTypeInfo("List", ClrConversionArgs(alias))))))
            == "System.Collections.Generic.List`1<System.Collections.Generic.List`1<System.Int32>>"
        assert ClrGenericShape(funnel.TryConstructDelegateType(ClrConversionFunction(
            alias,
            ClrConversionArgs(alias)))) == "System.Func`2<System.Int32,System.Int32>"
        assert ClrGenericShape(funnel.TryConvertTypeInfoToClrTypeForBinding(
            new GenericTypeInfo("List", ClrConversionArgs(alias))))
            == "System.Collections.Generic.List`1<System.Int32>"

        // An alias this context does not own is transparent, so it converts to nothing rather than
        // to the type its reference happens to name.
        unowned := new AliasTypeInfo(new SimpleTypeReference("int")) as TypeInfo
        assert funnel.TryConvertTypeInfoToClrType(unowned) == null
        assert funnel.TryConvertTypeInfoToClrType(new ArrayTypeInfo(unowned)) == null
    } finally {
        scan.Dispose()
    }
}

test "without well-known-type facts the funnel answers runtime types and descends without aliases" {
    path := "/tmp/clr-nofacts.nl"
    declarationContext := ClrConversionContext(path)
    funnel := new AnalyzerClrTypeConversion(declarationContext, null)

    // The no-metadata fallback answers with the COMPILER's own runtime types.
    assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.Int) == typeof(int)
    assert funnel.TryConvertTypeInfoToClrType(BuiltInTypes.String) == typeof(string)
    assert funnel.TryConvertTypeInfoToClrType(new ArrayTypeInfo(BuiltInTypes.Int)) == typeof(int[])
    assert ClrGenericShape(funnel.TryConvertTypeInfoToClrType(
        new NullableTypeInfo(BuiltInTypes.Int))) == "System.Nullable`1<System.Int32>"
    assert funnel.TryConvertTypeInfoToClrType(new NullableTypeInfo(BuiltInTypes.String)) == null

    // Generics, functions and unions all need the metadata facts and answer nothing without them.
    assert funnel.TryConvertTypeInfoToClrType(
        new GenericTypeInfo("List", ClrConversionArgs(BuiltInTypes.Int))) == null
    assert funnel.TryConstructDelegateType(ClrConversionValueFunction(1)) == null
    assert funnel.TryConvertTypeInfoToClrType(new AnonymousUnionTypeInfo(
        ClrConversionArgs2(BuiltInTypes.Int, BuiltInTypes.String))) == null

    // The surrogate conversion has no `object` to hand out, so it is the exact answer or nothing.
    assert funnel.TryConvertTypeInfoToClrTypeForBinding(BuiltInTypes.Int) == typeof(int)
    assert funnel.TryConvertTypeInfoToClrTypeForBinding(ClrConversionRecord("Point")) == null

    // The TOP-LEVEL alias is still resolved — that happens before the facts are consulted — but the
    // fallback table descends WITHOUT resolving aliases, so a nested one is not.
    meters := new AliasTypeInfo(new SimpleTypeReference("int"))
    declarationContext.RegisterDeclaredAlias(path, meters)
    alias := meters as TypeInfo
    assert funnel.TryConvertTypeInfoToClrType(alias) == typeof(int)
    assert funnel.TryConvertTypeInfoToClrType(new ArrayTypeInfo(alias)) == null
}
