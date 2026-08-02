namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for `ResolveMember` — what a member NAME resolves to on a type.
//
// This was `Analyzer.cs`'s largest single private member, so nothing named it directly: every arm
// was pinned only through end-to-end diagnostics on programs that happened to reach it. These are
// its first DIRECT contracts, and they concentrate on the arms no single call site reveals — the
// EVENT arm (which is why the `EventInfo` catalog row exists at all), the probe ORDER within a
// reflected type, the static/instance gate, and the fall-through to the extension surface.

class MemberResolutionHarness {
    Resolution: AnalyzerMemberResolution
    Extensions: AnalyzerExtensionMethodResolution
    Declared: List<FunctionDeclaration>
    Namespaces: List<string>
    Assemblies: List<Assembly>

    constructor(
        resolution: AnalyzerMemberResolution,
        extensions: AnalyzerExtensionMethodResolution,
        declared: List<FunctionDeclaration>,
        namespaces: List<string>,
        assemblies: List<Assembly>) {
        Resolution = resolution
        Extensions = extensions
        Declared = declared
        Namespaces = namespaces
        Assemblies = assemblies
    }
}

func MemberResolutionDefault(): MemberResolutionHarness {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)

    declared := new List<FunctionDeclaration>()
    namespaces := new List<string>()
    assemblies := new List<Assembly>()

    extensions := new AnalyzerExtensionMethodResolution(
        resolver,
        assignability,
        context,
        functionTypes,
        clrConversion,
        declared,
        namespaces,
        assemblies)

    return new MemberResolutionHarness(
        new AnalyzerMemberResolution(
            functionTypes,
            context,
            substitution,
            resolver,
            clrConversion,
            extensions,
            namespaces),
        extensions,
        declared,
        namespaces,
        assemblies)
}

func MemberResolutionCoreAssembly(): Assembly {
    coreType := typeof(object)
    return coreType.get_Assembly()
}

func MemberResolutionCoreType(fullName: string): Type {
    coreAssembly := MemberResolutionCoreAssembly()
    return coreAssembly.GetType(fullName)
}

func MemberResolutionIntArrayType(): Type {
    empty := new int[](0)
    boxed := empty as object
    return boxed.GetType()
}

test "a .NET EVENT resolves to an event, with its accessors and both types" {
    harness := MemberResolutionDefault()

    // THE ARM THE `EventInfo` CATALOG ROW EXISTS FOR. Without it a name that denotes an event would
    // reach the method arm or the extension fall-through, and `+=`/`on`/`off` would have no member
    // kind to reject or to subscribe through.
    domainType := MemberResolutionCoreType("System.AppDomain")
    answer := harness.Resolution.ResolveMember(
        new ReflectionTypeInfo(domainType), "ProcessExit", false, null)

    eventAnswer := answer as ReflectionEventInfo
    assert eventAnswer != null
    assert eventAnswer.Name == "ProcessExit"

    // The accessors ride on the answer: `on`/`off` call these instead of writing the backing field.
    addMethod := eventAnswer.AddMethod
    assert addMethod != null
    assert addMethod.get_Name() == "add_ProcessExit"

    removeMethod := eventAnswer.RemoveMethod
    assert removeMethod != null
    assert removeMethod.get_Name() == "remove_ProcessExit"

    // And both types do too: the handler delegate is what a subscription must be assignable to, and
    // the declaring type is where the accessors are found.
    handlerType := eventAnswer.HandlerDelegateType
    assert handlerType != null
    assert handlerType.get_Name() == "EventHandler"

    declaringType := eventAnswer.DeclaringType
    assert declaringType != null
    assert declaringType.get_Name() == "AppDomain"

    // The rendered form is the member kind, not a type name — this is what hover shows.
    eventObject := eventAnswer as object
    assert eventObject.ToString() == "event ProcessExit"
}

