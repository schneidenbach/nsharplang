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

class ColumnarInstanceInitializerJob {
    Struct: ColumnarStructDef
    Ctor: ColumnarConstructorInput
    Builder: MethodBuilder

    constructor(structDefinition: ColumnarStructDef, ctor: ColumnarConstructorInput, builder: MethodBuilder) {
        Struct = structDefinition
        Ctor = ctor
        Builder = builder
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
    InitializerJobs: List<ColumnarInstanceInitializerJob>
    DefaultConstructorJobs: List<ColumnarDefaultConstructorJob>

    constructor(
        succeeded: bool,
        declineSite: string,
        declineMessage: string,
        declineMember: string,
        objectConstructor: ConstructorInfo,
        constructorJobs: List<ColumnarConstructorBodyJob>,
        initializerJobs: List<ColumnarInstanceInitializerJob>,
        defaultConstructorJobs: List<ColumnarDefaultConstructorJob>
    ) {
        Succeeded = succeeded
        DeclineSite = declineSite
        DeclineMessage = declineMessage
        DeclineMember = declineMember
        ObjectConstructor = objectConstructor
        ConstructorJobs = constructorJobs
        InitializerJobs = initializerJobs
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
        structDepths: int[]
    ): ColumnarConstructorDeclarationResult {
        objectConstructor := typeof(object).GetConstructor(Type.EmptyTypes)
        constructorJobs := new List<ColumnarConstructorBodyJob>()
        initializerJobs := new List<ColumnarInstanceInitializerJob>()
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
                            if !definition.IsReference {
                                return Declined(
                                    "emit.ctor.instance-initializer-value-type",
                                    "instance field initializer constructor is only modeled for reference types",
                                    BuilderName(definition),
                                    objectConstructor,
                                    constructorJobs,
                                    initializerJobs,
                                    defaultConstructorJobs
                                )
                            }

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
                            if initPlan.NeedsHelper {
                                initializer := definition.Builder.DefineMethod(
                                    "<InitializeFields>$",
                                    MethodAttributes.Private | MethodAttributes.HideBySig,
                                    ColumnarTypeOfPlanner.RequiredVoidType(),
                                    Type.EmptyTypes
                                )
                                definition.InstanceInitializerMethod = initializer
                                initializerJobs.Add(new ColumnarInstanceInitializerJob(definition, ctor, initializer))
                            }
                        } else {
                            if ctor.ChainInitKind == 2 && definition.BaseDef == null {
                                return Declined(
                                    "emit.ctor.base-chain-without-base",
                                    "constructor base initializer requires a modeled base class",
                                    BuilderName(definition) + ".constructor",
                                    objectConstructor,
                                    constructorJobs,
                                    initializerJobs,
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
                                    initializerJobs,
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
                                        initializerJobs,
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
                                    initializerJobs,
                                    defaultConstructorJobs
                                )
                            }

                            builder := definition.DefineUserConstructor(parameterTypes, ctor.ParamDefaultKinds, canonicalDefaultTexts, ctor.VisibilityModifierFlags)
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
                                    initializerJobs,
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
                                    initializerJobs,
                                    defaultConstructorJobs
                                )
                            }
                            return Declined(
                                "emit.ctor.default-base-chain",
                                "default constructor requires an accessible external base parameterless constructor",
                                BuilderName(definition),
                                objectConstructor,
                                constructorJobs,
                                initializerJobs,
                                defaultConstructorJobs
                            )
                        }
                        if definition.BaseDef == null && definition.InstanceInitializerMethod == null && !hasInlineInitializers {
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
            initializerJobs,
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

    static func EmitInstanceInitializerCall(il: ILGenerator, definition: ColumnarStructDef) {
        if definition.InstanceInitializerMethod == null {
            return
        }
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Call, definition.InstanceInitializerMethod)
    }

    static func IsValidReferenceCtorBody(nodes: ColumnarNodeTable, source: string, currentStruct: ColumnarStructDef?, bodyRoot: int): bool {
        if currentStruct == null || nodes.Kind(bodyRoot) != 25 || ColumnarMethodBodyPlanner.ContainsReturnStatement(nodes, bodyRoot) {
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
                if !assigned.Contains(fieldName) && !currentStruct.NullableFields.Contains(fieldName) {
                    return false
                }
            }
        } finally {
            fieldEnumerator.Dispose()
        }
        return true
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
        initializerJobs: List<ColumnarInstanceInitializerJob>,
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
            initializerJobs,
            defaultConstructorJobs
        )
    }
}
