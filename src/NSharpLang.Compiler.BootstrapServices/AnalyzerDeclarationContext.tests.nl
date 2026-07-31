namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar
import NSharpLang.Compiler.TestStubs

class AnalyzerContextTestUnit {
    Package: object?
    Namespace: object?
    Imports: List<object>
    FileImports: List<object>
    Declarations: List<object>

    constructor(declarations: List<object>) {
        Package = null
        Namespace = null
        Imports = new List<object>()
        FileImports = new List<object>()
        Declarations = declarations
    }

    constructor(declarations: List<object>, imports: List<object>) {
        Package = null
        Namespace = null
        Imports = imports
        FileImports = new List<object>()
        Declarations = declarations
    }

    constructor(
        namespaceValue: object?,
        imports: List<object>,
        declarations: List<object>) {
        Package = null
        Namespace = namespaceValue
        Imports = imports
        FileImports = new List<object>()
        Declarations = declarations
    }
}

class AnalyzerContextTestImport {
    Namespace: string
    Alias: string?

    constructor(namespaceName: string) {
        Namespace = namespaceName
        Alias = null
    }
}

class AnalyzerContextTestNamespace {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

// The declaration stubs live in NSharpLang.Compiler.TestStubs (AnalyzerDeclarationContextStubs.tests.nl):
// their simple names must match the real Ast node names for the context's GetType().Name dispatch, and
// keeping them out of NSharpLang.Compiler avoids the tests-enabled-build simple-name collision. These
// factories are the only construction sites; they qualify fully because this file also imports
// NSharpLang.Compiler.Ast, which declares the same three simple names.
func StubClass(name: string): NSharpLang.Compiler.TestStubs.ClassDeclaration {
    return new NSharpLang.Compiler.TestStubs.ClassDeclaration(name, null)
}

func StubClassWithBase(
    name: string,
    baseClass: TypeReference): NSharpLang.Compiler.TestStubs.ClassDeclaration {
    return new NSharpLang.Compiler.TestStubs.ClassDeclaration(name, baseClass)
}

func StubAlias(
    name: string,
    typeReference: TypeReference): NSharpLang.Compiler.TestStubs.TypeAliasDeclaration {
    return new NSharpLang.Compiler.TestStubs.TypeAliasDeclaration(name, typeReference)
}

func StubField(
    name: string,
    typeReference: TypeReference,
    modifiers: int): NSharpLang.Compiler.TestStubs.FieldDeclaration {
    return new NSharpLang.Compiler.TestStubs.FieldDeclaration(
        name,
        typeReference,
        modifiers)
}

func AnalyzerContextDeclarations(first: object): List<object> {
    result := new List<object>()
    result.Add(first)
    return result
}

func AnalyzerContextDeclarationPair(first: object, second: object): List<object> {
    result := AnalyzerContextDeclarations(first)
    result.Add(second)
    return result
}

func AnalyzerContextTypeReferences(first: TypeReference): List<TypeReference> {
    result := new List<TypeReference>()
    result.Add(first)
    return result
}

func AnalyzerContextTypeReferencePair(
    first: TypeReference,
    second: TypeReference): List<TypeReference> {
    result := AnalyzerContextTypeReferences(first)
    result.Add(second)
    return result
}

func AnalyzerContextAssemblies(): List<Assembly> {
    result := new List<Assembly>()
    result.Add(typeof(List<int>).get_Assembly())
    result.Add(typeof(Stack<int>).get_Assembly())
    return result
}

func AnalyzerContextFor(path: string, declarations: List<object>): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    context.AddCompilationUnit(path, new AnalyzerContextTestUnit(declarations))
    return context
}

func AnalyzerContextForImports(
    path: string,
    imports: List<object>): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    context.AddCompilationUnit(
        path,
        new AnalyzerContextTestUnit(new List<object>(), imports))
    return context
}

func AnalyzerContextAddUnit(
    context: AnalyzerDeclarationContext,
    path: string,
    namespaceName: string,
    imports: List<object>,
    declarations: List<object>) {
    context.AddCompilationUnit(
        path,
        new AnalyzerContextTestUnit(
            new AnalyzerContextTestNamespace(namespaceName),
            imports,
            declarations))
}

func AnalyzerContextClass(
    name: string,
    nestedTypes: NestedTypeInfo[]): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        nestedTypes,
        true)
}

func AnalyzerContextTypeParameters(name: string): TypeParameter[] {
    parameters := new TypeParameter[](1)
    parameters[0] = new TypeParameter(name)
    return parameters
}

func AnalyzerContextGenericClass(
    name: string,
    parameterName: string,
    nestedTypes: NestedTypeInfo[]): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        AnalyzerContextTypeParameters(parameterName),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        nestedTypes,
        true)
}