test "the probe order inside a reflected type is property, then field, then event, then methods" {
    harness := MemberResolutionDefault()
    stringType := new ReflectionTypeInfo(typeof(string))

    // A PROPERTY answers as its own type, never as a method group.
    lengthAnswer := harness.Resolution.ResolveMember(stringType, "Length", false, null)
    assert TypeInfoIdentityFacts.AreEqual(lengthAnswer, BuiltInTypes.Int)

    // A FIELD answers as its own type. `string.Empty` is a public static field, so it is only
    // visible when static members are included — which is the gate below.
    emptyAnswer := harness.Resolution.ResolveMember(stringType, "Empty", true, null)
    assert TypeInfoIdentityFacts.AreEqual(emptyAnswer, BuiltInTypes.String)

    // A METHOD answers as a GROUP even when overloaded once, because overload resolution runs later.
    substringAnswer := harness.Resolution.ResolveMember(stringType, "Substring", false, null)
    substringGroup := substringAnswer as ReflectionMethodGroupInfo
    assert substringGroup != null
    assert substringGroup.Methods.Length > 1

    substringObject := substringGroup as object
    assert substringObject.ToString() == "Substring(...)"

    // An EVENT is probed after both, on a type that has one.
    domainType := new ReflectionTypeInfo(MemberResolutionCoreType("System.AppDomain"))
    processExit := harness.Resolution.ResolveMember(domainType, "ProcessExit", false, null)
    assert (processExit as ReflectionEventInfo) != null
}

test "the static gate decides whether a static member is visible at all" {
    harness := MemberResolutionDefault()
    stringType := new ReflectionTypeInfo(typeof(string))

    // `string.Empty` is static: written against the TYPE it resolves, written against a VALUE it
    // does not, and with nothing else claiming the name the answer falls to the extension surface,
    // which with no assemblies loaded is `unknown`.
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(stringType, "Empty", true, null), BuiltInTypes.String)
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(stringType, "Empty", false, null))

    // And the reverse for an instance member: `Length` is visible either way, because including
    // statics WIDENS the flags rather than replacing them.
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(stringType, "Length", false, null), BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(stringType, "Length", true, null), BuiltInTypes.Int)
}

test "a BUILT-IN simple type resolves against the CLR type behind it" {
    harness := MemberResolutionDefault()

    // Member access on a literal reaches metadata: `"x".Length`, `5.ToString()`. Nothing here is a
    // reflection type when it arrives — the conversion is the arm under test.
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(BuiltInTypes.String, "Length", false, null),
        BuiltInTypes.Int)

    toStringAnswer := harness.Resolution.ResolveMember(BuiltInTypes.Int, "ToString", false, null)
    assert (toStringAnswer as ReflectionMethodGroupInfo) != null

    // `unknown`, `null`, `never` and `void` are excluded BY NAME from that conversion, so a member
    // read off any of them stays unresolved rather than silently answering for some CLR type.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.Unknown, "Length", false, null))
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.Void, "Length", false, null))
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.Never, "Length", false, null))
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.Null, "Length", false, null))
}

test "the spellings that are not shapes are stripped before anything is resolved" {
    harness := MemberResolutionDefault()

    // An OBLIVIOUS or BY-REF spelling wraps a type without changing which members it has, so both
    // are unwrapped first and answer exactly as the inner type does.
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(
            new ObliviousTypeInfo(BuiltInTypes.String), "Length", false, null),
        BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(
            new ByRefTypeInfo(BuiltInTypes.String), "Length", false, null),
        BuiltInTypes.Int)

    // A NULLABLE spelling is different: it has a member set of its OWN that answers before the
    // inner type is consulted at all.
    nullableInt := new NullableTypeInfo(BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(nullableInt, "HasValue", false, null), BuiltInTypes.Bool)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(nullableInt, "Value", false, null), BuiltInTypes.Int)
}

test "an ARRAY answers `Length` itself and reaches metadata for everything else" {
    harness := MemberResolutionDefault()
    intArray := new ArrayTypeInfo(BuiltInTypes.Int)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(intArray, "Length", false, null), BuiltInTypes.Int)

    // The array converts to a CLR array type, so `System.Array`'s own members answer too.
    rankAnswer := harness.Resolution.ResolveMember(intArray, "Rank", false, null)
    assert TypeInfoIdentityFacts.AreEqual(rankAnswer, BuiltInTypes.Int)

    // A name nothing claims falls through to the extension surface.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(intArray, "NoSuchMemberAnywhere", false, null))
}

