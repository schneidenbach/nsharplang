namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR WHICH REFLECTED MEMBERS A RECEIVER OFFERS (task 019 slice 2). These are the
// semantic assertions that came out of `CompletionEngine.cs` with the reflection walk and the
// `BindingFlags` decision, plus the one rule the move ADDED: the family never answers a type it
// cannot read.
//
// THE `MetadataLoadContext` CONTRACTS AT THE FOOT OF THIS FILE ARE THE POINT OF THE SLICE. The
// analyzer builds `ReflectionTypeInfo` straight out of a load context, so a metadata type reaches
// this family in production — and the deleted C# closed a LIVE generic definition over one, which
// the CLR answers with a `TypeBuilderInstantiation` whose every member lookup throws.

func CrfReflected(clrType: Type): TypeInfo {
    reflected: TypeInfo = new ReflectionTypeInfo(clrType)
    return reflected
}

func CrfSimple(name: string): TypeInfo {
    simple: TypeInfo = new SimpleTypeInfo(name)
    return simple
}

func CrfGeneric(name: string, arguments: TypeInfo[]): GenericTypeInfo {
    list := new List<TypeInfo>()
    index := 0
    while index < arguments.Length {
        list.Add(arguments[index])
        index = index + 1
    }

    return new GenericTypeInfo(name, list)
}

func CrfArg(argument: TypeInfo): TypeInfo[] {
    arguments := new TypeInfo[](1)
    arguments[0] = argument
    return arguments
}

func CrfNames(items: List<CompletionItem>): List<string> {
    names := new List<string>()
    index := 0
    while index < items.Count {
        names.Add(items[index].Name)
        index = index + 1
    }

    return names
}

func CrfFind(items: List<CompletionItem>, name: string): CompletionItem? {
    index := 0
    while index < items.Count {
        candidate := items[index]
        if candidate.Name == name {
            return candidate
        }

        index = index + 1
    }

    return null
}

func CrfCountOfKind(items: List<CompletionItem>, kind: string): int {
    total := 0
    index := 0
    while index < items.Count {
        if items[index].Kind == kind {
            total = total + 1
        }

        index = index + 1
    }

    return total
}

func CrfInstanceFlags(): BindingFlags {
    return CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.InstanceOnly)
}

func CrfMlcType(loadContext: MetadataLoadContext, fullName: string): Type {
    core := loadContext.LoadFromAssemblyName("System.Runtime")
    resolved := core.GetType(fullName)
    if resolved == null {
        throw new InvalidOperationException("The load context does not define '" + fullName + "'.")
    }

    return resolved
}


// ── the BindingFlags decision ────────────────────────────────────────────────────────────────

test "the three filters pick Public plus Instance, Public plus Static, and Public plus both" {
    instanceOnly := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.InstanceOnly)
    staticOnly := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.StaticOnly)
    all := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.All)

    assert instanceOnly == (BindingFlags.Public | BindingFlags.Instance)
    assert staticOnly == (BindingFlags.Public | BindingFlags.Static)
    assert all == (BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)

    // The bit patterns themselves, so a platform renumbering fails here rather than silently
    // changing which members a completion offers.
    assert Convert.ToInt32(instanceOnly) == 20
    assert Convert.ToInt32(staticOnly) == 24
    assert Convert.ToInt32(all) == 28
}

test "the completion flags deliberately omit DeclaredOnly, NonPublic and FlattenHierarchy" {
    all := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.All)

    assert (all & BindingFlags.DeclaredOnly) == BindingFlags.Default
    assert (all & BindingFlags.NonPublic) == BindingFlags.Default
    assert (all & BindingFlags.FlattenHierarchy) == BindingFlags.Default
    assert (all & BindingFlags.Public) == BindingFlags.Public
}

test "no DeclaredOnly means INHERITED INSTANCE members are offered, and GetType proves it" {
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(string), CrfInstanceFlags())

    // `System.Object` declares `GetType`, and a string receiver still offers it.
    getType := CrfFind(items, "GetType")
    assert getType != null
    assert getType.Kind == "method"
    assert !getType.IsStatic
}

