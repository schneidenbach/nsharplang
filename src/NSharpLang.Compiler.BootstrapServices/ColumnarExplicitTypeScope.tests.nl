namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

func ExactTypeScope(
    sources: string[],
    fileNames: string[],
    activeSourceFileId: int): ColumnarBindingScopeFacts {
    scope := ColumnarBindingScopeFacts.Create(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        ExternalEmptyEnums(),
        ExternalEmptyStructs(),
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null)
    scope.PrepareExternalTypeBindings(null)
    return scope.ForSourceFile(activeSourceFileId)
}

func ExactTypeSingleScope(source: string): ColumnarBindingScopeFacts {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = source
    fileNames[0] = "exact-type.nl"
    return ExactTypeScope(sources, fileNames, 0)
}

func ExactTypeDefinition(
    builder: TypeBuilder,
    declaredName: string): ColumnarStructDef {
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        declaredName)
}

func ExactTypeBindings(
    definitions: List<ColumnarStructDef>): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    return bindings
}

func ExactTypeEmptyBindings(): ColumnarFragmentBindings {
    return ExactTypeBindings(new List<ColumnarStructDef>())
}

func ExactTypeProgram(
    sources: string[],
    fileNames: string[]): ColumnarProgramInput {
    program := ColumnarProgramInput.CreateFromSourceFiles(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        new List<ColumnarFunctionInput>(),
        ExternalEmptyEnums(),
        ExternalEmptyStructs(),
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null)
    program.PrepareExternalTypeBindings(null)
    return program
}

func ExactTypeResolutionBindings(
    definitions: IEnumerable<ColumnarStructDef>): ColumnarFragmentBindings {
    return ColumnarFragmentBindings.CreateTypeResolutionBindings(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        definitions,
        new ColumnarUnionDef[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal))
}

func ExactTypeAssertResolved(
    scope: ColumnarBindingScopeFacts,
    bindings: ColumnarFragmentBindings,
    canonical: string,
    expected: Type) {
    resolved := typeof(object)
    assert scope.TryResolveExactExplicitType(canonical, bindings, out resolved)
    assert resolved == expected
}

func ExactTypeAssertRejected(
    scope: ColumnarBindingScopeFacts,
    bindings: ColumnarFragmentBindings,
    canonical: string) {
    resolved := typeof(object)
    assert !scope.TryResolveExactExplicitType(canonical, bindings, out resolved)
    assert resolved == typeof(object)
}

test "exact explicit type scope resolves language builtins arrays and external names" {
    scope := ExactTypeSingleScope(
        "import System\nimport System.Text\nimport System.IO\n")
    bindings := ExactTypeEmptyBindings()

    ExactTypeAssertResolved(scope, bindings, "int", typeof(int))
    ExactTypeAssertResolved(scope, bindings, "long", typeof(long))
    ExactTypeAssertResolved(scope, bindings, "uint", typeof(uint))
    ExactTypeAssertResolved(scope, bindings, "ulong", typeof(ulong))
    ExactTypeAssertResolved(scope, bindings, "short", typeof(short))
    ExactTypeAssertResolved(scope, bindings, "ushort", typeof(ushort))
    ExactTypeAssertResolved(scope, bindings, "byte", typeof(byte))
    ExactTypeAssertResolved(scope, bindings, "sbyte", typeof(sbyte))
    ExactTypeAssertResolved(scope, bindings, "bool", typeof(bool))
    ExactTypeAssertResolved(scope, bindings, "char", typeof(char))
    ExactTypeAssertResolved(scope, bindings, "float", typeof(float))
    ExactTypeAssertResolved(scope, bindings, "double", typeof(double))
    ExactTypeAssertResolved(scope, bindings, "decimal", typeof(decimal))
    ExactTypeAssertResolved(scope, bindings, "string", typeof(string))
    ExactTypeAssertResolved(scope, bindings, "object", typeof(object))
    ExactTypeAssertResolved(scope, bindings, "nint", typeof(IntPtr))
    ExactTypeAssertResolved(scope, bindings, "nuint", typeof(UIntPtr))
    ExactTypeAssertResolved(scope, bindings, "int[][]", typeof(int[][]))
    ExactTypeAssertResolved(scope, bindings, "StringBuilder", typeof(System.Text.StringBuilder))
    ExactTypeAssertResolved(scope, bindings, "System.IO.StreamReader", typeof(System.IO.StreamReader))

    ExactTypeAssertRejected(scope, bindings, "")
    ExactTypeAssertRejected(scope, bindings, "int?")
    ExactTypeAssertRejected(scope, bindings, "List<int>")
    ExactTypeAssertRejected(scope, bindings, "int|string")
    ExactTypeAssertRejected(scope, bindings, ".int")
    ExactTypeAssertRejected(scope, bindings, "int.")
}

