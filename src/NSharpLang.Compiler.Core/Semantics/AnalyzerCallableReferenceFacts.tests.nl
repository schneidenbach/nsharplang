namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's callable / delegate-reference classification family.
// These predicates were `private static` in Analyzer.cs, so no test named them directly; their
// behaviour was pinned only indirectly, by end-to-end analyzer diagnostics. This is their first
// DIRECT pinning.
class CallableFactsProbeDelegateHolder {
    static func Identity(value: int): int {
        return value
    }
}

func CallableRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Required callable probe method was not found: " + name)
    }

    return method
}

func CallableProbeMethod(): MethodInfo {
    return CallableRequiredMethod(typeof(CallableFactsProbeDelegateHolder), "Identity")
}

// A FunctionTypeInfo carrying a DECLARED function's identity — what a method group reference to a
// named source function resolves to.
func CallableSourceFunction(sourceName: string?): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.SourceName = sourceName
    result.SyntheticName = "probe"
    result.ParameterTypes = new List<TypeInfo>()
    result.ReturnType = BuiltInTypes.Int
    return result
}

func CallableModifierFunction(modifiers: List<Ast.ParameterModifier>?): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.SourceName = "Probe"
    result.ParameterModifiers = modifiers
    return result
}

func CallableModifierList(values: Ast.ParameterModifier[]): List<Ast.ParameterModifier> {
    result := new List<Ast.ParameterModifier>()
    index := 0
    while index < values.Length {
        result.Add(values[index])
        index += 1
    }

    return result
}

func CallableTypeArguments(count: int): List<TypeInfo> {
    result := new List<TypeInfo>()
    if count > 0 {
        result.Add(BuiltInTypes.Int)
    }
    if count > 1 {
        result.Add(BuiltInTypes.String)
    }
    if count > 2 {
        result.Add(BuiltInTypes.Bool)
    }
    if count > 3 {
        result.Add(BuiltInTypes.Double)
    }
    return result
}

func CallableRequiredCoreType(fullName: string): Type {
    valueType := typeof(object).get_Assembly().GetType(fullName)
    if valueType == null {
        throw new InvalidOperationException("Required core-library type was not found: " + fullName)
    }

    return valueType
}

func CallableSimpleName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    simple := candidate as SimpleTypeInfo
    if simple == null {
        throw new InvalidOperationException("Expected a simple return type.")
    }

    return simple.Name
}

test "method-group classification accepts exactly the three method-group shapes" {
    probe := CallableProbeMethod()
    methods := new MethodInfo[](1)
    methods[0] = probe

    assert AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(new ReflectionMethodInfo(probe))
    assert AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(new ReflectionMethodGroupInfo(methods))
    assert AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(
        new NSharpMethodGroupInfo(new List<FunctionTypeInfo>())
    )

    // An EMPTY reflection group is still a method group — the shape decides, not the contents.
    assert AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(
        new ReflectionMethodGroupInfo(new MethodInfo[](0))
    )

    // A function type is NOT a method group, however it is named.
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(CallableSourceFunction("F"))
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(CallableSourceFunction(null))

    // Nothing else in the type model qualifies.
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(BuiltInTypes.Int)
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(BuiltInTypes.Object)
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(BuiltInTypes.Unknown)
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(new ArrayTypeInfo(BuiltInTypes.Int))
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(new ReflectionTypeInfo(typeof(Action)))
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(
        new GenericTypeInfo("Func", CallableTypeArguments(1))
    )
    assert !AnalyzerCallableReferenceFacts.IsMethodGroupReferenceType(new TypeInfo())
}

test "source function identity is exactly a non-empty source name" {
    assert AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(CallableSourceFunction("F"))
    assert AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(
        CallableSourceFunction("Namespace.Type.Member")
    )

    // Whitespace is a name; absent and empty are not.
    assert AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(CallableSourceFunction(" "))
    assert !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(CallableSourceFunction(null))
    assert !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(CallableSourceFunction(""))

    // The SYNTHETIC name is never consulted — only a lambda lacks a SOURCE name.
    lambda := new FunctionTypeInfo()
    lambda.SyntheticName = "lambda"
    assert !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(lambda)
}

test "callable-reference classification unions method groups with named source functions" {
    probe := CallableProbeMethod()

    // Every method-group shape is a callable reference.
    assert AnalyzerCallableReferenceFacts.IsCallableReferenceType(new ReflectionMethodInfo(probe))

    methods := new MethodInfo[](1)
    methods[0] = probe
    assert AnalyzerCallableReferenceFacts.IsCallableReferenceType(new ReflectionMethodGroupInfo(methods))
    assert AnalyzerCallableReferenceFacts.IsCallableReferenceType(
        new NSharpMethodGroupInfo(new List<FunctionTypeInfo>())
    )

    // A NAMED source function is a callable reference; a LAMBDA is a value and is not.
    assert AnalyzerCallableReferenceFacts.IsCallableReferenceType(CallableSourceFunction("F"))
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(CallableSourceFunction(null))
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(CallableSourceFunction(""))

    // A delegate-TYPED value is not a callable reference — it is already a value.
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(new ReflectionTypeInfo(typeof(Action)))
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(
        new GenericTypeInfo("Func", CallableTypeArguments(1))
    )
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(BuiltInTypes.Object)
    assert !AnalyzerCallableReferenceFacts.IsCallableReferenceType(BuiltInTypes.Null)
}

