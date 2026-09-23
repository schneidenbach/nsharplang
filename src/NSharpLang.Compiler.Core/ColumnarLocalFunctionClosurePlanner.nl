namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// WHAT A BODY'S LOCAL FUNCTIONS CAPTURE. A local function and a lambda are the same closure in this
// compiler: a body that captures nothing is a plain method, and a body that captures is an INSTANCE
// method of one display class created for the scope that declares it. This plan is the capture half
// of that decision — it is structural (names, not types), so it is asked BEFORE the enclosing body
// emits and the display type can be defined in time for the calls the body makes.
class ColumnarLocalFunctionClosurePlan {

    // Every enclosing binding — parameter or local — that some local function of this body reads or
    // writes. These are the names the enclosing body lifts into shared boxes and the display holds.
    CaptureNames: HashSet<string>
    // The local functions that run as instance methods of the body's DISPLAY: the ones that capture a
    // binding, plus the ones that only CALL such a sibling and therefore need the same receiver.
    DisplayMethodNames: HashSet<string>
    // The local functions that capture only `this` and run as instance methods of the ENCLOSING TYPE.
    // That placement is what gives a struct's capturing local function C#'s `ref this`: an instance
    // method of a value type receives its receiver by reference, so writes are seen by the caller.
    InstanceMethodNames: HashSet<string>
    // True when some DISPLAY method also needs the enclosing instance, which puts `<>4__this` on it.
    ReadsEnclosingInstance: bool

    constructor(captureNames: HashSet<string>, displayMethodNames: HashSet<string>, instanceMethodNames: HashSet<string>, readsEnclosingInstance: bool) {
        CaptureNames = captureNames
        DisplayMethodNames = displayMethodNames
        InstanceMethodNames = instanceMethodNames
        ReadsEnclosingInstance = readsEnclosingInstance
    }

    func NeedsDisplay(): bool {
        return DisplayMethodNames.Count > 0
    }

    func NeedsLowering(): bool {
        return DisplayMethodNames.Count > 0 || InstanceMethodNames.Count > 0
    }

    func IsDisplayMethod(name: string): bool {
        return DisplayMethodNames.Contains(name)
    }

    func IsInstanceMethod(name: string): bool {
        return InstanceMethodNames.Contains(name)
    }
}

