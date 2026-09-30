namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// A MEMBER GENERATOR'S BODY CALLS ITS DECLARING TYPE'S MEMBERS THROUGH THE RECEIVER ITS MACHINE
// CAPTURED. The scope is built the way the realization builds it — a machine type holding the
// declaring type's instance in `<>__this`, the declaring type as the enclosing definition — and each
// row plans one value through the scope's own expression door.
class IteratorScopeCallFixture {
    Host: ColumnarStructDef
    Machine: TypeBuilder
    ReceiverField: FieldInfo
    Scope: ColumnarIteratorBodyScope
    LastResultType: Type

    constructor(name: string, hostIsReference: bool, siblings: Dictionary<string, ColumnarSiblingCallFacts>) {
        Host = SourceCallDefinition(name + "Host", hostIsReference)
        Machine = SourceCallDefinition(name + "Machine", true).Builder
        ReceiverField = Machine.DefineField("<>__this", Host.Builder, FieldAttributes.Public)
        siblingNames := new List<string>()
        for entry in siblings {
            siblingNames.Add(entry.Key)
        }
        facts := new ColumnarIteratorBodyFacts(
            new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
            SourceCallDefinitions(Host),
            new ColumnarUnionDef[](0),
            new Dictionary<string, Type>(StringComparer.Ordinal),
            siblings,
            siblingNames,
            Host,
            IteratorStructuralTypeReferences()
        )
        Scope = ColumnarIteratorBodyScope.Create(Machine, facts, null)
        Scope.PublishEnclosingReceiver(ReceiverField, new string[](0), new FieldInfo[](0))
        LastResultType = typeof(object)
    }

    func Plan(source: string): ColumnarCodePlan {
        tree := DirectCallParsedTree(source)
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        resultType := typeof(int)
        if !Scope.TryAppendValue(tree.Nodes, tree.Source, tree.Root, plan, out resultType) {
            throw new InvalidOperationException("The iterator body scope declined '" + source + "'.")
        }
        LastResultType = resultType
        return plan
    }
}

func IteratorScopeNoSiblings(): Dictionary<string, ColumnarSiblingCallFacts> {
    return new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
}

// The receiver rows every captured-receiver call opens with: the machine at argument 0, then the one
// field that holds the declaring type's instance.
func IteratorScopeAssertCapturedReceiver(fixture: IteratorScopeCallFixture, plan: ColumnarCodePlan, receiverOpCode: short) {
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    argument := plan.OperandIndices[0]
    assert plan.ArgumentOrdinals[argument] == 0
    assert Object.ReferenceEquals(plan.Types[plan.ArgumentTypeIndices[argument]], fixture.Machine)
    assert plan.OpCodeValues[1] == receiverOpCode
    assert Object.ReferenceEquals(plan.Fields[plan.OperandIndices[1]], fixture.ReceiverField)
}

test "a bare member call in a member generator dispatches on the captured receiver" {
    fixture := new IteratorScopeCallFixture("IteratorScopeBare", true, IteratorScopeNoSiblings())
    _label := SourceCallPublicInstance(fixture.Host, "Label", new Type[](0), typeof(string))

    plan := fixture.Plan("Label()")

    assert plan.OperationCount == 3
    IteratorScopeAssertCapturedReceiver(fixture, plan, ColumnarCodePlanContract.Ldfld())
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    assert plan.Methods[plan.OperandIndices[2]].get_Name() == "Label"
}

test "a this-qualified member call in a member generator takes the same receiver" {
    fixture := new IteratorScopeCallFixture("IteratorScopeThis", true, IteratorScopeNoSiblings())
    _label := SourceCallPublicInstance(fixture.Host, "Label", new Type[](0), typeof(string))

    plan := fixture.Plan("this.Label()")

    assert plan.OperationCount == 3
    IteratorScopeAssertCapturedReceiver(fixture, plan, ColumnarCodePlanContract.Ldfld())
    assert plan.Methods[plan.OperandIndices[2]].get_Name() == "Label"
}