test "no FlattenHierarchy means INHERITED STATICS are NOT offered" {
    staticFlags := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.StaticOnly)
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfDerived), staticFlags)

    assert CrfFind(items, "DerivedStatic") != null
    assert CrfFind(items, "BaseStatic") == null

    // The instance arm, by contrast, DOES reach the base class.
    instanceItems := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfDerived), CrfInstanceFlags())
    assert CrfFind(instanceItems, "DerivedInstance") != null
    assert CrfFind(instanceItems, "BaseInstance") != null
}


// ── which receivers reflect ──────────────────────────────────────────────────────────────────

test "the eleven reflection receivers answer in both the N# spelling and the CLR one" {
    assert CompletionReflectionFacts.KnownReceiverType("string") == typeof(string)
    assert CompletionReflectionFacts.KnownReceiverType("System.String") == typeof(string)
    assert CompletionReflectionFacts.KnownReceiverType("int") == typeof(int)
    assert CompletionReflectionFacts.KnownReceiverType("System.Int32") == typeof(int)
    assert CompletionReflectionFacts.KnownReceiverType("long") == typeof(long)
    assert CompletionReflectionFacts.KnownReceiverType("System.Int64") == typeof(long)
    assert CompletionReflectionFacts.KnownReceiverType("bool") == typeof(bool)
    assert CompletionReflectionFacts.KnownReceiverType("System.Boolean") == typeof(bool)
    assert CompletionReflectionFacts.KnownReceiverType("double") == typeof(double)
    assert CompletionReflectionFacts.KnownReceiverType("System.Double") == typeof(double)
    assert CompletionReflectionFacts.KnownReceiverType("float") == typeof(float)
    assert CompletionReflectionFacts.KnownReceiverType("System.Single") == typeof(float)
    assert CompletionReflectionFacts.KnownReceiverType("char") == typeof(char)
    assert CompletionReflectionFacts.KnownReceiverType("System.Char") == typeof(char)
    assert CompletionReflectionFacts.KnownReceiverType("object") == typeof(object)
    assert CompletionReflectionFacts.KnownReceiverType("System.Object") == typeof(object)
    assert CompletionReflectionFacts.KnownReceiverType("DateTime") == typeof(DateTime)
    assert CompletionReflectionFacts.KnownReceiverType("System.DateTime") == typeof(DateTime)
}

test "the two STATIC-CLASS receivers are loaded by metadata name and are the real runtime types" {
    // `typeof(Console)` and `typeof(Math)` do not emit, so these are loaded by name — and this is
    // the assertion that the name route did not quietly answer a DIFFERENT type.
    consoleType := CompletionReflectionFacts.KnownReceiverType("Console")
    assert consoleType != null
    assert consoleType.get_FullName() == "System.Console"
    consoleAssembly := consoleType.get_Assembly()
    consoleAssemblyName := consoleAssembly.GetName()
    assert consoleAssemblyName.get_Name() == "System.Console"
    assert CompletionReflectionFacts.KnownReceiverType("System.Console") == consoleType

    mathType := CompletionReflectionFacts.KnownReceiverType("Math")
    assert mathType != null
    assert mathType.get_FullName() == "System.Math"
    assert CompletionReflectionFacts.KnownReceiverType("System.Math") == mathType

    // Both really are static classes, which is exactly why `typeof` could not spell them.
    assert consoleType.get_IsAbstract() && consoleType.get_IsSealed()
    assert mathType.get_IsAbstract() && mathType.get_IsSealed()
}

test "a name that is not one of the eleven is not a reflection receiver" {
    assert CompletionReflectionFacts.KnownReceiverType("Person") == null
    assert CompletionReflectionFacts.KnownReceiverType("decimal") == null
    assert CompletionReflectionFacts.KnownReceiverType("byte") == null
    assert CompletionReflectionFacts.KnownReceiverType("") == null
    assert CompletionReflectionFacts.KnownReceiverType("System.Text.StringBuilder") == null
}