func AnalyzerContextGenericStruct(
    name: string,
    parameterName: string): StructTypeInfo {
    return new StructTypeInfo(
        name,
        1,
        1,
        new TypeReference[](0),
        AnalyzerContextTypeParameters(parameterName),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func AnalyzerContextGenericRecord(
    name: string,
    parameterName: string): RecordTypeInfo {
    return new RecordTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        AnalyzerContextTypeParameters(parameterName),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func AnalyzerContextGenericInterface(
    name: string,
    parameterName: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        AnalyzerContextTypeParameters(parameterName),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
}

func AnalyzerContextAssertOpenParameter(
    context: AnalyzerDeclarationContext,
    owner: TypeInfo,
    name: string) {
    resolved := new TypeInfo()
    assert context.TryResolveTypeForOwner(
        new SimpleTypeReference(name),
        owner,
        null,
        out resolved)
    simple := resolved as SimpleTypeInfo
    assert simple != null
    assert simple.Name == name
}

test "declaration context keeps source identifiers case-sensitive" {
    path := "/tmp/case-sensitive.nl"
    declaration := StubAlias(
        "Widget",
        new SimpleTypeReference("int"))
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarations(declaration))

    exact := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "Widget", out exact)
    assert TypeInfoIdentityFacts.AreEqual(exact.Type, BuiltInTypes.Int)

    wrongCase := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert !context.TryResolveName(path, "widget", out wrongCase)
    assert !wrongCase.Claimed
}

test "project imports are exhausted before runtime imports" {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    sourcePath := "/tmp/my-types-datetime.nl"
    consumerPath := "/tmp/date-consumer.nl"
    AnalyzerContextAddUnit(
        context,
        sourcePath,
        "MyTypes",
        new List<object>(),
        AnalyzerContextDeclarations(StubClass("DateTime")))
    imports := new List<object>()
    imports.Add(new AnalyzerContextTestImport("System"))
    imports.Add(new AnalyzerContextTestImport("MyTypes"))
    AnalyzerContextAddUnit(
        context,
        consumerPath,
        "Consumer",
        imports,
        new List<object>())

    selection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(consumerPath, "DateTime", out selection)
    sourceType := selection.Type as ClassTypeInfo
    assert sourceType != null
    assert context.GetDeclarationFile(selection.Type) == sourcePath
}

test "bare runtime names and generic arity use the assembly scan" {
    path := "/tmp/bare-runtime-types.nl"
    context := AnalyzerContextFor(path, new List<object>())
    dateTimeSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "DateTime", out dateTimeSelection)
    dateTimeType := dateTimeSelection.Type as ReflectionTypeInfo
    assert dateTimeType != null
    assert dateTimeType.Type == typeof(DateTime)

    owner := AnalyzerContextClass("Owner", new NestedTypeInfo[](0))
    context.RegisterCanonicalType(path, "Owner", owner)
    arguments := AnalyzerContextTypeReferences(new SimpleTypeReference("int"))
    stackReference := new GenericTypeReference("Stack", arguments)
    resolvedStack := new TypeInfo()
    assert context.TryResolveTypeForOwner(
        stackReference,
        owner,
        null,
        out resolvedStack)
    stackType := resolvedStack as GenericTypeInfo
    assert stackType != null
    stackDefinition := stackType.GenericDefinition as ReflectionTypeInfo
    assert stackDefinition != null
    assert stackDefinition.Type == typeof(Stack<int>).GetGenericTypeDefinition()
}

test "unique exported lookup skips non-exported declarations" {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    privatePath := "/tmp/private-widget.nl"
    publicPath := "/tmp/public-widget.nl"
    privateWidget := StubClass("Widget")
    privateWidget.Modifiers = 2
    AnalyzerContextAddUnit(
        context,
        privatePath,
        "A",
        new List<object>(),
        AnalyzerContextDeclarations(privateWidget))
    AnalyzerContextAddUnit(
        context,
        publicPath,
        "B",
        new List<object>(),
        AnalyzerContextDeclarations(StubClass("Widget")))

    selection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveUniqueExportedType("Widget", out selection)
    assert selection.FilePath == publicPath
    assert context.GetDeclarationFile(selection.Type) == publicPath
}

test "declaration context terminates mixed source alias cycles" {
    path := "/tmp/alias-cycle.nl"
    first := StubAlias("A", new SimpleTypeReference("B"))
    second := StubAlias("B", new SimpleTypeReference("A"))
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarationPair(first, second))

    selection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert !context.TryResolveName(path, "A", out selection)
    assert selection.Claimed
    assert BuiltInTypes.IsUnknown(selection.Type)
}

test "source aliases do not steal declaration context from their targets" {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    sourceDependencyPath := "/tmp/source-dependency.nl"
    aliasDependencyPath := "/tmp/alias-dependency.nl"
    sourcePath := "/tmp/source-owner.nl"
    aliasPath := "/tmp/source-alias.nl"

    AnalyzerContextAddUnit(
        context,
        sourceDependencyPath,
        "SourceDeps",
        new List<object>(),
        AnalyzerContextDeclarations(StubClass("Dependency")))
    AnalyzerContextAddUnit(
        context,
        aliasDependencyPath,
        "AliasDeps",
        new List<object>(),
        AnalyzerContextDeclarations(StubClass("Dependency")))

    sourceImports := new List<object>()
    sourceImports.Add(new AnalyzerContextTestImport("SourceDeps"))
    sourceType := StubClassWithBase(
        "SourceType",
        new SimpleTypeReference("Dependency"))
    AnalyzerContextAddUnit(
        context,
        sourcePath,
        "Source",
        sourceImports,
        AnalyzerContextDeclarations(sourceType))

    aliasImports := new List<object>()
    aliasImports.Add(new AnalyzerContextTestImport("Source"))
    aliasImports.Add(new AnalyzerContextTestImport("AliasDeps"))
    alias := StubAlias(
        "Alias",
        new SimpleTypeReference("SourceType"))
    AnalyzerContextAddUnit(
        context,
        aliasPath,
        "Alias",
        aliasImports,
        AnalyzerContextDeclarations(alias))

    selection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(aliasPath, "Alias", out selection)
    assert context.GetDeclarationFile(selection.Type) == sourcePath
    cachedSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(aliasPath, "Alias", out cachedSelection)
    assert Object.ReferenceEquals(selection.Type, cachedSelection.Type)
    assert context.GetDeclarationFile(cachedSelection.Type) == sourcePath

    shape := new AnalyzerSourceMemberShape()
    assert context.TryGetSourceMemberShape(selection.Type, null, out shape)
    assert shape.BaseType != null
    assert context.GetDeclarationFile(shape.BaseType) == sourceDependencyPath
}