class ColumnarLocalFunctionClosurePlanner {
    static func Plan(
        localFunctions: List<ColumnarLocalFunctionInput>,
        source: string,
        parentBindingNames: HashSet<string>,
        enclosingInstanceNames: HashSet<string>
    ): ColumnarLocalFunctionClosurePlan {
        captureNames := new HashSet<string>(StringComparer.Ordinal)
        displayMethodNames := new HashSet<string>(StringComparer.Ordinal)
        instanceMethodNames := new HashSet<string>(StringComparer.Ordinal)
        if localFunctions == null || localFunctions.Count == 0 {
            return new ColumnarLocalFunctionClosurePlan(captureNames, displayMethodNames, instanceMethodNames, false)
        }

        declaredNames := new HashSet<string>(StringComparer.Ordinal)
        index := 0
        while index < localFunctions.Count {
            declaredNames.Add(localFunctions[index].Function.Name)
            index = index + 1
        }

        calledSiblings := new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        needsDisplay := new HashSet<string>(StringComparer.Ordinal)
        needsEnclosingInstance := new HashSet<string>(StringComparer.Ordinal)
        index = 0
        while index < localFunctions.Count {
            declaration := localFunctions[index].Function
            bound := new HashSet<string>(StringComparer.Ordinal)
            for paramName2 in declaration.ParamNames {
                bound.Add(paramName2)
            }
            // A name this body BINDS for itself is never a capture: the emitter refuses a local
            // function whose parameter or local shadows an enclosing binding (NL316), so subtracting
            // the whole bound set is exact rather than merely conservative.
            ColumnarClosureBindingPlanner.CollectBindingNames(declaration.BodyNodes, source, declaration.BodyRoot, bound)
            freeNames := new SortedSet<string>(StringComparer.Ordinal)
            ColumnarClosureBindingPlanner.CollectUnboundNames(declaration.BodyNodes, source, declaration.BodyRoot, bound, freeNames)

            siblings := new HashSet<string>(StringComparer.Ordinal)
            for freeName in freeNames {
                if parentBindingNames.Contains(freeName) {
                    captureNames.Add(freeName)
                    needsDisplay.Add(declaration.Name)
                } else if declaredNames.Contains(freeName) {
                    siblings.Add(freeName)
                } else if enclosingInstanceNames.Contains(freeName) {
                    needsEnclosingInstance.Add(declaration.Name)
                }
            }

            calledSiblings[declaration.Name] = siblings
            index = index + 1
        }

        // A capture-free local function that CALLS a capturing one still needs the display instance to
        // make that call, and one that calls a `this`-reading sibling needs the receiver that sibling
        // runs on. Both requirements flow BACKWARDS along the call graph, so they are one fixpoint;
        // mutual recursion is a cycle in that graph and settles in it.
        changed := true
        while changed {
            changed = false
            index = 0
            while index < localFunctions.Count {
                name := localFunctions[index].Function.Name
                calls := calledSiblings[name]
                for callee in calls {
                    if needsDisplay.Contains(callee) && !needsDisplay.Contains(name) {
                        needsDisplay.Add(name)
                        changed = true
                    }
                    if needsEnclosingInstance.Contains(callee) && !needsEnclosingInstance.Contains(name) {
                        needsEnclosingInstance.Add(name)
                        changed = true
                    }
                }

                index = index + 1
            }
        }

        readsEnclosingInstance := false
        index = 0
        while index < localFunctions.Count {
            name := localFunctions[index].Function.Name
            if needsDisplay.Contains(name) {
                displayMethodNames.Add(name)
                if needsEnclosingInstance.Contains(name) {
                    readsEnclosingInstance = true
                }
            } else if needsEnclosingInstance.Contains(name) {
                instanceMethodNames.Add(name)
            }

            index = index + 1
        }

        return new ColumnarLocalFunctionClosurePlan(captureNames, displayMethodNames, instanceMethodNames, readsEnclosingInstance)
    }

    // THE NAMES THE LOCAL FUNCTIONS' OWN SCOPE ENCLOSES: the enclosing body's parameters plus the
    // bindings its ROOT BLOCK declares. A name bound in a NESTED block — a loop variable, an `if`
    // body's local — is not in scope where the local function is written, so it is neither a capture
    // nor a shadowing conflict. Reading the whole body's binding set instead used to refuse
    // `func visit(item: string)` in a body that also wrote `for item in items`, which `nlc check`
    // accepts and C# accepts, because the two `item`s never share a scope.
    static func CollectDeclaringScopeBindingNames(nodes: ColumnarNodeTable, source: string, blockNode: int, names: HashSet<string>) {
        if nodes.Kind(blockNode) != ColumnarStatementNodeKind.BlockStatement {
            ColumnarClosureBindingPlanner.CollectBindingNames(nodes, source, blockNode, names)
            return
        }

        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(blockNode) {
            child := nodes.Child(blockNode, childOrdinal)
            childKind := nodes.Kind(child)
            if childKind == ColumnarStatementNodeKind.VariableDeclarationStatement {
                if nodes.ValueStart(child) >= 0 {
                    names.Add(nodes.Text(source, child))
                }
            } else if childKind == ColumnarStatementNodeKind.CatchClause {
                // A catch clause's binding is asked for rather than counted, because a clause with an
                // exception FILTER carries a third child and a filtered clause with no binding carries
                // the same TWO a bound one used to.
                catchBinding := ColumnarCatchClauseFacts.BindingNode(nodes, child)
                if catchBinding >= 0 {
                    names.Add(nodes.Text(source, catchBinding))
                }
            } else if childKind == ColumnarStatementNodeKind.TypedLocalDeclaration {
                if nodes.ChildCount(child) == 2 {
                    nameChild := nodes.Child(child, 0)
                    if nodes.Kind(nameChild) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(nameChild) >= 0 {
                        names.Add(nodes.Text(source, nameChild))
                    }
                }
            } else if childKind == ColumnarStatementNodeKind.TupleDeconstructionStatement {
                nameOrdinal := 0
                while nameOrdinal < nodes.ChildCount(child) - 1 {
                    element := nodes.Child(child, nameOrdinal)
                    if nodes.Kind(element) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(element) >= 0 {
                        names.Add(nodes.Text(source, element))
                    }
                    nameOrdinal = nameOrdinal + 1
                }
            }

            childOrdinal = childOrdinal + 1
        }
    }

