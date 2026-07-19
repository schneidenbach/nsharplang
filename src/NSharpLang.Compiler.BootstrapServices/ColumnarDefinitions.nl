namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

class ColumnarEnumDef {
    enumTypeValue: Type
    constantsValue: Dictionary<string, int>
    stringConstantsValue: Dictionary<string, string>?
    declaredTypeNameValue: string

    EnumType: Type => enumTypeValue
    Constants: Dictionary<string, int> => constantsValue
    StringConstants: Dictionary<string, string>? => stringConstantsValue
    IsStringBacked: bool => stringConstantsValue != null
    DeclaredTypeName: string => declaredTypeNameValue

    constructor(enumType: Type, constants: Dictionary<string, int>, stringConstants: Dictionary<string, string>? = null, declaredTypeName: string = "") {
        if enumType == null || constants == null || declaredTypeName == null {
            throw new InvalidOperationException(
                "Source enum definition facts cannot be null.")
        }
        enumTypeValue = enumType
        constantsValue = constants
        stringConstantsValue = stringConstants
        declaredTypeNameValue = declaredTypeName
    }
}

class ColumnarUnionDef {
    Base: TypeBuilder
    DeclaredTypeName: string
    Cases: Dictionary<string, ColumnarUnionCaseDef>
    TypeParamCount: int
    IsValueStruct: bool
    TagGetter: MethodInfo?

    constructor(baseBuilder: TypeBuilder, typeParamCount: int = 0, declaredTypeName: string = "") {
        if baseBuilder == null || declaredTypeName == null {
            throw new InvalidOperationException(
                "Source union definition facts cannot be null.")
        }
        Base = baseBuilder
        DeclaredTypeName = declaredTypeName
        Cases = new Dictionary<string, ColumnarUnionCaseDef>(StringComparer.Ordinal)
        TypeParamCount = typeParamCount
        IsValueStruct = false
    }
}

class ColumnarUnionCaseDef {
    CaseType: TypeBuilder
    Ctor: ConstructorBuilder
    FieldOrder: string[]
    Fields: Dictionary<string, FieldBuilder>
    UnionBase: TypeBuilder
    IsValueStruct: bool
    ValueStructTag: int
    ValueStructFactory: MethodInfo?
    ValueStructTagGetter: MethodInfo?

    constructor(caseType: TypeBuilder, ctor: ConstructorBuilder, fieldOrder: string[], fields: Dictionary<string, FieldBuilder>, unionBase: TypeBuilder) {
        CaseType = caseType
        Ctor = ctor
        FieldOrder = fieldOrder
        Fields = fields
        UnionBase = unionBase
        IsValueStruct = false
        ValueStructTag = 0
    }
}

// Named metadata rows keep the source-type model readable to both N# and its temporary
// C# assembly owner. N# tuple element names are source-only today, so public tuple fields
// would otherwise surface to C# as Item1/Item2/Item3.
class ColumnarInstanceMethodDef {
    Builder: MethodBuilder
    ParamTypes: Type[]
    ParamModifierKinds: int[]
    ReturnType: Type

    constructor(builder: MethodBuilder, paramTypes: Type[], returnType: Type) {
        if builder == null || paramTypes == null || returnType == null {
            throw new InvalidOperationException("Source instance-method definition facts cannot be null.")
        }

        Builder = builder
        ParamTypes = paramTypes
        ParamModifierKinds = new int[](0)
        ReturnType = returnType
    }

    constructor(builder: MethodBuilder, paramTypes: Type[], paramModifierKinds: int[], returnType: Type) {
        if builder == null || paramTypes == null || paramModifierKinds == null || returnType == null {
            throw new InvalidOperationException("Source instance-method definition facts cannot be null.")
        }

        if paramModifierKinds.Length != 0 && paramModifierKinds.Length != paramTypes.Length {
            throw new InvalidOperationException("Source instance-method modifier facts must be empty or match the parameter count.")
        }

        Builder = builder
        ParamTypes = paramTypes
        ParamModifierKinds = paramModifierKinds
        ReturnType = returnType
    }

