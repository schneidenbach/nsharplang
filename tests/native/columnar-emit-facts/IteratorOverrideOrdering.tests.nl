namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic
import System.Reflection

// This is deliberately a private-host control rather than a second iterator implementation test.
// The parser builds a valid synchronous iterator first.  The test then changes one already-created
// planner fact and invokes the existing `precomputedShape` emitter seam, so failures below occur
// after parser admission and within the real attachment/body interleave.
class IteratorOrderingOutcome {
    Outcome: string
    ResolvedPrefix: int
    TraceCount: int

    constructor(outcome: string, resolvedPrefix: int, traceCount: int) {
        Outcome = outcome
        ResolvedPrefix = resolvedPrefix
        TraceCount = traceCount
    }
}

class IteratorOrderingParsedInput {
    Function: object
    Shape: object
    Resolution: object

    constructor(function: object, shape: object, resolution: object) {
        Function = function
        Shape = shape
        Resolution = resolution
    }
}

func IteratorOrderingPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func IteratorOrderingCompilerType(name: string): Type {
    owner := Type.GetType("NSharpLang.Compiler.Columnar." + name + ", Compiler")
    if owner == null {
        throw new InvalidOperationException("Missing compiler type '" + name + "'")
    }
    return owner
}

func IteratorOrderingBootstrapType(name: string): Type {
    owner := Type.GetType("NSharpLang.Compiler.Columnar." + name + ", NSharpLang.Compiler.BootstrapServices")
    if owner == null {
        throw new InvalidOperationException("Missing bootstrap type '" + name + "'")
    }
    return owner
}

func IteratorOrderingRuntimeType(name: string): Type {
    owner := Type.GetType(name)
    if owner == null {
        throw new InvalidOperationException("Missing runtime type '" + name + "'")
    }
    return owner
}

func IteratorOrderingMethod(owner: Type, name: string, flags: BindingFlags, parameterCount: int): MethodInfo {
    methods := owner.GetMethods(flags)
    for method in methods {
        if method.get_Name() == name && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing method '" + owner.get_FullName() + "." + name + "'")
}

func IteratorOrderingConstructor(owner: Type, parameterTypes: Type[]): ConstructorInfo {
    constructor := owner.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("Missing constructor for '" + owner.get_FullName() + "'")
    }
    return constructor
}

func IteratorOrderingRequiredMember(target: object, name: string): object {
    field := target.GetType().GetField(name)
    if field != null {
        value := field.GetValue(target)
        if value == null {
            throw new InvalidOperationException("Member '" + name + "' was null")
        }
        return value
    }
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing member '" + name + "'")
    }
    propertyValue := property.GetValue(target)
    if propertyValue == null {
        throw new InvalidOperationException("Member '" + name + "' was null")
    }
    return propertyValue
}

func IteratorOrderingWriteField(target: object, name: string, value: object?) {
    field := target.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing mutable field '" + name + "'")
    }
    field.SetValue(target, value)
}

func IteratorOrderingRequiredList(value: object, label: string): IList {
    list := value as IList
    if list == null {
        throw new InvalidOperationException("Expected IList for " + label)
    }
    return list
}

func IteratorOrderingSetArrayCell(value: object, index: int, replacement: object) {
    array := value as Array
    if array == null {
        throw new InvalidOperationException("Expected an array for iterator ordering mutation")
    }
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(object)
    parameterTypes[1] = typeof(int)
    setValue := array.GetType().GetMethod("SetValue", parameterTypes)
    if setValue == null {
        throw new InvalidOperationException("Missing Array.SetValue(object, int)")
    }
    arguments := new object?[](2)
    IteratorOrderingPut(arguments, 0, replacement)
    IteratorOrderingPut(arguments, 1, index)
    ignored := setValue.Invoke(array, arguments)
    _ = ignored
}

