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

                            builder := definition.DefineUserConstructor(parameterTypes, ctor.ParamDefaultKinds, canonicalDefaultTexts, ctor.VisibilityModifierFlags, ctor.Body.ParamNames)
                            if ColumnarInitRequiredMemberEmitter.DeclaresRequiredMember(constructorInput) {
                                ColumnarInitRequiredMemberEmitter.ApplyCompilerFeatureRequiredToConstructor(builder)
                            }
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
                            if !ColumnarParameterDefaultEmitter.DefineConstructorParameterMetadataWithAttributes(
                                builder,
                                parameterTypes,
                                ctor.Body.ParamNames,
                                ctor.Body.ParamModifierKinds,
                                ctor.ParamDefaultKinds,
                                canonicalDefaultTexts,
                                typeResolution.Enums,
                                ctor.Body.ParamLabeledCanonicals,
                                ctor.Body.ParameterSourceAttributes,
                                typeResolution,
                                sourceAttributeQueue,
                                PositionalParameterFields(definition, ctor)
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
                        // THE SYNTHESIZED CONSTRUCTOR IS A CONSTRUCTOR TOO. A type whose members are
                        // `required` is constructible only by a compiler that understands the
                        // feature, and the parameterless constructor a caller actually reaches is the
                        // one this arm defines.
                        if ColumnarInitRequiredMemberEmitter.DeclaresRequiredMember(structInput) {
                            synthesizedConstructor := definition.DefaultCtor
                            if synthesizedConstructor != null {
                                ColumnarInitRequiredMemberEmitter.ApplyCompilerFeatureRequiredToConstructor(synthesizedConstructor)
                            }
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

    // THE FIELD EACH POSITIONAL PARAMETER DECLARES, or null where a parameter declares none. Only a
    // PRIMARY constructor's parameter list declares members: `record Options(Summary: bool)` writes one
    // declaration that becomes both a parameter and the field it stores into, so an attribute written
    // there has two rows it could belong to. An explicit `constructor(...)` declares parameters and
    // nothing else, and a parameter of one that happens to share a field's name is still only a
    // parameter — null is returned for the whole list rather than matched by name.
    static func PositionalParameterFields(definition: ColumnarStructDef, ctor: ColumnarConstructorInput): FieldBuilder?[]? {
        if !ctor.IsSynthesizedInitializer {
            return null
        }

        names := ctor.Body.ParamNames
        fields := new FieldBuilder?[](names.Length)
        index := 0
        while index < names.Length {
            declared: FieldBuilder = null
            if definition.Fields.TryGetValue(names[index], out declared) {
                fields[index] = declared
            }

            index = index + 1
        }

        return fields
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

    // The emitted source type is in another assembly, so `public`, `protected` and
    // `protected internal` permit a derived constructor call and the other three levels do not.
    // `ColumnarExternalBaseConstructors` owns that relation, and the walk through the generic
    // definition that a base closed over a source type needs.
    static func ResolveAccessibleExternalParameterlessConstructor(baseType: Type): ConstructorInfo? {
        return ColumnarExternalBaseConstructors.ResolveParameterless(baseType)
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
                // AN EVENT'S BACKING DELEGATE OWES NOTHING EITHER. An event with no subscribers IS
                // null — that is the whole reason `Changed?.Invoke(...)` is the raise idiom — and the
                // storage is written only by the synthesized `add_`/`remove_` accessors, so a
                // constructor that assigned it would be assigning somebody else's private field.
                // AN INIT-ONLY AUTO-PROPERTY'S STORAGE OWES NOTHING EITHER, for the reason the
                // event storage beside it owes nothing: the field is written only by the accessor
                // pair the emitter synthesized, and the whole point of `init` is that the value
                // arrives from an OBJECT INITIALIZER — outside every constructor this rule can see.
                if !assigned.Contains(fieldName) && !currentStruct.AutoPropertyBackingFields.Contains(fieldName) && !currentStruct.NullableFields.Contains(fieldName) && !currentStruct.Events.ContainsKey(fieldName) && IsReferenceTypedField(currentStruct, fieldName) {
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