test "exact explicit type scope gives source names and live type parameters semantic precedence" {
    dateTimeBuilder := TypeOfCreateSourceBuilder("DateTime", false)
    sourceBuilder := TypeOfCreateSourceBuilder("Scope.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(dateTimeBuilder, "DateTime"))
    definitions.Add(ExactTypeDefinition(sourceBuilder, "Scope.Widget"))
    bindings := ExactTypeBindings(definitions)
    scope := ExactTypeSingleScope(
        "namespace Scope\nclass DateTime {}\nclass Widget {}\n")

    ExactTypeAssertResolved(scope, bindings, "DateTime", dateTimeBuilder)
    ExactTypeAssertResolved(scope, bindings, "Widget", sourceBuilder)
    ExactTypeAssertResolved(scope, bindings, "Scope.Widget", sourceBuilder)

    genericOwner := TypeOfCreateSourceBuilder("ExactTypeGenericOwner", true)
    genericArguments := genericOwner.GetGenericArguments()
    assert genericArguments.Length == 1
    typeParameter := genericArguments[0]
    typeParameterName := typeParameter.Name
    genericParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    genericParameters[typeParameterName] = typeParameter
    genericBindings := BindingRawTypeParameters(genericParameters)
    genericBindings.SourceTypeDefinitions = definitions
    ExactTypeAssertResolved(
        scope, genericBindings, typeParameterName, typeParameter)
    typeParameterArray := typeof(object)
    assert scope.TryResolveExactExplicitType(
        typeParameterName + "[][]",
        genericBindings,
        out typeParameterArray)
    assert typeParameterArray.get_IsSZArray()
    firstElement := typeParameterArray.GetElementType()
    if firstElement == null {
        throw new InvalidOperationException(
            "Generic parameter array did not retain its first element type.")
    }
    assert firstElement.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        firstElement.GetElementType(), typeParameter)
}

test "exact explicit type scope resolves local aliases chains arrays and ordered namespaces" {
    leftBuilder := TypeOfCreateSourceBuilder("Left.Widget", false)
    rightBuilder := TypeOfCreateSourceBuilder("Right.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(leftBuilder, "Left.Widget"))
    definitions.Add(ExactTypeDefinition(rightBuilder, "Right.Widget"))
    bindings := ExactTypeBindings(definitions)

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Widget {}\ntype Alias = Widget\ntype Alias2 = Alias\ntype WidgetArray = Alias2[]\n"
    sources[1] = "namespace Right\nclass Widget {}\n"
    sources[2] = "namespace Caller\nimport Right\nimport Left\n"
    fileNames[0] = "left.nl"
    fileNames[1] = "right.nl"
    fileNames[2] = "caller.nl"

    leftScope := ExactTypeScope(sources, fileNames, 0)
    ExactTypeAssertResolved(leftScope, bindings, "Alias2", leftBuilder)
    aliasArray := typeof(object)
    assert leftScope.TryResolveExactExplicitType("WidgetArray", bindings, out aliasArray)
    assert aliasArray.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        aliasArray.GetElementType(), leftBuilder)

    callerScope := ExactTypeScope(sources, fileNames, 2)
    ExactTypeAssertResolved(callerScope, bindings, "Widget", rightBuilder)
    ExactTypeAssertRejected(callerScope, bindings, "Wrong.Widget")

    cycleScope := ExactTypeSingleScope("type A = B\ntype B = A\n")
    ExactTypeAssertRejected(cycleScope, ExactTypeEmptyBindings(), "A")
    unsupportedAlias := ExactTypeSingleScope("type Values = List<int>\n")
    ExactTypeAssertRejected(
        unsupportedAlias, ExactTypeEmptyBindings(), "Values")
}