func IteratorOrderingEmptyCompilerDictionary(valueTypeName: string): object {
    valueType := IteratorOrderingBootstrapType(valueTypeName)
    definition := typeof(Dictionary<string, int>).GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = typeof(string)
    arguments[1] = valueType
    dictionaryType := definition.MakeGenericType(arguments)
    constructor := IteratorOrderingConstructor(dictionaryType, new Type[](0))
    values := new object?[](0)
    dictionary := constructor.Invoke(values)
    if dictionary == null {
        throw new InvalidOperationException("Could not create compiler dictionary")
    }
    return dictionary
}

func IteratorOrderingResolution(program: object, sourceFileId: int): object {
    enumDefinitions := IteratorOrderingEmptyCompilerDictionary("ColumnarEnumDef")
    structDefinitions := IteratorOrderingEmptyCompilerDictionary("ColumnarStructDef")
    unionDefinitions := IteratorOrderingEmptyCompilerDictionary("ColumnarUnionDef")
    catalogType := IteratorOrderingBootstrapType("ColumnarSemanticTypeResolutionCatalog")
    catalogParameterTypes := new Type[](4)
    catalogParameterTypes[0] = program.GetType()
    catalogParameterTypes[1] = enumDefinitions.GetType()
    catalogParameterTypes[2] = structDefinitions.GetType()
    catalogParameterTypes[3] = unionDefinitions.GetType()
    catalogConstructor := IteratorOrderingConstructor(catalogType, catalogParameterTypes)
    catalogArguments := new object?[](4)
    IteratorOrderingPut(catalogArguments, 0, program)
    IteratorOrderingPut(catalogArguments, 1, enumDefinitions)
    IteratorOrderingPut(catalogArguments, 2, structDefinitions)
    IteratorOrderingPut(catalogArguments, 3, unionDefinitions)
    catalog := catalogConstructor.Invoke(catalogArguments)
    if catalog == null {
        throw new InvalidOperationException("Could not create semantic type-resolution catalog")
    }
    view := IteratorOrderingMethod(catalogType, "For", (BindingFlags)20, 3)
    viewArguments := new object?[](3)
    IteratorOrderingPut(viewArguments, 0, sourceFileId)
    IteratorOrderingPut(viewArguments, 1, null)
    IteratorOrderingPut(viewArguments, 2, null)
    resolution := view.Invoke(catalog, viewArguments)
    if resolution == null {
        throw new InvalidOperationException("Semantic type-resolution catalog returned null")
    }
    return resolution
}

func IteratorOrderingShape(function: object, source: string): object {
    planner := IteratorOrderingBootstrapType("ColumnarIteratorPlanner")
    analyze := IteratorOrderingMethod(planner, "AnalyzeShape", (BindingFlags)24, 16)
    values := new object?[](16)
    bodyNodes := IteratorOrderingRequiredMember(function, "BodyNodes")
    IteratorOrderingPut(values, 0, bodyNodes)
    IteratorOrderingPut(values, 1, source)
    bodyRootValue := IteratorOrderingRequiredMember(function, "BodyRoot")
    bodyRoot := Convert.ToInt32(bodyRootValue)
    IteratorOrderingPut(values, 2, bodyRoot)
    functionName := IteratorOrderingRequiredMember(function, "Name")
    IteratorOrderingPut(values, 3, functionName)
    IteratorOrderingPut(values, 4, 0)
    returnCanonical := IteratorOrderingRequiredMember(function, "ReturnCanonical")
    paramNames := IteratorOrderingRequiredMember(function, "ParamNames")
    paramCanonicals := IteratorOrderingRequiredMember(function, "ParamCanonicals")
    typeParamNames := IteratorOrderingRequiredMember(function, "TypeParamNames")
    IteratorOrderingPut(values, 5, returnCanonical)
    IteratorOrderingPut(values, 6, paramNames)
    IteratorOrderingPut(values, 7, paramCanonicals)
    IteratorOrderingPut(values, 8, typeParamNames)
    IteratorOrderingPut(values, 9, false)
    IteratorOrderingPut(values, 10, "")
    IteratorOrderingPut(values, 11, new string[](0))
    IteratorOrderingPut(values, 12, new string[](0))
    IteratorOrderingPut(values, 13, new string[](0))
    IteratorOrderingPut(values, 14, new string[](0))
    IteratorOrderingPut(values, 15, false)
    shape := analyze.Invoke(null, values)
    if shape == null {
        throw new InvalidOperationException("Iterator planner returned null")
    }
    if !Convert.ToBoolean(IteratorOrderingRequiredMember(shape, "Supported")) {
        throw new InvalidOperationException("Valid iterator shape was declined")
    }
    return shape
}

