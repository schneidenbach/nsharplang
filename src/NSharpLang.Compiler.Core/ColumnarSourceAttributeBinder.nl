namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// ONE CONSTRUCTOR A WRITTEN ATTRIBUTE MIGHT BE CALLING, with the parameter types the blob has to be
// encoded against. A constructor still being BUILT cannot answer `GetParameters()`, so the signature
// travels beside the handle rather than being asked of it.
class ColumnarAttributeConstructorCandidate {
    Constructor: ConstructorInfo
    ParameterTypes: Type[]

    constructor(candidate: ConstructorInfo, parameterTypes: Type[]) {
        Constructor = candidate
        ParameterTypes = parameterTypes
    }
}

// THE DECISION A WRITTEN ATTRIBUTE REDUCES TO: which constructor the CustomAttribute row names, and
// the bytes that row carries.
class ColumnarSourceAttributePlan {
    Constructor: ConstructorInfo
    Blob: byte[]

    constructor(attributeConstructor: ConstructorInfo, blob: byte[]) {
        Constructor = attributeConstructor
        Blob = blob
    }
}

// WHAT A WRITTEN ATTRIBUTE MEANS TO THE EMITTER.
//
// The attribute type resolves through the ORDINARY canonical type resolver — the same door every
// other written type name goes through — so a type declared in this program and a type from a
// referenced assembly are found the same way, and both spellings (`Mark` and `MarkAttribute`) are
// tried in the order the source wrote them.
//
// A TYPE BEING BUILT CANNOT BE ASKED ABOUT ITSELF. `TypeBuilder.GetConstructors` and
// `TypeBuilder.GetFields` throw before `CreateType`, so a source-declared attribute's constructors,
// fields and properties are read from the DEFINITION the emitter is already keeping for it, and only
// a type that came from metadata is asked by reflection. The base chain crosses from one world to
// the other exactly once — a source attribute deriving from an external attribute base reads its
// own members from its definition and its inherited ones by reflection.
//
// OVERLOAD SELECTION IS "WHICH SIGNATURE CAN THIS ARGUMENT LIST BE ENCODED INTO", ASKED OF EVERY
// CANDIDATE OF THE RIGHT ARITY. That is not a shortcut around overload resolution: a custom-attribute
// blob's encoding is decided entirely by the parameter type, so a signature the arguments cannot be
// encoded into is a signature the call could not have meant. Where more than one answers, the LEAST
// `object`-typed signature wins, which is the direction ordinary better-ness runs.
class ColumnarSourceAttributeBinder {
    static func TryPlan(attribute: ColumnarSourceAttributeInput, resolution: ColumnarSemanticTypeResolution, out plan: ColumnarSourceAttributePlan): bool {
        plan = null

        // A PSEUDO-CUSTOM ATTRIBUTE HAS NO BLOB. `MethodImpl` is stored in the method definition
        // row's implementation flags (`ColumnarMethodImplAttributes`), exactly as the C# compiler
        // stores it, and writing it here as well would put a row in the CustomAttribute table that a
        // C#-compiled assembly does not have — visible to every `GetCustomAttributesData()` caller.
        if ColumnarMethodImplAttributes.IsMethodImplAttribute(attribute, resolution) {
            return false
        }

        if !attribute.IsDecodable {
            return false
        }

        attributeType: Type = null
        sourceDefinition: ColumnarStructDef = null
        if !TryResolveAttributeType(attribute.Name, resolution, out attributeType, out sourceDefinition) {
            return false
        }

        positional := new List<ColumnarAttributeArgumentNode>()
        namedArguments := new List<ColumnarAttributeNamedArgument>()
        for argument in attribute.ArgumentSyntax {
            argumentName := argument.Name
            if argumentName == null {
                // A POSITIONAL ARGUMENT AFTER A NAMED ONE is not a call any blob can express — the
                // fixed arguments are positional by construction — so the whole attribute declines
                // rather than silently reordering it.
                if namedArguments.Count > 0 {
                    return false
                }

                positional.Add(argument.Value)
                continue
            }

            memberType: Type = null
            isField := false
            if !TryResolveNamedMember(attributeType, sourceDefinition, resolution, argumentName, out memberType, out isField) {
                return false
            }

            namedArguments.Add(new ColumnarAttributeNamedArgument(argumentName, memberType, isField, argument.Value))
        }

        writer := new ColumnarAttributeBlobWriter(resolution)
        selected: ColumnarSourceAttributePlan = null
        selectedScore := 0
        for candidate in CollectConstructors(attributeType, sourceDefinition) {
            if candidate.ParameterTypes.Length != positional.Count {
                continue
            }

            blob: byte[] = Array.Empty<byte>()
            if !writer.TryWriteBlob(positional, candidate.ParameterTypes, namedArguments, out blob) {
                continue
            }

            score := ObjectParameterCount(candidate.ParameterTypes)
            if selected == null || score < selectedScore {
                selected = new ColumnarSourceAttributePlan(candidate.Constructor, blob)
                selectedScore = score
            }
        }

        if selected == null {
            return false
        }

        plan = selected
        return true
    }