test "exact explicit type scope resolves namespace and file aliases without tail stripping" {
    widgetBuilder := TypeOfCreateSourceBuilder("Models.Widget", false)
    userIdBuilder := TypeOfCreateSourceBuilder("UserId", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(widgetBuilder, "Models.Widget"))
    // Packaged newtypes currently carry a short mechanical builder name; the scope has already
    // selected the exact file declaration before the declaration-name handle bridge runs.
    definitions.Add(ExactTypeDefinition(userIdBuilder, "UserId"))
    bindings := ExactTypeBindings(definitions)

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Caller\nimport Models as M\nimport \"models.nl\" as FileModels\nimport \"aliases.nl\"\n"
    sources[1] = "namespace Models\nclass Widget {}\ntype WidgetAlias = Widget\ntype UserId = newtype int\n"
    sources[2] = "namespace Aliases\ntype ImportedAlias = Models.Widget\n"
    fileNames[0] = "exact-alias/main.nl"
    fileNames[1] = "exact-alias/models.nl"
    fileNames[2] = "exact-alias/aliases.nl"

    scope := ExactTypeScope(sources, fileNames, 0)
    ExactTypeAssertResolved(scope, bindings, "M.Widget", widgetBuilder)
    ExactTypeAssertResolved(scope, bindings, "FileModels.Widget", widgetBuilder)
    ExactTypeAssertResolved(scope, bindings, "FileModels.WidgetAlias", widgetBuilder)
    ExactTypeAssertResolved(scope, bindings, "FileModels.UserId", userIdBuilder)
    ExactTypeAssertResolved(scope, bindings, "ImportedAlias", widgetBuilder)
    ExactTypeAssertRejected(scope, bindings, "FileModels.Missing")
    ExactTypeAssertRejected(scope, bindings, "Wrong.Widget")

    runtimeAlias := ExactTypeSingleScope("import System.Text as Text\n")
    ExactTypeAssertResolved(
        runtimeAlias,
        ExactTypeEmptyBindings(),
        "Text.StringBuilder",
        typeof(System.Text.StringBuilder))
    ExactTypeAssertRejected(runtimeAlias, ExactTypeEmptyBindings(), "Text")
}

