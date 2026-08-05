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

    constructor(methods: MethodInfo[]) {
        Methods = methods
        displayValue = "method group"
    }

    constructor(methods: MethodInfo[], displayText: string) {
        Methods = methods
        displayValue = displayText
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