func IteratorOrderingParse(): IteratorOrderingParsedInput {
    source := "import System.Collections.Generic\n\nfunc* IteratorOrderingControl(): IEnumerable<int> {\n    yield 7\n}\n"
    builder := IteratorOrderingCompilerType("ColumnarProgramInputBuilder")
    parse := IteratorOrderingMethod(builder, "TryBuild", (BindingFlags)40, 2)
    values := new object?[](2)
    IteratorOrderingPut(values, 0, source)
    IteratorOrderingPut(values, 1, null)
    if !Convert.ToBoolean(parse.Invoke(null, values)) {
        throw new InvalidOperationException("Iterator ordering control did not parse")
    }
    programBox := values[1]
    if programBox == null {
        throw new InvalidOperationException("Iterator ordering parser returned no program")
    }
    functionsValue := IteratorOrderingRequiredMember(programBox, "Functions")
    functions := IteratorOrderingRequiredList(functionsValue, "Functions")
    if functions.Count != 1 || functions[0] == null {
        throw new InvalidOperationException("Iterator ordering parser returned no function")
    }
    functionBox := functions[0]
    sourceFileIdValue := IteratorOrderingRequiredMember(functionBox, "SourceFileId")
    sourceFileId := Convert.ToInt32(sourceFileIdValue)
    shape := IteratorOrderingShape(functionBox, source)
    resolution := IteratorOrderingResolution(programBox, sourceFileId)
    return new IteratorOrderingParsedInput(functionBox, shape, resolution)
}

func IteratorOrderingStaticField(typeName: string, name: string): object {
    owner := IteratorOrderingRuntimeType(typeName)
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing static field '" + typeName + "." + name + "'")
    }
    value := field.GetValue(null)
    if value == null {
        throw new InvalidOperationException("Static field '" + typeName + "." + name + "' was null")
    }
    return value
}

func IteratorOrderingRequiredInvocation(method: MethodInfo, receiver: object?, values: object?[]): object {
    result := method.Invoke(receiver, values)
    if result == null {
        throw new InvalidOperationException("Reflection invocation unexpectedly returned null")
    }
    return result
}

func IteratorOrderingNewModule(label: string): object {
    assemblyBuilderType := IteratorOrderingRuntimeType("System.Reflection.Emit.AssemblyBuilder")
    accessType := IteratorOrderingRuntimeType("System.Reflection.Emit.AssemblyBuilderAccess")
    nameTypes := new Type[](2)
    nameTypes[0] = typeof(AssemblyName)
    nameTypes[1] = accessType
    defineAssembly := assemblyBuilderType.GetMethod("DefineDynamicAssembly", nameTypes)
    if defineAssembly == null {
        throw new InvalidOperationException("Missing AssemblyBuilder.DefineDynamicAssembly")
    }
    assemblyArguments := new object?[](2)
    IteratorOrderingPut(assemblyArguments, 0, new AssemblyName("IteratorOrdering" + label))
    runAccess := IteratorOrderingStaticField("System.Reflection.Emit.AssemblyBuilderAccess", "Run")
    IteratorOrderingPut(assemblyArguments, 1, runAccess)
    assembly := IteratorOrderingRequiredInvocation(defineAssembly, null, assemblyArguments)
    moduleTypes := new Type[](1)
    moduleTypes[0] = typeof(string)
    defineModule := assemblyBuilderType.GetMethod("DefineDynamicModule", moduleTypes)
    if defineModule == null {
        throw new InvalidOperationException("Missing AssemblyBuilder.DefineDynamicModule")
    }
    moduleArguments := new object?[](1)
    IteratorOrderingPut(moduleArguments, 0, "IteratorOrderingModule" + label)
    return IteratorOrderingRequiredInvocation(defineModule, assembly, moduleArguments)
}