test "all fifteen generic definitions load, are open, and carry the arity their name implies" {
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("List").get_FullName() == "System.Collections.Generic.List`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IEnumerable").get_FullName() == "System.Collections.Generic.IEnumerable`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("ICollection").get_FullName() == "System.Collections.Generic.ICollection`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IList").get_FullName() == "System.Collections.Generic.IList`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IReadOnlyCollection").get_FullName() == "System.Collections.Generic.IReadOnlyCollection`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IReadOnlyList").get_FullName() == "System.Collections.Generic.IReadOnlyList`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Dictionary").get_FullName() == "System.Collections.Generic.Dictionary`2"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IDictionary").get_FullName() == "System.Collections.Generic.IDictionary`2"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("IReadOnlyDictionary").get_FullName() == "System.Collections.Generic.IReadOnlyDictionary`2"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("HashSet").get_FullName() == "System.Collections.Generic.HashSet`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Queue").get_FullName() == "System.Collections.Generic.Queue`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Stack").get_FullName() == "System.Collections.Generic.Stack`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Nullable").get_FullName() == "System.Nullable`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Task").get_FullName() == "System.Threading.Tasks.Task`1"
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("ValueTask").get_FullName() == "System.Threading.Tasks.ValueTask`1"

    // Every one is an OPEN definition — that is what makes the close below legal.
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("List").get_IsGenericTypeDefinition()
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Dictionary").GetGenericArguments().Length == 2
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("List").GetGenericArguments().Length == 1

    // `Stack` is the one that does NOT live in the core library, so its name carries its assembly.
    stackAssembly := CompletionReflectionFacts.KnownReceiverGenericDefinition("Stack").get_Assembly()
    stackAssemblyName := stackAssembly.GetName()
    assert stackAssemblyName.get_Name() == "System.Collections"
}

test "the fully qualified generic spellings answer the same definitions as the short ones" {
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("System.Collections.Generic.List")
        == CompletionReflectionFacts.KnownReceiverGenericDefinition("List")
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("System.Collections.Generic.IReadOnlyDictionary")
        == CompletionReflectionFacts.KnownReceiverGenericDefinition("IReadOnlyDictionary")
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("System.Nullable")
        == CompletionReflectionFacts.KnownReceiverGenericDefinition("Nullable")
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("System.Threading.Tasks.ValueTask")
        == CompletionReflectionFacts.KnownReceiverGenericDefinition("ValueTask")
    assert CompletionReflectionFacts.KnownReceiverGenericDefinition("Span") == null
}


// ── resolving a receiver's CLR type ──────────────────────────────────────────────────────────

test "a reflected receiver answers its own type and a simple one answers the table" {
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfReflected(typeof(Exception))) == typeof(Exception)
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfSimple("string")) == typeof(string)
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfSimple("System.Double")) == typeof(double)
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfSimple("Person")) == null
    unknown: TypeInfo = BuiltInTypes.Unknown
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(unknown) == null
}

test "a generic receiver closes its definition over the arguments the source wrote" {
    closed := CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("List", CrfArg(CrfSimple("int"))))
    assert closed != null
    assert closed.get_FullName().StartsWith("System.Collections.Generic.List`1[[System.Int32", StringComparison.Ordinal)
    assert closed.GetGenericArguments()[0] == typeof(int)

    stringList := CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("System.Collections.Generic.IReadOnlyList", CrfArg(CrfSimple("string"))))
    assert stringList != null
    assert stringList.GetGenericArguments()[0] == typeof(string)
}

test "an arity the definition does not have, and a definition that is not known, are both non-answers" {
    twoArguments := new TypeInfo[](2)
    twoArguments[0] = CrfSimple("int")
    twoArguments[1] = CrfSimple("string")

    // `List` takes ONE argument; two is not a smaller list, it is no answer at all.
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("List", twoArguments)) == null
    // `Dictionary` takes two, and one is likewise no answer.
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("Dictionary", CrfArg(CrfSimple("int")))) == null
    // A definition outside the table.
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("Span", CrfArg(CrfSimple("int")))) == null
}

test "a close the CLR REFUSES is a non-answer, and Nullable over a reference type is that case" {
    // `Nullable<T>` is constrained to value types, so closing it over `string` THROWS — and this
    // needs no MetadataLoadContext at all: `x: Nullable<string>` is something a person can type,
    // and the completion engine runs on exactly the half-written code that contains it. The
    // deleted C# let the exception escape `GetCompletions`.
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("Nullable", CrfArg(CrfSimple("string")))) == null
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("Nullable", CrfArg(CrfSimple("Person")))) == null
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("System.Nullable", CrfArg(CrfReflected(typeof(Exception))))) == null

    // The value-type close, for contrast, is a real closed type.
    closed := CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("Nullable", CrfArg(CrfSimple("int"))))
    assert closed != null
    assert closed.GetGenericArguments()[0] == typeof(int)
}