    func Deconstruct(out builder: MethodBuilder, out paramTypes: Type[], out returnType: Type) {
        builder = Builder
        paramTypes = ParamTypes
        returnType = ReturnType
    }

    func Deconstruct(out builder: MethodBuilder, out paramTypes: Type[], out paramModifierKinds: int[], out returnType: Type) {
        builder = Builder
        paramTypes = ParamTypes
        paramModifierKinds = ParamModifierKinds
        returnType = ReturnType
    }
}

class ColumnarStaticMethodDef {
    Builder: MethodBuilder
    ParamTypes: Type[]
    ParamModifierKinds: int[]
    ReturnType: Type

    constructor(builder: MethodBuilder, paramTypes: Type[], paramModifierKinds: int[], returnType: Type) {
        Builder = builder
        ParamTypes = paramTypes
        ParamModifierKinds = paramModifierKinds
        ReturnType = returnType
    }

    func Deconstruct(out builder: MethodBuilder, out paramTypes: Type[], out paramModifierKinds: int[], out returnType: Type) {
        builder = Builder
        paramTypes = ParamTypes
        paramModifierKinds = ParamModifierKinds
        returnType = ReturnType
    }
}

// Top-level sibling functions compile to public static methods on the program/module type. The
// mechanical host carries their exact selected signature (parameter types, return type) and the
// param-modifier and generic-arity facts here, because a MethodBuilder does not expose
// GetParameters()/ReturnType before its owner is baked. N# alone decides which siblings a direct
// call may plan; the host only routes these facts.
class ColumnarSiblingCallFacts {
    Method: MethodInfo
    ParameterTypes: Type[]
    ParameterModifierKinds: int[]
    ReturnType: Type
    TypeParameterCount: int

    constructor(method: MethodInfo, parameterTypes: Type[], parameterModifierKinds: int[], returnType: Type, typeParameterCount: int) {
        if method == null || parameterTypes == null || parameterModifierKinds == null || returnType == null {
            throw new InvalidOperationException("Sibling call definition facts cannot be null.")
        }

        Method = method
        ParameterTypes = parameterTypes
        ParameterModifierKinds = parameterModifierKinds
        ReturnType = returnType
        TypeParameterCount = typeParameterCount
    }
}

class ColumnarPropertyDefinitionToken {
}

class ColumnarPropertyDef {
    Getter: MethodBuilder
    Setter: MethodBuilder?
    PropertyType: Type
    GetterParameterCount: int
    SetterParameterCount: int

    constructor(getter: MethodBuilder, setter: MethodBuilder?, propertyType: Type, token: ColumnarPropertyDefinitionToken) {
        if getter == null || propertyType == null || token == null {
            throw new InvalidOperationException("Source property definition facts cannot be null.")
        }

        Getter = getter
        Setter = setter
        PropertyType = propertyType
        GetterParameterCount = 0
        SetterParameterCount = setter == null ? 0 : 1
    }

