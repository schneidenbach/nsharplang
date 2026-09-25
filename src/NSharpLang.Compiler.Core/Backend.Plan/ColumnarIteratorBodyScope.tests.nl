namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

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