test "exact explicit type scope fences visibility collisions missing imports and incomplete aliases" {
    hiddenBuilder := TypeOfCreateSourceBuilder("Models.Hidden", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(hiddenBuilder, "Models.Hidden"))
    bindings := ExactTypeBindings(definitions)

    visibilitySources := new string[](2)
    visibilityNames := new string[](2)
    visibilitySources[0] = "namespace Models\nprivate class Hidden {}\n"
    visibilitySources[1] = "namespace Caller\nimport Models\n"
    visibilityNames[0] = "visibility/models.nl"
    visibilityNames[1] = "visibility/caller.nl"
    ExactTypeAssertResolved(
        ExactTypeScope(visibilitySources, visibilityNames, 0),
        bindings,
        "Hidden",
        hiddenBuilder)
    ExactTypeAssertRejected(
        ExactTypeScope(visibilitySources, visibilityNames, 1),
        bindings,
        "Hidden")

    collisionSources := new string[](3)
    collisionNames := new string[](3)
    collisionSources[0] = "import \"left.nl\"\nimport \"right.nl\"\n"
    collisionSources[1] = "namespace Left\nclass Widget {}\n"
    collisionSources[2] = "namespace Right\nclass Widget {}\n"
    collisionNames[0] = "collision/main.nl"
    collisionNames[1] = "collision/left.nl"
    collisionNames[2] = "collision/right.nl"
    collisionBindings := new List<ColumnarStructDef>()
    collisionBindings.Add(ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Left.Widget", false), "Left.Widget"))
    collisionBindings.Add(ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Right.Widget", false), "Right.Widget"))
    ExactTypeAssertRejected(
        ExactTypeScope(collisionSources, collisionNames, 0),
        ExactTypeBindings(collisionBindings),
        "Widget")

    missingSources := new string[](1)
    missingNames := new string[](1)
    missingSources[0] = "import \"missing.nl\" as Missing\n"
    missingNames[0] = "missing/main.nl"
    ExactTypeAssertRejected(
        ExactTypeScope(missingSources, missingNames, 0),
        ExactTypeEmptyBindings(),
        "int")

    duplicateAlias := ExactTypeSingleScope(
        "import System as Lib\nimport System.Text as Lib\n")
    ExactTypeAssertRejected(duplicateAlias, ExactTypeEmptyBindings(), "int")
}

test "program exact type resolution selects same short name by source file" {
    leftBuilder := TypeOfCreateSourceBuilder("Left.Widget", false)
    rightBuilder := TypeOfCreateSourceBuilder("Right.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(leftBuilder, "Left.Widget"))
    definitions.Add(ExactTypeDefinition(rightBuilder, "Right.Widget"))
    bindings := ExactTypeResolutionBindings(definitions)

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Left\nclass Widget {}\n"
    sources[1] = "namespace Right\nclass Widget {}\n"
    fileNames[0] = "exact-program/left.nl"
    fileNames[1] = "exact-program/right.nl"
    program := ExactTypeProgram(sources, fileNames)

    left := typeof(object)
    leftClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        0, "Widget", bindings, out left, out leftClaimed)
    assert leftClaimed
    assert ColumnarConstructionPlanner.SameObject(left, leftBuilder)

    right := typeof(object)
    rightClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1, "Widget", bindings, out right, out rightClaimed)
    assert rightClaimed
    assert ColumnarConstructionPlanner.SameObject(right, rightBuilder)
}

test "type resolution binding factory copies only live type facts" {
    genericOwner := TypeOfCreateSourceBuilder(
        "ExactResolutionBindingOwner", true)
    genericArguments := genericOwner.GetGenericArguments()
    assert genericArguments.Length == 1
    typeParameter := genericArguments[0]
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[typeParameter.Name] = typeParameter

    bindings := ColumnarFragmentBindings.CreateTypeResolutionBindings(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        typeParameters)

    assert bindings.ParameterOrdinals.Count == 0
    assert bindings.ParameterTypes.Count == 0
    assert bindings.Locals.Count == 0
    assert bindings.LiftedLocals.Count == 0
    assert bindings.BoxedCaptures.Count == 0
    assert bindings.TupleNames.Count == 0
    assert bindings.CurrentInstance == null
    assert bindings.EnclosingTypeDefinition == null

    resolved := typeof(object)
    assert bindings.TryGetTypeParameter(typeParameter.Name, out resolved)
    assert ColumnarConstructionPlanner.SameObject(resolved, typeParameter)
}

test "program exact type resolution preserves runtime and source aliases" {
    widgetBuilder := TypeOfCreateSourceBuilder("Models.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(widgetBuilder, "Models.Widget"))
    bindings := ExactTypeResolutionBindings(definitions)

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Models\nclass Widget {}\n"
    sources[1] = "namespace Caller\n"
        + "import Models\n"
        + "import System.Text as Text\n"
        + "type SourceAlias = Widget\n"
        + "type RuntimeAlias = Text.StringBuilder\n"
        + "type BrokenAlias = List<int>\n"
    fileNames[0] = "exact-alias-program/models.nl"
    fileNames[1] = "exact-alias-program/caller.nl"
    program := ExactTypeProgram(sources, fileNames)

    sourceAlias := typeof(object)
    sourceClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1, "SourceAlias", bindings, out sourceAlias, out sourceClaimed)
    assert sourceClaimed
    assert ColumnarConstructionPlanner.SameObject(
        sourceAlias, widgetBuilder)

    runtimeAlias := typeof(object)
    runtimeClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1, "RuntimeAlias", bindings, out runtimeAlias, out runtimeClaimed)
    assert runtimeClaimed
    assert runtimeAlias == typeof(System.Text.StringBuilder)

    namespaceAlias := typeof(object)
    namespaceClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "Text.StringBuilder",
        bindings,
        out namespaceAlias,
        out namespaceClaimed)
    assert namespaceClaimed
    assert namespaceAlias == typeof(System.Text.StringBuilder)

    rejected := typeof(object)
    rejectedClaimed := false
    assert !program.TryResolveExactExplicitTypeForFile(
        1, "BrokenAlias", bindings, out rejected, out rejectedClaimed)
    assert rejectedClaimed
    assert rejected == typeof(object)

    unsupported := typeof(object)
    unsupportedClaimed := true
    assert !program.TryResolveExactExplicitTypeForFile(
        1, "List<int>", bindings, out unsupported, out unsupportedClaimed)
    assert !unsupportedClaimed
    assert unsupported == typeof(object)
}