test "matching primary parameters claim unresolved member types" {
    path := "/tmp/primary-parameter.nl"
    context := AnalyzerContextFor(path, new List<object>())
    owner := AnalyzerContextClass("Owner", new NestedTypeInfo[](0))
    context.RegisterCanonicalType(path, "Owner", owner)
    parameters := new ParameterDeclarationInfo[](1)
    parameters[0] = new ParameterDeclarationInfo(
        "Value",
        new SimpleTypeReference("DefinitelyMissingAnalyzerType"),
        1,
        1)
    memberType := BuiltInTypes.Int as TypeInfo
    assert context.TryResolvePrimaryParameter(
        owner,
        parameters,
        "Value",
        null,
        out memberType)
    assert BuiltInTypes.IsUnknown(memberType)
}

test "open generic owner members keep lexical type parameters" {
    path := "/tmp/open-generic-owners.nl"
    context := AnalyzerContextFor(path, new List<object>())
    classOwner := AnalyzerContextGenericClass(
        "GenericClass",
        "TClass",
        new NestedTypeInfo[](0))
    structOwner := AnalyzerContextGenericStruct("GenericStruct", "TStruct")
    recordOwner := AnalyzerContextGenericRecord("GenericRecord", "TRecord")
    interfaceOwner := AnalyzerContextGenericInterface(
        "GenericInterface",
        "TInterface")
    context.RegisterCanonicalType(path, "GenericClass", classOwner)
    context.RegisterCanonicalType(path, "GenericStruct", structOwner)
    context.RegisterCanonicalType(path, "GenericRecord", recordOwner)
    context.RegisterCanonicalType(path, "GenericInterface", interfaceOwner)

    AnalyzerContextAssertOpenParameter(context, classOwner, "TClass")
    AnalyzerContextAssertOpenParameter(context, structOwner, "TStruct")
    AnalyzerContextAssertOpenParameter(context, recordOwner, "TRecord")
    AnalyzerContextAssertOpenParameter(context, interfaceOwner, "TInterface")

    closedSubstitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    closedSubstitution["TClass"] = BuiltInTypes.Int
    closed := new TypeInfo()
    assert context.TryResolveTypeForOwner(
        new SimpleTypeReference("TClass"),
        classOwner,
        closedSubstitution,
        out closed)
    assert TypeInfoIdentityFacts.AreEqual(closed, BuiltInTypes.Int)
}

test "nested owners see own nested types and ancestor parameters and siblings" {
    path := "/tmp/nested-open-generic-owner.nl"
    context := AnalyzerContextFor(path, new List<object>())
    leaf := AnalyzerContextClass("Leaf", new NestedTypeInfo[](0))
    innerNested := new NestedTypeInfo[](1)
    innerNested[0] = new NestedTypeInfo("Leaf", leaf)
    inner := AnalyzerContextGenericClass("Inner", "TInner", innerNested)
    sibling := AnalyzerContextClass("Sibling", new NestedTypeInfo[](0))
    outerNested := new NestedTypeInfo[](2)
    outerNested[0] = new NestedTypeInfo("Sibling", sibling)
    outerNested[1] = new NestedTypeInfo("Inner", inner)
    outer := AnalyzerContextGenericClass("Outer", "TOuter", outerNested)
    context.RegisterCanonicalType(path, "Outer", outer)

    AnalyzerContextAssertOpenParameter(context, inner, "TInner")
    AnalyzerContextAssertOpenParameter(context, inner, "TOuter")

    ownNested := new TypeInfo()
    assert context.TryResolveTypeForOwner(
        new SimpleTypeReference("Leaf"),
        inner,
        null,
        out ownNested)
    assert TypeInfoIdentityFacts.AreEqual(ownNested, leaf)

    ancestorSibling := new TypeInfo()
    assert context.TryResolveTypeForOwner(
        new SimpleTypeReference("Sibling"),
        inner,
        null,
        out ancestorSibling)
    assert TypeInfoIdentityFacts.AreEqual(ancestorSibling, sibling)
}

test "readonly member eligibility follows closed generic bases and terminal shadows" {
    path := "/tmp/readonly-closed-generic-base.nl"
    baseDeclaration := StubClass("Base")
    baseDeclaration.TypeParameters.Add(new TypeParameter("T"))
    baseDeclaration.Members.Add(StubField(
        "Value",
        new SimpleTypeReference("T"),
        512))

    baseArguments := AnalyzerContextTypeReferences(
        new SimpleTypeReference("int"))
    derivedDeclaration := StubClassWithBase(
        "Derived",
        new GenericTypeReference("Base", baseArguments))
    shadowDeclaration := StubClassWithBase(
        "Shadow",
        new GenericTypeReference("Base", baseArguments))
    shadowDeclaration.Members.Add(StubField(
        "Value",
        new SimpleTypeReference("int"),
        0))
    declarations := new List<object>()
    declarations.Add(baseDeclaration)
    declarations.Add(derivedDeclaration)
    declarations.Add(shadowDeclaration)
    context := AnalyzerContextFor(path, declarations)

    derivedSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "Derived", out derivedSelection)
    fieldName := ""
    claimed := false
    assert context.TryFindReadonlyField(
        derivedSelection.Type,
        "Value",
        false,
        out fieldName,
        out claimed)
    assert claimed
    assert fieldName == "Value"

    staticName := ""
    staticClaimed := false
    assert !context.TryFindReadonlyField(
        derivedSelection.Type,
        "Value",
        true,
        out staticName,
        out staticClaimed)
    assert staticClaimed

    shadowSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "Shadow", out shadowSelection)
    shadowName := ""
    shadowClaimed := false
    assert !context.TryFindReadonlyField(
        shadowSelection.Type,
        "Value",
        false,
        out shadowName,
        out shadowClaimed)
    assert shadowClaimed

    missingName := ""
    missingClaimed := true
    assert !context.TryFindReadonlyField(
        derivedSelection.Type,
        "Missing",
        false,
        out missingName,
        out missingClaimed)
    assert !missingClaimed
}