test "a member generator selects the declaring type's overload by argument type" {
    fixture := new IteratorScopeCallFixture("IteratorScopeOverload", true, IteratorScopeNoSiblings())
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    oneString := new Type[](1)
    oneString[0] = typeof(string)
    byInt := SourceCallPublicInstance(fixture.Host, "Describe", oneInt, typeof(string))
    byString := SourceCallPublicInstance(fixture.Host, "Describe", oneString, typeof(string))

    intPlan := fixture.Plan("Describe(4)")
    stringPlan := fixture.Plan("Describe(\"x\")")

    IteratorScopeAssertCapturedReceiver(fixture, intPlan, ColumnarCodePlanContract.Ldfld())
    assert Object.ReferenceEquals(intPlan.Methods[intPlan.OperandIndices[intPlan.OperationCount - 1]], byInt.Builder)
    IteratorScopeAssertCapturedReceiver(fixture, stringPlan, ColumnarCodePlanContract.Ldfld())
    assert Object.ReferenceEquals(stringPlan.Methods[stringPlan.OperandIndices[stringPlan.OperationCount - 1]], byString.Builder)
}

// A struct's methods take `this` by reference, so the receiver is the ADDRESS of the machine's copy.
test "a member generator of a struct calls the member on the address of its captured copy" {
    fixture := new IteratorScopeCallFixture("IteratorScopeValue", false, IteratorScopeNoSiblings())
    _read := SourceCallPublicInstance(fixture.Host, "Read", new Type[](0), typeof(int))

    plan := fixture.Plan("Read()")

    assert plan.OperationCount == 3
    IteratorScopeAssertCapturedReceiver(fixture, plan, ColumnarCodePlanContract.Ldflda())
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
}

test "a static member called bare from a member generator loads no receiver" {
    fixture := new IteratorScopeCallFixture("IteratorScopeStatic", true, IteratorScopeNoSiblings())
    _shared := SourceCallPublicStatic(fixture.Host, "Shared", new Type[](0), typeof(string))

    plan := fixture.Plan("Shared()")

    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Shared"
}

// Preserve `AnalyzerIdentifierResolution`'s provisional member binding when planning an NL209 use.
test "a colliding member name keeps its provisional binding in a member generator" {
    sibling := DirectCallSiblingFacts("IteratorScopeHiddenFree", "Label", new Type[](0), typeof(int))
    siblings := IteratorScopeNoSiblings()
    siblings["Label"] = sibling
    fixture := new IteratorScopeCallFixture("IteratorScopeHidden", true, siblings)
    member := SourceCallPublicInstance(fixture.Host, "Label", new Type[](0), typeof(string))

    plan := fixture.Plan("Label()")

    IteratorScopeAssertCapturedReceiver(fixture, plan, ColumnarCodePlanContract.Ldfld())
    assert Object.ReferenceEquals(plan.Methods[plan.OperandIndices[2]], member.Builder)
    assert fixture.LastResultType == typeof(string)
}

test "a sibling function with no enclosing member remains plannable in a member generator" {
    sibling := DirectCallSiblingFacts("IteratorScopeVisibleFree", "Caption", new Type[](0), typeof(int))
    siblings := IteratorScopeNoSiblings()
    siblings["Caption"] = sibling
    fixture := new IteratorScopeCallFixture("IteratorScopeVisible", true, siblings)
    _label := SourceCallPublicInstance(fixture.Host, "Label", new Type[](0), typeof(string))

    plan := fixture.Plan("Caption()")

    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert Object.ReferenceEquals(plan.Methods[plan.OperandIndices[0]], sibling.Method)
}

test "a captured receiver must be typed by the declaring type it holds" {
    fixture := new IteratorScopeCallFixture("IteratorScopeMistyped", true, IteratorScopeNoSiblings())
    stray := fixture.Machine.DefineField("<>__stray", typeof(string), FieldAttributes.Public)

    refused := false
    try {
        fixture.Scope.Bindings.SetCapturedReceiver(stray)
    } catch e: InvalidOperationException {
        refused = true
    }
    assert refused
    assert Object.ReferenceEquals(fixture.Scope.Bindings.CapturedReceiverField, fixture.ReceiverField)
}

