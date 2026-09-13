namespace NSharpLang.Compiler

import System
import System.Reflection

class ReflectionMethodInfo: TypeInfo {
    Method: MethodInfo
    displayValue: string

    constructor(method: MethodInfo) {
        Method = method
        displayValue = "method"
    }

    constructor(method: MethodInfo, displayText: string) {
        Method = method
        displayValue = displayText
    }

    override func ToString(): string {
        return displayValue
    }
}

class ReflectionMethodGroupInfo: TypeInfo {
    Methods: MethodInfo[]
    displayValue: string

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
    }

    constructor(methods: MethodInfo[], displayText: string) {
        Methods = methods
        displayValue = displayText
        IsSurrogateBinding = false
    }

    constructor(methods: MethodInfo[], displayText: string, surrogateBinding: bool) {
        Methods = methods
        displayValue = displayText
        IsSurrogateBinding = surrogateBinding
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
    displayValue: string

    constructor(name: string, addMethod: MethodInfo?, removeMethod: MethodInfo?, handlerDelegateType: Type?, declaringType: Type?, displayText: string) {
        Name = name
        AddMethod = addMethod
        RemoveMethod = removeMethod
        HandlerDelegateType = handlerDelegateType
        DeclaringType = declaringType
        displayValue = displayText
    }

    constructor(name: string) {
        Name = name
        AddMethod = null
        RemoveMethod = null
        HandlerDelegateType = null
        DeclaringType = null
        displayValue = "event"
    }

    override func ToString(): string {
        return displayValue
    }
}
