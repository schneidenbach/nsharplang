namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

func ExactTypeScope(
    sources: string[],
    fileNames: string[],
    activeSourceFileId: int
): ColumnarBindingScopeFacts {
    scope := ColumnarBindingScopeFacts.Create(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        ExternalEmptyEnums(),
        ExternalEmptyStructs(),
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null
    )
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
    declaredName: string
): ColumnarStructDef {
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        declaredName
    )
}

func ExactTypeInput(
    name: string,
    enclosingTypeName: string
): ColumnarStructInput {
    input := ExternalStruct(
        name,
        new string[](0),
        new string[](0),
        new List<ColumnarFunctionInput>(),
        null,
        true
    )
    input.EnclosingTypeName = enclosingTypeName
    return input
}

func ExactTypeBindings(
    definitions: List<ColumnarStructDef>
): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    exactSourceTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    for definition in definitions {
        exactSourceTypes[definition.DeclaredTypeName] = definition.Builder
    }
    bindings.ExactSourceTypes = exactSourceTypes
    return bindings
}

func ExactTypeEmptyBindings(): ColumnarFragmentBindings {
    return ExactTypeBindings(new List<ColumnarStructDef>())
}

func ExactTypeProgram(
    sources: string[],
    fileNames: string[]
): ColumnarProgramInput {
    program := ColumnarProgramInput.CreateFromSourceFiles(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        new List<ColumnarFunctionInput>(),
        ExternalEmptyEnums(),
        ExternalEmptyStructs(),
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null
    )
    program.PrepareExternalTypeBindings(null)
    return program
}

func ExactTypeResolutionBindings(
    definitions: IEnumerable<ColumnarStructDef>
): ColumnarFragmentBindings {
    return ColumnarFragmentBindings.CreateTypeResolutionBindings(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        definitions,
        new ColumnarUnionDef[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal)
    )
}

func ExactTypeAssertResolved(
    scope: ColumnarBindingScopeFacts,
    bindings: ColumnarFragmentBindings,
    canonical: string,
    expected: Type
) {
    resolved := typeof(object)
    assert scope.TryResolveExactExplicitType(canonical, bindings, out resolved)
    assert resolved == expected
}

func ExactTypeAssertRejected(
    scope: ColumnarBindingScopeFacts,
    bindings: ColumnarFragmentBindings,
    canonical: string
) {
    resolved := typeof(object)
    assert !scope.TryResolveExactExplicitType(canonical, bindings, out resolved)
    assert resolved == typeof(object)
}

test "exact explicit type scope resolves language builtins arrays and external names" {
    scope := ExactTypeSingleScope(
        "import System\nimport System.Text\nimport System.IO\nimport System.Collections.Generic\n"
    )
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
    ExactTypeAssertResolved(
        scope,
        bindings,
        "ValueTuple<int,string>",
        typeof(ValueTuple<int, string>)
    )

    nullableDefinition := Type.GetType("System.Nullable`1")
    if nullableDefinition == null {
        throw new InvalidOperationException(
            "System.Nullable<T> runtime type was not found."
        )
    }
    nullableArguments := new Type[](1)
    nullableArguments[0] = typeof(int)
    ExactTypeAssertResolved(
        scope,
        bindings,
        "int?",
        nullableDefinition.MakeGenericType(nullableArguments)
    )
    ExactTypeAssertResolved(scope, bindings, "string?", typeof(string))
    ExactTypeAssertResolved(
        scope,
        bindings,
        "(File:string?,Line:int,Column:int)",
        typeof(ValueTuple<string, int, int>)
    )
    ExactTypeAssertResolved(
        scope,
        bindings,
        "Dictionary<(File:string?,Line:int,Column:int),int>",
        typeof(Dictionary<ValueTuple<string, int, int>, int>)
    )
    ExactTypeAssertResolved(scope, bindings, "List<int>", typeof(List<int>))

    ExactTypeAssertRejected(scope, bindings, "")
    ExactTypeAssertRejected(scope, bindings, "int|string")
    ExactTypeAssertRejected(scope, bindings, ".int")
    ExactTypeAssertRejected(scope, bindings, "int.")
}