    // Define the accessors and their signature fact atomically. A ColumnarPropertyDef cannot
    // wrap an arbitrary MethodBuilder: the only construction route creates a zero-parameter
    // getter and, when present, a one-parameter setter itself.
    static func Define(owner: TypeBuilder, getterName: string, getterAttributes: MethodAttributes, propertyType: Type, setterName: string?, setterAttributes: MethodAttributes): ColumnarPropertyDef {
        if owner == null || getterName == null || propertyType == null {
            throw new InvalidOperationException("Source property definition inputs cannot be null.")
        }

        // Accessor identity is part of the property fact, not an optional caller convention.
        // In particular, schema-v3 permits a residual void call only for a genuine setter; stamp
        // SpecialName here so every accessor created through this atomic factory carries the CLR
        // invariant even when a synthetic fixture supplies only its visibility flags.
        // ECMA-335 MethodAttributes.SpecialName is the stable 0x0800 metadata bit.
        specialNameFlag := 0x0800
        exactGetterAttributes := (MethodAttributes)(
            (int)getterAttributes | specialNameFlag)
        getterParameters := new Type[](0)
        getter := owner.DefineMethod(
            getterName, exactGetterAttributes, propertyType, getterParameters)

        setter: MethodBuilder? = null
        if setterName != null {
            voidType := Type.GetType("System.Void")
            if voidType == null {
                throw new InvalidOperationException("System.Void runtime type was not found.")
            }

            setterParameters := new Type[](1)
            setterParameters[0] = propertyType
            exactSetterAttributes := (MethodAttributes)(
                (int)setterAttributes | specialNameFlag)
            setter = owner.DefineMethod(
                setterName, exactSetterAttributes, voidType, setterParameters)
        }

        return new ColumnarPropertyDef(getter, setter, propertyType, new ColumnarPropertyDefinitionToken())
    }
}

class ColumnarConstructorDef {
    Builder: ConstructorBuilder
    ParamTypes: Type[]
    DefaultKinds: int[]
    DefaultTexts: string[]

    constructor(builder: ConstructorBuilder, paramTypes: Type[], defaultKinds: int[], defaultTexts: string[]) {
        Builder = builder
        ParamTypes = paramTypes
        DefaultKinds = defaultKinds
        DefaultTexts = defaultTexts
    }

    func Deconstruct(out builder: ConstructorBuilder, out paramTypes: Type[], out defaultKinds: int[], out defaultTexts: string[]) {
        builder = Builder
        paramTypes = ParamTypes
        defaultKinds = DefaultKinds
        defaultTexts = DefaultTexts
    }
}

// Enum-member defaults are declaration facts. Bind source enum identity before constructor
// facts are registered so callers can never reinterpret an omitted argument through their own
// imports. Runtime enum reflection remains a mechanical host concern; this binder claims only
// source enum owners or source enum parameter types.
class ColumnarConstructorDefaultBinder {
    public static func TryCanonicalizeSourceEnumMember(
        parameterType: Type,
        defaultText: string,
        owner: ColumnarEnumDef?,
        parameter: ColumnarEnumDef?,
        out canonicalText: string,
        out claimed: bool): bool {
        canonicalText = defaultText
        claimed = false
        if parameterType == null
            || defaultText == null {
            return false
        }

        separator := defaultText.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= defaultText.Length {
            return false
        }
        memberName := defaultText.Substring(separator + 1)

        if owner == null && parameter == null {
            return false
        }

        claimed = true
        if owner == null
            || parameter == null
            || !Object.ReferenceEquals(owner, parameter)
            || !Object.ReferenceEquals(owner.EnumType, parameterType)
            || owner.DeclaredTypeName.Length == 0 {
            return false
        }
        if owner.IsStringBacked {
            if owner.StringConstants == null
                || !owner.StringConstants.ContainsKey(memberName) {
                return false
            }
        } else if !owner.Constants.ContainsKey(memberName) {
            return false
        }

        canonicalText = owner.DeclaredTypeName + "." + memberName
        return true
    }

