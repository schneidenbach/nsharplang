namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// The complete result of one iterator-realization attempt. The C# boundary retains ambient decline
// tracing and records these facts immediately when realization returns an unsupported result.
class ColumnarIteratorRealizationResult {
    Succeeded: bool
    DeclineSite: string
    DeclineMessage: string
    DeclineMember: string

    constructor(succeeded: bool, declineSite: string, declineMessage: string, declineMember: string) {
        Succeeded = succeeded
        DeclineSite = declineSite
        DeclineMessage = declineMessage
        DeclineMember = declineMember
    }
}

// Owns iterator-specific canonical resolution together with the CLR declaration and plan-execution
// sequence. Emission-host entry points retain their established tracing boundary.
class ColumnarIteratorRealization {
    static func ModifiedMemberReferencesOf(bodyFacts: ColumnarIteratorBodyFacts?): ColumnarModifiedMemberReferenceLedger? {
        if bodyFacts == null {
            return null
        }
        return bodyFacts.ModifiedMemberReferences
    }

    static func EmitMember(
        module: ModuleBuilder,
        structDef: ColumnarStructDef,
        method: ColumnarFunctionInput,
        builder: MethodBuilder,
        isStatic: bool,
        program: ColumnarProgramInput,
        typeResolution: ColumnarSemanticTypeResolution,
        methodSource: string,
        synthesizedTypes: List<TypeBuilder>,
        ordinalCounter: int[],
        bodyFacts: ColumnarIteratorBodyFacts? = null
    ): ColumnarIteratorRealizationResult {
        enclosingBuilder: Type = structDef.Builder
        enclosingBuilderName := enclosingBuilder.Name
        memberName := method.Name
        memberLabel := enclosingBuilderName + "." + memberName
        if method.IsAsync {
            return Declined(
                "emit.iterator.async-unsupported",
                "async member iterator methods are not yet lowered",
                memberLabel
            )
        }
        if isStatic {
            staticOrdinal := ordinalCounter[0]
            ordinalCounter[0] = staticOrdinal + 1
            staticFactoryIl := builder.GetILGenerator()
            // A static generator has no receiver to hoist, but its body still names its OWNER's type
            // parameters as well as its own: `Box<T>.Repeat(value: T)`. The machine restates both
            // lists, the owner's first, and the factory instantiates it over the exact builders the
            // declaring type and the method define.
            return EmitSync(
                module,
                method,
                staticOrdinal,
                methodSource,
                typeResolution,
                staticFactoryIl,
                synthesizedTypes,
                StaticMachineArguments(structDef, builder),
                null,
                memberLabel,
                null,
                null,
                null,
                null,
                null,
                null,
                bodyFacts,
                structDef
            )
        }
        if structDef.GenericParameters != null || method.TypeParamNames.Length > 0 {
            return Declined(
                "emit.iterator.instance-unsupported",
                "generic instance iterator methods are not yet lowered",
                memberLabel
            )
        }

        input: ColumnarStructInput? = null
        structEnumerator := StructInputEnumerator(program.Structs)
        structMovement := structEnumerator as IEnumerator
        try {
            if structMovement == null {
                throw new NullReferenceException()
            }
            while structMovement.MoveNext() {
                candidate := structEnumerator.get_Current()
                if candidate.Name == structDef.DeclaredTypeName || structDef.DeclaredTypeName.EndsWith("." + candidate.Name, StringComparison.Ordinal) {
                    input = candidate
                    break
                }
            }
        } finally {
            structDisposable := structEnumerator as IDisposable
            if structDisposable != null {
                structDisposable.Dispose()
            }
        }
        if input == null {
            return Declined(
                "emit.iterator.instance-unsupported",
                "enclosing type facts are unavailable for '" + memberLabel + "'",
                memberLabel
            )
        }

        fieldNames := new List<string>()
        fieldCanonicals := new List<string>()
        fieldHandles := new List<FieldInfo>()
        fieldIndex := 0
        while fieldIndex < input.FieldNames.Length {
            name := input.FieldNames[fieldIndex]
            if name.Length > 0 && char.IsUpper(name[0]) {
                fieldBuilder: FieldBuilder = null
                if structDef.Fields.TryGetValue(name, out fieldBuilder) {
                    fieldNames.Add(name)
                    fieldCanonicals.Add(input.FieldTypeCanonicals[fieldIndex])
                    fieldHandle: FieldInfo = fieldBuilder
                    fieldHandles.Add(fieldHandle)
                }
            }
            fieldIndex = fieldIndex + 1
        }

        methodNames := new List<string>()
        methodReturns := new List<string>()
        methodHandles := new List<MethodInfo>()
        methodEnumerator := MethodInputEnumerator(input.Methods)
        methodMovement := methodEnumerator as IEnumerator
        try {
            if methodMovement == null {
                throw new NullReferenceException()
            }
            while methodMovement.MoveNext() {
                candidateMethod := methodEnumerator.get_Current()
                if candidateMethod.Name.Length > 0 && char.IsUpper(candidateMethod.Name[0]) && !candidateMethod.IsStatic {
                    methodDefinition: ColumnarInstanceMethodDef = null
                    if structDef.Methods.TryGetValue(candidateMethod.Name, out methodDefinition) {
                        overloads: List<ColumnarInstanceMethodDef>? = null
                        hasMultipleOverloads := false
                        if structDef.MethodOverloads.TryGetValue(candidateMethod.Name, out overloads) {
                            hasMultipleOverloads = MethodOverloadCount(overloads) > 1
                        }
                        if !hasMultipleOverloads {
                            methodNames.Add(candidateMethod.Name)
                            methodReturns.Add(candidateMethod.ReturnCanonical)
                            methodHandle: MethodInfo = ((ColumnarInstanceMethodDef)methodDefinition).Builder
                            methodHandles.Add(methodHandle)
                        }
                    }
                }
            }
        } finally {
            methodDisposable := methodEnumerator as IDisposable
            if methodDisposable != null {
                methodDisposable.Dispose()
            }
        }

        shapeNodes := method.BodyNodes
        shapeRoot := method.BodyRoot
        shapeName := method.Name
        shapeOrdinal := ordinalCounter[0]
        ordinalCounter[0] = shapeOrdinal + 1
        shapeReturn := method.ReturnCanonical
        shapeParamNames := method.ParamNames
        shapeParamCanonicals := method.ParamCanonicals
        shapeTypeParamNames := method.TypeParamNames
        shapeInputName := input.Name
        shapeFieldNames := fieldNames.ToArray()
        shapeFieldCanonicals := fieldCanonicals.ToArray()
        shapeMethodNames := methodNames.ToArray()
        shapeMethodReturns := methodReturns.ToArray()
        shape := ColumnarIteratorPlanner.AnalyzeShape(
            shapeNodes,
            methodSource,
            shapeRoot,
            shapeName,
            shapeOrdinal,
            shapeReturn,
            shapeParamNames,
            shapeParamCanonicals,
            shapeTypeParamNames,
            true,
            shapeInputName,
            shapeFieldNames,
            shapeFieldCanonicals,
            shapeMethodNames,
            shapeMethodReturns,
            false
        )
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, memberLabel)
        }

        factoryIl := builder.GetILGenerator()
        emptyTypeParameters: Type[] = System.Type.EmptyTypes
        enclosingType: Type = structDef.Builder
        realizedFieldNames := fieldNames.ToArray()
        realizedFieldHandles := fieldHandles.ToArray()
        realizedFieldCanonicals := fieldCanonicals.ToArray()
        realizedMethodNames := methodNames.ToArray()
        realizedMethodHandles := methodHandles.ToArray()
        return EmitSync(
            module,
            method,
            0,
            methodSource,
            typeResolution,
            factoryIl,
            synthesizedTypes,
            emptyTypeParameters,
            shape,
            memberLabel,
            enclosingType,
            realizedFieldNames,
            realizedFieldHandles,
            realizedFieldCanonicals,
            realizedMethodNames,
            realizedMethodHandles,
            bodyFacts,
            null
        )
    }

    static func StructInputEnumerator(
        inputs: IEnumerable<ColumnarStructInput>
    ): IEnumerator<ColumnarStructInput> {
        return inputs.GetEnumerator()
    }

    static func MethodInputEnumerator(
        inputs: IEnumerable<ColumnarFunctionInput>
    ): IEnumerator<ColumnarFunctionInput> {
        return inputs.GetEnumerator()
    }

    static func MethodOverloadCount(overloads: List<ColumnarInstanceMethodDef>?): int {
        if overloads == null {
            throw new NullReferenceException()
        }

        return overloads.Count
    }

    static func EmitSync(
        module: ModuleBuilder,
        fn: ColumnarFunctionInput,
        funcOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        factoryIl: ILGenerator,
        synthesizedTypes: List<TypeBuilder>,
        methodTypeParams: Type[],
        precomputedShape: ColumnarIteratorShape? = null,
        memberLabel: string = "",
        enclosingType: Type? = null,
        enclosingFieldNames: string[]? = null,
        enclosingFields: FieldInfo[]? = null,
        enclosingFieldCanonicals: string[]? = null,
        enclosingMethodNames: string[]? = null,
        enclosingMethods: MethodInfo[]? = null,
        bodyFacts: ColumnarIteratorBodyFacts? = null,
        genericOwner: ColumnarStructDef? = null
    ): ColumnarIteratorRealizationResult {
        modifiedMemberReferences := ModifiedMemberReferencesOf(bodyFacts)
        declineLabel := memberLabel.Length == 0 ? fn.Name : memberLabel
        shape := SyncShape(fn, funcOrdinal, functionSource, precomputedShape)
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, declineLabel)
        }

        // The machine's parameter list: the function's own, preceded by its generic owner's when a
        // static member generator is lowered. `methodTypeParams` lists the factory's instantiation
        // in this same order.
        machineTypeParamNames := fn.TypeParamNames
        machineSpecialConstraints := fn.TypeParamSpecialConstraints
        machineTypeConstraints := fn.TypeParamTypeConstraints
        if genericOwner != null && genericOwner.GenericParameterNames.Length > 0 {
            machineTypeParamNames = OwnerFirstNames(genericOwner.GenericParameterNames, fn.TypeParamNames)
            machineSpecialConstraints = OwnerFirstSpecials(genericOwner.GenericParameterNames.Length, genericOwner.GenericParameterSpecialConstraints, fn.TypeParamNames.Length, fn.TypeParamSpecialConstraints)
            machineTypeConstraints = OwnerFirstTypeConstraints(genericOwner.GenericParameterNames.Length, genericOwner.GenericParameterTypeConstraints, fn.TypeParamNames.Length, fn.TypeParamTypeConstraints)
        }

        sm := module.DefineType(
            shape.TypeName,
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed
        )
        smTypeParamMap: Dictionary<string, Type>? = null
        smTypeParams := System.Type.EmptyTypes
        smSpecialConstraints := System.Array.Empty<int>()
        smBaseConstraints := System.Array.Empty<Type>()
        smInterfaceConstraints := System.Array.Empty<Type[]>()
        table := typeResolution.StructuralTypeReferences
        if machineTypeParamNames.Length > 0 {
            smGps := sm.DefineGenericParameters(machineTypeParamNames)
            smTypeParamMap = new Dictionary<string, Type>(StringComparer.Ordinal)
            smTypeParams = new Type[](smGps.Length)
            g := 0
            while g < smGps.Length {
                parameter: Type = smGps[g]
                smTypeParamMap[machineTypeParamNames[g]] = parameter
                smTypeParams[g] = parameter
                g = g + 1
            }
            // A dependent constraint such as `where U: T` resolves T through this exact structural
            // owner. Publish the machine's generic parameters before asking the shared constraint
            // planner to resolve those rows; the runtime type itself is still unbaked, as intended.
            table.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, smTypeParamMap)
            if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(smGps, machineSpecialConstraints, machineTypeConstraints, smTypeParamMap, smTypeParams, typeResolution, out smSpecialConstraints, out smBaseConstraints, out smInterfaceConstraints) {
                return Declined(
                    "emit.iterator.generic-constraints",
                    "iterator generic constraints could not be preserved for '" + declineLabel + "'",
                    declineLabel
                )
            }
        } else {
            table.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, null)
        }
        elementType: Type = null
        if !TryResolveIteratorCanonical(shape.ElementCanonical, smTypeParamMap, typeResolution, out elementType) {
            return Declined(
                "emit.iterator.element-type",
                "iterator element type '" + shape.ElementCanonical + "' could not be resolved for '" + declineLabel + "'",
                declineLabel
            )
        }

        enumerableOfT := ColumnarIteratorBodyPlanner.EnumerableInterfaceTypeOf(elementType)
        enumeratorOfT := ColumnarIteratorBodyPlanner.EnumeratorInterfaceTypeOf(elementType)
        sm.AddInterfaceImplementation(enumerableOfT)
        sm.AddInterfaceImplementation(enumeratorOfT)
        sm.AddInterfaceImplementation(typeof(System.Collections.IEnumerable))
        sm.AddInterfaceImplementation(typeof(System.Collections.IEnumerator))
        sm.AddInterfaceImplementation(typeof(IDisposable))

        fields := new FieldInfo[](shape.FieldCount)
        fieldBuilders := new FieldBuilder[](shape.FieldCount)
        i := 0
        while i < shape.FieldCount {
            // A hoisted field whose canonical is UNRESOLVED is defined by the body lowering, from the
            // exact CLR type the one expression owner gives its initializer (or its enumerated source).
            // Everything written in the signature — the state, the current value, every captured
            // parameter and every explicitly typed local — resolves from its own spelling here.
            if ColumnarIteratorPlanner.IsUnresolvedCanonical(shape.FieldCanonicals[i]) {
                i = i + 1
                continue
            }
            fieldType: Type = null
            if !TryResolveIteratorCanonical(shape.FieldCanonicals[i], smTypeParamMap, typeResolution, out fieldType) {
                return Declined(
                    "emit.iterator.field-type",
                    "iterator hoisted field type '" + shape.FieldCanonicals[i] + "' could not be resolved for '" + declineLabel + "'",
                    declineLabel
                )
            }
            if shape.FieldRoles[i] == ColumnarIteratorPlanner.LoopCaptureBoxFieldRole() {
                fieldType = ColumnarIteratorPlanner.LoopCaptureBoxType(fieldType)
            }
            fieldBuilder := sm.DefineField(shape.FieldNames[i], fieldType, FieldAttributes.Public)
            fieldHandle: FieldInfo = fieldBuilder
            fieldBuilders[i] = fieldBuilder
            fields[i] = fieldHandle
            i = i + 1
        }

        constructorTypes := new Type[](1)
        constructorTypes[0] = typeof(int)
        ctor := sm.DefineConstructor(
            MethodAttributes.Public | MethodAttributes.HideBySig,
            CallingConventions.Standard,
            constructorTypes
        )
        smDefinition: Type = sm
        memberSmType: Type = sm
        memberFields := fields
        memberCtor: ConstructorInfo = ctor
        if smTypeParamMap != null {
            memberSmType = smDefinition.MakeGenericType(smTypeParams)
            memberFields = new FieldInfo[](fields.Length)
            i = 0
            while i < fields.Length {
                if fieldBuilders[i] != null {
                    memberFields[i] = TypeBuilder.GetField(memberSmType, fieldBuilders[i])
                }
                i = i + 1
            }
            memberCtor = TypeBuilder.GetConstructor(memberSmType, ctor)
        }

        ctorIl := ctor.GetILGenerator()
        ctorIl.Emit(OpCodes.Ldarg_0)
        objectCtor := typeof(object).GetConstructor(System.Type.EmptyTypes)
        ctorIl.Emit(OpCodes.Call, objectCtor)
        ctorIl.Emit(OpCodes.Ldarg_0)
        ctorIl.Emit(OpCodes.Ldarg_1)
        ctorIl.Emit(OpCodes.Stfld, memberFields[0])
        ctorIl.Emit(OpCodes.Ret)

        genericMemberType: Type? = null
        if smTypeParamMap != null {
            genericMemberType = memberSmType
        }
        context := new ColumnarIteratorEmitContext(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            shape,
            memberSmType,
            elementType,
            shape.FieldNames,
            memberFields,
            table,
            memberCtor,
            enclosingType,
            enclosingFieldNames,
            enclosingFields,
            enclosingFieldCanonicals,
            enclosingMethodNames,
            enclosingMethods,
            null,
            bodyFacts,
            sm,
            genericMemberType,
            smTypeParamMap,
            fieldBuilders,
            synthesizedTypes,
            fn.SourceFileId,
            smSpecialConstraints,
            smBaseConstraints,
            smInterfaceConstraints,
            smTypeParams
        )
        overrideContext := ColumnarIteratorOverrideContext.ForSync(table, elementType, enumerableOfT, enumeratorOfT)
        publicImpl := MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot
        explicitImpl := MethodAttributes.Private | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot

        moveNext := sm.DefineMethod(shape.MemberNames[1], publicImpl, typeof(bool), System.Type.EmptyTypes)
        shape.MemberOverrideRows[1].Apply(overrideContext, sm, moveNext)
        moveNextPlan := ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context)
        if context.Declined {
            return Declined(context.DeclineSite, context.DeclineMessage + " in '" + declineLabel + "'", declineLabel)
        }
        moveNextIl := moveNext.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNextIl, modifiedMemberReferences)
        // `Dispose` drives this exact handle to unwind a machine abandoned inside a protected region.
        // A generic machine's members are taken on the instantiation its fields already came from.
        moveNextHandle: MethodInfo = moveNext
        if smTypeParamMap != null {
            moveNextHandle = TypeBuilder.GetMethod(memberSmType, moveNext)
        }
        context.MoveNextMethod = moveNextHandle

        getCurrent := sm.DefineMethod(
            shape.MemberNames[2],
            publicImpl | MethodAttributes.SpecialName,
            elementType,
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[2].Apply(overrideContext, sm, getCurrent)
        getCurrentPlan := ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context)
        getCurrentIl := getCurrent.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(getCurrentPlan, getCurrentIl)

        interfaceCurrent := sm.DefineMethod(
            shape.MemberNames[3],
            explicitImpl | MethodAttributes.SpecialName,
            typeof(object),
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[3].Apply(overrideContext, sm, interfaceCurrent)
        interfaceCurrentPlan := ColumnarIteratorBodyPlanner.BuildInterfaceGetCurrentPlan(context)
        interfaceCurrentIl := interfaceCurrent.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(interfaceCurrentPlan, interfaceCurrentIl)

        voidType := ColumnarTypeOfPlanner.RequiredVoidType()
        reset := sm.DefineMethod(shape.MemberNames[4], explicitImpl, voidType, System.Type.EmptyTypes)
        shape.MemberOverrideRows[4].Apply(overrideContext, sm, reset)
        resetPlan := ColumnarIteratorBodyPlanner.BuildResetPlan()
        resetIl := reset.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(resetPlan, resetIl)

        dispose := sm.DefineMethod(shape.MemberNames[5], explicitImpl, voidType, System.Type.EmptyTypes)
        shape.MemberOverrideRows[5].Apply(overrideContext, sm, dispose)
        disposePlan := ColumnarIteratorBodyPlanner.BuildDisposePlan(context)
        disposeIl := dispose.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(disposePlan, disposeIl)

        getEnumerator := sm.DefineMethod(shape.MemberNames[6], publicImpl, enumeratorOfT, System.Type.EmptyTypes)
        shape.MemberOverrideRows[6].Apply(overrideContext, sm, getEnumerator)
        getEnumeratorPlan := ColumnarIteratorBodyPlanner.BuildGetEnumeratorPlan(context)
        getEnumeratorIl := getEnumerator.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(getEnumeratorPlan, getEnumeratorIl)

        interfaceGetEnumerator := sm.DefineMethod(
            shape.MemberNames[7],
            explicitImpl,
            typeof(System.Collections.IEnumerator),
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[7].Apply(overrideContext, sm, interfaceGetEnumerator)
        interfaceGetEnumeratorPlan := ColumnarIteratorBodyPlanner.BuildInterfaceGetEnumeratorPlan(context)
        interfaceGetEnumeratorIl := interfaceGetEnumerator.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(interfaceGetEnumeratorPlan, interfaceGetEnumeratorIl)

        factoryContext := context
        if smTypeParamMap != null {
            factorySmType := smDefinition.MakeGenericType(methodTypeParams)
            factoryFields := new FieldInfo[](fields.Length)
            i = 0
            while i < fields.Length {
                if fieldBuilders[i] != null {
                    factoryFields[i] = TypeBuilder.GetField(factorySmType, fieldBuilders[i])
                }
                i = i + 1
            }
            factoryCtor := TypeBuilder.GetConstructor(factorySmType, ctor)
            factoryContext = new ColumnarIteratorEmitContext(
                fn.BodyNodes,
                functionSource,
                fn.BodyRoot,
                shape,
                factorySmType,
                elementType,
                shape.FieldNames,
                factoryFields,
                table,
                factoryCtor
            )
        }
        factoryPlan := ColumnarIteratorBodyPlanner.BuildFactoryPlan(factoryContext)
        ColumnarCodePlanExecutor.Execute(factoryPlan, factoryIl, modifiedMemberReferences)
        synthesizedTypes.Add(sm)
        return Completed()
    }

    static func EmitAsync(
        module: ModuleBuilder,
        fn: ColumnarFunctionInput,
        funcOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        factoryIl: ILGenerator,
        synthesizedTypes: List<TypeBuilder>,
        bodyFacts: ColumnarIteratorBodyFacts? = null
    ): ColumnarIteratorRealizationResult {
        modifiedMemberReferences := ModifiedMemberReferencesOf(bodyFacts)
        shape := ColumnarIteratorPlanner.AnalyzeShape(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            fn.Name,
            funcOrdinal,
            fn.ReturnCanonical,
            fn.ParamNames,
            fn.ParamCanonicals,
            fn.TypeParamNames,
            false,
            "",
            null,
            null,
            null,
            null,
            true
        )
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, fn.Name)
        }
        elementType: Type = null
        if !ColumnarCanonicalTypeResolver.TryResolveType(
            shape.ElementCanonical,
            typeResolution.Enums,
            typeResolution.Structs,
            typeResolution.Unions,
            out elementType
        ) || !ColumnarTypeOfPlanner.IsSupportedType(elementType) {
            return Declined(
                "emit.iterator.element-type",
                "iterator element type '" + shape.ElementCanonical + "' could not be resolved for '" + fn.Name + "'",
                fn.Name
            )
        }

        sm := module.DefineType(
            shape.TypeName,
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed
        )
        table := typeResolution.StructuralTypeReferences
        table.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, null)
        asyncEnumerable := ColumnarIteratorBodyPlanner.AsyncEnumerableInterfaceTypeOf(elementType)
        asyncEnumerator := ColumnarIteratorBodyPlanner.AsyncEnumeratorInterfaceTypeOf(elementType)
        sm.AddInterfaceImplementation(asyncEnumerable)
        sm.AddInterfaceImplementation(asyncEnumerator)
        sm.AddInterfaceImplementation(typeof(IAsyncDisposable))

        fields := new FieldInfo[](shape.FieldCount)
        continuationField: FieldInfo = null
        i := 0
        while i < shape.FieldCount {
            fieldType: Type = null
            role := shape.FieldRoles[i]
            if role == ColumnarIteratorPlanner.AwaiterFieldRole() {
                // An awaiter's type is whatever the awaited operand's own `GetAwaiter()` returns —
                // `TaskAwaiter` for a unit task, `TaskAwaiter<T>` for a value-producing one, and a
                // user awaitable's own awaiter for anything else. The body lowering defines the field
                // when it reaches the suspension point, exactly as it defines a `:=` local's.
                i = i + 1
                continue
            } else if role == ColumnarIteratorPlanner.PromiseFieldRole() {
                fieldType = typeof(System.Threading.Tasks.TaskCompletionSource<bool>)
            } else if role == ColumnarIteratorPlanner.ResultFieldRole() {
                fieldType = typeof(bool)
            } else if role == ColumnarIteratorPlanner.ContinuationFieldRole() {
                fieldType = typeof(Action)
            } else if ColumnarIteratorPlanner.IsUnresolvedCanonical(shape.FieldCanonicals[i]) {
                // Defined by the body lowering from the initializer's exact CLR type, exactly as the
                // synchronous machine does.
                i = i + 1
                continue
            } else if !ColumnarCanonicalTypeResolver.TryResolveType(
                shape.FieldCanonicals[i],
                typeResolution.Enums,
                typeResolution.Structs,
                typeResolution.Unions,
                out fieldType
            ) || !ColumnarTypeOfPlanner.IsSupportedType(fieldType) {
                return Declined(
                    "emit.iterator.field-type",
                    "iterator hoisted field type '" + shape.FieldCanonicals[i] + "' could not be resolved for '" + fn.Name + "'",
                    fn.Name
                )
            }
            if role == ColumnarIteratorPlanner.LoopCaptureBoxFieldRole() {
                fieldType = ColumnarIteratorPlanner.LoopCaptureBoxType(fieldType)
            }
            fieldBuilder := sm.DefineField(shape.FieldNames[i], fieldType, FieldAttributes.Public)
            fieldHandle: FieldInfo = fieldBuilder
            fields[i] = fieldHandle
            if role == ColumnarIteratorPlanner.ContinuationFieldRole() {
                continuationField = fields[i]
            }
            i = i + 1
        }

        voidType := ColumnarTypeOfPlanner.RequiredVoidType()
        core := sm.DefineMethod(shape.MemberNames[1], MethodAttributes.Public | MethodAttributes.HideBySig, voidType, System.Type.EmptyTypes)
        constructorTypes := new Type[](1)
        constructorTypes[0] = typeof(int)
        ctor := sm.DefineConstructor(
            MethodAttributes.Public | MethodAttributes.HideBySig,
            CallingConventions.Standard,
            constructorTypes
        )
        ctorIl := ctor.GetILGenerator()
        ctorIl.Emit(OpCodes.Ldarg_0)
        objectCtor := typeof(object).GetConstructor(System.Type.EmptyTypes)
        ctorIl.Emit(OpCodes.Call, objectCtor)
        ctorIl.Emit(OpCodes.Ldarg_0)
        ctorIl.Emit(OpCodes.Ldarg_1)
        ctorIl.Emit(OpCodes.Stfld, fields[0])
        ctorIl.Emit(OpCodes.Ldarg_0)
        ctorIl.Emit(OpCodes.Ldarg_0)
        coreHandle: MethodInfo = core
        ctorIl.Emit(OpCodes.Ldftn, coreHandle)
        actionConstructorTypes := new Type[](2)
        actionConstructorTypes[0] = typeof(object)
        actionConstructorTypes[1] = typeof(IntPtr)
        actionCtor := typeof(Action).GetConstructor(actionConstructorTypes)
        ctorIl.Emit(OpCodes.Newobj, actionCtor)
        ctorIl.Emit(OpCodes.Stfld, continuationField)
        ctorIl.Emit(OpCodes.Ret)

        ctorHandle: ConstructorInfo = ctor
        context := new ColumnarIteratorEmitContext(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            shape,
            sm,
            elementType,
            shape.FieldNames,
            fields,
            table,
            ctorHandle,
            null,
            null,
            null,
            null,
            null,
            null,
            coreHandle,
            bodyFacts,
            sm,
            null,
            null,
            fields,
            synthesizedTypes,
            fn.SourceFileId
        )
        overrideContext := ColumnarIteratorOverrideContext.ForAsync(table, elementType, asyncEnumerable, asyncEnumerator)
        publicImpl := MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot

        corePlan := ColumnarIteratorBodyPlanner.BuildAsyncMoveNextCorePlan(context)
        if context.Declined {
            return Declined(context.DeclineSite, context.DeclineMessage + " in '" + fn.Name + "'", fn.Name)
        }
        coreIl := core.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(corePlan, coreIl, modifiedMemberReferences)

        moveNextAsync := sm.DefineMethod(
            shape.MemberNames[2],
            publicImpl,
            typeof(System.Threading.Tasks.ValueTask<bool>),
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[2].Apply(overrideContext, sm, moveNextAsync)
        moveNextAsyncPlan := ColumnarIteratorBodyPlanner.BuildMoveNextAsyncPlan(context)
        moveNextAsyncIl := moveNextAsync.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(moveNextAsyncPlan, moveNextAsyncIl, modifiedMemberReferences)

        getCurrent := sm.DefineMethod(
            shape.MemberNames[3],
            publicImpl | MethodAttributes.SpecialName,
            elementType,
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[3].Apply(overrideContext, sm, getCurrent)
        getCurrentPlan := ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context)
        getCurrentIl := getCurrent.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(getCurrentPlan, getCurrentIl, modifiedMemberReferences)

        disposeAsync := sm.DefineMethod(
            shape.MemberNames[4],
            publicImpl,
            typeof(System.Threading.Tasks.ValueTask),
            System.Type.EmptyTypes
        )
        shape.MemberOverrideRows[4].Apply(overrideContext, sm, disposeAsync)
        disposeAsyncPlan := ColumnarIteratorBodyPlanner.BuildDisposeAsyncPlan(context)
        disposeAsyncIl := disposeAsync.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(disposeAsyncPlan, disposeAsyncIl, modifiedMemberReferences)

        cancellationParameters := new Type[](1)
        cancellationParameters[0] = typeof(System.Threading.CancellationToken)
        getAsyncEnumerator := sm.DefineMethod(
            shape.MemberNames[5],
            publicImpl,
            asyncEnumerator,
            cancellationParameters
        )
        shape.MemberOverrideRows[5].Apply(overrideContext, sm, getAsyncEnumerator)
        getAsyncEnumeratorPlan := ColumnarIteratorBodyPlanner.BuildGetAsyncEnumeratorPlan(context)
        getAsyncEnumeratorIl := getAsyncEnumerator.GetILGenerator()
        ColumnarCodePlanExecutor.Execute(getAsyncEnumeratorPlan, getAsyncEnumeratorIl, modifiedMemberReferences)

        factoryPlan := ColumnarIteratorBodyPlanner.BuildAsyncFactoryPlan(context)
        ColumnarCodePlanExecutor.Execute(factoryPlan, factoryIl, modifiedMemberReferences)
        synthesizedTypes.Add(sm)
        return Completed()
    }

    // The factory's instantiation of a static member generator's machine: the declaring type's own
    // builders in declared order, then the method's own. Both lists are what the factory's body sees
    // as its type parameters, so this is the machine closed over exactly those.
    static func StaticMachineArguments(structDef: ColumnarStructDef, builder: MethodBuilder): Type[] {
        arguments := new List<Type>()
        ownerParameters := structDef.GenericParameters
        if ownerParameters != null {
            for ownerName in structDef.GenericParameterNames {
                arguments.Add(ownerParameters[ownerName])
            }
        }
        if builder.IsGenericMethodDefinition {
            for methodParameter in builder.GetGenericArguments() {
                arguments.Add(methodParameter)
            }
        }
        return arguments.ToArray()
    }

    static func OwnerFirstNames(ownerNames: string[], ownNames: string[]): string[] {
        names := new string[](ownerNames.Length + ownNames.Length)
        i := 0
        while i < ownerNames.Length {
            names[i] = ownerNames[i]
            i = i + 1
        }
        i = 0
        while i < ownNames.Length {
            names[ownerNames.Length + i] = ownNames[i]
            i = i + 1
        }
        return names
    }

    // Constraint rows are aligned by parameter position, and either list may carry fewer rows than
    // parameters. Each side is therefore read per parameter, so a short owner list never lets the
    // method's rows slide onto the owner's parameters.
    static func OwnerFirstSpecials(ownerCount: int, ownerRows: int[], ownCount: int, ownRows: int[]): int[] {
        rows := new int[](ownerCount + ownCount)
        i := 0
        while i < ownerCount {
            rows[i] = ColumnarGenericConstraintPlanner.SpecialAt(ownerRows, i)
            i = i + 1
        }
        i = 0
        while i < ownCount {
            rows[ownerCount + i] = ColumnarGenericConstraintPlanner.SpecialAt(ownRows, i)
            i = i + 1
        }
        return rows
    }

    static func OwnerFirstTypeConstraints(ownerCount: int, ownerRows: string[][], ownCount: int, ownRows: string[][]): string[][] {
        rows := new string[][](ownerCount + ownCount)
        i := 0
        while i < ownerCount {
            rows[i] = ColumnarGenericConstraintPlanner.TypeConstraintsAt(ownerRows, i)
            i = i + 1
        }
        i = 0
        while i < ownCount {
            rows[ownerCount + i] = ColumnarGenericConstraintPlanner.TypeConstraintsAt(ownRows, i)
            i = i + 1
        }
        return rows
    }

    static func Completed(): ColumnarIteratorRealizationResult {
        return new ColumnarIteratorRealizationResult(true, "", "", "")
    }

    static func Declined(site: string, message: string, member: string): ColumnarIteratorRealizationResult {
        return new ColumnarIteratorRealizationResult(false, site, message, member)
    }

    static func SyncShape(fn: ColumnarFunctionInput, funcOrdinal: int, functionSource: string, precomputedShape: ColumnarIteratorShape?): ColumnarIteratorShape {
        if precomputedShape != null {
            return precomputedShape
        }
        return ColumnarIteratorPlanner.AnalyzeShape(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            fn.Name,
            funcOrdinal,
            fn.ReturnCanonical,
            fn.ParamNames,
            fn.ParamCanonicals,
            fn.TypeParamNames,
            false,
            "",
            null,
            null,
            null,
            null,
            false
        )
    }

    static func TryResolveIteratorCanonical(
        canonical: string,
        smTypeParamMap: Dictionary<string, Type>?,
        typeResolution: ColumnarSemanticTypeResolution,
        out resolvedType: Type
    ): bool {
        if smTypeParamMap != null {
            // A machine parameter wins before every general admission check. The method registry can
            // contain an MVAR with the same name, which cannot enter a TypeBuilder field signature.
            if smTypeParamMap.TryGetValue(canonical, out resolvedType) {
                return true
            }
            return ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
                canonical,
                smTypeParamMap,
                typeResolution.Enums,
                typeResolution.Structs,
                typeResolution.Unions,
                out resolvedType
            ) && (resolvedType.IsGenericParameter || (ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(resolvedType) && ((Type)resolvedType.GetElementType()).IsGenericParameter) || ColumnarTypeOfPlanner.IsSupportedType(resolvedType)) && !ContainsMethodVarReference(resolvedType, smTypeParamMap)
        }
        return ColumnarCanonicalTypeResolver.TryResolveType(
            canonical,
            typeResolution.Enums,
            typeResolution.Structs,
            typeResolution.Unions,
            out resolvedType
        ) && (ColumnarTypeOfPlanner.IsSupportedType(resolvedType) || IsOrdinaryDelegateFieldType(resolvedType))
    }

    // A COMPLETE EXTERNAL DELEGATE TYPE — `Func<int, int>`, `Predicate<string>`, a `delegate` a
    // referenced assembly declares. It is an ordinary reference and stores in an ordinary field, which
    // is all a hoisted local needs of it. The general storable-type catalog has not been widened to
    // say so, and widening it is a question about the whole value surface rather than about the one
    // field a generator hoists for a local the author wrote a delegate type on.
    static func IsOrdinaryDelegateFieldType(candidate: Type): bool {
        if candidate == null || candidate is TypeBuilder || candidate.IsGenericTypeDefinition || candidate.IsByRef || candidate.IsPointer || RuntimeTypeShapeFacts.ContainsBuilderBoundType(candidate) {
            return false
        }
        return typeof(Delegate).IsAssignableFrom(candidate)
    }

    // Only the machine's own generic parameters are legal in its field signatures. Preserve the
    // legacy recursive order and Dictionary.ContainsValue Type equality exactly.
    static func ContainsMethodVarReference(valueType: Type, smTypeParamMap: Dictionary<string, Type>): bool {
        if valueType.IsGenericParameter {
            return !smTypeParamMap.ContainsValue(valueType)
        }
        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(valueType) {
            return ContainsMethodVarReference(valueType.GetElementType(), smTypeParamMap)
        }
        if valueType.IsGenericType && !valueType.IsGenericTypeDefinition {
            arguments := valueType.GetGenericArguments()
            for argument in arguments {
                if ContainsMethodVarReference(argument, smTypeParamMap) {
                    return true
                }
            }
        }
        return false
    }
}