test "exact explicit type scope gives source names and live type parameters semantic precedence" {
    dateTimeBuilder := TypeOfCreateSourceBuilder("Scope.DateTime", false)
    sourceBuilder := TypeOfCreateSourceBuilder("Scope.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(dateTimeBuilder, "Scope.DateTime"))
    definitions.Add(ExactTypeDefinition(sourceBuilder, "Scope.Widget"))
    bindings := ExactTypeBindings(definitions)
    scope := ExactTypeSingleScope(
        "namespace Scope\nclass DateTime {}\nclass Widget {}\n"
    )

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
        scope,
        genericBindings,
        typeParameterName,
        typeParameter
    )
    typeParameterArray := typeof(object)
    assert scope.TryResolveExactExplicitType(
        typeParameterName + "[][]",
        genericBindings,
        out typeParameterArray
    )
    assert typeParameterArray.get_IsSZArray()
    firstElement := typeParameterArray.GetElementType()
    if firstElement == null {
        throw new InvalidOperationException(
            "Generic parameter array did not retain its first element type."
        )
    }
    assert firstElement.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        firstElement.GetElementType(),
        typeParameter
    )
}

test "exact explicit type scope preserves namespaced nested identity and ancestor lexical lookup" {
    source := "namespace Scope\nclass Outer { class Sibling {} class Middle { class Inner {} } }\nclass Sibling {}\n"
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = source
    fileNames[0] = "nested.nl"

    inputs := new List<ColumnarStructInput>()
    outerInput := ExactTypeInput("Outer", "")
    nestedSiblingInput := ExactTypeInput("Sibling", "Outer")
    middleInput := ExactTypeInput("Middle", "Outer")
    innerInput := ExactTypeInput("Inner", "Outer.Middle")
    topLevelSiblingInput := ExactTypeInput("Sibling", "")
    inputs.Add(outerInput)
    inputs.Add(topLevelSiblingInput)
    inputs.Add(nestedSiblingInput)
    inputs.Add(middleInput)
    inputs.Add(innerInput)

    scopeRoot := ColumnarBindingScopeFacts.Create(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        ExternalEmptyEnums(),
        inputs,
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null
    )
    scopeRoot.PrepareExternalTypeBindings(null)
    scope := scopeRoot.ForSourceFile(0)

    outerBuilder := TypeOfCreateSourceBuilder("Scope.Outer", false)
    nestedSiblingBuilder := TypeOfCreateSourceBuilder(
        "Scope.Outer.Sibling",
        false
    )
    middleBuilder := TypeOfCreateSourceBuilder(
        "Scope.Outer.Middle",
        false
    )
    innerBuilder := TypeOfCreateSourceBuilder(
        "Scope.Outer.Middle.Inner",
        false
    )
    topLevelSiblingBuilder := TypeOfCreateSourceBuilder("Scope.Sibling", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(outerBuilder, "Scope.Outer"))
    definitions.Add(ExactTypeDefinition(
        nestedSiblingBuilder,
        "Scope.Outer.Sibling"
    ))
    definitions.Add(ExactTypeDefinition(
        middleBuilder,
        "Scope.Outer.Middle"
    ))
    definitions.Add(ExactTypeDefinition(
        innerBuilder,
        "Scope.Outer.Middle.Inner"
    ))
    definitions.Add(ExactTypeDefinition(
        topLevelSiblingBuilder,
        "Scope.Sibling"
    ))
    bindings := ExactTypeBindings(definitions)

    assert scopeRoot.ExactStructTypeName(outerInput) == "Scope.Outer"
    assert scopeRoot.ExactStructTypeName(nestedSiblingInput) == "Scope.Outer.Sibling"
    ExactTypeAssertResolved(
        scope,
        bindings,
        "Outer.Sibling",
        nestedSiblingBuilder
    )
    exactNestedName := ""
    exactNestedClaimed := false
    assert scope.TryResolveExactSourceDeclarationName(
        "Outer.Sibling",
        out exactNestedName,
        out exactNestedClaimed
    )
    assert exactNestedClaimed
    assert exactNestedName == "Scope.Outer.Sibling"
    resolved := typeof(object)
    claimed := false
    assert scope.TryResolveExactExplicitTypeInContext(
        "Scope.Outer.Middle.Inner",
        "Sibling",
        bindings,
        out resolved,
        out claimed
    )
    assert claimed
    assert ColumnarConstructionPlanner.SameObject(
        resolved,
        nestedSiblingBuilder
    )
    ExactTypeAssertResolved(
        scope,
        bindings,
        "Sibling",
        topLevelSiblingBuilder
    )
}