    // The bare names that reach the enclosing instance from inside a member body: every instance
    // field, property and method on the declaring type's chain. A local function that reads one of
    // them captures `this`, exactly as a lambda does.
    static func EnclosingInstanceNames(definition: ColumnarStructDef?): HashSet<string> {
        names := new HashSet<string>(StringComparer.Ordinal)
        walk := definition
        while walk != null {
            walkFields := walk.Fields
            walkProperties := walk.Properties
            walkMethods := walk.Methods
            names.UnionWith(walkFields.get_Keys())
            names.UnionWith(walkProperties.get_Keys())
            names.UnionWith(walkMethods.get_Keys())
            walk = walk.BaseDef
        }
        return names
    }
}

// THE DISPLAY A BODY'S LOCAL FUNCTIONS RUN ON. The enclosing body creates one instance at its start
// and stores every captured binding's shared box into it as that box is created; each display method
// reads and writes those bindings through `ldarg.0`, which is the same `_boxedCaptures` route a
// capturing lambda's body already takes. One object is shared by the enclosing body and its display
// methods; `ReceiverIsArgument` is the only thing that differs between those two views of it, so the
// method view is taken with `ForDisplayMethodBody` rather than by mutating the enclosing one.
class ColumnarLocalFunctionDisplay {
    Builder: TypeBuilder
    Constructor: ConstructorInfo
    RuntimeType: Type
    RuntimeConstructor: ConstructorInfo
    Plan: ColumnarLocalFunctionClosurePlan
    BoxFields: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>
    EnclosingThisField: FieldBuilder?
    // The display AS A SOURCE TYPE, so a display method's body resolves `<>4__this` the way a
    // capturing lambda's body does. Null unless some display method needs the enclosing instance.
    DisplayDefinition: ColumnarStructDef?
    Instance: LocalBuilder?
    ReceiverIsArgument: bool
    EnclosingMethodTypeParameters: Type[]
    DisplayTypeParameters: Type[]

    constructor(builder: TypeBuilder?, displayConstructor: ConstructorInfo?, plan: ColumnarLocalFunctionClosurePlan, runtimeType: Type? = null, runtimeConstructor: ConstructorInfo? = null) {
        Builder = builder
        Constructor = displayConstructor
        RuntimeType = builder
        if runtimeType != null {
            RuntimeType = runtimeType
        }
        RuntimeConstructor = displayConstructor
        if runtimeConstructor != null {
            RuntimeConstructor = runtimeConstructor
        }
        Plan = plan
        BoxFields = new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
        EnclosingThisField = null
        DisplayDefinition = null
        Instance = null
        ReceiverIsArgument = false
        EnclosingMethodTypeParameters = System.Array.Empty<Type>()
        DisplayTypeParameters = System.Array.Empty<Type>()
    }

    func HasDisplay(): bool {
        return Builder != null
    }

    func ForDisplayMethodBody(): ColumnarLocalFunctionDisplay {
        view := new ColumnarLocalFunctionDisplay(Builder, Constructor, Plan, RuntimeType, RuntimeConstructor)
        view.BoxFields = BoxFields
        view.EnclosingThisField = EnclosingThisField
        view.DisplayDefinition = DisplayDefinition
        view.ReceiverIsArgument = true
        view.EnclosingMethodTypeParameters = EnclosingMethodTypeParameters
        view.DisplayTypeParameters = DisplayTypeParameters
        return view
    }

    // The enclosing body hands over its display instance and, as each captured binding's box appears,
    // the field that holds it. Both are asked for rather than written through the emitter's own
    // nullable handle, so one owner keeps the display's state consistent.
    func BindInstance(instance: LocalBuilder) {
        Instance = instance
    }

    func BindEnclosingThisField(field: FieldBuilder) {
        EnclosingThisField = field
    }