func IteratorOrderingFactoryIl(module: object, label: string): object {
    moduleBuilderType := IteratorOrderingRuntimeType("System.Reflection.Emit.ModuleBuilder")
    typeBuilderType := IteratorOrderingRuntimeType("System.Reflection.Emit.TypeBuilder")
    methodBuilderType := IteratorOrderingRuntimeType("System.Reflection.Emit.MethodBuilder")
    typeAttributesType := IteratorOrderingRuntimeType("System.Reflection.TypeAttributes")
    methodAttributesType := IteratorOrderingRuntimeType("System.Reflection.MethodAttributes")
    defineTypeTypes := new Type[](2)
    defineTypeTypes[0] = typeof(string)
    defineTypeTypes[1] = typeAttributesType
    defineType := moduleBuilderType.GetMethod("DefineType", defineTypeTypes)
    if defineType == null {
        throw new InvalidOperationException("Missing ModuleBuilder.DefineType")
    }
    typeArguments := new object?[](2)
    IteratorOrderingPut(typeArguments, 0, "IteratorOrderingFactory" + label)
    publicTypeAttribute := IteratorOrderingStaticField("System.Reflection.TypeAttributes", "Public")
    IteratorOrderingPut(typeArguments, 1, publicTypeAttribute)
    factoryOwner := IteratorOrderingRequiredInvocation(defineType, module, typeArguments)
    defineMethodTypes := new Type[](4)
    defineMethodTypes[0] = typeof(string)
    defineMethodTypes[1] = methodAttributesType
    defineMethodTypes[2] = typeof(Type)
    defineMethodTypes[3] = typeof(Type[])
    defineMethod := typeBuilderType.GetMethod("DefineMethod", defineMethodTypes)
    if defineMethod == null {
        throw new InvalidOperationException("Missing TypeBuilder.DefineMethod")
    }
    methodArguments := new object?[](4)
    IteratorOrderingPut(methodArguments, 0, "Factory")
    IteratorOrderingPut(methodArguments, 1, MethodAttributes.Public | MethodAttributes.Static)
    IteratorOrderingPut(methodArguments, 2, typeof(IEnumerable<int>))
    IteratorOrderingPut(methodArguments, 3, new Type[](0))
    factory := IteratorOrderingRequiredInvocation(defineMethod, factoryOwner, methodArguments)
    getIl := methodBuilderType.GetMethod("GetILGenerator", new Type[](0))
    if getIl == null {
        throw new InvalidOperationException("Missing MethodBuilder.GetILGenerator")
    }
    emptyArguments := new object?[](0)
    return IteratorOrderingRequiredInvocation(getIl, factory, emptyArguments)
}

func IteratorOrderingEmptyRuntimeList(valueTypeName: string): object {
    valueType := IteratorOrderingRuntimeType(valueTypeName)
    definition := typeof(List<int>).GetGenericTypeDefinition()
    arguments := new Type[](1)
    arguments[0] = valueType
    listType := definition.MakeGenericType(arguments)
    constructor := IteratorOrderingConstructor(listType, new Type[](0))
    emptyArguments := new object?[](0)
    list := constructor.Invoke(emptyArguments)
    if list == null {
        throw new InvalidOperationException("Could not create runtime list")
    }
    return list
}

