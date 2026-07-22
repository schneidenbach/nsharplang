namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Lambda definition placement and visibility is a semantic decision, not an emission mechanic. Given
// the captured-binding facts a lambda body resolves against its enclosing scope, N# selects the owning
// type, the generated method identity, and the exact CLR visibility, and it defines the synthesized
// method directly. A non-capturing lambda lowers to one of two CLR shapes:
//   * StaticProgram — no captures and no enclosing-instance reference: an assembly-visible static
//     method on the program type. It is ldftn'd cross-type from any sibling body, so its visibility
//     MUST be assembly (internal); a private static method here throws MethodAccessException at JIT.
//   * InstanceThis — no local/parameter captures but a bare reference to the enclosing reference type's
//     member chain: a private instance method on that type, bound directly to `this` at the use site.
// The C# emitter host resolves the raw capture facts (delegate signature, capture set, this-reference)
// and emits the recursive body through its sub-emitter; it never re-derives which type owns the method,
// what it is named, or how visible it is. The delegate is then constructed mechanically from the method
// N# selected. Value-capture (display-class) lowering is not modeled here and remains a fenced host
// residual until the columnar backend models the reflection-emit surface a display class needs.
enum ColumnarLambdaPlacementMode {
    StaticProgram,
    InstanceThis
}

// The resolved placement for one non-capturing lambda body. The host consumes the synthesized method
// and the body-scope facts to run its recursive sub-emitter, then constructs the delegate over Method:
// a StaticProgram placement uses `ldnull; ldftn Method`, an InstanceThis placement uses
// `ldarg.0; ldftn <Method bound to the enclosing generic context>`.
class ColumnarLambdaPlacement {
    Mode: ColumnarLambdaPlacementMode
    // The synthesized method whose IL stream the host fills with the lambda body and whose exact handle
    // is the ldftn target.
    Method: MethodBuilder
    // The type whose generic/type-resolution context the body sub-emitter binds to (the program type for
    // a static method, the enclosing type for a this-capture).
    OwnerTypeForBody: TypeBuilder
    // The current-instance definition the body sub-emitter runs under: null for the static program
    // method, the enclosing type for a this-capture.
    CurrentStructForBody: ColumnarStructDef?
    // Argument-ordinal shift for the body: 0 for the static method, 1 for the this-capture instance
    // method whose arg 0 is the receiver.
    OrdinalShift: int
    // Only the this-capture body binds the enclosing type's owned type parameters; the static shape
    // leaves this null so the sub-emitter uses its default (no method/enclosing type parameters).
    TypeParametersForBody: Dictionary<string, Type>?

    constructor(
        mode: ColumnarLambdaPlacementMode,
        method: MethodBuilder,
        ownerTypeForBody: TypeBuilder) {
        if method == null || ownerTypeForBody == null {
            throw new InvalidOperationException(
                "Lambda placement requires a synthesized method and its body owner.")
        }
        Mode = mode
        Method = method
        OwnerTypeForBody = ownerTypeForBody
        CurrentStructForBody = null
        OrdinalShift = 0
        TypeParametersForBody = null
    }
}

// The contextual-lambda parameter-signature binding for one lambda literal. A lambda's parameter
// types are not written in source; they are the TARGET delegate's parameter types, bound positionally
// to the lambda's parameter NAMES. N# owns that binding and the language rules it enforces — the
// parameter count must match the delegate arity, each parameter node must be an identifier, a repeated
// parameter name is malformed, and a parameter that shadows a name already visible in the enclosing
// scope is the pipeline's NL316. The C# host supplies the delegate's decomposed parameter types (its
// mechanical delegate-signature reflection) and the enclosing visible-binding names, and consumes the
// ordinals and per-name types to drive the lambda body sub-emitter; BodyNode is the lambda body child.
class ColumnarLambdaSignature {
    // Parameter name -> zero-based ordinal, in declaration order.
    Ordinals: Dictionary<string, int>
    // Parameter name -> its contextual type (the target delegate's parameter type at that ordinal).
    ParameterTypesByName: Dictionary<string, Type>
    // The lambda body node — the child after the last parameter.
    BodyNode: int

    constructor(
        ordinals: Dictionary<string, int>,
        parameterTypesByName: Dictionary<string, Type>,
        bodyNode: int) {
        if ordinals == null || parameterTypesByName == null {
            throw new InvalidOperationException(
                "A contextual-lambda signature requires its ordinal and parameter-type maps.")
        }
        Ordinals = ordinals
        ParameterTypesByName = parameterTypesByName
        BodyNode = bodyNode
    }
}