test "source aliases preserve the target member declaration identity" {
    path := "/tmp/alias-member-identity.nl"
    person := StubClass("Person")
    person.Members.Add(StubField(
        "Name",
        new SimpleTypeReference("string"),
        0))
    alias := StubAlias(
        "PersonAlias",
        new SimpleTypeReference("Person"))
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarationPair(person, alias))

    personSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    aliasSelection := new AnalyzerSourceTypeSelection(
        BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "Person", out personSelection)
    assert context.TryResolveName(path, "PersonAlias", out aliasSelection)
    assert Object.ReferenceEquals(personSelection.Type, aliasSelection.Type)

    directMember := new AnalyzerMemberSelection()
    aliasMember := new AnalyzerMemberSelection()
    assert context.TryFindMember(
        personSelection.Type, "Name", out directMember)
    assert context.TryFindMember(
        aliasSelection.Type, "Name", out aliasMember)
    assert directMember.Member != null
    assert Object.ReferenceEquals(directMember.Member, aliasMember.Member)
    assert Object.ReferenceEquals(personSelection.Type, aliasMember.Owner)
}

test "readonly selection crosses imported closed generic bases without reflection fallback" {
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    providerPath := "/tmp/readonly-models.nl"
    consumerPath := "/tmp/readonly-consumer.nl"

    baseDeclaration := StubClass("Base")
    baseDeclaration.TypeParameters.Add(new TypeParameter("T"))
    baseDeclaration.Members.Add(StubField(
        "Value",
        new SimpleTypeReference("T"),
        512))
    derivedArguments := AnalyzerContextTypeReferences(
        new SimpleTypeReference("T"))
    derivedDeclaration := StubClassWithBase(
        "Derived",
        new GenericTypeReference("Base", derivedArguments))
    derivedDeclaration.TypeParameters.Add(new TypeParameter("T"))
    declarations := new List<object>()
    declarations.Add(baseDeclaration)
    declarations.Add(derivedDeclaration)
    AnalyzerContextAddUnit(
        context,
        providerPath,
        "Models",
        new List<object>(),
        declarations)

    imports := new List<object>()
    imports.Add(new AnalyzerContextTestImport("Models"))
    AnalyzerContextAddUnit(
        context,
        consumerPath,
        "Consumer",
        imports,
        new List<object>())

    closedArguments := AnalyzerContextTypeReferences(
        new SimpleTypeReference("int"))
    closedReference := new GenericTypeReference(
        "Derived", closedArguments)
    closedDerived := new TypeInfo()
    closedDerived = context.ResolveTypeReference(
        closedReference,
        consumerPath,
        null,
        null)
    closedGeneric := closedDerived as GenericTypeInfo
    assert closedGeneric != null
    assert closedGeneric.TypeArguments.Count == 1
    assert TypeInfoIdentityFacts.AreEqual(
        closedGeneric.TypeArguments[0], BuiltInTypes.Int)

    fieldName := ""
    claimed := false
    assert context.TryFindReadonlyField(
        closedDerived,
        "Value",
        false,
        out fieldName,
        out claimed)
    assert claimed
    assert fieldName == "Value"
}

test "file import alias type ownership preserves nested visibility and claimed failures" {
    providerPath := "/tmp/file-alias-provider.nl"
    consumerPath := "/tmp/file-alias-consumer.nl"
    samePackagePath := "/tmp/file-alias-same-package.nl"
    context := new AnalyzerDeclarationContext()
    context.Reset("/tmp", AnalyzerContextAssemblies())
    AnalyzerContextAddUnit(
        context,
        providerPath,
        "Provider",
        new List<object>(),
        new List<object>())
    AnalyzerContextAddUnit(
        context,
        consumerPath,
        "Consumer",
        new List<object>(),
        new List<object>())
    AnalyzerContextAddUnit(
        context,
        samePackagePath,
        "Provider",
        new List<object>(),
        new List<object>())

    visible := AnalyzerContextClass("Visible", new NestedTypeInfo[](0))
    hidden := AnalyzerContextClass("hidden", new NestedTypeInfo[](0))
    nested := new NestedTypeInfo[](2)
    nested[0] = new NestedTypeInfo("Visible", visible, true)
    nested[1] = new NestedTypeInfo("hidden", hidden, false)
    outer := AnalyzerContextClass("Outer", nested)
    context.RegisterCanonicalType(providerPath, "Outer", outer)

    symbols := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    symbols["Outer"] = outer
    symbolsByAlias := new Dictionary<string, Dictionary<string, TypeInfo>>(
        StringComparer.Ordinal)
    symbolsByAlias["dep"] = symbols
    declarations := new Dictionary<string, SymbolDeclaration>(StringComparer.Ordinal)
    declarations["Outer"] = new SymbolDeclaration(
        "Outer", providerPath, 1, 1, "class")
    declarationsByAlias := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(
        StringComparer.Ordinal)
    declarationsByAlias["dep"] = declarations

    selectedType := BuiltInTypes.Unknown as TypeInfo
    selectedDeclaration: SymbolDeclaration? = null
    claimed := false
    assert context.TryResolveFileImportAliasType(
        "dep.Outer.Visible",
        consumerPath,
        symbolsByAlias,
        declarationsByAlias,
        out selectedType,
        out selectedDeclaration,
        out claimed)
    assert claimed
    assert Object.ReferenceEquals(selectedType, visible)
    assert selectedDeclaration != null
    assert selectedDeclaration.Name == "Outer"

    selectedType = BuiltInTypes.Int
    selectedDeclaration = declarations["Outer"]
    claimed = false
    assert !context.TryResolveFileImportAliasType(
        "dep.Outer.hidden",
        consumerPath,
        symbolsByAlias,
        declarationsByAlias,
        out selectedType,
        out selectedDeclaration,
        out claimed)
    assert claimed
    assert BuiltInTypes.IsUnknown(selectedType)
    assert selectedDeclaration == null

    assert !context.TryResolveFileImportAliasType(
        "dep.Outer.hidden",
        samePackagePath,
        symbolsByAlias,
        declarationsByAlias,
        out selectedType,
        out selectedDeclaration,
        out claimed)
    assert claimed
    assert BuiltInTypes.IsUnknown(selectedType)
    assert selectedDeclaration == null

    assert context.TryResolveFileImportAliasType(
        "dep.Outer.hidden",
        providerPath,
        symbolsByAlias,
        declarationsByAlias,
        out selectedType,
        out selectedDeclaration,
        out claimed)
    assert Object.ReferenceEquals(selectedType, hidden)

    claimed = true
    assert !context.TryResolveFileImportAliasType(
        "missing.Outer",
        consumerPath,
        symbolsByAlias,
        declarationsByAlias,
        out selectedType,
        out selectedDeclaration,
        out claimed)
    assert !claimed
}