test "a TUPLE answers by position and by element name" {
    harness := MemberResolutionDefault()

    elements := new List<TupleTypeElementInfo>()
    elements.Add(new TupleTypeElementInfo("count", BuiltInTypes.Int))
    elements.Add(new TupleTypeElementInfo(null, BuiltInTypes.String))
    tuple := new TupleTypeInfo(elements)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(tuple, "Item1", false, null), BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(tuple, "Item2", false, null), BuiltInTypes.String)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(tuple, "count", false, null), BuiltInTypes.Int)

    // The inherited `object` surface is reachable on a tuple VALUE, and only on a value.
    toStringAnswer := harness.Resolution.ResolveMember(tuple, "ToString", false, null)
    assert (toStringAnswer as ReflectionMethodInfo) != null
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(tuple, "ToString", true, null))
}

test "an ENUM member read off the enum TYPE is the enum type" {
    harness := MemberResolutionDefault()

    members := new List<EnumMemberInfo>()
    members.Add(new EnumMemberInfo("Red", 1, 1, EnumMemberValueKind.None, null))
    members.Add(new EnumMemberInfo("Green", 2, 1, EnumMemberValueKind.None, null))
    declaration := new EnumDeclarationInfo("Colour", members, EnumType.Int, 1, 1)
    enumType := new EnumTypeInfo(declaration)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(enumType, "Red", true, null), enumType)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(enumType, "Green", true, null), enumType)

    // A name that is not a member is not the enum type.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(enumType, "Blue", true, null))

    // And a member name read off a VALUE is not the enum type either — an enum value's surface is
    // the inherited `object` one.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(enumType, "Red", false, null))
    toStringAnswer := harness.Resolution.ResolveMember(enumType, "ToString", false, null)
    assert (toStringAnswer as ReflectionMethodInfo) != null
}

test "an ANONYMOUS UNION answers its discriminator pair and nothing else" {
    harness := MemberResolutionDefault()

    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.Int)
    arms.Add(BuiltInTypes.String)
    anonymous := new AnonymousUnionTypeInfo(arms)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(anonymous, "Index", false, null), BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(anonymous, "Value", false, null), BuiltInTypes.Object)

    // Everything else reaches the extension surface, which with nothing declared is `unknown` —
    // NOT one of the arms' own members.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(anonymous, "Length", false, null))
}

test "a NEWTYPE answers `Value` with its underlying type" {
    harness := MemberResolutionDefault()

    underlying: TypeReference = new SimpleTypeReference("int")
    newtypeCandidate := new NewtypeInfo("Meters", underlying)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(newtypeCandidate, "Value", false, null), BuiltInTypes.Int)

    // The wrapped type's OWN members are deliberately not offered: a newtype is a distinct type,
    // not an alias, so `meters.ToString()` is `object`'s and `meters.MaxValue` is nothing.
    toStringAnswer := harness.Resolution.ResolveMember(newtypeCandidate, "ToString", false, null)
    assert (toStringAnswer as ReflectionMethodInfo) != null
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(newtypeCandidate, "MaxValue", false, null))
}

test "the SoA table and row surfaces are the columns plus the intrinsics" {
    harness := MemberResolutionDefault()

    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int"), 1, 1))
    columns.Add(new SoaColumnInfo("name", new SimpleTypeReference("string"), 1, 1))
    declaration := new SoaRecordDeclarationInfo("Particles", columns, 1, 1)
    table := new SoaRecordTypeInfo(declaration)
    row := new SoaRowTypeInfo(declaration)

    // A COLUMN read off the TABLE is an ARRAY of the column type; read off a ROW it is the column
    // type itself. That difference is the whole SoA access model.
    columnAnswer := harness.Resolution.ResolveMember(table, "x", false, null)
    columnArray := columnAnswer as ArrayTypeInfo
    assert columnArray != null
    assert TypeInfoIdentityFacts.AreEqual(columnArray.ElementType, BuiltInTypes.Int)

    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(row, "x", false, null), BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(row, "name", false, null), BuiltInTypes.String)

    // A ROW HAS NOTHING BUT ITS COLUMNS — not the intrinsics, not the inherited `object` surface,
    // and not an extension. This is the arm that keeps a row view from escaping.
    assert BuiltInTypes.IsUnknown(harness.Resolution.ResolveMember(row, "length", false, null))
    assert BuiltInTypes.IsUnknown(harness.Resolution.ResolveMember(row, "ToString", false, null))

    // The table's intrinsics are synthesised: they have no declaration anywhere to resolve against.
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(table, "length", false, null), BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        harness.Resolution.ResolveMember(table, "capacity", false, null), BuiltInTypes.Int)

    addAnswer := harness.Resolution.ResolveMember(table, "add", false, null)
    addFunction := addAnswer as FunctionTypeInfo
    assert addFunction != null
    assert addFunction.SyntheticName == "add"

    copyRowAnswer := harness.Resolution.ResolveMember(table, "copyRow", false, null)
    copyRowFunction := copyRowAnswer as FunctionTypeInfo
    assert copyRowFunction != null
    copyRowNames := copyRowFunction.ParameterNames
    assert copyRowNames != null
    assert copyRowNames.Count == 2

    // `wrap` is the table's ONLY static member, and its parameter list is every column as an array
    // plus a length.
    wrapAnswer := harness.Resolution.ResolveMember(table, "wrap", true, null)
    wrapFunction := wrapAnswer as FunctionTypeInfo
    assert wrapFunction != null
    wrapNames := wrapFunction.ParameterNames
    assert wrapNames != null
    assert wrapNames.Count == 3
    assert wrapNames[0] == "x"
    assert wrapNames[1] == "name"
    assert wrapNames[2] == "length"
    assert TypeInfoIdentityFacts.AreEqual(wrapFunction.ReturnType, table)

    // And the intrinsics are INSTANCE members: they are not on the static surface.
    assert BuiltInTypes.IsUnknown(harness.Resolution.ResolveMember(table, "add", true, null))
    assert BuiltInTypes.IsUnknown(harness.Resolution.ResolveMember(table, "x", true, null))
}

