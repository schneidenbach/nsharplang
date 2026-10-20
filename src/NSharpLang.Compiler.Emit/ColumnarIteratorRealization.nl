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
        if isStatic {
            staticOrdinal := ordinalCounter[0]
            ordinalCounter[0] = staticOrdinal + 1
            staticFactoryIl := builder.GetILGenerator()
            // A STATIC GENERATOR'S MACHINE IS NESTED IN ITS DECLARING TYPE, AS C# NESTS IT, and it is
            // generic over everything its body can name: the declaring type's parameters first, then
            // the method's own. The factory instantiates it on exactly those — `<Names>d__0<!0>` inside
            // `Box<T>.Names`, `<Echo>d__1<!0, !!0>` inside `Box<T>.Echo<U>` — so neither the machine
            // nor the factory ever reaches a type parameter it does not own.
            staticEnclosingParameters := System.Type.EmptyTypes
            if enclosingBuilder.IsGenericTypeDefinition {
                staticEnclosingParameters = enclosingBuilder.GetGenericArguments()
            }
            staticMethodParameters := System.Type.EmptyTypes
            if builder.IsGenericMethodDefinition {
                staticMethodParameters = builder.GetGenericArguments()
            }
            if staticMethodParameters.Length != method.TypeParamNames.Length {
                return Declined(
                    "emit.iterator.generic-arity",
                    "the declared method '" + memberLabel + "' has " + staticMethodParameters.Length.ToString() + " type parameter(s) but its generator body names " + method.TypeParamNames.Length.ToString(),
                    memberLabel
                )
            }
            if method.IsAsync {
                return EmitAsync(
                    module,
                    method,
                    staticOrdinal,
                    methodSource,
                    typeResolution,
                    staticFactoryIl,
                    synthesizedTypes,
                    bodyFacts,
                    staticMethodParameters,
                    null,
                    memberLabel,
                    null,
                    null,
                    null,
                    null,
                    structDef.Builder,
                    staticEnclosingParameters,
                    ""
                )
            }
            return EmitSync(
                module,
                method,
                staticOrdinal,
                methodSource,
                typeResolution,
                staticFactoryIl,
                synthesizedTypes,
                staticMethodParameters,
                null,
                memberLabel,
                null,
                null,
                null,
                null,
                bodyFacts,
                structDef.Builder,
                staticEnclosingParameters
            )
        }
        // Instance machines carry the declaring type's parameters followed by the method's own parameters,
        // just like static machines. The source row supplies receiver and field facts so both sync and async
        // builders can capture `this` and plan the body as an ordinary member.
        input := StructInputFor(program, structDef)
        if input == null {
            return Declined(
                "emit.iterator.instance-unsupported",
                "enclosing type facts are unavailable for '" + memberLabel + "'",
                memberLabel
            )
        }

        // EVERY INSTANCE FIELD THE BODY CAN NAME, exactly as an ordinary member body names them. The
        // machine is NESTED in the declaring type, so that type's own fields are reachable whatever
        // their visibility — a camelCase field and a `private` one alike. An inherited source field is
        // reachable unless the base that declares it made it `private`, which is the ordinary member
        // body's answer too. Walking nearest-first, the first declaration of a name is the one it means.
        fieldNames := new List<string>()
        fieldCanonicals := new List<string>()
        fieldHandles := new List<FieldInfo>()
        fieldOwner: ColumnarStructDef? = structDef
        fieldOwnerInput: ColumnarStructInput? = input
        while fieldOwner != null && fieldOwnerInput != null {
            ownerDefinition := (ColumnarStructDef)fieldOwner
            ownerInput := (ColumnarStructInput)fieldOwnerInput
            isDeclaringType := Object.ReferenceEquals(ownerDefinition, structDef)
            fieldIndex := 0
            while fieldIndex < ownerInput.FieldNames.Length {
                name := ownerInput.FieldNames[fieldIndex]
                fieldBuilder: FieldBuilder = null
                if name.Length > 0 && !fieldNames.Contains(name) && ownerDefinition.Fields.TryGetValue(name, out fieldBuilder) && (isDeclaringType || !fieldBuilder.IsPrivate) {
                    fieldNames.Add(name)
                    fieldCanonicals.Add(ownerInput.FieldTypeCanonicals[fieldIndex])
                    fieldHandle: FieldInfo = fieldBuilder
                    fieldHandles.Add(fieldHandle)
                }
                fieldIndex = fieldIndex + 1
            }
            fieldOwner = ownerDefinition.BaseDef
            fieldOwnerInput = fieldOwner == null ? null : StructInputFor(program, (ColumnarStructDef)fieldOwner)
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
            method.IsAsync
        )
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, memberLabel)
        }

        factoryIl := builder.GetILGenerator()
        enclosingTypeParameters := System.Type.EmptyTypes
        if enclosingBuilder.IsGenericTypeDefinition {
            enclosingTypeParameters = enclosingBuilder.GetGenericArguments()
        }
        methodTypeParameters := System.Type.EmptyTypes
        if builder.IsGenericMethodDefinition {
            methodTypeParameters = builder.GetGenericArguments()
        }
        if methodTypeParameters.Length != method.TypeParamNames.Length {
            return Declined(
                "emit.iterator.generic-arity",
                "the declared method '" + memberLabel + "' has " + methodTypeParameters.Length.ToString() + " type parameter(s) but its generator body names " + method.TypeParamNames.Length.ToString(),
                memberLabel
            )
        }
        realizedFieldNames := fieldNames.ToArray()
        realizedFieldHandles := fieldHandles.ToArray()
        realizedFieldCanonicals := fieldCanonicals.ToArray()
        if method.IsAsync {
            return EmitAsync(
                module,
                method,
                shapeOrdinal,
                methodSource,
                typeResolution,
                factoryIl,
                synthesizedTypes,
                bodyFacts,
                methodTypeParameters,
                shape,
                memberLabel,
                structDef.Builder,
                realizedFieldNames,
                realizedFieldHandles,
                realizedFieldCanonicals,
                structDef.Builder,
                enclosingTypeParameters,
                shapeInputName
            )
        }
        enclosingType: Type = structDef.Builder
        return EmitSync(
            module,
            method,
            0,
            methodSource,
            typeResolution,
            factoryIl,
            synthesizedTypes,
            methodTypeParameters,
            shape,
            memberLabel,
            enclosingType,
            realizedFieldNames,
            realizedFieldHandles,
            realizedFieldCanonicals,
            bodyFacts,
            structDef.Builder,
            enclosingTypeParameters
        )
    }

    // WHERE A MACHINE LIVES. A free function's machine is a top-level type. A MEMBER generator's
    // machine is nested in the type that declares the member, as C# nests it: its body is that
    // member's body, so it must reach everything the member can — a `private` method or field of the
    // declaring type included, which a top-level type is refused at run time with a
    // `MethodAccessException`/`FieldAccessException`. It is nested ASSEMBLY rather than private
    // because a lambda in the generator is lowered onto a display of its own, which is a top-level
    // type that holds the machine and calls into it.
    static func DefineMachineType(module: ModuleBuilder, declaringType: TypeBuilder?, name: string): TypeBuilder {
        if declaringType != null {
            return declaringType.DefineNestedType(name, TypeAttributes.NestedAssembly | TypeAttributes.Class | TypeAttributes.Sealed)
        }

        return module.DefineType(name, TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed)
    }

    // The source row a definition was built from: exact semantic identity or its metadata/simple tail.
    // Keep the first-match walk because observed input wrappers may be enumerable protocol objects.
    static func StructInputFor(program: ColumnarProgramInput, definition: ColumnarStructDef): ColumnarStructInput? {
        if program == null || definition == null {
            return null
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
                candidateArity := 0
                if candidate.TypeParamNames != null {
                    candidateArity = candidate.TypeParamNames.Length
                }
                candidateMetadataName := TypeArityNames.Key(candidate.Name, candidateArity)
                candidateMatches := program.ExactStructTypeName(candidate) == definition.DeclaredTypeName
                if !candidateMatches {
                    candidateMatches = candidateMetadataName == definition.DeclaredTypeName || definition.DeclaredTypeName.EndsWith("." + candidateMetadataName, StringComparison.Ordinal) || definition.DeclaredTypeName.EndsWith("+" + candidateMetadataName, StringComparison.Ordinal) || candidate.Name == definition.DeclaredTypeName || definition.DeclaredTypeName.EndsWith("." + candidate.Name, StringComparison.Ordinal) || definition.DeclaredTypeName.EndsWith("+" + candidate.Name, StringComparison.Ordinal)
                }
                if candidateMatches {
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
        return input
    }

    static func StructInputEnumerator(
        inputs: IEnumerable<ColumnarStructInput>
    ): IEnumerator<ColumnarStructInput> {
        return inputs.GetEnumerator()
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
        bodyFacts: ColumnarIteratorBodyFacts? = null,
        declaringType: TypeBuilder? = null,
        enclosingTypeParams: Type[]? = null
    ): ColumnarIteratorRealizationResult {
        modifiedMemberReferences := ModifiedMemberReferencesOf(bodyFacts)
        declineLabel := memberLabel.Length == 0 ? fn.Name : memberLabel
        shape := SyncShape(fn, funcOrdinal, functionSource, precomputedShape)
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, declineLabel)
        }

        enclosingParameters := enclosingTypeParams ?? System.Type.EmptyTypes
        if enclosingParameters.Length > 0 && declaringType == null {
            return Declined(
                "emit.iterator.generic-enclosing",
                "a machine generic over its declaring type's parameters must be nested in that type for '" + declineLabel + "'",
                declineLabel
            )
        }
        sm := DefineMachineType(module, declaringType, shape.TypeName)
        smTypeParamMap: Dictionary<string, Type>? = null
        smTypeParams := System.Type.EmptyTypes
        smSpecialConstraints := System.Array.Empty<int>()
        smBaseConstraints := System.Array.Empty<Type>()
        smInterfaceConstraints := System.Array.Empty<Type[]>()
        table := typeResolution.StructuralTypeReferences
        if enclosingParameters.Length > 0 || fn.TypeParamNames.Length > 0 {
            // THE MACHINE'S PARAMETER LIST IS THE DECLARING TYPE'S, THEN THE METHOD'S. A type parameter
            // is encoded in metadata by POSITION (`!0`), not by owner, so a machine that re-declares
            // `Box<T>`'s parameters at the same positions reads every signature written in `Box<T>`'s
            // own parameters — `Box<!0>::Name()`, a field of type `!0` — as its own, which is the whole
            // reason C# nests its machines this way. The body is therefore planned in the DECLARING
            // type's own parameter handles, the ones every member it can call is declared in, so an
            // argument, a return value and a hoisted field all agree on identity. A method parameter
            // cannot be named from a type's field (an MVAR there is unencodable), so each one is
            // replaced by the machine's own parameter at its position after the enclosing ones.
            enclosingCount := enclosingParameters.Length
            methodCount := fn.TypeParamNames.Length
            parameterNames := new string[](enclosingCount + methodCount)
            n := 0
            while n < enclosingCount {
                parameterNames[n] = enclosingParameters[n].Name
                n = n + 1
            }
            n = 0
            while n < methodCount {
                parameterNames[enclosingCount + n] = fn.TypeParamNames[n]
                n = n + 1
            }
            smGps := sm.DefineGenericParameters(parameterNames)
            smTypeParamMap = new Dictionary<string, Type>(StringComparer.Ordinal)
            smTypeParams = new Type[](smGps.Length)
            smSpecialConstraints = new int[](smGps.Length)
            smBaseConstraints = new Type[](smGps.Length)
            smInterfaceConstraints = new Type[][](smGps.Length)
            e := 0
            while e < enclosingCount {
                enclosingParameter := enclosingParameters[e]
                if !enclosingParameter.IsGenericParameter || enclosingParameter.GenericParameterPosition != e {
                    return Declined(
                        "emit.iterator.generic-enclosing",
                        "the declaring type's parameter '" + enclosingParameter.Name + "' is not at position " + e.ToString() + " for '" + declineLabel + "'",
                        declineLabel
                    )
                }
                smTypeParamMap[enclosingParameter.Name] = enclosingParameter
                smTypeParams[e] = enclosingParameter
                enclosingSpecial := 0
                enclosingBase: Type? = null
                enclosingInterfaces := System.Type.EmptyTypes
                if !TryCopyEnclosingConstraints(enclosingParameter, smGps[e], out enclosingSpecial, out enclosingBase, out enclosingInterfaces) {
                    return Declined(
                        "emit.iterator.generic-constraints",
                        "the constraints on the declaring type's parameter '" + enclosingParameter.Name + "' could not be preserved on the iterator machine for '" + declineLabel + "'",
                        declineLabel
                    )
                }
                smSpecialConstraints[e] = enclosingSpecial
                smBaseConstraints[e] = enclosingBase
                smInterfaceConstraints[e] = enclosingInterfaces
                e = e + 1
            }
            methodGps := new GenericTypeParameterBuilder[](methodCount)
            // The declaring type's parameters already have their structural owner; the machine owns
            // only the parameters it stands in for the method's.
            machineOwnedParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
            g := 0
            while g < methodCount {
                methodGps[g] = smGps[enclosingCount + g]
                parameter: Type = methodGps[g]
                smTypeParamMap[fn.TypeParamNames[g]] = parameter
                smTypeParams[enclosingCount + g] = parameter
                machineOwnedParameters[fn.TypeParamNames[g]] = parameter
                g = g + 1
            }
            // A dependent constraint such as `where U: T` resolves T through this exact structural
            // owner. Publish the machine's generic parameters before asking the shared constraint
            // planner to resolve those rows; the runtime type itself is still unbaked, as intended.
            table.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, machineOwnedParameters)
            methodSpecialConstraints := System.Array.Empty<int>()
            methodBaseConstraints := System.Array.Empty<Type>()
            methodInterfaceConstraints := System.Array.Empty<Type[]>()
            if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(methodGps, fn.TypeParamSpecialConstraints, fn.TypeParamTypeConstraints, smTypeParamMap, smTypeParams, typeResolution, out methodSpecialConstraints, out methodBaseConstraints, out methodInterfaceConstraints) {
                return Declined(
                    "emit.iterator.generic-constraints",
                    "iterator generic constraints could not be preserved for '" + declineLabel + "'",
                    declineLabel
                )
            }
            g = 0
            while g < methodCount {
                smSpecialConstraints[enclosingCount + g] = methodSpecialConstraints[g]
                smBaseConstraints[enclosingCount + g] = methodBaseConstraints[g]
                smInterfaceConstraints[enclosingCount + g] = methodInterfaceConstraints[g]
                g = g + 1
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
        ColumnarEmitReflectionFacts.EmitConstructor(ctorIl, OpCodes.Call, objectCtor, "System.Object parameterless constructor")
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
            // The factory runs in the declaring method, so it instantiates the machine on that method's
            // view of the same parameters: the declaring type's own, then the method's MVARs.
            factoryTypeArguments := new Type[](enclosingParameters.Length + methodTypeParams.Length)
            enclosingParameters.CopyTo(factoryTypeArguments, 0)
            methodTypeParams.CopyTo(factoryTypeArguments, enclosingParameters.Length)
            if factoryTypeArguments.Length != smTypeParams.Length {
                return Declined(
                    "emit.iterator.generic-arity",
                    "the factory for '" + declineLabel + "' supplies " + factoryTypeArguments.Length.ToString() + " type argument(s) for a machine with " + smTypeParams.Length.ToString(),
                    declineLabel
                )
            }
            factorySmType := smDefinition.MakeGenericType(factoryTypeArguments)
            factoryFields := new FieldInfo[](fields.Length)
            i = 0
            while i < fields.Length {
                if fieldBuilders[i] != null {
                    factoryFields[i] = TypeBuilder.GetField(factorySmType, fieldBuilders[i])
                }
                i = i + 1
            }
            factoryCtor := TypeBuilder.GetConstructor(factorySmType, ctor)
            factoryEnclosingType := enclosingType
            if enclosingType != null && declaringType != null {
                // The factory's receiver is the declaring generic type's self-instantiation. In
                // particular, a struct receiver must be copied from `&Owner<!0>` with an ldobj token
                // for that same constructed type, not the open `Owner` definition.
                factoryEnclosingType = ColumnarSourceSelfInstantiation.Of(declaringType)
            }
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
                factoryCtor,
                factoryEnclosingType
            )
        }
        factoryPlan := ColumnarIteratorBodyPlanner.BuildFactoryPlan(factoryContext)
        ColumnarCodePlanExecutor.Execute(factoryPlan, factoryIl, modifiedMemberReferences)
        synthesizedTypes.Add(sm)
        return Completed()
    }

    // Compile an ordinary `async func` as a CLR async state machine. The iterator body planner owns
    // resume dispatch, hoisting, expression spills, protected-region re-entry and await-pattern
    // binding; this realization supplies the task builder and the C#-shaped struct/kickoff surface.
    static func DefineAsyncMachineType(module: ModuleBuilder, declaringType: TypeBuilder?, name: string): TypeBuilder {
        if declaringType != null {
            return declaringType.DefineNestedType(
                name,
                TypeAttributes.NestedPrivate | TypeAttributes.Sealed | TypeAttributes.SequentialLayout,
                typeof(ValueType)
            )
        }
        return module.DefineType(name, TypeAttributes.NotPublic | TypeAttributes.Sealed | TypeAttributes.SequentialLayout, typeof(ValueType))
    }

    static func AsyncBuilderMethodOnType(builderType: Type, definitionMethod: MethodInfo): MethodInfo {
        try {
            return TypeBuilder.GetMethod(builderType, definitionMethod)
        } catch ex: Exception {
            throw new InvalidOperationException("kickoff async builder member rebinding failed: " + ex.Message)
        }
    }

    static func DefineAsyncBuilderMethodBridges(
        module: ModuleBuilder,
        builderDefinition: Type,
        machineName: string,
        synthesizedTypes: List<TypeBuilder>
    ): ColumnarAsyncBuilderMethodBridges {
        bridgeType := module.DefineType(
            machineName + "$BuilderBridge",
            TypeAttributes.NotPublic | TypeAttributes.Abstract | TypeAttributes.Sealed | TypeAttributes.Class,
            typeof(object)
        )
        bridgeAttributes := MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig
        exceptionType := typeof(Exception)
        stateMachineInterface := typeof(System.Runtime.CompilerServices.IAsyncStateMachine)
        notifyInterface := typeof(System.Runtime.CompilerServices.INotifyCompletion)
        criticalNotifyInterface := typeof(System.Runtime.CompilerServices.ICriticalNotifyCompletion)
        builderResultDefinition := builderDefinition

        awaitOn := bridgeType.DefineMethod("AwaitOnCompleted", bridgeAttributes)
        awaitOnParameters := awaitOn.DefineGenericParameters(["TResult", "TAwaiter", "TStateMachine"])
        awaitOnParameters[1].SetInterfaceConstraints([notifyInterface])
        awaitOnParameters[2].SetInterfaceConstraints([stateMachineInterface])
        awaitOnBuilder := builderResultDefinition.MakeGenericType([awaitOnParameters[0]])
        awaitOn.SetReturnType(typeof(void))
        awaitOnParameterTypes := new Type[](3)
        awaitOnParameterTypes[0] = awaitOnBuilder.MakeByRefType()
        awaitOnParameterTypes[1] = awaitOnParameters[1].MakeByRefType()
        awaitOnParameterTypes[2] = awaitOnParameters[2].MakeByRefType()
        awaitOn.SetParameters(awaitOnParameterTypes)
        awaitOnMethod := FindAsyncBuilderMethod(builderResultDefinition, "AwaitOnCompleted", 2, 2)
        awaitOnMethod = TypeBuilder.GetMethod(awaitOnBuilder, awaitOnMethod).MakeGenericMethod([awaitOnParameters[1], awaitOnParameters[2]])
        awaitOnIl := awaitOn.GetILGenerator()
        awaitOnIl.Emit(OpCodes.Ldarg_0)
        awaitOnIl.Emit(OpCodes.Ldarg_1)
        awaitOnIl.Emit(OpCodes.Ldarg_2)
        awaitOnIl.Emit(OpCodes.Call, awaitOnMethod)
        awaitOnIl.Emit(OpCodes.Ret)

        awaitUnsafe := bridgeType.DefineMethod("AwaitUnsafeOnCompleted", bridgeAttributes)
        awaitUnsafeParameters := awaitUnsafe.DefineGenericParameters(["TResult", "TAwaiter", "TStateMachine"])
        awaitUnsafeParameters[1].SetInterfaceConstraints([criticalNotifyInterface])
        awaitUnsafeParameters[2].SetInterfaceConstraints([stateMachineInterface])
        awaitUnsafeBuilder := builderResultDefinition.MakeGenericType([awaitUnsafeParameters[0]])
        awaitUnsafe.SetReturnType(typeof(void))
        awaitUnsafeParameterTypes := new Type[](3)
        awaitUnsafeParameterTypes[0] = awaitUnsafeBuilder.MakeByRefType()
        awaitUnsafeParameterTypes[1] = awaitUnsafeParameters[1].MakeByRefType()
        awaitUnsafeParameterTypes[2] = awaitUnsafeParameters[2].MakeByRefType()
        awaitUnsafe.SetParameters(awaitUnsafeParameterTypes)
        awaitUnsafeMethod := FindAsyncBuilderMethod(builderResultDefinition, "AwaitUnsafeOnCompleted", 2, 2)
        awaitUnsafeMethod = TypeBuilder.GetMethod(awaitUnsafeBuilder, awaitUnsafeMethod).MakeGenericMethod([awaitUnsafeParameters[1], awaitUnsafeParameters[2]])
        awaitUnsafeIl := awaitUnsafe.GetILGenerator()
        awaitUnsafeIl.Emit(OpCodes.Ldarg_0)
        awaitUnsafeIl.Emit(OpCodes.Ldarg_1)
        awaitUnsafeIl.Emit(OpCodes.Ldarg_2)
        awaitUnsafeIl.Emit(OpCodes.Call, awaitUnsafeMethod)
        awaitUnsafeIl.Emit(OpCodes.Ret)

        setException := bridgeType.DefineMethod("SetException", bridgeAttributes)
        exceptionParameters := setException.DefineGenericParameters(["TResult"])
        exceptionBuilder := builderResultDefinition.MakeGenericType([exceptionParameters[0]])
        setException.SetReturnType(typeof(void))
        exceptionParameterTypes := new Type[](2)
        exceptionParameterTypes[0] = exceptionBuilder.MakeByRefType()
        exceptionParameterTypes[1] = exceptionType
        setException.SetParameters(exceptionParameterTypes)
        exceptionMethodDefinition := builderResultDefinition.GetMethod("SetException", [exceptionType])
        if exceptionMethodDefinition == null {
            throw new InvalidOperationException("the generic async builder has no SetException(Exception) method")
        }
        exceptionMethod := TypeBuilder.GetMethod(exceptionBuilder, exceptionMethodDefinition)
        setExceptionIl := setException.GetILGenerator()
        setExceptionIl.Emit(OpCodes.Ldarg_0)
        setExceptionIl.Emit(OpCodes.Ldarg_1)
        setExceptionIl.Emit(OpCodes.Call, exceptionMethod)
        setExceptionIl.Emit(OpCodes.Ret)

        setResult := bridgeType.DefineMethod("SetResult", bridgeAttributes)
        resultParameters := setResult.DefineGenericParameters(["TResult"])
        resultBuilder := builderResultDefinition.MakeGenericType([resultParameters[0]])
        setResult.SetReturnType(typeof(void))
        resultParameterTypes := new Type[](2)
        resultParameterTypes[0] = resultBuilder.MakeByRefType()
        resultParameterTypes[1] = resultParameters[0]
        setResult.SetParameters(resultParameterTypes)
        resultMethodDefinition := FindAsyncBuilderResultMethod(builderResultDefinition)
        resultMethod := TypeBuilder.GetMethod(resultBuilder, resultMethodDefinition)
        setResultIl := setResult.GetILGenerator()
        setResultIl.Emit(OpCodes.Ldarg_0)
        setResultIl.Emit(OpCodes.Ldarg_1)
        setResultIl.Emit(OpCodes.Call, resultMethod)
        setResultIl.Emit(OpCodes.Ret)

        setStateMachine := bridgeType.DefineMethod("SetStateMachine", bridgeAttributes)
        stateMachineParameters := setStateMachine.DefineGenericParameters(["TResult"])
        stateMachineBuilder := builderResultDefinition.MakeGenericType([stateMachineParameters[0]])
        setStateMachine.SetReturnType(typeof(void))
        stateMachineParameterTypes := new Type[](2)
        stateMachineParameterTypes[0] = stateMachineBuilder.MakeByRefType()
        stateMachineParameterTypes[1] = stateMachineInterface
        setStateMachine.SetParameters(stateMachineParameterTypes)
        stateMachineMethodDefinition := builderResultDefinition.GetMethod("SetStateMachine", [stateMachineInterface])
        if stateMachineMethodDefinition == null {
            throw new InvalidOperationException("the generic async builder has no SetStateMachine(IAsyncStateMachine) method")
        }
        stateMachineMethod := TypeBuilder.GetMethod(stateMachineBuilder, stateMachineMethodDefinition)
        setStateMachineIl := setStateMachine.GetILGenerator()
        setStateMachineIl.Emit(OpCodes.Ldarg_0)
        setStateMachineIl.Emit(OpCodes.Ldarg_1)
        setStateMachineIl.Emit(OpCodes.Call, stateMachineMethod)
        setStateMachineIl.Emit(OpCodes.Ret)

        synthesizedTypes.Add(bridgeType)
        return new ColumnarAsyncBuilderMethodBridges(awaitOn, awaitUnsafe, setException, setResult, setStateMachine)
    }

    static func FindAsyncBuilderMethod(builderDefinition: Type, name: string, genericArity: int, parameterCount: int): MethodInfo {
        for candidate in builderDefinition.GetMethods(BindingFlags.Instance | BindingFlags.Public) {
            if candidate.Name == name && candidate.IsGenericMethodDefinition && candidate.GetGenericArguments().Length == genericArity && candidate.GetParameters().Length == parameterCount {
                return candidate
            }
        }
        throw new InvalidOperationException("the async builder has no " + name + " method with the expected generic signature")
    }

    static func FindAsyncBuilderResultMethod(builderDefinition: Type): MethodInfo {
        for candidate in builderDefinition.GetMethods(BindingFlags.Instance | BindingFlags.Public) {
            parameters := candidate.GetParameters()
            if candidate.Name == "SetResult" && parameters.Length == 1 && parameters[0].ParameterType.IsGenericParameter && parameters[0].ParameterType.GenericParameterPosition == 0 {
                return candidate
            }
        }
        throw new InvalidOperationException("the generic async builder has no SetResult(TResult) method")
    }

    static func EmitTaskMember(
        module: ModuleBuilder,
        structDef: ColumnarStructDef,
        method: ColumnarFunctionInput,
        funcOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        kickoff: MethodBuilder,
        synthesizedTypes: List<TypeBuilder>,
        bodyFacts: ColumnarIteratorBodyFacts?,
        resultType: Type,
        program: ColumnarProgramInput,
        isStatic: bool,
        usesTaskBuilder: bool,
        defaultUsesTaskBuilder: bool
    ): ColumnarIteratorRealizationResult {
        input := StructInputFor(program, structDef)
        if input == null {
            return Declined("emit.async.instance-unsupported", "enclosing type facts are unavailable for async method '" + structDef.DeclaredTypeName + "." + method.Name + "'", method.Name)
        }
        fieldNames := new List<string>()
        fieldCanonicals := new List<string>()
        fieldHandles := new List<FieldInfo>()
        fieldOwner: ColumnarStructDef? = structDef
        fieldOwnerInput: ColumnarStructInput? = input
        while fieldOwner != null && fieldOwnerInput != null {
            ownerDefinition := (ColumnarStructDef)fieldOwner
            ownerInput := (ColumnarStructInput)fieldOwnerInput
            isDeclaringType := Object.ReferenceEquals(ownerDefinition, structDef)
            fieldIndex := 0
            while fieldIndex < ownerInput.FieldNames.Length {
                name := ownerInput.FieldNames[fieldIndex]
                fieldBuilder: FieldBuilder = null
                if name.Length > 0 && !fieldNames.Contains(name) && ownerDefinition.Fields.TryGetValue(name, out fieldBuilder) && (isDeclaringType || !fieldBuilder.IsPrivate) {
                    fieldNames.Add(name)
                    fieldCanonicals.Add(ownerInput.FieldTypeCanonicals[fieldIndex])
                    fieldHandle: FieldInfo = fieldBuilder
                    fieldHandles.Add(fieldHandle)
                }
                fieldIndex += 1
            }
            fieldOwner = ownerDefinition.BaseDef
            fieldOwnerInput = fieldOwner == null ? null : StructInputFor(program, (ColumnarStructDef)fieldOwner)
        }
        return EmitTask(
            module,
            method,
            funcOrdinal,
            functionSource,
            typeResolution,
            kickoff,
            synthesizedTypes,
            bodyFacts,
            resultType,
            !isStatic,
            input.Name,
            structDef.Builder,
            fieldNames.ToArray(),
            fieldHandles.ToArray(),
            fieldCanonicals.ToArray(),
            !structDef.IsReference,
            usesTaskBuilder,
            defaultUsesTaskBuilder,
            null,
            null,
            null
        )
    }

    static func EmitTask(
        module: ModuleBuilder,
        fn: ColumnarFunctionInput,
        funcOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        kickoff: MethodBuilder,
        synthesizedTypes: List<TypeBuilder>,
        bodyFacts: ColumnarIteratorBodyFacts?,
        resultType: Type,
        isInstance: bool = false,
        receiverCanonical: string = "",
        enclosingType: TypeBuilder? = null,
        enclosingFieldNames: string[]? = null,
        enclosingFields: FieldInfo[]? = null,
        enclosingFieldCanonicals: string[]? = null,
        receiverIsValueType: bool = false,
        usesTaskBuilder: bool = false,
        defaultUsesTaskBuilder: bool = false,
        receiverTypeOverride: Type? = null,
        asyncClosureBoxNames: string[]? = null,
        asyncClosureBoxSourceFields: FieldBuilder[]? = null
    ): ColumnarIteratorRealizationResult {
        kickoffMethodTypeParameters := System.Type.EmptyTypes
        if kickoff.IsGenericMethodDefinition {
            kickoffMethodTypeParameters = kickoff.GetGenericArguments()
        }
        if kickoffMethodTypeParameters.Length != fn.TypeParamNames.Length {
            return Declined("emit.async.generic-arity", "async function '" + fn.Name + "' has " + fn.TypeParamNames.Length.ToString() + " declared type parameter(s), but its kickoff method has " + kickoffMethodTypeParameters.Length.ToString(), fn.Name)
        }
        shapeEnclosingFieldNames := enclosingFieldNames ?? new string[](0)
        shapeEnclosingFieldCanonicals := enclosingFieldCanonicals ?? new string[](0)
        if asyncClosureBoxNames != null && asyncClosureBoxSourceFields != null && asyncClosureBoxNames.Length > 0 {
            extraCount := asyncClosureBoxNames.Length
            combinedNames := new string[](shapeEnclosingFieldNames.Length + extraCount)
            combinedCanonicals := new string[](shapeEnclosingFieldCanonicals.Length + extraCount)
            copyIndex := 0
            while copyIndex < shapeEnclosingFieldNames.Length {
                combinedNames[copyIndex] = shapeEnclosingFieldNames[copyIndex]
                combinedCanonicals[copyIndex] = shapeEnclosingFieldCanonicals[copyIndex]
                copyIndex += 1
            }
            boxIndex := 0
            while boxIndex < extraCount {
                valueType := asyncClosureBoxSourceFields[boxIndex].FieldType.GetGenericArguments()[0]
                valueCanonical := ""
                if !ColumnarIteratorPlanner.TryBuildRuntimeTypeCanonical(typeResolution, valueType, out valueCanonical) {
                    return Declined("emit.async.closure-box-value-type", "captured mutable local '" + asyncClosureBoxNames[boxIndex] + "' cannot be represented in async function '" + fn.Name + "'", fn.Name)
                }
                combinedNames[copyIndex] = asyncClosureBoxNames[boxIndex]
                combinedCanonicals[copyIndex] = valueCanonical
                copyIndex += 1
                boxIndex += 1
            }
            shapeEnclosingFieldNames = combinedNames
            shapeEnclosingFieldCanonicals = combinedCanonicals
        }
        shape := ColumnarIteratorPlanner.AnalyzeAsyncMethodShape(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            fn.Name,
            funcOrdinal,
            fn.ReturnCanonical,
            fn.ParamNames,
            fn.ParamCanonicals,
            fn.TypeParamNames,
            isInstance,
            receiverCanonical,
            shapeEnclosingFieldNames,
            shapeEnclosingFieldCanonicals
        )
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, fn.Name)
        }
        if asyncClosureBoxNames != null && asyncClosureBoxSourceFields != null {
            if asyncClosureBoxNames.Length != asyncClosureBoxSourceFields.Length {
                return Declined("emit.async.closure-box-shape", "captured mutable locals on async function '" + fn.Name + "' have inconsistent state-machine facts", fn.Name)
            }
            closureBoxCanonicals := new string[](asyncClosureBoxNames.Length)
            boxIndex := 0
            while boxIndex < asyncClosureBoxNames.Length {
                boxCanonical := ""
                if !ColumnarIteratorPlanner.TryBuildRuntimeTypeCanonical(typeResolution, asyncClosureBoxSourceFields[boxIndex].FieldType, out boxCanonical) {
                    return Declined("emit.async.closure-box-type", "captured mutable local '" + asyncClosureBoxNames[boxIndex] + "' cannot be represented in async function '" + fn.Name + "'", fn.Name)
                }
                closureBoxCanonicals[boxIndex] = boxCanonical
                boxIndex += 1
            }
            ColumnarIteratorPlanner.AppendAsyncClosureBoxFields(shape, asyncClosureBoxNames, closureBoxCanonicals)
        }

        isTaskFamily := usesTaskBuilder
        builderDefinition: Type = null
        if isTaskFamily {
            builderDefinition = typeof(System.Runtime.CompilerServices.AsyncTaskMethodBuilder)
            if resultType != ColumnarTypeOfPlanner.RequiredVoidType() {
                builderDefinition = typeof(System.Runtime.CompilerServices.AsyncTaskMethodBuilder<int>).GetGenericTypeDefinition()
            }
        } else {
            builderDefinition = typeof(System.Runtime.CompilerServices.AsyncValueTaskMethodBuilder)
            if resultType != ColumnarTypeOfPlanner.RequiredVoidType() {
                builderDefinition = typeof(System.Runtime.CompilerServices.AsyncValueTaskMethodBuilder<int>).GetGenericTypeDefinition()
            }
        }
        machineTypeParameterMap := new Dictionary<string, Type>(StringComparer.Ordinal)
        machineTypeParameters := System.Type.EmptyTypes
        machineSpecialConstraints := System.Array.Empty<int>()
        machineBaseConstraints := System.Array.Empty<Type>()
        machineInterfaceConstraints := System.Array.Empty<Type[]>()
        sm := DefineAsyncMachineType(module, enclosingType, shape.TypeName)
        if fn.TypeParamNames.Length > 0 {
            machineGps := sm.DefineGenericParameters(fn.TypeParamNames)
            machineTypeParameters = new Type[](machineGps.Length)
            machineOwnedParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
            gp := 0
            while gp < machineGps.Length {
                machineTypeParameters[gp] = machineGps[gp]
                machineTypeParameterMap[fn.TypeParamNames[gp]] = machineGps[gp]
                machineOwnedParameters[fn.TypeParamNames[gp]] = machineGps[gp]
                gp += 1
            }
            typeResolution.StructuralTypeReferences.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, machineOwnedParameters)
            if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(
                machineGps,
                fn.TypeParamSpecialConstraints,
                fn.TypeParamTypeConstraints,
                machineTypeParameterMap,
                machineTypeParameters,
                typeResolution,
                out machineSpecialConstraints,
                out machineBaseConstraints,
                out machineInterfaceConstraints
            ) {
                return Declined("emit.async.generic-constraints", "generic constraints on async function '" + fn.Name + "' could not be preserved on its state machine", fn.Name)
            }
        } else {
            typeResolution.StructuralTypeReferences.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, null)
        }
        machineType: Type = sm
        kickoffMachineType: Type = sm
        machineResultType := resultType
        if machineTypeParameters.Length > 0 {
            machineType = sm.MakeGenericType(machineTypeParameters)
            kickoffMachineType = sm.MakeGenericType(kickoffMethodTypeParameters)
            if resultType != ColumnarTypeOfPlanner.RequiredVoidType() && !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(kickoffMethodTypeParameters, machineTypeParameters, resultType, out machineResultType) {
                return Declined("emit.async.generic-result", "the generic result type of async function '" + fn.Name + "' could not be rebound to its state machine", fn.Name)
            }
        }
        builderType: Type = builderDefinition
        kickoffBuilderType: Type = builderDefinition
        if resultType != ColumnarTypeOfPlanner.RequiredVoidType() {
            builderType = builderDefinition.MakeGenericType([machineResultType])
            kickoffBuilderType = builderDefinition.MakeGenericType([resultType])
        }
        sm.AddInterfaceImplementation(typeof(System.Runtime.CompilerServices.IAsyncStateMachine))
        compilerGeneratedCtor := typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute).GetConstructor(System.Type.EmptyTypes)
        if compilerGeneratedCtor == null {
            throw new InvalidOperationException("CompilerGeneratedAttribute's parameterless constructor was not found.")
        }
        sm.SetCustomAttribute(compilerGeneratedCtor, ColumnarAttributeBlobs.NoArgument())
        fields := new FieldInfo[](shape.FieldCount)
        definitionFields := new FieldInfo[](shape.FieldCount)
        kickoffFields := new FieldInfo[](shape.FieldCount)
        i := 0
        while i < shape.FieldCount {
            role := shape.FieldRoles[i]
            fieldType: Type = null
            if role == ColumnarIteratorPlanner.StateFieldRole() {
                fieldType = typeof(int)
            } else if role == ColumnarIteratorPlanner.CapturedParameterFieldRole() && shape.FieldNames[i] == "<>__this" && receiverTypeOverride != null {
                fieldType = receiverTypeOverride
            } else if role == ColumnarIteratorPlanner.AsyncResultFieldRole() {
                fieldType = resultType == ColumnarTypeOfPlanner.RequiredVoidType() ? typeof(bool) : machineResultType
            } else if role == ColumnarIteratorPlanner.AsyncBuilderFieldRole() {
                fieldType = builderType
            } else if role == ColumnarIteratorPlanner.AsyncClosureBoxFieldRole() {
                if !TryResolveIteratorCanonical(shape.FieldCanonicals[i], machineTypeParameterMap, typeResolution, out fieldType) || !ColumnarTypeOfPlanner.IsSupportedType(fieldType) {
                    return Declined("emit.async.closure-box-type", "a captured mutable local on async function '" + fn.Name + "' cannot be represented in its state machine", fn.Name)
                }
            } else if role == ColumnarIteratorPlanner.AwaiterFieldRole() || ColumnarIteratorPlanner.IsUnresolvedCanonical(shape.FieldCanonicals[i]) {
                i += 1
                continue
            } else {
                if !TryResolveIteratorCanonical(shape.FieldCanonicals[i], machineTypeParameterMap, typeResolution, out fieldType) || !ColumnarTypeOfPlanner.IsSupportedType(fieldType) {
                    return Declined("emit.async.field-type", "async hoisted field type '" + shape.FieldCanonicals[i] + "' could not be resolved for '" + fn.Name + "'", fn.Name)
                }
                if role == ColumnarIteratorPlanner.LoopCaptureBoxFieldRole() {
                    fieldType = ColumnarIteratorPlanner.LoopCaptureBoxType(fieldType)
                }
            }
            fieldBuilder := sm.DefineField(shape.FieldNames[i], fieldType, FieldAttributes.Public)
            definitionField: FieldInfo = fieldBuilder
            definitionFields[i] = definitionField
            if machineTypeParameters.Length > 0 {
                fields[i] = TypeBuilder.GetField(machineType, definitionField)
            } else {
                fields[i] = definitionField
            }
            if kickoffMethodTypeParameters.Length > 0 {
                kickoffFields[i] = TypeBuilder.GetField(kickoffMachineType, definitionField)
            } else {
                kickoffFields[i] = definitionField
            }
            i += 1
        }

        builderField := kickoffFields[shape.FieldNames.Length - 1]
        stateField := kickoffFields[0]
        builderCreate: MethodInfo? = null
        taskProperty: PropertyInfo? = null
        taskGetter: MethodInfo? = null
        setStateMachineBuilder: MethodInfo? = null
        builderTypeUsesTypeBuilderParameter := resultType != ColumnarTypeOfPlanner.RequiredVoidType() && RuntimeTypeShapeFacts.ContainsBuilderBoundType(resultType)
        builderBridges: ColumnarAsyncBuilderMethodBridges? = null
        if resultType != ColumnarTypeOfPlanner.RequiredVoidType() && RuntimeTypeShapeFacts.ContainsBuilderBoundType(machineResultType) {
            builderBridges = DefineAsyncBuilderMethodBridges(module, builderDefinition, shape.TypeName, synthesizedTypes)
        }
        if builderTypeUsesTypeBuilderParameter {
            builderCreateDefinition := builderDefinition.GetMethod("Create", BindingFlags.Public | BindingFlags.Static, null, System.Type.EmptyTypes, null)
            if builderCreateDefinition != null {
                builderCreate = AsyncBuilderMethodOnType(kickoffBuilderType, builderCreateDefinition)
            }
            taskProperty = builderDefinition.GetProperty("Task")
            if taskProperty != null && taskProperty.GetMethod != null {
                taskGetter = AsyncBuilderMethodOnType(kickoffBuilderType, taskProperty.GetMethod)
            }
        } else {
            builderCreate = kickoffBuilderType.GetMethod("Create", BindingFlags.Public | BindingFlags.Static, null, System.Type.EmptyTypes, null)
            taskProperty = kickoffBuilderType.GetProperty("Task")
            if taskProperty != null {
                taskGetter = taskProperty.GetMethod
            }
        }
        if builderBridges != null {
            setStateMachineBuilder = builderBridges.SetStateMachine.MakeGenericMethod([machineResultType])
        } else {
            setStateMachineBuilder = builderType.GetMethod("SetStateMachine", [typeof(System.Runtime.CompilerServices.IAsyncStateMachine)])
        }
        if builderCreate == null || taskGetter == null || setStateMachineBuilder == null {
            return Declined("emit.async.builder-surface", "the async task builder for '" + fn.Name + "' is missing Create, Task, or SetStateMachine", fn.Name)
        }

        moveNext := sm.DefineMethod(
            "MoveNext",
            MethodAttributes.Private | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot,
            typeof(void),
            System.Type.EmptyTypes
        )
        setStateMachine := sm.DefineMethod(
            "SetStateMachine",
            MethodAttributes.Private | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot,
            typeof(void),
            [typeof(System.Runtime.CompilerServices.IAsyncStateMachine)]
        )
        interfaceType := typeof(System.Runtime.CompilerServices.IAsyncStateMachine)
        interfaceMoveNext := interfaceType.GetMethod("MoveNext")
        interfaceSetStateMachine := interfaceType.GetMethod("SetStateMachine")
        if interfaceMoveNext == null || interfaceSetStateMachine == null {
            throw new InvalidOperationException("IAsyncStateMachine's required methods were not found.")
        }
        sm.DefineMethodOverride(moveNext, interfaceMoveNext)
        sm.DefineMethodOverride(setStateMachine, interfaceSetStateMachine)

        context := new ColumnarIteratorEmitContext(
            fn.BodyNodes,
            functionSource,
            fn.BodyRoot,
            shape,
            machineType,
            machineResultType,
            shape.FieldNames,
            fields,
            typeResolution.StructuralTypeReferences,
            null,
            enclosingType,
            enclosingFieldNames,
            enclosingFields,
            enclosingFieldCanonicals,
            null,
            bodyFacts,
            sm,
            machineTypeParameters.Length == 0 ? null : machineType,
            machineTypeParameterMap,
            definitionFields,
            synthesizedTypes,
            fn.SourceFileId,
            machineSpecialConstraints,
            machineBaseConstraints,
            machineInterfaceConstraints,
            machineTypeParameters,
            machineResultType,
            true,
            builderBridges
        )

        // Async local functions are instance kickoffs on the parent state machine. Their own bodies
        // get independent task machines and read captured parent fields through the captured receiver.
        if fn.LocalFunctions != null {
            if machineTypeParameters.Length > 0 {
                for localFunction in fn.LocalFunctions {
                    if localFunction.Function.IsAsync {
                        return Declined(
                            "emit.async.local-function.generic-owner",
                            "async local function '" + localFunction.Function.Name + "' inside generic async function '" + fn.Name + "' is not yet supported",
                            fn.Name + "." + localFunction.Function.Name
                        )
                    }
                }
            }
            localFunctionOrdinal := 0
            for localFunction in fn.LocalFunctions {
                localFn := localFunction.Function
                if !localFn.IsAsync {
                    localFunctionOrdinal += 1
                    continue
                }
                if localFn.TypeParamNames.Length > 0 {
                    return Declined(
                        "emit.async.local-function.generic",
                        "generic async local function '" + localFn.Name + "' cannot yet be emitted as a state machine",
                        fn.Name + "." + localFn.Name
                    )
                }
                localInner: Type? = null
                localWrapped: Type? = null
                if !TryResolveAsyncLocalReturnShape(
                    localFn.ReturnCanonical,
                    machineTypeParameterMap,
                    typeResolution,
                    defaultUsesTaskBuilder,
                    out localInner,
                    out localWrapped
                ) || localInner == null || localWrapped == null {
                    return Declined("emit.async.local-function.return", "async local function '" + localFn.Name + "' has an unsupported result type '" + localFn.ReturnCanonical + "'", fn.Name + "." + localFn.Name)
                }
                localParameterTypes := new Type[](localFn.ParamNames.Length)
                parameterIndex := 0
                while parameterIndex < localParameterTypes.Length {
                    localParameterType: Type = null
                    if !TryResolveIteratorCanonical(localFn.ParamCanonicals[parameterIndex], machineTypeParameterMap, typeResolution, out localParameterType) || !ColumnarTypeOfPlanner.IsSupportedType(localParameterType) {
                        return Declined("emit.async.local-function.parameter", "parameter '" + localFn.ParamNames[parameterIndex] + "' of async local function '" + localFn.Name + "' has unsupported type '" + localFn.ParamCanonicals[parameterIndex] + "'", fn.Name + "." + localFn.Name)
                    }
                    localParameterTypes[parameterIndex] = localParameterType
                    parameterIndex += 1
                }
                localMethodName := "<>__asyncLocal" + localFunctionOrdinal.ToString()
                localMethod := sm.DefineMethod(
                    localMethodName,
                    MethodAttributes.Assembly | MethodAttributes.HideBySig,
                    localWrapped,
                    localParameterTypes
                )
                ColumnarLambdaPlacementPlanner.DefineSourceParameterNames(localMethod, localFn.ParamNames)
                if bodyFacts != null {
                    bodyFacts.AddLocalAsyncCallable(
                        localFn.Name,
                        localMethod,
                        localParameterTypes,
                        localFn.ParamNames,
                        localFn.ParamModifierKinds,
                        localWrapped,
                        localFn.ParamDefaultKinds,
                        localFn.ParamDefaultTexts
                    )
                }
                parentCaptureNames := new List<string>()
                parentCaptureCanonicals := new List<string>()
                parentCaptureFields := new List<FieldInfo>()
                parentFieldIndex := 0
                while parentFieldIndex < shape.FieldCount {
                    if definitionFields[parentFieldIndex] != null && !ColumnarIteratorPlanner.IsUnresolvedCanonical(shape.FieldCanonicals[parentFieldIndex]) && shape.FieldRoles[parentFieldIndex] != ColumnarIteratorPlanner.StateFieldRole() && shape.FieldRoles[parentFieldIndex] != ColumnarIteratorPlanner.AsyncBuilderFieldRole() && shape.FieldRoles[parentFieldIndex] != ColumnarIteratorPlanner.AsyncResultFieldRole() && shape.FieldRoles[parentFieldIndex] != ColumnarIteratorPlanner.AwaiterFieldRole() {
                        parentCaptureNames.Add(shape.FieldNames[parentFieldIndex])
                        parentCaptureCanonicals.Add(shape.FieldCanonicals[parentFieldIndex])
                        parentCaptureFields.Add(fields[parentFieldIndex])
                    }
                    parentFieldIndex += 1
                }
                childOrdinal := funcOrdinal * 1000 + localFunctionOrdinal + 1
                childResult := EmitTask(
                    module,
                    localFn,
                    childOrdinal,
                    functionSource,
                    typeResolution,
                    localMethod,
                    synthesizedTypes,
                    bodyFacts,
                    localInner,
                    true,
                    shape.TypeName,
                    sm,
                    parentCaptureNames.ToArray(),
                    parentCaptureFields.ToArray(),
                    parentCaptureCanonicals.ToArray(),
                    true,
                    localWrapped == typeof(System.Threading.Tasks.Task) || (localWrapped.IsGenericType && localWrapped.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition()),
                    defaultUsesTaskBuilder,
                    sm,
                    null,
                    null
                )
                if !childResult.Succeeded {
                    return childResult
                }
                localFunctionOrdinal += 1
            }
        }
        moveNextPlan := ColumnarIteratorBodyPlanner.BuildAsyncMoveNextCorePlan(context)
        if context.Declined {
            return Declined(context.DeclineSite, context.DeclineMessage + " in '" + fn.Name + "'", fn.Name)
        }
        i = 0
        while i < shape.FieldCount {
            if definitionFields[i] != null {
                kickoffFields[i] = kickoffMethodTypeParameters.Length == 0 ? definitionFields[i] : TypeBuilder.GetField(kickoffMachineType, definitionFields[i])
            }
            i += 1
        }
        ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNext.GetILGenerator(), ModifiedMemberReferencesOf(bodyFacts))

        setStateMachineIl := setStateMachine.GetILGenerator()
        setStateMachineIl.Emit(OpCodes.Ldarg_0)
        setStateMachineIl.Emit(OpCodes.Ldflda, fields[shape.FieldNames.Length - 1])
        setStateMachineIl.Emit(OpCodes.Ldarg_1)
        setStateMachineIl.Emit(OpCodes.Call, setStateMachineBuilder)
        setStateMachineIl.Emit(OpCodes.Ret)

        debuggerStepThroughCtor := typeof(System.Diagnostics.DebuggerStepThroughAttribute).GetConstructor(System.Type.EmptyTypes)
        asyncStateMachineCtor := typeof(System.Runtime.CompilerServices.AsyncStateMachineAttribute).GetConstructor([typeof(Type)])
        if debuggerStepThroughCtor == null || asyncStateMachineCtor == null {
            throw new InvalidOperationException("Async state-machine method attributes were not found.")
        }
        kickoff.SetCustomAttribute(debuggerStepThroughCtor, ColumnarAttributeBlobs.NoArgument())
        kickoff.SetCustomAttribute(
            asyncStateMachineCtor,
            ColumnarAttributeBlobs.TypeName(sm.FullName + ", " + module.Assembly.GetName().Name)
        )

        kickoffIl := kickoff.GetILGenerator()
        machineLocal := kickoffIl.DeclareLocal(kickoffMachineType)
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Initobj, kickoffMachineType)
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Ldc_I4_M1)
        kickoffIl.Emit(OpCodes.Stfld, stateField)
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Call, builderCreate)
        kickoffIl.Emit(OpCodes.Stfld, builderField)
        p := 0
        parameterFieldOffset := 1
        if isInstance {
            kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
            kickoffIl.Emit(OpCodes.Ldarg_0)
            if receiverIsValueType {
                kickoffIl.Emit(OpCodes.Ldobj, kickoffFields[1].FieldType)
            }
            kickoffIl.Emit(OpCodes.Stfld, kickoffFields[1])
            parameterFieldOffset = 2
        }
        while p < fn.ParamNames.Length {
            fieldIndex := parameterFieldOffset + p
            kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
            kickoffIl.Emit(OpCodes.Ldarg, p + (isInstance ? 1 : 0))
            kickoffIl.Emit(OpCodes.Stfld, kickoffFields[fieldIndex])
            p += 1
        }
        if asyncClosureBoxNames != null && asyncClosureBoxSourceFields != null {
            boxIndex := 0
            while boxIndex < asyncClosureBoxNames.Length {
                machineFieldName := ColumnarIteratorPlanner.AsyncClosureBoxFieldName(asyncClosureBoxNames[boxIndex])
                machineFieldIndex := 0
                while machineFieldIndex < shape.FieldNames.Length && shape.FieldNames[machineFieldIndex] != machineFieldName {
                    machineFieldIndex += 1
                }
                if machineFieldIndex >= shape.FieldNames.Length || kickoffFields[machineFieldIndex] == null {
                    return Declined("emit.async.closure-box-field", "captured mutable local '" + asyncClosureBoxNames[boxIndex] + "' has no state-machine field", fn.Name)
                }
                kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
                kickoffIl.Emit(OpCodes.Ldarg_0)
                kickoffIl.Emit(OpCodes.Ldfld, asyncClosureBoxSourceFields[boxIndex])
                kickoffIl.Emit(OpCodes.Stfld, kickoffFields[machineFieldIndex])
                boxIndex += 1
            }
        }

        startBuilder: MethodInfo? = null
        startOwner := builderTypeUsesTypeBuilderParameter ? builderDefinition : kickoffBuilderType
        for candidate in startOwner.GetMethods(BindingFlags.Public | BindingFlags.Instance) {
            if candidate.Name == "Start" && candidate.IsGenericMethodDefinition && candidate.GetGenericArguments().Length == 1 && candidate.GetParameters().Length == 1 {
                mappedStart := builderTypeUsesTypeBuilderParameter ? AsyncBuilderMethodOnType(kickoffBuilderType, candidate) : candidate
                startBuilder = mappedStart.MakeGenericMethod([kickoffMachineType])
                break
            }
        }
        if startBuilder == null {
            return Declined("emit.async.builder-start", "the async task builder for '" + fn.Name + "' has no Start<TStateMachine> method", fn.Name)
        }
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Ldflda, builderField)
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Call, startBuilder)
        kickoffIl.Emit(OpCodes.Ldloca, machineLocal)
        kickoffIl.Emit(OpCodes.Ldflda, builderField)
        kickoffIl.Emit(OpCodes.Call, taskGetter)
        kickoffIl.Emit(OpCodes.Ret)

        synthesizedTypes.Add(sm)
        return Completed()
    }

    static func TryResolveAsyncLocalReturnShape(
        canonical: string,
        typeParameters: Dictionary<string, Type>?,
        typeResolution: ColumnarSemanticTypeResolution,
        defaultUsesTaskBuilder: bool,
        out inner: Type?,
        out wrapped: Type?
    ): bool {
        inner = ColumnarTypeOfPlanner.RequiredVoidType()
        wrapped = null
        if canonical == "Task" {
            wrapped = typeof(System.Threading.Tasks.Task)
            return true
        }
        if canonical == "ValueTask" {
            wrapped = typeof(System.Threading.Tasks.ValueTask)
            return true
        }
        if canonical.StartsWith("Task<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !TryResolveIteratorCanonical(canonical.Substring(5, canonical.Length - 6), typeParameters, typeResolution, out inner) {
                return false
            }
            wrapped = typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition().MakeGenericType([inner])
            return true
        }
        if canonical.StartsWith("ValueTask<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !TryResolveIteratorCanonical(canonical.Substring(10, canonical.Length - 11), typeParameters, typeResolution, out inner) {
                return false
            }
            wrapped = typeof(System.Threading.Tasks.ValueTask<int>).GetGenericTypeDefinition().MakeGenericType([inner])
            return true
        }
        if !TryResolveIteratorCanonical(canonical, typeParameters, typeResolution, out inner) {
            return false
        }
        if inner == ColumnarTypeOfPlanner.RequiredVoidType() {
            wrapped = defaultUsesTaskBuilder ? typeof(System.Threading.Tasks.Task) : typeof(System.Threading.Tasks.ValueTask)
        } else if defaultUsesTaskBuilder {
            wrapped = typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition().MakeGenericType([inner])
        } else {
            wrapped = typeof(System.Threading.Tasks.ValueTask<int>).GetGenericTypeDefinition().MakeGenericType([inner])
        }
        return true
    }

    static func EmitAsync(
        module: ModuleBuilder,
        fn: ColumnarFunctionInput,
        funcOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        factoryIl: ILGenerator,
        synthesizedTypes: List<TypeBuilder>,
        bodyFacts: ColumnarIteratorBodyFacts? = null,
        methodTypeParams: Type[]? = null,
        precomputedShape: ColumnarIteratorShape? = null,
        memberLabel: string = "",
        enclosingType: Type? = null,
        enclosingFieldNames: string[]? = null,
        enclosingFields: FieldInfo[]? = null,
        enclosingFieldCanonicals: string[]? = null,
        declaringType: TypeBuilder? = null,
        enclosingTypeParams: Type[]? = null,
        receiverCanonical: string = ""
    ): ColumnarIteratorRealizationResult {
        modifiedMemberReferences := ModifiedMemberReferencesOf(bodyFacts)
        declineLabel := memberLabel.Length == 0 ? fn.Name : memberLabel
        shape := precomputedShape
        if shape == null {
            shape = ColumnarIteratorPlanner.AnalyzeShape(
                fn.BodyNodes,
                functionSource,
                fn.BodyRoot,
                fn.Name,
                funcOrdinal,
                fn.ReturnCanonical,
                fn.ParamNames,
                fn.ParamCanonicals,
                fn.TypeParamNames,
                receiverCanonical.Length > 0,
                receiverCanonical,
                enclosingFieldNames,
                enclosingFieldCanonicals,
                true
            )
        }
        if !shape.Supported {
            return Declined(shape.DeclineSite, shape.DeclineMessage, declineLabel)
        }
        enclosingParameters := enclosingTypeParams ?? System.Type.EmptyTypes
        methodParameters := methodTypeParams ?? System.Type.EmptyTypes
        if methodParameters.Length != fn.TypeParamNames.Length {
            return Declined(
                "emit.iterator.generic-arity",
                "the declared method '" + declineLabel + "' has " + methodParameters.Length.ToString() + " type parameter(s) but its generator body names " + fn.TypeParamNames.Length.ToString(),
                declineLabel
            )
        }
        if enclosingParameters.Length > 0 && declaringType == null {
            return Declined(
                "emit.iterator.generic-enclosing",
                "a machine generic over its declaring type's parameters must be nested in that type for '" + declineLabel + "'",
                declineLabel
            )
        }
        sm := DefineMachineType(module, declaringType, shape.TypeName)
        table := typeResolution.StructuralTypeReferences
        smTypeParamMap: Dictionary<string, Type>? = null
        smTypeParams := System.Type.EmptyTypes
        smSpecialConstraints := System.Array.Empty<int>()
        smBaseConstraints := System.Array.Empty<Type>()
        smInterfaceConstraints := System.Array.Empty<Type[]>()
        machineOwnedParameters: Dictionary<string, Type>? = null
        methodGps: GenericTypeParameterBuilder[]? = null
        if enclosingParameters.Length > 0 || fn.TypeParamNames.Length > 0 {
            enclosingCount := enclosingParameters.Length
            methodCount := fn.TypeParamNames.Length
            parameterNames := new string[](enclosingCount + methodCount)
            n := 0
            while n < enclosingCount {
                parameterNames[n] = enclosingParameters[n].Name
                n = n + 1
            }
            n = 0
            while n < methodCount {
                parameterNames[enclosingCount + n] = fn.TypeParamNames[n]
                n = n + 1
            }
            smGps := sm.DefineGenericParameters(parameterNames)
            smTypeParamMap = new Dictionary<string, Type>(StringComparer.Ordinal)
            smTypeParams = new Type[](smGps.Length)
            smSpecialConstraints = new int[](smGps.Length)
            smBaseConstraints = new Type[](smGps.Length)
            smInterfaceConstraints = new Type[][](smGps.Length)
            e := 0
            while e < enclosingCount {
                enclosingParameter := enclosingParameters[e]
                if !enclosingParameter.IsGenericParameter || enclosingParameter.GenericParameterPosition != e {
                    return Declined(
                        "emit.iterator.generic-enclosing",
                        "the declaring type's parameter '" + enclosingParameter.Name + "' is not at position " + e.ToString() + " for '" + declineLabel + "'",
                        declineLabel
                    )
                }
                smTypeParamMap[enclosingParameter.Name] = enclosingParameter
                smTypeParams[e] = enclosingParameter
                enclosingSpecial := 0
                enclosingBase: Type? = null
                enclosingInterfaces := System.Type.EmptyTypes
                if !TryCopyEnclosingConstraints(enclosingParameter, smGps[e], out enclosingSpecial, out enclosingBase, out enclosingInterfaces) {
                    return Declined(
                        "emit.iterator.generic-constraints",
                        "the constraints on the declaring type's parameter '" + enclosingParameter.Name + "' could not be preserved on the iterator machine for '" + declineLabel + "'",
                        declineLabel
                    )
                }
                smSpecialConstraints[e] = enclosingSpecial
                smBaseConstraints[e] = enclosingBase
                smInterfaceConstraints[e] = enclosingInterfaces
                e = e + 1
            }
            methodGps = new GenericTypeParameterBuilder[](methodCount)
            machineOwnedParameters = new Dictionary<string, Type>(StringComparer.Ordinal)
            g := 0
            while g < methodCount {
                methodGps[g] = smGps[enclosingCount + g]
                parameter: Type = methodGps[g]
                smTypeParamMap[fn.TypeParamNames[g]] = parameter
                smTypeParams[enclosingCount + g] = parameter
                machineOwnedParameters[fn.TypeParamNames[g]] = parameter
                g = g + 1
            }
        }
        elementType: Type = null
        if !TryResolveIteratorCanonical(shape.ElementCanonical, smTypeParamMap, typeResolution, out elementType) || !ColumnarTypeOfPlanner.IsSupportedType(elementType) {
            return Declined(
                "emit.iterator.element-type",
                "iterator element type '" + shape.ElementCanonical + "' could not be resolved for '" + declineLabel + "'",
                declineLabel
            )
        }
        // An async iterator that cannot resolve its element type is declined before it contributes a
        // synthesized machine to the shared type map. Keep this registration after that validation;
        // the synchronous realization intentionally retains its earlier registration contract.
        table.RegisterIteratorType(
            fn.SourceFileId,
            funcOrdinal,
            shape.TypeName,
            sm,
            machineOwnedParameters
        )
        if methodGps != null && smTypeParamMap != null {
            methodSpecialConstraints := System.Array.Empty<int>()
            methodBaseConstraints := System.Array.Empty<Type>()
            methodInterfaceConstraints := System.Array.Empty<Type[]>()
            if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(methodGps, fn.TypeParamSpecialConstraints, fn.TypeParamTypeConstraints, smTypeParamMap, smTypeParams, typeResolution, out methodSpecialConstraints, out methodBaseConstraints, out methodInterfaceConstraints) {
                return Declined(
                    "emit.iterator.generic-constraints",
                    "iterator generic constraints could not be preserved for '" + declineLabel + "'",
                    declineLabel
                )
            }
            g := 0
            while g < methodGps.Length {
                parameterIndex := enclosingParameters.Length + g
                smSpecialConstraints[parameterIndex] = methodSpecialConstraints[g]
                smBaseConstraints[parameterIndex] = methodBaseConstraints[g]
                smInterfaceConstraints[parameterIndex] = methodInterfaceConstraints[g]
                g = g + 1
            }
        }
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
            } else if !TryResolveIteratorCanonical(shape.FieldCanonicals[i], smTypeParamMap, typeResolution, out fieldType) || !ColumnarTypeOfPlanner.IsSupportedType(fieldType) {
                return Declined(
                    "emit.iterator.field-type",
                    "iterator hoisted field type '" + shape.FieldCanonicals[i] + "' could not be resolved for '" + declineLabel + "'",
                    declineLabel
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
        memberSmType: Type = sm
        memberFields := fields
        memberCtor: ConstructorInfo = ctor
        memberCore: MethodInfo = core
        if smTypeParamMap != null {
            memberSmType = sm.MakeGenericType(smTypeParams)
            memberFields = new FieldInfo[](fields.Length)
            i = 0
            while i < fields.Length {
                if fields[i] != null {
                    memberFields[i] = TypeBuilder.GetField(memberSmType, (FieldBuilder)fields[i])
                }
                i = i + 1
            }
            memberCtor = TypeBuilder.GetConstructor(memberSmType, ctor)
            memberCore = TypeBuilder.GetMethod(memberSmType, core)
        }
        ctorIl := ctor.GetILGenerator()
        ctorIl.Emit(OpCodes.Ldarg_0)
        objectCtor := typeof(object).GetConstructor(System.Type.EmptyTypes)
        ColumnarEmitReflectionFacts.EmitConstructor(ctorIl, OpCodes.Call, objectCtor, "System.Object parameterless constructor")
        ctorIl.Emit(OpCodes.Ldarg_0)
        ctorIl.Emit(OpCodes.Ldarg_1)
        ctorIl.Emit(OpCodes.Stfld, fields[0])
        ctorIl.Emit(OpCodes.Ldarg_0)
        ctorIl.Emit(OpCodes.Ldarg_0)
        coreHandle := memberCore
        ctorIl.Emit(OpCodes.Ldftn, coreHandle)
        actionConstructorTypes := new Type[](2)
        actionConstructorTypes[0] = typeof(object)
        actionConstructorTypes[1] = typeof(IntPtr)
        actionCtor := typeof(Action).GetConstructor(actionConstructorTypes)
        ColumnarEmitReflectionFacts.EmitConstructor(ctorIl, OpCodes.Newobj, actionCtor, "System.Action(object, IntPtr) delegate constructor")
        ctorIl.Emit(OpCodes.Stfld, continuationField)
        ctorIl.Emit(OpCodes.Ret)

        ctorHandle: ConstructorInfo = memberCtor
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
            ctorHandle,
            enclosingType,
            enclosingFieldNames,
            enclosingFields,
            enclosingFieldCanonicals,
            memberCore,
            bodyFacts,
            sm,
            smTypeParamMap == null ? null : memberSmType,
            smTypeParamMap,
            fields,
            synthesizedTypes,
            fn.SourceFileId,
            smSpecialConstraints,
            smBaseConstraints,
            smInterfaceConstraints,
            smTypeParams
        )
        overrideContext := ColumnarIteratorOverrideContext.ForAsync(table, elementType, asyncEnumerable, asyncEnumerator)
        publicImpl := MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.HideBySig | MethodAttributes.NewSlot

        corePlan := ColumnarIteratorBodyPlanner.BuildAsyncMoveNextCorePlan(context)
        if context.Declined {
            return Declined(context.DeclineSite, context.DeclineMessage + " in '" + declineLabel + "'", declineLabel)
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

        factoryContext := context
        if smTypeParamMap != null {
            factoryTypeArguments := new Type[](enclosingParameters.Length + methodParameters.Length)
            enclosingParameters.CopyTo(factoryTypeArguments, 0)
            methodParameters.CopyTo(factoryTypeArguments, enclosingParameters.Length)
            if factoryTypeArguments.Length != smTypeParams.Length {
                return Declined(
                    "emit.iterator.generic-arity",
                    "the factory for '" + declineLabel + "' supplies " + factoryTypeArguments.Length.ToString() + " type argument(s) for a machine with " + smTypeParams.Length.ToString(),
                    declineLabel
                )
            }
            factorySmType := sm.MakeGenericType(factoryTypeArguments)
            factoryFields := new FieldInfo[](fields.Length)
            i = 0
            while i < fields.Length {
                if fields[i] != null {
                    factoryFields[i] = TypeBuilder.GetField(factorySmType, (FieldBuilder)fields[i])
                }
                i = i + 1
            }
            factoryCtor := TypeBuilder.GetConstructor(factorySmType, ctor)
            factoryEnclosingType := enclosingType
            if enclosingType != null && declaringType != null {
                factoryEnclosingType = ColumnarSourceSelfInstantiation.Of(declaringType)
            }
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
                factoryCtor,
                factoryEnclosingType
            )
        }
        factoryPlan := ColumnarIteratorBodyPlanner.BuildAsyncFactoryPlan(factoryContext)
        ColumnarCodePlanExecutor.Execute(factoryPlan, factoryIl, modifiedMemberReferences)
        synthesizedTypes.Add(sm)
        return Completed()
    }

    // THE DECLARING TYPE'S CONSTRAINTS, RESTATED ON THE MACHINE'S PARAMETER AT THE SAME POSITION.
    // Without them the machine could not name `Box<!0>` at all — the runtime checks the instantiation
    // against `Box`'s own constraints — nor make a constrained call its body plans against them. The
    // constraints are read back from the declaring type's own builder, so they are the exact handles the
    // declaration pass set; they mention the declaring type's parameters, which encode by position and
    // therefore mean the machine's. A bit the language does not model is refused rather than dropped.
    static func TryCopyEnclosingConstraints(
        source: Type,
        destination: GenericTypeParameterBuilder,
        out special: int,
        out baseConstraint: Type?,
        out interfaceConstraints: Type[]
    ): bool {
        special = 0
        baseConstraint = null
        interfaceConstraints = System.Type.EmptyTypes
        attributeBits := (int)source.GenericParameterAttributes
        if !ColumnarGenericConstraintPlanner.TrySpecialFor(attributeBits, out special) {
            return false
        }
        if special != 0 {
            destination.SetGenericParameterAttributes((GenericParameterAttributes)ColumnarGenericConstraintPlanner.AttributeBitsFor(special))
        }
        interfaces := new List<Type>()
        for constraint in source.GetGenericParameterConstraints() {
            if constraint.IsInterface {
                interfaces.Add(constraint)
                continue
            }
            if baseConstraint != null {
                return false
            }
            baseConstraint = constraint
        }
        if baseConstraint != null {
            destination.SetBaseTypeConstraint(baseConstraint)
        }
        interfaceConstraints = interfaces.ToArray()
        if interfaceConstraints.Length > 0 {
            destination.SetInterfaceConstraints(interfaceConstraints)
        }
        return true
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
            ) && (resolvedType.IsGenericParameter || (ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(resolvedType) && ColumnarEmitReflectionFacts.RequiredElementType(resolvedType.GetElementType(), "array element type in iterator parameter analysis").IsGenericParameter) || ColumnarTypeOfPlanner.IsSupportedType(resolvedType)) && !ContainsMethodVarReference(resolvedType, smTypeParamMap)
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
            return ContainsMethodVarReference(ColumnarEmitReflectionFacts.RequiredElementType(valueType.GetElementType(), "element type of iterator signature"), smTypeParamMap)
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