    public static func TryCanonicalizeDefaults(
        parameterTypes: Type[],
        parameterCanonicals: string[],
        defaultKinds: int[],
        defaultTexts: string[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        out canonicalDefaultTexts: string[]): bool {
        canonicalDefaultTexts = new string[](0)
        if defaultKinds.Length == 0 && defaultTexts.Length == 0 {
            return true
        }
        if parameterCanonicals.Length != parameterTypes.Length
            || defaultKinds.Length != parameterTypes.Length
            || defaultTexts.Length != parameterTypes.Length {
            return false
        }

        canonicalDefaultTexts = new string[](parameterTypes.Length)
        index := 0
        while index < parameterTypes.Length {
            defaultText := defaultTexts[index]
            if defaultText == null {
                return false
            }
            if defaultKinds[index] != 1000 {
                canonicalDefaultTexts[index] = defaultText
                index += 1
                continue
            }

            separator := defaultText.LastIndexOf(".", StringComparison.Ordinal)
            if separator <= 0 || separator + 1 >= defaultText.Length {
                return false
            }
            ownerName := defaultText.Substring(0, separator)
            memberName := defaultText.Substring(separator + 1)
            sourceOwner: ColumnarEnumDef? = null
            sourceParameter: ColumnarEnumDef? = null
            enumRegistry.TryGetValue(ownerName, out sourceOwner)
            enumRegistry.TryGetValue(
                parameterCanonicals[index], out sourceParameter)
            sourceCanonical := ""
            sourceClaimed := false
            if TryCanonicalizeSourceEnumMember(
                    parameterTypes[index],
                    defaultText,
                    sourceOwner,
                    sourceParameter,
                    out sourceCanonical,
                    out sourceClaimed) {
                canonicalDefaultTexts[index] = sourceCanonical
                index += 1
                continue
            }
            if sourceClaimed {
                return false
            }

            runtimeEnum := typeof(object)
            runtimeClaimed := false
            if !enumRegistry.Resolver.TryResolve(
                    ownerName, out runtimeEnum, out runtimeClaimed)
                || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    runtimeEnum, parameterTypes[index])
                || runtimeEnum is TypeBuilder
                || runtimeEnum is EnumBuilder
                || !runtimeEnum.get_IsEnum()
                || Enum.GetUnderlyingType(runtimeEnum).FullName
                    != "System.Int32"
                || !Enum.IsDefined(runtimeEnum, memberName) {
                return false
            }
            fullName := runtimeEnum.FullName
            if fullName == null || fullName.Length == 0 {
                return false
            }
            canonicalDefaultTexts[index] = fullName + "." + memberName
            index += 1
        }
        return true
    }
}

// Live source-type metadata is N#-owned so expression planners can select exact unbaked
// FieldBuilder/MethodBuilder handles without a C# lookup bridge.
class ColumnarStructDef {
    Builder: TypeBuilder
    DeclaredTypeName: string
    FieldOrder: string[]
    Fields: Dictionary<string, FieldBuilder>
    NullableFields: HashSet<string>
    GenericParameters: Dictionary<string, Type>?
    IsReference: bool
    IsClosureDisplay: bool
    IsRecord: bool
    IsNewtype: bool
    IsInterface: bool
    InterfaceBases: List<ColumnarStructDef>
    ImplementedInterfaces: List<ColumnarStructDef>
    ImplementedInterfaceTypes: List<Type>
    ExternalInterfaces: List<Type>
    DefaultInterfaceMethodNames: HashSet<string>
    DefaultCtor: ConstructorBuilder?
    BaseDef: ColumnarStructDef?
    ExactBaseType: Type?
    Methods: Dictionary<string, ColumnarInstanceMethodDef>
    MethodOverloads: Dictionary<string, List<ColumnarInstanceMethodDef>>
    StaticMethods: Dictionary<string, List<ColumnarStaticMethodDef>>
    StaticFields: Dictionary<string, FieldBuilder>
    StaticProperties: Dictionary<string, ColumnarPropertyDef>
    Constructors: List<ColumnarConstructorDef>
    InstanceInitializerMethod: MethodBuilder?
    InstanceInitializerFields: HashSet<string>
    Properties: Dictionary<string, ColumnarPropertyDef>
    RecordEquals: MethodBuilder?
    RecordGetHashCode: MethodBuilder?
    RecordClone: MethodBuilder?