test "declaration context binds runtime generic definitions only at exact arity" {
    path := "/tmp/runtime-generic.nl"
    imports := new List<object>()
    imports.Add(new AnalyzerContextTestImport("System.Collections.Generic"))
    context := AnalyzerContextForImports(path, imports)

    intReference := new SimpleTypeReference("int")
    exactArguments := AnalyzerContextTypeReferences(intReference)
    exactReference := new GenericTypeReference("List", exactArguments)
    listOfInt := new TypeInfo()
    listOfInt = context.ResolveTypeReference(
        exactReference,
        path,
        null,
        null)
    exact := listOfInt as GenericTypeInfo
    assert exact != null
    assert exact.GenericDefinition != null

    stringReference := new SimpleTypeReference("string")
    wrongArguments := AnalyzerContextTypeReferencePair(
        intReference,
        stringReference)
    wrongReference := new GenericTypeReference("List", wrongArguments)
    listWithWrongArity := new TypeInfo()
    listWithWrongArity = context.ResolveTypeReference(
        wrongReference,
        path,
        null,
        null)
    wrong := listWithWrongArity as GenericTypeInfo
    assert wrong != null
    assert wrong.GenericDefinition == null
}

test "runtime generic arity retries an imported non-generic metadata head" {
    path := "/tmp/runtime-generic-collision.nl"
    imports := new List<object>()
    imports.Add(new AnalyzerContextTestImport("System"))
    context := AnalyzerContextForImports(path, imports)
    arguments := AnalyzerContextTypeReferencePair(
        new SimpleTypeReference("int"),
        new SimpleTypeReference("string"))
    reference := new GenericTypeReference("ValueTuple", arguments)
    resolved := new TypeInfo()
    resolved = context.ResolveTypeReference(reference, path, null, null)
    generic := resolved as GenericTypeInfo
    assert generic != null
    definition := generic.GenericDefinition as ReflectionTypeInfo
    assert definition != null
    assert definition.Type == typeof(ValueTuple<int, string>).GetGenericTypeDefinition()

    barePath := "/tmp/runtime-generic-bare-valuetuple.nl"
    bareContext := AnalyzerContextFor(barePath, new List<object>())
    bareResolved := new TypeInfo()
    bareResolved = bareContext.ResolveTypeReference(
        reference,
        barePath,
        null,
        null)
    bareGeneric := bareResolved as GenericTypeInfo
    assert bareGeneric != null
    assert bareGeneric.GenericDefinition != null
}

test "runtime Result structural members preserve nominal source arguments" {
    context := new AnalyzerDeclarationContext()
    sourceOk := AnalyzerContextClass("SourceOk", new NestedTypeInfo[](0))
    arguments := new List<TypeInfo>()
    arguments.Add(sourceOk)
    arguments.Add(BuiltInTypes.String)
    resultDefinition := TypeOfCreateBuilder(
        "NSharpLang.Runtime.Result`2",
        "NSharpLang.Runtime",
        2)
    resultType := new GenericTypeInfo(
        "Result",
        arguments,
        new ReflectionTypeInfo(resultDefinition))

    memberType := BuiltInTypes.Unknown as TypeInfo
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "OkValue", out memberType)
    assert Object.ReferenceEquals(memberType, sourceOk)
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "OkValueUnchecked", out memberType)
    assert Object.ReferenceEquals(memberType, sourceOk)
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "ErrValue", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.String)
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "ErrValueUnchecked", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.String)
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "IsOk", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Bool)
    assert context.TryResolveKnownGenericStructuralMember(
        resultType, "IsErr", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Bool)
    assert !context.TryResolveKnownGenericStructuralMember(
        resultType, "Missing", out memberType)

    impostor := new GenericTypeInfo(
        "Result",
        arguments,
        new ReflectionTypeInfo(
            typeof(ValueTuple<int, string>).GetGenericTypeDefinition()))
    assert !context.TryResolveKnownGenericStructuralMember(
        impostor, "OkValue", out memberType)
}

