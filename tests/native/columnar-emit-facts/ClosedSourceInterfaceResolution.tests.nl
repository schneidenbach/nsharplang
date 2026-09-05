namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// Each implementation has an own member on a constructed source interface. The two independent
// instantiations force the attachment path to bind distinct closed signatures rather than merely
// reusing the open interface method represented by `T`.
interface ClosedSourceSignature<TSignature> {
    func Transform(value: TSignature): TSignature
    func ArrayRoundTrip(values: TSignature[]): TSignature[]
}

class ClosedSourceSignatureInt: ClosedSourceSignature<int> {
    func Transform(value: int): int {
        return value + 1
    }

    func ArrayRoundTrip(values: int[]): int[] {
        return values
    }
}

class ClosedSourceSignatureString: ClosedSourceSignature<string> {
    func Transform(value: string): string {
        return value + "!"
    }

    func ArrayRoundTrip(values: string[]): string[] {
        return values
    }
}

// This constraint call reaches the shared closed-method selector. Its member has both a closed
// parameter and a closed return, so a successful invocation proves the call path uses the same
// substitution boundary as closed attachment rather than an open `T` signature.
interface ClosedSourceConstrained<TConstrained> {
    func Pick(other: TConstrained): TConstrained
}

class ClosedSourceConstrainedValue: ClosedSourceConstrained<ClosedSourceConstrainedValue> {
    Id: int

    constructor(id: int) {
        Id = id
    }

    func Pick(other: ClosedSourceConstrainedValue): ClosedSourceConstrainedValue {
        return other
    }
}

func ClosedSourcePick<TValue>(left: TValue, right: TValue): TValue where TValue: ClosedSourceConstrained<TValue> {
    return left.Pick(right)
}

class ClosedSourceMapPair {
    InterfaceMethod: MethodInfo
    TargetMethod: MethodInfo

    constructor(interfaceMethod: MethodInfo, targetMethod: MethodInfo) {
        InterfaceMethod = interfaceMethod
        TargetMethod = targetMethod
    }
}

func ClosedSourcePut(values: object?[], index: int, value: object?) {
    values[index] = value
}

// InterfaceMapping is reached by reflection because stage0 has no direct local for that value-type
// return. The test still reads the CLR mapping emitted by the production compiler, and it keeps the
// interface declaration owner separate from the concrete target owner.
func ClosedSourceMapField(mapping: object, fieldName: string): IList {
    field := mapping.GetType().GetField(fieldName)
    if field == null {
        throw new InvalidOperationException("Missing InterfaceMapping field '" + fieldName + "'")
    }
    values := field.GetValue(mapping) as IList
    if values == null {
        throw new InvalidOperationException("InterfaceMapping field '" + fieldName + "' was not an IList")
    }
    return values
}

func ClosedSourceMappedPair(implementation: Type, interfaceType: Type, memberName: string, parameterCount: int): ClosedSourceMapPair {
    getInterfaceMap := typeof(Type).GetMethod("GetInterfaceMap")
    if getInterfaceMap == null {
        throw new InvalidOperationException("Missing Type.GetInterfaceMap")
    }
    arguments := new object?[](1)
    ClosedSourcePut(arguments, 0, interfaceType)
    mapping := getInterfaceMap.Invoke(implementation, arguments)
    if mapping == null {
        throw new InvalidOperationException("Type.GetInterfaceMap returned null")
    }
    interfaceMethods := ClosedSourceMapField(mapping, "InterfaceMethods")
    targetMethods := ClosedSourceMapField(mapping, "TargetMethods")
    if interfaceMethods.Count != targetMethods.Count {
        throw new InvalidOperationException("InterfaceMapping method columns had different counts")
    }
    index := 0
    while index < interfaceMethods.Count {
        candidate := interfaceMethods[index] as MethodInfo
        target := targetMethods[index] as MethodInfo
        if candidate != null && target != null && candidate.get_Name() == memberName && candidate.GetParameters().Length == parameterCount {
            return new ClosedSourceMapPair(candidate, target)
        }
        index = index + 1
    }
    throw new InvalidOperationException("No mapped member '" + memberName + "'")
}

