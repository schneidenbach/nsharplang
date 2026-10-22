namespace NSharpLang.Compiler

import System
import System.Reflection

class ReflectionMethodInfo: TypeInfo {
    Method: MethodInfo
    displayValue: string
    IsExtension: bool

    constructor(method: MethodInfo) {
        Method = method
        displayValue = "method"
        IsExtension = false
    }

    constructor(method: MethodInfo, displayText: string) {
        Method = method
        displayValue = displayText
        IsExtension = false
    }

    constructor(method: MethodInfo, displayText: string, isExtension: bool) {
        Method = method
        displayValue = displayText
        IsExtension = isExtension
    }

    override func ToString(): string {
        return displayValue
    }
}

class ReflectionMethodGroupInfo: TypeInfo {
    Methods: MethodInfo[]
    displayValue: string
    IsExtension: bool

    // Whether this group was read off a SURROGATE instantiation — a constructed external generic
    // closed over a type the CLR has no handle for while it is being emitted, bound as `object`.
    // Such a group is a BEST EFFORT: when a candidate binds, the call is typed and checked exactly as
    // any other reflected call; when none does, the answer is `unknown` and nothing is reported,
    // because the surrogate — not the program — is what could not represent the argument. Before this
    // existed the callee typed as `unknown` unconditionally, so silence on failure is the behaviour
    // that was already there rather than a new hole.
    IsSurrogateBinding: bool

    constructor(methods: MethodInfo[]) {
        Methods = methods
        displayValue = "method group"
        IsSurrogateBinding = false
        IsExtension = false
    }

    constructor(methods: MethodInfo[], displayText: string) {
        Methods = methods
        displayValue = displayText
        IsSurrogateBinding = false
        IsExtension = false
    }

    constructor(methods: MethodInfo[], displayText: string, surrogateBinding: bool) {
        Methods = methods
        displayValue = displayText
        IsSurrogateBinding = surrogateBinding
        IsExtension = false
    }

    constructor(methods: MethodInfo[], displayText: string, surrogateBinding: bool, isExtension: bool) {
        Methods = methods
        displayValue = displayText
        IsSurrogateBinding = surrogateBinding
        IsExtension = isExtension
    }

    override func ToString(): string {
        return displayValue
    }
}

class ReflectionEventInfo: TypeInfo {
    Name: string
    AddMethod: MethodInfo?
    RemoveMethod: MethodInfo?
    HandlerDelegateType: Type?
    DeclaringType: Type?
    // THE HANDLER DELEGATE AS THE DECLARATION SPELLED IT, annotations included — which the bare CLR
    // `HandlerDelegateType` beside it cannot carry, because reference nullability lives on the MEMBER
    // rather than in the type. It is filled by whoever reads the `EventInfo`
    // (`NullabilityMetadataReflection.ConvertEventHandlerType`) and stays null for the name-only form,
    // whose caller has no `EventInfo` to read.
    AnnotatedHandlerType: TypeInfo?
    displayValue: string

    constructor(name: string, addMethod: MethodInfo?, removeMethod: MethodInfo?, handlerDelegateType: Type?, declaringType: Type?, displayText: string) {
        Name = name
        AddMethod = addMethod
        RemoveMethod = removeMethod
        HandlerDelegateType = handlerDelegateType
        DeclaringType = declaringType
        AnnotatedHandlerType = null
        displayValue = displayText
    }

    constructor(name: string) {
        Name = name
        AddMethod = null
        RemoveMethod = null
        HandlerDelegateType = null
        DeclaringType = null
        AnnotatedHandlerType = null
        displayValue = "event"
    }

    override func ToString(): string {
        return displayValue
    }
}
