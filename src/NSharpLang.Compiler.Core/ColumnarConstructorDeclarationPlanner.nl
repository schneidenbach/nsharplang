namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit


// The declaration facts consumed later by the still-C# constructor body lowering. These records
// preserve the old temporary tuple member names and carry the exact live builders and dictionaries
// produced during declaration; the host does not reconstruct any constructor decision from them.
class ColumnarConstructorBodyJob {
    Struct: ColumnarStructDef
    Ctor: ColumnarConstructorInput
    Builder: ConstructorBuilder
    Ordinals: Dictionary<string, int>
    ParamTypes: Dictionary<string, Type>

    constructor(structDefinition: ColumnarStructDef, ctor: ColumnarConstructorInput, builder: ConstructorBuilder, ordinals: Dictionary<string, int>, paramTypes: Dictionary<string, Type>) {
        Struct = structDefinition
        Ctor = ctor
        Builder = builder
        Ordinals = ordinals
        ParamTypes = paramTypes
    }
}

class ColumnarDefaultConstructorJob {
    Struct: ColumnarStructDef
    Builder: ConstructorBuilder

    constructor(structDefinition: ColumnarStructDef, builder: ConstructorBuilder) {
        Struct = structDefinition
        Builder = builder
    }
}

class ColumnarConstructorDeclarationResult {
    Succeeded: bool
    DeclineSite: string
    DeclineMessage: string
    DeclineMember: string
    ObjectConstructor: ConstructorInfo
    ConstructorJobs: List<ColumnarConstructorBodyJob>
    DefaultConstructorJobs: List<ColumnarDefaultConstructorJob>

    constructor(
        succeeded: bool,
        declineSite: string,
        declineMessage: string,
        declineMember: string,
        objectConstructor: ConstructorInfo,
        constructorJobs: List<ColumnarConstructorBodyJob>,
        defaultConstructorJobs: List<ColumnarDefaultConstructorJob>
    ) {
        Succeeded = succeeded
        DeclineSite = declineSite
        DeclineMessage = declineMessage
        DeclineMember = declineMember
        ObjectConstructor = objectConstructor
        ConstructorJobs = constructorJobs
        DefaultConstructorJobs = defaultConstructorJobs
    }
}