// A machine built without a program's declarations has no declaring type to ask, so it publishes its
// member reads and no call receiver.
test "a scope with no declaring type publishes member reads but no call receiver" {
    host := SourceCallDefinition("IteratorScopeFactsFreeHost", true)
    machine := SourceCallDefinition("IteratorScopeFactsFreeMachine", true).Builder
    receiver := machine.DefineField("<>__this", host.Builder, FieldAttributes.Public)
    member := machine.DefineField("Value", typeof(int), FieldAttributes.Public)
    names := new string[](1)
    names[0] = "Value"
    fields := new FieldInfo[](1)
    fields[0] = member
    scope := ColumnarIteratorBodyScope.Create(machine, ColumnarIteratorBodyFacts.Empty(IteratorStructuralTypeReferences()), null)

    scope.PublishEnclosingReceiver(receiver, names, fields)

    assert scope.Bindings.CapturedInstanceFields.ContainsKey("Value")
    assert scope.Bindings.CapturedReceiverField == null
    assert scope.Bindings.ImplicitInstanceDefinition() == null
}

// An instance generator's declaring type, its state machine, and a per-iteration display over that
// machine. The machine holds the captured receiver and a hoisted local spelled like the owner's field.
class ColumnarIteratorScopeOwner {
    Note: string

    constructor() {
        Note = "owner"
    }
}

class ColumnarIteratorScopeMachine {
    Receiver: ColumnarIteratorScopeOwner
    Note: string

    constructor() {
        Receiver = new ColumnarIteratorScopeOwner()
        Note = "local"
    }
}

class ColumnarIteratorScopeDisplay {
    Machine: ColumnarIteratorScopeMachine

    constructor() {
        Machine = new ColumnarIteratorScopeMachine()
    }
}

func IteratorScopeField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Required iterator-scope fixture field was not found.")
    }

    return field
}

// A machine scope whose hoisted `Note` is published, as the lowering publishes every hoisted field.
func IteratorScopeWithHoistedNote(): ColumnarIteratorBodyScope {
    scope := ColumnarIteratorBodyScope.Create(typeof(ColumnarIteratorScopeMachine), ColumnarIteratorBodyFacts.Empty(new ColumnarStructuralTypeReferenceTable()), null)
    scope.PublishField("Note", IteratorScopeField(typeof(ColumnarIteratorScopeMachine), "Note"))
    return scope
}

func IteratorScopePublishOwnerNote(scope: ColumnarIteratorBodyScope) {
    names := new string[](1)
    names[0] = "Note"
    members := new FieldInfo[](1)
    members[0] = IteratorScopeField(typeof(ColumnarIteratorScopeOwner), "Note")
    scope.PublishEnclosingMembers(IteratorScopeField(typeof(ColumnarIteratorScopeMachine), "Receiver"), names, members)
}

// `ldarg.0; ldfld Receiver; ldfld Owner.Note` — the member, through the captured receiver.
func IteratorScopeAssertReadsOwnerNote(plan: ColumnarCodePlan) {
    assert plan.OperationCount == 3
    assert plan.Fields[0].get_Name() == "Receiver"
    assert plan.Fields[1].get_DeclaringType() == typeof(ColumnarIteratorScopeOwner)
}

// `ldarg.0; ldfld Machine.Note` — the hoisted local.
func IteratorScopeAssertReadsHoistedNote(plan: ColumnarCodePlan) {
    assert plan.OperationCount == 2
    assert plan.Fields[0].get_DeclaringType() == typeof(ColumnarIteratorScopeMachine)
    assert plan.Fields[0].get_Name() == "Note"
}

test "an enclosing member answers its bare name until a binding hides it and again once that binding's scope closes" {
    scope := IteratorScopeWithHoistedNote()
    IteratorScopePublishOwnerNote(scope)
    assert scope.IsEnclosingMemberVisible("Note")
    IteratorScopeAssertReadsOwnerNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))

    mark := scope.EnterBindingScope()
    scope.HideEnclosingMember("Note")
    assert !scope.IsEnclosingMemberVisible("Note")
    assert !scope.Bindings.CapturedInstanceFields.ContainsKey("Note")
    IteratorScopeAssertReadsHoistedNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))

    scope.ExitBindingScope(mark)
    assert scope.IsEnclosingMemberVisible("Note")
    IteratorScopeAssertReadsOwnerNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))
}