class ColumnarLambdaPlacementPlanner {
    // Bind a lambda literal's parameters to the target delegate's parameter types, or decline. The host
    // passes the delegate's decomposed parameter types (from its mechanical delegate-signature
    // reflection) and the names already visible where the lambda is written; N# owns the arity match,
    // the identifier-node requirement, duplicate-name malformedness, and the NL316 enclosing shadow, and
    // returns the parameter ordinals, per-name types, and the body node. A null result is the standard
    // lambda decline. This owns only the signature decision; the delegate decomposition and return type,
    // the body emission, and the delegate construction stay mechanical in the host.
    public static func PlanContextualSignature(
        nodes: ColumnarNodeTable,
        source: string,
        lambdaNode: int,
        parameterTypes: Type[],
        visibleBindingNames: HashSet<string>): ColumnarLambdaSignature? {
        if nodes == null || source == null || parameterTypes == null || visibleBindingNames == null {
            throw new InvalidOperationException(
                "Contextual-lambda signature planning requires the node table, source, delegate parameter types, and visible bindings.")
        }

        parameterCount := nodes.ChildCount(lambdaNode) - 1
        if parameterCount != parameterTypes.Length {
            return null
        }

        ordinals := new Dictionary<string, int>(StringComparer.Ordinal)
        parameterTypesByName := new Dictionary<string, Type>(StringComparer.Ordinal)
        p := 0
        while p < parameterCount {
            parameterNode := nodes.Child(lambdaNode, p)
            if nodes.Kind(parameterNode) != ColumnarExpressionNodeKind.IdentifierExpression() {
                return null
            }

            parameterName := nodes.Text(source, parameterNode)
            if ordinals.ContainsKey(parameterName) {
                return null
            }
            if visibleBindingNames.Contains(parameterName) {
                return null
            }

            ordinals[parameterName] = p
            parameterTypesByName[parameterName] = parameterTypes[p]
            p = p + 1
        }

        return new ColumnarLambdaSignature(ordinals, parameterTypesByName, nodes.Child(lambdaNode, parameterCount))
    }

    // Select the owning type, generated-method identity, and visibility for one non-capturing lambda
    // body and define the synthesized method. Returns null to decline — an invalid synthesized signature,
    // or a value-type/constructor-body `this` capture that cannot bind a delegate directly to the current
    // instance — so the mechanical host reports the standard lambda decline. hasThisCapture is the host's
    // resolved fact that the body references the enclosing reference type's member chain (and so needs
    // `this`); when false the lambda is program-static.
    public static func PlanNonCapturingPlacement(
        programType: TypeBuilder,
        enclosing: ColumnarStructDef?,
        lambdaCounter: int[],
        isConstructorBody: bool,
        visibleTypeParameters: Dictionary<string, Type>,
        returnType: Type,
        parameterTypes: Type[],
        hasThisCapture: bool): ColumnarLambdaPlacement? {
        if programType == null || lambdaCounter == null || visibleTypeParameters == null
            || returnType == null || parameterTypes == null {
            throw new InvalidOperationException("Lambda placement planning requires non-null placement facts.")
        }

        if hasThisCapture {
            // A reference `this` binds the delegate directly to the current instance; a value-type or
            // constructor-body `this` would bind a copy with different mutation semantics — decline.
            if enclosing == null || !enclosing.IsReference || isConstructorBody {
                return null
            }
            if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
                returnType, parameterTypes, enclosing.Builder) {
                return null
            }
            // MethodAttributes.Private (0x0001) | MethodAttributes.HideBySig (0x0080): a private instance
            // method, same-type ldftn'd with the receiver, so private visibility is sufficient.
            instanceMethod := enclosing.Builder.DefineMethod(
                NextLambdaMethodName(lambdaCounter), (MethodAttributes)129, returnType, parameterTypes)
            placement := new ColumnarLambdaPlacement(
                ColumnarLambdaPlacementMode.InstanceThis, instanceMethod, enclosing.Builder)
            placement.CurrentStructForBody = enclosing
            placement.OrdinalShift = 1
            placement.TypeParametersForBody =
                ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(
                    visibleTypeParameters, enclosing.Builder)
            return placement
        }

        if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
            returnType, parameterTypes, programType) {
            return null
        }
        staticMethod := DefineProgramStaticLambda(
            programType, lambdaCounter, returnType, parameterTypes)
        return new ColumnarLambdaPlacement(
            ColumnarLambdaPlacementMode.StaticProgram, staticMethod, programType)
    }

    // Define the assembly-static program method that hosts a non-capturing lambda body.
    public static func DefineProgramStaticLambda(
        programType: TypeBuilder,
        lambdaCounter: int[],
        returnType: Type,
        parameterTypes: Type[]): MethodBuilder {
        if programType == null || lambdaCounter == null || returnType == null || parameterTypes == null {
            throw new InvalidOperationException("Static lambda definition requires a program type and signature.")
        }
        return programType.DefineMethod(
            NextLambdaMethodName(lambdaCounter), StaticLambdaAttributes(), returnType, parameterTypes)
    }

    // MethodAttributes.Assembly (0x0003) | MethodAttributes.Static (0x0010): an assembly-visible static
    // method. Cross-type ldftn from any sibling body requires assembly (internal) visibility; a private
    // static method here throws MethodAccessException at JIT.

    static func StaticLambdaAttributes(): MethodAttributes {
        return (MethodAttributes)19
    }

    static func NextLambdaMethodName(lambdaCounter: int[]): string {
        name := "<Lambda>_" + lambdaCounter[0].ToString()
        lambdaCounter[0] = lambdaCounter[0] + 1
        return name
    }
}