test "runtime delegate classification excludes the two abstract delegate roots" {
    // Concrete delegates, generic and non-generic, open and closed.
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(Action))
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(Action<int>))
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(Func<int>))
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(Func<int, string>))
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.Predicate`1")
    )
    assert AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.EventHandler")
    )

    // The abstract roots have no invocation signature and are excluded by name of identity.
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.Delegate")
    )
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.MulticastDelegate")
    )

    // Non-delegates, including the other abstract CLR roots and an array OF delegates.
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(object))
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(int))
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(string))
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.ValueType")
    )
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.Enum")
    )
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(
        CallableRequiredCoreType("System.Array")
    )
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(List<int>))
    assert !AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(typeof(Exception))
}

test "the delegate parameter modifier read is total over absent and short modifier lists" {
    absent := CallableModifierFunction(null)
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(absent, 0) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(absent, 5) == Ast.ParameterModifier.None

    empty := CallableModifierFunction(new List<Ast.ParameterModifier>())
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(empty, 0) == Ast.ParameterModifier.None

    values := new Ast.ParameterModifier[](4)
    values[0] = Ast.ParameterModifier.None
    values[1] = Ast.ParameterModifier.Ref
    values[2] = Ast.ParameterModifier.Out
    values[3] = Ast.ParameterModifier.Params
    populated := CallableModifierFunction(CallableModifierList(values))

    index := 0
    while index < values.Length {
        actual := AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(populated, index)
        if actual != values[index] {
            throw new InvalidOperationException(
                "Parameter modifier read disagreed at index " + index.ToString() + "."
            )
        }

        index += 1
    }

    // Reading PAST the list is `None`, not a fault: an unmodified trailing parameter is the norm.
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(populated, 4) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(populated, 99) == Ast.ParameterModifier.None

    // And reading BEFORE it is `None` too — the guard the completion engine's deleted copy carried
    // (task 019 slice 1). Without it this is an index fault, not an answer.
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(populated, -1) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(populated, -99) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(absent, -1) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(empty, -1) == Ast.ParameterModifier.None
}

test "delegate signature matching erases params and keeps ref and out" {
    // `params` is a call-site convenience, not part of the signature.
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Params) == Ast.ParameterModifier.None

    // Everything else is load-bearing and survives unchanged.
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.None) == Ast.ParameterModifier.None
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Ref) == Ast.ParameterModifier.Ref
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Out) == Ast.ParameterModifier.Out

    // The erasure makes a params arity match a plain one, and does NOT collapse ref into out.
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Params) == AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.None)
    assert AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Ref) != AnalyzerCallableReferenceFacts.NormalizeDelegateParameterModifier(Ast.ParameterModifier.Out)
}

test "Func reifies its last type argument as the return type" {
    arity := 1
    while arity <= 4 {
        arguments := CallableTypeArguments(arity)
        signature := AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
            new GenericTypeInfo("Func", arguments)
        )
        if signature == null {
            throw new InvalidOperationException(
                "Func<> of arity " + arity.ToString() + " must reify."
            )
        }

        parameterTypes := signature.ParameterTypes
        if parameterTypes == null || parameterTypes.Count != arity - 1 {
            throw new InvalidOperationException(
                "Func<> of arity " + arity.ToString() + " must take all but its last argument."
            )
        }

        modifiers := signature.ParameterModifiers
        if modifiers == null || modifiers.Count != arity - 1 {
            throw new InvalidOperationException(
                "Func<> of arity " + arity.ToString() + " must carry one modifier per parameter."
            )
        }

        index := 0
        while index < modifiers.Count {
            // The type arguments are carried through by identity, and every modifier is `None`.
            assert parameterTypes[index] == arguments[index]
            assert modifiers[index] == Ast.ParameterModifier.None
            index += 1
        }

        assert CallableSimpleName(signature.ReturnType) == CallableSimpleName(arguments[arguments.Count - 1])
        arity += 1
    }

    // `Func` with no type arguments has no return type to take, so it does not reify.
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("Func", CallableTypeArguments(0))
    ) == null
}

test "Action reifies every type argument as a parameter and returns void" {
    arity := 0
    while arity <= 4 {
        arguments := CallableTypeArguments(arity)
        signature := AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
            new GenericTypeInfo("Action", arguments)
        )
        if signature == null {
            throw new InvalidOperationException(
                "Action<> of arity " + arity.ToString() + " must reify."
            )
        }

        parameterTypes := signature.ParameterTypes
        if parameterTypes == null || parameterTypes.Count != arity {
            throw new InvalidOperationException(
                "Action<> of arity " + arity.ToString() + " must take every argument."
            )
        }

        modifiers := signature.ParameterModifiers
        if modifiers == null || modifiers.Count != arity {
            throw new InvalidOperationException(
                "Action<> of arity " + arity.ToString() + " must carry one modifier per parameter."
            )
        }

        index := 0
        while index < parameterTypes.Count {
            assert parameterTypes[index] == arguments[index]
            assert modifiers[index] == Ast.ParameterModifier.None
            index += 1
        }

        // Unlike Func, the return type is always void — never the last type argument.
        assert CallableSimpleName(signature.ReturnType) == "void"
        arity += 1
    }
}

test "only Func and Action reify; every other generic name declines" {
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("Predicate", CallableTypeArguments(1))
    ) == null
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("List", CallableTypeArguments(1))
    ) == null
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("", CallableTypeArguments(1))
    ) == null

    // The match is on the SIMPLE name and is case-sensitive; a qualified spelling is not a match.
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("System.Func", CallableTypeArguments(2))
    ) == null
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("System.Action", CallableTypeArguments(1))
    ) == null
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("func", CallableTypeArguments(2))
    ) == null
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("action", CallableTypeArguments(1))
    ) == null

    // Resolution identity wins over the spelling: a source-defined nominal Func is not the CLR
    // delegate merely because it has the same simple name.
    assert AnalyzerCallableReferenceFacts.CreateFunctionTypeInfoFromGenericDelegate(
        new GenericTypeInfo("Func", CallableTypeArguments(2), BuiltInTypes.Int)
    ) == null
}

// ── must-be-invocable-if-member ───────────────────────────────────────────────────────────────

test "IsInvocableMemberType: a method group and a signature are invocable, a plain value is not" {
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ReflectionMethodInfo(CallableProbeMethod(), "Identity(...)"))
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(CallableSourceFunction("Probe"))
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(BuiltInTypes.Int)
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(BuiltInTypes.String)
}

test "IsInvocableMemberType: Func and Action are invocable however they are spelled, other generics are not" {
    functionArguments := new List<TypeInfo>()
    functionArguments.Add(BuiltInTypes.String)
    functionArguments.Add(BuiltInTypes.Bool)
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new GenericTypeInfo("Func", functionArguments, null))

    actionArguments := new List<TypeInfo>()
    actionArguments.Add(BuiltInTypes.String)
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new GenericTypeInfo("Action", actionArguments, null))

    listArguments := new List<TypeInfo>()
    listArguments.Add(BuiltInTypes.String)
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(new GenericTypeInfo("List", listArguments, null))
}

test "IsInvocableMemberType: the wrappers are read through, because they do not change what the value IS" {
    functionArguments := new List<TypeInfo>()
    functionArguments.Add(BuiltInTypes.Bool)
    delegateType: TypeInfo = new GenericTypeInfo("Func", functionArguments, null)

    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new NullableTypeInfo(delegateType))
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ObliviousTypeInfo(delegateType))
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(new NullableTypeInfo(BuiltInTypes.Int))
}

test "IsInvocableMemberType: a reflected delegate is invocable and a reflected value type is not" {
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ReflectionTypeInfo(typeof(Action)))
    assert AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ReflectionTypeInfo(typeof(Predicate<string>)))
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ReflectionTypeInfo(typeof(int)))
    assert !AnalyzerCallableReferenceFacts.IsInvocableMemberType(new ReflectionTypeInfo(typeof(List<int>)))
}

// The roots themselves are not delegates: neither names a callable signature.
test "IsMetadataDelegateType: the base chain decides, and the two abstract roots are not delegates" {
    assert AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(Action))
    assert AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(Func<int, int>))
    assert AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(Predicate<int>))
    assert !AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(Delegate))
    assert !AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(MulticastDelegate))
    assert !AnalyzerCallableReferenceFacts.IsMetadataDelegateType(typeof(string))
}

test "generic delegate parameter names come from the framework Invoke metadata" {
    funcNames := AnalyzerCallableReferenceFacts.FrameworkDelegateParameterNames(true, 1)
    assert funcNames != null
    assert funcNames.Count == 1
    assert funcNames[0] == "arg"

    actionNames := AnalyzerCallableReferenceFacts.FrameworkDelegateParameterNames(false, 1)
    assert actionNames != null
    assert actionNames.Count == 1
    assert actionNames[0] == "obj"

    pairNames := AnalyzerCallableReferenceFacts.FrameworkDelegateParameterNames(true, 2)
    assert pairNames != null
    assert pairNames[0] == "arg1"
    assert pairNames[1] == "arg2"
    wideNames := AnalyzerCallableReferenceFacts.FrameworkDelegateParameterNames(true, 6)
    assert wideNames != null
    assert wideNames.Count == 6
    assert wideNames[0] == "arg1"
    assert wideNames[5] == "arg6"
}
