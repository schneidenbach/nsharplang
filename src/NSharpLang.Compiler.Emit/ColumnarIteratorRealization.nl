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

class ColumnarAsyncLocalFunctionRequest {
    Function: ColumnarFunctionInput
    Ordinal: int
    Kickoff: MethodBuilder
    ResultType: Type
    WrappedType: Type
    CaptureNames: string[]
    KickoffReceiverField: FieldInfo?

    constructor(function: ColumnarFunctionInput, ordinal: int, kickoff: MethodBuilder, resultType: Type, wrappedType: Type, captureNames: string[], kickoffReceiverField: FieldInfo? = null) {
        Function = function
        Ordinal = ordinal
        Kickoff = kickoff
        ResultType = resultType
        WrappedType = wrappedType
        CaptureNames = captureNames
        KickoffReceiverField = kickoffReceiverField
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

    // A nested async local's result is first resolved in the containing machine's generic context,
    // then stored on a child machine which owns a copied set of those parameters. Rebind only type
    // parameters declared by that owner; method parameters remain available for the method-parameter
    // substitution that follows.
    static func TryRebindAsyncOwnerTypeParameters(ownerType: Type, sourceParameters: Type[], targetParameters: Type[], sourceType: Type, out reboundType: Type): bool {
        reboundType = null
        if sourceType == null || sourceParameters.Length != targetParameters.Length {
            return false
        }
        if sourceType.IsGenericParameter {
            if sourceType.DeclaringMethod != null {
                reboundType = sourceType
                return true
            }
            parameterIndex := 0
            while parameterIndex < sourceParameters.Length {
                sourceParameter := sourceParameters[parameterIndex]
                if sourceType.GenericParameterPosition == parameterIndex && sourceParameter.DeclaringType == ownerType && sourceType.DeclaringType == ownerType {
                    reboundType = targetParameters[parameterIndex]
                    return reboundType != null
                }
                if Object.ReferenceEquals(sourceType, sourceParameter) || sourceType == sourceParameter {
                    reboundType = targetParameters[parameterIndex]
                    return reboundType != null
                }
                parameterIndex += 1
            }
            reboundType = sourceType
            return true
        }
        if sourceType.IsByRef {
            elementType: Type = null
            sourceElementType := ColumnarEmitReflectionFacts.RequiredElementType(sourceType.GetElementType(), "by-ref element type in async owner result rebinding")
            if !TryRebindAsyncOwnerTypeParameters(ownerType, sourceParameters, targetParameters, sourceElementType, out elementType) {
                return false
            }
            reboundType = elementType.MakeByRefType()
            return true
        }
        if sourceType.IsPointer {
            elementType: Type = null
            sourceElementType := ColumnarEmitReflectionFacts.RequiredElementType(sourceType.GetElementType(), "pointer element type in async owner result rebinding")
            if !TryRebindAsyncOwnerTypeParameters(ownerType, sourceParameters, targetParameters, sourceElementType, out elementType) {
                return false
            }
            reboundType = elementType.MakePointerType()
            return true
        }
        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(sourceType) {
            elementType: Type = null
            sourceElementType := ColumnarEmitReflectionFacts.RequiredElementType(sourceType.GetElementType(), "array element type in async owner result rebinding")
            if !TryRebindAsyncOwnerTypeParameters(ownerType, sourceParameters, targetParameters, sourceElementType, out elementType) {
                return false
            }
            reboundType = elementType.MakeArrayType()
            return true
        }
        if sourceType.IsArray {
            elementType: Type = null
            sourceElementType := ColumnarEmitReflectionFacts.RequiredElementType(sourceType.GetElementType(), "array element type in async owner result rebinding")
            if !TryRebindAsyncOwnerTypeParameters(ownerType, sourceParameters, targetParameters, sourceElementType, out elementType) {
                return false
            }
            reboundType = elementType.MakeArrayType(sourceType.GetArrayRank())
            return true
        }
        if sourceType.IsGenericType && !sourceType.IsGenericTypeDefinition {
            sourceArguments := sourceType.GetGenericArguments()
            reboundArguments := new Type[sourceArguments.Length]
            argumentIndex := 0
            while argumentIndex < sourceArguments.Length {
                reboundArgument: Type = null
                if !TryRebindAsyncOwnerTypeParameters(ownerType, sourceParameters, targetParameters, sourceArguments[argumentIndex], out reboundArgument) {
                    return false
                }
                reboundArguments[argumentIndex] = reboundArgument
                argumentIndex += 1
            }
            reboundType = sourceType.GetGenericTypeDefinition().MakeGenericType(reboundArguments)
            return true
        }
        reboundType = sourceType
        return true
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
        asyncLambdaResult := EmitAsyncLambdaRequests(module, funcOrdinal, functionSource, typeResolution, synthesizedTypes, bodyFacts, context)
        if !asyncLambdaResult.Succeeded {
            return asyncLambdaResult
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
                TypeAttributes.NestedPrivate | TypeAttributes.Sealed,
                typeof(ValueType)
            )
        }
        return module.DefineType(name, TypeAttributes.NotPublic | TypeAttributes.Sealed, typeof(ValueType))
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

        // Start<TStateMachine> has the same Reflection.Emit rebinding limitation as the generic
        // builder factory and Task getter when the result type is a builder-owned parameter. Route
        // it through a bridge whose two method parameters match the kickoff's actual builder and
        // constructed machine signatures.
        start := bridgeType.DefineMethod("Start", bridgeAttributes)
        startParameters := start.DefineGenericParameters(["TResult", "TStateMachine"])
        startParameters[1].SetInterfaceConstraints([stateMachineInterface])
        startBuilder := builderResultDefinition.MakeGenericType([startParameters[0]])
        start.SetReturnType(typeof(void))
        startParameterTypes := new Type[](2)
        startParameterTypes[0] = startBuilder.MakeByRefType()
        startParameterTypes[1] = startParameters[1].MakeByRefType()
        start.SetParameters(startParameterTypes)
        startMethod := FindAsyncBuilderMethod(builderResultDefinition, "Start", 1, 1)
        startMethod = TypeBuilder.GetMethod(startBuilder, startMethod).MakeGenericMethod([startParameters[1]])
        startIl := start.GetILGenerator()
        startIl.Emit(OpCodes.Ldarg_0)
        startIl.Emit(OpCodes.Ldarg_1)
        startIl.Emit(OpCodes.Call, startMethod)
        startIl.Emit(OpCodes.Ret)

        // The generic builder factory is a static member and Reflection.Emit cannot consistently
        // rebind it over a TypeBuilderInstantiation. `Create()` returns the zero-initialized builder;
        // this bridge expresses that factory for the method's generic result parameter.
        createBuilder := bridgeType.DefineMethod("CreateBuilder", bridgeAttributes)
        createBuilderParameters := createBuilder.DefineGenericParameters(["TResult"])
        createBuilderType := builderResultDefinition.MakeGenericType([createBuilderParameters[0]])
        createBuilder.SetReturnType(createBuilderType)
        createBuilder.SetParameters(System.Type.EmptyTypes)
        createBuilderIl := createBuilder.GetILGenerator()
        createBuilderLocal := createBuilderIl.DeclareLocal(createBuilderType)
        createBuilderIl.Emit(OpCodes.Ldloca, createBuilderLocal)
        createBuilderIl.Emit(OpCodes.Initobj, createBuilderType)
        createBuilderIl.Emit(OpCodes.Ldloc, createBuilderLocal)
        createBuilderIl.Emit(OpCodes.Ret)

        // A kickoff method whose result contains its own generic parameter cannot ask
        // Reflection.Emit to rebind `AsyncTaskMethodBuilder<T>.Task` directly on the
        // TypeBuilderInstantiation. Give the accessor the same closed generic bridge the builder
        // operations above use, so both Task<T> and ValueTask<T> results keep their exact signature.
        getTask := bridgeType.DefineMethod("GetTask", bridgeAttributes)
        getTaskParameters := getTask.DefineGenericParameters(["TResult"])
        getTaskBuilder := builderResultDefinition.MakeGenericType([getTaskParameters[0]])
        taskProperty := builderResultDefinition.GetProperty("Task")
        if taskProperty == null || taskProperty.GetMethod == null {
            throw new InvalidOperationException("the generic async builder has no Task getter")
        }
        builderTypeParameters := builderResultDefinition.GetGenericArguments()
        bridgeTaskReturn := typeof(object)
        if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(builderTypeParameters, [getTaskParameters[0]], taskProperty.PropertyType, out bridgeTaskReturn) {
            throw new InvalidOperationException("the generic async builder Task type could not be rebound")
        }
        getTask.SetReturnType(bridgeTaskReturn)
        getTask.SetParameters([getTaskBuilder.MakeByRefType()])
        getTaskMethod := TypeBuilder.GetMethod(getTaskBuilder, taskProperty.GetMethod)
        getTaskIl := getTask.GetILGenerator()
        getTaskIl.Emit(OpCodes.Ldarg_0)
        getTaskIl.Emit(OpCodes.Call, getTaskMethod)
        getTaskIl.Emit(OpCodes.Ret)

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
        return new ColumnarAsyncBuilderMethodBridges(awaitOn, awaitUnsafe, start, createBuilder, getTask, setException, setResult, setStateMachine)
    }