test "exact explicit type scope exposes nested declarations across files only when exported" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Scope\nclass Outer { public class Inner {} class hidden {} }\n"
    sources[1] = "namespace Scope\nfunc Use() {}\n"
    fileNames[0] = "outer.nl"
    fileNames[1] = "use.nl"

    inputs := new List<ColumnarStructInput>()
    outerInput := ExactTypeInput("Outer", "")
    innerInput := ExactTypeInput("Inner", "Outer")
    hiddenInput := ExactTypeInput("hidden", "Outer")
    inputs.Add(outerInput)
    inputs.Add(innerInput)
    inputs.Add(hiddenInput)
    scopeRoot := ColumnarBindingScopeFacts.Create(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        ExternalEmptyEnums(),
        inputs,
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null
    )
    scopeRoot.PrepareExternalTypeBindings(null)
    scope := scopeRoot.ForSourceFile(1)

    outerBuilder := TypeOfCreateSourceBuilder("Scope.Outer", false)
    innerBuilder := TypeOfCreateSourceBuilder(
        "Scope.Outer.Inner",
        false
    )
    hiddenBuilder := TypeOfCreateSourceBuilder(
        "Scope.Outer.hidden",
        false
    )
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(outerBuilder, "Scope.Outer"))
    definitions.Add(ExactTypeDefinition(
        innerBuilder,
        "Scope.Outer.Inner"
    ))
    definitions.Add(ExactTypeDefinition(
        hiddenBuilder,
        "Scope.Outer.hidden"
    ))
    bindings := ExactTypeBindings(definitions)

    ExactTypeAssertResolved(scope, bindings, "Outer.Inner", innerBuilder)
    ExactTypeAssertRejected(scope, bindings, "Outer.hidden")
}

test "exact explicit type scope resolves local aliases chains arrays and ordered namespaces" {
    leftBuilder := TypeOfCreateSourceBuilder("Left.Widget", false)
    rightBuilder := TypeOfCreateSourceBuilder("Right.Widget", false)
    boxBuilder := TypeOfCreateSourceBuilder("Left.Box", true)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(leftBuilder, "Left.Widget"))
    definitions.Add(ExactTypeDefinition(rightBuilder, "Right.Widget"))
    definitions.Add(ExactTypeDefinition(boxBuilder, "Left.Box"))
    bindings := ExactTypeBindings(definitions)

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Widget {}\nclass Box<T> {}\ntype Alias = Widget\ntype Alias2 = Alias\ntype WidgetArray = Alias2[]\ntype IntBox = Box<int>\n"
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
        aliasArray.GetElementType(),
        leftBuilder
    )
    intBox := typeof(object)
    assert leftScope.TryResolveExactExplicitType("IntBox", bindings, out intBox)
    assert intBox.get_IsGenericType()
    assert ColumnarConstructionPlanner.SameObject(
        intBox.GetGenericTypeDefinition(),
        boxBuilder
    )
    intBoxArguments := intBox.GetGenericArguments()
    assert intBoxArguments.Length == 1
    assert intBoxArguments[0] == typeof(int)

    callerScope := ExactTypeScope(sources, fileNames, 2)
    ExactTypeAssertResolved(callerScope, bindings, "Widget", rightBuilder)
    ExactTypeAssertRejected(callerScope, bindings, "Wrong.Widget")

    cycleScope := ExactTypeSingleScope("type A = B\ntype B = A\n")
    ExactTypeAssertRejected(cycleScope, ExactTypeEmptyBindings(), "A")
    unsupportedAlias := ExactTypeSingleScope(
        "type Values = DefinitelyMissingGeneric<int>\n"
    )
    ExactTypeAssertRejected(
        unsupportedAlias,
        ExactTypeEmptyBindings(),
        "Values"
    )
}

test "exact explicit type scope resolves namespace and file aliases without tail stripping" {
    widgetBuilder := TypeOfCreateSourceBuilder("Models.Widget", false)
    userIdBuilder := TypeOfCreateSourceBuilder("Models.UserId", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(widgetBuilder, "Models.Widget"))
    definitions.Add(ExactTypeDefinition(userIdBuilder, "Models.UserId"))
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
        typeof(System.Text.StringBuilder)
    )
    ExactTypeAssertRejected(runtimeAlias, ExactTypeEmptyBindings(), "Text")
}

