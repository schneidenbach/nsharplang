namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// THE EMIT ESTATE'S OWN FIXTURES.
//
// Backend.Emit's rows build in Compiler.Emit's own assembly, which references every lower slice
// PRODUCT-ONLY, so they cannot call a helper another slice's rows declare: these are the builders,
// reflection lookups and programs the emitter's rows share. Each one spells the Reflection.Emit or
// planner API it stands for directly; the planner rows' helpers of the same shape (`TypeOfCreateBuilder`,
// `ExecutorRequiredMethod`, `ColumnarIteratorShapeProbe` ...) stay with the planner rows.
func EmitFixtureRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("Required emit fixture method was not found: " + name)
    }
    return method
}

func EmitFixtureRequiredConstructor(owner: Type, parameters: Type[]): ConstructorInfo {
    constructorInfo := owner.GetConstructor(parameters)
    if constructorInfo == null {
        throw new InvalidOperationException("Required emit fixture constructor was not found.")
    }
    return constructorInfo
}

func EmitFixtureRequiredGetter(owner: Type, propertyName: string): MethodInfo {
    property := owner.GetProperty(propertyName)
    if property == null {
        throw new InvalidOperationException("Missing property '" + propertyName + "'.")
    }
    getter := property.GetGetMethod()
    if getter == null {
        throw new InvalidOperationException("Missing getter for '" + propertyName + "'.")
    }
    return getter
}

func EmitFixtureSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func EmitFixturePut(values: object?[], index: int, value: object?) {
    values[index] = value
}

// A reflection call whose answer the row needs: a null answer is a fixture failure, not a value.
func EmitFixtureInvoke(method: MethodInfo, target: object?, arguments: object[]): object {
    value := method.Invoke(target, arguments)
    if value == null {
        throw new InvalidOperationException("Required emit fixture invocation of " + method.get_Name() + " returned null.")
    }
    return value
}

func EmitFixtureNoStrings(): string[] {
    return new string[](0)
}