    static func ObjectParameterCount(parameterTypes: Type[]): int {
        count := 0
        index := 0
        while index < parameterTypes.Length {
            if parameterTypes[index].get_FullName() == "System.Object" {
                count = count + 1
            }

            index = index + 1
        }

        return count
    }

    // BOTH SPELLINGS, THE WRITTEN ONE FIRST. `[Mark]` and `[MarkAttribute]` name the same type and the
    // written spelling wins the search, which is the rule the analyzer applies to the same program.
    static func TryResolveAttributeType(attributeName: string, resolution: ColumnarSemanticTypeResolution, out attributeType: Type, out sourceDefinition: ColumnarStructDef): bool {
        attributeType = null
        sourceDefinition = null
        for candidate in AnalyzerAttributeValidator.GetClrAttributeNameCandidates(attributeName) {
            definition: ColumnarStructDef = null
            if resolution.Structs.TryGetValue(candidate, out definition) && definition != null && definition.IsReference && DerivesFromAttribute(definition.Builder) {
                attributeType = definition.Builder
                sourceDefinition = definition
                return true
            }

            resolved: Type = null
            if ColumnarCanonicalTypeResolver.TryResolveType(candidate, resolution.Enums, resolution.Structs, resolution.Unions, out resolved) && resolved != null && DerivesFromAttribute(resolved) {
                attributeType = resolved
                return true
            }
        }

        return false
    }

    // THE BASE CHAIN IS WALKED BY FULL NAME, never by identity, because a type being built and a
    // reference-loaded `System.Attribute` are different `Type` instances for the same type. A chain
    // that loops — which only a malformed program produces — is bounded by its own length rather than
    // trusted to terminate.
    static func DerivesFromAttribute(candidate: Type): bool {
        current: Type = candidate
        depth := 0
        while current != null && depth < 64 {
            if current.get_FullName() == "System.Attribute" {
                return true
            }

            current = current.get_BaseType()
            depth = depth + 1
        }

        return false
    }

    static func CollectConstructors(attributeType: Type, sourceDefinition: ColumnarStructDef): List<ColumnarAttributeConstructorCandidate> {
        candidates := new List<ColumnarAttributeConstructorCandidate>()
        if sourceDefinition != null {
            for declared in sourceDefinition.Constructors {
                candidates.Add(new ColumnarAttributeConstructorCandidate(declared.Builder, declared.ParamTypes))
            }

            defaultConstructor := sourceDefinition.DefaultCtor
            if candidates.Count == 0 && defaultConstructor != null {
                candidates.Add(new ColumnarAttributeConstructorCandidate(defaultConstructor, Array.Empty<Type>()))
            }

            return candidates
        }

        if ColumnarAttributeBlobWriter.IsUnbakedBuilderType(attributeType) {
            return candidates
        }

        for metadataConstructor in attributeType.GetConstructors(BindingFlags.Public | BindingFlags.Instance) {
            parameters := metadataConstructor.GetParameters()
            parameterTypes := new Type[](parameters.Length)
            index := 0
            while index < parameters.Length {
                parameterTypes[index] = parameters[index].get_ParameterType()
                index = index + 1
            }

            candidates.Add(new ColumnarAttributeConstructorCandidate(metadataConstructor, parameterTypes))
        }

        return candidates
    }

