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
class AnalyzerCallableReferenceFacts {

    // True when the value is a bare reference to code rather than a value of a delegate type: one of
    // the three method-group shapes, or a FunctionTypeInfo that carries a source function's identity
    // (a lambda does not). Such a value must be called, or converted to a delegate.
    static func IsCallableReferenceType(candidate: TypeInfo): bool {
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
    static func IsMethodGroupReferenceType(candidate: TypeInfo): bool {
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
    static func HasSourceFunctionIdentity(functionType: FunctionTypeInfo): bool {
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
    static func IsRuntimeDelegateType(candidate: Type): bool {
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

    // A DELEGATE TYPE AS METADATA SEES IT, which is not the same question `IsRuntimeDelegateType`
    // answers. That one compares against the RUNTIME's own roots and therefore says `false` for
    // every type loaded into a `MetadataLoadContext` — deliberately, because the values it
    // classifies are runtime ones. A type read off the project's reference set has no runtime
    // identity at all, so its base chain is walked and the roots are recognised by NAME.
    static func IsMetadataDelegateType(candidate: Type): bool {
        // The two abstract roots are excluded for the same reason `IsRuntimeDelegateType` excludes
        // them: neither names a callable signature, and `MulticastDelegate` would otherwise answer
        // true off its own base.
        candidateName := candidate.get_FullName()
        if candidateName == "System.Delegate" || candidateName == "System.MulticastDelegate" {
            return false
        }

        current: Type? = AnalyzerReflectionMemberProbe.BaseTypeOrNull(candidate)
        depth := 0
        while current != null && depth < 32 {
            fullName := current.get_FullName()
            if fullName == "System.MulticastDelegate" || fullName == "System.Delegate" {
                return true
            }

            current = AnalyzerReflectionMemberProbe.BaseTypeOrNull(current)
            depth = depth + 1
        }

        return false
    }

    // WHETHER A MEMBER OF THIS TYPE CAN STAND WHERE A CALL NAMES ITS TARGET — C#'s
    // "must be invocable if member" rule, stated over N#'s type shapes.
    //
    // A method group always can. A VALUE can only when its type is a delegate: `Func<…>`/`Action<…>`
    // however they are spelled, a delegate read out of metadata, and a signature the analyzer has
    // already reduced to a `FunctionTypeInfo`. Everything else — an `int` property called `Count`,
    // a `string` field — is NOT a candidate for `receiver.Name(args)` and must not hide the method
    // or extension of the same name, which is exactly what `list.Count(predicate)` depends on.
    //
    // The wrappers are read through because they do not change what the value IS.
    static func IsInvocableMemberType(candidate: TypeInfo): bool {
        if IsMethodGroupReferenceType(candidate) {
            return true
        }

        if candidate as FunctionTypeInfo != null {
            return true
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return IsInvocableMemberType(oblivious.InnerType)
        }

        nullable := candidate as NullableTypeInfo
        if nullable != null {
            return IsInvocableMemberType(nullable.InnerType)
        }

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            return CreateFunctionTypeInfoFromGenericDelegate(genericType) != null
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return IsMetadataDelegateType(reflectionType.Type) || IsRuntimeDelegateType(reflectionType.Type)
        }

        return false
    }

    // WHAT TO CALL A CALLABLE REFERENCE IN A DIAGNOSTIC.
    //
    // What the user WROTE wins, because that is the text they have to change: an identifier names
    // itself, and a member access names its member. Only when the expression is neither — a call
    // result, an index, a synthesised node — does the TYPE get to answer, and there the first
    // candidate's name is the best available approximation of a group that has not been resolved.
    // The transparent wrappers are peeled first, so `(f)` names `f` exactly as `f` does.
    static func GetCallableReferenceName(expression: Expression, candidate: TypeInfo): string {
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
    // modifier list or the index falls outside it. The read is TOTAL in both directions: a negative
    // index is `None`, not a fault. (The completion engine's own copy of this rule carried the
    // `index < 0` arm and the analyzer's did not; task 019 slice 1 deleted the copy and kept the
    // wider guard, because the two callers must not disagree about what an out-of-range read means.)
    static func GetFunctionParameterModifier(functionType: FunctionTypeInfo, index: int): ParameterModifier {
        modifiers := functionType.ParameterModifiers
        if modifiers == null || index < 0 || index >= modifiers.Count {
            return ParameterModifier.None
        }

        return modifiers[index]
    }

    // `params` is a call-site convenience, not part of a delegate's signature, so it erases to `None`
    // before two signatures' modifiers are compared. `ref` and `out` are load-bearing and are kept.
    static func NormalizeDelegateParameterModifier(modifier: ParameterModifier): ParameterModifier {
        if modifier == ParameterModifier.Params {
            return ParameterModifier.None
        }

        return modifier
    }

    // Reads a `Func<T1..Tn, TResult>` or `Action<T1..Tn>` as a function signature. `Func` takes its
    // last type argument as the return type and needs at least one; `Action` takes them all as
    // parameters and returns `void`. Any other generic name is not a delegate shape — null.
    static func CreateFunctionTypeInfoFromGenericDelegate(delegateType: GenericTypeInfo): FunctionTypeInfo? {
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

        // A resolved source type named Func/Action is its own nominal type. Only the framework
        // definitions have the structural delegate reading below; null is retained for hand-built
        // analyzer facts that deliberately carry no resolution identity.
        resolvedDefinition := delegateType.GenericDefinition
        if resolvedDefinition != null && !IsFrameworkDelegateDefinition(resolvedDefinition, isFunc, parameterCount) {
            return null
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
        signature.ParameterNames = FrameworkDelegateParameterNames(isFunc, parameterCount)
        if isFunc {
            signature.ReturnType = arguments[arguments.Count - 1]
        } else {
            signature.ReturnType = BuiltInTypes.Void
        }

        return signature
    }

    // The names declared by the framework's generic delegate Invoke methods, read from the open
    // definition selected by arity. This keeps optimized analyzer paths on metadata's identity.
    static func IsFrameworkDelegateDefinition(candidate: TypeInfo, isFunc: bool, parameterCount: int): bool {
        reflected := candidate as ReflectionTypeInfo
        if reflected == null {
            return false
        }
        expected := FrameworkDelegateDefinition(isFunc, parameterCount)
        return expected != null && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(reflected.Type, expected)
    }

    static func FrameworkDelegateDefinition(isFunc: bool, parameterCount: int): Type? {
        if parameterCount < 0 {
            return null
        }

        fullName := ""
        if isFunc {
            fullName = "System.Func`" + (parameterCount + 1).ToString()
        } else if parameterCount == 0 {
            fullName = "System.Action"
        } else {
            fullName = "System.Action`" + parameterCount.ToString()
        }
        return typeof(Action).Assembly.GetType(fullName)
    }

    static func FrameworkDelegateParameterNames(isFunc: bool, parameterCount: int): List<string>? {
        representative := FrameworkDelegateDefinition(isFunc, parameterCount)
        if representative == null {
            return null
        }
        invoke := representative.GetMethod("Invoke")
        if invoke == null {
            return null
        }
        parameters := invoke.GetParameters()
        if parameters.Length != parameterCount {
            return null
        }
        names := new List<string>()
        index := 0
        while index < parameters.Length {
            names.Add(parameters[index].get_Name() ?? "")
            index += 1
        }
        return names
    }
}