    static func FindAsyncBuilderMethod(builderDefinition: Type, name: string, genericArity: int, parameterCount: int): MethodInfo {
        for candidate in builderDefinition.GetMethods(BindingFlags.Instance | BindingFlags.Public) {
            if IsExactAsyncBuilderMethod(candidate, name, genericArity, parameterCount) {
                return candidate
            }
        }
        throw new InvalidOperationException("the async builder has no " + name + " method with the expected generic signature")
    }

    static func IsExactAsyncBuilderMethod(candidate: MethodInfo, name: string, genericArity: int, parameterCount: int): bool {
        if candidate == null || name == null || candidate.Name != name || candidate.IsStatic || !candidate.IsPublic || !candidate.IsGenericMethodDefinition || genericArity != parameterCount {
            return false
        }
        genericParameters := candidate.GetGenericArguments()
        parameters := candidate.GetParameters()
        if genericParameters.Length != genericArity || parameters.Length != parameterCount || candidate.ReturnType != typeof(void) {
            return false
        }
        index := 0
        while index < parameterCount {
            if genericParameters[index].GenericParameterAttributes != GenericParameterAttributes.None {
                return false
            }
            parameterType := parameters[index].ParameterType
            if !parameterType.IsByRef || parameterType.GetElementType() != genericParameters[index] {
                return false
            }
            expectedConstraint: Type? = null
            if name == "AwaitOnCompleted" && index == 0 {
                expectedConstraint = typeof(System.Runtime.CompilerServices.INotifyCompletion)
            } else if name == "AwaitUnsafeOnCompleted" && index == 0 {
                expectedConstraint = typeof(System.Runtime.CompilerServices.ICriticalNotifyCompletion)
            } else if name == "Start" && index == 0 || (name == "AwaitOnCompleted" || name == "AwaitUnsafeOnCompleted") && index == 1 {
                expectedConstraint = typeof(System.Runtime.CompilerServices.IAsyncStateMachine)
            } else {
                return false
            }
            constraints := genericParameters[index].GetGenericParameterConstraints()
            if constraints.Length != 1 || constraints[0] != expectedConstraint {
                return false
            }
            index += 1
        }
        return true
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
            null,
            null,
            false
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
        asyncClosureBoxSourceFields: FieldInfo[]? = null,
        kickoffReceiverField: FieldInfo? = null,
        enclosingOwnerIsAsyncStateMachine: bool = false
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
                closureBoxCanonicals[boxIndex] = ColumnarIteratorPlanner.UnresolvedCanonical()
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
        machineOwnedParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        enclosingTypeParameters := System.Type.EmptyTypes
        if enclosingType != null && enclosingType.IsGenericTypeDefinition {
            enclosingTypeParameters = enclosingType.GetGenericArguments()
        }
        enclosingParameterCount := enclosingTypeParameters.Length
        methodParameterCount := fn.TypeParamNames.Length
        sm := DefineAsyncMachineType(module, enclosingType, shape.TypeName)
        if enclosingParameterCount > 0 || methodParameterCount > 0 {
            combinedParameterNames := new string[enclosingParameterCount + methodParameterCount]
            parameterIndex := 0
            while parameterIndex < enclosingParameterCount {
                combinedParameterNames[parameterIndex] = enclosingTypeParameters[parameterIndex].Name
                parameterIndex += 1
            }
            parameterIndex = 0
            while parameterIndex < methodParameterCount {
                combinedParameterNames[enclosingParameterCount + parameterIndex] = fn.TypeParamNames[parameterIndex]
                parameterIndex += 1
            }
            machineParameterBuilders := sm.DefineGenericParameters(combinedParameterNames)
            machineTypeParameters = new Type[machineParameterBuilders.Length]
            machineSpecialConstraints = new int[machineParameterBuilders.Length]
            machineBaseConstraints = new Type[machineParameterBuilders.Length]
            machineInterfaceConstraints = new Type[][](machineParameterBuilders.Length)
            parameterIndex = 0
            while parameterIndex < enclosingParameterCount {
                enclosingParameter := enclosingTypeParameters[parameterIndex]
                if !enclosingParameter.IsGenericParameter || enclosingParameter.GenericParameterPosition != parameterIndex {
                    return Declined("emit.async.generic-enclosing", "the declaring type's parameter '" + enclosingParameter.Name + "' is not at position " + parameterIndex.ToString() + " for async function '" + fn.Name + "'", fn.Name)
                }
                if enclosingOwnerIsAsyncStateMachine {
                    machineTypeParameterMap[enclosingParameter.Name] = machineParameterBuilders[parameterIndex]
                    machineTypeParameters[parameterIndex] = machineParameterBuilders[parameterIndex]
                } else {
                    machineTypeParameterMap[enclosingParameter.Name] = enclosingParameter
                    machineTypeParameters[parameterIndex] = enclosingParameter
                }
                enclosingSpecial := 0
                enclosingBase: Type? = null
                enclosingInterfaces := System.Type.EmptyTypes
                if !TryCopyEnclosingConstraints(enclosingParameter, machineParameterBuilders[parameterIndex], out enclosingSpecial, out enclosingBase, out enclosingInterfaces) {
                    return Declined("emit.async.generic-constraints", "the constraints on the declaring type's parameter '" + enclosingParameter.Name + "' could not be preserved on async function '" + fn.Name + "'", fn.Name)
                }
                machineSpecialConstraints[parameterIndex] = enclosingSpecial
                machineBaseConstraints[parameterIndex] = enclosingBase
                machineInterfaceConstraints[parameterIndex] = enclosingInterfaces
                // The state machine's copy of the declaring type parameter is a distinct CLR
                // parameter from the source type's parameter. A nested async local machine closes
                // over this copy, so it needs the synthesized machine owner registered as well.
                machineOwnedParameters[enclosingParameter.Name] = machineParameterBuilders[parameterIndex]
                parameterIndex += 1
            }
            methodParameterBuilders := new GenericTypeParameterBuilder[methodParameterCount]
            parameterIndex = 0
            while parameterIndex < methodParameterCount {
                methodParameterBuilders[parameterIndex] = machineParameterBuilders[enclosingParameterCount + parameterIndex]
                methodParameter: Type = methodParameterBuilders[parameterIndex]
                machineTypeParameterMap[fn.TypeParamNames[parameterIndex]] = methodParameter
                machineTypeParameters[enclosingParameterCount + parameterIndex] = methodParameter
                machineOwnedParameters[fn.TypeParamNames[parameterIndex]] = methodParameter
                parameterIndex += 1
            }
            typeResolution.StructuralTypeReferences.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, machineOwnedParameters)
            methodSpecialConstraints := System.Array.Empty<int>()
            methodBaseConstraints := System.Array.Empty<Type>()
            methodInterfaceConstraints := System.Array.Empty<Type[]>()
            if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(methodParameterBuilders, fn.TypeParamSpecialConstraints, fn.TypeParamTypeConstraints, machineTypeParameterMap, machineTypeParameters, typeResolution, out methodSpecialConstraints, out methodBaseConstraints, out methodInterfaceConstraints) {
                return Declined("emit.async.generic-constraints", "generic constraints on async function '" + fn.Name + "' could not be preserved on its state machine", fn.Name)
            }
            parameterIndex = 0
            while parameterIndex < methodParameterCount {
                machineIndex := enclosingParameterCount + parameterIndex
                machineSpecialConstraints[machineIndex] = methodSpecialConstraints[parameterIndex]
                machineBaseConstraints[machineIndex] = methodBaseConstraints[parameterIndex]
                machineInterfaceConstraints[machineIndex] = methodInterfaceConstraints[parameterIndex]
                parameterIndex += 1
            }
        } else {
            typeResolution.StructuralTypeReferences.RegisterIteratorType(fn.SourceFileId, funcOrdinal, shape.TypeName, sm, null)
        }
        machineType: Type = sm
        kickoffMachineType: Type = sm
        machineResultType := resultType
        if machineTypeParameters.Length > 0 {
            machineType = sm.MakeGenericType(machineTypeParameters)
            kickoffTypeArguments := new Type[enclosingParameterCount + kickoffMethodTypeParameters.Length]
            parameterIndex := 0
            while parameterIndex < enclosingParameterCount {
                kickoffTypeArguments[parameterIndex] = enclosingTypeParameters[parameterIndex]
                parameterIndex += 1
            }
            parameterIndex = 0
            while parameterIndex < kickoffMethodTypeParameters.Length {
                kickoffTypeArguments[enclosingParameterCount + parameterIndex] = kickoffMethodTypeParameters[parameterIndex]
                parameterIndex += 1
            }
            kickoffMachineType = sm.MakeGenericType(kickoffTypeArguments)
            if resultType != ColumnarTypeOfPlanner.RequiredVoidType() && enclosingOwnerIsAsyncStateMachine && enclosingParameterCount > 0 {
                machineEnclosingTypeParameters := new Type[enclosingParameterCount]
                parameterIndex = 0
                while parameterIndex < enclosingParameterCount {
                    machineEnclosingTypeParameters[parameterIndex] = machineTypeParameters[parameterIndex]
                    parameterIndex += 1
                }
                if bodyFacts != null && bodyFacts.EnclosingTypeDefinition != null && bodyFacts.EnclosingTypeDefinition.Builder.IsGenericTypeDefinition {
                    sourceDeclaringTypeParameters := bodyFacts.EnclosingTypeDefinition.Builder.GetGenericArguments()
                    declaringTypeParameterCount := sourceDeclaringTypeParameters.Length
                    if declaringTypeParameterCount > enclosingParameterCount {
                        return Declined("emit.async.generic-result", "the enclosing declaring type has more generic parameters than async function '" + fn.Name + "' can preserve", fn.Name)
                    }
                    declaringTypeMachineParameters := new Type[declaringTypeParameterCount]
                    parameterIndex = 0
                    while parameterIndex < declaringTypeParameterCount {
                        declaringTypeMachineParameters[parameterIndex] = machineEnclosingTypeParameters[parameterIndex]
                        parameterIndex += 1
                    }
                    if !TryRebindAsyncOwnerTypeParameters(bodyFacts.EnclosingTypeDefinition.Builder, sourceDeclaringTypeParameters, declaringTypeMachineParameters, machineResultType, out machineResultType) {
                        return Declined("emit.async.generic-result", "the enclosing declaring type result of async function '" + fn.Name + "' could not be rebound to its state machine", fn.Name)
                    }
                }
                if !TryRebindAsyncOwnerTypeParameters(enclosingType, enclosingTypeParameters, machineEnclosingTypeParameters, machineResultType, out machineResultType) {
                    return Declined("emit.async.generic-result", "the enclosing generic result type of async function '" + fn.Name + "' could not be rebound to its state machine", fn.Name)
                }
            }
            if resultType != ColumnarTypeOfPlanner.RequiredVoidType() && methodParameterCount > 0 {
                machineMethodTypeParameters := new Type[methodParameterCount]
                parameterIndex = 0
                while parameterIndex < methodParameterCount {
                    machineMethodTypeParameters[parameterIndex] = machineTypeParameters[enclosingParameterCount + parameterIndex]
                    parameterIndex += 1
                }
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(kickoffMethodTypeParameters, machineMethodTypeParameters, machineResultType, out machineResultType) {
                    return Declined("emit.async.generic-result", "the generic result type of async function '" + fn.Name + "' could not be rebound to its state machine", fn.Name)
                }
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
                captureName := ColumnarIteratorPlanner.AsyncClosureBoxCaptureName(shape.FieldNames[i])
                captureIndex := 0
                while asyncClosureBoxNames != null && captureIndex < asyncClosureBoxNames.Length && asyncClosureBoxNames[captureIndex] != captureName {
                    captureIndex += 1
                }
                if asyncClosureBoxNames == null || asyncClosureBoxSourceFields == null || captureIndex >= asyncClosureBoxNames.Length || asyncClosureBoxSourceFields[captureIndex] == null {
                    return Declined("emit.async.closure-box-type", "a captured mutable local on async function '" + fn.Name + "' cannot be represented in its state machine", fn.Name)
                }
                fieldType = asyncClosureBoxSourceFields[captureIndex].FieldType
                if !ColumnarTypeOfPlanner.IsSupportedType(fieldType) {
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
            if builderBridges != null {
                builderCreate = builderBridges.Create.MakeGenericMethod([resultType])
                taskGetter = builderBridges.GetTask.MakeGenericMethod([resultType])
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

        // Local async kickoffs are declared before the parent body plan so call sites can bind them.
        // Their child machines are realized after that plan, when inferred parent fields and capture
        // boxes have exact CLR handles.
        asyncLocalRequests := new List<ColumnarAsyncLocalFunctionRequest>()
        if fn.LocalFunctions != null {
            parentBindings := new HashSet<string>(StringComparer.Ordinal)
            for parameterName in fn.ParamNames {
                parentBindings.Add(parameterName)
            }
            ColumnarLocalFunctionClosurePlanner.CollectDeclaringScopeBindingNames(fn.BodyNodes, functionSource, fn.BodyRoot, parentBindings)
            enclosingNames := new HashSet<string>(StringComparer.Ordinal)
            if bodyFacts != null && bodyFacts.EnclosingTypeDefinition != null {
                enclosingNames = ColumnarLocalFunctionClosurePlanner.EnclosingInstanceNames(bodyFacts.EnclosingTypeDefinition)
            }
            localFunctionOrdinal := 0
            for localFunction in fn.LocalFunctions {
                localFn := localFunction.Function
                if !localFn.IsAsync {
                    localFunctionOrdinal += 1
                    continue
                }
                localTypeParameterMap := new Dictionary<string, Type>(machineTypeParameterMap, StringComparer.Ordinal)
                localMethodTypeParameters := System.Type.EmptyTypes
                localMethodSpecialConstraints := System.Array.Empty<int>()
                localMethodBaseConstraints := System.Array.Empty<Type>()
                localMethodInterfaceConstraints := System.Array.Empty<Type[]>()
                localMethodName := "<>__asyncLocal" + localFunctionOrdinal.ToString()
                localMethodAttributes := MethodAttributes.Assembly | MethodAttributes.HideBySig
                let localMethodInitialReturn: System.Type? = null
                let localMethodInitialParameters: System.Type[]? = null
                localMethod := sm.DefineMethod(localMethodName, localMethodAttributes, localMethodInitialReturn, localMethodInitialParameters)
                if localFn.TypeParamNames.Length > 0 {
                    localMethodParameterBuilders := localMethod.DefineGenericParameters(localFn.TypeParamNames)
                    localMethodTypeParameters = new Type[localMethodParameterBuilders.Length]
                    parameterIndex := 0
                    while parameterIndex < localMethodParameterBuilders.Length {
                        localMethodTypeParameters[parameterIndex] = localMethodParameterBuilders[parameterIndex]
                        localTypeParameterMap[localFn.TypeParamNames[parameterIndex]] = localMethodParameterBuilders[parameterIndex]
                        parameterIndex += 1
                    }
                    if !ColumnarGenericConstraintPlanner.TryApplyGenericParameterConstraints(
                        localMethodParameterBuilders,
                        localFn.TypeParamSpecialConstraints,
                        localFn.TypeParamTypeConstraints,
                        localTypeParameterMap,
                        localMethodTypeParameters,
                        typeResolution,
                        out localMethodSpecialConstraints,
                        out localMethodBaseConstraints,
                        out localMethodInterfaceConstraints
                    ) {
                        return Declined("emit.async.local-function.generic-constraints", "generic constraints on async local function '" + localFn.Name + "' could not be preserved", fn.Name + "." + localFn.Name)
                    }
                    localOwnedParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
                    parameterIndex = 0
                    while parameterIndex < localFn.TypeParamNames.Length {
                        localOwnedParameters[localFn.TypeParamNames[parameterIndex]] = localMethodTypeParameters[parameterIndex]
                        parameterIndex += 1
                    }
                    typeResolution.StructuralTypeReferences.RegisterGenericParameters(
                        localOwnedParameters,
                        ColumnarStructuralGenericOwnerIdentity.SourceTypeMethod(localFn.SourceFileId, fn.Name + "." + localFn.Name, funcOrdinal * 1000 + localFunctionOrdinal + 1)
                    )
                }
                localInner: Type? = null
                localWrapped: Type? = null
                if !TryResolveAsyncLocalReturnShape(
                    localFn.ReturnCanonical,
                    localTypeParameterMap,
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
                    if !TryResolveIteratorCanonical(localFn.ParamCanonicals[parameterIndex], localTypeParameterMap, typeResolution, out localParameterType) || !ColumnarTypeOfPlanner.IsSupportedType(localParameterType) {
                        return Declined("emit.async.local-function.parameter", "parameter '" + localFn.ParamNames[parameterIndex] + "' of async local function '" + localFn.Name + "' has unsupported type '" + localFn.ParamCanonicals[parameterIndex] + "'", fn.Name + "." + localFn.Name)
                    }
                    localParameterTypes[parameterIndex] = localParameterType
                    parameterIndex += 1
                }
                localMethod.SetReturnType(localWrapped)
                localMethod.SetParameters(localParameterTypes)
                ColumnarLambdaPlacementPlanner.DefineSourceParameterNames(localMethod, localFn.ParamNames)
                localMethodForContext: MethodInfo = localMethod
                if machineTypeParameters.Length > 0 {
                    localMethodForContext = TypeBuilder.GetMethod(machineType, localMethod)
                }
                if bodyFacts != null {
                    bodyFacts.AddLocalAsyncCallable(
                        localFn.Name,
                        localMethodForContext,
                        localParameterTypes,
                        localFn.ParamNames,
                        localFn.ParamModifierKinds,
                        localWrapped,
                        localFn.ParamDefaultKinds,
                        localFn.ParamDefaultTexts,
                        localFn.TypeParamNames.Length,
                        localMethodSpecialConstraints,
                        localMethodBaseConstraints,
                        localMethodInterfaceConstraints
                    )
                }
                oneLocalFunction := new List<ColumnarLocalFunctionInput>()
                oneLocalFunction.Add(localFunction)
                localCapturePlan := ColumnarLocalFunctionClosurePlanner.Plan(oneLocalFunction, functionSource, parentBindings, enclosingNames)
                localCaptureNamesList := new List<string>()
                for captureName in localCapturePlan.CaptureNames {
                    localCaptureNamesList.Add(captureName)
                    context.AsyncLocalFunctionCaptureNames.Add(captureName)
                }
                localCaptureNames := localCaptureNamesList.ToArray()
                localReceiverField: FieldInfo? = null
                if bodyFacts != null && bodyFacts.EnclosingTypeDefinition != null {
                    receiverFieldIndex := 0
                    while receiverFieldIndex < shape.FieldNames.Length && shape.FieldNames[receiverFieldIndex] != "<>__this" {
                        receiverFieldIndex += 1
                    }
                    if receiverFieldIndex < definitionFields.Length {
                        localReceiverField = definitionFields[receiverFieldIndex]
                    }
                }
                System.Array.Sort(localCaptureNames, StringComparer.Ordinal)
                childOrdinal := funcOrdinal * 1000 + localFunctionOrdinal + 1
                asyncLocalRequests.Add(new ColumnarAsyncLocalFunctionRequest(
                    localFn,
                    childOrdinal,
                    localMethod,
                    localInner,
                    localWrapped,
                    localCaptureNames,
                    localReceiverField
                ))
                localFunctionOrdinal += 1
            }
        }
        moveNextPlan := ColumnarIteratorBodyPlanner.BuildAsyncMoveNextCorePlan(context)
        if context.Declined {
            return Declined(context.DeclineSite, context.DeclineMessage + " in '" + fn.Name + "'", fn.Name)
        }
        for request in asyncLocalRequests {
            localBoxFields := new FieldInfo[](request.CaptureNames.Length)
            captureIndex := 0
            while captureIndex < request.CaptureNames.Length {
                captureName := request.CaptureNames[captureIndex]
                let capture: (BoxField: FieldInfo, ValueType: Type) = (null, null)
                if !context.AsyncCaptureBoxes.TryGetValue(captureName, out capture) || capture.BoxField == null {
                    return Declined("emit.async.local-function.capture", "captured binding '" + captureName + "' has no shared field in local function '" + request.Function.Name + "'", request.Function.Name)
                }
                localBoxFields[captureIndex] = capture.BoxField
                captureIndex += 1
            }
            childResult := EmitTask(
                module,
                request.Function,
                request.Ordinal,
                functionSource,
                typeResolution,
                request.Kickoff,
                synthesizedTypes,
                bodyFacts,
                request.ResultType,
                true,
                shape.TypeName,
                sm,
                enclosingFieldNames,
                enclosingFields,
                enclosingFieldCanonicals,
                true,
                request.WrappedType == typeof(System.Threading.Tasks.Task) || (request.WrappedType.IsGenericType && request.WrappedType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition()),
                defaultUsesTaskBuilder,
                request.KickoffReceiverField == null ? machineType : request.KickoffReceiverField.FieldType,
                request.CaptureNames,
                localBoxFields,
                request.KickoffReceiverField,
                true
            )
            if !childResult.Succeeded {
                return childResult
            }
        }
        asyncLambdaResult := EmitAsyncLambdaRequests(module, funcOrdinal, functionSource, typeResolution, synthesizedTypes, bodyFacts, context)
        if !asyncLambdaResult.Succeeded {
            return asyncLambdaResult
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
            if kickoffReceiverField != null {
                kickoffIl.Emit(OpCodes.Ldfld, kickoffReceiverField)
            } else if receiverIsValueType {
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
        if builderTypeUsesTypeBuilderParameter && builderBridges != null {
            startBuilder = builderBridges.Start.MakeGenericMethod([resultType, kickoffMachineType])
        } else {
            startOwner := builderTypeUsesTypeBuilderParameter ? builderDefinition : kickoffBuilderType
            for candidate in startOwner.GetMethods(BindingFlags.Public | BindingFlags.Instance) {
                if candidate.Name == "Start" && candidate.IsGenericMethodDefinition && candidate.GetGenericArguments().Length == 1 && candidate.GetParameters().Length == 1 {
                    mappedStart := builderTypeUsesTypeBuilderParameter ? AsyncBuilderMethodOnType(kickoffBuilderType, candidate) : candidate
                    startBuilder = mappedStart.MakeGenericMethod([kickoffMachineType])
                    break
                }
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

    // Lambdas discovered in a state-machine body already have their delegate kickoff methods and
    // capture displays. Realize each lambda with the same async task-machine path as a source method.
    static func EmitAsyncLambdaRequests(
        module: ModuleBuilder,
        parentOrdinal: int,
        functionSource: string,
        typeResolution: ColumnarSemanticTypeResolution,
        synthesizedTypes: List<TypeBuilder>,
        bodyFacts: ColumnarIteratorBodyFacts?,
        context: ColumnarIteratorEmitContext
    ): ColumnarIteratorRealizationResult {
        if context == null || context.AsyncLambdaRequests.Count == 0 {
            return Completed()
        }
        for request in context.AsyncLambdaRequests {
            resultCanonical := "void"
            if request.ResultType != ColumnarTypeOfPlanner.RequiredVoidType() && !ColumnarIteratorPlanner.TryBuildRuntimeTypeCanonical(typeResolution, request.ResultType, out resultCanonical) {
                return Declined("emit.async.lambda-result-type", "the result type of async lambda at source node " + request.Node.ToString() + " cannot be represented in its state machine", request.Kickoff.Name)
            }
            parameterCanonicals := new string[](request.ParameterTypes.Length)
            parameterIndex := 0
            while parameterIndex < request.ParameterTypes.Length {
                parameterCanonical := ""
                if !ColumnarIteratorPlanner.TryBuildRuntimeTypeCanonical(typeResolution, request.ParameterTypes[parameterIndex], out parameterCanonical) {
                    return Declined("emit.async.lambda-parameter-type", "parameter '" + request.ParameterNames[parameterIndex] + "' of async lambda '" + request.Kickoff.Name + "' cannot be represented in its state machine", request.Kickoff.Name)
                }
                parameterCanonicals[parameterIndex] = parameterCanonical
                parameterIndex += 1
            }
            receiverCanonical := ""
            lambdaReceiverType: Type = request.OwnerType
            if request.KickoffReceiverField != null {
                lambdaReceiverType = request.KickoffReceiverField.FieldType
            }
            if !ColumnarIteratorPlanner.TryBuildRuntimeTypeCanonical(typeResolution, lambdaReceiverType, out receiverCanonical) {
                return Declined("emit.async.lambda-owner-type", "the closure type for async lambda '" + request.Kickoff.Name + "' cannot be represented in its state machine", request.Kickoff.Name)
            }
            fn := new ColumnarFunctionInput(
                request.Kickoff.Name,
                resultCanonical,
                request.ParameterNames,
                parameterCanonicals,
                context.Nodes,
                request.BodyNode,
                false,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                true,
                0,
                context.SourceFileId
            )
            wrappedType := request.WrappedType
            usesTaskBuilder := wrappedType == typeof(System.Threading.Tasks.Task) || (wrappedType.IsGenericType && wrappedType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition())
            lambdaOrdinal := parentOrdinal * 100000 + request.Ordinal + 1
            result := EmitTask(
                module,
                fn,
                lambdaOrdinal,
                functionSource,
                typeResolution,
                request.Kickoff,
                synthesizedTypes,
                bodyFacts,
                request.ResultType,
                true,
                receiverCanonical,
                request.OwnerType,
                request.EnclosingFieldNames,
                request.EnclosingFields,
                new string[](0),
                request.OwnerIsValueType,
                usesTaskBuilder,
                usesTaskBuilder,
                lambdaReceiverType,
                request.AsyncClosureBoxNames,
                request.AsyncClosureBoxFields,
                request.KickoffReceiverField,
                false
            )
            if !result.Succeeded {
                return result
            }
        }
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
        if canonical == "void" {
            inner = ColumnarTypeOfPlanner.RequiredVoidType()
            wrapped = defaultUsesTaskBuilder ? typeof(System.Threading.Tasks.Task) : typeof(System.Threading.Tasks.ValueTask)
            return true
        }
        if canonical.StartsWith("Task<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !TryResolveIteratorCanonical(canonical.Substring(5, canonical.Length - 6), typeParameters, typeResolution, out inner) || inner == null {
                return false
            }
            wrapped = typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition().MakeGenericType([inner])
            return true
        }
        if canonical.StartsWith("ValueTask<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            if !TryResolveIteratorCanonical(canonical.Substring(10, canonical.Length - 11), typeParameters, typeResolution, out inner) || inner == null {
                return false
            }
            wrapped = typeof(System.Threading.Tasks.ValueTask<int>).GetGenericTypeDefinition().MakeGenericType([inner])
            return true
        }
        if !TryResolveIteratorCanonical(canonical, typeParameters, typeResolution, out inner) || inner == null {
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
        asyncLambdaResult := EmitAsyncLambdaRequests(module, funcOrdinal, functionSource, typeResolution, synthesizedTypes, bodyFacts, context)
        if !asyncLambdaResult.Succeeded {
            return asyncLambdaResult
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
            ) && (resolvedType.IsGenericParameter || (ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(resolvedType) && ColumnarEmitReflectionFacts.RequiredElementType(resolvedType.GetElementType(), "array element type in iterator parameter analysis").IsGenericParameter) || ColumnarTypeOfPlanner.IsSupportedType(resolvedType) || IsOpenDelegateFieldType(resolvedType)) && !ContainsMethodVarReference(resolvedType, smTypeParamMap)
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

    // A constructed BCL delegate can contain the generic parameters of the enclosing method or
    // declaring type. Reflection.Emit may report that constructed shape as a generic definition,
    // even though its definition is the closed BCL delegate family (for example Func<,>). It is
    // still a reference-type field signature and is legal in the async machine.
    static func IsOpenDelegateFieldType(candidate: Type): bool {
        if candidate == null || candidate.IsByRef || candidate.IsPointer || !candidate.IsGenericType {
            return false
        }
        definition := candidate.GetGenericTypeDefinition()
        if Object.ReferenceEquals(candidate, definition) || definition is TypeBuilder || !typeof(Delegate).IsAssignableFrom(definition) {
            return false
        }
        return true
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