func ClosedSourceExactUnarySignature(method: MethodInfo, returnType: Type, parameterType: Type): bool {
    parameters := method.GetParameters()
    return method.get_ReturnType() == returnType && parameters.Length == 1 && parameters[0].get_ParameterType() == parameterType
}

func ClosedSourceRequiredDeclaringType(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("Method had no declaring type")
    }
    return owner
}

func ClosedSourceRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Missing closed source member '" + name + "'")
    }
    return method
}

func ClosedSourceHostMethod(typeName: string, methodName: string): MethodInfo {
    owner := Type.GetType("NSharpLang.Compiler.Columnar." + typeName + ", Compiler")
    if owner == null {
        throw new InvalidOperationException("Missing host " + typeName)
    }
    methods := owner.GetMethods((BindingFlags)40)
    for method in methods {
        if method.get_Name() == methodName {
            return method
        }
    }
    throw new InvalidOperationException("Missing host method " + methodName)
}

func ClosedSourceReadDeclineProperty(target: object, name: string): string {
    targetType := target.GetType()
    property := targetType.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing decline property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

// Invalid implementations cannot live in the test assembly, so this invokes the same production
// parser and emitter entry points with a fresh decline trace. Parsing is required first, and a
// successful result must contain an MZ image. The positive twins demonstrate that this parser/emitter
// route succeeds; `false without decline` remains the observed negative result rather than proof of
// one particular internal rejection.
func ClosedSourceEmitOutcome(source: string): string {
    parse := ClosedSourceHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    parseArguments := new object?[](2)
    ClosedSourcePut(parseArguments, 0, source)
    ClosedSourcePut(parseArguments, 1, null)
    if !Convert.ToBoolean(parse.Invoke(null, parseArguments)) {
        throw new InvalidOperationException("Closed-source control did not parse")
    }
    program := parseArguments[1]
    if program == null {
        throw new InvalidOperationException("Parser returned no program")
    }
    reset := ClosedSourceHostMethod("ColumnarDeclineTrace", "Reset")
    emptyArguments := new object?[](0)
    resetResult := reset.Invoke(null, emptyArguments)
    _ = resetResult
    emit := ClosedSourceHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArguments := new object?[](7)
    ClosedSourcePut(emitArguments, 0, "ClosedSourceInterfaceControl")
    ClosedSourcePut(emitArguments, 1, "Program")
    ClosedSourcePut(emitArguments, 2, program)
    ClosedSourcePut(emitArguments, 3, false)
    ClosedSourcePut(emitArguments, 4, null)
    ClosedSourcePut(emitArguments, 5, null)
    ClosedSourcePut(emitArguments, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArguments))
    snapshot := ClosedSourceHostMethod("ColumnarDeclineTrace", "Snapshot")
    records := snapshot.Invoke(null, emptyArguments) as IList
    if records == null {
        throw new InvalidOperationException("No decline snapshot")
    }
    if records.Count == 0 {
        if succeeded {
            image := emitArguments[4] as IList
            if image == null || image.Count < 2 || Convert.ToInt32(image[0]) != 77 || Convert.ToInt32(image[1]) != 90 {
                throw new InvalidOperationException("Emitter returned no MZ image")
            }
            return "success"
        }
        return "false without decline"
    }
    if succeeded {
        throw new InvalidOperationException("Emitter succeeded with a decline")
    }
    if records.Count != 1 {
        throw new InvalidOperationException("Expected one decline")
    }
    first := records[0]
    if first == null {
        throw new InvalidOperationException("No first decline")
    }
    return ClosedSourceReadDeclineProperty(first, "SiteId") + "|" + ClosedSourceReadDeclineProperty(first, "Message") + "|" + ClosedSourceReadDeclineProperty(first, "MemberName")
}

