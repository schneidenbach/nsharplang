namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// The unique names make the parent ECMA-335 reader's MethodImpl rows directly attributable.
// Each successful shape is compiled by the real product backend, then dispatches through the
// resulting CLR interface map; no alternate member-selection path is introduced by this test.

interface SourceInterfaceOwnAncestor {
    func OwnWins(): int
}
interface SourceInterfaceOwnDerived: SourceInterfaceOwnAncestor {
    func OwnWins(): int
}
class SourceInterfaceOwnImplementation: SourceInterfaceOwnDerived {
    func OwnWins(): int {
        return 101
    }
}

interface SourceInterfaceFallbackAncestor {
    func FallThrough(): int
}
interface SourceInterfaceFallbackDerived: SourceInterfaceFallbackAncestor {
    // The direct member has the same name but the wrong signature for the class method below.
    // It remains a default body so the ancestor is the only abstract obligation.
    func FallThrough(value: int): int {
        return value + 200
    }
}
class SourceInterfaceFallbackImplementation: SourceInterfaceFallbackDerived {
    func FallThrough(): int {
        return 102
    }
}

interface SourceInterfaceDiamondLeft {
    func DiamondFirst(): int
}
interface SourceInterfaceDiamondRight {
    func DiamondFirst(): int
}
interface SourceInterfaceDiamond: SourceInterfaceDiamondLeft, SourceInterfaceDiamondRight {
}
class SourceInterfaceDiamondImplementation: SourceInterfaceDiamond {
    func DiamondFirst(): int {
        return 103
    }
}

interface SourceInterfaceDefault {
    func DefaultCandidate(): int {
        return 104
    }
}
class SourceInterfaceDefaultOnly: SourceInterfaceDefault {
}
class SourceInterfaceDefaultOverride: SourceInterfaceDefault {
    func DefaultCandidate(): int {
        return 105
    }
}

interface SourceInterfaceExternalSource {
    func Dispose(): void
}
class SourceInterfaceExternalImplementation: SourceInterfaceExternalSource, IDisposable {
    func Dispose() {
    }
}

class SourceInterfaceMapPair {
    InterfaceMethod: MethodInfo
    TargetMethod: MethodInfo

    constructor(interfaceMethod: MethodInfo, targetMethod: MethodInfo) {
        InterfaceMethod = interfaceMethod
        TargetMethod = targetMethod
    }
}

func SourceInterfacePut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SourceInterfaceMapField(mapping: object, fieldName: string): IList {
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

func SourceInterfaceParameterCount(method: MethodInfo): int {
    return method.GetParameters().Length
}

func SourceInterfaceMappedPair(implementation: Type, interfaceType: Type, memberName: string, parameterCount: int): SourceInterfaceMapPair {
    getInterfaceMap := typeof(Type).GetMethod("GetInterfaceMap")
    if getInterfaceMap == null {
        throw new InvalidOperationException("Missing Type.GetInterfaceMap")
    }
    arguments := new object?[](1)
    SourceInterfacePut(arguments, 0, interfaceType)
    mapping := getInterfaceMap.Invoke(implementation, arguments)
    if mapping == null {
        throw new InvalidOperationException("Type.GetInterfaceMap returned null")
    }
    interfaceMethods := SourceInterfaceMapField(mapping, "InterfaceMethods")
    targetMethods := SourceInterfaceMapField(mapping, "TargetMethods")
    if interfaceMethods.Count != targetMethods.Count {
        throw new InvalidOperationException("InterfaceMapping method columns had different counts")
    }
    index := 0
    while index < interfaceMethods.Count {
        candidate := interfaceMethods[index] as MethodInfo
        target := targetMethods[index] as MethodInfo
        if candidate != null && target != null && candidate.get_Name() == memberName && SourceInterfaceParameterCount(candidate) == parameterCount {
            return new SourceInterfaceMapPair(candidate, target)
        }
        index = index + 1
    }
    throw new InvalidOperationException("No mapped member '" + memberName + "'")
}

func SourceInterfaceRequiredDeclaringType(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("Method had no declaring type")
    }
    return owner
}