test "THE FAMILY NEVER ANSWERS A TYPE IT CANNOT READ: a null reflected type is a non-answer" {
    // The deleted C# reported SUCCESS here with a null `out`, and the walk then called
    // `GetMethods` on it. A non-answer is the honest reading and it is what the caller already
    // does for every receiver this family declines.
    nullBacked: Type = null
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfReflected(nullBacked)) == null
}


// ── which type a type ARGUMENT becomes ───────────────────────────────────────────────────────

test "the sixteen built-in arguments answer their CLR types in both spellings" {
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("string")) == typeof(string)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("System.String")) == typeof(string)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("int")) == typeof(int)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("long")) == typeof(long)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("bool")) == typeof(bool)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("double")) == typeof(double)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("float")) == typeof(float)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("char")) == typeof(char)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("object")) == typeof(object)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("decimal")) == typeof(decimal)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("byte")) == typeof(byte)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("short")) == typeof(short)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("uint")) == typeof(uint)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("ulong")) == typeof(ulong)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("ushort")) == typeof(ushort)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("sbyte")) == typeof(sbyte)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("System.SByte")) == typeof(sbyte)
}

test "the ARGUMENT table is wider than the RECEIVER table, and everything else is object" {
    // `decimal` and `byte` are arguments but NOT receivers, and that difference is deliberate.
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("decimal")) == typeof(decimal)
    assert CompletionReflectionFacts.KnownReceiverType("decimal") == null

    // An argument the table cannot spell widens to `object` rather than failing the close.
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfSimple("Person")) == typeof(object)
    unknown: TypeInfo = BuiltInTypes.Unknown
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(unknown) == typeof(object)
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfGeneric("List", CrfArg(CrfSimple("int")))) == typeof(object)
    // A reflected argument passes through verbatim.
    assert CompletionReflectionFacts.GetReflectionTypeArgumentOrObject(CrfReflected(typeof(Exception))) == typeof(Exception)
}


// ── the member read ──────────────────────────────────────────────────────────────────────────

test "methods come first, then properties, then fields, and each carries its kind and type text" {
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfShape), CrfInstanceFlags())

    assert CrfCountOfKind(items, "method") > 0
    assert CrfCountOfKind(items, "property") == 1
    assert CrfCountOfKind(items, "field") == 1

    // The order is methods, then properties, then fields.
    names := CrfNames(items)
    assert names.IndexOf("Label") < names.IndexOf("Count")
    assert names.IndexOf("Describe") < names.IndexOf("Label")

    label := CrfFind(items, "Label")
    assert label != null
    assert label.Kind == "property"
    assert label.Type == "string"
    assert !label.IsStatic

    count := CrfFind(items, "Count")
    assert count != null
    assert count.Kind == "field"
    assert count.Type == "int"

    describe := CrfFind(items, "Describe")
    assert describe != null
    assert describe.Kind == "method"
    assert describe.Type == "string"
}

test "the System.Object skip is ASYMMETRIC: properties and fields are dropped, methods are not" {
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(string), CrfInstanceFlags())

    // `System.Object` declares `GetType`, `ToString`, `Equals` and `GetHashCode` as METHODS, and
    // they survive.
    assert CrfFind(items, "GetType") != null
    // No property or field on the list is declared by `System.Object` — the walk drops those.
    index := 0
    objectDeclared := 0
    while index < items.Count {
        item := items[index]
        if item.Kind != "method" && item.Name == "GetType" {
            objectDeclared = objectDeclared + 1
        }

        index = index + 1
    }

    assert objectDeclared == 0
}

test "a static receiver's members are static and an instance receiver's are not" {
    staticFlags := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.StaticOnly)
    staticItems := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfShape), staticFlags)

    origin := CrfFind(staticItems, "Origin")
    assert origin != null
    assert origin.IsStatic
    assert origin.Kind == "property"

    total := CrfFind(staticItems, "Total")
    assert total != null
    assert total.IsStatic
    assert total.Kind == "field"

    // The instance read does not offer them.
    instanceItems := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfShape), CrfInstanceFlags())
    assert CrfFind(instanceItems, "Origin") == null
    assert CrfFind(instanceItems, "Total") == null
}

test "an empty read is an empty list, not a null one" {
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(CrfEmpty), CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.StaticOnly))

    assert items != null
    assert items.Count == 0
}