    // A NAMED ARGUMENT NAMES SOMETHING THE CLR CAN SET IN METADATA: a settable property or a mutable
    // field, declared by the attribute type or inherited from its base. The search walks the base
    // chain because `[Derived(Reason = "x")]` may be setting a property `Base` declared.
    static func TryResolveNamedMember(attributeType: Type, sourceDefinition: ColumnarStructDef, resolution: ColumnarSemanticTypeResolution, memberName: string, out memberType: Type, out isField: bool): bool {
        memberType = null
        isField = false
        definition: ColumnarStructDef = sourceDefinition
        depth := 0
        while definition != null && depth < 64 {
            property: ColumnarPropertyDef = null
            if definition.Properties.TryGetValue(memberName, out property) && property != null && property.Setter != null {
                memberType = property.PropertyType
                isField = false
                return true
            }

            field: FieldBuilder = null
            if definition.Fields.TryGetValue(memberName, out field) && field != null && field.get_IsPublic() && !field.get_IsInitOnly() && !field.get_IsLiteral() {
                memberType = field.get_FieldType()
                isField = true
                return true
            }

            baseDefinition := definition.BaseDef
            if baseDefinition == null {
                externalBase := definition.ExactBaseType
                if externalBase == null {
                    return false
                }

                return TryResolveMetadataNamedMember(externalBase, memberName, out memberType, out isField)
            }

            definition = baseDefinition
            depth = depth + 1
        }

        if sourceDefinition != null {
            return false
        }

        return TryResolveMetadataNamedMember(attributeType, memberName, out memberType, out isField)
    }

    static func TryResolveMetadataNamedMember(attributeType: Type, memberName: string, out memberType: Type, out isField: bool): bool {
        memberType = null
        isField = false
        if ColumnarAttributeBlobWriter.IsUnbakedBuilderType(attributeType) {
            return false
        }

        instanceFlags := BindingFlags.Public | BindingFlags.Instance
        property := attributeType.GetProperty(memberName, instanceFlags)
        if property != null {
            setter := property.get_SetMethod()
            if setter != null && setter.get_IsPublic() && property.GetIndexParameters().Length == 0 {
                memberType = property.get_PropertyType()
                return true
            }
        }

        field := attributeType.GetField(memberName, instanceFlags)
        if field != null && !field.get_IsInitOnly() && !field.get_IsLiteral() {
            memberType = field.get_FieldType()
            isField = true
            return true
        }

        return false
    }
}

// ONE QUEUED ATTACHMENT. Exactly one of the six targets is set; the kind is the target that is not
// null rather than a separate tag, so a row cannot claim to be a method and carry a type.
class ColumnarSourceAttributeApplication {
    TypeTarget: TypeBuilder?
    MethodTarget: MethodBuilder?
    ParameterTarget: ParameterBuilder?
    FieldTarget: FieldBuilder?
    PropertyTarget: PropertyBuilder?
    ConstructorTarget: ConstructorBuilder?
    Attributes: ColumnarSourceAttributeInput[]
    Resolution: ColumnarSemanticTypeResolution

    constructor(attributes: ColumnarSourceAttributeInput[], resolution: ColumnarSemanticTypeResolution) {
        TypeTarget = null
        MethodTarget = null
        ParameterTarget = null
        FieldTarget = null
        PropertyTarget = null
        ConstructorTarget = null
        Attributes = attributes
        Resolution = resolution
    }
}

