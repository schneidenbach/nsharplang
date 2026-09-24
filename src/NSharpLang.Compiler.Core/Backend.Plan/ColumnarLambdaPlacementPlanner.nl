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
//   * StaticEnclosing — no value capture, and the lambda is written inside a source declaration. The
//     helper stays on that declaration so its body retains the lexical scope's CLR private access.
//   * InstanceThis — no local/parameter captures but a bare reference to the enclosing reference type's
//     member chain: a private instance method on that type, bound directly to `this` at the use site.
// N# resolves the contextual signature, ordered capture set, mutation/liftability facts, and enclosing
// instance reference before this planner selects the method placement. The C# emitter consumes those
// decisions only to emit the recursive body and display-class mechanics, then constructs the delegate
// from the method N# selected. That recursive body/display-class emission remains a fenced host residual.
enum ColumnarLambdaPlacementMode {
    StaticProgram,
    StaticEnclosing,
    InstanceThis
}

// The resolved placement for one non-capturing lambda body. The host consumes the synthesized method
// and the body-scope facts to run its recursive sub-emitter, then constructs the delegate over Method:
// a static placement uses `ldnull; ldftn Method`, while an InstanceThis placement uses
// `ldarg.0; ldftn <Method bound to the enclosing generic context>`.
class ColumnarLambdaPlacement {
    Mode: ColumnarLambdaPlacementMode
    // The synthesized method whose IL stream the host fills with the lambda body and whose exact handle
    // is the ldftn target.
    Method: MethodBuilder
    // The type whose generic/type-resolution context the body sub-emitter binds to.
    OwnerTypeForBody: TypeBuilder
    // The lexical source definition the body sub-emitter resolves under: null at file scope, the
    // enclosing type for either a type-owned static helper or a this-capture.
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

// The parameter-signature binding for one lambda literal. A contextual lambda takes its parameter
// types positionally from the target delegate; an untargeted typed lambda supplies the resolved types
// from its annotations. N# owns the shared binding and the language rules it enforces — the
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

// THE DISPLAY CLASS ONE CAPTURING LAMBDA RUNS ON, and the facts its use site needs to fill it.
//
// Two arms of the emitter build one of these: the TARGETED arm, which knows its delegate's return and
// parameter types before the body runs, and the INFERRED zero-parameter arm, which learns its return
// type FROM the body and sets the synthesized method's signature afterwards. The display itself is the
// same object in both — the same fields, the same box copies, the same `<>4__this` — so it is built
// once here rather than twice at the two call sites.
class ColumnarLambdaDisplayBuild {

    // The generated `<>c__DisplayClass<n>` and its parameterless constructor.
    Display: TypeBuilder
    DisplayCtor: ConstructorBuilder
    // The display as a member-resolution shape, so a snapshot read inside the body falls through to
    // the display's own field chain.
    DisplayDef: ColumnarStructDef
    DisplayFields: Dictionary<string, FieldBuilder>
    // The `<>4__this` field, when the body reads the enclosing instance; null otherwise.
    EnclosingThisField: FieldBuilder?
    // Captures copied BY VALUE, in the order their fields were defined.
    SnapshotNames: List<string>
    // Captures copied as a shared `StrongBox<T>` REFERENCE: the names, where each box is read from at
    // the use site (a local, or a field of the display this body itself runs on), and the display
    // fields they are stored into.
    BoxedNames: List<string>
    BoxedSourceLocals: List<LocalBuilder?>
    BoxedSourceFields: List<FieldInfo?>
    BoxedFields: FieldBuilder[]
    // The boxed captures as the body sub-emitter reads them: name -> (field, value type).
    BoxedCaptureMap: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>
    CapturesEnclosingThis: bool

    constructor(
        display: TypeBuilder,
        displayCtor: ConstructorBuilder,
        displayDef: ColumnarStructDef,
        displayFields: Dictionary<string, FieldBuilder>,
        enclosingThisField: FieldBuilder?,
        snapshotNames: List<string>,
        boxedNames: List<string>,
        boxedSourceLocals: List<LocalBuilder?>,
        boxedSourceFields: List<FieldInfo?>,
        boxedFields: FieldBuilder[],
        boxedCaptureMap: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>,
        capturesEnclosingThis: bool
    ) {
        Display = display
        DisplayCtor = displayCtor
        DisplayDef = displayDef
        DisplayFields = displayFields
        EnclosingThisField = enclosingThisField
        SnapshotNames = snapshotNames
        BoxedNames = boxedNames
        BoxedSourceLocals = boxedSourceLocals
        BoxedSourceFields = boxedSourceFields
        BoxedFields = boxedFields
        BoxedCaptureMap = boxedCaptureMap
        CapturesEnclosingThis = capturesEnclosingThis
    }