func EmitFixtureOneString(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

// ── Reflection.Emit builders ────────────────────────────────────────────────────────────────────

// A public type in its own run-only dynamic assembly, with `T0..Tn` when it is generic.
func EmitFixtureTypeBuilder(name: string, assemblyIdentity: string, genericParameterCount: int): TypeBuilder {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(assemblyIdentity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(name)
    builder := module.DefineType(name, TypeAttributes.Public)
    if genericParameterCount > 0 {
        builder.DefineGenericParameters(EmitFixtureGenericParameterNames(genericParameterCount))
    }
    return builder
}

// A public type in a PERSISTED assembly -- the builder family the emitter itself writes with, whose
// pre-bake companions differ from the run-only builder's (see `ColumnarExternalTypeGuardFacts`).
func EmitFixturePersistedBuilder(fullName: string, genericParameterCount: int, parent: Type): TypeBuilder {
    assembly := new PersistedAssemblyBuilder(new AssemblyName("EmitFixturePersistedAsm"), typeof(object).get_Assembly())
    module := assembly.DefineDynamicModule("EmitFixturePersistedModule")
    builder := module.DefineType(fullName, TypeAttributes.Public, parent)
    if genericParameterCount > 0 {
        builder.DefineGenericParameters(EmitFixtureGenericParameterNames(genericParameterCount))
    }
    return builder
}

func EmitFixtureGenericParameterNames(count: int): string[] {
    names := new string[](count)
    index := 0
    while index < names.Length {
        names[index] = "T" + index.ToString()
        index = index + 1
    }
    return names
}

func EmitFixtureFirstGenericMethodParameter(method: MethodBuilder, parameterName: string): Type {
    parameters := method.DefineGenericParameters(EmitFixtureOneString(parameterName))
    if parameters.Length != 1 {
        throw new InvalidOperationException("The method generic fixture did not define one parameter.")
    }
    return parameters[0]
}

func EmitFixtureBake(builder: TypeBuilder): Type {
    baked := builder.CreateType()
    if baked == null {
        throw new InvalidOperationException("The emit fixture did not produce a runtime type.")
    }
    return baked
}

func EmitFixtureIL(methodBuilder: MethodBuilder): ILGenerator {
    return methodBuilder.GetILGenerator()
}

func EmitFixtureReturnThis(method: MethodBuilder) {
    il := method.GetILGenerator()
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ret)
}

func EmitFixtureDefineField(owner: TypeBuilder, fieldName: string, fieldType: Type): FieldBuilder {
    return owner.DefineField(fieldName, fieldType, (FieldAttributes)6)
}

// A public instance method on a source definition, recorded the way the declaration walk records
// one: first overload of a name is also its `Methods` entry.
func EmitFixturePublicInstance(owner: ColumnarStructDef, memberName: string, parameterTypes: Type[], returnType: Type): ColumnarInstanceMethodDef {
    method := owner.Builder.DefineMethod(memberName, (MethodAttributes)6, returnType, parameterTypes)
    definition := new ColumnarInstanceMethodDef(method, parameterTypes, new int[](0), returnType)
    overloads := new List<ColumnarInstanceMethodDef>()
    if !owner.MethodOverloads.TryGetValue(memberName, out overloads) {
        overloads = new List<ColumnarInstanceMethodDef>()
        owner.MethodOverloads[memberName] = overloads
    }
    overloads.Add(definition)
    if !owner.Methods.ContainsKey(memberName) {
        owner.Methods[memberName] = definition
    }
    return definition
}

// ── programs and type resolution ────────────────────────────────────────────────────────────────

// A real multi-file program, each source under its namespace (none when the namespace is empty).
func EmitFixtureProgram(namespaces: string[], sources: string[], fileStem: string): ColumnarProgramInput {
    texts := new List<string>()
    names := new List<string>()
    index := 0
    while index < sources.Length {
        prefix := ""
        if namespaces[index].Length > 0 {
            prefix = "namespace " + namespaces[index] + "\n\n"
        }
        texts.Add(prefix + sources[index])
        names.Add("/tmp/" + fileStem + index.ToString() + ".nl")
        index = index + 1
    }
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(texts, names, "/tmp", out program)
    return program
}

// The source files alone, with no declaration inputs: a binding scope over exactly these texts.
func EmitFixtureSourceProgram(sources: string[], fileNames: string[]): ColumnarProgramInput {
    program := ColumnarProgramInput.CreateFromSourceFiles(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        new List<ColumnarStructInput>(),
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
    program.PrepareExternalTypeBindings(null)
    return program
}

func EmitFixtureTypeResolution(
    program: ColumnarProgramInput,
    sourceFileId: int,
    enums: Dictionary<string, ColumnarEnumDef>,
    structs: Dictionary<string, ColumnarStructDef>,
    unions: Dictionary<string, ColumnarUnionDef>,
    typeParameters: Dictionary<string, Type>?,
    enclosingSourceDeclarationName: string?
): ColumnarSemanticTypeResolution {
    catalog := new ColumnarSemanticTypeResolutionCatalog(program, enums, structs, unions)
    return catalog.For(sourceFileId, typeParameters, enclosingSourceDeclarationName)
}

func EmitFixtureEmptyEnums(): Dictionary<string, ColumnarEnumDef> {
    return new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
}

func EmitFixtureEmptyStructs(): Dictionary<string, ColumnarStructDef> {
    return new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
}

func EmitFixtureEmptyUnions(): Dictionary<string, ColumnarUnionDef> {
    return new Dictionary<string, ColumnarUnionDef>(StringComparer.Ordinal)
}

// ── source definitions and constructor rows the declaration walk would build ────────────────────

func EmitFixtureStructDefinition(name: string, genericParameterCount: int): ColumnarStructDef {
    builder := EmitFixtureTypeBuilder(name, "ColumnarEmitFixtures." + name, genericParameterCount)
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        name
    )
}

// A body with no statements: one empty block node.
func EmitFixtureEmptyBody(name: string, parameterNames: string[], parameterCanonicals: string[]): ColumnarFunctionInput {
    zero := new int[](1)
    nodes := new ColumnarNodeTable(zero, zero, zero, zero, zero, new int[](0), zero, zero)
    return new ColumnarFunctionInput(name, "void", parameterNames, parameterCanonicals, nodes, 0, false)
}

func EmitFixtureConstructor(
    body: ColumnarFunctionInput,
    chainKind: int,
    chainArgumentKinds: int[],
    chainArgumentTexts: string[],
    isSynthesizedInitializer: bool = false
): ColumnarConstructorInput {
    return new ColumnarConstructorInput(body, chainKind, chainArgumentKinds, chainArgumentTexts, null, null, isSynthesizedInitializer, 0)
}

func EmitFixtureStructInput(name: string, constructors: IReadOnlyList<ColumnarConstructorInput>): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        new List<ColumnarFunctionInput>(),
        constructors,
        new List<ColumnarPropertyInput>(),
        true
    )
}

func EmitFixtureSingleSourceProgram(source: string, structs: IReadOnlyList<ColumnarStructInput>): ColumnarProgramInput {
    return ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        structs,
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
}

// One type-resolution view per definition, each resolving the whole set by declared name.
func EmitFixtureResolutions(program: ColumnarProgramInput, definitions: ColumnarStructDef[]): ColumnarSemanticTypeResolution[] {
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    for definition in definitions {
        registry[definition.DeclaredTypeName] = definition
    }
    resolutions := new ColumnarSemanticTypeResolution[](definitions.Length)
    index := 0
    while index < definitions.Length {
        resolutions[index] = EmitFixtureTypeResolution(program, 0, EmitFixtureEmptyEnums(), registry, EmitFixtureEmptyUnions(), null, definitions[index].DeclaredTypeName)
        index = index + 1
    }
    return resolutions
}