    func BindDisplayDefinition(definition: ColumnarStructDef) {
        DisplayDefinition = definition
    }

    func BindGenericParameters(enclosingParameters: Type[], displayParameters: Type[]) {
        EnclosingMethodTypeParameters = enclosingParameters
        DisplayTypeParameters = displayParameters
    }

    func OpenDisplayType(valueType: Type): Type? {
        if EnclosingMethodTypeParameters.Length == 0 {
            return valueType
        }
        let result: Type? = null
        if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(EnclosingMethodTypeParameters, DisplayTypeParameters, valueType, out result) {
            return null
        }
        return result
    }

    func FieldForRuntimeInstance(field: FieldBuilder): FieldInfo {
        if EnclosingMethodTypeParameters.Length == 0 {
            return field
        }
        return TypeBuilder.GetField(RuntimeType, field)
    }

    func DisplayDefinitionOrNull(): ColumnarStructDef? {
        return DisplayDefinition
    }

    func AddCapture(name: string, boxField: FieldInfo, valueType: Type) {
        let entry: (BoxField: FieldInfo, ValueType: Type) = (boxField, valueType)
        BoxFields[name] = entry
    }

    func HasCapture(name: string): bool {
        return BoxFields.ContainsKey(name)
    }

    func Captures(name: string): bool {
        return Plan.CaptureNames.Contains(name)
    }

    func CaptureNames(): HashSet<string> {
        return Plan.CaptureNames
    }

    func IsDisplayMethod(name: string): bool {
        return Plan.IsDisplayMethod(name)
    }

    func IsInstanceMethod(name: string): bool {
        return Plan.IsInstanceMethod(name)
    }

    func InstanceLocal(): LocalBuilder? {
        return Instance
    }

    func EnclosingThisFieldOrNull(): FieldBuilder? {
        return EnclosingThisField
    }

    // Every captured name must have reached a shared box by the time the enclosing body finished, or
    // the display methods have nowhere to read it from. The enclosing body reports the miss by name.
    func FirstUnhoistedCapture(): string? {
        for captureName in Plan.CaptureNames {
            if !BoxFields.ContainsKey(captureName) {
                return captureName
            }
        }
        return null
    }
}

// The declared shape of one body's local functions: the callable map every call site in the body and
// in the local bodies resolves against, the declaration nodes that make a name visible, and the
// closure the capturing ones run on. A free function's body and a type member's body both build this
// the same way, which is what keeps "local function" one lowering rather than two.
class ColumnarLocalFunctionLowering {
    LocalFuncs: Dictionary<string, (Method: MethodBuilder, ParamTypes: Type[], ReturnType: Type)>
    // A GENERIC local function is not in the map above, because that map's entries are handles a call
    // site dispatches DIRECTLY and an open generic method is not one: it has to be closed first. It
    // carries the same facts a generic top-level `func` carries — the open handle, the declared
    // parameter and return types, the type parameters and their constraints — so the call site reaches
    // it through the SAME inference and instantiation the generic sibling arm performs.
    GenericLocalFuncs: Dictionary<string, ColumnarSiblingMethodDefinition>
    DeclaredNodes: Dictionary<int, string>
    VisibleNames: List<string>
    Closure: ColumnarLocalFunctionDisplay?
    DeclaringScopeBindings: HashSet<string>

    constructor(
        localFuncs: Dictionary<string, (Method: MethodBuilder, ParamTypes: Type[], ReturnType: Type)>,
        genericLocalFuncs: Dictionary<string, ColumnarSiblingMethodDefinition>,
        declaredNodes: Dictionary<int, string>,
        visibleNames: List<string>,
        closure: ColumnarLocalFunctionDisplay?,
        declaringScopeBindings: HashSet<string>
    ) {
        LocalFuncs = localFuncs
        GenericLocalFuncs = genericLocalFuncs
        DeclaredNodes = declaredNodes
        VisibleNames = visibleNames
        Closure = closure
        DeclaringScopeBindings = declaringScopeBindings
    }

    func PlacementShift(name: string): int {
        if Closure == null {
            return 0
        }
        if Closure.IsDisplayMethod(name) || Closure.IsInstanceMethod(name) {
            return 1
        }
        return 0
    }
}