func IteratorOrderingResolvedPrefix(shape: object): int {
    rowsValue := IteratorOrderingRequiredMember(shape, "MemberOverrideRows")
    rows := IteratorOrderingRequiredList(rowsValue, "MemberOverrideRows")
    prefix := 0
    index := 1
    while index < rows.Count {
        row := rows[index]
        if row == null {
            throw new InvalidOperationException("Iterator override row was null")
        }
        targetField := row.GetType().GetField("ResolvedTarget")
        if targetField == null {
            throw new InvalidOperationException("Iterator override row had no ResolvedTarget")
        }
        if targetField.GetValue(row) == null {
            break
        }
        prefix = prefix + 1
        index = index + 1
    }
    while index < rows.Count {
        later := rows[index]
        if later == null {
            throw new InvalidOperationException("Iterator override row was null")
        }
        laterTarget := later.GetType().GetField("ResolvedTarget")
        if laterTarget == null {
            throw new InvalidOperationException("Iterator override row had no ResolvedTarget")
        }
        if laterTarget.GetValue(later) != null {
            throw new InvalidOperationException("Iterator override targets were not a prefix")
        }
        index = index + 1
    }
    return prefix
}

func IteratorOrderingTraceCount(): int {
    trace := IteratorOrderingCompilerType("ColumnarDeclineTrace")
    snapshot := IteratorOrderingMethod(trace, "Snapshot", (BindingFlags)40, 0)
    emptyArguments := new object?[](0)
    records := snapshot.Invoke(null, emptyArguments) as IList
    if records == null {
        throw new InvalidOperationException("Iterator ordering decline trace was not an IList")
    }
    return records.Count
}

func IteratorOrderingResetTrace() {
    trace := IteratorOrderingCompilerType("ColumnarDeclineTrace")
    reset := IteratorOrderingMethod(trace, "Reset", (BindingFlags)40, 0)
    emptyArguments := new object?[](0)
    ignored := reset.Invoke(null, emptyArguments)
    _ = ignored
}

func IteratorOrderingExceptionText(actual: Exception): string {
    boxed: object = actual
    actualType := boxed.GetType()
    fullName := actualType.get_FullName()
    if fullName == null {
        fullName = actualType.get_Name()
    }
    return fullName + "|" + actual.get_Message()
}

func IteratorOrderingExceptionOutcome(exception: Exception): string {
    innerBox: object? = exception.get_InnerException()
    if innerBox == null {
        return IteratorOrderingExceptionText(exception)
    }
    inner := (Exception)innerBox
    return IteratorOrderingExceptionText(inner)
}