// ── IL a row can read back ──────────────────────────────────────────────────────────────────────

// A generator over a throwaway dynamic method, for rows that emit a handful of instructions.
func EmitFixtureDynamicIl(name: string): ILGenerator {
    return new DynamicMethod(name, typeof(int), new Type[](0)).GetILGenerator()
}

func EmitFixtureIntParameters(count: int): Type[] {
    types := new Type[](count)
    index := 0
    while index < types.Length {
        types[index] = typeof(int)
        index = index + 1
    }
    return types
}

func EmitFixtureNamedMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("The baked emit fixture has no method " + name + ".")
    }
    return method
}

// A baked method's IL bytes, each as an int so a row can compare it with an opcode's value.
func EmitFixtureIlBytes(method: MethodBase): int[] {
    body := method.GetMethodBody()
    if body == null {
        throw new InvalidOperationException("The baked emit fixture has no method body.")
    }
    bytes := body.GetILAsByteArray()
    if bytes == null {
        throw new InvalidOperationException("The baked emit fixture exposed no IL bytes.")
    }
    values := new int[](bytes.Length)
    index := 0
    while index < values.Length {
        values[index] = Convert.ToInt32(bytes[index])
        index = index + 1
    }
    return values
}

// ── an iterator's classified shape, from the source of one `func*` ──────────────────────────────

// The realization rows hand the emitter a shape the planner classified from real source, parsed and
// bound the way the emission host parses and binds it.
class EmitFixtureIteratorShapeProbe {
    Shape: ColumnarIteratorShape
    Nodes: ColumnarNodeTable
    BodyRoot: int
    Source: string

    constructor(
        source: string,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        typeParamNames: string[],
        isInstance: bool,
        isAsync: bool = false
    ) {
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        tokenKinds := new int[](capacity)
        tokenStarts := new int[](capacity)
        tokenValueLengths := new int[](capacity)
        tokenCounts := new int[](2)
        tokenCount := TokenizeColumnarSourceInto(
            source,
            rawKinds,
            rawStarts,
            rawValueLengths,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCounts
        )

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        returnLabeledTypeTexts := new string[](capacity)
        paramLabeledTypeTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        status := ParseColumnarProductFunctionInfoInto(
            source,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            funcIndex,
            0,
            functionNameTexts,
            returnTypeTexts,
            paramNameTexts,
            paramTypeTexts,
            paramModifierKinds,
            paramDefaultKinds,
            paramDefaultTexts,
            paramTupleNameCounts,
            paramTupleNameTexts,
            returnTupleNameTexts,
            returnLabeledTypeTexts,
            paramLabeledTypeTexts,
            typeParamTexts,
            typeParamSpecials,
            typeParamConstraintCounts,
            typeParamConstraintTypeTexts,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths,
            localFunctionNodeIndices,
            localFunctionTokenIndices,
            result
        )
        if status < 0 {
            throw new InvalidOperationException("Iterator-shape probe could not parse the func* body.")
        }

        bodyRoot := result[6]
        nodes := new ColumnarNodeTable(
            nodeKinds,
            valueStarts,
            valueLengths,
            childStart,
            childCount,
            childIndices,
            spanStarts,
            spanLengths
        )
        // The body's own expressions resolve through the scope the emission host stamps: over the
        // probe's source plus the imports every generator here uses.
        scopeSources := new string[](1)
        scopeFileNames := new string[](1)
        scopeSources[0] = "import System\nimport System.Collections.Generic\nimport System.Threading.Tasks\n" + source
        scopeFileNames[0] = "iterator-probe.nl"
        scope := ColumnarBindingScopeFacts.Create(
            ColumnarEmissionPlanner.BuildSourceFiles(scopeSources, scopeFileNames),
            new List<ColumnarEnumInput>(),
            new List<ColumnarStructInput>(),
            new List<ColumnarUnionInput>(),
            new List<ColumnarInterfaceInput>(),
            null
        )
        scope.PrepareExternalTypeBindings(null)
        nodes.SetBindingContext(scope.ForSourceFile(0), "", typeParamNames, null)

        Nodes = nodes
        BodyRoot = bodyRoot
        Source = source
        Shape = ColumnarIteratorPlanner.AnalyzeShape(
            nodes,
            source,
            bodyRoot,
            "Gen",
            0,
            returnCanonical,
            paramNames,
            paramCanonicals,
            typeParamNames,
            isInstance,
            "",
            new string[](0),
            new string[](0),
            isAsync
        )
    }
}