test "exact explicit type scope fences visibility collisions missing imports and incomplete aliases" {
    hiddenBuilder := TypeOfCreateSourceBuilder("Models.Hidden", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(hiddenBuilder, "Models.Hidden"))
    bindings := ExactTypeBindings(definitions)

    visibilitySources := new string[](2)
    visibilityNames := new string[](2)
    visibilitySources[0] = "namespace Models\nimport Models as Same\nprivate class Hidden {}\ntype HiddenAlias = Same.Hidden\n"
    visibilitySources[1] = "namespace Caller\nimport Models\n"
    visibilityNames[0] = "visibility/models.nl"
    visibilityNames[1] = "visibility/caller.nl"
    ExactTypeAssertResolved(
        ExactTypeScope(visibilitySources, visibilityNames, 0),
        bindings,
        "Hidden",
        hiddenBuilder
    )
    ExactTypeAssertResolved(
        ExactTypeScope(visibilitySources, visibilityNames, 0),
        bindings,
        "Same.Hidden",
        hiddenBuilder
    )
    ExactTypeAssertResolved(
        ExactTypeScope(visibilitySources, visibilityNames, 0),
        bindings,
        "HiddenAlias",
        hiddenBuilder
    )
    ExactTypeAssertRejected(
        ExactTypeScope(visibilitySources, visibilityNames, 1),
        bindings,
        "Hidden"
    )

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
        TypeOfCreateSourceBuilder("Left.Widget", false),
        "Left.Widget"
    ))
    collisionBindings.Add(ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Right.Widget", false),
        "Right.Widget"
    ))
    ExactTypeAssertRejected(
        ExactTypeScope(collisionSources, collisionNames, 0),
        ExactTypeBindings(collisionBindings),
        "Widget"
    )

    missingSources := new string[](1)
    missingNames := new string[](1)
    missingSources[0] = "import \"missing.nl\" as Missing\n"
    missingNames[0] = "missing/main.nl"
    ExactTypeAssertRejected(
        ExactTypeScope(missingSources, missingNames, 0),
        ExactTypeEmptyBindings(),
        "int"
    )

    duplicateAlias := ExactTypeSingleScope(
        "import System as Lib\nimport System.Text as Lib\n"
    )
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
        0,
        "Widget",
        bindings,
        out left,
        out leftClaimed
    )
    assert leftClaimed
    assert ColumnarConstructionPlanner.SameObject(left, leftBuilder)

    right := typeof(object)
    rightClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "Widget",
        bindings,
        out right,
        out rightClaimed
    )
    assert rightClaimed
    assert ColumnarConstructionPlanner.SameObject(right, rightBuilder)

    leftName := ""
    leftNameClaimed := false
    assert program.TryResolveExactSourceDeclarationNameForFile(
        0,
        "Widget",
        out leftName,
        out leftNameClaimed
    )
    assert leftNameClaimed
    assert leftName == "Left.Widget"

    rightName := ""
    rightNameClaimed := false
    assert program.TryResolveExactSourceDeclarationNameForFile(
        1,
        "Widget",
        out rightName,
        out rightNameClaimed
    )
    assert rightNameClaimed
    assert rightName == "Right.Widget"
}

test "program exact type resolution selects one exported cross namespace name" {
    reportBuilder := TypeOfCreateSourceBuilder(
        "NSharpLang.Compiler.Performance.SystemsReport",
        false
    )
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(
        reportBuilder,
        "NSharpLang.Compiler.Performance.SystemsReport"
    ))
    bindings := ExactTypeResolutionBindings(definitions)

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace NSharpLang.Compiler.Performance\nclass SystemsReport {}\n"
    sources[1] = "namespace NSharpLang.Compiler.CodeIntelligence\nclass Formatter {}\n"
    fileNames[0] = "exact-program/report.nl"
    fileNames[1] = "exact-program/formatter.nl"
    program := ExactTypeProgram(sources, fileNames)

    reportType := typeof(object)
    reportClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "SystemsReport",
        bindings,
        out reportType,
        out reportClaimed
    )
    assert reportClaimed
    assert ColumnarConstructionPlanner.SameObject(reportType, reportBuilder)

    reportName := ""
    reportNameClaimed := false
    assert program.TryResolveExactSourceDeclarationNameForFile(
        1,
        "SystemsReport",
        out reportName,
        out reportNameClaimed
    )
    assert reportNameClaimed
    assert reportName == "NSharpLang.Compiler.Performance.SystemsReport"
}