func SourceInterfaceHostMethod(typeName: string, methodName: string): MethodInfo {
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

func SourceInterfaceReadDeclineProperty(target: object, name: string): string {
    targetType := target.GetType()
    property := targetType.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing decline property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

// This is a test-only call to the stable product emitter entry point. It supplies invalid source
// shapes that cannot live directly in a `.tests.nl` compilation, while retaining parser-to-emitter
// behavior on both the baseline and post-port compiler. Parsing must succeed before this helper
// samples the fresh emitter decline trace, so a parser refusal cannot masquerade as member matching.
func SourceInterfaceEmitOutcome(source: string): string {
    parse := SourceInterfaceHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    parseArguments := new object?[](2)
    SourceInterfacePut(parseArguments, 0, source)
    SourceInterfacePut(parseArguments, 1, null)
    if !Convert.ToBoolean(parse.Invoke(null, parseArguments)) {
        throw new InvalidOperationException("Source-interface control did not parse")
    }
    program := parseArguments[1]
    if program == null {
        throw new InvalidOperationException("Parser returned no program")
    }
    reset := SourceInterfaceHostMethod("ColumnarDeclineTrace", "Reset")
    emptyArguments := new object?[](0)
    resetResult := reset.Invoke(null, emptyArguments)
    _ = resetResult
    emit := SourceInterfaceHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArguments := new object?[](7)
    SourceInterfacePut(emitArguments, 0, "SourceInterfaceNegative")
    SourceInterfacePut(emitArguments, 1, "Program")
    SourceInterfacePut(emitArguments, 2, program)
    SourceInterfacePut(emitArguments, 3, false)
    SourceInterfacePut(emitArguments, 4, null)
    SourceInterfacePut(emitArguments, 5, null)
    SourceInterfacePut(emitArguments, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArguments))
    snapshot := SourceInterfaceHostMethod("ColumnarDeclineTrace", "Snapshot")
    records := snapshot.Invoke(null, emptyArguments) as IList
    if records == null {
        throw new InvalidOperationException("No decline snapshot")
    }
    if records.Count == 0 {
        if succeeded {
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
    return SourceInterfaceReadDeclineProperty(first, "SiteId") + "|" + SourceInterfaceReadDeclineProperty(first, "Message") + "|" + SourceInterfaceReadDeclineProperty(first, "MemberName")
}

test "a direct source declaration owns an own matching interface slot" {
    value := new SourceInterfaceOwnImplementation()
    ancestor: SourceInterfaceOwnAncestor = value
    own: SourceInterfaceOwnDerived = value
    assert ancestor.OwnWins() == 101
    assert own.OwnWins() == 101

    pair := SourceInterfaceMappedPair(typeof(SourceInterfaceOwnImplementation), typeof(SourceInterfaceOwnDerived), "OwnWins", 0)
    assert SourceInterfaceRequiredDeclaringType(pair.InterfaceMethod) == typeof(SourceInterfaceOwnDerived)
    assert SourceInterfaceRequiredDeclaringType(pair.TargetMethod) == typeof(SourceInterfaceOwnImplementation)
}

test "a mismatching own source declaration selects its actual ancestor owner" {
    value := new SourceInterfaceFallbackImplementation()
    ancestor: SourceInterfaceFallbackAncestor = value
    derived: SourceInterfaceFallbackDerived = value
    assert ancestor.FallThrough() == 102
    assert derived.FallThrough(1) == 201

    pair := SourceInterfaceMappedPair(typeof(SourceInterfaceFallbackImplementation), typeof(SourceInterfaceFallbackAncestor), "FallThrough", 0)
    assert SourceInterfaceRequiredDeclaringType(pair.InterfaceMethod) == typeof(SourceInterfaceFallbackAncestor)
    assert SourceInterfaceRequiredDeclaringType(pair.TargetMethod) == typeof(SourceInterfaceFallbackImplementation)
}

test "a source diamond takes its first base and dispatches through both arms" {
    value := new SourceInterfaceDiamondImplementation()
    left: SourceInterfaceDiamondLeft = value
    right: SourceInterfaceDiamondRight = value
    assert left.DiamondFirst() == 103
    assert right.DiamondFirst() == 103

    leftPair := SourceInterfaceMappedPair(typeof(SourceInterfaceDiamondImplementation), typeof(SourceInterfaceDiamondLeft), "DiamondFirst", 0)
    rightPair := SourceInterfaceMappedPair(typeof(SourceInterfaceDiamondImplementation), typeof(SourceInterfaceDiamondRight), "DiamondFirst", 0)
    assert SourceInterfaceRequiredDeclaringType(leftPair.InterfaceMethod) == typeof(SourceInterfaceDiamondLeft)
    assert SourceInterfaceRequiredDeclaringType(rightPair.InterfaceMethod) == typeof(SourceInterfaceDiamondRight)
    assert SourceInterfaceRequiredDeclaringType(leftPair.TargetMethod) == typeof(SourceInterfaceDiamondImplementation)
    assert SourceInterfaceRequiredDeclaringType(rightPair.TargetMethod) == typeof(SourceInterfaceDiamondImplementation)
}

test "a default interface body remains admitted and an override maps its declared slot" {
    defaultOnly := new SourceInterfaceDefaultOnly()
    defaultInterface: SourceInterfaceDefault = defaultOnly
    assert defaultInterface.DefaultCandidate() == 104

    overridden := new SourceInterfaceDefaultOverride()
    overriddenInterface: SourceInterfaceDefault = overridden
    assert overriddenInterface.DefaultCandidate() == 105
    pair := SourceInterfaceMappedPair(typeof(SourceInterfaceDefaultOverride), typeof(SourceInterfaceDefault), "DefaultCandidate", 0)
    assert SourceInterfaceRequiredDeclaringType(pair.InterfaceMethod) == typeof(SourceInterfaceDefault)
    assert SourceInterfaceRequiredDeclaringType(pair.TargetMethod) == typeof(SourceInterfaceDefaultOverride)
}

test "source and external same-signature slots both remain dispatchable" {
    value := new SourceInterfaceExternalImplementation()
    source: SourceInterfaceExternalSource = value
    runtime: IDisposable = value
    source.Dispose()
    runtime.Dispose()

    sourcePair := SourceInterfaceMappedPair(typeof(SourceInterfaceExternalImplementation), typeof(SourceInterfaceExternalSource), "Dispose", 0)
    externalPair := SourceInterfaceMappedPair(typeof(SourceInterfaceExternalImplementation), typeof(IDisposable), "Dispose", 0)
    assert SourceInterfaceRequiredDeclaringType(sourcePair.TargetMethod) == typeof(SourceInterfaceExternalImplementation)
    assert SourceInterfaceRequiredDeclaringType(externalPair.TargetMethod) == typeof(SourceInterfaceExternalImplementation)
}

test "missing and signature-mismatched source members reach the emitter and decline without a located row" {
    missing := "interface SourceInterfaceMissing {\n    func Required(value: int): int\n}\nclass SourceInterfaceMissingImplementation: SourceInterfaceMissing {\n    func Other(value: int): int { return value }\n}\n"
    mismatch := "interface SourceInterfaceMismatch {\n    func Required(value: int): int\n}\nclass SourceInterfaceMismatchImplementation: SourceInterfaceMismatch {\n    func Required(value: string): int { return 0 }\n}\n"
    assert SourceInterfaceEmitOutcome(missing) == "false without decline"
    assert SourceInterfaceEmitOutcome(mismatch) == "false without decline"
}