    constructor(builder: TypeBuilder, fieldOrder: string[], fields: Dictionary<string, FieldBuilder>, isReference: bool, isRecord: bool = false, isClosureDisplay: bool = false, declaredTypeName: string = "") {
        if builder == null || fieldOrder == null || fields == null || declaredTypeName == null {
            throw new InvalidOperationException("Columnar source-type metadata cannot be null.")
        }

        Builder = builder
        DeclaredTypeName = declaredTypeName
        FieldOrder = fieldOrder
        Fields = fields
        NullableFields = new HashSet<string>(StringComparer.Ordinal)
        IsReference = isReference
        IsClosureDisplay = isClosureDisplay
        IsRecord = isRecord
        IsNewtype = false
        IsInterface = false
        InterfaceBases = new List<ColumnarStructDef>()
        ImplementedInterfaces = new List<ColumnarStructDef>()
        ImplementedInterfaceTypes = new List<Type>()
        ExternalInterfaces = new List<Type>()
        DefaultInterfaceMethodNames = new HashSet<string>(StringComparer.Ordinal)
        Methods = new Dictionary<string, ColumnarInstanceMethodDef>(StringComparer.Ordinal)
        MethodOverloads = new Dictionary<string, List<ColumnarInstanceMethodDef>>(StringComparer.Ordinal)
        StaticMethods = new Dictionary<string, List<ColumnarStaticMethodDef>>(StringComparer.Ordinal)
        StaticFields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal)
        StaticProperties = new Dictionary<string, ColumnarPropertyDef>(StringComparer.Ordinal)
        Constructors = new List<ColumnarConstructorDef>()
        InstanceInitializerFields = new HashSet<string>(StringComparer.Ordinal)
        Properties = new Dictionary<string, ColumnarPropertyDef>(StringComparer.Ordinal)
        ExactBaseType = null
    }

    // Define the exact user-constructor handle and its planner-visible signature as one N#
    // operation. The temporary C# assembly owner may attach parameter metadata and emit the body,
    // but it cannot construct or partially register semantic constructor facts.
    func DefineUserConstructor(
        parameterTypes: Type[],
        defaultKinds: int[],
        defaultTexts: string[]): ConstructorBuilder {
        if parameterTypes == null || defaultKinds == null || defaultTexts == null {
            throw new InvalidOperationException(
                "Source constructor definition facts cannot be null.")
        }

        exactParameterTypes := new Type[](parameterTypes.Length)
        exactDefaultKinds := new int[](parameterTypes.Length)
        exactDefaultTexts := new string[](parameterTypes.Length)
        hasExplicitDefaultColumns := defaultKinds.Length != 0
            || defaultTexts.Length != 0
        if hasExplicitDefaultColumns
            && (defaultKinds.Length != parameterTypes.Length
                || defaultTexts.Length != parameterTypes.Length) {
            throw new InvalidOperationException(
                "Source constructor default facts must match the parameter count.")
        }

        index := 0
        while index < parameterTypes.Length {
            if parameterTypes[index] == null {
                throw new InvalidOperationException(
                    "Source constructor parameter types cannot contain null values.")
            }
            exactParameterTypes[index] = parameterTypes[index]
            if hasExplicitDefaultColumns {
                if defaultTexts[index] == null {
                    throw new InvalidOperationException(
                        "Source constructor default texts cannot contain null values.")
                }
                exactDefaultKinds[index] = defaultKinds[index]
                exactDefaultTexts[index] = defaultTexts[index]
            } else {
                exactDefaultKinds[index] = -1
                exactDefaultTexts[index] = ""
            }
            index = index + 1
        }

        builder := Builder.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            exactParameterTypes)
        Constructors.Add(new ColumnarConstructorDef(
            builder,
            exactParameterTypes,
            exactDefaultKinds,
            exactDefaultTexts))
        return builder
    }

    func SetFieldOrder(fieldOrder: string[]) {
        if fieldOrder == null {
            throw new InvalidOperationException("Columnar source-type field order cannot be null.")
        }

        FieldOrder = fieldOrder
    }

    // Synthesized record value members enter the same exact source-method registry as user
    // declarations. Defining the MethodBuilder and its signature fact together prevents a later
    // call owner from reconstructing either fact from an unbaked TypeBuilder.
    func DefineSynthesizedRecordEquals(): MethodBuilder {
        if !IsRecord || RecordEquals != null || Methods.ContainsKey("Equals") || MethodOverloads.ContainsKey("Equals") {
            throw new InvalidOperationException("Synthesized record Equals requires one unclaimed record member slot.")
        }

        parameterTypes := new Type[](1)
        parameterTypes[0] = typeof(object)
        method := Builder.DefineMethod("Equals", (MethodAttributes)198, typeof(bool), parameterTypes)
        definition := new ColumnarInstanceMethodDef(method, parameterTypes, new int[](0), typeof(bool))
        overloads := new List<ColumnarInstanceMethodDef>()
        overloads.Add(definition)

        RecordEquals = method
        Methods["Equals"] = definition
        MethodOverloads["Equals"] = overloads
        return method
    }

    func DefineSynthesizedRecordGetHashCode(): MethodBuilder {
        if !IsRecord || RecordGetHashCode != null || Methods.ContainsKey("GetHashCode") || MethodOverloads.ContainsKey("GetHashCode") {
            throw new InvalidOperationException("Synthesized record GetHashCode requires one unclaimed record member slot.")
        }

        parameterTypes := new Type[](0)
        method := Builder.DefineMethod("GetHashCode", (MethodAttributes)198, typeof(int), parameterTypes)
        definition := new ColumnarInstanceMethodDef(method, parameterTypes, new int[](0), typeof(int))
        overloads := new List<ColumnarInstanceMethodDef>()
        overloads.Add(definition)

        RecordGetHashCode = method
        Methods["GetHashCode"] = definition
        MethodOverloads["GetHashCode"] = overloads
        return method
    }
}