test "program exact type resolution rejects ambiguous exported cross namespace names" {
    leftBuilder := TypeOfCreateSourceBuilder("Left.Widget", false)
    rightBuilder := TypeOfCreateSourceBuilder("Right.Widget", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(leftBuilder, "Left.Widget"))
    definitions.Add(ExactTypeDefinition(rightBuilder, "Right.Widget"))
    bindings := ExactTypeResolutionBindings(definitions)

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Widget {}\n"
    sources[1] = "namespace Right\nclass Widget {}\n"
    sources[2] = "namespace Caller\nclass Consumer {}\n"
    fileNames[0] = "exact-program/ambiguous-left.nl"
    fileNames[1] = "exact-program/ambiguous-right.nl"
    fileNames[2] = "exact-program/ambiguous-caller.nl"
    program := ExactTypeProgram(sources, fileNames)

    ambiguousType := typeof(object)
    ambiguousTypeClaimed := false
    assert !program.TryResolveExactExplicitTypeForFile(
        2,
        "Widget",
        bindings,
        out ambiguousType,
        out ambiguousTypeClaimed
    )
    assert ambiguousTypeClaimed
    assert ambiguousType == typeof(object)

    ambiguousName := ""
    ambiguousNameClaimed := false
    assert !program.TryResolveExactSourceDeclarationNameForFile(
        2,
        "Widget",
        out ambiguousName,
        out ambiguousNameClaimed
    )
    assert ambiguousNameClaimed
    assert ambiguousName == ""
}

test "type resolution binding factory copies only live type facts" {
    genericOwner := TypeOfCreateSourceBuilder(
        "ExactResolutionBindingOwner",
        true
    )
    genericArguments := genericOwner.GetGenericArguments()
    assert genericArguments.Length == 1
    typeParameter := genericArguments[0]
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[typeParameter.Name] = typeParameter

    bindings := ColumnarFragmentBindings.CreateTypeResolutionBindings(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        typeParameters
    )

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
    sources[1] = "namespace Caller\n" + "import Models\n" + "import System.Text as Text\n" + "import System.Collections.Generic as Collections\n" + "type SourceAlias = Widget\n" + "type RuntimeAlias = Text.StringBuilder\n" + "type RuntimeGenericAlias = Collections.List<int>\n" + "type BrokenAlias = DefinitelyMissingGeneric<int>\n"
    fileNames[0] = "exact-alias-program/models.nl"
    fileNames[1] = "exact-alias-program/caller.nl"
    program := ExactTypeProgram(sources, fileNames)

    sourceAlias := typeof(object)
    sourceClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "SourceAlias",
        bindings,
        out sourceAlias,
        out sourceClaimed
    )
    assert sourceClaimed
    assert ColumnarConstructionPlanner.SameObject(
        sourceAlias,
        widgetBuilder
    )

    sourceAliasName := ""
    sourceAliasNameClaimed := false
    assert program.TryResolveExactSourceDeclarationNameForFile(
        1,
        "SourceAlias",
        out sourceAliasName,
        out sourceAliasNameClaimed
    )
    assert sourceAliasNameClaimed
    assert sourceAliasName == "Models.Widget"

    runtimeAlias := typeof(object)
    runtimeClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "RuntimeAlias",
        bindings,
        out runtimeAlias,
        out runtimeClaimed
    )
    assert runtimeClaimed
    assert runtimeAlias == typeof(System.Text.StringBuilder)

    runtimeAliasName := ""
    runtimeAliasNameClaimed := false
    assert !program.TryResolveExactSourceDeclarationNameForFile(
        1,
        "RuntimeAlias",
        out runtimeAliasName,
        out runtimeAliasNameClaimed
    )
    assert runtimeAliasNameClaimed
    assert runtimeAliasName == ""

    runtimeGenericAlias := typeof(object)
    runtimeGenericClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "RuntimeGenericAlias",
        bindings,
        out runtimeGenericAlias,
        out runtimeGenericClaimed
    )
    assert runtimeGenericClaimed
    assert runtimeGenericAlias == typeof(List<int>)

    namespaceAlias := typeof(object)
    namespaceClaimed := false
    assert program.TryResolveExactExplicitTypeForFile(
        1,
        "Text.StringBuilder",
        bindings,
        out namespaceAlias,
        out namespaceClaimed
    )
    assert namespaceClaimed
    assert namespaceAlias == typeof(System.Text.StringBuilder)

    rejected := typeof(object)
    rejectedClaimed := false
    assert !program.TryResolveExactExplicitTypeForFile(
        1,
        "BrokenAlias",
        bindings,
        out rejected,
        out rejectedClaimed
    )
    assert rejectedClaimed
    assert rejected == typeof(object)

    unsupported := typeof(object)
    unsupportedClaimed := true
    assert !program.TryResolveExactExplicitTypeForFile(
        1,
        "DefinitelyMissingGeneric<int>",
        bindings,
        out unsupported,
        out unsupportedClaimed
    )
    assert !unsupportedClaimed
    assert unsupported == typeof(object)
}
