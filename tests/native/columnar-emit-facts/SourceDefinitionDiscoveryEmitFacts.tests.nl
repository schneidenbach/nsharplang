namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// These names identify only the source-definition discovery routes.  The test assembly is emitted
// by the production columnar backend, so the metadata and interface maps below exercise the same
// registry-to-builder discovery used by declaration constraints, closed interface attachment, and
// constrained calls.
interface SourceDiscoveryMarker {
    func Mark(): int
}

struct SourceDiscoveryMarkerValue: SourceDiscoveryMarker {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Mark(): int {
        return Value + 100
    }
}

class SourceDiscoveryConstrainedByInterface<T> where T: SourceDiscoveryMarker {
    Count: int
}

func SourceDiscoveryConstrainedCall<T>(value: T): int where T: SourceDiscoveryMarker {
    return value.Mark()
}

interface SourceDiscoveryClosedSlot<T> {
    func Rewrite(value: T): T
}

class SourceDiscoveryClosedSlotInt: SourceDiscoveryClosedSlot<int> {
    func Rewrite(value: int): int {
        return value + 33
    }
}

class SourceDiscoveryMapPair {
    InterfaceMethod: MethodInfo
    TargetMethod: MethodInfo

    constructor(interfaceMethod: MethodInfo, targetMethod: MethodInfo) {
        InterfaceMethod = interfaceMethod
        TargetMethod = targetMethod
    }
}

func SourceDiscoveryPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SourceDiscoveryMapField(mapping: object, fieldName: string): IList {
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

func SourceDiscoveryMappedPair(implementation: Type, interfaceType: Type, memberName: string, parameterCount: int): SourceDiscoveryMapPair {
    getInterfaceMap := typeof(Type).GetMethod("GetInterfaceMap")
    if getInterfaceMap == null {
        throw new InvalidOperationException("Missing Type.GetInterfaceMap")
    }
    arguments := new object?[](1)
    SourceDiscoveryPut(arguments, 0, interfaceType)
    mapping := getInterfaceMap.Invoke(implementation, arguments)
    if mapping == null {
        throw new InvalidOperationException("Type.GetInterfaceMap returned null")
    }
    interfaceMethods := SourceDiscoveryMapField(mapping, "InterfaceMethods")
    targetMethods := SourceDiscoveryMapField(mapping, "TargetMethods")
    if interfaceMethods.Count != targetMethods.Count {
        throw new InvalidOperationException("InterfaceMapping method columns had different counts")
    }
    index := 0
    while index < interfaceMethods.Count {
        candidate := interfaceMethods[index] as MethodInfo
        target := targetMethods[index] as MethodInfo
        if candidate != null && target != null && candidate.get_Name() == memberName && candidate.GetParameters().Length == parameterCount {
            return new SourceDiscoveryMapPair(candidate, target)
        }
        index = index + 1
    }
    throw new InvalidOperationException("No mapped member '" + memberName + "'")
}

func SourceDiscoveryRequiredDeclaringType(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("Method had no declaring type")
    }
    return owner
}

func SourceDiscoveryExactUnarySignature(method: MethodInfo, returnType: Type, parameterType: Type): bool {
    parameters := method.GetParameters()
    return method.get_ReturnType() == returnType && parameters.Length == 1 && parameters[0].get_ParameterType() == parameterType
}

