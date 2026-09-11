namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.IO
import System.Reflection

// These are emitted production declarations, not a resolver surrogate.  The two Stream slots are
// deliberately declared at different external base levels; the generic comparer retains both its
// closed effective signature and its open generic definition through CLR reflection.
class BaseOverrideAncestorStream: MemoryStream {
    FlushCalls: int
    CloseCalls: int

    constructor() {
        FlushCalls = 0
        CloseCalls = 0
    }

    override func Flush() {
        FlushCalls = FlushCalls + 1
    }

    override func Close() {
        CloseCalls = CloseCalls + 1
    }
}

class BaseOverrideClosedComparer: Comparer<int> {
    override func Compare(left: int, right: int): int {
        return left - right
    }
}

func BaseOverrideNoParameters(): Type[] {
    return new Type[](0)
}

func BaseOverrideIntPair(): Type[] {
    values := new Type[](2)
    values[0] = typeof(int)
    values[1] = typeof(int)
    return values
}

func BaseOverrideRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("Missing base-override fixture member '" + name + "'.")
    }
    return method
}

// `MethodInfo.GetBaseDefinition()` is intentionally reached by reflection: the control reads the
// CLR result after real emission, while avoiding an unrelated direct-call admission requirement.
func BaseOverrideBaseDefinition(method: MethodInfo): MethodInfo {
    getBaseDefinition := typeof(MethodInfo).GetMethod("GetBaseDefinition", BaseOverrideNoParameters())
    if getBaseDefinition == null {
        throw new InvalidOperationException("Missing MethodInfo.GetBaseDefinition.")
    }
    arguments := new object?[](0)
    result := getBaseDefinition.Invoke(method, arguments) as MethodInfo
    if result == null {
        throw new InvalidOperationException("MethodInfo.GetBaseDefinition returned no MethodInfo.")
    }
    return result
}

func BaseOverrideRequiredDeclaringType(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("A base-override fixture member had no declaring type.")
    }
    return owner
}

func BaseOverrideRequirement(condition: bool, label: string): bool {
    if !condition {
        throw new InvalidOperationException("Base-override binding requirement failed: " + label)
    }
    return true
}

test "base overrides dispatch through actual MemoryStream and Stream ancestors" {
    concrete := new BaseOverrideAncestorStream()
    viaBase: Stream = concrete
    viaBase.Flush()
    viaBase.Close()
    assert BaseOverrideRequirement(concrete.FlushCalls == 1, "Flush dispatch")
    assert BaseOverrideRequirement(concrete.CloseCalls == 1, "Close dispatch")

    flush := BaseOverrideRequiredMethod(typeof(BaseOverrideAncestorStream), "Flush", BaseOverrideNoParameters())
    close := BaseOverrideRequiredMethod(typeof(BaseOverrideAncestorStream), "Close", BaseOverrideNoParameters())
    assert BaseOverrideRequirement(Convert.ToInt32(flush.get_Attributes()) == 198, "Flush attributes")
    assert BaseOverrideRequirement(Convert.ToInt32(close.get_Attributes()) == 198, "Close attributes")
    assert BaseOverrideRequirement(BaseOverrideRequiredDeclaringType(flush) == typeof(BaseOverrideAncestorStream), "Flush declaration owner")
    assert BaseOverrideRequirement(BaseOverrideRequiredDeclaringType(close) == typeof(BaseOverrideAncestorStream), "Close declaration owner")
    assert BaseOverrideRequirement(BaseOverrideRequiredDeclaringType(BaseOverrideBaseDefinition(flush)) == typeof(Stream), "Flush base definition owner")
    assert BaseOverrideRequirement(BaseOverrideRequiredDeclaringType(BaseOverrideBaseDefinition(close)) == typeof(Stream), "Close base definition owner")
}

test "a closed external generic base retains its effective int signature and open declaration" {
    concrete := new BaseOverrideClosedComparer()
    viaBase: Comparer<int> = concrete
    assert BaseOverrideRequirement(viaBase.Compare(9, 4) == 5, "first closed comparer dispatch")
    assert BaseOverrideRequirement(viaBase.Compare(1, 7) == -6, "second closed comparer dispatch")

    closedBase := typeof(Comparer<int>)
    closedTarget := BaseOverrideRequiredMethod(closedBase, "Compare", BaseOverrideIntPair())
    assert BaseOverrideRequirement(BaseOverrideRequiredDeclaringType(closedTarget) == closedBase, "closed contract owner")
    assert BaseOverrideRequirement(closedTarget.get_ReturnType() == typeof(int), "closed contract return")
    closedParameters := closedTarget.GetParameters()
    assert BaseOverrideRequirement(closedParameters.Length == 2, "closed contract arity")
    assert BaseOverrideRequirement(closedParameters[0].get_ParameterType() == typeof(int), "closed contract first parameter")
    assert BaseOverrideRequirement(closedParameters[1].get_ParameterType() == typeof(int), "closed contract second parameter")

    implementation := BaseOverrideRequiredMethod(typeof(BaseOverrideClosedComparer), "Compare", BaseOverrideIntPair())
    assert BaseOverrideRequirement(Convert.ToInt32(implementation.get_Attributes()) == 198, "closed implementation attributes")
    assert BaseOverrideRequirement(implementation.get_ReturnType() == typeof(int), "closed implementation return")
    effectiveParameters := implementation.GetParameters()
    assert BaseOverrideRequirement(effectiveParameters.Length == 2, "closed implementation arity")
    assert BaseOverrideRequirement(effectiveParameters[0].get_ParameterType() == typeof(int), "closed implementation first parameter")
    assert BaseOverrideRequirement(effectiveParameters[1].get_ParameterType() == typeof(int), "closed implementation second parameter")

    effectiveBase := BaseOverrideRequiredDeclaringType(BaseOverrideBaseDefinition(implementation))
    assert BaseOverrideRequirement(effectiveBase == closedBase, "base definition closed context")
    assert BaseOverrideRequirement(effectiveBase.get_IsGenericType(), "base definition generic shape")
    assert BaseOverrideRequirement(effectiveBase.GetGenericTypeDefinition() == closedBase.GetGenericTypeDefinition(), "base definition generic definition")
    effectiveArguments := effectiveBase.GetGenericArguments()
    assert BaseOverrideRequirement(effectiveArguments.Length == 1, "base definition generic arity")
    assert BaseOverrideRequirement(effectiveArguments[0] == typeof(int), "base definition closed generic argument")

    openBase := closedBase.GetGenericTypeDefinition()
    openArguments := openBase.GetGenericArguments()
    assert BaseOverrideRequirement(openArguments.Length == 1, "open generic definition arity")
    assert BaseOverrideRequirement(openArguments[0].get_IsGenericParameter(), "open generic definition parameter")
    assert BaseOverrideRequirement(openArguments[0].get_GenericParameterPosition() == 0, "open generic definition parameter position")
}