// WHY ATTRIBUTE ATTACHMENT IS A PHASE AND NOT A STATEMENT.
//
// An attribute names a CONSTRUCTOR, and a source-declared attribute's constructor is a
// `ConstructorBuilder` that does not exist until the emitter reaches that type's members. The
// declaration order of the source decides nothing: `[Mark] class Target` may be written above
// `class MarkAttribute`, and inside one type the attribute on the type itself is attached before any
// constructor in the program has been defined.
//
// Binding therefore cannot happen where the attribute is met. Every attachment is QUEUED as it is
// met — in the order it is met, which is the order the CustomAttribute rows come out in — and the
// whole queue is bound and written once, after every type, method, constructor, field and property in
// the assembly has been defined and before the first `CreateType`.
class ColumnarSourceAttributeQueue {
    applications: List<ColumnarSourceAttributeApplication>

    constructor() {
        applications = new List<ColumnarSourceAttributeApplication>()
    }

    func TryQueue(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution, out application: ColumnarSourceAttributeApplication): bool {
        application = null
        if attributes == null || attributes.Length == 0 {
            return false
        }

        application = new ColumnarSourceAttributeApplication(attributes, resolution)
        applications.Add(application)
        return true
    }

    func QueueType(target: TypeBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.TypeTarget = target
        }
    }

    func QueueMethod(target: MethodBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.MethodTarget = target
        }
    }

    func QueueParameter(target: ParameterBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.ParameterTarget = target
        }
    }

    func QueueField(target: FieldBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.FieldTarget = target
        }
    }

    // A PROPERTY'S ATTRIBUTES GO ON THE PROPERTY ROW, not on its accessors, because that is where
    // every framework that reads them looks — `PropertyInfo.GetCustomAttributes` is what model
    // binding, serialization and validation ask. `[MethodImpl]` is the one exception and it is not
    // this owner's: a property row has no implementation flags, so it is routed to the accessors by
    // `ColumnarMethodImplAttributes` and refused a blob here.
    func QueueProperty(target: PropertyBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.PropertyTarget = target
        }
    }

    func QueueConstructor(target: ConstructorBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution) {
        application: ColumnarSourceAttributeApplication = null
        if TryQueue(attributes, resolution, out application) {
            application.ConstructorTarget = target
        }
    }

    // AN ATTRIBUTE THAT CANNOT BE BOUND IS NOT WRITTEN, AND THAT IS NOT A SILENT LOSS: the analyzer
    // has already reported the program that produced it — an unknown attribute type, a non-constant
    // argument, a named argument no member accepts — and the build carries that error. The one shape
    // that reaches here bindable-but-unwritten is the pseudo-custom `[MethodImpl]`, which was already
    // written into the method's implementation flags.
    func Flush() {
        for application in applications {
            for attribute in application.Attributes {
                plan: ColumnarSourceAttributePlan = null
                if !ColumnarSourceAttributeBinder.TryPlan(attribute, application.Resolution, out plan) {
                    continue
                }

                typeTarget := application.TypeTarget
                if typeTarget != null {
                    typeTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                    continue
                }

                methodTarget := application.MethodTarget
                if methodTarget != null {
                    methodTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                    continue
                }

                parameterTarget := application.ParameterTarget
                if parameterTarget != null {
                    parameterTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                    continue
                }

                fieldTarget := application.FieldTarget
                if fieldTarget != null {
                    fieldTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                    continue
                }

                propertyTarget := application.PropertyTarget
                if propertyTarget != null {
                    propertyTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                    continue
                }

                constructorTarget := application.ConstructorTarget
                if constructorTarget != null {
                    constructorTarget.SetCustomAttribute(plan.Constructor, plan.Blob)
                }
            }
        }

        applications.Clear()
    }
}
