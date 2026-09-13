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
    // The local functions that must run as INSTANCE methods of the display: the ones that capture,
    // plus the ones that only CALL a capturing sibling and therefore need the same receiver in hand.
    DisplayMethodNames: HashSet<string>
    // True when some display method reads the enclosing instance, which puts `<>4__this` on the display.
    ReadsEnclosingInstance: bool

    constructor(captureNames: HashSet<string>, displayMethodNames: HashSet<string>, readsEnclosingInstance: bool) {
        CaptureNames = captureNames
        DisplayMethodNames = displayMethodNames
        ReadsEnclosingInstance = readsEnclosingInstance
    }

    func NeedsDisplay(): bool {
        return DisplayMethodNames.Count > 0
    }

    func IsDisplayMethod(name: string): bool {
        return DisplayMethodNames.Contains(name)
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
        readsEnclosingInstance := false
        if localFunctions == null || localFunctions.Count == 0 {
            return new ColumnarLocalFunctionClosurePlan(captureNames, displayMethodNames, readsEnclosingInstance)
        }

        declaredNames := new HashSet<string>(StringComparer.Ordinal)
        index := 0
        while index < localFunctions.Count {
            declaredNames.Add(localFunctions[index].Function.Name)
            index = index + 1
        }

        calledSiblings := new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        index = 0
        while index < localFunctions.Count {
            declaration := localFunctions[index].Function
            bound := new HashSet<string>(StringComparer.Ordinal)
            parameterIndex := 0
            while parameterIndex < declaration.ParamNames.Length {
                bound.Add(declaration.ParamNames[parameterIndex])
                parameterIndex = parameterIndex + 1
            }
            // A name this body BINDS for itself is never a capture: the emitter refuses a local
            // function whose parameter or local shadows an enclosing binding (NL316), so subtracting
            // the whole bound set is exact rather than merely conservative.
            ColumnarClosureBindingPlanner.CollectBindingNames(declaration.BodyNodes, source, declaration.BodyRoot, bound)
            freeNames := new SortedSet<string>(StringComparer.Ordinal)
            ColumnarClosureBindingPlanner.CollectUnboundNames(declaration.BodyNodes, source, declaration.BodyRoot, bound, freeNames)

            siblings := new HashSet<string>(StringComparer.Ordinal)
            capturesHere := false
            readsInstanceHere := false
            for freeName in freeNames {
                if parentBindingNames.Contains(freeName) {
                    captureNames.Add(freeName)
                    capturesHere = true
                } else if declaredNames.Contains(freeName) {
                    siblings.Add(freeName)
                } else if enclosingInstanceNames.Contains(freeName) {
                    readsInstanceHere = true
                }
            }

            calledSiblings[declaration.Name] = siblings
            if capturesHere || readsInstanceHere {
                displayMethodNames.Add(declaration.Name)
            }
            if readsInstanceHere {
                readsEnclosingInstance = true
            }

            index = index + 1
        }

        // A capture-free local function that CALLS a capturing one still needs the display instance to
        // make that call, so the "runs on the display" set is the closure of the call graph over the
        // capturing seeds. Mutual recursion is a cycle in that graph and settles in the same fixpoint.
        changed := true
        while changed {
            changed = false
            index = 0
            while index < localFunctions.Count {
                name := localFunctions[index].Function.Name
                if !displayMethodNames.Contains(name) {
                    calls := calledSiblings[name]
                    for callee in calls {
                        if displayMethodNames.Contains(callee) && !displayMethodNames.Contains(name) {
                            displayMethodNames.Add(name)
                            changed = true
                        }
                    }
                }

                index = index + 1
            }
        }

        return new ColumnarLocalFunctionClosurePlan(captureNames, displayMethodNames, readsEnclosingInstance)
    }

    // THE NAMES THE LOCAL FUNCTIONS' OWN SCOPE ENCLOSES: the enclosing body's parameters plus the
    // bindings its ROOT BLOCK declares. A name bound in a NESTED block — a loop variable, an `if`
    // body's local — is not in scope where the local function is written, so it is neither a capture
    // nor a shadowing conflict. Reading the whole body's binding set instead used to refuse
    // `func visit(item: string)` in a body that also wrote `for item in items`, which `nlc check`
    // accepts and C# accepts, because the two `item`s never share a scope.
    static func CollectDeclaringScopeBindingNames(nodes: ColumnarNodeTable, source: string, blockNode: int, names: HashSet<string>) {
        if nodes.Kind(blockNode) != 25 {
            ColumnarClosureBindingPlanner.CollectBindingNames(nodes, source, blockNode, names)
            return
        }

        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(blockNode) {
            child := nodes.Child(blockNode, childOrdinal)
            childKind := nodes.Kind(child)
            if childKind == 24 {
                if nodes.ValueStart(child) >= 0 {
                    names.Add(nodes.Text(source, child))
                }
            } else if childKind == 40 || childKind == 50 {
                if nodes.ChildCount(child) == 2 {
                    nameChild := nodes.Child(child, 0)
                    if nodes.Kind(nameChild) == 6 && nodes.ValueStart(nameChild) >= 0 {
                        names.Add(nodes.Text(source, nameChild))
                    }
                }
            } else if childKind == 30 {
                nameOrdinal := 0
                while nameOrdinal < nodes.ChildCount(child) - 1 {
                    element := nodes.Child(child, nameOrdinal)
                    if nodes.Kind(element) == 6 && nodes.ValueStart(element) >= 0 {
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
    Plan: ColumnarLocalFunctionClosurePlan
    BoxFields: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>
    EnclosingThisField: FieldBuilder?
    Instance: LocalBuilder?
    ReceiverIsArgument: bool

    constructor(builder: TypeBuilder, displayConstructor: ConstructorInfo, plan: ColumnarLocalFunctionClosurePlan) {
        Builder = builder
        Constructor = displayConstructor
        Plan = plan
        BoxFields = new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
        EnclosingThisField = null
        Instance = null
        ReceiverIsArgument = false
    }

    func ForDisplayMethodBody(): ColumnarLocalFunctionDisplay {
        view := new ColumnarLocalFunctionDisplay(Builder, Constructor, Plan)
        view.BoxFields = BoxFields
        view.EnclosingThisField = EnclosingThisField
        view.ReceiverIsArgument = true
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
