namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

public class ColumnarEnumDef {
    enumTypeValue: Type
    constantsValue: Dictionary<string, int>
    stringConstantsValue: Dictionary<string, string>?

    EnumType: Type => enumTypeValue
    Constants: Dictionary<string, int> => constantsValue
    StringConstants: Dictionary<string, string>? => stringConstantsValue
    IsStringBacked: bool => stringConstantsValue != null

    constructor(enumType: Type, constants: Dictionary<string, int>, stringConstants: Dictionary<string, string>? = null) {
        enumTypeValue = enumType
        constantsValue = constants
        stringConstantsValue = stringConstants
    }
}

public class ColumnarUnionDef {
    Base: TypeBuilder
    Cases: Dictionary<string, ColumnarUnionCaseDef>
    TypeParamCount: int
    IsValueStruct: bool
    TagGetter: MethodInfo?

    constructor(baseBuilder: TypeBuilder, typeParamCount: int = 0) {
        Base = baseBuilder
        Cases = new Dictionary<string, ColumnarUnionCaseDef>(StringComparer.Ordinal)
        TypeParamCount = typeParamCount
        IsValueStruct = false
    }
}

public class ColumnarUnionCaseDef {
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
public class ColumnarInstanceMethodDef {
    Builder: MethodBuilder
    ParamTypes: Type[]
    ReturnType: Type

    constructor(builder: MethodBuilder, paramTypes: Type[], returnType: Type) {
        Builder = builder
        ParamTypes = paramTypes
        ReturnType = returnType
    }

    public func Deconstruct(out builder: MethodBuilder, out paramTypes: Type[], out returnType: Type) {
        builder = Builder
        paramTypes = ParamTypes
        returnType = ReturnType
    }
}

public class ColumnarStaticMethodDef {
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

    public func Deconstruct(out builder: MethodBuilder, out paramTypes: Type[], out paramModifierKinds: int[], out returnType: Type) {
        builder = Builder
        paramTypes = ParamTypes
        paramModifierKinds = ParamModifierKinds
        returnType = ReturnType
    }
}

class ColumnarPropertyDefinitionToken {}

public class ColumnarPropertyDef {
    Getter: MethodBuilder
    Setter: MethodBuilder?
    PropertyType: Type
    GetterParameterCount: int

    constructor(
        getter: MethodBuilder,
        setter: MethodBuilder?,
        propertyType: Type,
        token: ColumnarPropertyDefinitionToken) {
        if getter == null || propertyType == null || token == null {
            throw new InvalidOperationException(
                "Source property definition facts cannot be null.")
        }
        Getter = getter
        Setter = setter
        PropertyType = propertyType
        GetterParameterCount = 0
    }

    // Define the accessors and their signature fact atomically. A ColumnarPropertyDef cannot
    // wrap an arbitrary MethodBuilder: the only construction route creates a zero-parameter
    // getter and, when present, a one-parameter setter itself.
    public static func Define(
        owner: TypeBuilder,
        getterName: string,
        getterAttributes: MethodAttributes,
        propertyType: Type,
        setterName: string?,
        setterAttributes: MethodAttributes): ColumnarPropertyDef {
        if owner == null || getterName == null || propertyType == null {
            throw new InvalidOperationException(
                "Source property definition inputs cannot be null.")
        }
        getterParameters := new Type[](0)
        getter := owner.DefineMethod(
            getterName, getterAttributes, propertyType, getterParameters)
        setter: MethodBuilder? = null
        if setterName != null {
            voidType := Type.GetType("System.Void")
            if voidType == null {
                throw new InvalidOperationException(
                    "System.Void runtime type was not found.")
            }
            setterParameters := new Type[](1)
            setterParameters[0] = propertyType
            setter = owner.DefineMethod(
                setterName, setterAttributes, voidType, setterParameters)
        }
        return new ColumnarPropertyDef(
            getter,
            setter,
            propertyType,
            new ColumnarPropertyDefinitionToken())
    }

}

public class ColumnarConstructorDef {
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

    public func Deconstruct(out builder: ConstructorBuilder, out paramTypes: Type[], out defaultKinds: int[], out defaultTexts: string[]) {
        builder = Builder
        paramTypes = ParamTypes
        defaultKinds = DefaultKinds
        defaultTexts = DefaultTexts
    }
}

// Live source-type metadata is N#-owned so expression planners can select exact unbaked
// FieldBuilder/MethodBuilder handles without a C# lookup bridge.
public class ColumnarStructDef {
    Builder: TypeBuilder
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