// Exact read-only view of the active `this` chain. Production facts wrap the live source
// definitions without copying their mutable declaration maps; native owner tests can instead
// provide baked runtime handles. Lookup and cycle rejection live here as one semantic authority.
class ColumnarCurrentPropertyFact {
    Getter: MethodInfo
    PropertyType: Type
    GetterParameterCount: int

    constructor(getter: MethodInfo, propertyType: Type, getterParameterCount: int) {
        if getter == null || propertyType == null || getterParameterCount < 0 {
            throw new InvalidOperationException("Current-instance property facts cannot be null.")
        }

        Getter = getter
        PropertyType = propertyType
        GetterParameterCount = getterParameterCount
    }
}

class ColumnarCurrentInstanceFacts {
    ExactType: Type
    IsReference: bool
    IsClosureDisplay: bool
    SourceDefinition: ColumnarStructDef?
    Fields: Dictionary<string, FieldInfo>
    Properties: Dictionary<string, ColumnarCurrentPropertyFact>
    BaseFacts: ColumnarCurrentInstanceFacts?

    constructor(exactType: Type, isReference: bool, isClosureDisplay: bool = false) {
        if exactType == null {
            throw new InvalidOperationException("Current-instance exact type cannot be null.")
        }

        ExactType = exactType
        IsReference = isReference
        IsClosureDisplay = isClosureDisplay
        SourceDefinition = null
        Fields = new Dictionary<string, FieldInfo>(StringComparer.Ordinal)
        Properties = new Dictionary<string, ColumnarCurrentPropertyFact>(StringComparer.Ordinal)
    }

    static func FromSourceDefinition(source: ColumnarStructDef): ColumnarCurrentInstanceFacts {
        if source == null {
            throw new InvalidOperationException("Current-instance source definition cannot be null.")
        }

        result := new ColumnarCurrentInstanceFacts(source.Builder, source.IsReference, source.IsClosureDisplay)

        result.SourceDefinition = source
        return result
    }