test "closed source own slots retain two instantiated scalar and SZ-array signatures" {
    intInterface := typeof(ClosedSourceSignature<int>)
    stringInterface := typeof(ClosedSourceSignature<string>)
    openInterface := intInterface.GetGenericTypeDefinition()
    openTransform := ClosedSourceRequiredMethod(openInterface, "Transform")
    openArray := ClosedSourceRequiredMethod(openInterface, "ArrayRoundTrip")
    openTransformParameters := openTransform.GetParameters()
    openArrayParameters := openArray.GetParameters()
    if openTransformParameters.Length != 1 || openArrayParameters.Length != 1 {
        throw new InvalidOperationException("Open closed-source signature did not have one parameter")
    }
    openTransformParameter := openTransformParameters[0].get_ParameterType()
    openArrayParameter := openArrayParameters[0].get_ParameterType()
    openArrayElement := openArrayParameter.GetElementType()
    if openArrayElement == null {
        throw new InvalidOperationException("Open closed-source array had no element type")
    }
    assert openTransform.get_ReturnType() == openTransformParameter
    assert openTransformParameter.get_IsGenericParameter()
    assert openArray.get_ReturnType() == openArrayParameter
    assert openArrayParameter.get_IsSZArray()
    assert openArrayElement.get_IsGenericParameter()

    intTransform := ClosedSourceRequiredMethod(intInterface, "Transform")
    intArray := ClosedSourceRequiredMethod(intInterface, "ArrayRoundTrip")
    stringTransform := ClosedSourceRequiredMethod(stringInterface, "Transform")
    stringArray := ClosedSourceRequiredMethod(stringInterface, "ArrayRoundTrip")

    assert ClosedSourceExactUnarySignature(intTransform, typeof(int), typeof(int))
    assert ClosedSourceExactUnarySignature(intArray, typeof(int[]), typeof(int[]))
    assert ClosedSourceExactUnarySignature(stringTransform, typeof(string), typeof(string))
    assert ClosedSourceExactUnarySignature(stringArray, typeof(string[]), typeof(string[]))

    intPair := ClosedSourceMappedPair(typeof(ClosedSourceSignatureInt), intInterface, "Transform", 1)
    intArrayPair := ClosedSourceMappedPair(typeof(ClosedSourceSignatureInt), intInterface, "ArrayRoundTrip", 1)
    stringPair := ClosedSourceMappedPair(typeof(ClosedSourceSignatureString), stringInterface, "Transform", 1)
    stringArrayPair := ClosedSourceMappedPair(typeof(ClosedSourceSignatureString), stringInterface, "ArrayRoundTrip", 1)
    assert ClosedSourceRequiredDeclaringType(intPair.InterfaceMethod) == intInterface
    assert ClosedSourceRequiredDeclaringType(intArrayPair.InterfaceMethod) == intInterface
    assert ClosedSourceRequiredDeclaringType(stringPair.InterfaceMethod) == stringInterface
    assert ClosedSourceRequiredDeclaringType(stringArrayPair.InterfaceMethod) == stringInterface
    assert ClosedSourceRequiredDeclaringType(intPair.TargetMethod) == typeof(ClosedSourceSignatureInt)
    assert ClosedSourceRequiredDeclaringType(intArrayPair.TargetMethod) == typeof(ClosedSourceSignatureInt)
    assert ClosedSourceRequiredDeclaringType(stringPair.TargetMethod) == typeof(ClosedSourceSignatureString)
    assert ClosedSourceRequiredDeclaringType(stringArrayPair.TargetMethod) == typeof(ClosedSourceSignatureString)
    assert ClosedSourceExactUnarySignature(intPair.TargetMethod, typeof(int), typeof(int))
    assert ClosedSourceExactUnarySignature(intArrayPair.TargetMethod, typeof(int[]), typeof(int[]))
    assert ClosedSourceExactUnarySignature(stringPair.TargetMethod, typeof(string), typeof(string))
    assert ClosedSourceExactUnarySignature(stringArrayPair.TargetMethod, typeof(string[]), typeof(string[]))

    invokeArguments := new object?[](1)
    ClosedSourcePut(invokeArguments, 0, 40)
    assert Convert.ToInt32(intPair.InterfaceMethod.Invoke(new ClosedSourceSignatureInt(), invokeArguments)) == 41
    ClosedSourcePut(invokeArguments, 0, "ok")
    assert Convert.ToString(stringPair.InterfaceMethod.Invoke(new ClosedSourceSignatureString(), invokeArguments)) == "ok!"
    intValues := new int[](1)
    intValues[0] = 7
    ClosedSourcePut(invokeArguments, 0, intValues)
    assert Object.ReferenceEquals(intArrayPair.InterfaceMethod.Invoke(new ClosedSourceSignatureInt(), invokeArguments), intValues)
    stringValues := new string[](1)
    stringValues[0] = "array"
    ClosedSourcePut(invokeArguments, 0, stringValues)
    assert Object.ReferenceEquals(stringArrayPair.InterfaceMethod.Invoke(new ClosedSourceSignatureString(), invokeArguments), stringValues)
}