    constructor(
        builder: TypeBuilder,
        fieldOrder: string[],
        fields: Dictionary<string, FieldBuilder>,
        isReference: bool,
        isRecord: bool = false,
        isClosureDisplay: bool = false) {
        if builder == null || fieldOrder == null || fields == null {
            throw new InvalidOperationException("Columnar source-type metadata cannot be null.")
        }
        Builder = builder
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
    }

    public func SetFieldOrder(fieldOrder: string[]) {
        if fieldOrder == null {
            throw new InvalidOperationException("Columnar source-type field order cannot be null.")
        }
        FieldOrder = fieldOrder
    }

}

// Exact read-only view of the active `this` chain. Production facts wrap the live source
// definitions without copying their mutable declaration maps; native owner tests can instead
// provide baked runtime handles. Lookup and cycle rejection live here as one semantic authority.
public class ColumnarCurrentPropertyFact {
    Getter: MethodInfo
    PropertyType: Type
    GetterParameterCount: int

    constructor(
        getter: MethodInfo,
        propertyType: Type,
        getterParameterCount: int) {
        if getter == null || propertyType == null || getterParameterCount < 0 {
            throw new InvalidOperationException(
                "Current-instance property facts cannot be null.")
        }
        Getter = getter
        PropertyType = propertyType
        GetterParameterCount = getterParameterCount
    }
}

public class ColumnarCurrentInstanceFacts {
    ExactType: Type
    IsReference: bool
    IsClosureDisplay: bool
    SourceDefinition: ColumnarStructDef?
    Fields: Dictionary<string, FieldInfo>
    Properties: Dictionary<string, ColumnarCurrentPropertyFact>
    BaseFacts: ColumnarCurrentInstanceFacts?

    constructor(
        exactType: Type,
        isReference: bool,
        isClosureDisplay: bool = false) {
        if exactType == null {
            throw new InvalidOperationException(
                "Current-instance exact type cannot be null.")
        }
        ExactType = exactType
        IsReference = isReference
        IsClosureDisplay = isClosureDisplay
        SourceDefinition = null
        Fields = new Dictionary<string, FieldInfo>(StringComparer.Ordinal)
        Properties = new Dictionary<string, ColumnarCurrentPropertyFact>(StringComparer.Ordinal)
    }

    public static func FromSourceDefinition(
        source: ColumnarStructDef): ColumnarCurrentInstanceFacts {
        if source == null {
            throw new InvalidOperationException(
                "Current-instance source definition cannot be null.")
        }
        result := new ColumnarCurrentInstanceFacts(
            source.Builder, source.IsReference, source.IsClosureDisplay)
        result.SourceDefinition = source
        return result
    }

    public static func TryFindField(
        root: ColumnarCurrentInstanceFacts,
        name: string,
        out field: FieldInfo?,
        out declaringType: Type): bool {
        if root == null || name == null {
            throw new InvalidOperationException(
                "Current-instance field lookup facts cannot be null.")
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
                    throw new InvalidOperationException(
                        "Current-instance runtime facts cannot mix source definitions into their base chain.")
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

    public static func TryFindProperty(
        root: ColumnarCurrentInstanceFacts,
        name: string,
        out getter: MethodInfo?,
        out propertyType: Type,
        out declaringType: Type): bool {
        if root == null || name == null {
            throw new InvalidOperationException(
                "Current-instance property lookup facts cannot be null.")
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
                        throw new InvalidOperationException(
                            "Source property getter facts must declare zero parameters.")
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
                    throw new InvalidOperationException(
                        "Current-instance runtime facts cannot mix source definitions into their base chain.")
                }
                if currentFacts.Properties.ContainsKey(name) {
                    property := currentFacts.Properties[name]
                    getter = property.Getter
                    propertyType = property.PropertyType
                    if property.GetterParameterCount != 0 {
                        throw new InvalidOperationException(
                            "Current-instance property getter facts must declare zero parameters.")
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
                throw new InvalidOperationException(
                    "Current-instance source hierarchy contains a cycle.")
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
                throw new InvalidOperationException(
                    "Current-instance runtime hierarchy contains a cycle.")
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