func SourceDiscoveryHostMethod(typeName: string, methodName: string): MethodInfo {
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

func SourceDiscoveryReadDeclineProperty(target: object, name: string): string {
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing decline property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

// Invalid implementations cannot live in this emitted test assembly.  This invokes the actual
// parser and emitter, requires parser success first, resets the trace for every run, and accepts a
// successful MZ image only when no decline was recorded.  A `false without decline` remains an
// observed baseline outcome rather than an invented failure reason.
func SourceDiscoveryEmitOutcome(source: string): string {
    parse := SourceDiscoveryHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    parseArguments := new object?[](2)
    SourceDiscoveryPut(parseArguments, 0, source)
    SourceDiscoveryPut(parseArguments, 1, null)
    if !Convert.ToBoolean(parse.Invoke(null, parseArguments)) {
        throw new InvalidOperationException("Source-discovery control did not parse")
    }
    program := parseArguments[1]
    if program == null {
        throw new InvalidOperationException("Source-discovery parser returned no program")
    }
    reset := SourceDiscoveryHostMethod("ColumnarDeclineTrace", "Reset")
    emptyArguments := new object?[](0)
    resetResult := reset.Invoke(null, emptyArguments)
    _ = resetResult
    emit := SourceDiscoveryHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArguments := new object?[](7)
    SourceDiscoveryPut(emitArguments, 0, "SourceDefinitionDiscoveryControl")
    SourceDiscoveryPut(emitArguments, 1, "Program")
    SourceDiscoveryPut(emitArguments, 2, program)
    SourceDiscoveryPut(emitArguments, 3, false)
    SourceDiscoveryPut(emitArguments, 4, null)
    SourceDiscoveryPut(emitArguments, 5, null)
    SourceDiscoveryPut(emitArguments, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArguments))
    snapshot := SourceDiscoveryHostMethod("ColumnarDeclineTrace", "Snapshot")
    records := snapshot.Invoke(null, emptyArguments) as IList
    if records == null {
        throw new InvalidOperationException("No source-discovery decline snapshot")
    }
    if records.Count == 0 {
        if succeeded {
            image := emitArguments[4] as IList
            if image == null || image.Count < 2 || Convert.ToInt32(image[0]) != 77 || Convert.ToInt32(image[1]) != 90 {
                throw new InvalidOperationException("Source-discovery emitter returned no MZ image")
            }
            return "success"
        }
        return "false without decline"
    }
    if succeeded || records.Count != 1 {
        throw new InvalidOperationException("Source-discovery emitter produced an unexpected decline set")
    }
    first := records[0]
    if first == null {
        throw new InvalidOperationException("Source-discovery decline snapshot was empty")
    }
    return SourceDiscoveryReadDeclineProperty(first, "SiteId") + "|" + SourceDiscoveryReadDeclineProperty(first, "Message") + "|" + SourceDiscoveryReadDeclineProperty(first, "MemberName")
}

test "a source interface generic constraint keeps its actual interface metadata" {
    closed := typeof(SourceDiscoveryConstrainedByInterface<SourceDiscoveryMarkerValue>)
    open := closed.GetGenericTypeDefinition()
    parameters := open.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected one constrained type parameter")
    }
    parameter := parameters[0]
    assert parameter.get_IsGenericParameter()
    assert parameter.get_IsGenericTypeParameter()
    assert !parameter.get_IsGenericMethodParameter()
    assert parameter.get_GenericParameterPosition() == 0
    assert parameter.get_DeclaringType() == open
    constraints := parameter.GetGenericParameterConstraints()
    assert constraints.Length == 1
    assert constraints[0] == typeof(SourceDiscoveryMarker)
}

test "a generic source interface constraint emits constrained dispatch and reaches its implementation" {
    value := new SourceDiscoveryMarkerValue(7)
    assert SourceDiscoveryConstrainedCall(value) == 107
}

test "a closed source interface slot retains its closed declaration and concrete target" {
    value := new SourceDiscoveryClosedSlotInt()
    interfaceType := typeof(SourceDiscoveryClosedSlot<int>)
    pair := SourceDiscoveryMappedPair(typeof(SourceDiscoveryClosedSlotInt), interfaceType, "Rewrite", 1)
    invokeArguments := new object?[](1)
    SourceDiscoveryPut(invokeArguments, 0, 9)
    assert Convert.ToInt32(pair.InterfaceMethod.Invoke(value, invokeArguments)) == 42
    assert SourceDiscoveryRequiredDeclaringType(pair.InterfaceMethod) == interfaceType
    assert SourceDiscoveryRequiredDeclaringType(pair.TargetMethod) == typeof(SourceDiscoveryClosedSlotInt)
    assert SourceDiscoveryExactUnarySignature(pair.InterfaceMethod, typeof(int), typeof(int))
    assert SourceDiscoveryExactUnarySignature(pair.TargetMethod, typeof(int), typeof(int))
}

test "closed source interface completeness keeps a matching twin separate from a parsed missing member" {
    missing := "interface SourceDiscoveryMissing<T> {\n    func Required(value: T): T\n}\nclass SourceDiscoveryMissingImplementation: SourceDiscoveryMissing<int> {\n    func Other(value: int): int { return value }\n}\n"
    matching := "interface SourceDiscoveryMissing<T> {\n    func Required(value: T): T\n}\nclass SourceDiscoveryMissingImplementation: SourceDiscoveryMissing<int> {\n    func Required(value: int): int { return value }\n}\n"
    assert SourceDiscoveryEmitOutcome(matching) == "success"
    assert SourceDiscoveryEmitOutcome(missing) == "false without decline"
}
