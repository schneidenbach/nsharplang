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

    constructor(mode: ColumnarLambdaPlacementMode, method: MethodBuilder, ownerTypeForBody: TypeBuilder) {
        if method == null || ownerTypeForBody == null {
            throw new InvalidOperationException("Lambda placement requires a synthesized method and its body owner.")
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

    constructor(ordinals: Dictionary<string, int>, parameterTypesByName: Dictionary<string, Type>, bodyNode: int) {
        if ordinals == null || parameterTypesByName == null {
            throw new InvalidOperationException("A contextual-lambda signature requires its ordinal and parameter-type maps.")
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
    static func PlanContextualSignature(nodes: ColumnarNodeTable, source: string, lambdaNode: int, parameterTypes: Type[], visibleBindingNames: HashSet<string>): ColumnarLambdaSignature? {
        if nodes == null || source == null || parameterTypes == null || visibleBindingNames == null {
            throw new InvalidOperationException("Contextual-lambda signature planning requires the node table, source, delegate parameter types, and visible bindings.")
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

    // Collect the CAPTURE SET of a contextual lambda body: the enclosing-scope names the body reads and
    // closes over. A capture is a kind-6 identifier that resolves in the enclosing local/parameter/lifted
    // name set (the host passes the union) and is NOT bound by this lambda's — or a nested lambda's — own
    // parameters. The host passes the lambda's own parameter names as the initial bound set and the union
    // of its enclosing locals/parameters/lifted names as the capturable set; N# owns the pure AST scan and
    // returns the captured names. The host's non-capturing-vs-capturing branch consumes the result — an
    // empty set is the static lowering, a non-empty set drives the display-class capture. The this-capture
    // member-chain scan and the display-class emission stay mechanical in the host.
    static func PlanCaptureSet(nodes: ColumnarNodeTable, source: string, bodyNode: int, boundParameterNames: HashSet<string>, enclosingCapturableNames: HashSet<string>): HashSet<string> {
        if nodes == null || source == null || boundParameterNames == null || enclosingCapturableNames == null {
            throw new InvalidOperationException("Contextual-lambda capture-set planning requires the node table, source, bound parameter names, and enclosing capturable names.")
        }

        captures := new HashSet<string>(StringComparer.Ordinal)
        CollectContextualLambdaCaptures(nodes, source, bodyNode, boundParameterNames, enclosingCapturableNames, captures)
        return captures
    }

    // The recursive capture walk. TYPE-kernel subtrees never contribute a value name: a generic callee
    // (kind 38 — its name lives in the value span), a bare-new (kind 42), and a typeof (kind 55) are
    // skipped outright; the type child of a new-expression (kind 15) / cast (kind 16) and the type child of
    // `is`/`as` (kind 46/47) are stepped over. A nested lambda (kind 39) binds its own parameter names
    // before its body is walked, so those names shadow the enclosing scope inside it. A kind-6 identifier
    // with a real value span is captured when it is unbound here and lives in the enclosing capturable set;
    // a value-less identifier is a masquerading TYPE node and is never a name read.
    static func CollectContextualLambdaCaptures(nodes: ColumnarNodeTable, source: string, node: int, bound: HashSet<string>, enclosingCapturableNames: HashSet<string>, captures: HashSet<string>) {
        kind := nodes.Kind(node)
        if kind == 38 || kind == 42 || kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            return
        }

        if kind == 39 {
            nestedBound := new HashSet<string>(StringComparer.Ordinal)
            for existing in bound {
                nestedBound.Add(existing)
            }

            nestedParameterCount := nodes.ChildCount(node) - 1
            p := 0
            while p < nestedParameterCount {
                parameterNode := nodes.Child(node, p)
                if nodes.Kind(parameterNode) == ColumnarExpressionNodeKind.IdentifierExpression() {
                    nestedBound.Add(nodes.Text(source, parameterNode))
                }

                p = p + 1
            }

            CollectContextualLambdaCaptures(nodes, source, nodes.Child(node, nestedParameterCount), nestedBound, enclosingCapturableNames, captures)
            return
        }

        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ValueStart(node) >= 0 {
                name := nodes.Text(source, node)
                if !bound.Contains(name) && enclosingCapturableNames.Contains(name) {
                    captures.Add(name)
                }
            }
        }

        if kind == 46 || kind == 47 {
            CollectContextualLambdaCaptures(nodes, source, nodes.Child(node, 0), bound, enclosingCapturableNames, captures)
            return
        }

        first := 0
        if kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.CastExpression() {
            first = 1
        }

        childCount := nodes.ChildCount(node)
        c := first
        while c < childCount {
            CollectContextualLambdaCaptures(nodes, source, nodes.Child(node, c), bound, enclosingCapturableNames, captures)
            c = c + 1
        }
    }

    // Select the RETURN TYPE of a single-parameter contextual delegate argument, or decline. A selector or
    // predicate like the one `Select`/`Where` takes has no written return type; its return type is the type
    // the argument's body produces. N# owns the SELECTION between the two admitted argument forms — a
    // contextual lambda literal whose body the host has mechanically preflighted, and a visible
    // local-function method group. The host resolves each form's candidate return type mechanically (the
    // lambda candidate is the host's scoped sub-emitter body-preflight result, already gated to a supported
    // non-void type; the local-function candidate is the resolved method-group return, already gated to a
    // supported non-void type with a single parameter equivalent to the source element type) and passes
    // null for a form that does not apply. The lambda form takes precedence; a null result is the standard
    // inference decline the host reports. The body preflight and the reflection-bound validity/equivalence
    // checks stay mechanical in the host — this owns only which candidate the return type comes from.
    static func PlanSingleParameterContextualReturnType(lambdaBodyReturnType: Type?, localFunctionReturnType: Type?): Type? {
        if lambdaBodyReturnType != null {
            return lambdaBodyReturnType
        }

        return localFunctionReturnType
    }

    // Select the owning type, generated-method identity, and visibility for one non-capturing lambda
    // body and define the synthesized method. Returns null to decline — an invalid synthesized signature,
    // or a value-type/constructor-body `this` capture that cannot bind a delegate directly to the current
    // instance — so the mechanical host reports the standard lambda decline. hasThisCapture is the host's
    // resolved fact that the body references the enclosing reference type's member chain (and so needs
    // `this`); when false the lambda is program-static.
    static func PlanNonCapturingPlacement(programType: TypeBuilder, enclosing: ColumnarStructDef?, lambdaCounter: int[], isConstructorBody: bool, visibleTypeParameters: Dictionary<string, Type>, returnType: Type, parameterTypes: Type[], hasThisCapture: bool): ColumnarLambdaPlacement? {
        if programType == null || lambdaCounter == null || visibleTypeParameters == null || returnType == null || parameterTypes == null {
            throw new InvalidOperationException("Lambda placement planning requires non-null placement facts.")
        }

        if hasThisCapture {
            // A reference `this` binds the delegate directly to the current instance; a value-type or
            // constructor-body `this` would bind a copy with different mutation semantics — decline.
            if enclosing == null || !enclosing.IsReference || isConstructorBody {
                return null
            }
            if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(returnType, parameterTypes, enclosing.Builder) {
                return null
            }
            // MethodAttributes.Private (0x0001) | MethodAttributes.HideBySig (0x0080): a private instance
            // method, same-type ldftn'd with the receiver, so private visibility is sufficient.
            instanceMethod := enclosing.Builder.DefineMethod(NextLambdaMethodName(lambdaCounter), (MethodAttributes)129, returnType, parameterTypes)
            placement := new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.InstanceThis, instanceMethod, enclosing.Builder)
            placement.CurrentStructForBody = enclosing
            placement.OrdinalShift = 1
            placement.TypeParametersForBody = ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(visibleTypeParameters, enclosing.Builder)
            return placement
        }

        if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(returnType, parameterTypes, programType) {
            return null
        }
        staticMethod := DefineProgramStaticLambda(programType, lambdaCounter, returnType, parameterTypes)
        return new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.StaticProgram, staticMethod, programType)
    }

    // Define the assembly-static program method that hosts a non-capturing lambda body.
    static func DefineProgramStaticLambda(programType: TypeBuilder, lambdaCounter: int[], returnType: Type, parameterTypes: Type[]): MethodBuilder {
        if programType == null || lambdaCounter == null || returnType == null || parameterTypes == null {
            throw new InvalidOperationException("Static lambda definition requires a program type and signature.")
        }
        return programType.DefineMethod(NextLambdaMethodName(lambdaCounter), StaticLambdaAttributes(), returnType, parameterTypes)
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