// Owns constructor declaration, default-constructor synthesis, constructor validation, and the
// exact base/this-chain instructions. Recursive constructor body and field-initializer expression
// lowering remain in the host; they consume these declarations without re-deciding their shape.
class ColumnarConstructorDeclarationPlanner {
    static func Declare(
        program: ColumnarProgramInput,
        structs: IReadOnlyList<ColumnarStructInput>,
        structDefinitions: ColumnarStructDef[],
        typeResolutions: ColumnarSemanticTypeResolution[],
        structDepths: int[],
        sourceAttributeQueue: ColumnarSourceAttributeQueue
    ): ColumnarConstructorDeclarationResult {
        objectConstructor := typeof(object).GetConstructor(Type.EmptyTypes)
        constructorJobs := new List<ColumnarConstructorBodyJob>()
        defaultConstructorJobs := new List<ColumnarDefaultConstructorJob>()

        structIndex := 0
        while structIndex < structs.Count {
            if structs[structIndex].Constructors.Count != 0 {
                definition := structDefinitions[structIndex]
                typeResolution := typeResolutions[structIndex]
                constructorInput := structs[structIndex]
                constructorInputs := constructorInput.Constructors
                constructorEnumerator := ConstructorInputEnumerator(constructorInputs)
                constructorMovement := constructorEnumerator as IEnumerator
                try {
                    while constructorMovement.MoveNext() {
                        ctor := constructorEnumerator.get_Current()
                        if IsZeroParamSynthesizedInitializer(ctor) {
                            // A VALUE TYPE TAKES THE SAME PLAN. Its declared constructors each run the
                            // stores inline; the values that never reach a constructor (`default(S)`,
                            // an array element) never run them, which is the language rule the
                            // analyzer already enforces (NL329 refuses a struct initializer when the
                            // type declares no constructor at all).
                            ctorSource := program.GetSourceForFileId(ctor.Body.SourceFileId)
                            initPlan := ColumnarFieldInitPlanner.PlanFieldInitialization(ctor.Body, ctorSource, definition)
                            definition.InstanceInitializerPlan = initPlan
                            definition.InstanceInitializerCtor = ctor
                            initializedFieldNames := initPlan.InitializedFieldNames
                            initializedIndex := 0
                            while initializedIndex < initializedFieldNames.Length {
                                definition.InstanceInitializerFields.Add(initializedFieldNames[initializedIndex])
                                initializedIndex += 1
                            }
                        } else {
                            if ctor.ChainInitKind == 2 && definition.BaseDef == null && definition.ExactBaseType == null {
                                return Declined(
                                    "emit.ctor.base-chain-without-base",
                                    "constructor base initializer requires a modeled base class",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }
                            if definition.IsReference && ctor.ChainInitKind == 0 && definition.BaseDef == null && definition.ExactBaseType != null && ResolveAccessibleExternalParameterlessConstructor(definition.ExactBaseType) == null {
                                return Declined(
                                    "emit.ctor.implicit-base-chain",
                                    "constructor requires an accessible base parameterless constructor",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }

                            parameterTypes := new Type[](ctor.Body.ParamNames.Length)
                            ordinals := new Dictionary<string, int>(StringComparer.Ordinal)
                            parameterTypeMap := new Dictionary<string, Type>(StringComparer.Ordinal)
                            parameterIndex := 0
                            while parameterIndex < ctor.Body.ParamNames.Length {
                                parameterType: Type = null
                                if !ColumnarCanonicalTypeResolver.TryResolveMemberType(
                                    ctor.Body.ParamCanonicals[parameterIndex],
                                    definition,
                                    typeResolution.Enums,
                                    typeResolution.Structs,
                                    typeResolution.Unions,
                                    out parameterType
                                ) || !ColumnarInterfaceRealization.IsSupportedParameterType(parameterType) {
                                    return Declined(
                                        "emit.ctor.param-type",
                                        "constructor parameter type is not modeled",
                                        BuilderName(definition) + ".constructor",
                                        objectConstructor,
                                        constructorJobs,
                                        defaultConstructorJobs
                                    )
                                }
                                parameterTypes[parameterIndex] = parameterType
                                ordinals[ctor.Body.ParamNames[parameterIndex]] = parameterIndex + 1
                                parameterTypeMap[ctor.Body.ParamNames[parameterIndex]] = parameterType
                                parameterIndex += 1
                            }

                            canonicalDefaultTexts: string[] = null
                            if !ColumnarConstructorDefaultBinder.TryCanonicalizeDefaults(
                                parameterTypes,
                                ctor.Body.ParamCanonicals,
                                ctor.ParamDefaultKinds,
                                ctor.ParamDefaultTexts,
                                typeResolution.Enums,
                                out canonicalDefaultTexts
                            ) {
                                return Declined(
                                    "emit.ctor.param-default",
                                    "constructor parameter default could not be bound to its exact declaration",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }

                            builder := definition.DefineUserConstructor(parameterTypes, ctor.ParamDefaultKinds, canonicalDefaultTexts, ctor.VisibilityModifierFlags)
                            sourceAttributeQueue.QueueConstructor(builder, ctor.Body.SourceAttributes, typeResolution)
                            if !ColumnarMethodImplAttributes.TryApplyToConstructor(builder, ctor.Body.SourceAttributes, typeResolution) {
                                return Declined(
                                    "emit.methodimpl.options",
                                    "[MethodImpl] needs a compile-time MethodImplOptions value",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }
                            if !ColumnarParameterDefaultEmitter.DefineConstructorParameterMetadataWithTupleNames(
                                builder,
                                parameterTypes,
                                ctor.Body.ParamNames,
                                ctor.Body.ParamModifierKinds,
                                ctor.ParamDefaultKinds,
                                canonicalDefaultTexts,
                                typeResolution.Enums,
                                ctor.Body.ParamLabeledCanonicals
                            ) {
                                return Declined(
                                    "emit.ctor.param-metadata",
                                    "constructor parameter metadata could not be emitted",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }
                            constructorJobs.Add(new ColumnarConstructorBodyJob(definition, ctor, builder, ordinals, parameterTypeMap))
                        }
                    }
                } finally {
                    constructorDisposable := constructorEnumerator as IDisposable
                    if constructorDisposable != null {
                        constructorDisposable.Dispose()
                    }
                }
            }
            structIndex += 1
        }

        depth := 0
        while depth < structs.Count {
            defaultIndex := 0
            while defaultIndex < structs.Count {
                if structDepths[defaultIndex] == depth {
                    structInput := structs[defaultIndex]
                    if structInput.IsReference && !HasCallableConstructor(structInput) {
                        definition := structDefinitions[defaultIndex]
                        hasInlineInitializers := definition.InstanceInitializerPlan != null && definition.InstanceInitializerPlan.InlineOrdinals.Length > 0
                        implicitBaseConstructor := ResolveImplicitBaseConstructor(definition, objectConstructor)
                        if implicitBaseConstructor == null {
                            if definition.BaseDef != null {
                                return Declined(
                                    "emit.ctor.default-base-chain",
                                    "default constructor requires a modeled base parameterless constructor",
                                    BuilderName(definition),
                                    objectConstructor,
                                    constructorJobs,
                                    defaultConstructorJobs
                                )
                            }
                            return Declined(
                                "emit.ctor.default-base-chain",
                                "default constructor requires an accessible external base parameterless constructor",
                                BuilderName(definition),
                                objectConstructor,
                                constructorJobs,
                                defaultConstructorJobs
                            )
                        }
                        if definition.BaseDef == null && !hasInlineInitializers {
                            definition.DefaultCtor = definition.Builder.DefineDefaultConstructor(MethodAttributes.Public)
                        } else {
                            defaultBuilder := definition.Builder.DefineConstructor(
                                MethodAttributes.Public,
                                CallingConventions.Standard,
                                Type.EmptyTypes
                            )
                            definition.DefaultCtor = defaultBuilder
                            defaultConstructorJobs.Add(new ColumnarDefaultConstructorJob(definition, defaultBuilder))
                        }
                    }
                }
                defaultIndex += 1
            }
            depth += 1
        }

        return new ColumnarConstructorDeclarationResult(
            true,
            "",
            "",
            "",
            objectConstructor,
            constructorJobs,
            defaultConstructorJobs
        )
    }

    static func ResolveParameterlessCtor(definition: ColumnarStructDef): ConstructorBuilder? {
        if definition.DefaultCtor != null {
            return definition.DefaultCtor
        }
        constructorEnumerator := definition.Constructors.GetEnumerator()
        try {
            while constructorEnumerator.MoveNext() {
                constructorDefinition := constructorEnumerator.get_Current()
                builder: ConstructorBuilder = null
                parameterTypes: Type[] = null
                defaultKinds: int[] = null
                defaultTexts: string[] = null
                constructorDefinition.Deconstruct(out builder, out parameterTypes, out defaultKinds, out defaultTexts)
                if parameterTypes.Length == 0 {
                    return builder
                }
            }
        } finally {
            constructorEnumerator.Dispose()
        }
        return null
    }

    static func IsZeroParamSynthesizedInitializer(ctor: ColumnarConstructorInput): bool {
        return ctor.IsSynthesizedInitializer && ctor.Body.ParamNames.Length == 0
    }

    static func HasCallableConstructor(structInput: ColumnarStructInput): bool {
        constructorEnumerator := ConstructorInputEnumerator(structInput.Constructors)
        constructorMovement := constructorEnumerator as IEnumerator
        try {
            while constructorMovement.MoveNext() {
                if !IsZeroParamSynthesizedInitializer(constructorEnumerator.get_Current()) {
                    return true
                }
            }
        } finally {
            constructorDisposable := constructorEnumerator as IDisposable
            if constructorDisposable != null {
                constructorDisposable.Dispose()
            }
        }
        return false
    }

    static func ResolveAccessibleExternalParameterlessConstructor(baseType: Type): ConstructorInfo? {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        constructors := baseType.GetConstructors(flags)
        constructorIndex := 0
        while constructorIndex < constructors.Length {
            candidate := constructors[constructorIndex]
            // The emitted source type is in another assembly. Public (6), Family (4), and
            // FamORAssem (5) therefore permit a derived constructor call; Assembly (3),
            // FamANDAssem (2), and Private (1) do not.
            accessAttributes := (int)candidate.get_Attributes() & 7
            if candidate.GetParameters().Length == 0 && (accessAttributes == 6 || accessAttributes == 4 || accessAttributes == 5) {
                return candidate
            }
            constructorIndex += 1
        }
        return null
    }

    // EVERY CONSTRUCTOR OF AN EXTERNAL BASE THIS ASSEMBLY MAY CALL. The emitted type lives in another
    // assembly, so the same three access levels a parameterless base constructor is accepted at are
    // the ones a parameterised one is accepted at.
    static func ResolveAccessibleExternalConstructors(baseType: Type): List<ConstructorInfo> {
        accessible := new List<ConstructorInfo>()
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        constructors := baseType.GetConstructors(flags)
        constructorIndex := 0
        while constructorIndex < constructors.Length {
            candidate := constructors[constructorIndex]
            accessAttributes := (int)candidate.get_Attributes() & 7
            if accessAttributes == 6 || accessAttributes == 4 || accessAttributes == 5 {
                accessible.Add(candidate)
            }

            constructorIndex += 1
        }

        return accessible
    }

    static func ResolveImplicitBaseConstructor(definition: ColumnarStructDef, objectConstructor: ConstructorInfo): ConstructorInfo? {
        if definition.BaseDef != null {
            baseParameterless := ResolveParameterlessCtor(definition.BaseDef)
            if baseParameterless == null {
                return null
            }
            return ResolveExactBaseConstructor(definition, baseParameterless)
        }
        if definition.ExactBaseType != null {
            return ResolveAccessibleExternalParameterlessConstructor(definition.ExactBaseType)
        }
        return objectConstructor
    }

    static func EmitCtorBaseChain(il: ILGenerator, definition: ColumnarStructDef, objectConstructor: ConstructorInfo) {
        if definition.BaseDef != null {
            baseParameterless := ResolveParameterlessCtor(definition.BaseDef)
            if baseParameterless == null {
                throw new InvalidOperationException("base has only parameterized constructors")
            }
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Call, ResolveExactBaseConstructor(definition, baseParameterless))
            return
        }
        baseConstructor: ConstructorInfo? = objectConstructor
        if definition.ExactBaseType != null {
            baseConstructor = ResolveAccessibleExternalParameterlessConstructor(definition.ExactBaseType)
            if baseConstructor == null {
                throw new InvalidOperationException("external base has no accessible parameterless constructor")
            }
        }
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Call, baseConstructor)
    }

    static func ResolveExactBaseConstructor(derived: ColumnarStructDef, openConstructor: ConstructorBuilder): ConstructorInfo {
        exactBaseType := derived.ExactBaseType
        if derived.BaseDef == null || exactBaseType == null {
            return openConstructor
        }
        exactType: Type = exactBaseType
        baseBuilder: Type = derived.BaseDef.Builder
        if Object.ReferenceEquals(exactType, baseBuilder) {
            return openConstructor
        }
        return TypeBuilder.GetConstructor(exactType, openConstructor)
    }

    static func IsValidReferenceCtorBody(nodes: ColumnarNodeTable, source: string, currentStruct: ColumnarStructDef?, bodyRoot: int): bool {
        if currentStruct == null || nodes.Kind(bodyRoot) != 25 || ColumnarMethodBodyPlanner.ContainsValueReturnStatement(nodes, bodyRoot) {
            return false
        }
        assigned := new HashSet<string>(currentStruct.InstanceInitializerFields, StringComparer.Ordinal)
        childIndex := 0
        while childIndex < nodes.ChildCount(bodyRoot) {
            statement := nodes.Child(bodyRoot, childIndex)
            if nodes.Kind(statement) == 23 {
                expression := nodes.Child(statement, 0)
                if nodes.Kind(expression) == 14 && ColumnarNodeTextFacts.Text(nodes, source, expression) == "=" {
                    target := nodes.Child(expression, 0)
                    if nodes.Kind(target) == 6 && currentStruct.Fields.ContainsKey(ColumnarNodeTextFacts.Text(nodes, source, target)) {
                        assigned.Add(ColumnarNodeTextFacts.Text(nodes, source, target))
                    }
                }
            }
            childIndex += 1
        }

        fieldEnumerator := currentStruct.Fields.get_Keys().GetEnumerator()
        try {
            while fieldEnumerator.MoveNext() {
                fieldName := fieldEnumerator.get_Current()
                // ONLY A NON-NULLABLE REFERENCE-TYPED FIELD OWES THE CONSTRUCTOR AN ASSIGNMENT — the mirror
                // of `AnalyzerDefiniteAssignment.CheckConstructorFields`. Every value type's `default` is a
                // valid value the CLR has already written, so a `bool`, an `int`, an enum, a struct and a
                // type-parameter field are all definitely assigned before the body runs.
                if !assigned.Contains(fieldName) && !currentStruct.NullableFields.Contains(fieldName) && IsReferenceTypedField(currentStruct, fieldName) {
                    return false
                }
            }
        } finally {
            fieldEnumerator.Dispose()
        }
        return true
    }

    // Whether a declared field's CLR type is a reference type. A type parameter is NOT one: an
    // unconstrained `T` can be instantiated with a struct, and C# asks nothing of such a field either.
    static func IsReferenceTypedField(currentStruct: ColumnarStructDef, fieldName: string): bool {
        let field: System.Reflection.Emit.FieldBuilder? = null
        if !currentStruct.Fields.TryGetValue(fieldName, out field) {
            return true
        }

        fieldType: Type = field.get_FieldType()
        if fieldType.get_IsGenericParameter() {
            return false
        }

        return !fieldType.get_IsValueType()
    }

    static func ConstructorInputEnumerator(constructors: IEnumerable<ColumnarConstructorInput>): IEnumerator<ColumnarConstructorInput> {
        return constructors.GetEnumerator()
    }

    static func BuilderName(definition: ColumnarStructDef): string {
        builder: Type = definition.Builder
        return builder.get_Name()
    }

    static func Declined(
        site: string,
        message: string,
        member: string,
        objectConstructor: ConstructorInfo,
        constructorJobs: List<ColumnarConstructorBodyJob>,
        defaultConstructorJobs: List<ColumnarDefaultConstructorJob>
    ): ColumnarConstructorDeclarationResult {
        ColumnarDeclineTrace.Record(site, message, -1, 0, member)
        return new ColumnarConstructorDeclarationResult(
            false,
            site,
            message,
            member,
            objectConstructor,
            constructorJobs,
            defaultConstructorJobs
        )
    }
}