    // The boxed-capture map the body sub-emitter takes, or NOTHING when there are no boxed captures:
    // an empty map and no map mean the same thing to the sub-emitter, and it expects the second.
    func BoxedCapturesOrNull(): Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>? {
        if BoxedCaptureMap.Count == 0 {
            return null
        }

        return BoxedCaptureMap
    }
}

class ColumnarLambdaPlacementPlanner {

    // Bind a lambda literal's parameters to the target delegate's parameter types, or decline. The host
    // passes the delegate's decomposed parameter types (from its mechanical delegate-signature
    // reflection) and the names already visible where the lambda is written; N# owns the arity match,
    // the identifier-node requirement, duplicate-name malformedness, and the NL316 enclosing shadow, and
    // returns the parameter ordinals, per-name types, and the body node. A null result is the standard
    // lambda decline. This owns only the signature decision; delegate decomposition and construction
    // stay mechanical in the host, while recursive body emission remains C# lowering debt.
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
            if nodes.Kind(parameterNode) != ColumnarExpressionNodeKind.IdentifierExpression {
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
    // name set and is NOT bound by this lambda's — or a nested lambda's — own parameters.
    // ColumnarClosureBindingPlanner builds the live enclosing union and the lambda's initial bound set,
    // invokes this pure AST scan, and orders the result. An empty result selects static lowering; a
    // non-empty result enters the remaining C# display-class lowering debt.
    static func PlanCaptureSet(nodes: ColumnarNodeTable, source: string, bodyNode: int, boundParameterNames: HashSet<string>, enclosingCapturableNames: HashSet<string>): HashSet<string> {
        if nodes == null || source == null || boundParameterNames == null || enclosingCapturableNames == null {
            throw new InvalidOperationException("Contextual-lambda capture-set planning requires the node table, source, bound parameter names, and enclosing capturable names.")
        }

        captures := new HashSet<string>(StringComparer.Ordinal)
        CollectContextualLambdaCaptures(nodes, source, bodyNode, boundParameterNames, enclosingCapturableNames, captures)
        return captures
    }

    // The recursive capture walk. TYPE-kernel subtrees never contribute a value name: a bare-new
    // (kind 42) and a typeof (kind 55) are
    // skipped outright; a generic callee (kind 38) keeps its callee EXPRESSION as child 0 and its type
    // arguments after it, so only child 0 is walked — which is how `values.OfType<string>()` inside a
    // lambda captures `values`; the type child of a new-expression (kind 15) / cast (kind 16) and the type child of
    // `is`/`as` (kind 46/47) are stepped over. A nested lambda (kind 39, or the `async` spelling 78) binds its own parameter names
    // before its body is walked, so those names shadow the enclosing scope inside it. A kind-6 identifier
    // with a real value span is captured when it is unbound here and lives in the enclosing capturable set;
    // a value-less identifier is a masquerading TYPE node and is never a name read.
    static func CollectContextualLambdaCaptures(nodes: ColumnarNodeTable, source: string, node: int, bound: HashSet<string>, enclosingCapturableNames: HashSet<string>, captures: HashSet<string>) {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TypeOfExpression {
            return
        }
        if kind == ColumnarExpressionNodeKind.GenericCallee {
            CollectContextualLambdaCaptures(nodes, source, ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, node), bound, enclosingCapturableNames, captures)
            return
        }

        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            nestedBound := new HashSet<string>(StringComparer.Ordinal)
            for existing in bound {
                nestedBound.Add(existing)
            }

            nestedParameterCount := nodes.ChildCount(node) - 1
            p := 0
            while p < nestedParameterCount {
                parameterNode := nodes.Child(node, p)
                if nodes.Kind(parameterNode) == ColumnarExpressionNodeKind.IdentifierExpression {
                    nestedBound.Add(nodes.Text(source, parameterNode))
                }

                p = p + 1
            }

            CollectContextualLambdaCaptures(nodes, source, nodes.Child(node, nestedParameterCount), nestedBound, enclosingCapturableNames, captures)
            return
        }

        if kind == ColumnarExpressionNodeKind.IdentifierExpression {
            if nodes.ValueStart(node) >= 0 {
                name := nodes.Text(source, node)
                if !bound.Contains(name) && enclosingCapturableNames.Contains(name) {
                    captures.Add(name)
                }
            }
        }

        if kind == ColumnarExpressionNodeKind.IsExpression || kind == ColumnarExpressionNodeKind.AsExpression {
            CollectContextualLambdaCaptures(nodes, source, nodes.Child(node, 0), bound, enclosingCapturableNames, captures)
            return
        }