test "runtime span structural properties resolve without constructing mixed reflection types" {
    context := new AnalyzerDeclarationContext()
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Byte)

    spanType := new GenericTypeInfo(
        "Span",
        arguments,
        new ReflectionTypeInfo(
            typeof(Span<byte>).GetGenericTypeDefinition()))
    memberType := BuiltInTypes.Unknown as TypeInfo
    assert context.TryResolveKnownGenericStructuralMember(
        spanType, "Length", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Int)
    assert context.TryResolveKnownGenericStructuralMember(
        spanType, "IsEmpty", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Bool)
    assert context.TryResolveKnownGenericStructuralMember(
        spanType, "ptr", out memberType)
    spanPointer := memberType as ReflectionTypeInfo
    assert spanPointer != null
    assert spanPointer.Type.get_IsPointer()
    spanPointerElement := spanPointer.Type.GetElementType()
    assert spanPointerElement != null
    assert spanPointerElement.get_FullName() == "System.Void"
    assert !context.TryResolveKnownGenericStructuralMember(
        spanType, "Missing", out memberType)

    readOnlySpanType := new GenericTypeInfo(
        "ReadOnlySpan",
        arguments,
        new ReflectionTypeInfo(
            typeof(ReadOnlySpan<byte>).GetGenericTypeDefinition()))
    assert context.TryResolveKnownGenericStructuralMember(
        readOnlySpanType, "Length", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Int)
    assert context.TryResolveKnownGenericStructuralMember(
        readOnlySpanType, "IsEmpty", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Bool)
    assert context.TryResolveKnownGenericStructuralMember(
        readOnlySpanType, "ptr", out memberType)
    readOnlySpanPointer := memberType as ReflectionTypeInfo
    assert readOnlySpanPointer != null
    assert readOnlySpanPointer.Type.get_IsPointer()
    readOnlySpanPointerElement := readOnlySpanPointer.Type.GetElementType()
    assert readOnlySpanPointerElement != null
    assert readOnlySpanPointerElement.get_FullName() == "System.Void"

    impostor := new GenericTypeInfo(
        "Span",
        arguments,
        new ReflectionTypeInfo(
            typeof(List<byte>).GetGenericTypeDefinition()))
    assert !context.TryResolveKnownGenericStructuralMember(
        impostor, "Length", out memberType)
    assert !context.TryResolveKnownGenericStructuralMember(
        impostor, "ptr", out memberType)
}

test "runtime read-only collection count resolves across inherited interface shape" {
    context := new AnalyzerDeclarationContext()
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    memberType := BuiltInTypes.Unknown as TypeInfo

    collectionType := new GenericTypeInfo(
        "IReadOnlyCollection",
        arguments,
        new ReflectionTypeInfo(
            typeof(IReadOnlyCollection<string>).GetGenericTypeDefinition()))
    assert context.TryResolveKnownGenericStructuralMember(
        collectionType, "Count", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Int)

    listType := new GenericTypeInfo(
        "IReadOnlyList",
        arguments,
        new ReflectionTypeInfo(
            typeof(IReadOnlyList<string>).GetGenericTypeDefinition()))
    assert context.TryResolveKnownGenericStructuralMember(
        listType, "Count", out memberType)
    assert TypeInfoIdentityFacts.AreEqual(memberType, BuiltInTypes.Int)
    assert !context.TryResolveKnownGenericStructuralMember(
        listType, "Length", out memberType)

    impostor := new GenericTypeInfo(
        "IReadOnlyList",
        arguments,
        new ReflectionTypeInfo(
            typeof(List<string>).GetGenericTypeDefinition()))
    assert !context.TryResolveKnownGenericStructuralMember(
        impostor, "Count", out memberType)
}

test "runtime array AsSpan extension preserves element identity and System import scope" {
    context := new AnalyzerDeclarationContext()
    sourceElement := AnalyzerContextClass(
        "ArrayExtensionSourceElement", new NestedTypeInfo[](0))
    arrayType := new ArrayTypeInfo(sourceElement)
    memberType := BuiltInTypes.Unknown as TypeInfo

    assert !context.TryResolveKnownArrayExtensionMember(
        arrayType, "AsSpan", false, out memberType)
    assert !context.TryResolveKnownArrayExtensionMember(
        arrayType, "Missing", true, out memberType)
    assert context.TryResolveKnownArrayExtensionMember(
        arrayType, "AsSpan", true, out memberType)

    group := memberType as NSharpMethodGroupInfo
    assert group != null
    functions := NSharpMethodGroupInfoFactory.GetFunctions(group)
    assert functions.Count == 2
    assert functions[0].ParameterTypes != null
    assert functions[0].ParameterTypes.Count == 0
    assert functions[1].ParameterTypes != null
    assert functions[1].ParameterTypes.Count == 2
    assert TypeInfoIdentityFacts.AreEqual(
        functions[1].ParameterTypes[0], BuiltInTypes.Int)
    assert TypeInfoIdentityFacts.AreEqual(
        functions[1].ParameterTypes[1], BuiltInTypes.Int)

    spanType := functions[0].ReturnType as GenericTypeInfo
    assert spanType != null
    assert spanType.TypeArguments.Count == 1
    assert TypeInfoIdentityFacts.AreEqual(
        spanType.TypeArguments[0], sourceElement)
    spanDefinition := spanType.GenericDefinition as ReflectionTypeInfo
    assert spanDefinition != null
    assert spanDefinition.Type
        == typeof(Span<int>).GetGenericTypeDefinition()
}