test "closed source defaults and exact concrete completion reach the production emitter" {
    defaultOnly := "interface ClosedSourceControlDefault<T> {\n    func Echo(value: T): T { return value }\n}\nclass ClosedSourceControlDefaultOnly: ClosedSourceControlDefault<int> {\n}\n"
    defaultOverride := "interface ClosedSourceControlDefault<T> {\n    func Echo(value: T): T { return value }\n}\nclass ClosedSourceControlDefaultOverride: ClosedSourceControlDefault<int> {\n    func Echo(value: int): int { return value + 1 }\n}\n"
    complete := "interface ClosedSourceControlComplete<T> {\n    func Required(value: T): T\n}\nclass ClosedSourceControlCompleteImplementation: ClosedSourceControlComplete<int> {\n    func Required(value: int): int { return value }\n}\n"

    assert ClosedSourceEmitOutcome(defaultOnly) == "success"
    assert ClosedSourceEmitOutcome(defaultOverride) == "success"
    assert ClosedSourceEmitOutcome(complete) == "success"
}

test "closed source completeness rejects missing and exact-signature mismatches after parser success" {
    matchingMissing := "interface ClosedSourceControlMissing<T> {\n    func Required(value: T): T\n}\nclass ClosedSourceControlMissingImplementation: ClosedSourceControlMissing<int> {\n    func Required(value: int): int { return value }\n}\n"
    missing := "interface ClosedSourceControlMissing<T> {\n    func Required(value: T): T\n}\nclass ClosedSourceControlMissingImplementation: ClosedSourceControlMissing<int> {\n    func Other(value: int): int { return value }\n}\n"
    matchingMismatch := "interface ClosedSourceControlMismatch<T> {\n    func Required(value: T): T\n}\nclass ClosedSourceControlMismatchImplementation: ClosedSourceControlMismatch<int> {\n    func Required(value: int): int { return value }\n}\n"
    mismatch := "interface ClosedSourceControlMismatch<T> {\n    func Required(value: T): T\n}\nclass ClosedSourceControlMismatchImplementation: ClosedSourceControlMismatch<int> {\n    func Required(value: string): int { return 0 }\n}\n"

    assert ClosedSourceEmitOutcome(matchingMissing) == "success"
    assert ClosedSourceEmitOutcome(missing) == "false without decline"
    assert ClosedSourceEmitOutcome(matchingMismatch) == "success"
    assert ClosedSourceEmitOutcome(mismatch) == "false without decline"
}

test "a constrained source call closes both its parameter and return before dispatch" {
    left := new ClosedSourceConstrainedValue(1)
    right := new ClosedSourceConstrainedValue(2)
    result := ClosedSourcePick(left, right)
    assert result.Id == 2

    constrainedInterface := typeof(ClosedSourceConstrained<ClosedSourceConstrainedValue>)
    pick := ClosedSourceRequiredMethod(constrainedInterface, "Pick")
    concreteType := typeof(ClosedSourceConstrainedValue)
    assert ClosedSourceExactUnarySignature(pick, concreteType, concreteType)
}