        first := 0
        if kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.CastExpression {
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
    // contextual lambda literal whose body the host has preflighted, and a visible local-function method
    // group. The host's remaining C# decision code resolves each form's candidate return type (the
    // lambda candidate is the host's scoped sub-emitter body-preflight result, already gated to a supported
    // non-void type; the local-function candidate is the resolved method-group return, already gated to a
    // supported non-void type with a single parameter equivalent to the source element type) and passes
    // null for a form that does not apply. The lambda form takes precedence; a null result is the standard
    // inference decline the host reports. The body preflight and reflection-bound validity/equivalence
    // checks remain C# debt — this owns only which candidate the return type comes from.
    static func PlanSingleParameterContextualReturnType(lambdaBodyReturnType: Type?, localFunctionReturnType: Type?): Type? {
        if lambdaBodyReturnType != null {
            return lambdaBodyReturnType
        }

        return localFunctionReturnType
    }

    // Select the owning type, generated-method identity, and visibility for one non-capturing lambda
    // body and define the synthesized method. Returns null to decline — an invalid synthesized signature,
    // or a VALUE-TYPE `this` capture that cannot bind a delegate directly to the current instance — so
    // the mechanical host reports the standard lambda decline. hasThisCapture is the host's
    // resolved fact that the body references the enclosing reference type's member chain (and so needs
    // `this`); when false a type-owned lambda remains a static method on that type, while a file-level
    // lambda is program-static.
    //
    // `programType` IS THE FILE-LEVEL PLACEMENT'S OWNER AND NOTHING ELSE, so it is null whenever the
    // lambda is written inside a type: those shapes put their method on `enclosing` or on
    // `staticOwner` and never touch the holder. The host resolves it only for the file-level shape,
    // because resolving a holder is what CREATES it — see `ColumnarFreeFunctionHolders`.
    //
    // `staticOwner` IS THE TYPE WHOSE STATIC MEMBER IS BEING EMITTED, and it exists because
    // `enclosing` is the INSTANCE-context marker and is null in every static body. Without it a
    // lambda written in a static method, a static field initializer or a `.cctor` of a named type
    // was treated as FILE-LEVEL and landed on the namespace's `Program` holder — which created that
    // public holder for a namespace declaring no free function at all. `NSharpLang.Cli.Program` and
    // `NSharpLang.Cli.Commands.Program` in the emitted `Compiler` assembly each held nothing but two
    // lowered lambdas, and the first of them is what made `src/NSharpLang.Cli/Program.cs` warn
    // CS0436 against its own compiler.
    //
    // A STATIC HELPER'S BODY KEEPS NO INSTANCE CONTEXT — `CurrentStructForBody` stays null for BOTH
    // static owners, and the two used to disagree. `staticOwner` left it null; `enclosing` set it,
    // so a lambda written in an INSTANCE member ran its static helper body with the instance-context
    // marker pointing at a type it holds no instance of, while its own first parameter really did sit
    // at argument ordinal zero. `ColumnarDirectCallPlanner` reads exactly that pair — an instance
    // context plus a parameter at ordinal zero — as the contextual-lambda PREFLIGHT frame, whose
    // ordinal zero is synthetic and whose implicit receiver cannot be emitted, and hands the WHOLE
    // call back to the legacy residual. So every call in such a body fell to the hand-written subset:
    // `Console.WriteLine(3)` declined in a lambda written in an instance method and emitted in the
    // identical lambda written in a static one, and an external extension call
    // (`logger.LogInformation(...)`) inside a lambda NESTED IN A CAPTURING LAMBDA declined for the
    // same reason — the parent display is the enclosing marker there, and the nested helper is static.
    // `hasThisCapture` above has already decided the other way for any body that DOES reference the
    // enclosing chain, so a body reaching here provably needs no instance, and giving it one could
    // only make `ldarg.0` mean the first parameter.
    static func PlanNonCapturingPlacement(programType: TypeBuilder?, enclosing: ColumnarStructDef?, lambdaCounter: int[], visibleTypeParameters: Dictionary<string, Type>, returnType: Type, parameterTypes: Type[], hasThisCapture: bool, staticOwner: ColumnarStructDef? = null): ColumnarLambdaPlacement? {
        if lambdaCounter == null || visibleTypeParameters == null || returnType == null || parameterTypes == null {
            throw new InvalidOperationException("Lambda placement planning requires non-null placement facts.")
        }

        if hasThisCapture {
            // A reference `this` binds the delegate directly to the current instance — INCLUDING inside
            // that type's own constructor, where `ldarg.0` is the very object being constructed and the
            // delegate that captures it observes every field the rest of the constructor still writes.
            // A VALUE type is the case the rule exists for: its `this` is a managed pointer to storage
            // the constructor owns, and a delegate built over it would carry a copy with different
            // mutation semantics. Refusing the constructor outright also refused the reference case, so
            // `this.handler = () => this.Name` emitted in a method and declined in the constructor that
            // set the very same field.
            if enclosing == null || !enclosing.IsReference {
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

        // ONE STATIC HELPER, ONE RULE. `enclosing` and `staticOwner` name the same thing — the type
        // this lambda was WRITTEN inside — and they are mutually exclusive by construction, because
        // the host reads `staticOwner` only when the instance-context marker is null. They used to
        // produce placements that disagreed about the body's instance context, and the disagreement
        // was a real defect: see the note on `CurrentStructForBody` below.
        lexicalOwner := enclosing ?? staticOwner
        if lexicalOwner != null {
            if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(returnType, parameterTypes, lexicalOwner.Builder) {
                return null
            }
            lexicalMethod := lexicalOwner.Builder.DefineMethod(NextLambdaMethodName(lambdaCounter), StaticLambdaAttributes(), returnType, parameterTypes)
            placement := new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.StaticEnclosing, lexicalMethod, lexicalOwner.Builder)
            placement.TypeParametersForBody = ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(visibleTypeParameters, lexicalOwner.Builder)
            return placement
        }

        if programType == null {
            throw new InvalidOperationException("A file-level lambda's placement requires its namespace's program holder.")
        }
        if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(returnType, parameterTypes, programType) {
            return null
        }
        staticMethod := DefineProgramStaticLambda(programType, lambdaCounter, returnType, parameterTypes)
        return new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.StaticProgram, staticMethod, programType)
    }

    // Define the assembly-static program method that hosts a non-capturing lambda body.
    // THE SAME PLACEMENT DECISION FOR A LAMBDA WHOSE RETURN TYPE ITS OWN BODY DECIDES.
    //
    // `f := () => this.Value` has no delegate target to take a signature from, so the synthesized
    // method is defined SIGNATURE-LESS and gets `SetReturnType`/`SetParameters` after its body has
    // been emitted. That is the only difference: WHERE the method goes is the same question, with the
    // same answer — a body that needs the enclosing instance becomes a private instance method on the
    // enclosing reference type. A capture-free type body keeps a static helper on its lexical owner;
    // only a file-level lambda uses the program type.
    // Asking it only for a lambda with a delegate target is why `f := () => this.Value` declined at
    // `emit.body` while `f: Func<int> = () => this.Value` emitted.
    // `programType` is null for a lambda written inside a type, for the same reason as above, and
    // `staticOwner` carries the same static-body owner `PlanNonCapturingPlacement` documents.
    static func PlanInferredPlacement(programType: TypeBuilder?, enclosing: ColumnarStructDef?, lambdaCounter: int[], visibleTypeParameters: Dictionary<string, Type>, parameterTypes: Type[], hasThisCapture: bool, staticOwner: ColumnarStructDef? = null): ColumnarLambdaPlacement? {
        if lambdaCounter == null || visibleTypeParameters == null || parameterTypes == null {
            throw new InvalidOperationException("Lambda placement planning requires non-null placement facts.")
        }

        if hasThisCapture {
            // The same rule as `PlanNonCapturingPlacement`: a reference `this` binds directly, in a
            // constructor body as much as anywhere else, and only a value type's `this` cannot.
            if enclosing == null || !enclosing.IsReference {
                return null
            }
            instanceMethod := enclosing.Builder.DefineMethod(NextLambdaMethodName(lambdaCounter), (MethodAttributes)129)
            placement := new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.InstanceThis, instanceMethod, enclosing.Builder)
            placement.CurrentStructForBody = enclosing
            placement.OrdinalShift = 1
            placement.TypeParametersForBody = ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(visibleTypeParameters, enclosing.Builder)

            return placement
        }

        // The same one rule as `PlanNonCapturingPlacement`: the lexical owner is whichever of the two
        // the host supplied, and the body gets no instance context.
        lexicalOwner := enclosing ?? staticOwner
        if lexicalOwner != null {
            lexicalMethod := lexicalOwner.Builder.DefineMethod(NextLambdaMethodName(lambdaCounter), StaticLambdaAttributes())
            placement := new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.StaticEnclosing, lexicalMethod, lexicalOwner.Builder)
            placement.TypeParametersForBody = ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(visibleTypeParameters, lexicalOwner.Builder)
            return placement
        }

        if programType == null {
            throw new InvalidOperationException("A file-level lambda's placement requires its namespace's program holder.")
        }
        staticMethod := programType.DefineMethod(NextLambdaMethodName(lambdaCounter), StaticLambdaAttributes())

        return new ColumnarLambdaPlacement(ColumnarLambdaPlacementMode.StaticProgram, staticMethod, programType)
    }

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