test "an unresolved name falls through to the extension surface, with the WRITTEN receiver" {
    harness := MemberResolutionDefault()

    // A source extension on `string`. The receiver `ResolveMember` was given is the built-in
    // `string` spelling, but by the time the fall-through happens the walk has replaced it with a
    // REFLECTION type — the extension surface must still see the written one, or a source extension
    // declared against `string` would never be offered for a string literal.
    parameters := new List<Parameter>()
    parameters.Add(
        new Parameter(
            "self", new SimpleTypeReference("string"), null, false,
            ParameterModifier.None, null, 1, 1, false, null))
    harness.Declared.Add(
        new FunctionDeclaration(
            "Shout", parameters, null, null, null, null, null, Modifiers.Public,
            new List<AttributeNode>(), false, null, false, false, 1, 1))

    answer := harness.Resolution.ResolveMember(BuiltInTypes.String, "Shout", false, "Owner")
    extensionFunction := answer as FunctionTypeInfo
    assert extensionFunction != null
    assert extensionFunction.SourceName == "Shout"

    // The containing type name threads through unchanged — it is read at THIS call.
    assert extensionFunction.SourceContainingType == "Owner"

    // And a name neither metadata nor the extension surface claims is `unknown`.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.String, "NoSuchMemberAnywhere", false, null))
}

test "the external extension scan is reachable through member resolution" {
    harness := MemberResolutionDefault()
    harness.Namespaces.Add("System")
    harness.Assemblies.Add(MemberResolutionCoreAssembly())

    // `AsSpan` is declared on `System.MemoryExtensions`, a static class in the core assembly under
    // an imported namespace. Nothing on `string` itself claims the name, so member resolution must
    // reach the external scan for it.
    answer := harness.Resolution.ResolveMember(BuiltInTypes.String, "AsSpan", false, null)
    assert !BuiltInTypes.IsUnknown(answer)

    // Un-import the namespace and the same name is nothing — the namespace list is LIVE, and it is
    // read through member resolution exactly as it is through the extension surface directly.
    harness.Namespaces.Clear()
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(BuiltInTypes.String, "AsSpan", false, null))
}

test "`AsSpan` on an ARRAY needs `System` imported, and the import is read live" {
    harness := MemberResolutionDefault()
    intArray := new ArrayTypeInfo(BuiltInTypes.Int)

    // THE KNOWN-ARRAY-EXTENSION ARM. It is gated on `System` being imported and answers BEFORE any
    // CLR conversion, so it is the analyzer's own answer rather than metadata's.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(intArray, "AsSpan", false, null))

    harness.Namespaces.Add("System")
    assert !BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(intArray, "AsSpan", false, null))

    // And the arm is INSTANCE-only: `int[].AsSpan` written against the type is not it.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.ResolveMember(intArray, "AsSpan", true, null))
}