test "runtime interface method resolution includes inherited IDisposable members" {
    context := new AnalyzerDeclarationContext()
    memberType := BuiltInTypes.Unknown as TypeInfo
    runtimeTypeOwner := typeof(Type)
    runtimeOwnerDefinition := TypeOfRequiredRuntimeType(
        runtimeTypeOwner, "System.Buffers.IMemoryOwner`1")
    runtimeListDefinition := TypeOfRequiredRuntimeType(
        runtimeTypeOwner, "System.Collections.Generic.List`1")
    runtimeDisposable := TypeOfRequiredRuntimeType(
        runtimeTypeOwner, "System.IDisposable")
    runtimeArguments := new Type[](1)
    runtimeArguments[0] = typeof(byte)
    runtimeOwner := runtimeOwnerDefinition.MakeGenericType(runtimeArguments)
    runtimeList := runtimeListDefinition.MakeGenericType(runtimeArguments)
    resolved := context.TryResolveRuntimeInterfaceMethodMember(
        runtimeOwner, "Dispose", false, out memberType)
    assert resolved
    group := memberType as ReflectionMethodGroupInfo
    assert group != null
    assert group.Methods.Length == 1
    assert group.Methods[0].get_Name() == "Dispose"
    assert group.Methods[0].get_DeclaringType() == runtimeDisposable

    resolved = context.TryResolveRuntimeInterfaceMethodMember(
        runtimeList, "Dispose", false, out memberType)
    assert !resolved
    resolved = context.TryResolveRuntimeInterfaceMethodMember(
        runtimeOwner, "Missing", false, out memberType)
    assert !resolved

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        metadataContext := scan.Context
        assert metadataContext != null
        memoryAssembly := metadataContext.LoadFromAssemblyName("System.Memory")
        metadataOwner := memoryAssembly.GetType("System.Buffers.IMemoryOwner`1")
        assert metadataOwner != null
        resolved = context.TryResolveRuntimeInterfaceMethodMember(
            metadataOwner, "Dispose", false, out memberType)
        assert resolved
        metadataGroup := memberType as ReflectionMethodGroupInfo
        assert metadataGroup != null
        assert metadataGroup.Methods.Length == 1
        assert metadataGroup.Methods[0].get_Name() == "Dispose"
        assert metadataGroup.Methods[0].get_DeclaringType() != null
        assert metadataGroup.Methods[0].get_DeclaringType().FullName
            == "System.IDisposable"
    } finally {
        scan.Dispose()
    }
}

// ---------------------------------------------------------------------------------------------
// 017 slice 4 — the alias-resolution owner. `Analyzer.cs`'s ResolveTypeAlias moved here whole once
// DeclareType started registering the AliasTypeInfo instance it builds, so the alias decision is a
// declaration-context fact instead of a scope-stack walk through the C# TypeReference engine.
// ---------------------------------------------------------------------------------------------

test "017 slice 4: registering a declared alias is an instance fact and leaves the canonical name entry alone" {
    path := "/tmp/s4-alias-register.nl"
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarations(StubAlias("Meters", new SimpleTypeReference("int"))))
    alias := new AliasTypeInfo(new SimpleTypeReference("int"))

    assert !context.ContainsSourceType(alias)
    assert context.GetDeclarationFile(alias) == null

    context.RegisterDeclaredAlias(path, alias)

    assert context.ContainsSourceType(alias)
    assert context.GetDeclarationFile(alias) == path

    // Name lookup is UNCHANGED by the registration: the alias NAME still answers the RESOLVED
    // target the context computes for the declaration, never the AliasTypeInfo instance.
    selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveName(path, "Meters", out selection)
    assert BuiltInTypes.Is(selection.Type, BuiltInTypes.Int)
    assert selection.Type as AliasTypeInfo == null

    canonical := BuiltInTypes.Unknown as TypeInfo
    assert context.TryGetCanonicalType(path, "Meters", out canonical)
    assert BuiltInTypes.Is(canonical, BuiltInTypes.Int)
    assert canonical as AliasTypeInfo == null

    // A second, distinct instance over the same aliased type is a different fact: identity is by
    // INSTANCE, which is the whole point of the unification.
    twin := new AliasTypeInfo(new SimpleTypeReference("int"))
    assert !context.ContainsSourceType(twin)
}

test "017 slice 4: an owned alias resolves to its target and an unowned alias is transparent" {
    path := "/tmp/s4-alias-resolve.nl"
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarations(StubClass("Widget")))

    unowned := new AliasTypeInfo(new SimpleTypeReference("int")) as TypeInfo
    assert context.ResolveDeclaredAlias(unowned) == unowned

    owned := new AliasTypeInfo(new SimpleTypeReference("int"))
    context.RegisterDeclaredAlias(path, owned)
    assert BuiltInTypes.Is(context.ResolveDeclaredAlias(owned), BuiltInTypes.Int)

    // The aliased reference is resolved against the alias's OWN declaring file, so a source name
    // declared there resolves to that file's type.
    sourceAlias := new AliasTypeInfo(new SimpleTypeReference("Widget"))
    context.RegisterDeclaredAlias(path, sourceAlias)
    resolvedWidget := context.ResolveDeclaredAlias(sourceAlias) as ClassTypeInfo
    assert resolvedWidget != null
    assert resolvedWidget.Name == "Widget"

    // Array / nullable / generic shells over the alias target are rebuilt, not flattened.
    arrayAlias := new AliasTypeInfo(
        new ArrayTypeReference(new SimpleTypeReference("int")))
    context.RegisterDeclaredAlias(path, arrayAlias)
    resolvedArray := context.ResolveDeclaredAlias(arrayAlias) as ArrayTypeInfo
    assert resolvedArray != null
    assert BuiltInTypes.Is(resolvedArray.ElementType, BuiltInTypes.Int)

    nullableAlias := new AliasTypeInfo(
        new NullableTypeReference(new SimpleTypeReference("string")))
    context.RegisterDeclaredAlias(path, nullableAlias)
    resolvedNullable := context.ResolveDeclaredAlias(nullableAlias) as NullableTypeInfo
    assert resolvedNullable != null
    assert BuiltInTypes.Is(resolvedNullable.InnerType, BuiltInTypes.String)
}