// ── the MetadataLoadContext dimension ────────────────────────────────────────────────────────

test "a receiver read through a MetadataLoadContext reflects, and answers what its live twin does" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null
        metadataString := CrfMlcType(loadContext, "System.String")
        // It really is the load context's type and not the live one.
        assert metadataString != typeof(string)

        resolved := CompletionReflectionFacts.ResolveCompletionReflectionType(CrfReflected(metadataString))
        assert resolved == metadataString

        metadataItems := CompletionReflectionFacts.BuildReflectionMemberItems(metadataString, CrfInstanceFlags())
        liveItems := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(string), CrfInstanceFlags())
        assert metadataItems.Count == liveItems.Count
        assert metadataItems.Count > 0

        // The names, kinds and type texts agree member for member, because nothing in the read
        // compares a `Type` by identity — the `System.Object` skip is a FullName compare and the
        // type text is keyed on `get_FullName()`.
        index := 0
        while index < metadataItems.Count {
            metadataItem := metadataItems[index]
            liveItem := liveItems[index]
            assert metadataItem.Name == liveItem.Name
            assert metadataItem.Kind == liveItem.Kind
            assert metadataItem.Type == liveItem.Type
            assert metadataItem.IsStatic == liveItem.IsStatic
            index = index + 1
        }
    } finally {
        scan.Dispose()
    }
}

test "a LIVE definition closed over a METADATA argument is POISONED, and the family declines it" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null
        metadataInt := CrfMlcType(loadContext, "System.Int32")
        assert metadataInt != typeof(int)

        // What the CLR really does with the mix, asserted here so a platform change fails this
        // contract rather than silently reopening the crash: it does NOT throw, it POISONS.
        definition := CompletionReflectionFacts.KnownReceiverGenericDefinition("List")
        assert definition != null
        arguments := new Type[](1)
        arguments[0] = metadataInt
        poisoned := definition.MakeGenericType(arguments)
        assert AnalyzerClrTypeConversion.IsPoisonedMixedInstantiation(poisoned)

        // And this is the shape `AnalyzerReflectionTypeConversion.ConvertReflectionType` produces
        // for `List<SomeExternalType>` read out of a load context, so it reaches the family in
        // production. The family answers NOTHING rather than a type whose every member lookup
        // throws NotSupportedException.
        assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("List", CrfArg(CrfReflected(metadataInt)))) == null

        // The all-live close, for contrast, is a real closed type.
        assert CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("List", CrfArg(CrfSimple("int")))) != null
    } finally {
        scan.Dispose()
    }
}

test "a metadata argument that the built-in table can spell is NOT poisoned, because it never travels" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null

        // `List<int>` written in SOURCE carries a `SimpleTypeInfo`, which the argument table maps
        // to the LIVE `typeof(int)` — so the close stays inside one reflection universe and the
        // completion works. Only a REFLECTED argument can carry a foreign universe in.
        closed := CompletionReflectionFacts.ResolveCompletionReflectionType(CrfGeneric("List", CrfArg(CrfSimple("int"))))
        assert closed != null
        assert !AnalyzerClrTypeConversion.IsPoisonedMixedInstantiation(closed)
        items := CompletionReflectionFacts.BuildReflectionMemberItems(closed, CrfInstanceFlags())
        assert items.Count > 0
        assert CrfFind(items, "Add") != null
    } finally {
        scan.Dispose()
    }
}


// ── fixtures ─────────────────────────────────────────────────────────────────────────────────

class CrfBase {
    static func BaseStatic(): int {
        return 1
    }

    func BaseInstance(): int {
        return 2
    }
}

class CrfDerived: CrfBase {
    static func DerivedStatic(): int {
        return 3
    }

    func DerivedInstance(): int {
        return 4
    }
}

// NOTE: this fixture carries NO backing field, deliberately. A camelCase N# field is file-private
// BY CONVENTION but is emitted as a PUBLIC IL field, so it would show up in this very completion
// list and make the counts below say something other than what they mean.
class CrfShape {
    Count: int
    static Total: int

    Label: string => "label"
    static Origin: string => "origin"

    constructor(count: int) {
        Count = count
    }

    func Describe(prefix: string): string {
        return prefix + Label
    }
}

class CrfEmpty {
    constructor() {
    }
}