test "this.name reads the captured receiver's member while a binding hides its bare name" {
    scope := IteratorScopeWithHoistedNote()
    IteratorScopePublishOwnerNote(scope)
    scope.HideEnclosingMember("Note")
    IteratorScopeAssertReadsOwnerNote(BoundPlan(BoundExplicitThisTree("Note"), scope.Bindings))

    // `this` is the captured receiver, never the machine: a name only the machine holds is not a
    // member the source could have written `this.` in front of.
    scope.PublishField("Hoisted", IteratorScopeField(typeof(ColumnarIteratorScopeMachine), "Note"))
    missing := BoundExplicitThisTree("Hoisted")
    missingPlan := new ColumnarCodePlan()
    assert ColumnarBoundIdentifierPlanner.Plan(missing.Nodes, missing.Source, missing.Root, scope.Bindings, missingPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(missingPlan)
}

test "a parameter hidden before the members are published keeps its name from the first statement" {
    scope := IteratorScopeWithHoistedNote()
    scope.HideEnclosingMember("Note")
    IteratorScopePublishOwnerNote(scope)
    assert !scope.IsEnclosingMemberVisible("Note")
    assert scope.Bindings.ReceiverMembers.ContainsKey("Note")
    IteratorScopeAssertReadsHoistedNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))
}

test "a loop-capture box published while its member is visible waits aside until a binding hides the member" {
    scope := IteratorScopeWithHoistedNote()
    IteratorScopePublishOwnerNote(scope)
    boxField := IteratorScopeField(BoundBoxOwnerType(), "Box")
    scope.PublishBoxedCapture("Note", boxField, typeof(int))
    assert !scope.Bindings.BoxedCaptures.ContainsKey("Note")
    IteratorScopeAssertReadsOwnerNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))

    mark := scope.EnterBindingScope()
    scope.HideEnclosingMember("Note")
    assert scope.Bindings.BoxedCaptures.ContainsKey("Note")
    boxedPlan := BoundPlan(BoundIdentifierTree("Note"), scope.Bindings)
    assert boxedPlan.ResultType == typeof(int)
    assert boxedPlan.Fields[0].get_Name() == "Box"

    scope.ExitBindingScope(mark)
    assert !scope.Bindings.BoxedCaptures.ContainsKey("Note")
    IteratorScopeAssertReadsOwnerNote(BoundPlan(BoundIdentifierTree("Note"), scope.Bindings))
}

test "a display's hop to a machine field yields its name to a visible member and takes it back when hidden" {
    scope := ColumnarIteratorBodyScope.Create(typeof(ColumnarIteratorScopeDisplay), ColumnarIteratorBodyFacts.Empty(new ColumnarStructuralTypeReferenceTable()), null)
    machineHop := IteratorScopeField(typeof(ColumnarIteratorScopeDisplay), "Machine")
    hoistedNote := IteratorScopeField(typeof(ColumnarIteratorScopeMachine), "Note")
    scope.PublishDisplayedMachineField("Note", machineHop, hoistedNote)
    IteratorScopePublishOwnerNote(scope)
    assert scope.Bindings.CapturedInstanceFields["Note"].Item2.get_DeclaringType() == typeof(ColumnarIteratorScopeOwner)

    mark := scope.EnterBindingScope()
    scope.HideEnclosingMember("Note")
    assert scope.Bindings.CapturedInstanceFields["Note"].Item2.get_DeclaringType() == typeof(ColumnarIteratorScopeMachine)

    scope.ExitBindingScope(mark)
    assert scope.Bindings.CapturedInstanceFields["Note"].Item2.get_DeclaringType() == typeof(ColumnarIteratorScopeOwner)
}

test "a lambda scope starts with the bindings that hide members where the lambda was written" {
    outer := IteratorScopeWithHoistedNote()
    IteratorScopePublishOwnerNote(outer)
    outer.HideEnclosingMember("Note")

    lambda := IteratorScopeWithHoistedNote()
    lambda.HideAsIn(outer)
    IteratorScopePublishOwnerNote(lambda)
    assert !lambda.IsEnclosingMemberVisible("Note")
    IteratorScopeAssertReadsHoistedNote(BoundPlan(BoundIdentifierTree("Note"), lambda.Bindings))
}

test "a binding scope closes only back to a mark it opened" {
    scope := IteratorScopeWithHoistedNote()
    refused := false
    try {
        scope.ExitBindingScope(1)
    } catch e: InvalidOperationException {
        refused = e.Message.Length > 0
    }
    assert refused
}