test "017 slice 4: an alias chain walks to a fixed point and a self-referential alias answers unknown" {
    path := "/tmp/s4-alias-chain.nl"
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarationPair(
            StubAlias("Meters", new SimpleTypeReference("int")),
            StubAlias("Distance", new SimpleTypeReference("Meters"))))

    // `type Chain = Distance` where `Distance` is itself an alias declaration: the answer is the
    // END of the chain, not the next link.
    chain := new AliasTypeInfo(new SimpleTypeReference("Distance"))
    context.RegisterDeclaredAlias(path, chain)
    assert BuiltInTypes.Is(context.ResolveDeclaredAlias(chain), BuiltInTypes.Int)

    // A registration that makes an alias resolve back to ITSELF terminates on the reference-identity
    // cycle set and answers `unknown` — the rule the C# owner stated with a
    // HashSet<AliasTypeInfo>(ReferenceEqualityComparer.Instance).
    loopPath := "/tmp/s4-alias-loop.nl"
    loopContext := AnalyzerContextFor(
        loopPath,
        AnalyzerContextDeclarations(StubAlias("Loop", new SimpleTypeReference("Loop"))))
    loop := new AliasTypeInfo(new SimpleTypeReference("Loop"))
    loopContext.RegisterCanonicalType(loopPath, "Loop", loop)
    assert BuiltInTypes.IsUnknown(loopContext.ResolveDeclaredAlias(loop))
}

test "017 slice 4: the oblivious wrapper is transparent and every other TypeInfo family is its own answer" {
    path := "/tmp/s4-alias-oblivious.nl"
    context := AnalyzerContextFor(
        path,
        AnalyzerContextDeclarations(StubClass("Widget")))

    alias := new AliasTypeInfo(new SimpleTypeReference("int"))
    context.RegisterDeclaredAlias(path, alias)

    assert BuiltInTypes.Is(
        context.ResolveDeclaredAlias(new ObliviousTypeInfo(alias)),
        BuiltInTypes.Int)
    assert BuiltInTypes.Is(
        context.ResolveDeclaredAlias(
            new ObliviousTypeInfo(new ObliviousTypeInfo(alias))),
        BuiltInTypes.Int)
    assert BuiltInTypes.Is(
        context.ResolveDeclaredAlias(new ObliviousTypeInfo(BuiltInTypes.String)),
        BuiltInTypes.String)

    // Non-alias, non-oblivious values are returned by IDENTITY — no re-resolution, no copy.
    simple := new SimpleTypeInfo("int") as TypeInfo
    assert context.ResolveDeclaredAlias(simple) == simple
    array := new ArrayTypeInfo(BuiltInTypes.Int) as TypeInfo
    assert context.ResolveDeclaredAlias(array) == array
    nullable := new NullableTypeInfo(BuiltInTypes.Int) as TypeInfo
    assert context.ResolveDeclaredAlias(nullable) == nullable
    declaredNewtype := new NewtypeInfo("Meters", new SimpleTypeReference("int")) as TypeInfo
    assert context.ResolveDeclaredAlias(declaredNewtype) == declaredNewtype
    unknown := BuiltInTypes.Unknown as TypeInfo
    assert context.ResolveDeclaredAlias(unknown) == unknown

    // An alias NESTED inside another family is NOT reached — the owner normalizes the value it is
    // handed, it does not rewrite type arguments.
    wrapped := new ArrayTypeInfo(alias) as TypeInfo
    assert context.ResolveDeclaredAlias(wrapped) == wrapped
}

test "an instance method hides a same-named extension method on surrogate receivers" {
    context := new AnalyzerDeclarationContext()

    // The witness: `Dictionary<K, V>` declares both `Remove` arities itself, so the BCL
    // `CollectionExtensions.Remove(key, out value)` must never answer for a dictionary receiver
    // whose exact CLR type could not be built.
    assert context.HasRuntimeInstanceMethod(typeof(Dictionary<string, object>), "Remove")
    assert context.HasRuntimeInstanceMethod(typeof(Dictionary<string, object>), "ContainsKey")
    assert context.HasRuntimeInstanceMethod(typeof(List<object>), "Contains")

    // A name the receiver does NOT declare stays open to extensions — `GetValueOrDefault` is
    // exactly such an extension, and blocking it would be the opposite bug.
    assert !context.HasRuntimeInstanceMethod(typeof(Dictionary<string, object>), "GetValueOrDefault")
    assert !context.HasRuntimeInstanceMethod(typeof(List<object>), "Select")

    // Statics never hide an extension: an extension call has a receiver, a static call does not.
    assert !context.HasRuntimeInstanceMethod(typeof(string), "Join")
    assert context.HasRuntimeInstanceMethod(typeof(string), "StartsWith")

    // Interfaces need the INHERITED surface walked explicitly; `Type.GetMethods` omits it.
    // `IReadOnlyCollection<T>` declares only `Count`, and inherits `GetEnumerator` from
    // `IEnumerable<T>` — so the inherited name is only found when that walk happens.
    readOnly := typeof(IReadOnlyCollection<int>)
    assert context.HasRuntimeInstanceMethod(readOnly, "get_Count")
    assert context.HasRuntimeInstanceMethod(readOnly, "GetEnumerator")
    assert !context.HasRuntimeInstanceMethod(readOnly, "Remove")
}

test "a dictionary keyed on a source-declared enum removes by key alone" {
    // The production shape this fix exists for: `Dictionary<string, NullState>` has no closed CLR
    // type because `NullState` is source-declared, so this call is checked against an unmodelled
    // receiver. It must compile, return the removal verdict, and drop the entry.
    states := new Dictionary<string, NullState>(StringComparer.Ordinal)
    states["x"] = NullState.NotNull
    states["x.y"] = NullState.MaybeNull

    assert states.Remove("x")
    assert !states.ContainsKey("x")
    assert states.Count == 1
    assert !states.Remove("x")
    assert states.Remove("x.y")
    assert states.Count == 0
}