    static func TryFindField(root: ColumnarCurrentInstanceFacts, name: string, out field: FieldInfo?, out declaringType: Type): bool {
        if root == null || name == null {
            throw new InvalidOperationException("Current-instance field lookup facts cannot be null.")
        }

        if root.SourceDefinition != null {
            ValidateSourceHierarchy(root.SourceDefinition)
            current: ColumnarStructDef? = root.SourceDefinition
            while current != null {
                if current.Fields.ContainsKey(name) {
                    field = AsFieldInfo(current.Fields[name])
                    declaringType = current.Builder
                    return true
                }

                current = current.BaseDef
            }
        } else {
            ValidateRuntimeHierarchy(root)
            currentFacts: ColumnarCurrentInstanceFacts? = root
            while currentFacts != null {
                if currentFacts.SourceDefinition != null {
                    throw new InvalidOperationException("Current-instance runtime facts cannot mix source definitions into their base chain.")
                }

                if currentFacts.Fields.ContainsKey(name) {
                    field = currentFacts.Fields[name]
                    declaringType = currentFacts.ExactType
                    return true
                }

                currentFacts = currentFacts.BaseFacts
            }
        }

        field = null
        declaringType = typeof(object)
        return false
    }

    static func TryFindProperty(root: ColumnarCurrentInstanceFacts, name: string, out getter: MethodInfo?, out propertyType: Type, out declaringType: Type): bool {
        if root == null || name == null {
            throw new InvalidOperationException("Current-instance property lookup facts cannot be null.")
        }

        if root.SourceDefinition != null {
            ValidateSourceHierarchy(root.SourceDefinition)
            current: ColumnarStructDef? = root.SourceDefinition
            while current != null {
                if current.Properties.ContainsKey(name) {
                    property := current.Properties[name]
                    getter = AsMethodInfo(property.Getter)
                    propertyType = property.PropertyType
                    if property.GetterParameterCount != 0 {
                        throw new InvalidOperationException("Source property getter facts must declare zero parameters.")
                    }

                    declaringType = current.Builder
                    return true
                }

                current = current.BaseDef
            }
        } else {
            ValidateRuntimeHierarchy(root)
            currentFacts: ColumnarCurrentInstanceFacts? = root
            while currentFacts != null {
                if currentFacts.SourceDefinition != null {
                    throw new InvalidOperationException("Current-instance runtime facts cannot mix source definitions into their base chain.")
                }

                if currentFacts.Properties.ContainsKey(name) {
                    property := currentFacts.Properties[name]
                    getter = property.Getter
                    propertyType = property.PropertyType
                    if property.GetterParameterCount != 0 {
                        throw new InvalidOperationException("Current-instance property getter facts must declare zero parameters.")
                    }

                    declaringType = currentFacts.ExactType
                    return true
                }

                currentFacts = currentFacts.BaseFacts
            }
        }

        getter = null
        propertyType = typeof(object)
        declaringType = typeof(object)
        return false
    }

    static func ValidateSourceHierarchy(root: ColumnarStructDef) {
        slow: ColumnarStructDef? = root
        fast: ColumnarStructDef? = root
        while fast != null && fast.BaseDef != null {
            if slow != null {
                slow = slow.BaseDef
            }

            next := fast.BaseDef
            if next == null {
                return
            }

            fast = next.BaseDef
            if slow != null && slow == fast {
                throw new InvalidOperationException("Current-instance source hierarchy contains a cycle.")
            }
        }
    }

    static func ValidateRuntimeHierarchy(root: ColumnarCurrentInstanceFacts) {
        slow: ColumnarCurrentInstanceFacts? = root
        fast: ColumnarCurrentInstanceFacts? = root
        while fast != null && fast.BaseFacts != null {
            if slow != null {
                slow = slow.BaseFacts
            }

            next := fast.BaseFacts
            if next == null {
                return
            }

            fast = next.BaseFacts
            if slow != null && slow == fast {
                throw new InvalidOperationException("Current-instance runtime hierarchy contains a cycle.")
            }
        }
    }

    static func AsFieldInfo(value: FieldInfo): FieldInfo {
        return value
    }

    static func AsMethodInfo(value: MethodInfo): MethodInfo {
        return value
    }
}