func IteratorOrderingRun(mutation: string): IteratorOrderingOutcome {
    parsed := IteratorOrderingParse()
    rowsValue := IteratorOrderingRequiredMember(parsed.Shape, "MemberOverrideRows")
    rows := IteratorOrderingRequiredList(rowsValue, "MemberOverrideRows")
    if mutation == "direct-missing" || mutation == "direct-null" {
        direct := rows[7]
        if direct == null {
            throw new InvalidOperationException("Missing direct iterator row")
        }
        if mutation == "direct-missing" {
            IteratorOrderingWriteField(direct, "LookupName", "IteratorOrderingMissing")
        } else {
            IteratorOrderingWriteField(direct, "LookupName", null)
        }
    } else if mutation == "property-missing" {
        property := rows[3]
        if property == null {
            throw new InvalidOperationException("Missing property iterator row")
        }
        IteratorOrderingWriteField(property, "LookupName", "IteratorOrderingMissing")
    } else if mutation == "rebound-missing" {
        rebound := rows[2]
        if rebound == null {
            throw new InvalidOperationException("Missing rebound iterator row")
        }
        IteratorOrderingWriteField(rebound, "LookupName", "IteratorOrderingMissing")
    } else if mutation == "body-state" {
        fieldsValue := IteratorOrderingRequiredMember(parsed.Shape, "FieldNames")
        fields := IteratorOrderingRequiredList(fieldsValue, "FieldNames")
        if fields.Count == 0 {
            throw new InvalidOperationException("Unexpected iterator state-field layout")
        }
        firstField := fields[0]
        if Convert.ToString(firstField) != "<>__state" {
            throw new InvalidOperationException("Unexpected iterator state-field layout")
        }
        IteratorOrderingSetArrayCell(fieldsValue, 0, "IteratorOrderingState")
    } else if mutation != "positive" {
        throw new InvalidOperationException("Unknown iterator ordering mutation '" + mutation + "'")
    }

    module := IteratorOrderingNewModule(mutation)
    factoryIl := IteratorOrderingFactoryIl(module, mutation)
    emitterOwner := IteratorOrderingCompilerType("ColumnarIlEmitter")
    emitter := IteratorOrderingMethod(emitterOwner, "TryEmitIteratorStateMachine", (BindingFlags)40, 16)
    values := new object?[](16)
    IteratorOrderingPut(values, 0, module)
    IteratorOrderingPut(values, 1, parsed.Function)
    IteratorOrderingPut(values, 2, 0)
    IteratorOrderingPut(values, 3, "import System.Collections.Generic\n\nfunc* IteratorOrderingControl(): IEnumerable<int> {\n    yield 7\n}\n")
    IteratorOrderingPut(values, 4, parsed.Resolution)
    IteratorOrderingPut(values, 5, factoryIl)
    synthesizedTypes := IteratorOrderingEmptyRuntimeList("System.Reflection.Emit.TypeBuilder")
    IteratorOrderingPut(values, 6, synthesizedTypes)
    IteratorOrderingPut(values, 7, new Type[](0))
    IteratorOrderingPut(values, 8, parsed.Shape)
    IteratorOrderingPut(values, 9, "IteratorOrderingControl")
    IteratorOrderingPut(values, 10, null)
    IteratorOrderingPut(values, 11, null)
    IteratorOrderingPut(values, 12, null)
    IteratorOrderingPut(values, 13, null)
    IteratorOrderingPut(values, 14, null)
    IteratorOrderingPut(values, 15, null)
    IteratorOrderingResetTrace()
    outcome := "false"
    try {
        succeeded := Convert.ToBoolean(emitter.Invoke(null, values))
        if succeeded {
            outcome = "success"
        }
    } catch exception: Exception {
        outcome = IteratorOrderingExceptionOutcome(exception)
    }
    resolvedPrefix := IteratorOrderingResolvedPrefix(parsed.Shape)
    traceCount := IteratorOrderingTraceCount()
    return new IteratorOrderingOutcome(outcome, resolvedPrefix, traceCount)
}

test "a precomputed sync iterator shape keeps attachment and body failures at their original later phases" {
    positive := IteratorOrderingRun("positive")
    assert positive.Outcome == "success"
    assert positive.ResolvedPrefix == 7
    assert positive.TraceCount == 0

    directMissing := IteratorOrderingRun("direct-missing")
    assert directMissing.Outcome == "System.InvalidOperationException|Iterator method-override handles cannot be null."
    assert directMissing.ResolvedPrefix == 6
    assert directMissing.TraceCount == 0

    propertyMissing := IteratorOrderingRun("property-missing")
    assert propertyMissing.Outcome == "System.NullReferenceException|Object reference not set to an instance of an object."
    assert propertyMissing.ResolvedPrefix == 2
    assert propertyMissing.TraceCount == 0

    reboundMissing := IteratorOrderingRun("rebound-missing")
    assert reboundMissing.Outcome == "System.NullReferenceException|Object reference not set to an instance of an object."
    assert reboundMissing.ResolvedPrefix == 1
    assert reboundMissing.TraceCount == 0

    directNull := IteratorOrderingRun("direct-null")
    assert directNull.Outcome == "System.ArgumentNullException|Value cannot be null. (Parameter 'name')"
    assert directNull.ResolvedPrefix == 6
    assert directNull.TraceCount == 0

    bodyState := IteratorOrderingRun("body-state")
    assert bodyState.Outcome == "System.InvalidOperationException|Iterator state machine has no field named '<>__state'."
    assert bodyState.ResolvedPrefix == 1
    assert bodyState.TraceCount == 0
}
