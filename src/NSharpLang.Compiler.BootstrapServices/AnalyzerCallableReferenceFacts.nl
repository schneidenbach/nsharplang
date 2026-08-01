namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// The analyzer's CALLABLE / DELEGATE-REFERENCE classification family.
//
// These decide what a value that names code IS: a bare method reference (a "method group", which is
// not a value and may only be called or converted to a delegate), a named source function, a CLR
// delegate type, or a `Func<...>`/`Action<...>` shape that can be read as a signature. Together with
// the delegate-parameter-modifier reads they are the leaf policy under the analyzer's assignability
// decision and under the `MethodGroupUsedAsValue` diagnostic.
//
// Every rule here is an exact, total function of its inputs — no analyzer state, no name resolution,
// no diagnostics, no recovery. Do not reintroduce any of them in C#, and do not grow this class
// beyond the callable/delegate family; the rest of the assignability closure lands in sibling
// owners.

public class AnalyzerCallableReferenceFacts {

    // True when the value is a bare reference to code rather than a value of a delegate type: one of
    // the three method-group shapes, or a FunctionTypeInfo that carries a source function's identity
    // (a lambda does not). Such a value must be called, or converted to a delegate.
    public static func IsCallableReferenceType(candidate: TypeInfo): bool {
        if IsMethodGroupReferenceType(candidate) {
            return true
        }

        functionType := candidate as FunctionTypeInfo
        if functionType == null {
            return false
        }

        return HasSourceFunctionIdentity(functionType)
    }

    // The three TypeInfo shapes that denote an unresolved group of candidate methods: a single
    // reflection method, a reflection method group, and an N# source method group.
    public static func IsMethodGroupReferenceType(candidate: TypeInfo): bool {
        reflectionMethod := candidate as ReflectionMethodInfo
        if reflectionMethod != null {
            return true
        }

        reflectionGroup := candidate as ReflectionMethodGroupInfo
        if reflectionGroup != null {
            return true
        }

        sourceGroup := candidate as NSharpMethodGroupInfo
        return sourceGroup != null
    }

    // True when the function type came from a DECLARED source function rather than a lambda: only a
    // declaration records the source name. This is the method-group-versus-lambda discriminator.
    public static func HasSourceFunctionIdentity(functionType: FunctionTypeInfo): bool {
        return !string.IsNullOrEmpty(functionType.SourceName)
    }

    // True for a concrete CLR delegate type. The two abstract roots are excluded: neither
    // `System.Delegate` nor `System.MulticastDelegate` has an invocation signature to bind against.
    //
    // The roots are read out of the core library rather than written `typeof(Delegate)` because the
    // columnar front end's `typeof` surface does not carry them, and extending that surface is a
    // compiler-capability change that would need a two-stage bootstrap. This is the established
    // `typeof(object).get_Assembly()` idiom, and it yields the identical runtime Type instances — so
    // the RUNTIME-versus-MetadataLoadContext asymmetry is preserved exactly: a delegate type loaded
    // into a MetadataLoadContext is NOT reference-equal to the runtime roots and, like the C# this
    // replaces, answers false.
    public static func IsRuntimeDelegateType(candidate: Type): bool {
        coreLibrary := typeof(object).get_Assembly()
        delegateRoot := coreLibrary.GetType("System.Delegate")
        if delegateRoot == null {
            return false
        }

        isDelegate := delegateRoot.IsAssignableFrom(candidate)
        if !isDelegate {
            return false
        }

        multicastRoot := coreLibrary.GetType("System.MulticastDelegate")
        return candidate != delegateRoot && candidate != multicastRoot
    }

    // WHAT TO CALL A CALLABLE REFERENCE IN A DIAGNOSTIC.
    //
    // What the user WROTE wins, because that is the text they have to change: an identifier names
    // itself, and a member access names its member. Only when the expression is neither — a call
    // result, an index, a synthesised node — does the TYPE get to answer, and there the first
    // candidate's name is the best available approximation of a group that has not been resolved.
    // The transparent wrappers are peeled first, so `(f)` names `f` exactly as `f` does.
    public static func GetCallableReferenceName(expression: Expression, candidate: TypeInfo): string {
        unwrapped := AnalyzerConstantExpressionFacts.UnwrapTransparentWrappers(expression)

        identifier := unwrapped as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := unwrapped as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        reflectionMethod := candidate as ReflectionMethodInfo
        if reflectionMethod != null {
            return reflectionMethod.Method.get_Name()
        }

        reflectionGroup := candidate as ReflectionMethodGroupInfo
        if reflectionGroup != null && reflectionGroup.Methods.Length > 0 {
            return reflectionGroup.Methods[0].get_Name()
        }

        sourceGroup := candidate as NSharpMethodGroupInfo
        if sourceGroup != null {
            functions := NSharpMethodGroupInfoFactory.GetFunctions(sourceGroup)
            if functions.Count > 0 {
                firstSyntheticName := functions[0].SyntheticName
                if firstSyntheticName != null {
                    return firstSyntheticName
                }

                return "method"
            }
        }

        functionType := candidate as FunctionTypeInfo
        if functionType != null {
            syntheticName := functionType.SyntheticName
            if syntheticName != null && syntheticName.Length > 0 {
                return syntheticName
            }
        }

        return "method"
    }

    // The declared modifier of parameter `index`, or `None` when the function type carries no
    // modifier list or the list is shorter than the parameter list.
    public static func GetFunctionParameterModifier(functionType: FunctionTypeInfo, index: int): ParameterModifier {
        modifiers := functionType.ParameterModifiers
        if modifiers == null || index >= modifiers.Count {
            return ParameterModifier.None
        }

        return modifiers[index]
    }

    // `params` is a call-site convenience, not part of a delegate's signature, so it erases to `None`
    // before two signatures' modifiers are compared. `ref` and `out` are load-bearing and are kept.
    public static func NormalizeDelegateParameterModifier(modifier: ParameterModifier): ParameterModifier {
        if modifier == ParameterModifier.Params {
            return ParameterModifier.None
        }

        return modifier
    }

    // Reads a `Func<T1..Tn, TResult>` or `Action<T1..Tn>` as a function signature. `Func` takes its
    // last type argument as the return type and needs at least one; `Action` takes them all as
    // parameters and returns `void`. Any other generic name is not a delegate shape — null.
    public static func CreateFunctionTypeInfoFromGenericDelegate(delegateType: GenericTypeInfo): FunctionTypeInfo? {
        name := delegateType.Name
        isFunc := name == "Func"
        if !isFunc && name != "Action" {
            return null
        }

        arguments := delegateType.TypeArguments
        if isFunc && arguments.Count == 0 {
            return null
        }

        parameterCount := arguments.Count
        if isFunc {
            parameterCount = arguments.Count - 1
        }

        parameterTypes := new List<TypeInfo>()
        parameterModifiers := new List<ParameterModifier>()
        index := 0
        while index < parameterCount {
            parameterTypes.Add(arguments[index])
            parameterModifiers.Add(ParameterModifier.None)
            index += 1
        }

        signature := new FunctionTypeInfo()
        signature.ParameterTypes = parameterTypes
        signature.ParameterModifiers = parameterModifiers
        if isFunc {
            signature.ReturnType = arguments[arguments.Count - 1]
        } else {
            signature.ReturnType = BuiltInTypes.Void
        }

        return signature
    }
}
