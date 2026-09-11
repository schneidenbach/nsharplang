namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Reflection

// These names are deliberately unique: the ECMA-335 MethodImpl reader used by the parent
// control can attribute each external declaration and body to this fixture without relying on
// the source-interface or closed-source rows in the same native assembly.
class ExternalInterfaceDisposeOnly: IDisposable {
    DisposeCount: int

    func Dispose() {
        DisposeCount = DisposeCount + 1
    }
}

// The declared interface order is part of the physical MethodImpl control.  The three members
// exercise a zero-parameter void slot, and two independently closed unary BCL signatures.
class ExternalInterfaceAllSlots: IDisposable, IComparable<int>, IEquatable<int> {
    DisposeCount: int

    func Dispose() {
        DisposeCount = DisposeCount + 1
    }

    func CompareTo(other: int): int {
        return other + 70
    }

    func Equals(other: int): bool {
        return other == 71
    }
}

class ExternalInterfaceArraySlot: IEquatable<int[]> {
    func Equals(other: int[]): bool {
        return other.Length == 2 && other[0] == 73 && other[1] == 74
    }
}

func ExternalInterfaceRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Missing external interface member '" + name + "'")
    }
    return method
}

func ExternalInterfaceExactZeroSignature(method: MethodInfo, returnType: Type): bool {
    return method.get_ReturnType() == returnType && method.GetParameters().Length == 0
}

func ExternalInterfaceExactUnarySignature(method: MethodInfo, returnType: Type, parameterType: Type): bool {
    parameters := method.GetParameters()
    return method.get_ReturnType() == returnType && parameters.Length == 1 && parameters[0].get_ParameterType() == parameterType
}

test "an external IDisposable slot maps to its concrete target and dispatches" {
    value := new ExternalInterfaceDisposeOnly()
    disposable: IDisposable = value
    disposable.Dispose()
    assert value.DisposeCount == 1

    contract := ExternalInterfaceRequiredMethod(typeof(IDisposable), "Dispose")
    pair := SourceInterfaceMappedPair(typeof(ExternalInterfaceDisposeOnly), typeof(IDisposable), "Dispose", 0)
    assert SourceInterfaceRequiredDeclaringType(pair.InterfaceMethod) == typeof(IDisposable)
    assert SourceInterfaceRequiredDeclaringType(pair.TargetMethod) == typeof(ExternalInterfaceDisposeOnly)
    assert pair.TargetMethod.get_Name() == "Dispose"
    assert ExternalInterfaceExactZeroSignature(pair.InterfaceMethod, contract.get_ReturnType())
    assert ExternalInterfaceExactZeroSignature(pair.TargetMethod, contract.get_ReturnType())
}

test "multiple external slots retain exact closed signatures, owners, and dispatch" {
    value := new ExternalInterfaceAllSlots()
    disposable: IDisposable = value
    comparable: IComparable<int> = value
    equatable: IEquatable<int> = value
    disposable.Dispose()
    assert value.DisposeCount == 1
    assert comparable.CompareTo(2) == 72
    assert equatable.Equals(71)
    assert !equatable.Equals(70)

    disposableContract := ExternalInterfaceRequiredMethod(typeof(IDisposable), "Dispose")
    comparableContract := ExternalInterfaceRequiredMethod(typeof(IComparable<int>), "CompareTo")
    equatableContract := ExternalInterfaceRequiredMethod(typeof(IEquatable<int>), "Equals")
    comparableParameter := comparableContract.GetParameters()[0].get_ParameterType()
    equatableParameter := equatableContract.GetParameters()[0].get_ParameterType()

    disposablePair := SourceInterfaceMappedPair(typeof(ExternalInterfaceAllSlots), typeof(IDisposable), "Dispose", 0)
    comparablePair := SourceInterfaceMappedPair(typeof(ExternalInterfaceAllSlots), typeof(IComparable<int>), "CompareTo", 1)
    equatablePair := SourceInterfaceMappedPair(typeof(ExternalInterfaceAllSlots), typeof(IEquatable<int>), "Equals", 1)
    assert SourceInterfaceRequiredDeclaringType(disposablePair.InterfaceMethod) == typeof(IDisposable)
    assert SourceInterfaceRequiredDeclaringType(comparablePair.InterfaceMethod) == typeof(IComparable<int>)
    assert SourceInterfaceRequiredDeclaringType(equatablePair.InterfaceMethod) == typeof(IEquatable<int>)
    assert SourceInterfaceRequiredDeclaringType(disposablePair.TargetMethod) == typeof(ExternalInterfaceAllSlots)
    assert SourceInterfaceRequiredDeclaringType(comparablePair.TargetMethod) == typeof(ExternalInterfaceAllSlots)
    assert SourceInterfaceRequiredDeclaringType(equatablePair.TargetMethod) == typeof(ExternalInterfaceAllSlots)
    assert disposablePair.TargetMethod.get_Name() == "Dispose"
    assert comparablePair.TargetMethod.get_Name() == "CompareTo"
    assert equatablePair.TargetMethod.get_Name() == "Equals"
    assert ExternalInterfaceExactZeroSignature(disposablePair.InterfaceMethod, disposableContract.get_ReturnType())
    assert ExternalInterfaceExactZeroSignature(disposablePair.TargetMethod, disposableContract.get_ReturnType())
    assert ExternalInterfaceExactUnarySignature(comparablePair.InterfaceMethod, comparableContract.get_ReturnType(), comparableParameter)
    assert ExternalInterfaceExactUnarySignature(comparablePair.TargetMethod, comparableContract.get_ReturnType(), comparableParameter)
    assert ExternalInterfaceExactUnarySignature(equatablePair.InterfaceMethod, equatableContract.get_ReturnType(), equatableParameter)
    assert ExternalInterfaceExactUnarySignature(equatablePair.TargetMethod, equatableContract.get_ReturnType(), equatableParameter)
}

test "an external generic parameter closes recursively to an SZ-array signature" {
    openInterface := typeof(IEquatable<int[]>).GetGenericTypeDefinition()
    openEquals := ExternalInterfaceRequiredMethod(openInterface, "Equals")
    openParameters := openEquals.GetParameters()
    if openParameters.Length != 1 {
        throw new InvalidOperationException("Open IEquatable<> did not have one parameter")
    }
    openParameter := openParameters[0].get_ParameterType()
    assert openParameter.get_IsGenericParameter()
    assert openParameter.get_GenericParameterPosition() == 0
    assert openParameter.get_DeclaringMethod() == null
    assert openParameter.get_DeclaringType() == openInterface

    values := new int[](2)
    values[0] = 73
    values[1] = 74
    value := new ExternalInterfaceArraySlot()
    equatable: IEquatable<int[]> = value
    assert equatable.Equals(values)

    closedInterface := typeof(IEquatable<int[]>)
    closedContract := ExternalInterfaceRequiredMethod(closedInterface, "Equals")
    closedParameter := closedContract.GetParameters()[0].get_ParameterType()
    pair := SourceInterfaceMappedPair(typeof(ExternalInterfaceArraySlot), closedInterface, "Equals", 1)
    assert SourceInterfaceRequiredDeclaringType(pair.InterfaceMethod) == closedInterface
    assert SourceInterfaceRequiredDeclaringType(pair.TargetMethod) == typeof(ExternalInterfaceArraySlot)
    assert pair.TargetMethod.get_Name() == "Equals"
    assert closedParameter == typeof(int[])
    assert ExternalInterfaceExactUnarySignature(pair.InterfaceMethod, closedContract.get_ReturnType(), typeof(int[]))
    assert ExternalInterfaceExactUnarySignature(pair.TargetMethod, closedContract.get_ReturnType(), typeof(int[]))
}

// The parser must accept every literal below.  ClosedSourceEmitOutcome reaches the real emitter,
// requires an MZ image for the positive twins, and snapshots a fresh decline trace.  Its observed
// `false without decline` result remains a boundary outcome: the passing twins show this path can
// reach attachment, but the negative result alone does not identify a particular internal phase.
test "external completeness accepts exact members and declines missing or mismatched slots" {
    matchingMissing := "import System\n\nclass ExternalInterfaceControlMissing: IDisposable {\n    func Dispose() {\n    }\n}\n"
    missing := "import System\n\nclass ExternalInterfaceControlMissing: IDisposable {\n    func Other() {\n    }\n}\n"
    matchingComparable := "import System\n\nclass ExternalInterfaceControlComparable: IComparable<int> {\n    func CompareTo(other: int): int { return other }\n}\n"
    returnMismatch := "import System\n\nclass ExternalInterfaceControlComparable: IComparable<int> {\n    func CompareTo(other: int): string { return \"wrong\" }\n}\n"
    arityMismatch := "import System\n\nclass ExternalInterfaceControlComparable: IComparable<int> {\n    func CompareTo(left: int, right: int): int { return left + right }\n}\n"
    parameterMismatch := "import System\n\nclass ExternalInterfaceControlComparable: IComparable<int> {\n    func CompareTo(other: string): int { return 0 }\n}\n"

    assert ClosedSourceEmitOutcome(matchingMissing) == "success"
    assert ClosedSourceEmitOutcome(missing) == "false without decline"
    assert ClosedSourceEmitOutcome(matchingComparable) == "success"
    assert ClosedSourceEmitOutcome(returnMismatch) == "false without decline"
    assert ClosedSourceEmitOutcome(arityMismatch) == "false without decline"
    assert ClosedSourceEmitOutcome(parameterMismatch) == "false without decline"
}
